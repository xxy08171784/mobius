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
	return stacks(unit, BLEED)
