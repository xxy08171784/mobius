class_name MoveEffectHandler
extends EffectHandler
## Move 优先走 B1 Displacement.move；测试桩仍可走兼容服务入口。


func get_type_key() -> StringName:
	return &"move"


func apply(
	work_state: Variant,
	effect: Dictionary,
	context: EffectContext,
	_rng: RandomNumberGenerator
) -> Dictionary:
	if context.source_unit_id < 0:
		return _error(&"invalid_source")
	var destination: Variant = EffectStateAccess.target_cell(context)
	if not destination is Vector2i:
		return _error(&"invalid_target")

	var board := EffectStateAccess.get_board(work_state)
	if board != null:
		var params: Dictionary = effect.get("params", {})
		var move_points := maxi(
			0,
			int(params.get("move_points", params.get("steps", params.get("amount", 0))))
		)
		var displacement := Displacement.move(
			board,
			context.source_unit_id,
			destination,
			move_points
		)
		if not displacement.moved and displacement.reason != DisplacementResult.REASON_SAME_CELL:
			return _error(displacement.reason if not displacement.reason.is_empty() else &"move_failed")
		var event := EffectEvent.create(
			EffectStateAccess.allocate_event_seq(work_state),
			&"unit_moved",
			context.source_unit_id,
			context.source_unit_id,
			{"cell": displacement.from_cell},
			{"cell": displacement.to_cell},
			{
				"path": displacement.path.duplicate(),
				"reason": displacement.reason,
				"move_points": move_points,
			}
		)
		return {"ok": true, "events": [event], "triggers": []}

	var result: Variant = EffectStateAccess.call_state_or_service(
		work_state,
		&"move_unit",
		&"board",
		&"move_unit",
		[context.source_unit_id, destination]
	)
	if result == null:
		return _error(&"move_unavailable")
	var before: Dictionary = {}
	var after: Dictionary = {"cell": destination}
	if result is Dictionary:
		var result_dict := result as Dictionary
		if not bool(result_dict.get("ok", true)):
			return _error(StringName(String(result_dict.get("error_code", "move_failed"))))
		before = result_dict.get("before", before)
		after = result_dict.get("after", after)
	elif result is bool and not bool(result):
		return _error(&"move_failed")

	var event := EffectEvent.create(
		EffectStateAccess.allocate_event_seq(work_state),
		&"unit_moved",
		context.source_unit_id,
		context.source_unit_id,
		before,
		after
	)
	return {"ok": true, "events": [event], "triggers": []}


func _error(code: StringName) -> Dictionary:
	return {"ok": false, "error_code": code, "events": [], "triggers": []}
