class_name RunSession
extends RefCounted
## 一局游玩的规则协调器：唯一节点入口 `enter_node()`，战斗进/出经 EncounterBuilder / BattleResult。
## 与 BattleSession 同构：在工作快照上结算，成功才一次性提交；失败零副作用、不推进正式 RNG。
##
## 可无头测试：content / save_service 以“鸭子对象”注入（游戏里传 ContentDB / SaveService autoload）。

## 地图节点类型 -> 转移 kind（去掉 "node." 前缀）。
const KIND_BATTLE := &"battle"
const KIND_ACT_COMPLETE := &"act_complete"
const KIND_RUN_COMPLETE := &"run_complete"
const KIND_DEFEAT := &"defeat"

const CAMPAIGN_PATH := "res://content/maps/campaign_default.tres"

signal state_changed(run: RunState)
signal save_failed(message: String)

var last_save_ok: bool = true
var state: RunState = null

var _rng: RngStreams = null
var _content: Object = null
var _save_service: Object = null
var _campaign: CampaignDef = null
var _encounters := EncounterSelector.new()


## 装配一局：恢复 RNG、绑定内容与存档门面。campaign 缺省从 CAMPAIGN_PATH 读取。
func setup(
	run_state: RunState,
	content: Object,
	campaign: CampaignDef = null,
	save_service: Object = null
) -> void:
	state = run_state
	_content = content
	_encounters.setup(content)
	_save_service = save_service
	_campaign = campaign if campaign != null else _default_campaign()
	_rng = RngStreams.new()
	if state != null and not state.rng_snapshot.is_empty():
		_rng.restore(state.rng_snapshot)
	elif state != null:
		_rng.derive_streams(state.seed)


## 静态工厂：从角色 + 种子生成一份确定的初始 RunState（不依赖场景）。
static func create_run(
	character_id: StringName,
	seed_text: String,
	content: Object,
	campaign: CampaignDef = null
) -> RunState:
	if content == null:
		push_error("RunSession.create_run: content is null")
		return null
	var character: CharacterDef = content.get_character(character_id)
	if character == null:
		push_error("RunSession.create_run: unknown character: %s" % String(character_id))
		return null
	var unit_def: UnitDef = content.get_unit(character.unit_def_id)
	if unit_def == null:
		push_error("RunSession.create_run: unknown unit: %s" % String(character.unit_def_id))
		return null

	var camp := campaign if campaign != null else load(CAMPAIGN_PATH) as CampaignDef
	var rng := RngStreams.new()
	rng.derive_streams(seed_text)

	var run := RunState.new()
	run.run_id = absi(seed_text.hash())
	run.seed = seed_text
	run.character_id = character_id
	run.act_index = 0
	run.max_hp = unit_def.base_stat(StatSystem.STAT_MAX_HP)
	run.hp = run.max_hp
	run.gold = 99
	for card_id: StringName in character.starter_deck:
		run.add_card(card_id)
	for relic_id: StringName in character.starter_relics:
		run.add_relic(relic_id)
	run.map = MapGenerator.generate(camp.act_def(0), rng.get_stream(&"route"))
	run.rng_snapshot = rng.snapshot()
	return run


## 当前地图上可进入的节点 ID（升序）。StS 式：初始为入口，之后为当前节点的后继。
func available_node_ids() -> Array[int]:
	var ids: Array[int] = []
	if state == null or state.map == null:
		return ids
	for id: int in state.map.nodes:
		if state.can_enter(id):
			ids.append(id)
	ids.sort()
	return ids


func can_enter(node_id: int) -> bool:
	return state != null and state.can_enter(node_id)


## 该节点是否战斗节点（monster/elite/boss）。纯查询，无副作用；表现层据此决定先选进场格。
func is_battle_node(node_id: int) -> bool:
	if state == null or state.map == null:
		return false
	var node: MapNodeState = state.map.get_node(node_id)
	if node == null:
		return false
	return node.type_key == RouteMapDef.TYPE_MONSTER \
		or node.type_key == RouteMapDef.TYPE_ELITE \
		or node.type_key == RouteMapDef.TYPE_BOSS


## 部署预览：在 RNG 克隆上解析该战斗节点，返回棋盘尺寸与敌人落点（**不提交、不推进正式 RNG**）。
## 敌人落点不依赖玩家起点（见 EncounterBuilder._plan_enemy_spawns），故与随后 enter_node 同 seed 同结果。
func preview_battle(node_id: int) -> Dictionary:
	if state == null or state.map == null:
		return {}
	var node: MapNodeState = state.map.get_node(node_id)
	if node == null:
		return {}
	var work := state.duplicate_state()
	var work_rng := _rng.clone()
	var transition := _resolve_node(work, work_rng, node, Vector2i.ZERO)
	if not bool(transition.get("ok", false)):
		return {}
	var battle_state: BattleState = (transition.get("battle", {}) as Dictionary).get("state", null)
	if battle_state == null:
		return {}
	var cells: Array[Vector2i] = []
	for enemy_id: int in battle_state.enemy_ids():
		cells.append(battle_state.board.get_unit_cell(enemy_id))
	return {
		"cols": battle_state.board.cols,
		"rows": battle_state.board.rows,
		"enemy_cells": cells,
	}


## 进入节点。成功返回转移 dict：
##   battle        -> { kind, encounter_id, battle: <EncounterBuilder.build 结果> }
##   rest/shop/... -> { kind, content_id }
## player_start：战斗节点时表现层传玩家选定的进场格；非法格由 EncounterBuilder 回退。
## 失败返回 { ok:false, error_code }，零副作用。
func enter_node(node_id: int, player_start: Vector2i = Vector2i(-1, -1)) -> Dictionary:
	if state == null or state.map == null:
		return _fail(&"run_not_ready")
	var node: MapNodeState = state.map.get_node(node_id)
	if node == null:
		return _fail(&"unknown_node")
	if state.flow_phase == &"deployment" and state.pending_node_id == node_id:
		pass
	elif not state.can_enter(node_id):
		return _fail(&"node_locked")

	# 工作快照上结算，成功才提交。
	var work := state.duplicate_state()
	var work_rng := _rng.clone()
	var transition := _resolve_node(work, work_rng, node, player_start)
	if not bool(transition.get("ok", false)):
		return transition

	work.map.enter(node_id, work.current_node_id)
	work.current_node_id = node_id
	work.map.get_node(node_id).content_id = StringName(String(transition.get("content_id", "")))
	if StringName(String(transition.get("kind", ""))) == KIND_BATTLE:
		work.next_battle_id += 1
	work.flow_phase = StringName(transition.get("kind", "route"))
	work.pending_node_id = node_id
	work.pending_content_id = StringName(transition.get("content_id", ""))
	work.pending_payload = {}
	if work.flow_phase == KIND_BATTLE:
		var battle: Dictionary = transition["battle"]
		work.pending_battle_id = (battle["state"] as BattleState).battle_id
		work.pending_payload = BattleCheckpoint.capture(battle)
	elif work.flow_phase == &"shop":
		work.pending_payload["shop"] = (transition["shop"] as ShopState).to_dict()
	elif work.flow_phase == &"treasure":
		work.pending_payload = {"relic_id": transition["relic_id"], "gold": transition["gold"]}
	_commit(work, work_rng)
	transition["saved"] = last_save_ok
	return transition


## 战斗结束：把 BattleResult 的持久变化写回 RunState；Boss 胜利推进章节。
func on_battle_finished(result: BattleResult) -> Dictionary:
	if state == null or result == null:
		return _fail(&"run_not_ready")
	if result.run_instance_id != state.instance_id:
		return _fail(&"run_id_mismatch")
	if state.settled_battle_ids.has(result.battle_id):
		return _fail(&"battle_already_settled")
	if state.flow_phase != KIND_BATTLE or result.battle_id != state.pending_battle_id:
		return _fail(&"battle_id_mismatch")
	var work := state.duplicate_state()
	var rng := _rng.clone()
	if not result.rng_snapshot.is_empty():
		rng.restore(result.rng_snapshot)
	work.max_hp = maxi(1, work.max_hp + int(result.persistent_changes.get("max_hp_delta", 0)))
	var hp_map: Dictionary = result.persistent_changes.get("player_hp", {})
	work.hp = clampi(int(hp_map.get(EncounterBuilder.PLAYER_UNIT_ID, work.hp)), 0, work.max_hp)
	work.settled_battle_ids.append(result.battle_id)
	var kind: StringName = &"victory"
	if not result.victory or work.hp <= 0:
		work.hp = 0
		work.clear_pending()
		work.flow_phase = &"run_over"
		work.outcome = KIND_DEFEAT
		kind = KIND_DEFEAT
	else:
		work.gold += RewardSystem.GOLD_REWARD
		RelicSystem.on_victory(work, _content)
		var node := work.map.get_node(work.current_node_id)
		if node != null and node.type_key == RouteMapDef.TYPE_BOSS:
			# 每幕 Boss 胜利恢复已损失生命的 80%，向上取整；与胜利同一事务，重复回调不重复回血。
			var missing_hp := maxi(0, work.max_hp - work.hp)
			work.hp = mini(work.max_hp, work.hp + ceili(missing_hp * 0.8))
			kind = _advance_act(work, rng)["kind"]
		if kind == KIND_RUN_COMPLETE:
			work.clear_pending()
			work.flow_phase = &"run_over"
			work.outcome = KIND_RUN_COMPLETE
		else:
			var reward := RewardSystem.generate(_content.reward_card_ids(), rng.get_stream(&"reward"))
			reward.battle_id = result.battle_id
			work.flow_phase = &"reward"
			work.pending_payload = {"reward": reward.to_dict()}
	_commit(work, rng)
	return {"ok": true, "kind": kind, "saved": last_save_ok}


func current_node() -> MapNodeState:
	if state == null or state.current_node_id < 0:
		return null
	return state.map.get_node(state.current_node_id)


## 节点内变更（休息/商店/事件）后手动存档。
func save() -> bool:
	return _autosave()


## 奖励只在胜利事务中抽取。显示或重新读档不消费 RNG。
func generate_reward() -> RewardState:
	if state == null or state.flow_phase != &"reward":
		return null
	return RewardState.from_dict(state.pending_payload.get("reward", {}))


func claim_reward(reward: RewardState, index: int) -> Dictionary:
	var pending := generate_reward()
	if pending == null or reward == null or reward.battle_id != pending.battle_id or reward.offers != pending.offers:
		return _fail(&"reward_not_pending")
	var work := state.duplicate_state()
	var result := RewardSystem.claim(work, pending, index)
	if bool(result.get("ok", false)):
		work.clear_pending()
		_commit(work, _rng.clone())
		reward.claimed = true
	return result


func begin_deployment(node_id: int) -> Dictionary:
	if not can_enter(node_id) or not is_battle_node(node_id):
		return _fail(&"node_locked")
	var preview := preview_battle(node_id)
	if preview.is_empty():
		return _fail(&"encounter_build")
	var work := state.duplicate_state()
	work.flow_phase = &"deployment"
	work.pending_node_id = node_id
	work.pending_payload = {"preview": preview}
	_commit(work, _rng.clone())
	return {"ok": true, "kind": &"deployment", "preview": preview}


func cancel_deployment() -> bool:
	if state == null or state.flow_phase != &"deployment":
		return false
	var work := state.duplicate_state()
	work.clear_pending()
	_commit(work, _rng.clone())
	return true


func checkpoint_battle(battle: BattleState) -> bool:
	if state == null or state.flow_phase != KIND_BATTLE or battle == null or battle.battle_id != state.pending_battle_id:
		return false
	if battle.run_instance_id != state.instance_id:
		return false
	var previous := SaveCodec.new().decode_state(state.pending_payload.get("battle", {})) as BattleState
	if previous != null and previous.version > battle.version:
		return false
	var work := state.duplicate_state()
	work.pending_payload["battle"] = SaveCodec.new().encode_state(battle)
	var rng := RngStreams.new()
	rng.restore(battle.rng_snapshot)
	_commit(work, rng)
	return last_save_ok


func resolve_node_action(action: StringName, data: Dictionary = {}) -> Dictionary:
	if state == null:
		return _fail(&"run_not_ready")
	var work := state.duplicate_state()
	var result := RunNodeTransaction.apply(work, _content, action, data)
	if bool(result.get("ok", false)):
		_commit(work, _rng.clone())
	return result


func resume_pending_flow() -> Dictionary:
	if state == null:
		return _fail(&"run_not_ready")
	var out := {"ok": true, "kind": state.flow_phase, "content_id": state.pending_content_id}
	match state.flow_phase:
		&"battle":
			out["battle"] = BattleCheckpoint.restore(state.pending_payload, _content)
			if (out["battle"] as Dictionary).is_empty():
				return _fail(&"battle_content_missing")
		&"deployment":
			out["preview"] = state.pending_payload.get("preview", {})
		&"shop":
			out["shop"] = ShopState.from_dict(state.pending_payload.get("shop", {}))
		&"treasure":
			out.merge(state.pending_payload)
		&"run_over":
			out["kind"] = state.outcome
	return out


func _commit(work: RunState, rng: RngStreams) -> void:
	work.rng_snapshot = rng.snapshot()
	state = work
	_rng = rng
	state_changed.emit(state)
	_autosave()


## 只读 state，产出转移；战斗 build 用当前 next_battle_id（提交时由 enter_node 推进）。
func _resolve_node(
	work: RunState,
	rng: RngStreams,
	node: MapNodeState,
	player_start: Vector2i
) -> Dictionary:
	match node.type_key:
		RouteMapDef.TYPE_MONSTER, RouteMapDef.TYPE_ELITE, RouteMapDef.TYPE_BOSS:
			return _encounters.resolve(work, rng, node.type_key, player_start)
		RouteMapDef.TYPE_REST:
			return {"ok": true, "error_code": &"ok", "kind": &"rest", "content_id": &""}
		RouteMapDef.TYPE_SHOP:
			var shop_id := _pick_content(&"shop", rng)
			if shop_id.is_empty():
				return _fail(&"no_shop")
			var shop_def: ShopDef = _content.get_shop(shop_id)
			if shop_def == null:
				return _fail(&"no_shop")
			var shop_state := ShopSystem.generate(shop_def, rng.get_stream(&"encounter"), _content)
			return {
				"ok": true,
				"error_code": &"ok",
				"kind": &"shop",
				"content_id": shop_id,
				"shop": shop_state,
			}
		RouteMapDef.TYPE_TREASURE:
			var relic_id := _pick_content(&"relic", rng)
			if relic_id.is_empty():
				return _fail(&"no_relic")
			var reward := TreasureSystem.claim(work, relic_id)
			if not bool(reward.get("ok", false)):
				return _fail(&"treasure")
			return {
				"ok": true,
				"error_code": &"ok",
				"kind": &"treasure",
				"content_id": relic_id,
				"relic_id": relic_id,
				"gold": int(reward.get("gold", 0)),
			}
		RouteMapDef.TYPE_EVENT:
			var event_id := _pick_content(&"event", rng)
			if event_id.is_empty():
				return _fail(&"no_event")
			return {"ok": true, "error_code": &"ok", "kind": &"event", "content_id": event_id}
		_:
			return {
				"ok": true,
				"error_code": &"ok",
				"kind": _kind_of(node.type_key),
				"content_id": node.content_id,
			}


## 按 kind 从 ContentDB 确定性抽一个内容 ID（shop / event / relic）。单一候选不抽签（不推进）。
func _pick_content(kind: StringName, rng: RngStreams) -> StringName:
	var ids: Array
	match kind:
		&"shop":
			ids = _content.shop_ids()
		&"relic":
			ids = _content.relic_ids()
		_:
			ids = _content.event_ids()
	var candidates: Array[StringName] = []
	for id_value: Variant in ids:
		if kind == &"relic":
			var relic: RelicDef = _content.get_relic(StringName(String(id_value)))
			if relic == null or not relic.enabled:
				continue
		candidates.append(StringName(String(id_value)))
	if candidates.is_empty():
		return &""
	if candidates.size() == 1:
		return candidates[0]
	var stream: RandomNumberGenerator = rng.get_stream(&"encounter")
	return candidates[stream.randi_range(0, candidates.size() - 1)]


func _advance_act(work: RunState, rng: RngStreams) -> Dictionary:
	var next_index := work.act_index + 1
	if next_index >= _campaign.act_count():
		return {"ok": true, "error_code": &"ok", "kind": KIND_RUN_COMPLETE}
	work.act_index = next_index
	work.current_node_id = -1
	work.map = MapGenerator.generate(_campaign.act_def(next_index), rng.get_stream(&"route"))
	work.rng_snapshot = rng.snapshot()
	return {"ok": true, "error_code": &"ok", "kind": KIND_ACT_COMPLETE, "act_index": next_index}


func _autosave() -> bool:
	last_save_ok = true
	if _save_service != null and _save_service.has_method("save_run"):
		last_save_ok = bool(_save_service.call("save_run", state))
	if not last_save_ok:
		save_failed.emit("保存失败；当前进度仍在内存中。请释放磁盘空间后点击重试，成功前不要退出。")
	return last_save_ok


func _default_campaign() -> CampaignDef:
	if ResourceLoader.exists(CAMPAIGN_PATH):
		var loaded := load(CAMPAIGN_PATH)
		if loaded is CampaignDef:
			return loaded as CampaignDef
	return CampaignDef.new()


static func _kind_of(type_key: StringName) -> StringName:
	var text := String(type_key)
	if text.begins_with("node."):
		return StringName(text.substr(5))
	return type_key


static func _fail(code: StringName) -> Dictionary:
	return {"ok": false, "error_code": code}
