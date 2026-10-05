extends "res://tests/test_case.gd"


func run() -> Array[String]:
	reset()
	_test_same_name_cards_keep_unique_uid()
	_test_card_belongs_to_exactly_one_zone()
	_test_duplicate_deck_is_independent()
	return failures()


func _card(uid: int, card_id: StringName = &"card.slash") -> BattleCardState:
	var card := BattleCardState.new()
	card.battle_uid = uid
	card.card_id = card_id
	return card


func _test_same_name_cards_keep_unique_uid() -> void:
	var deck := DeckState.new()
	assert_true(deck.add_card(_card(1), DeckState.ZONE_HAND), "first card should be added")
	assert_true(deck.add_card(_card(2), DeckState.ZONE_HAND), "second same-name card should be added")
	assert_equal(deck.hand, [1, 2], "same CardDef must still have separate battle UIDs")
	assert_true(bool(deck.validate_invariants()["ok"]), "valid deck should satisfy zone invariant")


func _test_card_belongs_to_exactly_one_zone() -> void:
	var deck := DeckState.new()
	deck.add_card(_card(7), DeckState.ZONE_HAND)
	assert_true(deck.move_card(7, DeckState.ZONE_HAND, DeckState.ZONE_RESOLVING), "hand -> resolving")
	assert_equal(deck.zone_of(7), DeckState.ZONE_RESOLVING, "card should move to resolving")
	deck.discard.append(7)
	var invalid := deck.validate_invariants()
	assert_true(not bool(invalid["ok"]), "same UID in two zones must be rejected")
	assert_equal(invalid["error"], &"card_in_multiple_zones", "duplicate-zone error")


func _test_duplicate_deck_is_independent() -> void:
	var deck := DeckState.new()
	var original_card := _card(5)
	deck.add_card(original_card, DeckState.ZONE_HAND)
	var copy := deck.duplicate_deck()
	copy.get_card(5).cost_modifier = -2
	copy.hand.clear()
	copy.discard.append(5)
	assert_equal(deck.get_card(5).cost_modifier, 0, "cloned BattleCardState must be independent")
	assert_equal(deck.hand, [5], "cloned zone arrays must be independent")
