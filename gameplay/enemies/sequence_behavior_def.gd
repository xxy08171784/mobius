class_name SequenceBehaviorDef
extends BehaviorDef
## 循环行动序列（MVP 默认行为）。按 sequence 顺序取，取尽回绕。
## 蓄力类行动的跨回合推进由回合系统处理（Phase 3），本类只管"第 step 步是哪个行动"。

@export var sequence: Array[EnemyActionDef] = []


func action_def_for(step: int) -> EnemyActionDef:
	if sequence.is_empty():
		return null
	return sequence[posmod(step, sequence.size())]
