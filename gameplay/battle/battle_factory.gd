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
	state.board = _copy_board(board)
	state.units = _copy_units(units)
	state.deck = deck.duplicate_deck() if deck != null else DeckState.new()
	state.rng_snapshot = rng.snapshot() if rng != null else {}
	state.hand_size = maxi(0, hand_size)
	state.energy_per_round = maxi(0, energy_per_round)
	state.move_points_per_round = maxi(0, move_points_per_round)
	state.phase = BattleState.Phase.SETUP
	state.resume_phase = BattleState.Phase.PLAYER_INPUT
	return state


static func create_empty_8x8(battle_id: int, rng: RngStreams) -> BattleState:
	return create_state(
		battle_id,
		BoardState.new(8, 8),
		{},
		DeckState.new(),
		rng
	)


static func _copy_board(source: BoardState) -> BoardState:
	if source == null:
		return BoardState.new()
	var copy := BoardState.new(source.cols, source.rows)
	for y: int in range(source.rows):
		for x: int in range(source.cols):
			var cell := Vector2i(x, y)
			var source_cell := source.get_cell(cell)
			if source_cell == null:
				continue
			var cell_copy := CellState.new()
			cell_copy.terrain_key = source_cell.terrain_key
			cell_copy.blocks_los = source_cell.blocks_los
			cell_copy.traversable = source_cell.traversable
			cell_copy.trap = source_cell.trap
			copy.set_cell(cell, cell_copy)
	for unit_id: int in source.get_unit_ids():
		copy.place_unit(unit_id, source.get_unit_cell(unit_id))
	return copy


static func _copy_units(source: Dictionary[int, UnitState]) -> Dictionary[int, UnitState]:
	var result: Dictionary[int, UnitState] = {}
	for unit_id: int in source:
		result[unit_id] = _copy_unit(source[unit_id])
	return result


static func _copy_unit(source: UnitState) -> UnitState:
	var copy := UnitState.create(source.unit_id, source.def_id, source.team, source.max_hp)
	copy.hp = source.hp
	copy.block = source.block
	copy.resources = source.resources.duplicate()
	for instance_id: int in source.statuses:
		var old_status: StatusState = source.statuses[instance_id]
		var status := StatusState.new()
		status.instance_id = old_status.instance_id
		status.status_id = old_status.status_id
		status.stacks = old_status.stacks
		status.duration = old_status.duration
		status.source_unit_id = old_status.source_unit_id
		copy.statuses[instance_id] = status
	return copy
