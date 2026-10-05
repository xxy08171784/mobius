extends "res://tests/test_case.gd"


func run() -> Array[String]:
	reset()
	_test_sort_order()
	_test_trigger_cap()
	return failures()


func _test_sort_order() -> void:
	var system := TriggerSystem.new()
	system.enqueue({"phase": 2, "priority": 0, "instance_id": 1})
	system.enqueue({"phase": 1, "priority": 5, "instance_id": 2})
	system.enqueue({"phase": 1, "priority": 1, "instance_id": 9})
	system.enqueue({"phase": 1, "priority": 1, "instance_id": 3})
	var result := system.drain()
	var order: Array = result["order"]
	assert_true(bool(result["ok"]), "trigger drain should succeed")
	assert_equal(int(order[0]["instance_id"]), 3, "phase -> priority -> id order #1")
	assert_equal(int(order[1]["instance_id"]), 9, "phase -> priority -> id order #2")
	assert_equal(int(order[2]["instance_id"]), 2, "phase -> priority -> id order #3")
	assert_equal(int(order[3]["instance_id"]), 1, "phase -> priority -> id order #4")


func _test_trigger_cap() -> void:
	var system := TriggerSystem.new()
	system.max_processed = 3
	for i: int in range(4):
		system.enqueue({"phase": 0, "priority": 0, "instance_id": i})
	var result := system.drain()
	assert_true(not bool(result["ok"]), "trigger cap should reject overflow")
	assert_true(bool(result["overflow"]), "overflow flag should be true")
	assert_equal(int(result["processed"]), 3, "must stop exactly at trigger cap")
