extends "res://tests/test_case.gd"


func run() -> Array[String]:
	reset()
	_test_battle_state_round_trip()
	_test_clone_has_no_shared_mutable_array()
	_test_json_preserves_int64_and_vector2i()
	_test_future_schema_is_rejected()
	return failures()


func _make_state() -> BattleState:
	var state := BattleState.new()
	state.phase = BattleState.Phase.PLAYER_INPUT
	state.version = 17
	state.next_uid = 9007199254740993
	state.next_event_seq = 9223372036854775806
	state.command_locked = true
	state.seen_command_ids = [1, 9007199254740995]
	return state


func _test_battle_state_round_trip() -> void:
	var codec := SaveCodec.new()
	var original := _make_state()
	var decoded := codec.decode_state(codec.encode_state(original)) as BattleState
	assert_true(decoded != null, "BattleState must decode")
	if decoded == null:
		return
	assert_equal(decoded.phase, original.phase, "phase round-trip")
	assert_equal(decoded.version, original.version, "version round-trip")
	assert_equal(decoded.next_uid, original.next_uid, "next_uid round-trip")
	assert_equal(decoded.next_event_seq, original.next_event_seq, "next_event_seq round-trip")
	assert_equal(decoded.command_locked, original.command_locked, "command_locked round-trip")
	assert_equal(decoded.seen_command_ids, original.seen_command_ids, "seen command IDs round-trip")


func _test_clone_has_no_shared_mutable_array() -> void:
	var codec := SaveCodec.new()
	var original := _make_state()
	var clone := codec.clone_state(original) as BattleState
	assert_true(clone != null, "clone must decode")
	if clone == null:
		return
	clone.seen_command_ids.append(77)
	clone.next_uid += 1
	assert_equal(original.seen_command_ids.size(), 2, "mutating clone array must not mutate original")
	assert_equal(original.next_uid, 9007199254740993, "mutating clone scalar must not mutate original")


func _test_json_preserves_int64_and_vector2i() -> void:
	var codec := SaveCodec.new()
	var fixture := {
		"large": 9007199254740997,
		"cell": Vector2i(-12, 34),
		"by_cell": {Vector2i(2, 3): 9223372036854775806},
	}
	var encoded: Variant = codec.encode_value(fixture)
	var json := JSON.stringify(encoded)
	var parsed: Variant = JSON.parse_string(json)
	var decoded: Dictionary = codec.decode_value(parsed)
	assert_equal(decoded["large"], fixture["large"], "int64 must survive JSON")
	assert_equal(decoded["cell"], fixture["cell"], "Vector2i must survive JSON")
	assert_equal(decoded["by_cell"], fixture["by_cell"], "Vector2i dictionary keys must survive JSON")


func _test_future_schema_is_rejected() -> void:
	var codec := SaveCodec.new()
	var encoded := codec.encode_state(_make_state())
	encoded["schema_version"] = SaveMigrator.CURRENT_SCHEMA_VERSION + 1
	assert_equal(codec.decode_state(encoded), null, "future schema must be rejected")
