extends SceneTree
## Phase 0 手写测试运行器。
## 用法：godot --headless --path . -s res://tests/run_all.gd

const TEST_DIR := "res://tests/rules"
const RUN_ONE := "res://tests/run_one.gd"


func _init() -> void:
	_run_all()


func _run_all() -> void:
	print("[TEST] runner start")
	var test_paths := _collect_test_paths()
	var total := 0
	var failed := 0

	for path: String in test_paths:
		var filename := path.get_file()
		total += 1
		print("[RUN ] %s" % filename)
		var child := _run_isolated(path)
		if bool(child["ok"]):
			print("[PASS] %s" % filename)
		else:
			failed += 1
			print("[FAIL] %s" % filename)
			var output := String(child["output"]).strip_edges()
			if not output.is_empty():
				for line: String in output.split("\n"):
					print("  | %s" % line)

	print("Rule tests: %d total, %d passed, %d failed" % [total, total - failed, failed])
	quit(0 if failed == 0 else 1)


func _collect_test_paths() -> Array[String]:
	var requested := OS.get_cmdline_user_args()
	if not requested.is_empty():
		var explicit: Array[String] = []
		for value: String in requested:
			explicit.append(value)
		return explicit

	var filenames := Array(DirAccess.get_files_at(TEST_DIR))
	filenames.sort()
	var paths: Array[String] = []
	for filename: String in filenames:
		if filename.begins_with("test_") and filename.ends_with(".gd"):
			paths.append(TEST_DIR.path_join(filename))
	return paths


func _run_isolated(test_path: String) -> Dictionary:
	var output: Array = []
	var project_dir := ProjectSettings.globalize_path("res://")
	var args := PackedStringArray([
		"--headless",
		"--path",
		project_dir,
		"-s",
		RUN_ONE,
		"--",
		test_path,
	])
	var exit_code := OS.execute(OS.get_executable_path(), args, output, true)
	var combined := ""
	for chunk: Variant in output:
		combined += str(chunk)

	# Godot 的 GDScript 运行时错误不会可靠地让进程返回非 0。
	# 因此 stderr/stdout 中出现脚本/解析错误也必须算失败，避免“报错后 PASS”。
	var has_script_error := (
		combined.contains("SCRIPT ERROR:")
		or combined.contains("Parse Error:")
		or combined.contains("Failed to load script")
	)
	return {
		"ok": exit_code == 0 and not has_script_error,
		"exit_code": exit_code,
		"output": combined,
	}
