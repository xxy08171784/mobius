class_name BattleCardState
extends RefCounted
## 单场战斗中的卡实例。临时费用/标签只活到本场结束。

var battle_uid: int = -1
var source_run_uid: int = -1
var card_id: StringName = &""
var upgrade_level: int = 0
var cost_modifier: int = 0
## 战斗内攻击/护甲永久修正；仅活到本场战斗结束。
var damage_modifier: int = 0
var block_modifier: int = 0
var temporary_tags: Array[StringName] = []
## 单卡战斗态（抽到次数、当回合临时加成等），必须可序列化。
var runtime_data: Dictionary = {}
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
	copy.damage_modifier = damage_modifier
	copy.block_modifier = block_modifier
	copy.temporary_tags = temporary_tags.duplicate()
	copy.runtime_data = runtime_data.duplicate(true)
	copy.generated = generated
	return copy
