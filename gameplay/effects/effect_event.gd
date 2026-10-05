class_name EffectEvent
extends GameEvent
## A1 规则层产生的通用效果事件。表现层只消费这些数据，不参与结算。

var payload: Dictionary = {}


static func create(
	event_seq: int,
	event_type: StringName,
	source_unit_id: int,
	target_unit_id: int,
	before_values: Dictionary = {},
	after_values: Dictionary = {},
	extra_payload: Dictionary = {}
) -> EffectEvent:
	var event := EffectEvent.new()
	event.seq = event_seq
	event.type_key = event_type
	event.source_id = source_unit_id
	event.target_id = target_unit_id
	event.before = before_values.duplicate(true)
	event.after = after_values.duplicate(true)
	event.payload = extra_payload.duplicate(true)
	return event
