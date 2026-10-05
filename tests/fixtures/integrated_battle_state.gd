class_name IntegratedBattleState
extends Resource
## 仅用于 A/B 接口集成测试：使用真实 UnitState + BoardState，
## 但不提前把 Phase 3 的字段塞进正式 BattleState。

var next_uid: int = 100
var next_event_seq: int = 1
var units: Dictionary[int, UnitState] = {}
var board: BoardState = BoardState.new(6, 4)


func duplicate_state() -> IntegratedBattleState:
	var copy := IntegratedBattleState.new()
	copy.next_uid = next_uid
	copy.next_event_seq = next_event_seq
	copy.board = _duplicate_board(board)
	for unit_id: int in units:
		copy.units[unit_id] = _duplicate_unit(units[unit_id])
	return copy


static func _duplicate_unit(unit: UnitState) -> UnitState:
	var copy := UnitState.create(unit.unit_id, unit.def_id, unit.team, unit.max_hp)
	copy.hp = unit.hp
	copy.block = unit.block
	copy.resources = unit.resources.duplicate()
	for instance_id: int in unit.statuses:
		var source: StatusState = unit.statuses[instance_id]
		var status := StatusState.new()
		status.instance_id = source.instance_id
		status.status_id = source.status_id
		status.stacks = source.stacks
		status.duration = source.duration
		status.source_unit_id = source.source_unit_id
		copy.statuses[instance_id] = status
	return copy


static func _duplicate_board(source: BoardState) -> BoardState:
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
