class_name DamageEffectHandler
extends EffectHandler
## 基础伤害：合法性 -> 状态修饰 -> StatSystem 统一取整 -> Block -> HP -> 事件/触发 -> 死亡。


func get_type_key() -> StringName:
	return &"damage"


func apply(
	work_state: Variant,
	effect: Dictionary,
	context: EffectContext,
	_rng: RandomNumberGenerator
) -> Dictionary:
	var target_id := EffectStateAccess.target_unit_id(context)
	var target: Variant = EffectStateAccess.get_unit(work_state, target_id)
	if target == null:
		return _error(&"invalid_target")

	var source: Variant = null
	if context.source_unit_id >= 0:
		source = EffectStateAccess.get_unit(work_state, context.source_unit_id)
		if source == null or _is_dead(source):
			return _error(&"invalid_source")
	if _is_dead(target):
		return _error(&"invalid_target")

	var params: Dictionary = effect.get("params", {})
	var raw_amount := maxf(0.0, float(params.get("amount", 0.0)))
	var flat_bonus := 0.0
	var percent_bonus := 0.0
	if not bool(params.get("ignore_status_modifiers", false)):
		if source is UnitState:
			flat_bonus += StatusRules.outgoing_damage_flat(source as UnitState)
		if target is UnitState:
			percent_bonus += StatusRules.incoming_damage_percent(target as UnitState)

	var final_damage := maxi(0, StatSystem.compute(raw_amount, flat_bonus, percent_bonus, 0.0, INF))
	var hp_before := int(EffectStateAccess.get_field(target, &"hp", 0))
	var block_before := maxi(0, int(EffectStateAccess.get_field(target, &"block", 0)))
	var ignore_block := bool(params.get("ignore_block", false))
	# ignore_block=true：无视护甲（中毒、刺透等不吃护盾）。
	var absorbed := 0 if ignore_block else mini(block_before, final_damage)

	var hp_damage := final_damage - absorbed
	var block_after := block_before if ignore_block else block_before - absorbed
	var hp_after := maxi(0, hp_before - hp_damage)

	if not EffectStateAccess.set_field(target, &"block", block_after):
		return _error(&"missing_block_field")
	if not EffectStateAccess.set_field(target, &"hp", hp_after):
		return _error(&"missing_hp_field")
	if hp_after == 0 and EffectStateAccess.has_field(target, &"alive"):
		EffectStateAccess.set_field(target, &"alive", false)

	var seq := EffectStateAccess.allocate_event_seq(work_state)
	var event := EffectEvent.create(
		seq,
		&"damage",
		context.source_unit_id,
		target_id,
		{"hp": hp_before, "block": block_before},
		{"hp": hp_after, "block": block_after},
		{
			"amount": final_damage,
			"raw_amount": raw_amount,
			"flat_bonus": flat_bonus,
			"percent_bonus": percent_bonus,
			"absorbed": absorbed,
			"hp_damage": hp_damage,
			"ignore_block": ignore_block,
			"status_id": params.get("status_id", &""),
		}
	)

	var triggers: Array = [
		_make_trigger(10, target_id, &"on_damaged", context),
	]
	if context.source_unit_id >= 0:
		triggers.append(_make_trigger(10, context.source_unit_id, &"on_deal_damage", context))
	if hp_after == 0:
		triggers.append(_make_trigger(20, target_id, &"on_death", context))
		# 死亡即离场：尸体不占格（combat_rules §9）。胜利判定按存活过滤（units），不受影响。
		var board: Variant = EffectStateAccess.get_board(work_state)
		if board != null:
			board.remove_unit(target_id)

	return {"ok": true, "events": [event], "triggers": triggers}


func _is_dead(unit: Variant) -> bool:
	if EffectStateAccess.has_field(unit, &"alive") and not bool(EffectStateAccess.get_field(unit, &"alive", true)):
		return true
	return int(EffectStateAccess.get_field(unit, &"hp", 0)) <= 0


func _make_trigger(phase: int, instance_id: int, event_type: StringName, context: EffectContext) -> Dictionary:
	return {
		"phase": phase,
		"priority": 0,
		"instance_id": instance_id,
		"event_type": event_type,
		"context": context,
		"effects": [],
	}


func _error(code: StringName) -> Dictionary:
	return {"ok": false, "error_code": code, "events": [], "triggers": []}
