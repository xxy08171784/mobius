extends Node
## 校验封装 + 同目录临时文件 + 上一份有效备份；Run/Profile 使用同一可靠读写实现。
signal persistence_error(message: String)
signal backup_recovered(path: String)
const PROFILE_PATH := "user://profile.json"
const RUN_PATH := "user://runs/current.json"
const RUN_BACKUP_PATH := "user://runs/current.bak"
var run_path: String = RUN_PATH
var profile_path: String = PROFILE_PATH
var last_error: String = ""
var recovered_from_backup: bool = false


func save_profile(profile: RefCounted) -> bool:
	return profile is ProfileState and _write_json(profile_path, (profile as ProfileState).to_dict())


func load_profile() -> ProfileState:
	var profile := ProfileState.from_dict(_read_json(profile_path))
	if profile != null:
		return profile
	var backup := _backup_path(profile_path)
	profile = ProfileState.from_dict(_read_json(backup))
	if profile != null:
		_recover(backup, profile_path)
	return profile


func has_run() -> bool:
	var run := load_run() as RunState
	return run != null and run.is_active()


func save_run(run: RefCounted) -> bool:
	if not run is RunState:
		return _error("无效的冒险状态。")
	return _write_json(run_path, SaveCodec.new().encode_state(run))


func load_run(include_settled: bool = false) -> RefCounted:
	recovered_from_backup = false
	var primary := _read_json(run_path)
	if int(primary.get("schema_version", 0)) > SaveMigrator.CURRENT_SCHEMA_VERSION:
		_error("存档版本比当前游戏更新，请使用更新版本的游戏读取。")
		return null
	var run := _decode_run(primary)
	if run == null:
		var backup := _backup_path(run_path)
		run = _decode_run(_read_json(backup))
		if run != null:
			recovered_from_backup = true
			_recover(backup, run_path)
	if run != null:
		var profile := load_profile()
		if not include_settled and profile != null and profile.completed_runs.has(run.instance_id):
			return null
	return run


func _decode_run(data: Dictionary) -> RunState:
	if not SaveMigrator.new().can_load(data) or data.get("state_type", "") != "RunState":
		return null
	var payload: Variant = data.get("state")
	if not payload is Dictionary:
		return null
	for key: String in ["map", "deck", "relics", "rng_snapshot", "hp", "seed"]:
		if not payload.has(key):
			return null
	var run := SaveCodec.new().decode_state(data) as RunState
	if run == null or run.map == null or run.map.nodes.is_empty() or run.max_hp < 1:
		return null
	if not [&"route", &"deployment", &"battle", &"rest", &"shop", &"event", &"treasure", &"reward", &"run_over"].has(run.flow_phase):
		return null
	if run.flow_phase == &"battle" and (run.pending_battle_id < 0 or not run.pending_payload.has("battle")):
		return null
	return run


func archive_run(run: RunState) -> bool:
	if run == null or run.instance_id.is_empty():
		return _error("无法归档：缺少冒险编号。")
	var archive := run_path.get_base_dir().path_join("history").path_join(run.instance_id.validate_filename() + ".json")
	if not _write_json(archive, SaveCodec.new().encode_state(run)):
		return false
	return clear_run()


func clear_run() -> bool:
	# 先清备份：即使后续主档删除失败，也不会在读档时复活上一战。
	for path: String in [_backup_path(run_path), run_path + ".tmp", run_path]:
		if FileAccess.file_exists(path) and DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) != OK:
			return _error("无法清理存档：" + path)
	return true


func _write_json(path: String, data: Dictionary) -> bool:
	last_error = ""
	var global_path := ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(global_path.get_base_dir()) != OK:
		return _error("无法创建存档目录。")
	var payload := JSON.stringify(data)
	var envelope := {"payload": payload, "sha256": payload.sha256_text()}
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return _error("无法写入临时存档：" + temp)
	file.store_string(JSON.stringify(envelope))
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or _read_json(temp).is_empty():
		return _error("临时存档校验失败。")
	var backup := _backup_path(path)
	# 不用损坏的主档覆盖有效备份。
	if not _read_json(path).is_empty():
		if DirAccess.copy_absolute(global_path, ProjectSettings.globalize_path(backup)) != OK:
			return _error("备份失败；旧存档保持不变。")
	if not _replace_file(temp, path):
		# Windows 替换失败时恢复主文件，保留 temp 供诊断（读档绝不自动选未提交的 temp）。
		if not FileAccess.file_exists(path) and FileAccess.file_exists(backup):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(backup), global_path)
		return _error("替换存档失败；已保留上一份备份。")
	return true


func _replace_file(source: String, destination: String) -> bool:
	var target := ProjectSettings.globalize_path(destination)
	if FileAccess.file_exists(destination) and DirAccess.remove_absolute(target) != OK:
		return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(source), target) == OK


func _recover(backup: String, destination: String) -> bool:
	var temp := destination + ".recovery"
	if DirAccess.copy_absolute(ProjectSettings.globalize_path(backup), ProjectSettings.globalize_path(temp)) != OK:
		return _error("备份可读，但无法恢复主存档。")
	if not _replace_file(temp, destination):
		return _error("备份可读，但主存档恢复失败。")
	backup_recovered.emit(destination)
	return true


func _backup_path(path: String) -> String:
	return path.get_basename() + ".bak"


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {}
	if parsed.has("payload"):
		var payload := String(parsed.get("payload", ""))
		if payload.sha256_text() != String(parsed.get("sha256", "")):
			return {}
		parsed = JSON.parse_string(payload)
	return parsed if parsed is Dictionary else {}


func _error(message: String) -> bool:
	last_error = message
	persistence_error.emit(message)
	return false
