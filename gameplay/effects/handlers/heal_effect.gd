class_name HealEffectHandler
extends EffectHandler
## 战斗内治疗。永久最大生命值属于 Run/奖励层，不在此 handler 偷偷修改。


func get_type_key() -> StringName:
	return &"heal"


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
	var amount := maxi(0, int(params.get("amount", 0)))
	var hp_before := int(EffectStateAccess.get_field(target, &"hp", 0))
	var max_hp := maxi(0, int(EffectStateAccess.get_field(target, &"max_hp", hp_before)))
	var hp_after := mini(max_hp, hp_before + amount)
	if not EffectStateAccess.set_field(target, &"hp", hp_after):
		return _error(&"missing_hp_field")

	var actual := hp_after - hp_before
	var event := EffectEvent.create(
		EffectStateAccess.allocate_event_seq(work_state),
		&"healed",
		context.source_unit_id,
		target_id,
		{"hp": hp_before, "max_hp": max_hp},
		{"hp": hp_after, "max_hp": max_hp},
		{"requested": amount, "amount": actual}
	)
	return {"ok": true, "events": [event], "triggers": []}


func _error(code: StringName) -> Dictionary:
	return {"ok": false, "error_code": code, "events": [], "triggers": []}
