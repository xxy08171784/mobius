class_name ApplyStatusEffectHandler
extends EffectHandler


func get_type_key() -> StringName:
	return &"apply_status"


func apply(
	work_state: Variant,
	effect: Dictionary,
	context: EffectContext,
	_rng: RandomNumberGenerator
) -> Dictionary:
	var target_id := EffectStateAccess.target_unit_id(context)
	var target: Variant = EffectStateAccess.get_unit(work_state, target_id)
	if target == null:
		return _error(&"invalid_target")

	var params: Dictionary = effect.get("params", {})
	var status_id := StringName(String(effect.get("status_id", params.get("status_id", ""))))
	if status_id.is_empty():
		return _error(&"invalid_status")

	var statuses: Variant = EffectStateAccess.get_field(target, &"statuses")
	if statuses == null:
		statuses = {}
		if not EffectStateAccess.set_field(target, &"statuses", statuses):
			return _error(&"missing_statuses_field")
	if not statuses is Dictionary:
		return _error(&"invalid_statuses_container")

	var status := StatusState.new()
	status.instance_id = EffectStateAccess.allocate_uid(work_state)
	status.status_id = status_id
	status.stacks = maxi(1, int(params.get("stacks", 1)))
	status.duration = maxi(1, int(params.get("duration", 1)))
	status.source_unit_id = context.source_unit_id
	if target is UnitState:
		(target as UnitState).set_status(status.instance_id, status)
	else:
		(statuses as Dictionary)[status.instance_id] = status

	var event := EffectEvent.create(
		EffectStateAccess.allocate_event_seq(work_state),
		&"status_applied",
		context.source_unit_id,
		target_id,
		{},
		{},
		{
			"instance_id": status.instance_id,
			"status_id": status.status_id,
			"stacks": status.stacks,
			"duration": status.duration,
		}
	)
	return {"ok": true, "events": [event], "triggers": []}


func _error(code: StringName) -> Dictionary:
	return {"ok": false, "error_code": code, "events": [], "triggers": []}
