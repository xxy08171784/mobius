@abstract
class_name BehaviorDef
extends Resource
## 敌人行为规则基类（@abstract，只读）。可预测行为优先：规则表/FSM，不用行为树。
## 依据 architecture_review §1：BehaviorDef 作为抽象基类；具体行为在子类。
## 降级路径是数据：fallback_action_id（原意图失效时改用）。

@export var id: StringName = &""

## 原意图失效（目标消失/堵路等）时改用的行动 ID；空 = 无降级（返回空意图）。
@export var fallback_action_id: StringName = &""


## 取第 step 步（敌人自增的行动计数）应执行的行动定义；无则返回 null。
@abstract
func action_def_for(step: int) -> EnemyActionDef
