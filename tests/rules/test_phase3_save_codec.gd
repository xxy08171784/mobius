extends "res://tests/test_case.gd"


func run() -> Array[String]:
	reset()
	_test_full_battle_state_json_round_trip()
	_test_full_clone_has_no_shared_battle_objects()
	return failures()


func _rich_state() -> BattleState:
	var streams := Phase3Fixture.rng("save-phase3")
	var deck := DeckState.new()
	var card := Phase3Fixture.battle_card(70, &"card.saved")
	card.source_run_uid = 700
	card.upgrade_level = 2
	card.cost_modifier = -1
	card.temporary_tags = [&"temp"]
	deck.add_card(card, DeckState.ZONE_HAND)
	var state := Phase3Fixture.base_state(
		streams,
		20,
		15,
		Vector2i(1, 1),
		Vector2i(4, 1),
		deck,
		5,
		4,
		2
	)
	state.phase = BattleState.Phase.PLAYER_INPUT
	state.resume_phase = BattleState.Phase.PLAYER_INPUT
	state.round_index = 3
	state.version = 9
	state.next_uid = 1234
	state.next_event_seq = 88
	state.seen_command_ids = [41]
	state.command_result_snapshots[41] = {
		"accepted": true,
		"error_code": int(CommandResult.ErrorCode.OK),
		"text_key": &"",
		"state_version": 9,
		"events": [],
		"has_events": true,
	}
	state.enemy_steps[2] = 5
	state.enemy_charge_remaining[2] = 1
	var intent := IntentState.new()
	intent.action_id = &"enemy.attack"
	intent.actor_id = 2
	intent.locked_unit_id = 1
	intent.locked_cell = Vector2i(1, 1)
	intent.affected_cells = [Vector2i(1, 1)]
	intent.magnitude = 4
	state.enemy_intents[2] = intent
	state.enemy_charge_intents[2] = intent

	var status := StatusState.new()
	status.instance_id = 77
	status.status_id = &"poison"
	status.stacks = 2
	status.duration = 3
	status.source_unit_id = 2
	state.get_unit(1).set_status(77, status)
	state.get_unit(1).block = 6
	state.get_unit(1).set_resource(&"energy", 2)

	var wall := CellState.new()
	wall.terrain_key = &"wall"
	wall.traversable = false
	wall.blocks_los = true
	state.board.set_cell(Vector2i(3, 3), wall)
	return state


func _test_full_battle_state_json_round_trip() -> void:
	var codec := SaveCodec.new()
	var original := _rich_state()
	var encoded_board: Variant = codec.call("_encode_board", original.board)
	assert_true(encoded_board is Dictionary and (encoded_board as Dictionary).has("cols"), "board codec helper must encode")
	var encoded_units: Variant = codec.call("_encode_units", original.units)
	assert_true(encoded_units is Array and (encoded_units as Array).size() == 2, "unit codec helper must encode")
	var encoded_deck: Variant = codec.call("_encode_deck", original.deck)
	assert_true(encoded_deck is Dictionary and (encoded_deck as Dictionary).has("cards"), "deck codec helper must encode")
	var encoded_intents: Variant = codec.call("_encode_intents", original.enemy_intents)
	assert_true(encoded_intents is Array and (encoded_intents as Array).size() == 1, "intent codec helper must encode")
	assert_true(codec.encode_value(original.rng_snapshot) != null, "RNG snapshot must be JSON-safe")
	assert_true(codec.encode_value(original.command_result_snapshots) != null, "command result cache must be JSON-safe")
	var encoded := codec.encode_state(original)
	assert_true(encoded.has("state_type"), "encoded BattleState must contain state_type before JSON")
	var json := JSON.stringify(encoded)
	assert_true(json.contains("state_type"), "serialized BattleState JSON must contain state_type")
	var parser := JSON.new()
	var parse_error := parser.parse(json)
	assert_equal(
		parse_error,
		OK,
		"full BattleState encoded JSON must parse: %s at line %d" % [
			parser.get_error_message(),
			parser.get_error_line(),
		]
	)
	if parse_error != OK:
		return
	var parsed: Variant = parser.data
	assert_true(parsed is Dictionary, "parsed BattleState JSON must be a Dictionary")
	if not parsed is Dictionary:
		return
	assert_equal(String((parsed as Dictionary).get("state_type", "")), "BattleState", "state_type survives JSON")
	assert_true(SaveMigrator.new().can_load(parsed as Dictionary), "schema_version survives JSON and is loadable")
	var decoded := codec.decode_state(parsed) as BattleState
	assert_true(decoded != null, "full BattleState should survive JSON")
	if decoded == null:
		return
	assert_equal(
		DeterministicReplay.hash_variant(codec.encode_state(decoded)),
		DeterministicReplay.hash_variant(encoded),
		"full BattleState codec should be canonical after JSON round-trip"
	)
	assert_equal(decoded.board.get_unit_cell(1), Vector2i(1, 1), "board occupancy persists")
	assert_true(not decoded.board.is_traversable(Vector2i(3, 3)), "explicit terrain persists")
	assert_equal(decoded.get_unit(1).get_status(77).status_id, &"poison", "StatusState persists")
	assert_equal(decoded.deck.zone_of(70), DeckState.ZONE_HAND, "card zone persists")
	assert_equal(decoded.enemy_intents[2].action_id, &"enemy.attack", "enemy intent persists")
	assert_equal(decoded.rng_snapshot, original.rng_snapshot, "RNG snapshot persists")
	assert_true(decoded.command_result_snapshots.has(41), "idempotency result snapshot persists")


func _test_full_clone_has_no_shared_battle_objects() -> void:
	var original := _rich_state()
	var clone := SaveCodec.new().clone_state(original) as BattleState
	clone.get_unit(1).hp = 1
	clone.get_unit(1).get_status(77).stacks = 99
	clone.board.move_unit(1, Vector2i(2, 1))
	clone.deck.move_card(70, DeckState.ZONE_HAND, DeckState.ZONE_DISCARD)
	clone.enemy_intents[2].magnitude = 999

	assert_equal(original.get_unit(1).hp, 20, "clone UnitState must not share HP object")
	assert_equal(original.get_unit(1).get_status(77).stacks, 2, "clone StatusState must be independent")
	assert_equal(original.board.get_unit_cell(1), Vector2i(1, 1), "clone BoardState must be independent")
	assert_equal(original.deck.zone_of(70), DeckState.ZONE_HAND, "clone DeckState must be independent")
	assert_equal(original.enemy_intents[2].magnitude, 4, "clone IntentState must be independent")
