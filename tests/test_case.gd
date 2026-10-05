class_name PhaseZeroTestCase
extends RefCounted
## 极小测试基类：项目不引第三方测试框架，Phase 0 先保证 headless 可跑。

var _failures: Array[String] = []


func reset() -> void:
	_failures.clear()


func failures() -> Array[String]:
	return _failures.duplicate()


func assert_true(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func assert_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (actual=%s, expected=%s)" % [message, actual, expected])


func assert_not_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		_failures.append("%s (both=%s)" % [message, actual])
