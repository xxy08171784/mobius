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
	# 无目标技能默认把状态施加给来源单位，允许“专注”等自增益卡保持无目标合同。
	if target_id < 0:
		target_id = context.source_unit_id
	var target: Variant = EffectStateAccess.get_unit(work_state, target_id)
	if target == null:
		return _error(&"invalid_target")

	var params: Dictionary = effect.get("params", {})
	var status_id := StringName(String(effect.get("status_id", params.get("status_id", ""))))
	if status_id.is_empty():
		return _error(&"invalid_status")

	# 玩家没有眩晕机制；错误配置的玩家眩晕效果也不进入状态列表。
	if target is UnitState and target.team == UnitState.Team.PLAYER and status_id == StatusRules.STUN:
		return {"ok": true, "events": [], "triggers": []}

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
	status.duration = -1 if bool(params.get("persistent", false)) else maxi(1, int(params.get("duration", 1)))
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
