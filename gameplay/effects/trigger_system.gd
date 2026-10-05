class_name TriggerSystem
extends RefCounted
## 确定性触发队列：阶段 -> priority -> 稳定实例 ID。
## 新触发只能入队，禁止递归内联执行。

const DEFAULT_MAX_PROCESSED: int = 1000

var max_processed: int = DEFAULT_MAX_PROCESSED
var _queue: Array[Dictionary] = []


func clear() -> void:
	_queue.clear()


func size() -> int:
	return _queue.size()


func enqueue(trigger: Dictionary) -> void:
	_queue.append(trigger.duplicate(true))


func enqueue_many(triggers: Array) -> void:
	for trigger: Variant in triggers:
		if trigger is Dictionary:
			enqueue(trigger)


func drain(processor: Callable = Callable()) -> Dictionary:
	var processed := 0
	var order: Array[Dictionary] = []
	while not _queue.is_empty():
		if processed >= max_processed:
			return {
				"ok": false,
				"overflow": true,
				"processed": processed,
				"order": order,
			}

		_queue.sort_custom(_comes_before)
		var trigger: Dictionary = _queue.pop_front()
		order.append(trigger.duplicate(true))
		processed += 1

		if processor.is_valid():
			var result: Variant = processor.call(trigger)
			if result is Dictionary:
				var result_dict := result as Dictionary
				if not bool(result_dict.get("ok", true)):
					return {
						"ok": false,
						"overflow": false,
						"processed": processed,
						"order": order,
						"error_code": result_dict.get("error_code", &"trigger_error"),
					}
				enqueue_many(result_dict.get("triggers", []))

	return {
		"ok": true,
		"overflow": false,
		"processed": processed,
		"order": order,
	}


static func _comes_before(a: Dictionary, b: Dictionary) -> bool:
	var phase_a := int(a.get("phase", 0))
	var phase_b := int(b.get("phase", 0))
	if phase_a != phase_b:
		return phase_a < phase_b
	var priority_a := int(a.get("priority", 0))
	var priority_b := int(b.get("priority", 0))
	if priority_a != priority_b:
		return priority_a < priority_b
	return int(a.get("instance_id", 0)) < int(b.get("instance_id", 0))
