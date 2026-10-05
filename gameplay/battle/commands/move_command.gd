class_name MoveCommand
extends GameCommand
## 自由移动（是否消耗独立行动点属于玩法规则，见 combat_rules.md §13）。

var destination: Vector2i = Vector2i.ZERO


func get_type_key() -> StringName:
	return &"move"
