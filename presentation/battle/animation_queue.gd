class_name BattleAnimationQueue
extends Node
## Phase 4 第一版只负责按事件顺序节拍播放；正式美术到位后在这里接 Tween/VFX。

var step_seconds: float = 0.10


func play(events: EventBatch, event_sink: Callable) -> void:
	await get_tree().process_frame
	if events == null:
		return
	for event: GameEvent in events.events:
		if event_sink.is_valid():
			event_sink.call(event)
		if step_seconds > 0.0:
			await get_tree().create_timer(step_seconds).timeout
