class_name EffectResolver
extends RefCounted
## A1 结算唯一入口。
## resolve() 不改 state_in/rng_in：只操作克隆；任一错误都丢弃工作快照。

const ERROR_OK: StringName = &"ok"
const ERROR_INVALID_STATE: StringName = &"invalid_state"
const ERROR_INVALID_RNG: StringName = &"invalid_rng"
const ERROR_INVALID_PLAN: StringName = &"invalid_plan"
const ERROR_UNKNOWN_EFFECT: StringName = &"unknown_effect"
const ERROR_TRIGGER_OVERFLOW: StringName = &"trigger_overflow"

var _handlers: Dictionary = {}


func _init() -> void:
	register_handler(DamageEffectHandler.new())
	register_handler(BlockEffectHandler.new())
	register_handler(DrawEffectHandler.new())
	register_handler(MoveEffectHandler.new())
	register_handler(PushEffectHandler.new())
	register_handler(ApplyStatusEffectHandler.new())
	register_handler(PullEffectHandler.new())
	register_handler(CleanseEffectHandler.new())


func register_handler(handler: EffectHandler) -> void:
	_handlers[handler.get_type_key()] = handler


func resolve(state_in: Variant, plan: Variant, rng_in: Variant) -> Dictionary:
	var state_clone := _clone_state(state_in)
	if not bool(state_clone.get("ok", false)):
		return _failure(state_in, rng_in, ERROR_INVALID_STATE)
	var rng_clone := _clone_rng(rng_in)
	if not bool(rng_clone.get("ok", false)):
		return _failure(state_in, rng_in, ERROR_INVALID_RNG)

	var work_state: Variant = state_clone["value"]
	var rng_out: Variant = rng_clone["owner"]
	var battle_rng: RandomNumberGenerator = rng_clone["rng"]
	var normalized_plan := _normalize_plan(plan)
	if not bool(normalized_plan.get("ok", false)):
		return _failure(state_in, rng_in, ERROR_INVALID_PLAN)

	var events := EventBatch.new()
	var trigger_system := TriggerSystem.new()
	trigger_system.enqueue_many(normalized_plan.get("triggers", []))
	var base_context: EffectContext = normalized_plan["context"]

	for raw_effect: Variant in normalized_plan["effects"]:
		var effect := _normalize_effect(raw_effect)
		if effect.is_empty():
			return _failure(state_in, rng_in, ERROR_INVALID_PLAN)
		var context := _context_for_effect(base_context, effect)
		var applied := _apply_effect(work_state, effect, context, battle_rng, events)
		if not bool(applied.get("ok", false)):
			return _failure(
				state_in,
				rng_in,
				StringName(String(applied.get("error_code", ERROR_UNKNOWN_EFFECT)))
			)
		trigger_system.enqueue_many(applied.get("triggers", []))

	var trigger_result := trigger_system.drain(
		func(trigger: Dictionary) -> Dictionary:
			return _process_trigger(trigger, work_state, battle_rng, events)
	)
	if not bool(trigger_result.get("ok", false)):
		var code: StringName = ERROR_TRIGGER_OVERFLOW if bool(trigger_result.get("overflow", false)) else StringName(String(trigger_result.get("error_code", "trigger_error")))
		return _failure(state_in, rng_in, code)

	return {
		"ok": true,
		"error_code": ERROR_OK,
		"state_out": work_state,
		"rng_out": rng_out,
		"events": events,
		"processed_triggers": int(trigger_result.get("processed", 0)),
	}


func _apply_effect(
	work_state: Variant,
	effect: Dictionary,
	context: EffectContext,
	battle_rng: RandomNumberGenerator,
	events: EventBatch
) -> Dictionary:
	var type_key := StringName(String(effect.get("type_key", "")))
	var handler: EffectHandler = _handlers.get(type_key)
	if handler == null:
		return {"ok": false, "error_code": ERROR_UNKNOWN_EFFECT, "triggers": []}
	var result: Dictionary = handler.apply(work_state, effect, context, battle_rng)
	if not bool(result.get("ok", false)):
		return result
	for event: Variant in result.get("events", []):
		if event is GameEvent:
			events.push_back(event)
	return result


func _process_trigger(
	trigger: Dictionary,
	work_state: Variant,
	battle_rng: RandomNumberGenerator,
	events: EventBatch
) -> Dictionary:
	var trigger_context := EffectContext.new()
	var stored_context: Variant = trigger.get("context")
	if stored_context is EffectContext:
		trigger_context = (stored_context as EffectContext).duplicate_context()
	elif stored_context is Dictionary:
		trigger_context = EffectContext.from_dictionary(stored_context)
	trigger_context.depth += 1
	if trigger_context.root_trigger_id == 0:
		trigger_context.root_trigger_id = int(trigger.get("instance_id", 0))

	var produced_triggers: Array = []
	for raw_effect: Variant in trigger.get("effects", []):
		var effect := _normalize_effect(raw_effect)
		if effect.is_empty():
			return {"ok": false, "error_code": ERROR_INVALID_PLAN, "triggers": []}
		var context := _context_for_effect(trigger_context, effect)
		var result := _apply_effect(work_state, effect, context, battle_rng, events)
		if not bool(result.get("ok", false)):
			return result
		produced_triggers.append_array(result.get("triggers", []))
	return {"ok": true, "triggers": produced_triggers}


func _normalize_plan(plan: Variant) -> Dictionary:
	if plan is Array:
		return {
			"ok": true,
			"effects": plan,
			"triggers": [],
			"context": EffectContext.new(),
		}
	if not plan is Dictionary:
		return {"ok": false}
	var data := plan as Dictionary
	var context := EffectContext.new()
	var raw_context: Variant = data.get("context")
	if raw_context is EffectContext:
		context = (raw_context as EffectContext).duplicate_context()
	elif raw_context is Dictionary:
		context = EffectContext.from_dictionary(raw_context)
	return {
		"ok": true,
		"effects": data.get("effects", []),
		"triggers": data.get("triggers", []),
		"context": context,
	}


func _normalize_effect(raw_effect: Variant) -> Dictionary:
	if raw_effect is EffectDef:
		return (raw_effect as EffectDef).to_plan_item()
	if raw_effect is Dictionary:
		return (raw_effect as Dictionary).duplicate(true)
	return {}


func _context_for_effect(base: EffectContext, effect: Dictionary) -> EffectContext:
	var context := base.duplicate_context()
	var raw_context: Variant = effect.get("context")
	if raw_context is EffectContext:
		context = (raw_context as EffectContext).duplicate_context()
	elif raw_context is Dictionary:
		context = EffectContext.from_dictionary(raw_context)
	if effect.has("source_unit_id"):
		context.source_unit_id = int(effect["source_unit_id"])
	if effect.has("source_card_uid"):
		context.source_card_uid = int(effect["source_card_uid"])
	if effect.has("target"):
		context.target = effect["target"]
	return context


func _clone_state(state: Variant) -> Dictionary:
	if state is BattleState:
		var clone: RefCounted = SaveCodec.new().clone_state(state)
		return {"ok": clone != null, "value": clone}
	if state is Object and (state as Object).has_method(&"duplicate_state"):
		var custom_clone: Variant = (state as Object).call(&"duplicate_state")
		return {"ok": custom_clone != null, "value": custom_clone}
	if state is Resource:
		return {"ok": true, "value": (state as Resource).duplicate(true)}
	if state is Dictionary:
		return {"ok": true, "value": (state as Dictionary).duplicate(true)}
	return {"ok": false}


func _clone_rng(rng: Variant) -> Dictionary:
	if rng is RngStreams:
		var streams := (rng as RngStreams).clone()
		return {"ok": true, "owner": streams, "rng": streams.battle_rng()}
	if rng is RandomNumberGenerator:
		var copy := RandomNumberGenerator.new()
		copy.seed = (rng as RandomNumberGenerator).seed
		copy.state = (rng as RandomNumberGenerator).state
		return {"ok": true, "owner": copy, "rng": copy}
	return {"ok": false}


func _failure(state_in: Variant, rng_in: Variant, code: StringName) -> Dictionary:
	return {
		"ok": false,
		"error_code": code,
		"state_out": state_in,
		"rng_out": rng_in,
		"events": EventBatch.new(),
		"processed_triggers": 0,
	}
