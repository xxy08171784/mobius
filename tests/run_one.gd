extends SceneTree
## 单测试子进程执行器。
## 不负责捕获 Godot 自身的 SCRIPT ERROR；父进程 run_all.gd 会检查完整 stderr/stdout。


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		printerr("[CHILD-FAIL] expected exactly one test path")
		quit(2)
		return

	var path := String(args[0])
	var script := load(path) as Script
	if script == null:
		printerr("[CHILD-FAIL] %s: load failed" % path)
		quit(2)
		return

	var test_case: Object = script.new()
	if test_case == null or not test_case.has_method("run"):
		printerr("[CHILD-FAIL] %s: missing run()" % path)
		quit(2)
		return

	var result: Variant = test_case.call("run")
	if not result is Array:
		printerr(
			"[CHILD-FAIL] %s: run() must return Array, got %s"
			% [path, type_string(typeof(result))]
		)
		quit(2)
		return

	var failures := result as Array
	if failures.is_empty():
		quit(0)
		return

	for failure: Variant in failures:
		printerr("[ASSERT] %s" % failure)
	quit(1)
