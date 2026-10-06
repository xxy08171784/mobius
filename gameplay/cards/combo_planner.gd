class_name ComboPlanner
extends RefCounted
## 组合出牌的纯规划/预演服务。
## 输入 State / Deck / RNG 均不修改；成功返回工作副本与固定执行步骤。

const ERROR_OK: StringName = &"ok"
const ERROR_COMBO: StringName = &"combo"
const ERROR_COST: StringName = &"cost"
const ERROR_TARGET: StringName = &"target"
const ERROR_EFFECT: StringName = &"effect"

var _card_system := CardSystem.new()
var _resolver := EffectResolver.new()


func build_plan(
	state_in: Variant,
	deck_in: DeckState,
	command: PlayCardsCommand,
	card_defs: Dictionary,
	available_resource: int,
	rng_in: Variant,
	target_validator: Callable = Callable()
) -> Dictionary:
	if deck_in == null or command == null or command.card_uids.is_empty():
		return _failure(state_in, deck_in, rng_in, ERROR_COMBO)
	if command.card_uids.size() != command.targets.size():
		return _failure(state_in, deck_in, rng_in, ERROR_TARGET)
	if not bool(deck_in.validate_invariants().get("ok", false)):
		return _failure(state_in, deck_in, rng_in, ERROR_COMBO)
	if state_in is BattleState and not FormalCardRules.validate_command_choices(
		state_in as BattleState, command, card_defs
	):
		return _failure(state_in, deck_in, rng_in, ERROR_COMBO)

	var selected := _collect_selected(deck_in, command.card_uids, card_defs)
	if not bool(selected.get("ok", false)):
		return _failure(state_in, deck_in, rng_in, ERROR_COMBO)

	# 类别约束：多张连出时攻击/招式同类、防御同类；技能/能力不可连出（零副作用拒绝）。
	if not _combo_classes_ok(deck_in, command.card_uids, card_defs):
		return _failure(state_in, deck_in, rng_in, ERROR_COMBO)

	var total_cost := int(selected["total_cost"])
	if total_cost > available_resource:
		return _failure(state_in, deck_in, rng_in, ERROR_COST)
	var combo_metadata := _build_combo_metadata(deck_in, command.card_uids, card_defs)

	var work_state: Variant = _clone_state_for_combo(state_in)
	if work_state == null:
		return _failure(state_in, deck_in, rng_in, ERROR_COMBO)
	var work_deck := _deck_for_work_state(work_state, deck_in)
	var moved := _card_system.move_hand_to_resolving(work_deck, command.card_uids)
	if not bool(moved.get("ok", false)):
		return _failure(state_in, deck_in, rng_in, ERROR_COMBO)
	if work_state is BattleState:
		FormalCardRules.apply_combo_pre_modifiers(
			work_state as BattleState, command, card_defs
		)
		work_deck = _deck_for_work_state(work_state, work_deck)

	var work_rng: Variant = rng_in
	var all_events := EventBatch.new()
	var steps: Array[Dictionary] = []

	for index: int in range(command.card_uids.size()):
		var uid := command.card_uids[index]
		var card := work_deck.get_card(uid)
		var definition := _get_def(card_defs, card.card_id)
		var target: Variant = command.targets[index]
		if not _target_matches_rule(
			work_state,
			command.actor_id,
			definition.get_target_rule(card.upgrade_level),
			target
		):
			return _failure(state_in, deck_in, rng_in, ERROR_TARGET)
		if work_state is BattleState:
			var formal_target := FormalCardRules.validate_target(
				work_state as BattleState,
				command.actor_id,
				definition,
				target
			)
			if not bool(formal_target.get("ok", false)):
				return _failure(state_in, deck_in, rng_in, ERROR_TARGET)

		var target_check := _validate_target(
			target_validator,
			work_state,
			card,
			definition,
			target
		)
		if not bool(target_check.get("ok", false)):
			if bool(target_check.get("fizzle", false)):
				_card_system.finish_resolving(
					work_deck,
					uid,
					definition.should_exhaust(card.upgrade_level)
				)
				steps.append(_make_step(uid, target, definition, true, false))
				continue
			return _failure(state_in, deck_in, rng_in, ERROR_TARGET)

		var terminal_skip := _is_terminal(work_state) and _is_attack_card(card, definition)
		if terminal_skip:
			_card_system.finish_resolving(
				work_deck,
				uid,
				definition.should_exhaust(card.upgrade_level)
			)
			steps.append(_make_step(uid, target, definition, false, true))
			continue

		var metadata := _metadata_for_card(
			combo_metadata,
			definition,
			card,
			uid,
			index
		)
		var formal_result: Dictionary = {}
		if work_state is BattleState:
			formal_result = FormalCardRules.resolve_card(
				work_state as BattleState,
				work_rng,
				command.actor_id,
				card,
				definition,
				target,
				command,
				metadata,
				card_defs
			)
		if bool(formal_result.get("handled", false)):
			if not bool(formal_result.get("ok", false)):
				return _failure(state_in, deck_in, rng_in, ERROR_EFFECT)
			work_state = formal_result["state_out"]
			work_rng = formal_result["rng_out"]
			work_deck = _deck_for_work_state(work_state, work_deck)
			_append_events(all_events, formal_result.get("events"))
		else:
			var effect_plan := {
				"context": {
					"source_unit_id": command.actor_id,
					"source_card_uid": uid,
					"target": target,
					"metadata": metadata,
				},
				"effects": FormalCardRules.prepare_effects(
					card,
					definition,
					(work_state as BattleState).round_index if work_state is BattleState else 0
				),
			}
			var resolved := _resolver.resolve(work_state, effect_plan, work_rng)
			if not bool(resolved.get("ok", false)):
				return _failure(state_in, deck_in, rng_in, ERROR_EFFECT)
			work_state = resolved["state_out"]
			work_rng = resolved["rng_out"]
			work_deck = _deck_for_work_state(work_state, work_deck)
			_append_events(all_events, resolved["events"])
		_update_terminal_if_battle_state(work_state)
		_card_system.finish_resolving(
			work_deck,
			uid,
			definition.should_exhaust(card.upgrade_level)
		)
		steps.append(_make_step(uid, target, definition, false, false))

	if work_state is BattleState:
		FormalCardRules.apply_combo_post_modifiers(work_state, command, card_defs, steps)
	var invariant := work_deck.validate_invariants()
	if not bool(invariant.get("ok", false)):
		return _failure(state_in, deck_in, rng_in, ERROR_COMBO)

	return {
		"ok": true,
		"error_code": ERROR_OK,
		"state_out": work_state,
		"deck_out": work_deck,
		"rng_out": work_rng,
		"events": all_events,
		"steps": steps,
		"cost_spent": total_cost,
		"resource_after": available_resource - total_cost,
		"selected_uids": command.card_uids.duplicate(),
	}


func _clone_state_for_combo(state_in: Variant) -> Variant:
	if state_in is BattleState:
		return SaveCodec.new().clone_state(state_in as BattleState)
	if state_in is Object and (state_in as Object).has_method(&"duplicate_state"):
		return (state_in as Object).call(&"duplicate_state")
	if state_in is Resource:
		return (state_in as Resource).duplicate(true)
	if state_in is Dictionary:
		return (state_in as Dictionary).duplicate(true)
	return state_in


func _deck_for_work_state(state: Variant, fallback: DeckState) -> DeckState:
	var embedded: Variant = EffectStateAccess.get_field(state, &"deck")
	if embedded is DeckState:
		return embedded as DeckState
	# 无内嵌牌堆（例如独立测试桩）时也必须使用副本，保证规划纯函数不污染调用方的权威 DeckState。
	return DeckState.new() if fallback == null else fallback.duplicate_deck()


func build_plan_for_actor(
	state_in: Variant,
	deck_in: DeckState,
	command: PlayCardsCommand,
	card_defs: Dictionary,
	rng_in: Variant,
	resource_key: StringName = &"energy",
	target_validator: Callable = Callable()
) -> Dictionary:
	var actor: Variant = EffectStateAccess.get_unit(state_in, command.actor_id)
	if not actor is UnitState:
		return _failure(state_in, deck_in, rng_in, ERROR_COMBO)
	return build_plan(
		state_in,
		deck_in,
		command,
		card_defs,
		(actor as UnitState).get_resource(resource_key),
		rng_in,
		target_validator
	)


func _collect_selected(deck: DeckState, uids: Array[int], card_defs: Dictionary) -> Dictionary:
	var seen: Dictionary = {}
	var total_cost := 0
	for uid: int in uids:
		if seen.has(uid):
			return {"ok": false}
		seen[uid] = true
		if deck.zone_of(uid) != DeckState.ZONE_HAND:
			return {"ok": false}
		var card := deck.get_card(uid)
		if card == null:
			return {"ok": false}
		var definition := _get_def(card_defs, card.card_id)
		if definition == null or not definition.is_valid():
			return {"ok": false}
		total_cost += card.effective_cost(definition)
	return {"ok": true, "total_cost": total_cost}


## 组合类别合法性：
## - 单张恒合法；
## - 多张时任一技能/能力（NO_COMBO）→ 非法；
## - 其余须同类；未标注（NEUTRAL）通配。
func _combo_classes_ok(deck: DeckState, uids: Array[int], card_defs: Dictionary) -> bool:
	if uids.size() <= 1:
		return true
	var reference := CardDef.ComboClass.NEUTRAL
	for uid: int in uids:
		var card := deck.get_card(uid)
		if card == null:
			return false
		var definition := _get_def(card_defs, card.card_id)
		if definition == null:
			return false
		var combo_class := CardDef.combo_class_of(card.effective_tags(definition))
		if combo_class == CardDef.ComboClass.NO_COMBO:
			return false
		if combo_class == CardDef.ComboClass.NEUTRAL:
			continue
		if reference == CardDef.ComboClass.NEUTRAL:
			reference = combo_class
		elif reference != combo_class:
			return false
	return true


func _get_def(card_defs: Dictionary, card_id: StringName) -> CardDef:
	if card_defs.has(card_id):
		return card_defs[card_id] as CardDef
	if card_defs.has(String(card_id)):
		return card_defs[String(card_id)] as CardDef
	return null


func _build_combo_metadata(
	deck: DeckState,
	uids: Array[int],
	card_defs: Dictionary
) -> Dictionary:
	var entries: Array[Dictionary] = []
	var total_play_count := 0
	var category_card_counts: Dictionary = {}
	var category_play_counts: Dictionary = {}
	for uid: int in uids:
		var card := deck.get_card(uid)
		if card == null:
			continue
		var definition := _get_def(card_defs, card.card_id)
		if definition == null:
			continue
		var category := _category_key(definition.card_category)
		var weight := definition.get_play_count_weight(card.upgrade_level)
		total_play_count += weight
		category_card_counts[category] = int(category_card_counts.get(category, 0)) + 1
		category_play_counts[category] = int(category_play_counts.get(category, 0)) + weight
		entries.append({
			"uid": uid,
			"card_id": definition.card_id,
			"card_number": definition.card_number,
			"category": category,
			"play_count_weight": weight,
		})
	return {
		"selected_uids": uids.duplicate(),
		"selected_count": uids.size(),
		"play_count_total": total_play_count,
		"category_card_counts": category_card_counts,
		"category_play_counts": category_play_counts,
		"cards": entries,
	}


func _metadata_for_card(
	combo: Dictionary,
	definition: CardDef,
	card: BattleCardState,
	uid: int,
	index: int
) -> Dictionary:
	var result := combo.duplicate(true)
	var category := _category_key(definition.card_category)
	var weight := definition.get_play_count_weight(card.upgrade_level)
	result["source_index"] = index
	result["source_card_uid"] = uid
	result["source_card_id"] = definition.card_id
	result["source_card_number"] = definition.card_number
	result["source_category"] = category
	result["source_play_count_weight"] = weight
	result["other_selected_count"] = maxi(0, int(combo.get("selected_count", 0)) - 1)
	result["other_play_count"] = maxi(0, int(combo.get("play_count_total", 0)) - weight)
	var other_category_counts: Dictionary = Dictionary(combo.get("category_card_counts", {})).duplicate(true)
	other_category_counts[category] = maxi(0, int(other_category_counts.get(category, 0)) - 1)
	result["other_category_card_counts"] = other_category_counts
	return result


func _category_key(category: CardDef.CardCategory) -> StringName:
	match category:
		CardDef.CardCategory.SKILL:
			return &"skill"
		CardDef.CardCategory.TECHNIQUE:
			return &"technique"
		CardDef.CardCategory.ATTACK:
			return &"attack"
		CardDef.CardCategory.DEFENSE:
			return &"defense"
		_:
			return &"unassigned"


func _target_matches_rule(
	state: Variant,
	actor_id: int,
	rule: TargetSpec,
	target: Variant
) -> bool:
	if rule == null:
		return true
	if not target is TargetSpec:
		return false
	var resolved := target as TargetSpec
	if not resolved.is_resolved() or resolved.kind() != rule.kind():
		return false

	if rule is TargetSpec.UnitTarget:
		var rule_unit := rule as TargetSpec.UnitTarget
		var resolved_unit := resolved as TargetSpec.UnitTarget
		var target_unit: Variant = EffectStateAccess.get_unit(state, resolved_unit.unit_id)
		if target_unit == null:
			return false
		match rule_unit.team:
			TargetSpec.UnitTarget.Team.ANY:
				return true
			TargetSpec.UnitTarget.Team.SELF:
				return resolved_unit.unit_id == actor_id
			_:
				var actor: Variant = EffectStateAccess.get_unit(state, actor_id)
				if not actor is UnitState or not target_unit is UnitState:
					return false
				var same_team := (actor as UnitState).team == (target_unit as UnitState).team
				if rule_unit.team == TargetSpec.UnitTarget.Team.ALLY:
					return same_team and resolved_unit.unit_id != actor_id
				if rule_unit.team == TargetSpec.UnitTarget.Team.ENEMY:
					return not same_team
				return false

	if rule is TargetSpec.CellTarget:
		var cell := (resolved as TargetSpec.CellTarget).cell
		var board := EffectStateAccess.get_board(state)
		return board == null or board.is_inside(cell)

	if rule is TargetSpec.DirectionTarget:
		var direction := (resolved as TargetSpec.DirectionTarget).direction
		return absi(direction.x) <= 1 and absi(direction.y) <= 1

	return true


func _validate_target(
	validator: Callable,
	state: Variant,
	card: BattleCardState,
	definition: CardDef,
	target: Variant
) -> Dictionary:
	if not validator.is_valid():
		return {"ok": true}
	var result: Variant = validator.call(state, card, definition, target)
	if result is bool:
		return {"ok": bool(result), "fizzle": false}
	if result is Dictionary:
		var data := result as Dictionary
		return {
			"ok": bool(data.get("ok", false)),
			"fizzle": bool(data.get("fizzle", false)),
		}
	return {"ok": false, "fizzle": false}


func _is_attack_card(card: BattleCardState, definition: CardDef) -> bool:
	return card.effective_tags(definition).has(&"attack")


func _is_terminal(state: Variant) -> bool:
	if state is Object and (state as Object).has_method(&"is_terminal"):
		return bool((state as Object).call(&"is_terminal"))
	return false


func _update_terminal_if_battle_state(state: Variant) -> void:
	if not state is BattleState:
		return
	var battle := state as BattleState
	if battle.alive_player_ids().is_empty():
		battle.phase = BattleState.Phase.DEFEAT
	elif battle.alive_enemy_ids().is_empty():
		battle.phase = BattleState.Phase.VICTORY


func _append_events(destination: EventBatch, source: Variant) -> void:
	if not source is EventBatch:
		return
	for event: GameEvent in (source as EventBatch).events:
		destination.push_back(event)


func _make_step(
	uid: int,
	target: Variant,
	definition: CardDef,
	fizzled: bool,
	skipped_terminal: bool
) -> Dictionary:
	return {
		"card_uid": uid,
		"card_id": definition.card_id,
		"target": target,
		"fizzled": fizzled,
		"skipped_terminal": skipped_terminal,
	}


func _failure(
	state_in: Variant,
	deck_in: DeckState,
	rng_in: Variant,
	code: StringName
) -> Dictionary:
	return {
		"ok": false,
		"error_code": code,
		"state_out": state_in,
		"deck_out": deck_in,
		"rng_out": rng_in,
		"events": EventBatch.new(),
		"steps": [],
		"cost_spent": 0,
		"selected_uids": [],
	}
