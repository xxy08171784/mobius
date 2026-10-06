class_name CardSelectionBudget
extends RefCounted
## 显示与选择门槛共用实际费用，包含升级和本场费用修正；最终结算仍由 Session 校验。

static func total_cost(state: BattleState, definitions: Dictionary, uids: Array[int]) -> int:
	var total := 0
	for uid: int in uids:
		var card := state.deck.get_card(uid)
		var definition: CardDef = null if card == null else definitions.get(card.card_id)
		if definition != null:
			total += card.effective_cost(definition)
	return total


static func energy(state: BattleState) -> int:
	var players := state.alive_player_ids()
	return 0 if players.is_empty() else state.get_unit(players[0]).get_resource(TurnSystem.ENERGY_RESOURCE)
