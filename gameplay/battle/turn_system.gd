class_name TurnSystem
extends EnemyTurnExecutor
## 回合流程门面：生命周期编排；敌人、状态 tick、延迟效果和终局判定分别独立。
var _status_ticks := StatusTickSystem.new()
var _round_effects := RoundEffectSystem.new()


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

	RelicSystem.trigger(state, &"round_start")
	if state.round_index == 1:
		RelicSystem.trigger(state, &"battle_start")
	var need := maxi(0, state.hand_size - state.deck.hand.size())
	if need > 0:
		_card_system.draw_cards(state.deck, need, rng.battle_rng())
	var scheduled := _round_effects._run_scheduled_round_start(state, rng)
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
	var player_finish := _status_ticks._finish_owner_turn(state, rng, UnitState.Team.PLAYER)
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
			var stunned_finish := _status_ticks._finish_single_owner_turn(state, rng, enemy_id)
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
		var enemy_finish := _status_ticks._finish_single_owner_turn(state, rng, enemy_id)
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

func _discard_remaining_hand(deck: DeckState) -> void:
	var remaining := deck.hand.duplicate()
	for uid_value: Variant in remaining:
		_card_system.discard_from_hand(deck, int(uid_value))

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


func evaluate_outcome(state: BattleState) -> BattleState.Phase:
	return OutcomeEvaluator.evaluate(state)
