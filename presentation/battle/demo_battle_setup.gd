class_name DemoBattleSetup
extends RefCounted
## Phase 4/5 可玩战斗装配：规则对象来自正式 ContentDB，表现仍可使用占位 UI。


static func build(seed_text: String = "phase5-content-demo", enemy_content_id: StringName = &"enemy.ring_stalker") -> Dictionary:
	if not ContentDB.ensure_loaded():
		push_error("DemoBattleSetup: content catalog failed to load")
		return {}
	var rng := RngStreams.new()
	rng.derive_streams(seed_text)

	var card_defs := ContentDB.all_cards()

	var deck := DeckState.new()
	var specs: Array = [
		[101, &"card.warrior.strike"],
		[102, &"card.warrior.strike"],
		[103, &"card.warrior.strike"],
		[104, &"card.warrior.strike"],
		[105, &"card.warrior.guard"],
		[106, &"card.warrior.guard"],
		[107, &"card.warrior.guard"],
		[108, &"card.warrior.pommel"],
		[109, &"card.warrior.lunge"],
		[110, &"card.warrior.quick_draw"],
	]
	for spec: Array in specs:
		var card := BattleCardState.new()
		card.battle_uid = int(spec[0])
		card.card_id = StringName(spec[1])
		deck.add_card(card, DeckState.ZONE_DRAW)

	var player_def := ContentDB.get_unit(&"unit.hero.prototype")
	var enemy_def := ContentDB.get_enemy(enemy_content_id)
	if player_def == null or enemy_def == null:
		push_error("DemoBattleSetup: missing player/enemy content")
		return {}
	var enemy_unit_def := ContentDB.get_unit(enemy_def.unit_def_id)
	if enemy_unit_def == null:
		push_error("DemoBattleSetup: missing enemy UnitDef: %s" % String(enemy_def.unit_def_id))
		return {}

	var board := BoardState.new(8, 8)
	var player := UnitState.create(1, player_def.id, UnitState.Team.PLAYER, player_def.base_stat(StatSystem.STAT_MAX_HP))
	var enemy := UnitState.create(2, enemy_unit_def.id, UnitState.Team.ENEMY, enemy_unit_def.base_stat(StatSystem.STAT_MAX_HP))
	var units: Dictionary[int, UnitState] = {1: player, 2: enemy}
	board.place_unit(1, Vector2i(2, 5))
	board.place_unit(2, Vector2i(4, 4))

	var state := BattleFactory.create_state(401, board, units, deck, rng, 5, 3, 2)
	var enemy_actions := _enemy_actions(enemy_def)

	return {
		"rng": rng,
		"state": state,
		"card_defs": card_defs,
		"enemy_behaviors": {2: enemy_def.behavior},
		"enemy_actions": enemy_actions,
		"card_labels": _card_labels(card_defs),
	}


static func _card_labels(card_defs: Dictionary) -> Dictionary:
	var labels: Dictionary = {}
	for id: Variant in card_defs:
		var definition := card_defs[id] as CardDef
		if definition == null:
			continue
		labels[id] = "%s\n%d 能量 · %s" % [
			definition.display_name if not definition.display_name.is_empty() else String(definition.card_id),
			definition.base_cost,
			definition.description,
		]
	return labels


static func _enemy_actions(enemy_def: EnemyDef) -> Dictionary:
	var actions: Dictionary = {}
	if enemy_def == null or not enemy_def.behavior is SequenceBehaviorDef:
		return actions
	for action: EnemyActionDef in (enemy_def.behavior as SequenceBehaviorDef).sequence:
		if action != null and not action.id.is_empty():
			actions[action.id] = action
	return actions
