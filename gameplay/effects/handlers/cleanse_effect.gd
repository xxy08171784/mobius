class_name CleanseEffectHandler
extends EffectHandler
## 净化：移除目标身上的**负面**状态（流血/中毒/易伤/虚弱/减速/缠绕），保留正面（专注等）。
## 阴气护体（DEFEND + cleanse）用。

const NEGATIVE_STATUSES: Array[StringName] = [
	StatusRules.BLEED,
	StatusRules.POISON,
	StatusRules.VULNERABLE,
	StatusRules.WEAK,
	StatusRules.SLOW,
	StatusRules.ENTANGLE,
	StatusRules.CORRODE,
	StatusRules.IGNITE,
]


func get_type_key() -> StringName:
	return &"cleanse"


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

	var removed: Array[String] = []
	if target is UnitState:
		for instance_id: int in (target as UnitState).status_ids():
			var status := (target as UnitState).get_status(instance_id)
			if status != null and status.status_id in NEGATIVE_STATUSES:
				(target as UnitState).remove_status(instance_id)
				removed.append(String(status.status_id))

	var event := EffectEvent.create(
		EffectStateAccess.allocate_event_seq(work_state),
		&"status_cleansed",
		context.source_unit_id,
		target_id,
		{},
		{},
		{"removed": removed}
	)
	return {"ok": true, "events": [event], "triggers": []}


func _error(code: StringName) -> Dictionary:
	return {"ok": false, "error_code": code, "events": [], "triggers": []}
