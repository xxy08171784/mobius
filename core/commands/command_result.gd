class_name CommandResult
extends RefCounted
## submit() 的返回值：接受/拒绝、错误码、事件批、状态版本。
## 失败时必须零副作用（不改权威状态、不推进正式 RNG）。

enum ErrorCode {
	OK,
	DUPLICATE,      # 命令 ID 已见过
	PHASE,          # 当前阶段不接受输入
	BUSY,           # 命令锁置位（结算/表现中）
	ACTOR,          # 施法者不存在/已死亡/阵营错误
	COMMAND_TYPE,   # 该阶段不允许此命令类型
	COST,           # 费用/行动点不足
	TARGET,         # 目标非法
	COMBO,          # 组合整体非法
	OVERFLOW,       # 触发处理超上限
}

var accepted: bool = false
var error_code: ErrorCode = ErrorCode.OK

## 失败时用于 UI 的本地化文本键（存档不依赖具体文案）。
var text_key: StringName = &""

## 结算成功后的事件批（有序）；失败时为 null。
var events: EventBatch = null

## 提交后的权威状态版本，供 UI 拒绝过期预览。
var state_version: int = 0
