class_name EventBatch
extends RefCounted
## 一次结算产生的有序事件序列。表现层按顺序播放。

var events: Array[GameEvent] = []

func push_back(event: GameEvent) -> void:
	events.append(event)

func size() -> int:
	return events.size()

func clear() -> void:
	events.clear()
