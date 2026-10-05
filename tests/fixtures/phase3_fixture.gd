class_name Phase3Fixture
extends RefCounted
## Phase 3 规则集成测试的最小 8×8 / 1 玩家 / 1 敌人构造工具。


static func rng(seed: String = "phase3") -> RngStreams:
	var streams := RngStreams.new()
	streams.derive_streams(seed)
	return streams


static func unit_target(unit_id: int) -> TargetSpec.UnitTarget:
	var target := TargetSpec.UnitTarget.new()
	target.unit_id = unit_id
	return target


static func damage_card(
	card_id: StringName,
	cost: int,
	damage: int
) -> CardDef:
	var definition := CardDef.new()
	definition.card_id = card_id
	definition.base_cost = cost
	definition.tags = [&"attack"]
	definition.effects = [TestEffectDef.make(&"damage", {"amount": damage})]
	var rule := TargetSpec.UnitTarget.new()
	rule.team = TargetSpec.UnitTarget.Team.ENEMY
	definition.target_rule = rule
	return definition


static func block_card(
	card_id: StringName,
	cost: int,
	block: int
) -> CardDef:
	var definition := CardDef.new()
	definition.card_id = card_id
	definition.base_cost = cost
	definition.tags = [&"skill"]
	definition.effects = [TestEffectDef.make(&"block", {"amount": block})]
	return definition


static func battle_card(uid: int, card_id: StringName) -> BattleCardState:
	var card := BattleCardState.new()
	card.battle_uid = uid
	card.card_id = card_id
	return card


static func base_state(
	streams: RngStreams,
	player_hp: int = 20,
	enemy_hp: int = 12,
	player_cell: Vector2i = Vector2i(0, 0),
	enemy_cell: Vector2i = Vector2i(1, 0),
	deck: DeckState = null,
	hand_size: int = 0,
	energy: int = 3,
	move_points: int = 0
) -> BattleState:
	var board := BoardState.new(8, 8)
	var player := UnitState.create(1, &"unit.player", UnitState.Team.PLAYER, player_hp)
	var enemy := UnitState.create(2, &"unit.enemy", UnitState.Team.ENEMY, enemy_hp)
	var units: Dictionary[int, UnitState] = {1: player, 2: enemy}
	board.place_unit(1, player_cell)
	board.place_unit(2, enemy_cell)
	return BattleFactory.create_state(
		101,
		board,
		units,
		deck if deck != null else DeckState.new(),
		streams,
		hand_size,
		energy,
		move_points
	)


static func attack_action(
	id: StringName = &"enemy.attack",
	damage: int = 3,
	range_: int = 1
) -> EnemyActionDef:
	var action := EnemyActionDef.new()
	action.id = id
	action.kind = EnemyActionDef.Kind.ATTACK
	action.target_policy = EnemyActionDef.TargetPolicy.PLAYER
	action.damage = damage
	action.range = range_
	return action


static func defend_action(
	id: StringName = &"enemy.defend",
	block: int = 4
) -> EnemyActionDef:
	var action := EnemyActionDef.new()
	action.id = id
	action.kind = EnemyActionDef.Kind.DEFEND
	action.target_policy = EnemyActionDef.TargetPolicy.SELF
	action.block = block
	return action


static func behavior(actions: Array[EnemyActionDef]) -> SequenceBehaviorDef:
	var definition := SequenceBehaviorDef.new()
	definition.id = &"behavior.phase3"
	definition.sequence = actions
	return definition


static func session(
	state: BattleState,
	streams: RngStreams,
	card_defs: Dictionary = {},
	behavior_def: BehaviorDef = null,
	target_validator: Callable = Callable()
) -> BattleSession:
	var battle := BattleSession.new()
	var behaviors: Dictionary = {}
	if behavior_def != null:
		behaviors[2] = behavior_def
	battle.setup(streams, state, card_defs, behaviors, {}, target_validator)
	return battle
