class_name EventSystem
extends RefCounted
## 事件规则：选择选项后应用其效果。校验先行，失败零副作用。


## 应用第 index 个选项的效果到 RunState。返回事件结果摘要。
static func resolve(run: RunState, def: EventDef, choice_index: int) -> Dictionary:
	if run == null:
		return {"ok": false, "error_code": &"run_not_ready"}
	if def == null or not def.is_valid():
		return {"ok": false, "error_code": &"invalid_event"}
	if choice_index < 0 or choice_index >= def.choices.size():
		return {"ok": false, "error_code": &"invalid_choice"}
	var choice: EventChoice = def.choices[choice_index]
	if choice == null or not choice.is_valid():
		return {"ok": false, "error_code": &"invalid_choice"}
	if run.gold + choice.gold_delta < 0:
		return {"ok": false, "error_code": &"not_enough_gold"}

	run.hp = clampi(run.hp + choice.hp_delta, 0, run.max_hp)
	run.gold = maxi(0, run.gold + choice.gold_delta)

	var added: StringName = &""
	if not choice.add_card_id.is_empty():
		var card := run.add_card(choice.add_card_id)
		added = card.card_id

	return {
		"ok": true,
		"kind": &"event_choice",
		"hp": run.hp,
		"gold": run.gold,
		"add_card_id": added,
	}
