class_name StatusRules
extends RefCounted
## Phase 5A 的首批正式状态规则。数值集中在这里，便于策划后续调参/替换为数据字段。
##
## 流血：拥有者回合结束时受到“层数”点伤害，持续时间随后 -1。
## 易伤：存在时受到的普通伤害 +50%。
## 专注：每层令造成的普通伤害 +1。

const BLEED: StringName = &"status.bleed"
const VULNERABLE: StringName = &"status.vulnerable"
const FOCUS: StringName = &"status.focus"
## 中毒：回合结束按总层数受到无视护盾的伤害，随后总层数减 1。
const POISON: StringName = &"status.poison"
## 虚弱：拥有者造成的普通伤害 -25%（来源侧百分比修饰）。
const WEAK: StringName = &"status.weak"
## 减速：玩家回合移动点和敌人主动移动步数每层 -1。
const SLOW: StringName = &"status.slow"
## 缠绕：禁止主动位移，拉拽/击退例外。
const ENTANGLE: StringName = &"status.entangle"
## 腐蚀：拥有者获得的护盾 -25%（施加给玩家，第三幕史莱姆/食尸鬼）。
const CORRODE: StringName = &"status.corrode"
## 着火：火焰 DoT，回合结束按 层数×5 掉血并减层（第三幕旱魃）。
const IGNITE: StringName = &"status.ignite"
## 眩晕（cxm 卡牌系统）。
const STUN: StringName = &"status.stun"
## 刀痕（cxm 卡牌系统）。
const KNIFE_MARK: StringName = &"status.knife_mark"
## 怒火：每层令造成的普通伤害 +2（反应 buff，亡灵意志/食尸鬼体质）。
const RAGE: StringName = &"status.rage"

## 回合结束按层数结算伤害的状态（DoT）。数组顺序即结算顺序（确定性）。
const DOT_STATUSES: Array[StringName] = [BLEED, POISON, IGNITE]


const VULNERABLE_DAMAGE_PERCENT := 0.5
const FOCUS_DAMAGE_PER_STACK := 1.0
## 虚弱：造成伤害的百分比修正。
const WEAK_OUTGOING_PERCENT := -0.25
## 腐蚀：获得护盾的百分比修正。
const CORRODE_BLOCK_PERCENT := -0.25
## 着火：每层结算的火焰伤害。
const IGNITE_DAMAGE_PER_STACK := 5
## 怒火：每层结算的普通伤害加成。
const RAGE_DAMAGE_PER_STACK := 2


static func stacks(unit: UnitState, status_id: StringName) -> int:
	if unit == null:
		return 0
	var total := 0
	for instance_id: int in unit.status_ids():
		var status := unit.get_status(instance_id)
		if status != null and status.status_id == status_id and not status.is_expired():
			total += maxi(0, status.stacks)
	return total


static func outgoing_damage_flat(unit: UnitState) -> float:
	return float(stacks(unit, FOCUS)) * FOCUS_DAMAGE_PER_STACK \
		+ float(stacks(unit, RAGE)) * RAGE_DAMAGE_PER_STACK \
		+ float(unit.get_resource(&"courage") if unit != null else 0)


static func incoming_damage_percent(unit: UnitState) -> float:
	return VULNERABLE_DAMAGE_PERCENT if stacks(unit, VULNERABLE) > 0 else 0.0


## 虚弱：拥有者造成普通伤害的百分比修饰（-25%）。作为**来源侧**修正进伤害管线。
static func outgoing_damage_percent(unit: UnitState) -> float:
	if unit == null:
		return 0.0
	return WEAK_OUTGOING_PERCENT if stacks(unit, WEAK) > 0 else 0.0


## 腐蚀：拥有者获得护盾的百分比修饰（-25%）。作为**获得方**修正进护盾管线。
static func outgoing_block_percent(unit: UnitState) -> float:
	if unit == null:
		return 0.0
	return CORRODE_BLOCK_PERCENT if stacks(unit, CORRODE) > 0 else 0.0


## 减速：开局移动力扣减（= 层数）。
static func move_penalty(unit: UnitState) -> int:
	return 0 if unit == null else stacks(unit, SLOW)


## 缠绕：是否被锁死移动。
static func move_locked(unit: UnitState) -> bool:
	return unit != null and stacks(unit, ENTANGLE) > 0


static func owner_turn_end_damage(unit: UnitState) -> int:
	var total := 0
	for status_id: StringName in DOT_STATUSES:
		total += dot_tick_damage(status_id, stacks(unit, status_id))
	return total


## 单个 DoT 的一次结算伤害：着火 = 层数×5，其余（流血/中毒）= 层数。
static func dot_tick_damage(status_id: StringName, stacks_count: int) -> int:
	if status_id == IGNITE:
		return stacks_count * IGNITE_DAMAGE_PER_STACK
	return stacks_count


## 无视护甲的 DoT（伤害不吃护盾）：中毒。经伤害管线 ignore_block 参数实现（§6）。
static func is_armor_ignoring(status_id: StringName) -> bool:
	return status_id == POISON


## 层数驱动的 DoT（回合结束掉血后**减层数**，而非减持续）：中毒、着火。
## 流血则相反：吃护盾、按持续递减。
static func is_stack_decaying(status_id: StringName) -> bool:
	return status_id == POISON or status_id == IGNITE


## 总层数仅减 amount，按稳定实例顺序消耗，避免多个来源额外加快衰减。
static func decay_stacks(unit: UnitState, status_id: StringName, amount: int = 1) -> void:
	if unit == null:
		return
	for instance_id: int in unit.status_ids():
		var status := unit.get_status(instance_id)
		if status != null and status.status_id == status_id:
			var removed := mini(status.stacks, maxi(0, amount))
			status.stacks -= removed
			amount -= removed
			if amount <= 0:
				break


static func is_stunned(unit: UnitState) -> bool:
	return stacks(unit, STUN) > 0


static func slow_penalty(unit: UnitState) -> int:
	return move_penalty(unit)


static func is_negative(status_id: StringName) -> bool:
	return status_id in [BLEED, POISON, VULNERABLE, STUN, SLOW, KNIFE_MARK, WEAK, ENTANGLE, CORRODE, IGNITE]


static func has_negative_status(unit: UnitState) -> bool:
	if unit == null:
		return false
	for instance_id: int in unit.status_ids():
		var status := unit.get_status(instance_id)
		if status != null and not status.is_expired() and is_negative(status.status_id):
			return true
	return false


static func movement_budget(unit: UnitState, base: int) -> int:
	return 0 if move_locked(unit) else maxi(0, base - move_penalty(unit))
