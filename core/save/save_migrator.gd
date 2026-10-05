class_name SaveMigrator
extends RefCounted
## 存档版本升级。旧 build 读到更高 schema 版本必须拒绝（combat_rules.md §12.5）。

const CURRENT_SCHEMA_VERSION: int = 1


## 是否能被当前 build 加载。版本高于本 build -> 拒绝，不尝试解析。
func can_load(data: Dictionary) -> bool:
	var v := int(data.get("schema_version", 0))
	return v > 0 and v <= CURRENT_SCHEMA_VERSION


## 将旧版数据升级到 CURRENT_SCHEMA_VERSION。
func migrate(data: Dictionary) -> Dictionary:
	# TODO: 按 schema_version 逐级升级。
	return data
