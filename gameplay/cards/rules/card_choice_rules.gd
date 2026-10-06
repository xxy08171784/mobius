class_name CardChoiceRules
extends CardRuleSupport

static func choice_request(
	state: BattleState,
	source_uid: int,
	selected_uids: Array[int],
	card_defs: Dictionary
) -> Dictionary:
	if state == null:
		return {}
	var source := state.deck.get_card(source_uid)
	var definition := _def_for_card(card_defs, source)
	if source == null or definition == null:
		return {}
	var number := definition.card_number
	var zone := DeckState.ZONE_HAND
	var min_count := 1
	var max_count := 1
	var title := ""
	match number:
		2:
			zone = DeckState.ZONE_DRAW
			title = "立刻征用：选择抽牌堆中的 1 张攻击牌"
		5:
			title = "招式领悟：选择手牌中的 1 张招式牌"
		6:
			title = "遣散：选择最多 2 张手牌"
			min_count = 0
			max_count = 2
		12:
			title = "复制：选择 1 张手牌（能力类除外）"
		44:
			title = "应激格挡：选择 1 张手牌放入弃牌堆"
		_:
			return {}
	var candidates: Array[int] = []
	var values: Variant = state.deck.get_zone(zone)
	if values is Array:
		for value: Variant in values:
			var uid := int(value)
			if selected_uids.has(uid):
				continue
			var card := state.deck.get_card(uid)
			var candidate_def := _def_for_card(card_defs, card)
			if card == null or candidate_def == null:
				continue
			if number == 2 and candidate_def.card_category != CardDef.CardCategory.ATTACK:
				continue
			if number == 5 and candidate_def.card_category != CardDef.CardCategory.TECHNIQUE:
				continue
			if number == 12 and card.effective_tags(candidate_def).has(CardDef.TAG_ABILITY):
				continue
			candidates.append(uid)
	return {
		"title": title,
		"source_uid": source_uid,
		"zone": zone,
		"min_count": min_count,
		"max_count": max_count,
		"candidates": candidates,
	}

static func validate_command_choices(
	state: BattleState,
	command: PlayCardsCommand,
	card_defs: Dictionary
) -> bool:
	if state == null or command == null:
		return false
	for source_uid: int in command.card_uids:
		var request := choice_request(state, source_uid, command.card_uids, card_defs)
		if request.is_empty():
			continue
		var selected := _choice_array(command, source_uid)
		var min_count := int(request.get("min_count", 0))
		var max_count := int(request.get("max_count", 0))
		if selected.size() < min_count or selected.size() > max_count:
			return false
		var seen: Dictionary = {}
		var candidates: Array = request.get("candidates", [])
		for uid: int in selected:
			if seen.has(uid) or not candidates.has(uid):
				return false
			seen[uid] = true
	return true
