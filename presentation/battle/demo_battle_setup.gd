class_name DemoBattleSetup
extends RefCounted
## Phase 4 无正式美术/内容资源时使用的可玩战斗数据。
## 只负责组装现有规则对象，不参与 UI 结算。


static func build(seed_text: String = "phase4-demo") -> Dictionary:
	var rng := RngStreams.new()
	rng.derive_streams(seed_text)

	var card_defs: Dictionary = {}
	card_defs[&"card.strike"] = _attack_card(&"card.strike", 1, 5)
	card_defs[&"card.heavy"] = _attack_card(&"card.heavy", 2, 9)
	card_defs[&"card.guard"] = _block_card(&"card.guard", 1, 5)

	var deck := DeckState.new()
	var specs: Array = [
		[101, &"card.strike"],
		[102, &"card.strike"],
		[103, &"card.strike"],
		[104, &"card.heavy"],
		[105, &"card.heavy"],
		[106, &"card.guard"],
		[107, &"card.guard"],
		[108, &"card.strike"],
	]
	for spec: Array in specs:
		var card := BattleCardState.new()
		card.battle_uid = int(spec[0])
		card.card_id = StringName(spec[1])
		deck.add_card(card, DeckState.ZONE_DRAW)

	var board := BoardState.new(8, 8)
	var player := UnitState.create(1, &"unit.demo_player", UnitState.Team.PLAYER, 26)
	var enemy := UnitState.create(2, &"unit.demo_enemy", UnitState.Team.ENEMY, 30)
	var units: Dictionary[int, UnitState] = {1: player, 2: enemy}
	board.place_unit(1, Vector2i(2, 5))
	board.place_unit(2, Vector2i(4, 4))

	var state := BattleFactory.create_state(401, board, units, deck, rng, 5, 3, 2)

	var approach := EnemyActionDef.new()
	approach.id = &"enemy.approach"
	approach.kind = EnemyActionDef.Kind.APPROACH
	approach.target_policy = EnemyActionDef.TargetPolicy.PLAYER
	approach.move_steps = 2

	var attack := EnemyActionDef.new()
	attack.id = &"enemy.attack"
	attack.kind = EnemyActionDef.Kind.ATTACK
	attack.target_policy = EnemyActionDef.TargetPolicy.PLAYER
	attack.damage = 4
	attack.range = 1

	var defend := EnemyActionDef.new()
	defend.id = &"enemy.defend"
	defend.kind = EnemyActionDef.Kind.DEFEND
	defend.target_policy = EnemyActionDef.TargetPolicy.SELF
	defend.block = 4

	var behavior := SequenceBehaviorDef.new()
	behavior.id = &"behavior.demo"
	behavior.sequence = [approach, attack, defend]

	return {
		"rng": rng,
		"state": state,
		"card_defs": card_defs,
		"enemy_behaviors": {2: behavior},
		"enemy_actions": {
			approach.id: approach,
			attack.id: attack,
			defend.id: defend,
		},
		"card_labels": {
			&"card.strike": "斩击\n1 能量 · 5 伤害",
			&"card.heavy": "重击\n2 能量 · 9 伤害",
			&"card.guard": "格挡\n1 能量 · +5 护盾",
		},
	}


static func _attack_card(card_id: StringName, cost: int, damage: int) -> CardDef:
	var definition := CardDef.new()
	definition.card_id = card_id
	definition.base_cost = cost
	definition.tags = [&"attack"]
	definition.effects = [ConfiguredEffectDef.make(&"damage", {"amount": damage})]
	var target_rule := TargetSpec.UnitTarget.new()
	target_rule.team = TargetSpec.UnitTarget.Team.ENEMY
	definition.target_rule = target_rule
	return definition


static func _block_card(card_id: StringName, cost: int, amount: int) -> CardDef:
	var definition := CardDef.new()
	definition.card_id = card_id
	definition.base_cost = cost
	definition.tags = [&"skill"]
	definition.effects = [ConfiguredEffectDef.make(&"block", {"amount": amount})]
	return definition
