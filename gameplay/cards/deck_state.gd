class_name DeckState
extends RefCounted
## 一场战斗中的卡牌实例与五个互斥牌区。

const ZONE_DRAW: StringName = &"draw"
const ZONE_HAND: StringName = &"hand"
const ZONE_DISCARD: StringName = &"discard"
const ZONE_EXHAUST: StringName = &"exhaust"
const ZONE_RESOLVING: StringName = &"resolving"

var cards: Dictionary = {} # battle_uid -> BattleCardState
var draw: Array[int] = []
var hand: Array[int] = []
var discard: Array[int] = []
var exhaust: Array[int] = []
var resolving: Array[int] = []


func add_card(card: BattleCardState, zone: StringName = ZONE_DRAW) -> bool:
	if card == null or card.battle_uid < 0 or cards.has(card.battle_uid):
		return false
	var zone_array := get_zone(zone)
	if zone_array == null:
		return false
	cards[card.battle_uid] = card
	zone_array.append(card.battle_uid)
	return true


func get_card(uid: int) -> BattleCardState:
	return cards.get(uid) as BattleCardState


func get_zone(zone: StringName) -> Variant:
	match zone:
		ZONE_DRAW:
			return draw
		ZONE_HAND:
			return hand
		ZONE_DISCARD:
			return discard
		ZONE_EXHAUST:
			return exhaust
		ZONE_RESOLVING:
			return resolving
		_:
			return null


func zone_of(uid: int) -> StringName:
	for zone: StringName in [ZONE_DRAW, ZONE_HAND, ZONE_DISCARD, ZONE_EXHAUST, ZONE_RESOLVING]:
		var zone_array: Array = get_zone(zone)
		if zone_array.has(uid):
			return zone
	return &""


func move_card(uid: int, from_zone: StringName, to_zone: StringName) -> bool:
	var source: Variant = get_zone(from_zone)
	var destination: Variant = get_zone(to_zone)
	if source == null or destination == null:
		return false
	var source_array := source as Array
	var destination_array := destination as Array
	var index := source_array.find(uid)
	if index < 0 or destination_array.has(uid):
		return false
	source_array.remove_at(index)
	destination_array.append(uid)
	return true


func validate_invariants() -> Dictionary:
	var seen: Dictionary = {}
	for zone: StringName in [ZONE_DRAW, ZONE_HAND, ZONE_DISCARD, ZONE_EXHAUST, ZONE_RESOLVING]:
		var zone_array: Array = get_zone(zone)
		for uid_value: Variant in zone_array:
			var uid := int(uid_value)
			if not cards.has(uid):
				return {"ok": false, "error": &"unknown_card_uid", "uid": uid}
			if seen.has(uid):
				return {"ok": false, "error": &"card_in_multiple_zones", "uid": uid}
			seen[uid] = zone
	for uid_value: Variant in cards.keys():
		var uid := int(uid_value)
		if not seen.has(uid):
			return {"ok": false, "error": &"card_has_no_zone", "uid": uid}
	return {"ok": true}


func duplicate_deck() -> DeckState:
	var copy := DeckState.new()
	for uid_value: Variant in cards.keys():
		var uid := int(uid_value)
		var card: BattleCardState = cards[uid]
		copy.cards[uid] = card.duplicate_state()
	copy.draw = draw.duplicate()
	copy.hand = hand.duplicate()
	copy.discard = discard.duplicate()
	copy.exhaust = exhaust.duplicate()
	copy.resolving = resolving.duplicate()
	return copy


## A1 DrawEffectHandler 的接线入口。
func draw_cards(_unit_id: int, count: int, rng: RandomNumberGenerator) -> Dictionary:
	return CardSystem.new().draw_cards(self, count, rng)
