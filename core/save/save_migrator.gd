class_name SaveMigrator
extends RefCounted
## 存档版本升级。旧 build 读到更高 schema 版本必须拒绝（combat_rules.md §12.5）。

const CURRENT_SCHEMA_VERSION: int = 2


## 是否能被当前 build 加载。版本高于本 build -> 拒绝，不尝试解析。
func can_load(data: Dictionary) -> bool:
	var v := int(data.get("schema_version", 0))
	return v > 0 and v <= CURRENT_SCHEMA_VERSION


## 将旧版数据升级到 CURRENT_SCHEMA_VERSION。
func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("schema_version", 0))
	if version < CURRENT_SCHEMA_VERSION:
		# v1 -> v2：本版新增 RunState 类型；BattleState 数据无需字段改动。
		data["schema_version"] = CURRENT_SCHEMA_VERSION
	return data
