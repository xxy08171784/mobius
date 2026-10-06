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
const ResourceEffectHandlerScript = preload("res://gameplay/effects/handlers/resource_effect.gd")
const HealEffectHandlerScript = preload("res://gameplay/effects/handlers/heal_effect.gd")

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
	register_handler(ResourceEffectHandlerScript.new())
	register_handler(HealEffectHandlerScript.new())


func register_handler(handler: EffectHandler) -> void:
	_handlers[handler.get_type_key()] = handler


func supports(type_key: StringName) -> bool:
	return _handlers.has(type_key)


func resolve(state_in: Variant, plan: Variant, rng_in: Variant, reactions: Dictionary = {}) -> Dictionary:
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
			return _process_trigger(trigger, work_state, battle_rng, events, reactions)
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
	events: EventBatch,
	reactions: Dictionary
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

	# 被动反应：仅对"非反应产出"的触发展开（限深一层，防反伤互相反弹死循环）。
	if not bool(trigger.get("from_reaction", false)) and not reactions.is_empty():
		for raw_effect: Variant in _reaction_effects(trigger, work_state, reactions):
			var effect := _normalize_effect(raw_effect)
			if effect.is_empty():
				return {"ok": false, "error_code": ERROR_INVALID_PLAN, "triggers": []}
			var context := _context_for_effect(trigger_context, effect)
			var result := _apply_effect(work_state, effect, context, battle_rng, events)
			if not bool(result.get("ok", false)):
				return result
			for child: Variant in result.get("triggers", []):
				if child is Dictionary:
					(child as Dictionary)["from_reaction"] = true
				produced_triggers.append(child)
	return {"ok": true, "triggers": produced_triggers}


## 按触发事件取相关单位的反应，展开成具体效果 dict。on_any_death 广播全场。
func _reaction_effects(trigger: Dictionary, work_state: Variant, reactions: Dictionary) -> Array:
	var out: Array = []
	var event_type := StringName(String(trigger.get("event_type", &"")))
	if event_type.is_empty() or reactions.is_empty():
		return out
	var context: Variant = trigger.get("context")
	var attacker_id := -1
	if context is EffectContext:
		attacker_id = (context as EffectContext).source_unit_id

	var instance_id := int(trigger.get("instance_id", -1))
	var death_cell := BoardState.INVALID_CELL
	var raw_cell: Variant = trigger.get("cell")
	if raw_cell is Vector2i:
		death_cell = raw_cell as Vector2i
	var board := EffectStateAccess.get_board(work_state)

	# [反应单位, 需匹配的事件类型]：
	#   on_death -> 死亡单位自身的 on_death；另**广播**全场单位的 on_any_death（食尸鬼体质）
	#   其它      -> 触发单位自身的同名反应
	var pairs: Array = []
	if event_type == &"on_death":
		if instance_id >= 0:
			pairs.append([instance_id, &"on_death"])
		for uid: int in _all_unit_ids(work_state):
			pairs.append([uid, &"on_any_death"])
	elif event_type == &"on_any_death":
		for uid: int in _all_unit_ids(work_state):
			pairs.append([uid, &"on_any_death"])
	elif instance_id >= 0:
		pairs.append([instance_id, event_type])

	for pair: Array in pairs:
		var reactor_id: int = int(pair[0])
		var want_event: StringName = pair[1]
		var reactor_cell := BoardState.INVALID_CELL
		if board != null:
			reactor_cell = board.get_unit_cell(reactor_id)
		if reactor_cell == BoardState.INVALID_CELL and reactor_id == instance_id:
			reactor_cell = death_cell
		for reaction: Variant in reactions.get(reactor_id, []):
			if reaction is ReactionDef and (reaction as ReactionDef).event_type == want_event:
				out.append_array(
					_expand_reaction(reaction as ReactionDef, reactor_id, attacker_id, work_state, reactor_cell)
				)
	return out


## 把一条反应展开为效果 dict 列表（解出动态目标）。
func _expand_reaction(reaction: ReactionDef, reactor_id: int, attacker_id: int, work_state: Variant, reactor_cell: Vector2i) -> Array:
	var out: Array = []
	var reactor: Variant = EffectStateAccess.get_unit(work_state, reactor_id)
	if reactor == null:
		return out
	var reactor_alive := int(EffectStateAccess.get_field(reactor, &"hp", 0)) > 0
	match reaction.kind:
		ReactionDef.Kind.DAMAGE_ATTACKER:
			if attacker_id >= 0 and attacker_id != reactor_id:
				out.append({
					"type_key": &"damage",
					"target": attacker_id,
					"params": {"amount": reaction.amount, "ignore_block": reaction.ignore_block},
				})
		ReactionDef.Kind.AOE_AROUND_SELF:
			for uid: int in _opponents_in_box(work_state, reactor_id, reactor_cell, reaction.radius):
				out.append({
					"type_key": &"damage",
					"target": uid,
					"params": {"amount": reaction.amount, "ignore_block": reaction.ignore_block},
				})
		ReactionDef.Kind.HEAL_SELF:
			if reactor_alive:
				out.append({"type_key": &"heal", "target": reactor_id, "params": {"amount": reaction.amount}})
		ReactionDef.Kind.BUFF_SELF:
			if reactor_alive and not reaction.status_id.is_empty():
				out.append(_status_effect(reactor_id, reaction))
		ReactionDef.Kind.BUFF_ALLIES:
			if not reaction.status_id.is_empty():
				for uid: int in _ally_ids(work_state, reactor_id):
					out.append(_status_effect(uid, reaction))
	return out


func _status_effect(unit_id: int, reaction: ReactionDef) -> Dictionary:
	return {
		"type_key": &"apply_status",
		"target": unit_id,
		"status_id": reaction.status_id,
		"params": {"stacks": maxi(1, reaction.stacks), "duration": maxi(1, reaction.duration)},
	}


func _all_unit_ids(work_state: Variant) -> Array[int]:
	var out: Array[int] = []
	var units: Variant = EffectStateAccess.get_field(work_state, &"units")
	if units is Dictionary:
		for key: Variant in (units as Dictionary):
			out.append(int(key))
	out.sort()
	return out


## 以 center 为中心的方框（切比雪夫）半径内、与 reactor 敌对阵营的单位 ID（确定性排序）。
func _opponents_in_box(work_state: Variant, reactor_id: int, center: Vector2i, radius: int) -> Array[int]:
	var out: Array[int] = []
	var board := EffectStateAccess.get_board(work_state)
	if board == null or center == BoardState.INVALID_CELL:
		return out
	var reactor: Variant = EffectStateAccess.get_unit(work_state, reactor_id)
	var reactor_team := int(EffectStateAccess.get_field(reactor, &"team", -1))
	for y: int in range(center.y - radius, center.y + radius + 1):
		for x: int in range(center.x - radius, center.x + radius + 1):
			var cell := Vector2i(x, y)
			if not board.is_inside(cell):
				continue
			var uid := board.get_unit_at(cell)
			if uid < 0 or uid == reactor_id:
				continue
			var other: Variant = EffectStateAccess.get_unit(work_state, uid)
			if other != null and int(EffectStateAccess.get_field(other, &"team", -1)) != reactor_team:
				out.append(uid)
	out.sort()
	return out


## 与 reactor 同阵营（含自身）的单位 ID。
func _ally_ids(work_state: Variant, reactor_id: int) -> Array[int]:
	var out: Array[int] = []
	var reactor: Variant = EffectStateAccess.get_unit(work_state, reactor_id)
	if reactor == null:
		return out
	var team := int(EffectStateAccess.get_field(reactor, &"team", -1))
	for uid: int in _all_unit_ids(work_state):
		var u: Variant = EffectStateAccess.get_unit(work_state, uid)
		if u != null and int(EffectStateAccess.get_field(u, &"team", -1)) == team \
				and int(EffectStateAccess.get_field(u, &"hp", 0)) > 0:
			out.append(uid)
	return out


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
	var params: Dictionary = effect.get("params", {})
	var target_mode := StringName(String(params.get("target_mode", "")))
	if target_mode == &"source":
		context.target = context.source_unit_id
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
