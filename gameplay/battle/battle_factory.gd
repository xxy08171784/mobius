class_name BattleFactory
extends RefCounted
## Phase 3 战斗构造器。
## 仓库当前尚无 RunState，因此本层先接“显式战斗输入”；未来 RunState 只需转成这些输入即可。


static func create_state(
	battle_id: int,
	board: BoardState,
	units: Dictionary[int, UnitState],
	deck: DeckState,
	rng: RngStreams,
	hand_size: int = 5,
	energy_per_round: int = 3,
	move_points_per_round: int = 0
) -> BattleState:
	var state := BattleState.new()
	state.battle_id = battle_id
	state.board = board if board != null else BoardState.new()
	state.units = units
	state.deck = deck if deck != null else DeckState.new()
	state.rng_snapshot = rng.snapshot() if rng != null else {}
	state.hand_size = maxi(0, hand_size)
	state.energy_per_round = maxi(0, energy_per_round)
	state.move_points_per_round = maxi(0, move_points_per_round)
	state.phase = BattleState.Phase.SETUP
	state.resume_phase = BattleState.Phase.PLAYER_INPUT
	return SaveCodec.new().clone_state(state) as BattleState


static func create_empty_8x8(battle_id: int, rng: RngStreams) -> BattleState:
	return create_state(
		battle_id,
		BoardState.new(8, 8),
		{},
		DeckState.new(),
		rng
	)
