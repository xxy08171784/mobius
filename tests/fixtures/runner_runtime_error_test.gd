extends "res://tests/test_case.gd"
## 仅供测试 runner 自身使用；默认 tests/rules 扫描不会执行本文件。


func run() -> Array[String]:
	reset()
	_trigger_runtime_error()
	return failures()


func _trigger_runtime_error() -> void:
	var missing: Object = null
	missing.call("this_method_does_not_exist")
