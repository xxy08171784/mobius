class_name SaveService
extends Node
## 存档读写门面。autoload。
## user://profile.json  user://settings.cfg  user://runs/current.json(.bak)
## 原子写：临时文件 -> 校验 -> 保留备份 -> 替换；处理读写失败。

const PROFILE_PATH := "user://profile.json"
const RUN_PATH := "user://runs/current.json"
const RUN_BACKUP_PATH := "user://runs/current.bak"


func save_profile(_profile: RefCounted) -> bool:
	# TODO
	return false


func load_profile() -> RefCounted:
	# TODO
	return null


func save_run(_run: RefCounted) -> bool:
	# TODO: 仅在效果队列排空的安全点保存。
	return false


func load_run() -> RefCounted:
	# TODO
	return null
