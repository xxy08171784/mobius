class_name TurnSystem
extends RefCounted
## 阶段推进的唯一来源。禁止 UI/按钮回调直接修改 BattleState.phase。

const ENERGY_RESOURCE: StringName = &"energy"
const MOVE_RESOURCE: StringName = &"move_points"

## 召唤落点与最近玩家的最大切比雪夫距离。
const SUMMON_RADIUS := 2

var _card_system := CardSystem.new()
var _resolver := EffectResolver.new()


func transition_to(state: BattleState, target: BattleState.Phase) -> bool:
	if state == null or state.is_terminal():
		return false
	if not _can_transition(state.phase, target):
		return false
	state.phase = target
	return true


func begin_round(
	state: BattleState,
	rng: RngStreams,
	enemy_behaviors: Dictionary
) -> Dictionary:
	if state == null or rng == null:
		return {"ok": false, "events": EventBatch.new()}
	if state.phase != BattleState.Phase.SETUP and state.phase != BattleState.Phase.ROUND_END:
		return {"ok": false, "events": EventBatch.new()}

	state.phase = BattleState.Phase.ROUND_START
	state.round_index += 1

	for unit_id: int in state.player_ids():
		var unit := state.get_unit(unit_id)
		if unit == null or not unit.is_alive():
			continue
		unit.clear_block()
		unit.set_resource(ENERGY_RESOURCE, state.energy_per_round)
		# 移动限制状态：减速每层 -1 移动力；缠绕直接锁死（第二幕泥俑/蜘蛛，见 StatusRules）。
		var move_budget := state.move_points_per_round
		if StatusRules.move_locked(unit):
			move_budget = 0
		else:
			move_budget = maxi(0, move_budget - StatusRules.move_penalty(unit))
		unit.set_resource(MOVE_RESOURCE, move_budget)

	var need := maxi(0, state.hand_size - state.deck.hand.size())
	if need > 0:
		_card_system.draw_cards(state.deck, need, rng.battle_rng())
	var scheduled := _run_scheduled_round_start(state, rng)
	if not bool(scheduled.get("ok", false)):
		return {"ok": false, "events": EventBatch.new()}

	_lock_enemy_intents(state, enemy_behaviors)
	var terminal := evaluate_outcome(state)
	if terminal != BattleState.Phase.SETUP:
		state.phase = terminal
	else:
		state.phase = BattleState.Phase.PLAYER_INPUT
	return {"ok": true, "events": scheduled.get("events", EventBatch.new())}


func run_end_turn(
	state: BattleState,
	rng: RngStreams,
	enemy_behaviors: Dictionary,
	enemy_actions: Dictionary,
	summon_pool: Array = []
) -> Dictionary:
	var events := EventBatch.new()
	if state == null or rng == null or state.phase != BattleState.Phase.PLAYER_INPUT:
		return {"ok": false, "error_code": &"phase", "events": events}

	state.phase = BattleState.Phase.PLAYER_END
	var player_finish := _finish_owner_turn(state, rng, UnitState.Team.PLAYER)
	if not bool(player_finish.get("ok", false)):
		return {"ok": false, "error_code": &"status_effect", "events": EventBatch.new()}
	_append_events(events, player_finish.get("events"))
	_discard_remaining_hand(state.deck)
	var terminal := evaluate_outcome(state)
	if terminal != BattleState.Phase.SETUP:
		state.phase = terminal
		return {"ok": true, "events": events}

	state.phase = BattleState.Phase.ENEMY_ACT
	for enemy_id: int in state.enemy_ids():
		var enemy := state.get_unit(enemy_id)
		if enemy == null or not enemy.is_alive():
			continue
		enemy.clear_block()
		if StatusRules.is_stunned(enemy):
			state.enemy_steps[enemy_id] = int(state.enemy_steps.get(enemy_id, 0)) + 1
			var stunned_finish := _finish_single_owner_turn(state, rng, enemy_id)
			if not bool(stunned_finish.get("ok", false)):
				return {"ok": false, "error_code": &"status_effect", "events": EventBatch.new()}
			_append_events(events, stunned_finish.get("events"))
			continue
		var intent: IntentState = state.enemy_intents.get(enemy_id)
		var action_result := _execute_enemy_intent(
			state,
			rng,
			enemy_id,
			intent,
			enemy_behaviors,
			enemy_actions,
			summon_pool
		)
		if not bool(action_result.get("ok", false)):
			return {
				"ok": false,
				"error_code": action_result.get("error_code", &"enemy_effect"),
				"events": EventBatch.new(),
			}
		_append_events(events, action_result.get("events"))
		var enemy_finish := _finish_single_owner_turn(state, rng, enemy_id)
		if not bool(enemy_finish.get("ok", false)):
			return {"ok": false, "error_code": &"status_effect", "events": EventBatch.new()}
		_append_events(events, enemy_finish.get("events"))

		terminal = evaluate_outcome(state)
		if terminal != BattleState.Phase.SETUP:
			state.phase = terminal
			return {"ok": true, "events": events}

	state.phase = BattleState.Phase.ROUND_END
	terminal = evaluate_outcome(state)
	if terminal != BattleState.Phase.SETUP:
		state.phase = terminal
		return {"ok": true, "events": events}

	var next_round := begin_round(state, rng, enemy_behaviors)
	if not bool(next_round.get("ok", false)):
		return {"ok": false, "error_code": &"round_start", "events": EventBatch.new()}
	_append_events(events, next_round.get("events"))
	return {"ok": true, "events": events}


## 返回 SETUP 表示“尚未结束”，否则返回终态。玩家死亡优先。
func evaluate_outcome(state: BattleState) -> BattleState.Phase:
	if state.alive_player_ids().is_empty():
		return BattleState.Phase.DEFEAT
	if state.alive_enemy_ids().is_empty():
		return BattleState.Phase.VICTORY
	return BattleState.Phase.SETUP


func _lock_enemy_intents(state: BattleState, enemy_behaviors: Dictionary) -> void:
	state.enemy_intents.clear()
	var players: Array[UnitState] = []
	for player_id: int in state.alive_player_ids():
		players.append(state.get_unit(player_id))

	for enemy_id: int in state.enemy_ids():
		var enemy := state.get_unit(enemy_id)
		if enemy == null or not enemy.is_alive():
			continue
		if state.enemy_charge_intents.has(enemy_id):
			state.enemy_intents[enemy_id] = _copy_intent(state.enemy_charge_intents[enemy_id])
			continue
		var behavior: BehaviorDef = enemy_behaviors.get(enemy_id)
		var step := int(state.enemy_steps.get(enemy_id, 0))
		state.enemy_intents[enemy_id] = EnemyPlanner.plan(
			state.board,
			enemy,
			behavior,
			step,
			players
		)


func _execute_enemy_intent(
	state: BattleState,
	rng: RngStreams,
	enemy_id: int,
	intent: IntentState,
	enemy_behaviors: Dictionary,
	enemy_actions: Dictionary,
	summon_pool: Array
) -> Dictionary:
	var empty_events := EventBatch.new()
	if intent == null or intent.is_empty():
		state.enemy_steps[enemy_id] = int(state.enemy_steps.get(enemy_id, 0)) + 1
		return {"ok": true, "events": empty_events}

	var action: EnemyActionDef = enemy_actions.get(intent.action_id)
	if action == null:
		state.enemy_steps[enemy_id] = int(state.enemy_steps.get(enemy_id, 0)) + 1
		return {"ok": true, "events": empty_events}

	if action.kind == EnemyActionDef.Kind.CHARGE and action.charge_turns > 0:
		return _execute_charge(state, rng, enemy_id, intent, action)

	if action.kind == EnemyActionDef.Kind.SUMMON:
		return _execute_summon(state, rng, enemy_id, enemy_behaviors, enemy_actions, summon_pool)

	var effect_plan := _intent_to_effect_plan(state, enemy_id, intent, action, rng)
	if effect_plan.is_empty():
		state.enemy_steps[enemy_id] = int(state.enemy_steps.get(enemy_id, 0)) + 1
		return {"ok": true, "events": empty_events}

	var resolved := _resolver.resolve(state, effect_plan, rng)
	if not bool(resolved.get("ok", false)):
		if resolved.get("error_code") == EffectResolver.ERROR_TRIGGER_OVERFLOW:
			return {"ok": false, "error_code": &"trigger_overflow", "events": empty_events}
		# 锁定目标/格子被玩家行动破坏时，本次落空；不重算整轮意图。
		state.enemy_steps[enemy_id] = int(state.enemy_steps.get(enemy_id, 0)) + 1
		return {"ok": true, "events": empty_events}

	_copy_resolved_state_into(state, resolved["state_out"])
	_restore_rng_from_resolution(rng, resolved["rng_out"])
	state.enemy_steps[enemy_id] = int(state.enemy_steps.get(enemy_id, 0)) + 1
	return {"ok": true, "events": resolved["events"]}


func _execute_charge(
	state: BattleState,
	rng: RngStreams,
	enemy_id: int,
	intent: IntentState,
	action: EnemyActionDef
) -> Dictionary:
	var empty_events := EventBatch.new()
	if not state.enemy_charge_remaining.has(enemy_id):
		state.enemy_charge_remaining[enemy_id] = action.charge_turns
		state.enemy_charge_intents[enemy_id] = _copy_intent(intent)
		return {"ok": true, "events": empty_events}

	var remaining := int(state.enemy_charge_remaining[enemy_id]) - 1
	if remaining > 0:
		state.enemy_charge_remaining[enemy_id] = remaining
		return {"ok": true, "events": empty_events}

	state.enemy_charge_remaining.erase(enemy_id)
	state.enemy_charge_intents.erase(enemy_id)
	state.enemy_steps[enemy_id] = int(state.enemy_steps.get(enemy_id, 0)) + 1
	var effect_plan := _attack_plan_if_valid(state, enemy_id, intent, action, rng)
	if effect_plan.is_empty():
		return {"ok": true, "events": empty_events}
	var resolved := _resolver.resolve(state, effect_plan, rng)
	if not bool(resolved.get("ok", false)):
		if resolved.get("error_code") == EffectResolver.ERROR_TRIGGER_OVERFLOW:
			return {"ok": false, "error_code": &"trigger_overflow", "events": empty_events}
		return {"ok": true, "events": empty_events}
	_copy_resolved_state_into(state, resolved["state_out"])
	_restore_rng_from_resolution(rng, resolved["rng_out"])
	return {"ok": true, "events": resolved["events"]}


## 召唤：从预解析召唤池（EncounterBuilder 产出）在玩家附近生成一只小怪，并把其行为/行动注册进
## 会话字典（下一回合锁意图即带上 -> 召唤单位首回合即可行动）。纯规则层，不经 EffectResolver
## （效果解析器是内容无关的，拿不到 ContentDB）。池空/无落点则本回合不生成。
func _execute_summon(
	state: BattleState,
	rng: RngStreams,
	summoner_id: int,
	enemy_behaviors: Dictionary,
	enemy_actions: Dictionary,
	summon_pool: Array
) -> Dictionary:
	var empty_events := EventBatch.new()
	state.enemy_steps[summoner_id] = int(state.enemy_steps.get(summoner_id, 0)) + 1
	if summon_pool.is_empty():
		return {"ok": true, "events": empty_events}

	var stream: RandomNumberGenerator = rng.battle_rng()
	var spec: Dictionary = summon_pool[stream.randi_range(0, summon_pool.size() - 1)]
	var spawn_cell := _summon_cell(state, summoner_id, stream)
	if spawn_cell == BoardState.INVALID_CELL:
		return {"ok": true, "events": empty_events}

	var new_id := _next_unit_id(state)
	var unit := UnitState.create(
		new_id,
		StringName(String(spec.get("unit_def_id", &""))),
		UnitState.Team.ENEMY,
		maxi(1, int(spec.get("max_hp", 1)))
	)
	unit.enemy_id = StringName(String(spec.get("enemy_id", &"")))
	state.units[new_id] = unit
	state.board.place_unit(new_id, spawn_cell)
	state.enemy_steps[new_id] = 0

	var behavior: Variant = spec.get("behavior", null)
	if behavior != null:
		enemy_behaviors[new_id] = behavior
	for action_value: Variant in spec.get("actions", []):
		if action_value is EnemyActionDef:
			enemy_actions[(action_value as EnemyActionDef).id] = action_value

	var event := EffectEvent.create(
		EffectStateAccess.allocate_event_seq(state),
		&"unit_summoned",
		summoner_id,
		new_id,
		{},
		{"cell": spawn_cell},
		{"unit_id": new_id, "def_id": String(spec.get("unit_def_id", &"")), "cell": spawn_cell}
	)
	var batch := EventBatch.new()
	batch.push_back(event)
	return {"ok": true, "events": batch}


## 分配不冲突的新单位 ID 并推进全局计数器。next_uid 可能未初始化到已有单位之上（create_state 现状），
## 防御性取 max(next_uid, 已存在最大单位 ID + 1)，保证召唤生成不覆盖现有单位。
func _next_unit_id(state: BattleState) -> int:
	var max_existing := 0
	for unit_id: int in state.units:
		if unit_id > max_existing:
			max_existing = unit_id
	var base := maxi(state.next_uid, max_existing + 1)
	state.next_uid = base + 1
	return base


## 召唤落点：离最近玩家切比雪夫 ≤ SUMMON_RADIUS 的空可走格（rng 洗牌取首个）；兜底全盘空格；无则 INVALID。
func _summon_cell(state: BattleState, summoner_id: int, rng: RandomNumberGenerator) -> Vector2i:
	var board := state.board
	var player_cell := _nearest_player_cell(state, summoner_id)
	var near: Array[Vector2i] = []
	var fallback: Array[Vector2i] = []
	for y: int in range(board.rows):
		for x: int in range(board.cols):
			var cell := Vector2i(x, y)
			if board.is_occupied(cell) or not board.is_traversable(cell):
				continue
			fallback.append(cell)
			if player_cell != BoardState.INVALID_CELL and maxi(
				absi(cell.x - player_cell.x), absi(cell.y - player_cell.y)
			) <= SUMMON_RADIUS:
				near.append(cell)
	var pool := near if not near.is_empty() else fallback
	if pool.is_empty():
		return BoardState.INVALID_CELL
	_shuffle_cells(pool, rng)
	return pool[0]


## Fisher-Yates 就地洗牌（确定性来自传入 rng）。
func _shuffle_cells(cells: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cells[i]
		cells[i] = cells[j]
		cells[j] = tmp


func _intent_to_effect_plan(
	state: BattleState,
	enemy_id: int,
	intent: IntentState,
	action: EnemyActionDef,
	rng: RngStreams
) -> Dictionary:
	match action.kind:
		EnemyActionDef.Kind.ATTACK:
			return _attack_plan_with_advance(state, enemy_id, intent, action, rng)
		EnemyActionDef.Kind.DEFEND:
			var defend_effects: Array = [{
				"type_key": &"block",
				"target": enemy_id,
				"params": {"amount": _roll_block(action, rng)},
			}]
			if action.cleanse:
				defend_effects.append({
					"type_key": &"cleanse",
					"target": enemy_id,
					"params": {},
				})
			return {"context": {"source_unit_id": enemy_id}, "effects": defend_effects}
		EnemyActionDef.Kind.APPROACH:
			return _approach_plan(state, enemy_id, action)
		EnemyActionDef.Kind.DASH:
			return _dash_plan(state, enemy_id, action)
		EnemyActionDef.Kind.PULL:
			return _pull_plan(state, enemy_id, action, rng)
		_:
			return {}


func _attack_plan_if_valid(
	state: BattleState,
	enemy_id: int,
	intent: IntentState,
	action: EnemyActionDef,
	rng: RngStreams
) -> Dictionary:
	var from_cell := state.board.get_unit_cell(enemy_id)
	var effects := _attack_effects(state, enemy_id, intent, action, from_cell, rng)
	if effects.is_empty():
		return {}
	return {"context": {"source_unit_id": enemy_id}, "effects": effects}


## 先移动再出招（敌人每回合"先移动再判断能不能攻击"）：advance_steps > 0 时按当前最近玩家
## 用 plan_move（近战逼近 / 远程风筝由 action 的 range/shape/kiting 决定）走一段，命中从**移动后的格子**判定。
func _attack_plan_with_advance(
	state: BattleState,
	enemy_id: int,
	intent: IntentState,
	action: EnemyActionDef,
	rng: RngStreams
) -> Dictionary:
	var enemy := state.get_unit(enemy_id)
	var from_cell := state.board.get_unit_cell(enemy_id)
	var attack_from := from_cell
	var effects: Array = []
	if action.advance_steps > 0 and enemy != null:
		var target_cell := _nearest_player_cell(state, enemy_id)
		if target_cell != BoardState.INVALID_CELL:
			var path := EnemyPlanner.plan_move(state.board, enemy, target_cell, action.advance_steps, action)
			if path.size() >= 2:
				effects.append({
					"type_key": &"move",
					"target": {"cell": path[path.size() - 1]},
					"params": {"move_points": path.size() - 1},
				})
				attack_from = path[path.size() - 1]
	effects.append_array(_attack_effects(state, enemy_id, intent, action, attack_from, rng))
	if effects.is_empty():
		return {}
	return {"context": {"source_unit_id": enemy_id}, "effects": effects}


## 从 from_cell 判定能否命中锁定目标，产出攻击效果（damage×hit_count + 附带状态 + 可选贯穿）。
## 空 = 打不到。damage/block 支持 [min,max] 区间（执行时在战斗流掷，确定性）。
func _attack_effects(
	state: BattleState,
	enemy_id: int,
	intent: IntentState,
	action: EnemyActionDef,
	from_cell: Vector2i,
	rng: RngStreams
) -> Array:
	var effects: Array = []
	if not intent.has_target():
		return effects
	var target := state.get_unit(intent.locked_unit_id)
	if target == null or not target.is_alive():
		return effects
	var target_cell := state.board.get_unit_cell(intent.locked_unit_id)
	if from_cell == BoardState.INVALID_CELL or target_cell == BoardState.INVALID_CELL:
		return effects
	if not BoardQuery.within_range(action.range_shape, from_cell, target_cell, action.range):
		return effects
	if action.requires_los and not BoardQuery.has_line_of_sight(state.board, from_cell, target_cell):
		return effects
	var damage := _roll_damage(action, rng)
	if damage > 0:
		for _hit in maxi(1, action.hit_count):
			effects.append({
				"type_key": &"damage",
				"target": intent.locked_unit_id,
				"params": {"amount": damage},
			})
	if not action.apply_status_id.is_empty() and action.apply_status_stacks > 0:
		effects.append({
			"type_key": &"apply_status",
			"target": intent.locked_unit_id,
			"status_id": action.apply_status_id,
			"params": {
				"stacks": action.apply_status_stacks,
				"duration": maxi(1, action.apply_status_duration),
			},
		})
	# 贯穿（阴兵过境）：主目标"身后一格"若还有玩家阵营单位，追加一次同额伤害。
	if action.pierce and damage > 0:
		var behind := target_cell + Vector2i(
			signi(target_cell.x - from_cell.x),
			signi(target_cell.y - from_cell.y)
		)
		var behind_unit := state.board.get_unit_at(behind)
		if behind_unit >= 0 and behind_unit != intent.locked_unit_id:
			var behind_target := state.get_unit(behind_unit)
			if behind_target != null and behind_target.is_alive() \
					and behind_target.team == UnitState.Team.PLAYER:
				effects.append({
					"type_key": &"damage",
					"target": behind_unit,
					"params": {"amount": damage},
				})
	return effects


## APPROACH 执行：**移动在执行时按当前最近的玩家重算**（攻击/防御仍用回合开始锁定的意图，
## 满足"仅移动重算，攻击保持预告"）。plan_move 返回真实路径（含起点）；无可推进则本回合不动。
func _approach_plan(state: BattleState, enemy_id: int, action: EnemyActionDef) -> Dictionary:
	var enemy := state.get_unit(enemy_id)
	if enemy == null or not enemy.is_alive():
		return {}
	var move_steps := maxi(0, action.move_steps - StatusRules.slow_penalty(enemy))
	if move_steps <= 0:
		return {}
	var target_cell := _nearest_player_cell(state, enemy_id)
	if target_cell == BoardState.INVALID_CELL:
		return {}
	var path := EnemyPlanner.plan_move(
		state.board,
		enemy,
		target_cell,
		move_steps,
		action
	)
	if path.size() < 2:
		return {}
	return {
		"context": {"source_unit_id": enemy_id},
		"effects": [{
			"type_key": &"move",
			"target": {"cell": path[path.size() - 1]},
			"params": {"move_points": move_steps},
		}],
	}


## 当前最近的在世玩家单位 ID（曼哈顿；平手取较小 unit_id）。无则 -1。
func _nearest_player_id(state: BattleState, enemy_id: int) -> int:
	var enemy_cell := state.board.get_unit_cell(enemy_id)
	if enemy_cell == BoardState.INVALID_CELL:
		return -1
	var best_id := -1
	var best_dist := 1 << 30
	for player_id: int in state.alive_player_ids():
		var cell := state.board.get_unit_cell(player_id)
		if cell == BoardState.INVALID_CELL:
			continue
		var dist := absi(cell.x - enemy_cell.x) + absi(cell.y - enemy_cell.y)
		if dist < best_dist or (dist == best_dist and (best_id < 0 or player_id < best_id)):
			best_dist = dist
			best_id = player_id
	return best_id


## 当前最近的在世玩家格。无则 INVALID_CELL。
func _nearest_player_cell(state: BattleState, enemy_id: int) -> Vector2i:
	var player_id := _nearest_player_id(state, enemy_id)
	return BoardState.INVALID_CELL if player_id < 0 else state.board.get_unit_cell(player_id)


## DASH（横冲直撞）：朝当前最近玩家冲 up to move_steps（纯接近，不像近战那样"已能攻击就停"），
## 伤害 = damage + 移动步数 × dash_damage_per_step。
func _dash_plan(state: BattleState, enemy_id: int, action: EnemyActionDef) -> Dictionary:
	var enemy := state.get_unit(enemy_id)
	if enemy == null or not enemy.is_alive():
		return {}
	var target_id := _nearest_player_id(state, enemy_id)
	if target_id < 0:
		return {}
	var target_cell := state.board.get_unit_cell(target_id)
	var path := EnemyPlanner.plan_approach(state.board, enemy_id, target_cell, action.move_steps)
	var steps := maxi(0, path.size() - 1)
	var amount := action.damage + steps * action.dash_damage_per_step
	var effects: Array = []
	if steps > 0:
		effects.append({
			"type_key": &"move",
			"target": {"cell": path[path.size() - 1]},
			"params": {"move_points": steps},
		})
	if amount > 0:
		effects.append({
			"type_key": &"damage",
			"target": target_id,
			"params": {"amount": amount},
		})
	if effects.is_empty():
		return {}
	return {"context": {"source_unit_id": enemy_id}, "effects": effects}


## PULL（勾魂）：把最近玩家朝自己**直线拉** move_steps 格（撞墙/单位即停），
## 伤害 = damage + 实际移动步数 × dash_damage_per_step。目标须在射程内。
func _pull_plan(
	state: BattleState,
	enemy_id: int,
	action: EnemyActionDef,
	rng: RngStreams
) -> Dictionary:
	var enemy_cell := state.board.get_unit_cell(enemy_id)
	if enemy_cell == BoardState.INVALID_CELL:
		return {}
	var target_id := _nearest_player_id(state, enemy_id)
	if target_id < 0:
		return {}
	var target_cell := state.board.get_unit_cell(target_id)
	if target_cell == BoardState.INVALID_CELL:
		return {}
	if not BoardQuery.within_range(action.range_shape, enemy_cell, target_cell, action.range):
		return {}
	var path := Displacement.pull_path(state.board, target_cell, enemy_cell, action.move_steps)
	var steps := maxi(0, path.size() - 1)
	var effects: Array = []
	if steps > 0:
		effects.append({
			"type_key": &"pull",
			"target": target_id,
			"params": {"toward_cell": enemy_cell, "distance": action.move_steps},
		})
	var amount := _roll_damage(action, rng) + steps * action.dash_damage_per_step
	if amount > 0:
		effects.append({
			"type_key": &"damage",
			"target": target_id,
			"params": {"amount": amount},
		})
	if effects.is_empty():
		return {}
	return {"context": {"source_unit_id": enemy_id}, "effects": effects}


## 区间掷值（伤害）：[damage_min, damage_max] 且 max>=min 且 max>0 时在战斗流掷，否则用固定 damage。
static func _roll_damage(action: EnemyActionDef, rng: RngStreams) -> int:
	return _roll_range(action.damage_min, action.damage_max, action.damage, rng)


## 区间掷值（护盾）：DEFEND 用，规则同上。
static func _roll_block(action: EnemyActionDef, rng: RngStreams) -> int:
	return _roll_range(action.block_min, action.block_max, action.block, rng)


static func _roll_range(low: int, high: int, fallback: int, rng: RngStreams) -> int:
	if rng != null and high >= low and high > 0:
		return rng.battle_rng().randi_range(low, high)
	return fallback


func _discard_remaining_hand(deck: DeckState) -> void:
	var remaining := deck.hand.duplicate()
	for uid_value: Variant in remaining:
		_card_system.discard_from_hand(deck, int(uid_value))


func _run_scheduled_round_start(state: BattleState, rng: RngStreams) -> Dictionary:
	var events := EventBatch.new()
	var due: Array[Dictionary] = []
	var pending: Array[Dictionary] = []
	for entry: Dictionary in state.scheduled_effects:
		if int(entry.get("round", -1)) <= state.round_index:
			due.append(entry)
		else:
			pending.append(entry)
	state.scheduled_effects = pending
	for entry: Dictionary in due:
		var kind := StringName(String(entry.get("kind", "")))
		var source_id := int(entry.get("source_unit_id", -1))
		var effects: Array = []
		match kind:
			&"draw":
				effects = [{
					"type_key": &"draw",
					"params": {"count": maxi(0, int(entry.get("count", 0)))},
				}]
			&"block":
				effects = [{
					"type_key": &"block",
					"params": {"amount": maxi(0, int(entry.get("amount", 0))), "target_mode": &"source"},
				}]
			_:
				continue
		var resolved := _resolver.resolve(
			state,
			{"context": {"source_unit_id": source_id}, "effects": effects},
			rng
		)
		if not bool(resolved.get("ok", false)):
			return {"ok": false, "events": EventBatch.new()}
		_copy_resolved_state_into(state, resolved["state_out"])
		_restore_rng_from_resolution(rng, resolved["rng_out"])
		_append_events(events, resolved["events"])
	return {"ok": true, "events": events}


func _finish_owner_turn(state: BattleState, rng: RngStreams, team: UnitState.Team) -> Dictionary:
	var events := EventBatch.new()
	var ids := state.player_ids() if team == UnitState.Team.PLAYER else state.enemy_ids()
	for unit_id: int in ids:
		var result := _finish_single_owner_turn(state, rng, unit_id)
		if not bool(result.get("ok", false)):
			return {"ok": false, "events": EventBatch.new()}
		_append_events(events, result.get("events"))
	return {"ok": true, "events": events}


func _finish_single_owner_turn(state: BattleState, rng: RngStreams, unit_id: int) -> Dictionary:
	var events := EventBatch.new()
	var unit := state.get_unit(unit_id)
	if unit == null:
		return {"ok": true, "events": events}

	# 回合结束 DoT（流血/中毒）：逐状态结算，层数即伤害（忽略加成，§6 取整前）。
	# 中毒无视护甲（不吃盾，§8）且按层数递减；流血吃盾、按持续递减。
	for dot_id: StringName in StatusRules.DOT_STATUSES:
		if not unit.is_alive():
			break
		var dot_damage := StatusRules.dot_tick_damage(dot_id, StatusRules.stacks(unit, dot_id))
		if dot_damage <= 0:
			continue
		var resolved := _resolver.resolve(
			state,
			{
				"context": {"source_unit_id": -1},
				"effects": [{
					"type_key": &"damage",
					"target": unit_id,
					"params": {
						"amount": dot_damage,
						"ignore_status_modifiers": true,
						"ignore_block": StatusRules.is_armor_ignoring(dot_id),
						"status_id": dot_id,
					},
				}],
			},
			rng
		)
		if not bool(resolved.get("ok", false)):
			return {"ok": false, "events": EventBatch.new()}
		_copy_resolved_state_into(state, resolved["state_out"])
		_restore_rng_from_resolution(rng, resolved["rng_out"])
		_append_events(events, resolved["events"])
		unit = state.get_unit(unit_id)
		if StatusRules.is_stack_decaying(dot_id):
			StatusRules.decay_stacks(unit, dot_id)

	var expired: Array[int] = []
	for instance_id: int in unit.status_ids():
		var status := unit.get_status(instance_id)
		# 层数驱动的状态不吃持续递减（由层数决定寿命）。
		if not StatusRules.is_stack_decaying(status.status_id):
			status.decrease_duration()
		if status.is_expired():
			expired.append(instance_id)
	for instance_id: int in expired:
		unit.remove_status(instance_id)
	return {"ok": true, "events": events}


func _copy_resolved_state_into(target: BattleState, source: BattleState) -> void:
	target.board = source.board
	target.units = source.units
	target.deck = source.deck
	target.scheduled_effects = source.scheduled_effects
	target.ground_items = source.ground_items
	target.collected_items = source.collected_items
	target.run_changes = source.run_changes
	target.next_uid = source.next_uid
	target.next_event_seq = source.next_event_seq
	target.enemy_intents = source.enemy_intents
	target.enemy_steps = source.enemy_steps
	target.enemy_charge_remaining = source.enemy_charge_remaining
	target.enemy_charge_intents = source.enemy_charge_intents


func _restore_rng_from_resolution(target: RngStreams, resolved_rng: Variant) -> void:
	if resolved_rng is RngStreams:
		target.restore((resolved_rng as RngStreams).snapshot())


func _append_events(destination: EventBatch, source: Variant) -> void:
	if not source is EventBatch:
		return
	for event: GameEvent in (source as EventBatch).events:
		destination.push_back(event)


func _copy_intent(source: IntentState) -> IntentState:
	var copy := IntentState.new()
	copy.action_id = source.action_id
	copy.actor_id = source.actor_id
	copy.target_policy = source.target_policy
	copy.locked_unit_id = source.locked_unit_id
	copy.locked_cell = source.locked_cell
	copy.affected_cells = source.affected_cells.duplicate()
	copy.magnitude = source.magnitude
	copy.is_fallback = source.is_fallback
	return copy


func _can_transition(from: BattleState.Phase, to: BattleState.Phase) -> bool:
	match from:
		BattleState.Phase.SETUP:
			return to == BattleState.Phase.ROUND_START
		BattleState.Phase.ROUND_START:
			return to == BattleState.Phase.PLAYER_INPUT or to == BattleState.Phase.VICTORY or to == BattleState.Phase.DEFEAT
		BattleState.Phase.PLAYER_INPUT:
			return to == BattleState.Phase.RESOLVING or to == BattleState.Phase.PLAYER_END
		BattleState.Phase.RESOLVING:
			return to == BattleState.Phase.PLAYER_INPUT or to == BattleState.Phase.VICTORY or to == BattleState.Phase.DEFEAT
		BattleState.Phase.PLAYER_END:
			return to == BattleState.Phase.ENEMY_ACT or to == BattleState.Phase.VICTORY or to == BattleState.Phase.DEFEAT
		BattleState.Phase.ENEMY_ACT:
			return to == BattleState.Phase.ROUND_END or to == BattleState.Phase.VICTORY or to == BattleState.Phase.DEFEAT
		BattleState.Phase.ROUND_END:
			return to == BattleState.Phase.ROUND_START or to == BattleState.Phase.VICTORY or to == BattleState.Phase.DEFEAT
		_:
			return false
