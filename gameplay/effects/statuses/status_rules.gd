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
## 中毒：与流血同型（拥有者回合结束按层数掉血），只是稳定键不同以便区分文案/来源。
const POISON: StringName = &"status.poison"
const STUN: StringName = &"status.stun"
const SLOW: StringName = &"status.slow"
const KNIFE_MARK: StringName = &"status.knife_mark"

## 回合结束按层数结算伤害的状态（DoT）。数组顺序即结算顺序（确定性）。
const DOT_STATUSES: Array[StringName] = [BLEED, POISON]


const VULNERABLE_DAMAGE_PERCENT := 0.5
const FOCUS_DAMAGE_PER_STACK := 1.0


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
	return float(stacks(unit, FOCUS)) * FOCUS_DAMAGE_PER_STACK


static func incoming_damage_percent(unit: UnitState) -> float:
	return VULNERABLE_DAMAGE_PERCENT if stacks(unit, VULNERABLE) > 0 else 0.0


static func owner_turn_end_damage(unit: UnitState) -> int:
	var total := 0
	for status_id: StringName in DOT_STATUSES:
		total += stacks(unit, status_id)
	return total


## 无视护甲的 DoT（伤害不吃护盾）：中毒。
static func is_armor_ignoring(status_id: StringName) -> bool:
	return status_id == POISON


## 层数驱动的 DoT：中毒回合结束后减层；流血仍按持续时间递减。
static func is_stack_decaying(status_id: StringName) -> bool:
	return status_id == POISON


## 对拥有者身上该 id 的每个状态实例减层（最小 0）。
static func decay_stacks(unit: UnitState, status_id: StringName, amount: int = 1) -> void:
	if unit == null:
		return
	for instance_id: int in unit.status_ids():
		var status := unit.get_status(instance_id)
		if status != null and status.status_id == status_id:
			status.stacks = maxi(0, status.stacks - maxi(0, amount))


static func is_stunned(unit: UnitState) -> bool:
	return stacks(unit, STUN) > 0


static func slow_penalty(unit: UnitState) -> int:
	return 1 if stacks(unit, SLOW) > 0 else 0


static func is_negative(status_id: StringName) -> bool:
	return status_id in [BLEED, POISON, VULNERABLE, STUN, SLOW, KNIFE_MARK]


static func has_negative_status(unit: UnitState) -> bool:
	if unit == null:
		return false
	for instance_id: int in unit.status_ids():
		var status := unit.get_status(instance_id)
		if status != null and not status.is_expired() and is_negative(status.status_id):
			return true
	return false
