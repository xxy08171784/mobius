extends SceneTree
## 临时无头测试入口：跑 tests/rules/map_generator_test.gd。
## 用法：godot --headless --path D:/mobius --script res://tools/run_map_tests.gd
## Phase 0 的 tests/run_all.gd 落地后可删本文件（测试逻辑保留在 tests/rules/）。


func _initialize() -> void:
	var script: GDScript = load("res://tests/rules/map_generator_test.gd")
	if script == null:
		printerr("MAP TESTS: 无法加载 tests/rules/map_generator_test.gd")
		quit(1)
		return
	var t: RefCounted = script.new()
	var fails: Array = t.call("run_all")
	if fails.is_empty():
		print("MAP TESTS: PASS")
		quit(0)
	else:
		printerr("MAP TESTS: FAIL (%d)" % fails.size())
		for f in fails:
			printerr("  - " + str(f))
		quit(1)
