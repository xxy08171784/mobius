class_name ReactionDef
extends Resource
## 被动反应（敌人能力，只读）。某事件发生时触发一组效果。
## 事件由结算管线（EffectResolver 触发队列）发出：
##   on_damaged      拥有者受到伤害（反伤/崩裂）
##   on_deal_damage  拥有者造成伤害（本轮预留，汲血用）
##   on_death        拥有者死亡（自爆/亡灵意志）
##   on_any_death    任意单位死亡（食尸鬼体质，广播全场）
## 反应在触发处理中展开为具体效果并施加；**限深一层**（反应产出的触发不再展开反应，防死循环）。

enum Kind {
	DAMAGE_ATTACKER,   # 对触发来源（攻击者）造成伤害（反伤/崩裂）
	AOE_AROUND_SELF,   # 以自身为中心的方框（切比雪夫，含对角）范围伤害（自爆）
	HEAL_SELF,         # 自愈（复用 cxm 的 heal handler）
	BUFF_SELF,         # 给自身加状态
	BUFF_ALLIES,       # 给同阵营全体加状态（含自身，亡灵意志）
}

## 触发事件键（见类注释）。
@export var event_type: StringName = &""
@export var kind: Kind = Kind.DAMAGE_ATTACKER
## 伤害/治疗量。
@export var amount: int = 0
## AOE_AROUND_SELF：方框半径（切比雪夫；1 = 3×3、2 = 5×5）。
@export var radius: int = 1
## 伤害类是否无视护甲。
@export var ignore_block: bool = false
## BUFF_*：施加的状态与参数。
@export var status_id: StringName = &""
@export var stacks: int = 1
@export var duration: int = 1
