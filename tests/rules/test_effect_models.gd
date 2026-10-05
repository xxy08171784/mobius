extends "res://tests/test_case.gd"


func run() -> Array[String]:
	reset()
	_test_status_state()
	_test_relic_state()
	_test_effect_context_copy()
	return failures()


func _test_status_state() -> void:
	var status := StatusState.new()
	status.status_id = &"poison"
	status.stacks = 2
	status.duration = 3
	status.source_unit_id = 9
	status.decrease_duration()
	assert_equal(status.duration, 2, "status duration should decrease")
	assert_true(not status.is_expired(), "positive status should not be expired")
	status.decrease_duration(9)
	assert_true(status.is_expired(), "duration zero should expire status")


func _test_relic_state() -> void:
	var relic := RelicState.new()
	relic.relic_id = &"relic.test"
	assert_equal(relic.add_counter(&"uses"), 1, "relic counter first increment")
	assert_equal(relic.add_counter(&"uses", 2), 3, "relic counter should accumulate")


func _test_effect_context_copy() -> void:
	var context := EffectContext.new()
	context.source_unit_id = 7
	context.source_card_uid = 88
	context.target = 3
	context.depth = 2
	var copy := context.duplicate_context()
	copy.depth += 1
	assert_equal(context.depth, 2, "context copy must not mutate original")
	assert_equal(copy.source_card_uid, 88, "context copy should preserve fields")
