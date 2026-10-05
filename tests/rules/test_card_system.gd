extends "res://tests/test_case.gd"


func run() -> Array[String]:
	reset()
	_test_draw_moves_uid_between_zones()
	_test_discard_reshuffle_is_deterministic()
	_test_exhaust_never_reshuffles()
	_test_move_selection_is_atomic()
	return failures()


func _deck_with_cards(count: int) -> DeckState:
	var deck := DeckState.new()
	for uid: int in range(1, count + 1):
		var card := BattleCardState.new()
		card.battle_uid = uid
		card.card_id = &"card.test"
		deck.add_card(card, DeckState.ZONE_DRAW)
	return deck


func _rng(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng


func _test_draw_moves_uid_between_zones() -> void:
	var deck := _deck_with_cards(3)
	var result := CardSystem.new().draw_cards(deck, 2, _rng(1))
	assert_true(bool(result["ok"]), "draw should succeed")
	assert_equal(result["cards"], [3, 2], "draw pile top is the array end")
	assert_equal(deck.draw, [1], "drawn cards leave draw pile")
	assert_equal(deck.hand, [3, 2], "drawn cards enter hand")
	assert_true(bool(deck.validate_invariants()["ok"]), "draw must preserve zone invariant")


func _test_discard_reshuffle_is_deterministic() -> void:
	var a := _deck_with_cards(4)
	var b := _deck_with_cards(4)
	a.discard = a.draw.duplicate()
	b.discard = b.draw.duplicate()
	a.draw.clear()
	b.draw.clear()
	var result_a := CardSystem.new().draw_cards(a, 4, _rng(12345))
	var result_b := CardSystem.new().draw_cards(b, 4, _rng(12345))
	assert_equal(result_a["cards"], result_b["cards"], "same RNG state must produce same shuffle")
	assert_equal(a.hand, b.hand, "same shuffle must produce same hand order")


func _test_exhaust_never_reshuffles() -> void:
	var deck := _deck_with_cards(2)
	deck.exhaust = [1]
	deck.discard = [2]
	deck.draw.clear()
	var result := CardSystem.new().draw_cards(deck, 2, _rng(3))
	assert_equal(result["cards"], [2], "only discard pile may reshuffle")
	assert_equal(deck.exhaust, [1], "exhaust pile must remain untouched")


func _test_move_selection_is_atomic() -> void:
	var deck := _deck_with_cards(3)
	deck.hand = [1, 2]
	deck.draw = [3]
	var before := deck.hand.duplicate()
	var result := CardSystem.new().move_hand_to_resolving(deck, [1, 3])
	assert_true(not bool(result["ok"]), "selection containing non-hand card should fail")
	assert_equal(deck.hand, before, "failed selection must not partially move valid cards")
	assert_equal(deck.resolving, [], "failed selection must leave resolving empty")
