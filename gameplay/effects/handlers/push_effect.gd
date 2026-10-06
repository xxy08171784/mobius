class_name PushEffectHandler
extends EffectHandler
## Push 的墙/单位/边界处理由 B1 棋盘统一入口决定，A1 不复制空间规则。


func get_type_key() -> StringName:
	return &"push"


func apply(
	work_state: Variant,
	effect: Dictionary,
	context: EffectContext,
	_rng: RandomNumberGenerator
) -> Dictionary:
	var target_id := EffectStateAccess.target_unit_id(context)
	var params: Dictionary = effect.get("params", {})
	var direction: Variant = effect.get("direction", params.get("direction"))
	if not direction is Vector2i or (direction as Vector2i) == Vector2i.ZERO:
		direction = EffectStateAccess.target_direction(context)
	if (
		(not direction is Vector2i or (direction as Vector2i) == Vector2i.ZERO)
		and StringName(String(params.get("direction_mode", ""))) == &"away_from_source"
	):
		direction = _away_from_source_direction(work_state, context.source_unit_id, target_id)
	if target_id < 0:
		target_id = context.source_unit_id
	if target_id < 0:
		return _error(&"invalid_target")
	if not direction is Vector2i or (direction as Vector2i) == Vector2i.ZERO:
		return _error(&"invalid_direction")
	var steps := maxi(0, int(params.get("steps", params.get("amount", 1))))

	var board := EffectStateAccess.get_board(work_state)
	if board != null:
		var displacement := Displacement.push(board, target_id, direction, steps)
		if displacement.reason == DisplacementResult.REASON_NO_UNIT or displacement.reason == DisplacementResult.REASON_BAD_DIRECTION:
			return _error(displacement.reason)
		var event := EffectEvent.create(
			EffectStateAccess.allocate_event_seq(work_state),
			&"unit_pushed",
			context.source_unit_id,
			target_id,
			{"cell": displacement.from_cell},
			{"cell": displacement.to_cell},
			{
				"direction": direction,
				"steps": steps,
				"path": displacement.path.duplicate(),
				"reason": displacement.reason,
				"moved": displacement.moved,
			}
		)
		return {"ok": true, "events": [event], "triggers": []}

	var result: Variant = EffectStateAccess.call_state_or_service(
		work_state,
		&"push_unit",
		&"board",
		&"push_unit",
		[target_id, direction, steps]
	)
	if result == null:
		return _error(&"push_unavailable")
	var before: Dictionary = {}
	var after: Dictionary = {}
	if result is Dictionary:
		var result_dict := result as Dictionary
		if not bool(result_dict.get("ok", true)):
			return _error(StringName(String(result_dict.get("error_code", "push_failed"))))
		before = result_dict.get("before", before)
		after = result_dict.get("after", after)
	elif result is bool and not bool(result):
		return _error(&"push_failed")

	var event := EffectEvent.create(
		EffectStateAccess.allocate_event_seq(work_state),
		&"unit_pushed",
		context.source_unit_id,
		target_id,
		before,
		after,
		{"direction": direction, "steps": steps}
	)
	return {"ok": true, "events": [event], "triggers": []}


func _away_from_source_direction(work_state: Variant, source_id: int, target_id: int) -> Vector2i:
	if source_id < 0 or target_id < 0:
		return Vector2i.ZERO
	var board := EffectStateAccess.get_board(work_state)
	if board == null:
		return Vector2i.ZERO
	var source_cell := board.get_unit_cell(source_id)
	var target_cell := board.get_unit_cell(target_id)
	if source_cell == BoardState.INVALID_CELL or target_cell == BoardState.INVALID_CELL:
		return Vector2i.ZERO
	var delta := target_cell - source_cell
	return Vector2i(signi(delta.x), signi(delta.y))


func _error(code: StringName) -> Dictionary:
	return {"ok": false, "error_code": code, "events": [], "triggers": []}
