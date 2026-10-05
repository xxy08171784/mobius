extends Node
## 存档读写门面。autoload。
## user://profile.json  user://settings.cfg  user://runs/current.json(.bak)
## 原子写：临时文件 -> 校验可读 -> 保留旧档备份 -> 替换；处理读写失败。

const PROFILE_PATH := "user://profile.json"
const RUN_PATH := "user://runs/current.json"
const RUN_BACKUP_PATH := "user://runs/current.bak"


func save_profile(profile: RefCounted) -> bool:
	# TODO: ProfileState 落地后实现。
	return false


func load_profile() -> RefCounted:
	# TODO: ProfileState 落地后实现。
	return null


## 是否存在可续玩的 Run 存档。
func has_run() -> bool:
	return FileAccess.file_exists(RUN_PATH)


## 保存一局 RunState。仅在效果队列排空的安全点（节点边界）调用。
func save_run(run: RefCounted) -> bool:
	if run == null or not run is RunState:
		push_error("SaveService.save_run: expected RunState, got %s" % (type_string(typeof(run)) if run != null else "null"))
		return false
	var data := SaveCodec.new().encode_state(run)
	if data.is_empty():
		push_error("SaveService.save_run: encode failed")
		return false
	return _write_json(RUN_PATH, data)


## 读档；无存档或损坏返回 null。读档后由 RunSession.setup 恢复 RNG 与内容绑定。
func load_run() -> RefCounted:
	var data := _read_json(RUN_PATH)
	if data.is_empty():
		return null
	var loaded: RefCounted = SaveCodec.new().decode_state(data)
	if loaded is RunState:
		return loaded
	return null


## 原子写：临时文件 -> JSON 可解析校验 -> 旧档备份 -> 替换。
func _write_json(path: String, data: Dictionary) -> bool:
	var global_path := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(global_path.get_base_dir())

	var text := JSON.stringify(data)
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveService: cannot open temp file %s" % temp_path)
		return false
	file.store_string(text)
	file.close()

	# 校验：临时文件必须能被 JSON 解析，否则视为写失败，不碰旧档。
	var check := FileAccess.open(temp_path, FileAccess.READ)
	if check == null:
		push_error("SaveService: temp file unreadable %s" % temp_path)
		return false
	var parsed: Variant = JSON.parse_string(check.get_as_text())
	check.close()
	if not parsed is Dictionary:
		push_error("SaveService: temp file failed JSON check")
		return false

	var temp_global := ProjectSettings.globalize_path(temp_path)
	var path_global := ProjectSettings.globalize_path(path)
	var backup_global := ProjectSettings.globalize_path(RUN_BACKUP_PATH)

	# 保留旧档为 .bak（覆盖上次备份）。
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(RUN_BACKUP_PATH):
			DirAccess.remove_absolute(backup_global)
		DirAccess.copy_absolute(path_global, backup_global)

	# 替换：Windows 上 rename 覆盖已存在文件不可靠，先删旧再改，备份兜底。
	DirAccess.remove_absolute(path_global)
	if DirAccess.rename_absolute(temp_global, path_global) != OK:
		push_error("SaveService: rename failed; backup preserved at %s" % RUN_BACKUP_PATH)
		return false
	return true


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}
