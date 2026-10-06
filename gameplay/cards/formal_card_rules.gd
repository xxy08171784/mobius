class_name FormalCardRules
extends CardRuleSupport
## 正式卡牌门面。复杂卡按稳定 ID 注册；选择、目标与各机制独立维护。

static func on_card_drawn(card: BattleCardState) -> void:
	if card == null:
		return
	match card.card_id:
		&"card.reward.37":
			card.runtime_data["stacked_block"] = int(card.runtime_data.get("stacked_block", 0)) + 4
		&"card.reward.46":
			card.runtime_data["heal_charge"] = mini(9, int(card.runtime_data.get("heal_charge", 0)) + 3)

static func choice_request(
	state: BattleState,
	source_uid: int,
	selected_uids: Array[int],
	card_defs: Dictionary
) -> Dictionary:
	return CardChoiceRules.choice_request(state, source_uid, selected_uids, card_defs)


static func validate_command_choices(
	state: BattleState,
	command: PlayCardsCommand,
	card_defs: Dictionary
) -> bool:
	return CardChoiceRules.validate_command_choices(state, command, card_defs)


static func validate_target(
	state: BattleState,
	actor_id: int,
	definition: CardDef,
	target: Variant
) -> Dictionary:
	return CardTargetRules.validate_target(state, actor_id, definition, target)


static func apply_combo_pre_modifiers(
	state: BattleState,
	command: PlayCardsCommand,
	card_defs: Dictionary
) -> void:
	if state == null or command == null:
		return
	for source_uid: int in command.card_uids:
		var source := state.deck.get_card(source_uid)
		var source_def := _def_for_card(card_defs, source)
		if source == null or source_def == null:
			continue
		match source_def.card_number:
			26:
				for uid: int in command.card_uids:
					if uid == source_uid:
						continue
					var other := state.deck.get_card(uid)
					var other_def := _def_for_card(card_defs, other)
					if other != null and other_def != null and other_def.card_category == CardDef.CardCategory.TECHNIQUE:
						other.damage_modifier += 3
			49:
				for uid: int in command.card_uids:
					if uid == source_uid:
						continue
					var other := state.deck.get_card(uid)
					if other != null:
						other.block_modifier += 3

static func prepare_effects(
	card: BattleCardState,
	definition: CardDef,
	round_index: int
) -> Array:
	var out: Array = []
	if card == null or definition == null:
		return out
	var has_block := false
	for raw: Variant in definition.get_effects(card.upgrade_level):
		var item: Dictionary = {}
		if raw is EffectDef:
			item = (raw as EffectDef).to_plan_item()
		elif raw is Dictionary:
			item = (raw as Dictionary).duplicate(true)
		if item.is_empty():
			continue
		var params: Dictionary = Dictionary(item.get("params", {})).duplicate(true)
		var type_key := StringName(String(item.get("type_key", "")))
		if type_key == &"damage":
			params["amount"] = float(params.get("amount", 0.0)) + float(_damage_bonus(card, round_index))
		elif type_key == &"block":
			has_block = true
			params["amount"] = float(params.get("amount", 0.0)) + float(card.block_modifier)
		item["params"] = params
		out.append(item)
	if card.block_modifier > 0 and not has_block:
		out.append({
			"type_key": &"block",
			"params": {"amount": card.block_modifier, "target_mode": &"source"},
		})
	return out

static func is_special(definition: CardDef) -> bool:
	return definition != null and FormalCardRuleRegistry.has_rule(definition.card_id)


static func resolve_card(
	state: BattleState,
	rng: Variant,
	actor_id: int,
	card: BattleCardState,
	definition: CardDef,
	target: Variant,
	command: PlayCardsCommand,
	combo_metadata: Dictionary,
	card_defs: Dictionary
) -> Dictionary:
	if not is_special(definition):
		return {"handled": false}
	if state == null or card == null:
		return _failure(state, rng)
	return FormalCardRuleRegistry.resolve(state, rng, actor_id, card, definition, target, command, combo_metadata, card_defs)
