extends SceneTree
## Phase 0 手写测试运行器。
## 用法：godot --headless --path . -s res://tests/run_all.gd

const TEST_DIR := "res://tests/rules"


func _init() -> void:
	_run_all()


func _run_all() -> void:
	print("[TEST] runner start")
	var filenames := Array(DirAccess.get_files_at(TEST_DIR))
	filenames.sort()
	var total := 0
	var failed := 0

	for filename: String in filenames:
		if not filename.begins_with("test_") or not filename.ends_with(".gd"):
			continue
		total += 1
		var path := TEST_DIR.path_join(filename)
		print("[LOAD] %s" % filename)
		var script := load(path) as Script
		if script == null:
			failed += 1
			printerr("[FAIL] %s: load failed" % filename)
			continue
		var test_case: Object = script.new()
		if not test_case.has_method("run"):
			failed += 1
			printerr("[FAIL] %s: missing run()" % filename)
			continue

		print("[RUN ] %s" % filename)
		var failures: Array = test_case.call("run")
		if failures.is_empty():
			print("[PASS] %s" % filename)
		else:
			failed += 1
			print("[FAIL] %s" % filename)
			for failure: Variant in failures:
				print("  - %s" % failure)

	print("Rule tests: %d total, %d passed, %d failed" % [total, total - failed, failed])
	quit(0 if failed == 0 else 1)
