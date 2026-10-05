class_name DrawEffectHandler
extends EffectHandler
## 抽牌效果只定义调用契约；真正牌区规则由 A2 的 Deck/CardSystem 提供。


func get_type_key() -> StringName:
	return &"draw"


func apply(
	work_state: Variant,
	effect: Dictionary,
	context: EffectContext,
	rng: RandomNumberGenerator
) -> Dictionary:
	var params: Dictionary = effect.get("params", {})
	var count := maxi(0, int(params.get("count", params.get("amount", 0))))
	var result: Variant = EffectStateAccess.call_state_or_service(
		work_state,
		&"draw_cards",
		&"deck",
		&"draw_cards",
		[context.source_unit_id, count, rng]
	)
	if result == null:
		return _error(&"draw_unavailable")

	var cards: Array = []
	if result is Array:
		cards = (result as Array).duplicate()
	elif result is Dictionary:
		var result_dict := result as Dictionary
		if not bool(result_dict.get("ok", true)):
			return _error(StringName(String(result_dict.get("error_code", "draw_failed"))))
		cards = result_dict.get("cards", [])
	else:
		return _error(&"draw_failed")

	var event := EffectEvent.create(
		EffectStateAccess.allocate_event_seq(work_state),
		&"cards_drawn",
		context.source_unit_id,
		context.source_unit_id,
		{},
		{},
		{"requested": count, "cards": cards.duplicate()}
	)
	return {"ok": true, "events": [event], "triggers": []}


func _error(code: StringName) -> Dictionary:
	return {"ok": false, "error_code": code, "events": [], "triggers": []}
