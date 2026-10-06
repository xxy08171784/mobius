class_name CardDef
extends Resource
## 卡牌静态定义。Resource 约定只读，运行时变化放 RunCardState/BattleCardState。

enum ContentTargetKind { NONE, UNIT, CELL, DIRECTION }

## 卡牌类别 tag（组合出牌规则的载体，见 combo_class_of）。
const TAG_ATTACK: StringName = &"attack"
const TAG_TECHNIQUE: StringName = &"technique"
const TAG_DEFENSE: StringName = &"defense"
const TAG_SKILL: StringName = &"skill"
const TAG_ABILITY: StringName = &"ability"

## 组合类别：攻击/招式同类，防御单独一类，技能/能力不可连出，未标注为通配。
enum ComboClass { ATTACK, DEFENSE, NO_COMBO, NEUTRAL }

@export var card_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var base_cost: int = 0
@export var tags: Array[StringName] = []
@export var effects: Array[EffectDef] = []
@export var exhaust_on_play: bool = false
@export var attack_range: int = 1
@export var requires_los: bool = true

## TargetSpec 是冻结的 RefCounted 契约，不能直接序列化进 .tres。
## 内容资源用这两个字段描述目标槽，运行时再合成为 TargetSpec。
@export var content_target_kind: ContentTargetKind = ContentTargetKind.NONE
@export_enum("Any", "Ally", "Enemy", "Self") var content_target_team: int = 2

## B1 的正式 TargetSpec 目标槽；null 表示该卡不需要目标。
var target_rule: TargetSpec = null

## level -> Dictionary 覆盖。
## 支持字段：cost / tags / effects / target_rule / exhaust_on_play。
@export var upgrade_overrides: Dictionary = {}


func is_valid() -> bool:
	return not card_id.is_empty() and base_cost >= 0


## 由 tag 集合判定组合类别。技能/能力优先（一旦出现即视为不可连出）；
## 防御独立一类；攻击/招式同类；其余（含未标注的占位卡）为通配 NEUTRAL。
static func combo_class_of(tags: Array) -> int:
	if tags.has(TAG_SKILL) or tags.has(TAG_ABILITY):
		return ComboClass.NO_COMBO
	if tags.has(TAG_DEFENSE):
		return ComboClass.DEFENSE
	if tags.has(TAG_ATTACK) or tags.has(TAG_TECHNIQUE):
		return ComboClass.ATTACK
	return ComboClass.NEUTRAL


func get_cost(upgrade_level: int = 0) -> int:
	var data := _upgrade_data(upgrade_level)
	return maxi(0, int(data.get("cost", base_cost)))


func get_tags(upgrade_level: int = 0) -> Array[StringName]:
	var data := _upgrade_data(upgrade_level)
	if data.has("tags"):
		var result: Array[StringName] = []
		for tag: Variant in data["tags"]:
			result.append(StringName(String(tag)))
		return result
	return tags.duplicate()


func get_effects(upgrade_level: int = 0) -> Array:
	var data := _upgrade_data(upgrade_level)
	if data.has("effects"):
		return Array(data["effects"]).duplicate()
	return Array(effects).duplicate()


func get_target_rule(upgrade_level: int = 0) -> TargetSpec:
	var value: Variant = _upgrade_data(upgrade_level).get("target_rule", target_rule)
	if value is TargetSpec:
		return value as TargetSpec
	return _content_target_rule()


func get_attack_range(upgrade_level: int = 0) -> int:
	return maxi(0, int(_upgrade_data(upgrade_level).get("range", attack_range)))


func needs_line_of_sight(upgrade_level: int = 0) -> bool:
	return bool(_upgrade_data(upgrade_level).get("requires_los", requires_los))


func should_exhaust(upgrade_level: int = 0) -> bool:
	return bool(_upgrade_data(upgrade_level).get("exhaust_on_play", exhaust_on_play))


func _upgrade_data(level: int) -> Dictionary:
	if level <= 0:
		return {}
	if upgrade_overrides.has(level):
		return upgrade_overrides[level]
	if upgrade_overrides.has(str(level)):
		return upgrade_overrides[str(level)]
	return {}


func _content_target_rule() -> TargetSpec:
	match content_target_kind:
		ContentTargetKind.UNIT:
			var unit_target := TargetSpec.UnitTarget.new()
			unit_target.team = content_target_team as TargetSpec.UnitTarget.Team
			return unit_target
		ContentTargetKind.CELL:
			return TargetSpec.CellTarget.new()
		ContentTargetKind.DIRECTION:
			return TargetSpec.DirectionTarget.new()
		_:
			return null
