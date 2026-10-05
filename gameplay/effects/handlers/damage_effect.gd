class_name DamageEffectHandler
extends EffectHandler
## 基础伤害：合法性 -> StatSystem 统一取整 -> Block -> HP -> 事件/触发 -> 死亡。
## 力量/虚弱/易伤等具体修饰来源尚未冻结，不在此擅自发明字段。


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

	if context.source_unit_id >= 0:
		var source: Variant = EffectStateAccess.get_unit(work_state, context.source_unit_id)
		if source == null or _is_dead(source):
			return _error(&"invalid_source")
	if _is_dead(target):
		return _error(&"invalid_target")

	var params: Dictionary = effect.get("params", {})
	var raw_amount := maxf(0.0, float(params.get("amount", 0.0)))

	# 先接入 B2 的统一 floor/钳制语义；具体攻防修饰以后只替换 flat/percent 输入。
	var final_damage := maxi(0, StatSystem.compute(raw_amount, 0.0, 0.0, 0.0, INF))
	var hp_before := int(EffectStateAccess.get_field(target, &"hp", 0))
	var block_before := maxi(0, int(EffectStateAccess.get_field(target, &"block", 0)))
	var absorbed := mini(block_before, final_damage)
	var hp_damage := final_damage - absorbed
	var block_after := block_before - absorbed
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
		{"amount": final_damage, "absorbed": absorbed, "hp_damage": hp_damage}
	)

	var triggers: Array = [
		_make_trigger(10, target_id, &"on_damaged", context),
	]
	if context.source_unit_id >= 0:
		triggers.append(_make_trigger(10, context.source_unit_id, &"on_deal_damage", context))
	if hp_after == 0:
		triggers.append(_make_trigger(20, target_id, &"on_death", context))

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
