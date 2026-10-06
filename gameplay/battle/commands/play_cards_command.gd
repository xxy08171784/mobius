class_name PlayCardsCommand
extends GameCommand
## 组合出牌：选定的卡 UID 序列 + 每张卡的目标（combat_rules.md §4）。

## RunCard/BattleCard 实例 UID，按执行顺序排列。
var card_uids: Array[int] = []

## 与 card_uids 一一对应的 TargetSpec（可不同目标）。
var targets: Array = []
## 额外卡牌选择。key = 出牌卡 battle_uid，value = 被该牌选择的 battle_uid 数组。
var choices: Dictionary = {}


func get_type_key() -> StringName:
	return &"play_cards"
