@abstract
class_name GameCommand
extends RefCounted
## 玩家/敌人意图的基类。只承载数据，不含结算逻辑。
## 结算由 BattleSession.submit() 在规则层完成（combat_rules.md §3）。
## 见 architecture_review.md：用 @abstract 强制"只能继承"。

## 命令唯一 ID，用于幂等去重（combat_rules.md §12.3）。
var command_id: int = 0

## 发起者 unit ID。
var actor_id: int = -1

## 命令类型稳定键，供校验与日志使用。
@abstract
func get_type_key() -> StringName
