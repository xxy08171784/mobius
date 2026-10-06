class_name PullEffectHandler
extends EffectHandler
## 拖拽：把目标（玩家）朝施法者方向直线拉（碰撞处理统一走 B1 `Displacement.pull`）。
## 发 `unit_moved` 事件（带 path），让表现层滑移动画直接复用。
## 每步伤害由 TurnSystem 在计划里按路径步数算好，作为独立的 damage 效果，本 handler 不产伤害。

const REASON_MOVE_KEYS: Array[StringName] = [
	DisplacementResult.REASON_NO_UNIT,
	DisplacementResult.REASON_BAD_DIRECTION,
]


func get_type_key() -> StringName:
	return &"pull"


func apply(
	work_state: Variant,
	effect: Dictionary,
	context: EffectContext,
	_rng: RandomNumberGenerator
) -> Dictionary:
	var target_id := EffectStateAccess.target_unit_id(context)
	if target_id < 0:
		return _error(&"invalid_target")
	var params: Dictionary = effect.get("params", {})
	var toward: Variant = effect.get("toward_cell", params.get("toward_cell"))
	if not toward is Vector2i:
		return _error(&"invalid_direction")
	var distance := maxi(0, int(params.get("distance", params.get("steps", params.get("amount", 1)))))

	var board := EffectStateAccess.get_board(work_state)
	if board == null:
		return _error(&"pull_unavailable")
	var displacement := Displacement.pull(board, target_id, toward as Vector2i, distance)
	if displacement.reason in REASON_MOVE_KEYS:
		return _error(displacement.reason)
	var event := EffectEvent.create(
		EffectStateAccess.allocate_event_seq(work_state),
		&"unit_moved",
		context.source_unit_id,
		target_id,
		{"cell": displacement.from_cell},
		{"cell": displacement.to_cell},
		{
			"path": displacement.path.duplicate(),
			"reason": displacement.reason,
			"distance": distance,
		}
	)
	return {"ok": true, "events": [event], "triggers": []}


func _error(code: StringName) -> Dictionary:
	return {"ok": false, "error_code": code, "events": [], "triggers": []}
