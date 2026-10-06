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

var state: RunState = null

var _rng: RngStreams = null
var _content: Object = null
var _save_service: Object = null
var _campaign: CampaignDef = null


## 装配一局：恢复 RNG、绑定内容与存档门面。campaign 缺省从 CAMPAIGN_PATH 读取。
func setup(
	run_state: RunState,
	content: Object,
	campaign: CampaignDef = null,
	save_service: Object = null
) -> void:
	state = run_state
	_content = content
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

	var camp := campaign if campaign != null else CampaignDef.new()
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
	var transition := _resolve_node(work, work_rng, node, Vector2i(-1, -1))
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
	if not state.can_enter(node_id):
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
	work.rng_snapshot = work_rng.snapshot()

	state = work
	_rng = work_rng
	_autosave()
	return transition


## 战斗结束：把 BattleResult 的持久变化写回 RunState；Boss 胜利推进章节。
func on_battle_finished(result: BattleResult) -> Dictionary:
	if state == null or result == null:
		return _fail(&"run_not_ready")

	var max_hp_delta := int(result.persistent_changes.get("max_hp_delta", 0))
	if max_hp_delta != 0:
		state.max_hp = maxi(1, state.max_hp + max_hp_delta)
	var hp_map: Dictionary = result.persistent_changes.get("player_hp", {})
	if hp_map.has(EncounterBuilder.PLAYER_UNIT_ID):
		state.hp = clampi(int(hp_map[EncounterBuilder.PLAYER_UNIT_ID]), 0, state.max_hp)

	if not result.victory or state.hp <= 0:
		state.hp = maxi(0, state.hp)
		_autosave()
		return {"ok": true, "error_code": &"ok", "kind": KIND_DEFEAT}

	state.gold += RewardSystem.GOLD_REWARD

	var node := state.map.get_node(state.current_node_id) if state.current_node_id >= 0 else null
	if node != null and node.type_key == RouteMapDef.TYPE_BOSS:
		var advanced := _advance_act(state, _rng)
		_autosave()
		return advanced

	_autosave()
	return {"ok": true, "error_code": &"ok", "kind": &"victory"}


func current_node() -> MapNodeState:
	if state == null or state.current_node_id < 0:
		return null
	return state.map.get_node(state.current_node_id)


## 节点内变更（休息/商店/事件）后手动存档。
func save() -> void:
	_autosave()


## 战败/通关后生成三选一奖励（用 reward 流，确定性；推进正式 RNG）。
func generate_reward() -> RewardState:
	if state == null or _rng == null:
		return null
	return RewardSystem.generate(_content.reward_card_ids(), _rng.get_stream(&"reward"))


## 领取（index>=0）或放弃（index<0）。成功后自动存档。
func claim_reward(reward: RewardState, index: int) -> Dictionary:
	var result := RewardSystem.claim(state, reward, index)
	if bool(result.get("ok", false)):
		_autosave()
	return result


## 只读 state，产出转移；战斗 build 用当前 next_battle_id（提交时由 enter_node 推进）。
func _resolve_node(
	work: RunState,
	rng: RngStreams,
	node: MapNodeState,
	player_start: Vector2i
) -> Dictionary:
	match node.type_key:
		RouteMapDef.TYPE_MONSTER:
			var pooled := _resolve_monster_pool(work, rng, player_start)
			if not pooled.is_empty():
				return pooled
			return _resolve_fixed_encounter(work, rng, player_start, &"monster")
		RouteMapDef.TYPE_ELITE:
			var elite := _resolve_elite_encounter(work, rng, player_start)
			if not elite.is_empty():
				return elite
			return _resolve_fixed_encounter(work, rng, player_start, &"elite")
		RouteMapDef.TYPE_BOSS:
			var boss := _resolve_boss_encounter(work, rng, player_start)
			if not boss.is_empty():
				return boss
			return _resolve_fixed_encounter(work, rng, player_start, &"boss")
		RouteMapDef.TYPE_REST:
			return {"ok": true, "error_code": &"ok", "kind": &"rest", "content_id": &""}
		RouteMapDef.TYPE_SHOP:
			var shop_id := _pick_content(&"shop", rng)
			if shop_id.is_empty():
				return _fail(&"no_shop")
			var shop_def: ShopDef = _content.get_shop(shop_id)
			if shop_def == null:
				return _fail(&"no_shop")
			var shop_state := ShopSystem.generate(shop_def, rng.get_stream(&"encounter"))
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


## 本幕怪物池：按 battle_index（= next_battle_id，当前战斗的 1 起序号）抽 2~4 只（前 2 战固定 2）。
## 无池 / content 不支持池时返回空 dict，调用方回退到固定 EncounterDef。
func _resolve_monster_pool(work: RunState, rng: RngStreams, player_start: Vector2i) -> Dictionary:
	if _content == null or not _content.has_method("get_monster_pool"):
		return {}
	var pool: MonsterPoolDef = _content.get_monster_pool(StringName("monster_pool.act%d" % (work.act_index + 1)))
	if pool == null:
		return {}
	var encounter := MonsterPool.build_encounter(pool, work.next_battle_id, rng.get_stream(&"encounter"))
	if encounter == null:
		return _fail(&"monster_pool_empty")
	var battle := EncounterBuilder.build(encounter, work, rng, _content, player_start)
	if battle.is_empty():
		return _fail(&"encounter_build")
	return {
		"ok": true,
		"error_code": &"ok",
		"kind": KIND_BATTLE,
		"content_id": encounter.id,
		"encounter_id": encounter.id,
		"battle": battle,
	}


## 固定遭遇：按 tier 抽一个 EncounterDef（elite/boss 与 monster 回退共用）。
func _resolve_fixed_encounter(work: RunState, rng: RngStreams, player_start: Vector2i, tier: StringName) -> Dictionary:
	var encounter_id := _pick_encounter(rng, tier)
	if encounter_id.is_empty():
		return _fail(&"no_encounter")
	var encounter: EncounterDef = _content.get_encounter(encounter_id)
	var battle := EncounterBuilder.build(encounter, work, rng, _content, player_start)
	if battle.is_empty():
		return _fail(&"encounter_build")
	return {
		"ok": true,
		"error_code": &"ok",
		"kind": KIND_BATTLE,
		"content_id": encounter_id,
		"encounter_id": encounter_id,
		"battle": battle,
	}


## 本幕精英战：1 精英（精英池随机）+ 2 小怪（小怪池有放回）。无池返回空 dict 以回退。
func _resolve_elite_encounter(work: RunState, rng: RngStreams, player_start: Vector2i) -> Dictionary:
	if _content == null or not _content.has_method("get_monster_pool"):
		return {}
	var act := work.act_index + 1
	var elite_pool: MonsterPoolDef = _content.get_monster_pool(StringName("monster_pool.act%d_elite" % act))
	var mob_pool: MonsterPoolDef = _content.get_monster_pool(StringName("monster_pool.act%d" % act))
	if elite_pool == null or mob_pool == null:
		return {}
	var encounter := MonsterPool.build_elite_encounter(
		elite_pool, mob_pool, work.next_battle_id, rng.get_stream(&"encounter")
	)
	if encounter == null:
		return _fail(&"monster_pool_empty")
	return _battle_transition(encounter, work, rng, player_start)


## 本幕 Boss：直接取墓外 Boss 遭遇。无则返回空 dict（回退固定遭遇）。
func _resolve_boss_encounter(work: RunState, rng: RngStreams, player_start: Vector2i) -> Dictionary:
	if _content == null or not _content.has_method("get_encounter"):
		return {}
	var encounter: EncounterDef = _content.get_encounter(StringName("encounter.boss.act%d" % (work.act_index + 1)))
	if encounter == null:
		return {}
	return _battle_transition(encounter, work, rng, player_start)


## 装配一场战斗的转移 dict（供池/精英/Boss 共用）。
func _battle_transition(encounter: EncounterDef, work: RunState, rng: RngStreams, player_start: Vector2i) -> Dictionary:
	var battle := EncounterBuilder.build(encounter, work, rng, _content, player_start)
	if battle.is_empty():
		return _fail(&"encounter_build")
	return {
		"ok": true,
		"error_code": &"ok",
		"kind": KIND_BATTLE,
		"content_id": encounter.id,
		"encounter_id": encounter.id,
		"battle": battle,
	}


## 按 tier 确定性抽一个遭遇（encounter 流）。空 = 无可用遭遇。
func _pick_encounter(rng: RngStreams, tier: StringName) -> StringName:
	var candidates: Array[StringName] = []
	for id_value: Variant in _content.encounter_ids():
		var id := StringName(String(id_value))
		var encounter: EncounterDef = _content.get_encounter(id)
		if encounter != null and encounter.tier == tier:
			candidates.append(id)
	if candidates.is_empty():
		return &""
	var stream: RandomNumberGenerator = rng.get_stream(&"encounter")
	return candidates[stream.randi_range(0, candidates.size() - 1)]


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


func _autosave() -> void:
	if _save_service != null and _save_service.has_method("save_run"):
		_save_service.call("save_run", state)


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
