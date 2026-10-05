extends "res://tests/test_case.gd"


func run() -> Array[String]:
	reset()
	var state := BattleState.new()
	var first := DeterministicReplay.replay("1234", state, [], Callable())
	var second := DeterministicReplay.replay("1234", state, [], Callable())
	assert_equal(first, second, "empty replay with same seed/state must be deterministic")

	state.version = 1
	var changed := DeterministicReplay.summarize(state, [])
	assert_not_equal(
		changed["state_hash"],
		first["state_hash"],
		"state hash must change when state changes"
	)
	return failures()
