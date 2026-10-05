class_name TurnSystem
extends RefCounted
## 阶段推进的唯一来源。禁止 UI/按钮回调直接修改 BattleState.phase。


## 校验并执行阶段迁移（合法转移见 combat_rules.md §1）。
func transition_to(state: BattleState, target: BattleState.Phase) -> bool:
	if state.is_terminal():
		return false
	state.phase = target
	return true
