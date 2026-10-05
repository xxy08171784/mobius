extends "res://tests/test_case.gd"


func run() -> Array[String]:
	reset()
	_test_setup_locks_intent_and_resets_resources()
	_test_preview_and_rejected_command_have_zero_side_effects()
	_test_play_card_submit_lock_and_duplicate_are_authoritative()
	_test_move_command_spends_move_points()
	_test_session_forwards_card_target_validator()
	_test_end_turn_executes_locked_enemy_intent_and_starts_next_round()
	_test_victory_and_defeat_boundaries()
	_test_duplicate_result_survives_save_reload()
	_test_command_history_is_bounded_fifo()
	_test_same_seed_and_commands_are_deterministic()
	return failures()


func _test_setup_locks_intent_and_resets_resources() -> void:
	var streams := Phase3Fixture.rng("setup")
	var attack := Phase3Fixture.attack_action()
	var state := Phase3Fixture.base_state(streams, 20, 12, Vector2i(0, 0), Vector2i(1, 0))
	state.energy_per_round = 4
	state.move_points_per_round = 2
	var session := Phase3Fixture.session(state, streams, {}, Phase3Fixture.behavior([attack]))

	assert_equal(session.state.phase, BattleState.Phase.PLAYER_INPUT, "setup should enter PLAYER_INPUT")
	assert_equal(session.state.round_index, 1, "setup should start round 1")
	assert_equal(session.state.get_unit(1).get_resource(&"energy"), 4, "round start resets energy")
	assert_equal(session.state.get_unit(1).get_resource(&"move_points"), 2, "round start resets move points")
	assert_true(session.state.enemy_intents.has(2), "round start should lock enemy intent")
	assert_equal(session.state.enemy_intents[2].locked_unit_id, 1, "enemy intent should lock player")


func _test_preview_and_rejected_command_have_zero_side_effects() -> void:
	var streams := Phase3Fixture.rng("preview")
	var attack_card := Phase3Fixture.damage_card(&"card.hit", 1, 4)
	var expensive := Phase3Fixture.damage_card(&"card.expensive", 9, 9)
	var deck := DeckState.new()
	deck.add_card(Phase3Fixture.battle_card(10, attack_card.card_id), DeckState.ZONE_HAND)
	deck.add_card(Phase3Fixture.battle_card(11, expensive.card_id), DeckState.ZONE_HAND)
	var state := Phase3Fixture.base_state(streams, 20, 12, Vector2i(0, 0), Vector2i(2, 0), deck)
	var defs := {attack_card.card_id: attack_card, expensive.card_id: expensive}
	var session := Phase3Fixture.session(state, streams, defs)
	var codec := SaveCodec.new()

	var preview_command := PlayCardsCommand.new()
	preview_command.command_id = 100
	preview_command.actor_id = 1
	preview_command.card_uids = [10]
	preview_command.targets = [Phase3Fixture.unit_target(2)]
	var before_preview := codec.encode_state(session.state)
	var preview := session.preview(preview_command)
	assert_true(preview.accepted, "valid preview should be accepted")
	assert_equal(codec.encode_state(session.state), before_preview, "preview must not mutate authoritative state/RNG")

	var expensive_command := PlayCardsCommand.new()
	expensive_command.command_id = 101
	expensive_command.actor_id = 1
	expensive_command.card_uids = [11]
	expensive_command.targets = [Phase3Fixture.unit_target(2)]
	var before_reject := codec.encode_state(session.state)
	var rejected := session.submit(expensive_command)
	assert_true(not rejected.accepted, "insufficient cost should reject")
	assert_equal(rejected.error_code, CommandResult.ErrorCode.COST, "cost validation should happen before target/combo")
	assert_equal(codec.encode_state(session.state), before_reject, "rejected command must have zero authoritative side effects")
	var duplicate_reject := session.submit(expensive_command)
	assert_equal(duplicate_reject.error_code, CommandResult.ErrorCode.COST, "same rejected ID should return first result in-session")


func _test_play_card_submit_lock_and_duplicate_are_authoritative() -> void:
	var streams := Phase3Fixture.rng("submit")
	var hit := Phase3Fixture.damage_card(&"card.hit", 1, 4)
	var deck := DeckState.new()
	deck.add_card(Phase3Fixture.battle_card(20, hit.card_id), DeckState.ZONE_HAND)
	var state := Phase3Fixture.base_state(streams, 20, 12, Vector2i(0, 0), Vector2i(1, 0), deck)
	var session := Phase3Fixture.session(state, streams, {hit.card_id: hit})

	var command := PlayCardsCommand.new()
	command.command_id = 200
	command.actor_id = 1
	command.card_uids = [20]
	command.targets = [Phase3Fixture.unit_target(2)]
	var result := session.submit(command)
	assert_true(result.accepted, "valid card command should commit")
	assert_equal(session.state.version, 1, "accepted command increments version once")
	assert_equal(session.state.get_unit(2).hp, 8, "damage should commit to authoritative UnitState")
	assert_equal(session.state.get_unit(1).get_resource(&"energy"), 2, "combo cost is deducted once")
	assert_equal(session.state.deck.zone_of(20), DeckState.ZONE_DISCARD, "played card leaves resolving to discard")
	assert_equal(session.state.phase, BattleState.Phase.RESOLVING, "accepted non-terminal command locks during presentation")
	assert_true(session.state.command_locked, "accepted non-terminal command sets authoritative command lock")

	var duplicate := session.submit(command)
	assert_true(duplicate.accepted, "duplicate accepted ID returns first accepted result")
	assert_equal(duplicate.state_version, result.state_version, "duplicate returns original state version")
	assert_equal(session.state.version, 1, "duplicate must not execute twice")
	assert_equal(session.state.get_unit(2).hp, 8, "duplicate must not deal damage twice")

	var busy := EndTurnCommand.new()
	busy.command_id = 201
	busy.actor_id = 1
	var busy_result := session.submit(busy)
	assert_equal(busy_result.error_code, CommandResult.ErrorCode.BUSY, "fresh command during presentation should be BUSY")

	session.finish_presentation()
	assert_equal(session.state.phase, BattleState.Phase.PLAYER_INPUT, "presentation completion resumes PLAYER_INPUT")
	assert_true(not session.state.command_locked, "presentation completion clears lock")


func _test_move_command_spends_move_points() -> void:
	var streams := Phase3Fixture.rng("move")
	var state := Phase3Fixture.base_state(
		streams,
		20,
		12,
		Vector2i(0, 0),
		Vector2i(7, 7),
		DeckState.new(),
		0,
		3,
		2
	)
	var session := Phase3Fixture.session(state, streams)
	var move := MoveCommand.new()
	move.command_id = 300
	move.actor_id = 1
	move.destination = Vector2i(0, 1)
	var result := session.submit(move)
	assert_true(result.accepted, "enabled free MoveCommand should commit")
	assert_equal(session.state.board.get_unit_cell(1), Vector2i(0, 1), "move commits through Displacement")
	assert_equal(session.state.get_unit(1).get_resource(&"move_points"), 1, "move spends path length once")
	session.finish_presentation()

	var occupied := MoveCommand.new()
	occupied.command_id = 301
	occupied.actor_id = 1
	occupied.destination = Vector2i(7, 7)
	var rejected := session.submit(occupied)
	assert_equal(rejected.error_code, CommandResult.ErrorCode.TARGET, "occupied destination is target error")
	assert_equal(session.state.board.get_unit_cell(1), Vector2i(0, 1), "rejected move does not change occupancy")


func _test_session_forwards_card_target_validator() -> void:
	var streams := Phase3Fixture.rng("target-validator")
	var hit := Phase3Fixture.damage_card(&"card.range", 1, 4)
	var deck := DeckState.new()
	deck.add_card(Phase3Fixture.battle_card(35, hit.card_id), DeckState.ZONE_HAND)
	var state := Phase3Fixture.base_state(
		streams,
		20,
		12,
		Vector2i(0, 0),
		Vector2i(3, 0),
		deck
	)
	var session := Phase3Fixture.session(
		state,
		streams,
		{hit.card_id: hit},
		null,
		Callable(self, "_range_one_validator")
	)
	var command := PlayCardsCommand.new()
	command.command_id = 350
	command.actor_id = 1
	command.card_uids = [35]
	command.targets = [Phase3Fixture.unit_target(2)]
	var result := session.submit(command)
	assert_true(not result.accepted, "BattleSession should forward content-specific target validation")
	assert_equal(result.error_code, CommandResult.ErrorCode.TARGET, "range validator failure maps to TARGET")
	assert_equal(session.state.get_unit(2).hp, 12, "failed range validation must not resolve card damage")


func _range_one_validator(
	state: Variant,
	_card: BattleCardState,
	_definition: CardDef,
	target: Variant
) -> Dictionary:
	if not state is BattleState or not target is TargetSpec.UnitTarget:
		return {"ok": false}
	var battle := state as BattleState
	var from_cell := battle.board.get_unit_cell(1)
	var target_cell := battle.board.get_unit_cell((target as TargetSpec.UnitTarget).unit_id)
	var distance := absi(target_cell.x - from_cell.x) + absi(target_cell.y - from_cell.y)
	return {"ok": distance <= 1}


func _test_end_turn_executes_locked_enemy_intent_and_starts_next_round() -> void:
	var streams := Phase3Fixture.rng("enemy-turn")
	var attack := Phase3Fixture.attack_action(&"enemy.attack", 3, 1)
	var state := Phase3Fixture.base_state(streams, 20, 12, Vector2i(0, 0), Vector2i(1, 0))
	var session := Phase3Fixture.session(state, streams, {}, Phase3Fixture.behavior([attack]))
	var end_turn := EndTurnCommand.new()
	end_turn.command_id = 400
	end_turn.actor_id = 1
	var result := session.submit(end_turn)

	assert_true(result.accepted, "EndTurn should execute locked enemy intent")
	assert_equal(session.state.get_unit(1).hp, 17, "enemy attack should use EffectResolver damage")
	assert_equal(session.state.round_index, 2, "EndTurn should finish enemy phase and start next round")
	assert_equal(session.state.resume_phase, BattleState.Phase.PLAYER_INPUT, "post-enemy presentation resumes next player input")
	assert_equal(session.state.enemy_steps.get(2, 0), 1, "executed enemy action advances stable behavior step")
	assert_true(result.events != null and result.events.size() == 1, "enemy attack should produce presentation damage event")
	session.finish_presentation()
	assert_equal(session.state.phase, BattleState.Phase.PLAYER_INPUT, "next round becomes interactive after events finish")


func _test_victory_and_defeat_boundaries() -> void:
	var victory_rng := Phase3Fixture.rng("victory")
	var kill := Phase3Fixture.damage_card(&"card.kill", 1, 99)
	var follow := Phase3Fixture.damage_card(&"card.follow", 0, 2)
	var deck := DeckState.new()
	deck.add_card(Phase3Fixture.battle_card(50, kill.card_id), DeckState.ZONE_HAND)
	deck.add_card(Phase3Fixture.battle_card(51, follow.card_id), DeckState.ZONE_HAND)
	var victory_state := Phase3Fixture.base_state(victory_rng, 20, 5, Vector2i(0, 0), Vector2i(1, 0), deck)
	var victory_session := Phase3Fixture.session(
		victory_state,
		victory_rng,
		{kill.card_id: kill, follow.card_id: follow}
	)
	var combo := PlayCardsCommand.new()
	combo.command_id = 500
	combo.actor_id = 1
	combo.card_uids = [50, 51]
	combo.targets = [Phase3Fixture.unit_target(2), Phase3Fixture.unit_target(2)]
	var victory := victory_session.submit(combo)
	assert_true(victory.accepted, "lethal combo should commit")
	assert_equal(victory_session.state.phase, BattleState.Phase.VICTORY, "last enemy death should end at VICTORY")
	assert_equal(victory_session.state.deck.resolving, [], "terminal combo still cleans all committed resolving cards")
	assert_equal(victory_session.state.deck.discard, [50, 51], "later attack is skipped but card cleanup remains")
	assert_true(victory_session.battle_result().victory, "BattleResult should expose victory")

	var defeat_rng := Phase3Fixture.rng("defeat")
	var lethal_enemy := Phase3Fixture.attack_action(&"enemy.kill", 99, 1)
	var defeat_state := Phase3Fixture.base_state(defeat_rng, 10, 20, Vector2i(0, 0), Vector2i(1, 0))
	var defeat_session := Phase3Fixture.session(defeat_state, defeat_rng, {}, Phase3Fixture.behavior([lethal_enemy]))
	var end_turn := EndTurnCommand.new()
	end_turn.command_id = 501
	end_turn.actor_id = 1
	var defeat := defeat_session.submit(end_turn)
	assert_true(defeat.accepted, "lethal enemy turn is an accepted player EndTurn command")
	assert_equal(defeat_session.state.phase, BattleState.Phase.DEFEAT, "player death has terminal DEFEAT")
	assert_true(not defeat_session.battle_result().victory, "BattleResult should expose defeat")

	var both_dead := Phase3Fixture.base_state(Phase3Fixture.rng("both"))
	both_dead.get_unit(1).hp = 0
	both_dead.get_unit(2).hp = 0
	assert_equal(TurnSystem.new().evaluate_outcome(both_dead), BattleState.Phase.DEFEAT, "simultaneous death prioritizes DEFEAT")


func _test_duplicate_result_survives_save_reload() -> void:
	var streams := Phase3Fixture.rng("duplicate-save")
	var hit := Phase3Fixture.damage_card(&"card.persisted-hit", 1, 4)
	var deck := DeckState.new()
	deck.add_card(Phase3Fixture.battle_card(55, hit.card_id), DeckState.ZONE_HAND)
	var state := Phase3Fixture.base_state(streams, 20, 12, Vector2i(0, 0), Vector2i(1, 0), deck)
	var session := Phase3Fixture.session(state, streams, {hit.card_id: hit})
	var command := PlayCardsCommand.new()
	command.command_id = 550
	command.actor_id = 1
	command.card_uids = [55]
	command.targets = [Phase3Fixture.unit_target(2)]
	var first := session.submit(command)
	assert_true(first.accepted, "first command should be accepted before save")
	var hp_after_first := session.state.get_unit(2).hp

	var encoded := SaveCodec.new().encode_state(session.state)
	var restored := SaveCodec.new().decode_state(encoded) as BattleState
	var restored_session := BattleSession.new()
	restored_session.setup(Phase3Fixture.rng("ignored-after-restore"), restored, {hit.card_id: hit})
	var duplicate := restored_session.submit(command)
	assert_true(duplicate.accepted, "persisted duplicate should return first accepted result")
	assert_equal(duplicate.state_version, first.state_version, "persisted duplicate keeps original result version")
	assert_equal(restored_session.state.get_unit(2).hp, hp_after_first, "persisted duplicate must not resolve damage again")
	assert_equal(restored_session.state.version, first.state_version, "persisted duplicate must not increment version")


func _test_command_history_is_bounded_fifo() -> void:
	var streams := Phase3Fixture.rng("fifo")
	var state := Phase3Fixture.base_state(
		streams,
		20,
		20,
		Vector2i(0, 0),
		Vector2i(7, 7)
	)
	var session := Phase3Fixture.session(state, streams)
	for i: int in range(BattleSession.MAX_SEEN_COMMANDS + 2):
		var command := EndTurnCommand.new()
		command.command_id = 800 + i
		command.actor_id = 1
		var result := session.submit(command)
		assert_true(result.accepted, "FIFO fixture EndTurn should be accepted")
		session.finish_presentation()
	assert_equal(session.state.seen_command_ids.size(), BattleSession.MAX_SEEN_COMMANDS, "persisted command IDs are bounded")
	assert_equal(session.state.command_result_snapshots.size(), BattleSession.MAX_SEEN_COMMANDS, "persisted result cache is bounded")
	assert_true(not session.state.seen_command_ids.has(800), "oldest accepted command should be evicted")
	assert_true(not session.state.seen_command_ids.has(801), "second-oldest accepted command should be evicted")
	assert_true(session.state.seen_command_ids.has(865), "newest accepted command stays in FIFO")

	# 内存缓存也必须同样封顶：已淘汰 ID 再来应视为新的命令，而非无限期命中旧结果。
	var recycled := EndTurnCommand.new()
	recycled.command_id = 800
	recycled.actor_id = 1
	var recycled_result := session.submit(recycled)
	assert_true(recycled_result.accepted, "evicted command ID may be reused after FIFO window")
	assert_equal(session.state.version, BattleSession.MAX_SEEN_COMMANDS + 3, "reused evicted ID executes exactly once")
	session.finish_presentation()


func _test_same_seed_and_commands_are_deterministic() -> void:
	var first := _run_deterministic_script("same-seed")
	var second := _run_deterministic_script("same-seed")
	assert_equal(first["state_hash"], second["state_hash"], "same seed + command log must yield same state hash")
	assert_equal(first["event_hash"], second["event_hash"], "same seed + command log must yield same event hash")


func _run_deterministic_script(seed: String) -> Dictionary:
	var streams := Phase3Fixture.rng(seed)
	var guard := Phase3Fixture.block_card(&"card.guard", 1, 2)
	var deck := DeckState.new()
	deck.add_card(Phase3Fixture.battle_card(60, guard.card_id), DeckState.ZONE_HAND)
	var attack := Phase3Fixture.attack_action(&"enemy.attack", 3, 1)
	var state := Phase3Fixture.base_state(streams, 20, 20, Vector2i(0, 0), Vector2i(1, 0), deck)
	var session := Phase3Fixture.session(state, streams, {guard.card_id: guard}, Phase3Fixture.behavior([attack]))
	var events: Array = []

	var play := PlayCardsCommand.new()
	play.command_id = 600
	play.actor_id = 1
	play.card_uids = [60]
	play.targets = [null]
	var play_result := session.submit(play)
	_events_to_data(events, play_result.events)
	session.finish_presentation()

	var end_turn := EndTurnCommand.new()
	end_turn.command_id = 601
	end_turn.actor_id = 1
	var end_result := session.submit(end_turn)
	_events_to_data(events, end_result.events)
	session.finish_presentation()

	return {
		"state_hash": DeterministicReplay.hash_variant(SaveCodec.new().encode_state(session.state)),
		"event_hash": DeterministicReplay.hash_variant(events),
	}


func _events_to_data(output: Array, batch: EventBatch) -> void:
	if batch == null:
		return
	for event: GameEvent in batch.events:
		output.append({
			"seq": event.seq,
			"type": event.type_key,
			"source": event.source_id,
			"target": event.target_id,
			"before": event.before,
			"after": event.after,
		})
