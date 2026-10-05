extends "res://tests/test_case.gd"


func run() -> Array[String]:
	reset()
	_test_same_seed_same_streams()
	_test_streams_are_isolated()
	_test_clone_does_not_advance_original()
	_test_snapshot_restore()
	return failures()


func _test_same_seed_same_streams() -> void:
	var a := RngStreams.new()
	var b := RngStreams.new()
	a.derive_streams("1234567890123456789")
	b.derive_streams("1234567890123456789")
	for stream_id: StringName in RngStreams.STREAM_IDS:
		assert_equal(
			a.get_stream(stream_id).randi(),
			b.get_stream(stream_id).randi(),
			"same seed must reproduce stream %s" % stream_id
		)


func _test_streams_are_isolated() -> void:
	var baseline := RngStreams.new()
	var changed := RngStreams.new()
	baseline.derive_streams("42")
	changed.derive_streams("42")
	changed.get_stream(&"route").randi()
	changed.get_stream(&"route").randi()
	assert_equal(
		changed.battle_rng().randi(),
		baseline.battle_rng().randi(),
		"advancing route stream must not advance battle stream"
	)


func _test_clone_does_not_advance_original() -> void:
	var original := RngStreams.new()
	original.derive_streams("987654321")
	var preview := original.clone()
	preview.battle_rng().randi()
	preview.battle_rng().randi()
	var control := original.clone()
	assert_equal(
		original.battle_rng().randi(),
		control.battle_rng().randi(),
		"advancing clone must not advance original"
	)


func _test_snapshot_restore() -> void:
	var original := RngStreams.new()
	original.derive_streams("-123456789")
	original.battle_rng().randi()
	original.get_stream(&"reward").randi()
	var snapshot := original.snapshot()
	var restored := RngStreams.new()
	restored.restore(snapshot)
	assert_equal(restored.snapshot(), snapshot, "snapshot -> restore must round-trip exactly")
	assert_equal(
		restored.battle_rng().randi(),
		original.battle_rng().randi(),
		"restored battle stream must continue from same state"
	)
