class_name BattleAnimationQueue
extends Node
## 按 EventBatch 顺序播放占位反馈；正式美术到位后可把 visual_sink 替换为正式 Tween/VFX。

var step_seconds: float = 0.10


func play(events: EventBatch, event_sink: Callable, visual_sink: Callable = Callable()) -> void:
	await get_tree().process_frame
	if events == null:
		return
	for event: GameEvent in events.events:
		if visual_sink.is_valid():
			visual_sink.call(event)
		if event_sink.is_valid():
			event_sink.call(event)
		if step_seconds > 0.0:
			await get_tree().create_timer(step_seconds).timeout
