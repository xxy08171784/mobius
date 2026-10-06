class_name EnemyActionDef
extends Resource
## 敌人单个行动的规则定义（行为表的一行）。只读。
## 依据：development_split.md §3 B3（蓄力/普通/接近）；§5.6 原规则不在仓库内，本文件为据此设计的 MVP。

enum Kind {
	ATTACK,     # 普通：对锁定目标造成伤害（可多段 hit_count）
	APPROACH,   # 接近：朝目标移动（锁定格子；执行时按当前目标重算）
	CHARGE,     # 蓄力：本回合锁定目标并预告，蓄满后释放
	DEFEND,     # 防御：获得护盾
	DASH,       # 冲撞：朝目标移动，伤害 = damage + 移动步数 × dash_damage_per_step
	SUMMON,     # 召唤：从召唤池在玩家附近生成一只小怪
	PULL,       # 拖拽：把最近玩家朝自己拉 move_steps 格，伤害 = damage + 移动步数 × dash_damage_per_step
}

enum TargetPolicy {
	PLAYER,   # 取最近的玩家单位（确定性）
	SELF,     # 锁自身
	NONE,     # 无目标
}

@export var id: StringName = &""
@export var kind: Kind = Kind.ATTACK
@export var target_policy: TargetPolicy = TargetPolicy.PLAYER

## 射程（配合 range_shape）。ATTACK 判定用；APPROACH 忽略。
@export var range: int = 1

## 射程形状（方框含对角 / 菱形曼哈顿 / 无视距离）。决定命中判定与威胁格显示。
##   BOX: range=1 -> 3×3、range=2 -> 5×5（含对角）；UNLIMITED: 忽略 range。
@export var range_shape: BoardQuery.RangeShape = BoardQuery.RangeShape.BOX

@export var requires_los: bool = false

## APPROACH：是否"风筝"——能打到目标时就尽量远离，否则照常接近。
## 远程怪设为 true，近战保持 false。
@export var kiting: bool = false

## ATTACK/CHARGE 的预告伤害；DEFEND 的护盾值。
@export var damage: int = 0
@export var block: int = 0

## ATTACK 多段次数：同一次攻击重复 damage 次（驽俑强射 4×2 -> damage=4, hit_count=2）。
@export var hit_count: int = 1

## DASH（横冲直撞）：每移动一步额外伤害。总伤害 = damage + 移动步数 × 本值。
@export var dash_damage_per_step: int = 3

## ATTACK/CHARGE 命中后附带施加的状态（为空则只造成伤害）。
@export var apply_status_id: StringName = &""
@export var apply_status_stacks: int = 1
@export var apply_status_duration: int = 1

## CHARGE：蓄力回合数（跨回合推进由回合系统处理，Phase 3）。
@export var charge_turns: int = 0

## APPROACH：单次接近步数上限。
@export var move_steps: int = 1

## 行动前朝当前玩家推进的步数（近战逼近 / 远程风筝）。仅 ATTACK 用：
## DASH 自带移动、DEFEND/SUMMON/CHARGE 保持 0。>0 时敌人每回合"先移动再出招"。
@export var advance_steps: int = 0

## 随机伤害区间：`damage_max >= damage_min` 且 max>0 时，执行时在 [min,max] 内掷；否则用固定 `damage`。
@export var damage_min: int = 0
@export var damage_max: int = 0

## 随机护盾区间：DEFEND 用，规则同上；否则用固定 `block`。
@export var block_min: int = 0
@export var block_max: int = 0

## DEFEND 是否同时清除自身所有负面状态（阴气护体）。
@export var cleanse: bool = false

## ATTACK 是否贯穿：命中主目标后，主目标"身后一格"若有玩家阵营单位，则追加一次同额伤害（阴兵过境）。
@export var pierce: bool = false
