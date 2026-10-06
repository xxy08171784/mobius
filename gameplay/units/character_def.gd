class_name CharacterDef
extends Resource
## 角色定义：初始卡组 / 初始遗物 / 职业标签。只读。
## 卡牌与遗物用稳定 StringName ID 引用（定义资源由 Track A / ContentDB 提供）。

@export var id: StringName = &""
@export var display_name: String = ""

## 关联的单位定义 ID（决定基础属性）。
@export var unit_def_id: StringName = &""

## 初始卡组：卡牌定义 ID 列表（同名卡可重复出现）。
@export var starter_deck: Array[StringName] = []

## 初始遗物 ID 列表。
@export var starter_relics: Array[StringName] = []

## 职业标签（如 &"warrior"、&"mage"），供内容过滤/组合规则使用。
@export var class_tags: Array[StringName] = []


func is_valid() -> bool:
	return not id.is_empty() and not unit_def_id.is_empty() and not starter_deck.is_empty()

## 0 表示默认可选；大于 0 时由 Profile 货币解锁。
@export_range(0, 9999) var unlock_cost: int = 0
