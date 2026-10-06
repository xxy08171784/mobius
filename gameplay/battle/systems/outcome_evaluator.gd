class_name OutcomeEvaluator
extends RefCounted

static func evaluate(state: BattleState) -> BattleState.Phase:
	if state.alive_player_ids().is_empty():
		return BattleState.Phase.DEFEAT
	if state.alive_enemy_ids().is_empty():
		return BattleState.Phase.VICTORY
	return BattleState.Phase.SETUP
