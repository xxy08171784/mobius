extends "res://tests/test_case.gd"


func run() -> Array[String]:
	reset()
	_test_run_and_battle_identity_are_separate()
	_test_run_card_becomes_battle_instance()
	_test_upgrade_and_temporary_cost()
	_test_definition_is_not_mutated_by_battle_state()
	_test_numbered_card_visual_identity()
	return failures()


func _test_run_and_battle_identity_are_separate() -> void:
	var a := RunCardState.new()
	a.run_uid = 10
	a.card_id = &"card.slash"
	var b := RunCardState.new()
	b.run_uid = 11
	b.card_id = &"card.slash"
	assert_equal(a.card_id, b.card_id, "same definition id is allowed")
	assert_not_equal(a.run_uid, b.run_uid, "same-name cards must keep distinct UIDs")

	var battle := BattleCardState.new()
	battle.battle_uid = 101
	battle.source_run_uid = a.run_uid
	battle.card_id = a.card_id
	assert_not_equal(battle.battle_uid, battle.source_run_uid, "battle UID and run UID are separate identities")


func _test_run_card_becomes_battle_instance() -> void:
	var run_card := RunCardState.new()
	run_card.run_uid = 77
	run_card.card_id = &"card.guard"
	run_card.upgrade_level = 2
	var battle := CardSystem.new().create_battle_card(run_card, 900)
	assert_equal(battle.battle_uid, 900, "battle instance gets its own UID")
	assert_equal(battle.source_run_uid, 77, "battle instance remembers source run card")
	assert_equal(battle.card_id, &"card.guard", "definition ID carries into battle")
	assert_equal(battle.upgrade_level, 2, "permanent upgrade carries into battle")
	assert_true(not battle.generated, "run-owned card is not generated")


func _test_upgrade_and_temporary_cost() -> void:
	var definition := CardDef.new()
	definition.card_id = &"card.slash"
	definition.base_cost = 3
	definition.tags = [&"attack"]
	definition.upgrade_overrides = {
		1: {"cost": 2, "tags": [&"attack", &"upgraded"]},
	}

	var card := BattleCardState.new()
	card.battle_uid = 1
	card.card_id = definition.card_id
	card.upgrade_level = 1
	card.cost_modifier = -1
	card.temporary_tags = [&"combo_bonus"]

	assert_equal(card.effective_cost(definition), 1, "upgrade then battle cost modifier should determine final cost")
	var tags := card.effective_tags(definition)
	assert_true(tags.has(&"attack"), "base/upgrade tag should remain")
	assert_true(tags.has(&"upgraded"), "upgrade tags should apply")
	assert_true(tags.has(&"combo_bonus"), "temporary battle tags should apply")


func _test_definition_is_not_mutated_by_battle_state() -> void:
	var definition := CardDef.new()
	definition.card_id = &"card.guard"
	definition.base_cost = 2
	definition.tags = [&"skill"]
	var card := BattleCardState.new()
	card.battle_uid = 2
	card.card_id = definition.card_id
	card.cost_modifier = -99
	card.temporary_tags.append(&"temporary")
	card.effective_tags(definition).append(&"should_not_leak")
	assert_equal(definition.base_cost, 2, "battle modifiers must not edit CardDef")
	assert_equal(definition.tags, [&"skill"], "effective tags must be a copy")


func _test_numbered_card_visual_identity() -> void:
	var definition := CardDef.new()
	definition.card_id = &"card.reward.23"
	definition.card_number = 23
	definition.card_category = CardDef.CardCategory.ATTACK
	definition.play_count_weight = 2
	assert_true(definition.is_numbered_card(), "formal numbered card should be detectable")
	assert_equal(definition.get_visual_key(), &"card_23", "numbered card should derive stable PNG key")
	assert_equal(definition.get_play_count_weight(), 2, "play-count weight should be a generic CardDef property")
	definition.visual_key = &"custom_visual"
	assert_equal(definition.get_visual_key(), &"custom_visual", "explicit visual key should override derived key")
