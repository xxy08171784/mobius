class_name ResourceEffectHandler
extends EffectHandler
## 通用单位资源效果。勇气、移动点、能量等都走 UnitState.resources，不为每种资源建 handler。


func get_type_key() -> StringName:
	return &"resource"


func apply(
	work_state: Variant,
	effect: Dictionary,
	context: EffectContext,
	_rng: RandomNumberGenerator
) -> Dictionary:
	var params: Dictionary = effect.get("params", {})
	var resource_key := StringName(String(params.get("key", params.get("resource", ""))).strip_edges())
	if resource_key.is_empty():
		return _error(&"invalid_resource")

	var target_id := EffectStateAccess.target_unit_id(context)
	if target_id < 0:
		target_id = context.source_unit_id
	var target: Variant = EffectStateAccess.get_unit(work_state, target_id)
	if target == null:
		return _error(&"invalid_target")

	var before := _get_resource(target, resource_key)
	var operation := StringName(String(params.get("operation", "add")))
	var amount := int(params.get("amount", 0))
	var after := before
	var consumed := 0
	match operation:
		&"add":
			after = before + amount
		&"set":
			after = amount
		&"spend":
			var spend_amount := maxi(0, amount)
			if before < spend_amount:
				return _error(&"resource_insufficient")
			consumed = spend_amount
			after = before - spend_amount
		&"consume_all":
			consumed = maxi(0, before)
			after = 0
		_:
			return _error(&"invalid_operation")

	if bool(params.get("clamp_non_negative", true)):
		after = maxi(0, after)
	if not _set_resource(target, resource_key, after):
		return _error(&"resource_unavailable")

	var event := EffectEvent.create(
		EffectStateAccess.allocate_event_seq(work_state),
		&"resource_changed",
		context.source_unit_id,
		target_id,
		{"resource": resource_key, "value": before},
		{"resource": resource_key, "value": after},
		{
			"resource": resource_key,
			"operation": operation,
			"amount": amount,
			"consumed": consumed,
		}
	)
	return {"ok": true, "events": [event], "triggers": []}


func _get_resource(target: Variant, key: StringName) -> int:
	if target is Object and (target as Object).has_method(&"get_resource"):
		return int((target as Object).call(&"get_resource", key))
	var resources: Variant = EffectStateAccess.get_field(target, &"resources", {})
	if resources is Dictionary:
		var dict := resources as Dictionary
		if dict.has(key):
			return int(dict[key])
		if dict.has(String(key)):
			return int(dict[String(key)])
	return 0


func _set_resource(target: Variant, key: StringName, value: int) -> bool:
	if target is Object and (target as Object).has_method(&"set_resource"):
		(target as Object).call(&"set_resource", key, value)
		return true
	var resources: Variant = EffectStateAccess.get_field(target, &"resources", null)
	if resources is Dictionary:
		var dict := resources as Dictionary
		dict[key] = value
		return true
	return false


func _error(code: StringName) -> Dictionary:
	return {"ok": false, "error_code": code, "events": [], "triggers": []}
