extends "res://tests/test_case.gd"
## 5 种正式通用初始牌 + 15 张初始牌组。


func run() -> Array[String]:
	reset()
	_test_starter_deck_counts()
	_test_atomic_starters()
	_test_charge()
	_test_relentless()
	return failures()


func _test_starter_deck_counts() -> void:
	var hero := load("res://content/characters/hero.tres") as CharacterDef
	assert_true(hero != null, "hero should load")
	if hero == null:
		return
	assert_equal(hero.starter_deck.size(), 15, "starter deck should contain 15 cards")
	var counts: Dictionary = {}
	for card_id: StringName in hero.starter_deck:
		counts[card_id] = int(counts.get(card_id, 0)) + 1
	assert_equal(int(counts.get(&"card.starter.punch", 0)), 2, "拳头 x2")
	assert_equal(int(counts.get(&"card.starter.attack", 0)), 3, "攻击 x3")
	assert_equal(int(counts.get(&"card.starter.charge", 0)), 2, "突击 x2")
	assert_equal(int(counts.get(&"card.starter.relentless", 0)), 2, "持续打击 x2")
	assert_equal(int(counts.get(&"card.starter.defend", 0)), 6, "防守 x6")


func _test_atomic_starters() -> void:
	var punch := load("res://content/cards/starter/punch.tres") as CardDef
	var attack := load("res://content/cards/starter/attack.tres") as CardDef
	var defend := load("res://content/cards/starter/defend.tres") as CardDef
	assert_equal(punch.base_cost, 0, "拳头费用0")
	assert_equal(attack.base_cost, 1, "攻击费用1")
	assert_equal(defend.base_cost, 1, "防守费用1")
	assert_equal(punch.card_category, CardDef.CardCategory.ATTACK, "拳头使用攻击牌卡框")
	assert_equal(attack.card_category, CardDef.CardCategory.ATTACK, "攻击使用攻击牌卡框")
	assert_equal(defend.card_category, CardDef.CardCategory.DEFENSE, "防守使用防御牌卡框")
	assert_equal(punch.get_icon_key(), &"icon_01", "通用卡暂用 icon_01")
	assert_equal(defend.get_icon_key(), &"icon_01", "防守暂用 icon_01")

	var state := FormalCardFixture.state()
	var punch_card := FormalCardFixture.add_token(state, &"card.starter.punch", 101)
	var punch_result := EffectResolver.new().resolve(
		state,
		{
			"context": {"source_unit_id": 1, "source_card_uid": punch_card.battle_uid, "target": FormalCardFixture.unit_target(2)},
			"effects": FormalCardRules.prepare_effects(punch_card, punch, state.round_index),
		},
		FormalCardFixture.rng("starter-punch")
	)
	assert_true(bool(punch_result.get("ok", false)), "拳头应成功结算")
	if bool(punch_result.get("ok", false)):
		assert_equal((punch_result["state_out"] as BattleState).get_unit(2).hp, 26, "拳头造成4伤害")

	state = FormalCardFixture.state()
	var attack_card := FormalCardFixture.add_token(state, &"card.starter.attack", 102)
	var attack_result := EffectResolver.new().resolve(
		state,
		{
			"context": {"source_unit_id": 1, "source_card_uid": attack_card.battle_uid, "target": FormalCardFixture.unit_target(2)},
			"effects": FormalCardRules.prepare_effects(attack_card, attack, state.round_index),
		},
		FormalCardFixture.rng("starter-attack")
	)
	assert_true(bool(attack_result.get("ok", false)), "攻击应成功结算")
	if bool(attack_result.get("ok", false)):
		assert_equal((attack_result["state_out"] as BattleState).get_unit(2).hp, 24, "攻击造成6伤害")

	state = FormalCardFixture.state()
	var defend_card := FormalCardFixture.add_token(state, &"card.starter.defend", 103)
	var defend_result := EffectResolver.new().resolve(
		state,
		{
			"context": {"source_unit_id": 1, "source_card_uid": defend_card.battle_uid, "target": null},
			"effects": FormalCardRules.prepare_effects(defend_card, defend, state.round_index),
		},
		FormalCardFixture.rng("starter-defend")
	)
	assert_true(bool(defend_result.get("ok", false)), "防守应成功结算")
	if bool(defend_result.get("ok", false)):
		assert_equal((defend_result["state_out"] as BattleState).get_unit(1).block, 5, "防守获得5防御")


func _test_charge() -> void:
	var state := FormalCardFixture.state(30, 30, 30, Vector2i(1, 2), Vector2i(4, 2))
	var card := FormalCardFixture.add_token(state, &"card.starter.charge", 201)
	var definition := load("res://content/cards/starter/charge.tres") as CardDef
	var target := FormalCardFixture.unit_target(2)
	assert_true(
		bool(FormalCardRules.validate_target(state, 1, definition, target).get("ok", false)),
		"突击应允许3格外且可在2步内接敌的目标"
	)
	var command := FormalCardFixture.command(1, [201], [target])
	var result := FormalCardRules.resolve_card(
		state, FormalCardFixture.rng("starter-charge"), 1, card, definition, target, command, {}, {definition.card_id: definition}
	)
	assert_true(bool(result.get("ok", false)), "突击应成功结算")
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		assert_equal(out.board.get_unit_cell(1), Vector2i(3, 2), "突击向敌人移动2格并停在其前")
		assert_equal(out.get_unit(2).hp, 25, "突击造成5伤害")


func _test_relentless() -> void:
	var state := FormalCardFixture.state(30, 30, 40)
	var card := FormalCardFixture.add_token(state, &"card.starter.relentless", 301)
	var definition := load("res://content/cards/starter/relentless.tres") as CardDef
	var target := FormalCardFixture.unit_target(2)
	var command := FormalCardFixture.command(1, [301], [target])
	var first := FormalCardRules.resolve_card(
		state, FormalCardFixture.rng("starter-relentless-1"), 1, card, definition, target, command, {}, {definition.card_id: definition}
	)
	assert_true(bool(first.get("ok", false)), "持续打击第一次应成功")
	if not bool(first.get("ok", false)):
		return
	var after_first := first["state_out"] as BattleState
	assert_equal(after_first.get_unit(2).hp, 34, "持续打击第一次造成6伤害")
	assert_true(bool(after_first.deck.get_card(301).runtime_data.get("relentless_used_once", false)), "第一次后记录单卡战斗态")
	var second_card := after_first.deck.get_card(301)
	var second := FormalCardRules.resolve_card(
		after_first, first["rng_out"], 1, second_card, definition, target, command, {}, {definition.card_id: definition}
	)
	assert_true(bool(second.get("ok", false)), "持续打击第二次应成功")
	if bool(second.get("ok", false)):
		assert_equal((second["state_out"] as BattleState).get_unit(2).hp, 23, "持续打击第二次造成11伤害")
