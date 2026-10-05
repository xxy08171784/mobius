class_name BattleCardState
extends RefCounted
## 单场战斗中的卡实例。临时费用/标签只活到本场结束。

var battle_uid: int = -1
var source_run_uid: int = -1
var card_id: StringName = &""
var upgrade_level: int = 0
var cost_modifier: int = 0
var temporary_tags: Array[StringName] = []
var generated: bool = false


func effective_cost(definition: CardDef) -> int:
	return maxi(0, definition.get_cost(upgrade_level) + cost_modifier)


func effective_tags(definition: CardDef) -> Array[StringName]:
	var result := definition.get_tags(upgrade_level)
	for tag: StringName in temporary_tags:
		if not result.has(tag):
			result.append(tag)
	return result


func duplicate_state() -> BattleCardState:
	var copy := BattleCardState.new()
	copy.battle_uid = battle_uid
	copy.source_run_uid = source_run_uid
	copy.card_id = card_id
	copy.upgrade_level = upgrade_level
	copy.cost_modifier = cost_modifier
	copy.temporary_tags = temporary_tags.duplicate()
	copy.generated = generated
	return copy
