class_name FormalCardFixture
extends RefCounted
## 49 张正式卡专项测试的纯规则夹具。


static func rng(seed: String = "formal-cards") -> RngStreams:
	var streams := RngStreams.new()
	streams.derive_streams(seed)
	return streams


static func definition(number: int) -> CardDef:
	return load("res://content/cards/reward/card_%02d.tres" % number) as CardDef


static func defs(numbers: Array[int]) -> Dictionary:
	var out: Dictionary = {}
	for number: int in numbers:
		var definition := definition(number)
		if definition != null:
			out[definition.card_id] = definition
	return out


static func card(number: int, uid: int) -> BattleCardState:
	var value := BattleCardState.new()
	value.battle_uid = uid
	value.card_id = StringName("card.reward.%02d" % number)
	return value


static func token(card_id: StringName, uid: int) -> BattleCardState:
	var value := BattleCardState.new()
	value.battle_uid = uid
	value.card_id = card_id
	return value


static func state(
	player_hp: int = 30,
	player_max_hp: int = 30,
	enemy_hp: int = 30,
	player_cell: Vector2i = Vector2i(2, 2),
	enemy_cell: Vector2i = Vector2i(3, 2),
	move_points: int = 3,
	courage: int = 0
) -> BattleState:
	var out := BattleState.new()
	out.phase = BattleState.Phase.PLAYER_INPUT
	out.resume_phase = BattleState.Phase.PLAYER_INPUT
	out.battle_id = 9001
	out.round_index = 1
	out.board = BoardState.new(8, 8)
	var player := UnitState.create(1, &"unit.player", UnitState.Team.PLAYER, player_max_hp)
	player.hp = clampi(player_hp, 0, player_max_hp)
	player.set_resource(TurnSystem.ENERGY_RESOURCE, 20)
	player.set_resource(TurnSystem.MOVE_RESOURCE, move_points)
	player.set_resource(&"courage", courage)
	var enemy := UnitState.create(2, &"unit.enemy", UnitState.Team.ENEMY, enemy_hp)
	out.units = {1: player, 2: enemy}
	out.board.place_unit(1, player_cell)
	out.board.place_unit(2, enemy_cell)
	out.deck = DeckState.new()
	return out


static func add_enemy(
	state_value: BattleState,
	unit_id: int,
	hp: int,
	cell: Vector2i
) -> UnitState:
	var enemy := UnitState.create(unit_id, StringName("unit.enemy.%d" % unit_id), UnitState.Team.ENEMY, hp)
	state_value.units[unit_id] = enemy
	state_value.board.place_unit(unit_id, cell)
	return enemy


static func add_card(
	state_value: BattleState,
	number: int,
	uid: int,
	zone: StringName = DeckState.ZONE_HAND
) -> BattleCardState:
	var value := card(number, uid)
	state_value.deck.add_card(value, zone)
	return value


static func add_token(
	state_value: BattleState,
	card_id: StringName,
	uid: int,
	zone: StringName = DeckState.ZONE_HAND
) -> BattleCardState:
	var value := token(card_id, uid)
	state_value.deck.add_card(value, zone)
	return value


static func unit_target(unit_id: int) -> TargetSpec.UnitTarget:
	var target := TargetSpec.UnitTarget.new()
	target.unit_id = unit_id
	return target


static func cell_target(cell: Vector2i) -> TargetSpec.CellTarget:
	var target := TargetSpec.CellTarget.new()
	target.cell = cell
	return target


static func direction_target(direction: Vector2i) -> TargetSpec.DirectionTarget:
	var target := TargetSpec.DirectionTarget.new()
	target.direction = direction
	return target


static func command(
	actor_id: int,
	uids: Array[int],
	targets: Array,
	choices: Dictionary = {}
) -> PlayCardsCommand:
	var value := PlayCardsCommand.new()
	value.actor_id = actor_id
	value.card_uids = uids
	value.targets = targets
	value.choices = choices.duplicate(true)
	return value


static func resolve(
	state_value: BattleState,
	number: int,
	uid: int,
	target: Variant = null,
	command_value: PlayCardsCommand = null,
	card_defs: Dictionary = {}
) -> Dictionary:
	var source := state_value.deck.get_card(uid)
	if source == null:
		source = add_card(state_value, number, uid)
	var definition := definition(number)
	if command_value == null:
		command_value = command(1, [uid], [target])
	if card_defs.is_empty() and definition != null:
		card_defs[definition.card_id] = definition
	return FormalCardRules.resolve_card(
		state_value,
		rng("card-%02d" % number),
		1,
		source,
		definition,
		target,
		command_value,
		{},
		card_defs
	)
