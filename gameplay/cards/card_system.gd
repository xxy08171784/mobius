class_name CardSystem
extends RefCounted
## 牌区规则服务：抽牌、弃牌洗回、进入 resolving、结算后弃置/消耗。


func create_battle_card(run_card: RunCardState, battle_uid: int) -> BattleCardState:
	var card := BattleCardState.new()
	card.battle_uid = battle_uid
	card.source_run_uid = run_card.run_uid
	card.card_id = run_card.card_id
	card.upgrade_level = run_card.upgrade_level
	card.generated = false
	return card


func create_generated_card(card_id: StringName, battle_uid: int, upgrade_level: int = 0) -> BattleCardState:
	var card := BattleCardState.new()
	card.battle_uid = battle_uid
	card.source_run_uid = -1
	card.card_id = card_id
	card.upgrade_level = upgrade_level
	card.generated = true
	return card


func draw_cards(deck: DeckState, count: int, rng: RandomNumberGenerator) -> Dictionary:
	if deck == null or rng == null or count < 0:
		return {"ok": false, "error_code": &"invalid_draw", "cards": []}
	var drawn: Array[int] = []
	for _i: int in range(count):
		if deck.draw.is_empty():
			var shuffled := reshuffle_discard(deck, rng)
			if not shuffled and deck.draw.is_empty():
				break
		if deck.draw.is_empty():
			break
		var uid: int = deck.draw.pop_back()
		deck.hand.append(uid)
		drawn.append(uid)
	return {"ok": true, "cards": drawn}


func reshuffle_discard(deck: DeckState, rng: RandomNumberGenerator) -> bool:
	if deck == null or rng == null or deck.discard.is_empty():
		return false
	var pool: Array[int] = deck.discard.duplicate()
	deck.discard.clear()
	_shuffle_in_place(pool, rng)
	deck.draw.append_array(pool)
	return true


func move_hand_to_resolving(deck: DeckState, uids: Array[int]) -> Dictionary:
	if deck == null or uids.is_empty():
		return {"ok": false, "error_code": &"invalid_selection"}
	var seen: Dictionary = {}
	for uid: int in uids:
		if seen.has(uid):
			return {"ok": false, "error_code": &"duplicate_card"}
		seen[uid] = true
		if not deck.hand.has(uid):
			return {"ok": false, "error_code": &"card_not_in_hand", "uid": uid}

	# 先全部校验，再一次性移动，避免失败时产生半状态。
	for uid: int in uids:
		deck.move_card(uid, DeckState.ZONE_HAND, DeckState.ZONE_RESOLVING)
	return {"ok": true}


func finish_resolving(deck: DeckState, uid: int, exhaust_card: bool) -> bool:
	return deck.move_card(
		uid,
		DeckState.ZONE_RESOLVING,
		DeckState.ZONE_EXHAUST if exhaust_card else DeckState.ZONE_DISCARD
	)


func discard_from_hand(deck: DeckState, uid: int) -> bool:
	return deck.move_card(uid, DeckState.ZONE_HAND, DeckState.ZONE_DISCARD)


func exhaust_from_hand(deck: DeckState, uid: int) -> bool:
	return deck.move_card(uid, DeckState.ZONE_HAND, DeckState.ZONE_EXHAUST)


func _shuffle_in_place(values: Array[int], rng: RandomNumberGenerator) -> void:
	for i: int in range(values.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp := values[i]
		values[i] = values[j]
		values[j] = temp
