class_name CardDef
extends Resource
## 卡牌静态定义。Resource 约定只读，运行时变化放 RunCardState/BattleCardState。

enum ContentTargetKind { NONE, UNIT, CELL, DIRECTION }
enum CardCategory { UNASSIGNED, SKILL, TECHNIQUE, ATTACK, DEFENSE }

## 组合规则仍以运行时有效 tags 为准；CardCategory 主要服务正式内容分类与效果元数据。
const TAG_ATTACK: StringName = &"attack"
const TAG_TECHNIQUE: StringName = &"technique"
const TAG_DEFENSE: StringName = &"defense"
const TAG_SKILL: StringName = &"skill"
const TAG_ABILITY: StringName = &"ability"

## 攻击/招式可以互相组合，防御单独成组；技能/能力只允许单独打出。
enum ComboClass { ATTACK, DEFENSE, NO_COMBO, NEUTRAL }

@export var card_id: StringName = &""
## 正式奖励卡永久编号。0 表示原型/测试/未编号卡，不参与 01~49 的正式编号体系。
@export_range(0, 999, 1) var card_number: int = 0
@export var card_category: CardCategory = CardCategory.UNASSIGNED
## 旧整卡 PNG 的兼容键；当前战斗手牌改用“卡框 + icon + 文本”动态拼卡。
@export var visual_key: StringName = &""
## 动态卡面的技能图标键。正式卡默认 icon_01 ~ icon_49；通用牌可显式共用图标。
@export var icon_key: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## 特殊卡的数值参数；升级覆盖中的 rule_values 按键覆盖。
@export var rule_values: Dictionary = {}
@export var requires_active_movement: bool = false
@export var base_cost: int = 0
## 是否允许进入普通战后奖励池。尚未实现规则的正式卡可先注册/展示，但不能被玩家抽到。
@export var reward_pool_enabled: bool = true
@export var tags: Array[StringName] = []
@export var effects: Array[EffectDef] = []
@export var exhaust_on_play: bool = false
@export var attack_range: int = 1
@export var requires_los: bool = true
## 组合出牌计数权重。普通牌=1，算作两张=2，不计入出牌数=0。
@export_range(0, 8, 1) var play_count_weight: int = 1

## TargetSpec 是冻结的 RefCounted 契约，不能直接序列化进 .tres。
## 内容资源用这两个字段描述目标槽，运行时再合成为 TargetSpec。
@export var content_target_kind: ContentTargetKind = ContentTargetKind.NONE
@export_enum("Any", "Ally", "Enemy", "Self") var content_target_team: int = 2

## B1 的正式 TargetSpec 目标槽；null 表示该卡不需要目标。
var target_rule: TargetSpec = null

## level -> Dictionary 覆盖。
## 支持字段：cost / tags / effects / target_rule / exhaust_on_play / play_count_weight / range / requires_los / description / rule_values。
@export var upgrade_overrides: Dictionary = {}


func is_valid() -> bool:
	return not card_id.is_empty() and base_cost >= 0


## 用有效 tag 判定组合类别，兼容升级/战斗临时 tag。
static func combo_class_of(card_tags: Array) -> int:
	if card_tags.has(TAG_SKILL) or card_tags.has(TAG_ABILITY):
		return ComboClass.NO_COMBO
	if card_tags.has(TAG_DEFENSE):
		return ComboClass.DEFENSE
	if card_tags.has(TAG_ATTACK) or card_tags.has(TAG_TECHNIQUE):
		return ComboClass.ATTACK
	return ComboClass.NEUTRAL


func is_numbered_card() -> bool:
	return card_number > 0


func get_visual_key() -> StringName:
	if not visual_key.is_empty():
		return visual_key
	if card_number > 0:
		return StringName("card_%02d" % card_number)
	return card_id


func get_icon_key() -> StringName:
	if not icon_key.is_empty():
		return icon_key
	if card_number > 0:
		return StringName("icon_%02d" % card_number)
	return &"icon_01"


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


func get_play_count_weight(upgrade_level: int = 0) -> int:
	return maxi(0, int(_upgrade_data(upgrade_level).get("play_count_weight", play_count_weight)))


func _upgrade_data(level: int) -> Dictionary:
	if level <= 0:
		return {}
	level = 1
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


func get_rule_value(key: String, level: int = 0, fallback: float = 0.0) -> float:
	var upgraded: Dictionary = _upgrade_data(level).get("rule_values", {})
	return float(upgraded.get(key, rule_values.get(key, fallback)))


func get_description(level: int = 0) -> String:
	return String(_upgrade_data(level).get("description", description))


func get_display_name(level: int = 0) -> String:
	return (display_name if not display_name.is_empty() else String(card_id)) + ("+" if level > 0 else "")
