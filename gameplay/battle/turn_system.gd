class_name TurnSystem
extends RefCounted
## 阶段推进的唯一来源。禁止 UI/按钮回调直接修改 BattleState.phase。

const ENERGY_RESOURCE: StringName = &"energy"
const MOVE_RESOURCE: StringName = &"move_points"

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
		unit.set_resource(MOVE_RESOURCE, state.move_points_per_round)

	var need := maxi(0, state.hand_size - state.deck.hand.size())
	if need > 0:
		_card_system.draw_cards(state.deck, need, rng.battle_rng())

	_lock_enemy_intents(state, enemy_behaviors)
	var terminal := evaluate_outcome(state)
	if terminal != BattleState.Phase.SETUP:
		state.phase = terminal
	else:
		state.phase = BattleState.Phase.PLAYER_INPUT
	return {"ok": true, "events": EventBatch.new()}


func run_end_turn(
	state: BattleState,
	rng: RngStreams,
	enemy_behaviors: Dictionary,
	enemy_actions: Dictionary
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
		var intent: IntentState = state.enemy_intents.get(enemy_id)
		var action_result := _execute_enemy_intent(
			state,
			rng,
			enemy_id,
			intent,
			enemy_actions
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
	enemy_actions: Dictionary
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

	var effect_plan := _intent_to_effect_plan(state, enemy_id, intent, action)
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
	var effect_plan := _attack_plan_if_valid(state, enemy_id, intent, action)
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


func _intent_to_effect_plan(
	state: BattleState,
	enemy_id: int,
	intent: IntentState,
	action: EnemyActionDef
) -> Dictionary:
	match action.kind:
		EnemyActionDef.Kind.ATTACK:
			return _attack_plan_if_valid(state, enemy_id, intent, action)
		EnemyActionDef.Kind.DEFEND:
			return {
				"context": {"source_unit_id": enemy_id},
				"effects": [{
					"type_key": &"block",
					"target": enemy_id,
					"params": {"amount": action.block},
				}],
			}
		EnemyActionDef.Kind.APPROACH:
			if not intent.has_locked_cell():
				return {}
			return {
				"context": {"source_unit_id": enemy_id},
				"effects": [{
					"type_key": &"move",
					"target": {"cell": intent.locked_cell},
					"params": {"move_points": action.move_steps},
				}],
			}
		_:
			return {}


func _attack_plan_if_valid(
	state: BattleState,
	enemy_id: int,
	intent: IntentState,
	action: EnemyActionDef
) -> Dictionary:
	if not intent.has_target():
		return {}
	var target := state.get_unit(intent.locked_unit_id)
	if target == null or not target.is_alive():
		return {}
	var from_cell := state.board.get_unit_cell(enemy_id)
	var target_cell := state.board.get_unit_cell(intent.locked_unit_id)
	if from_cell == BoardState.INVALID_CELL or target_cell == BoardState.INVALID_CELL:
		return {}
	var distance := absi(target_cell.x - from_cell.x) + absi(target_cell.y - from_cell.y)
	if distance > action.range:
		return {}
	if action.requires_los and not BoardQuery.has_line_of_sight(state.board, from_cell, target_cell):
		return {}
	return {
		"context": {"source_unit_id": enemy_id},
		"effects": [{
			"type_key": &"damage",
			"target": intent.locked_unit_id,
			"params": {"amount": action.damage},
		}],
	}


func _discard_remaining_hand(deck: DeckState) -> void:
	var remaining := deck.hand.duplicate()
	for uid_value: Variant in remaining:
		_card_system.discard_from_hand(deck, int(uid_value))


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

	var bleed_damage := StatusRules.owner_turn_end_damage(unit)
	if unit.is_alive() and bleed_damage > 0:
		var resolved := _resolver.resolve(
			state,
			{
				"context": {"source_unit_id": -1},
				"effects": [{
					"type_key": &"damage",
					"target": unit_id,
					"params": {
						"amount": bleed_damage,
						"ignore_status_modifiers": true,
						"status_id": StatusRules.BLEED,
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

	var expired: Array[int] = []
	for instance_id: int in unit.status_ids():
		var status := unit.get_status(instance_id)
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
