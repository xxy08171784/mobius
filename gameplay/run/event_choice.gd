class_name EventChoice
extends Resource
## 事件的一个选项及其效果。只读定义。

@export var label: String = ""
## HP 变化（正=治疗，负=伤害）；会被钳制在 [0, max_hp]。
@export var hp_delta: int = 0
## 金币变化（正=获得，负=失去）；不会低于 0。
@export var gold_delta: int = 0
## 非空则加入一张该卡（稳定 ID）。
@export var add_card_id: StringName = &""


func is_valid() -> bool:
	return not label.is_empty()
