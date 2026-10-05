class_name BlockEffectHandler
extends EffectHandler


func get_type_key() -> StringName:
	return &"block"


func apply(
	work_state: Variant,
	effect: Dictionary,
	context: EffectContext,
	_rng: RandomNumberGenerator
) -> Dictionary:
	var target_id := EffectStateAccess.target_unit_id(context)
	if target_id < 0:
		target_id = context.source_unit_id
	var target: Variant = EffectStateAccess.get_unit(work_state, target_id)
	if target == null:
		return _error(&"invalid_target")
	var params: Dictionary = effect.get("params", {})
	var amount := maxi(0, int(floor(float(params.get("amount", 0.0)))))
	var before := maxi(0, int(EffectStateAccess.get_field(target, &"block", 0)))
	var after := before + amount
	if not EffectStateAccess.set_field(target, &"block", after):
		return _error(&"missing_block_field")
	var event := EffectEvent.create(
		EffectStateAccess.allocate_event_seq(work_state),
		&"block_gained",
		context.source_unit_id,
		target_id,
		{"block": before},
		{"block": after},
		{"amount": amount}
	)
	return {"ok": true, "events": [event], "triggers": []}


func _error(code: StringName) -> Dictionary:
	return {"ok": false, "error_code": code, "events": [], "triggers": []}
