class_name RunCardState
extends RefCounted
## 一整局持有的永久卡实例。同名卡靠 run_uid 区分。

var run_uid: int = -1
var card_id: StringName = &""
var upgrade_level: int = 0
var permanent_modifiers: Dictionary = {}


func duplicate_state() -> RunCardState:
	var copy := RunCardState.new()
	copy.run_uid = run_uid
	copy.card_id = card_id
	copy.upgrade_level = upgrade_level
	copy.permanent_modifiers = permanent_modifiers.duplicate(true)
	return copy
