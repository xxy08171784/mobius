class_name SaveMigrator
extends RefCounted
## 存档版本升级。旧 build 读到更高 schema 版本必须拒绝（combat_rules.md §12.5）。

const CURRENT_SCHEMA_VERSION: int = 3


## 是否能被当前 build 加载。版本高于本 build -> 拒绝，不尝试解析。
func can_load(data: Dictionary) -> bool:
	var v := int(data.get("schema_version", 0))
	return v > 0 and v <= CURRENT_SCHEMA_VERSION


## 将旧版数据升级到 CURRENT_SCHEMA_VERSION。
func migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("schema_version", 0))
	if version < CURRENT_SCHEMA_VERSION:
		# v1/v2 没有中断现场，保留旧地图进度迁移到 route；不能凭空还原旧战斗。
		# v3 新增流程事务字段，由 SaveCodec 的缺省值补齐。
		data["schema_version"] = CURRENT_SCHEMA_VERSION
	return data
