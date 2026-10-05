extends "res://tests/test_case.gd"


func run() -> Array[String]:
	reset()
	assert_true(true, "runner smoke test")
	return failures()
