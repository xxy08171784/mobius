extends "res://tests/test_case.gd"


func run() -> Array[String]:
	reset()
	_test_damage_block_hp_and_purity()
	_test_invalid_effect_has_zero_side_effects()
	_test_block_and_status()
	_test_cross_module_handler_contracts()
	_test_trigger_overflow_rejects_snapshot()
	_test_same_input_same_output()
	return failures()


func _make_rng() -> RngStreams:
	var rng := RngStreams.new()
	rng.derive_streams("20261005")
	return rng


func _test_damage_block_hp_and_purity() -> void:
	var state := EffectTestState.new()
	var rng := _make_rng()
	var rng_before := rng.snapshot()
	var result := EffectResolver.new().resolve(
		state,
		{
			"context": {"source_unit_id": 1},
			"effects": [
				{"type_key": &"damage", "target": 2, "params": {"amount": 5}},
			],
		},
		rng
	)
	assert_true(bool(result["ok"]), "damage resolve should succeed")
	var out: EffectTestState = result["state_out"]
	assert_equal(int(out.units[2]["block"]), 0, "Block must absorb damage first")
	assert_equal(int(out.units[2]["hp"]), 8, "remaining damage must reduce HP")
	assert_equal(int(state.units[2]["block"]), 3, "input state block must stay unchanged")
	assert_equal(int(state.units[2]["hp"]), 10, "input state HP must stay unchanged")
	assert_equal(rng.snapshot(), rng_before, "resolve must not advance input RNG")
	var events: EventBatch = result["events"]
	assert_equal(events.size(), 1, "damage should emit one presentation event")
	if events.size() == 1:
		var event: EffectEvent = events.events[0]
		assert_equal(int(event.payload["absorbed"]), 3, "damage event should expose absorbed block")
		assert_equal(int(event.payload["hp_damage"]), 2, "damage event should expose HP damage")


func _test_invalid_effect_has_zero_side_effects() -> void:
	var state := EffectTestState.new()
	var rng := _make_rng()
	var state_hp_before := int(state.units[2]["hp"])
	var rng_before := rng.snapshot()
	var result := EffectResolver.new().resolve(
		state,
		{"effects": [{"type_key": &"damage", "source_unit_id": 1, "target": 999, "params": {"amount": 5}}]},
		rng
	)
	assert_true(not bool(result["ok"]), "invalid target must reject resolution")
	assert_equal(int(state.units[2]["hp"]), state_hp_before, "rejected resolve must not mutate state")
	assert_equal(rng.snapshot(), rng_before, "rejected resolve must not advance RNG")
	assert_equal((result["events"] as EventBatch).size(), 0, "rejected resolve must expose no partial events")


func _test_block_and_status() -> void:
	var state := EffectTestState.new()
	var result := EffectResolver.new().resolve(
		state,
		{
			"context": {"source_unit_id": 1},
			"effects": [
				{"type_key": &"block", "target": 1, "params": {"amount": 4}},
				{
					"type_key": &"apply_status",
					"target": 2,
					"params": {"status_id": &"poison", "stacks": 2, "duration": 3},
				},
			],
		},
		_make_rng()
	)
	assert_true(bool(result["ok"]), "block + status plan should succeed")
	var out: EffectTestState = result["state_out"]
	assert_equal(int(out.units[1]["block"]), 4, "block handler should add block")
	var statuses: Dictionary = out.units[2]["statuses"]
	assert_equal(statuses.size(), 1, "apply_status should add one StatusState")
	if statuses.size() == 1:
		var status: StatusState = statuses.values()[0]
		assert_equal(status.status_id, &"poison", "status id should be preserved")
		assert_equal(status.stacks, 2, "status stacks should be preserved")
		assert_equal(status.duration, 3, "status duration should be preserved")


func _test_cross_module_handler_contracts() -> void:
	var state := EffectTestState.new()
	var result := EffectResolver.new().resolve(
		state,
		{
			"context": {"source_unit_id": 1},
			"effects": [
				{"type_key": &"draw", "params": {"count": 2}},
				{"type_key": &"move", "target": {"cell": Vector2i(1, 1)}},
				{
					"type_key": &"push",
					"target": 2,
					"direction": Vector2i.RIGHT,
					"params": {"steps": 2},
				},
			],
		},
		_make_rng()
	)
	assert_true(bool(result["ok"]), "draw/move/push contracts should execute through test adapter")
	var out: EffectTestState = result["state_out"]
	assert_equal(out.draw_pile, [103, 104], "draw contract should mutate only work deck")
	assert_equal(out.positions[1], Vector2i(1, 1), "move contract should call board entry")
	assert_equal(out.positions[2], Vector2i(4, 0), "push contract should call board entry")
	assert_equal(state.draw_pile, [101, 102, 103, 104], "cross-module effects must not mutate input state")


func _test_trigger_overflow_rejects_snapshot() -> void:
	var triggers: Array = []
	for i: int in range(TriggerSystem.DEFAULT_MAX_PROCESSED + 1):
		triggers.append({"phase": 0, "priority": 0, "instance_id": i, "effects": []})
	var state := EffectTestState.new()
	var result := EffectResolver.new().resolve(
		state,
		{"effects": [], "triggers": triggers},
		_make_rng()
	)
	assert_true(not bool(result["ok"]), "resolver must reject trigger overflow")
	assert_equal(result["error_code"], EffectResolver.ERROR_TRIGGER_OVERFLOW, "overflow error code")
	assert_equal(int(state.next_event_seq), 1, "overflow must not leave partial authoritative state")


func _test_same_input_same_output() -> void:
	var state := EffectTestState.new()
	var rng := _make_rng()
	var plan := {
		"context": {"source_unit_id": 1},
		"effects": [{"type_key": &"damage", "target": 2, "params": {"amount": 4}}],
	}
	var a := EffectResolver.new().resolve(state, plan, rng)
	var b := EffectResolver.new().resolve(state, plan, rng)
	var state_a: EffectTestState = a["state_out"]
	var state_b: EffectTestState = b["state_out"]
	assert_equal(state_a.units, state_b.units, "same state/plan/RNG must produce same unit result")
	assert_equal(
		(a["rng_out"] as RngStreams).snapshot(),
		(b["rng_out"] as RngStreams).snapshot(),
		"same state/plan/RNG must produce same RNG result"
	)
