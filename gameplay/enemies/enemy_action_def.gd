class_name EnemyActionDef
extends Resource
## 敌人单个行动的规则定义（行为表的一行）。只读。
## 依据：development_split.md §3 B3（蓄力/普通/接近）；§5.6 原规则不在仓库内，本文件为据此设计的 MVP。

enum Kind {
	ATTACK,     # 普通：对锁定目标造成伤害
	APPROACH,   # 接近：朝目标移动（锁定格子）
	CHARGE,     # 蓄力：本回合锁定目标并预告，蓄满后释放
	DEFEND,     # 防御：获得护盾
}

enum TargetPolicy {
	PLAYER,   # 取最近的玩家单位（确定性）
	SELF,     # 锁自身
	NONE,     # 无目标
}

@export var id: StringName = &""
@export var kind: Kind = Kind.ATTACK
@export var target_policy: TargetPolicy = TargetPolicy.PLAYER

## 射程（Manhattan）。ATTACK 判定用；APPROACH 忽略。
@export var range: int = 1
@export var requires_los: bool = false

## ATTACK/CHARGE 的预告伤害；DEFEND 的护盾值。
@export var damage: int = 0
@export var block: int = 0

## CHARGE：蓄力回合数（跨回合推进由回合系统处理，Phase 3）。
@export var charge_turns: int = 0

## APPROACH：单次接近步数上限。
@export var move_steps: int = 1
