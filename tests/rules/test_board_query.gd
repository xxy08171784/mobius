extends "res://tests/test_case.gd"
## BoardQuery / Pathfinder 测试（B1）。run() -> Array[String]，空 = 全过。
## 重点：supercover 视线（不穿角、端格不挡、对称）、移动可达 vs 视线分离（§10）。


func run() -> Array[String]:
	reset()
	_test_los_straight_clear_and_blocked()
	_test_los_endpoints_do_not_block()
	_test_los_no_corner_peek()
	_test_los_symmetry_sweep()
	_test_los_wall_blocks_movement_not_sight()
	_test_reachable_budget_and_bounds()
	_test_reachable_blocked_by_wall_and_occupancy()
	_test_find_path()
	_test_target_cells()
	return failures()


func _make_board() -> BoardState:
	return BoardState.new(8, 8)


func _pillar(board: BoardState, cell: Vector2i) -> void:
	var cs := CellState.new()
	cs.blocks_los = true
	board.set_cell(cell, cs)


func _wall(board: BoardState, cell: Vector2i) -> void:
	var cs := CellState.new()
	cs.traversable = false
	board.set_cell(cell, cs)


func _test_los_straight_clear_and_blocked() -> void:
	var b := _make_board()
	assert_true(BoardQuery.has_line_of_sight(b, Vector2i(0, 0), Vector2i(3, 0)), "空盘直线可见")
	_pillar(b, Vector2i(1, 0))
	assert_equal(BoardQuery.has_line_of_sight(b, Vector2i(0, 0), Vector2i(3, 0)), false, "(1,0)柱子挡视线")
	b = _make_board()
	_pillar(b, Vector2i(2, 0))
	assert_equal(BoardQuery.has_line_of_sight(b, Vector2i(0, 0), Vector2i(3, 0)), false, "(2,0)柱子挡视线")
	b = _make_board()
	_pillar(b, Vector2i(1, 2))
	assert_true(BoardQuery.has_line_of_sight(b, Vector2i(0, 0), Vector2i(0, 3)), "线外无关格(1,2)不挡竖直线")


func _test_los_endpoints_do_not_block() -> void:
	var b := _make_board()
	_pillar(b, Vector2i(0, 0))
	assert_true(BoardQuery.has_line_of_sight(b, Vector2i(0, 0), Vector2i(3, 0)), "起点格本身不挡")
	b = _make_board()
	_pillar(b, Vector2i(3, 0))
	assert_true(BoardQuery.has_line_of_sight(b, Vector2i(0, 0), Vector2i(3, 0)), "终点格本身不挡")


func _test_los_no_corner_peek() -> void:
	# 对角 (0,0)->(3,3) 恰穿两处格角，任一贴角相邻格为障碍即挡（无穿角窥视）。
	var b := _make_board()
	assert_true(BoardQuery.has_line_of_sight(b, Vector2i(0, 0), Vector2i(3, 3)), "空盘对角可见")
	b = _make_board()
	_pillar(b, Vector2i(1, 0))
	assert_equal(BoardQuery.has_line_of_sight(b, Vector2i(0, 0), Vector2i(3, 3)), false, "贴角(1,0)挡对角视线")
	b = _make_board()
	_pillar(b, Vector2i(0, 1))
	assert_equal(BoardQuery.has_line_of_sight(b, Vector2i(0, 0), Vector2i(3, 3)), false, "贴角(0,1)挡对角视线")
	b = _make_board()
	_pillar(b, Vector2i(2, 3))
	assert_equal(BoardQuery.has_line_of_sight(b, Vector2i(0, 0), Vector2i(3, 3)), false, "反向贴角(2,3)挡对角视线")
	b = _make_board()
	_pillar(b, Vector2i(1, 1))
	assert_equal(BoardQuery.has_line_of_sight(b, Vector2i(0, 0), Vector2i(3, 3)), false, "对角中段(1,1)挡视线")


func _test_los_symmetry_sweep() -> void:
	var b := _make_board()
	for c: Vector2i in [Vector2i(2, 2), Vector2i(4, 1), Vector2i(5, 5), Vector2i(1, 6), Vector2i(3, 0)]:
		_pillar(b, c)
	for y in 8:
		for x in 8:
			for y2 in 8:
				for x2 in 8:
					var a := Vector2i(x, y)
					var c := Vector2i(x2, y2)
					if BoardQuery.has_line_of_sight(b, a, c) != BoardQuery.has_line_of_sight(b, c, a):
						failures().append("视线不对称 %s <-> %s" % [a, c])
						return


func _test_los_wall_blocks_movement_not_sight() -> void:
	var b := _make_board()
	_wall(b, Vector2i(1, 0))
	assert_true(BoardQuery.has_line_of_sight(b, Vector2i(0, 0), Vector2i(3, 0)), "墙不挡视线")
	assert_equal(BoardQuery.reachable_cells(b, Vector2i(0, 0), 2).has(Vector2i(2, 0)), false, "墙挡移动")


func _test_reachable_budget_and_bounds() -> void:
	var b := _make_board()
	var mid := BoardQuery.reachable_cells(b, Vector2i(4, 4), 2)
	assert_equal(mid.size(), 12, "中心 2 步可达 12 格（Manhattan 环去掉起点）")
	assert_equal(mid.has(Vector2i(4, 4)), false, "不含起点")
	for cell: Vector2i in mid:
		assert_true(absi(cell.x - 4) + absi(cell.y - 4) <= 2, "可达格在射程内")
	var corner := BoardQuery.reachable_cells(b, Vector2i(0, 0), 2)
	assert_equal(corner.size(), 5, "角上 2 步可达 5 格（受盘边裁剪）")
	assert_true(corner.has(Vector2i(2, 0)) and corner.has(Vector2i(0, 2)) and corner.has(Vector2i(1, 1)), "角上可达集正确")
	assert_equal(BoardQuery.reachable_cells(b, Vector2i(0, 0), 0), [], "0 步无可达")


func _test_reachable_blocked_by_wall_and_occupancy() -> void:
	var b := _make_board()
	_wall(b, Vector2i(1, 0))
	var r := BoardQuery.reachable_cells(b, Vector2i(0, 0), 2)
	assert_equal(r.has(Vector2i(2, 0)), false, "墙阻断后方格")
	assert_true(r.has(Vector2i(1, 1)) and r.has(Vector2i(0, 2)), "可绕行其余格")

	b = _make_board()
	b.place_unit(9, Vector2i(1, 0))
	var r2 := BoardQuery.reachable_cells(b, Vector2i(0, 0), 2)
	assert_equal(r2.has(Vector2i(1, 0)), false, "占用格不可达")
	assert_equal(r2.has(Vector2i(2, 0)), false, "占用格阻断后方")


func _test_find_path() -> void:
	var b := _make_board()
	var p := Pathfinder.find_path(b, Vector2i(0, 0), Vector2i(3, 3))
	assert_equal(p.size(), 7, "空盘最短路径 7 格")
	assert_equal(p[0], Vector2i(0, 0), "路径含起点")
	assert_equal(p[p.size() - 1], Vector2i(3, 3), "路径含终点")
	for i in range(1, p.size()):
		var d: Vector2i = p[i] - p[i - 1]
		assert_equal(absi(d.x) + absi(d.y), 1, "路径正交连续")

	assert_equal(Pathfinder.find_path(b, Vector2i(0, 0), Vector2i(0, 0)), [Vector2i(0, 0)], "同格路径")
	assert_equal(Pathfinder.find_path(b, Vector2i(0, 0), Vector2i(9, 9)), [], "越界目标无路径")

	_wall(b, Vector2i(1, 0))
	var detour := Pathfinder.find_path(b, Vector2i(0, 0), Vector2i(3, 0))
	assert_true(detour.size() > 0, "可绕墙到目标")
	assert_equal(detour.has(Vector2i(1, 0)), false, "绕行不穿墙")

	var b2 := _make_board()
	b2.place_unit(5, Vector2i(3, 0))
	assert_equal(Pathfinder.find_path(b2, Vector2i(0, 0), Vector2i(3, 0)), [], "目标被占无路径")


func _test_target_cells() -> void:
	var b := _make_board()
	assert_equal(BoardQuery.get_target_cells(b, Vector2i(4, 4), 1, false).size(), 4, "射程 1 = 4 邻格")
	assert_equal(BoardQuery.get_target_cells(b, Vector2i(4, 4), 2, false).size(), 12, "射程 2 = 12 格")
	assert_equal(BoardQuery.get_target_cells(b, Vector2i(4, 4), 2, true).size(), 12, "空盘射程 2 全部可见")
	assert_equal(BoardQuery.get_target_cells(b, Vector2i(4, 4), 2, false).has(Vector2i(4, 4)), false, "不含自身")

	var b2 := _make_board()
	_pillar(b2, Vector2i(4, 5))
	var los := BoardQuery.get_target_cells(b2, Vector2i(4, 4), 3, true)
	assert_true(los.has(Vector2i(4, 5)), "障碍格自身可为目标（端格不挡）")
	assert_equal(los.has(Vector2i(4, 6)), false, "障碍后方被 LoS 过滤")
	assert_equal(los.has(Vector2i(4, 7)), false, "更后方也被过滤")
	var nolos := BoardQuery.get_target_cells(b2, Vector2i(4, 4), 3, false)
	assert_true(nolos.has(Vector2i(4, 6)) and nolos.has(Vector2i(4, 7)), "不要求 LoS 时含障碍后方")
