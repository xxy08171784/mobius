class_name StatusDef
extends Resource
## 状态的只读定义。运行中的层数/持续时间放在 StatusState。

enum TickTiming {
	ROUND_START,
	OWNER_TURN_START,
	OWNER_TURN_END,
	ROUND_END,
}

@export var status_id: StringName = &""
@export var tick_timing: TickTiming = TickTiming.OWNER_TURN_END
@export var priority: int = 0


func is_valid() -> bool:
	return not status_id.is_empty()
