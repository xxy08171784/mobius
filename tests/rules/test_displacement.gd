extends "res://tests/test_case.gd"
## 位移规则测试（B1，combat_rules §9）。run() -> Array[String]，空 = 全过。
## 覆盖：移动预算/可达、击退遇墙/单位/盘边停下、传送忽略地形、交换不要求路径。


func run() -> Array[String]:
	reset()
	_test_move()
	_test_push_free()
	_test_push_blocked_and_edge()
	_test_push_direction_validation()
	_test_teleport()
	_test_swap()
	return failures()


func _make_board() -> BoardState:
	return BoardState.new(8, 8)


func _wall(board: BoardState, cell: Vector2i) -> void:
	var cs := CellState.new()
	cs.traversable = false
	board.set_cell(cell, cs)


func _test_move() -> void:
	var b := _make_board()
	b.place_unit(1, Vector2i(0, 0))
	var ok := Displacement.move(b, 1, Vector2i(2, 0), 2)
	assert_true(ok.moved, "预算内移动成功")
	assert_equal(ok.to_cell, Vector2i(2, 0), "移动到目标格")
	assert_equal(ok.path.size(), 3, "路径含起点终点")
	assert_equal(b.get_unit_cell(1), Vector2i(2, 0), "盘上位置更新")

	b = _make_board()
	b.place_unit(1, Vector2i(0, 0))
	var budget := Displacement.move(b, 1, Vector2i(2, 0), 1)
	assert_equal(budget.moved, false, "超出预算拒绝")
	assert_equal(budget.reason, DisplacementResult.REASON_OUT_OF_BUDGET, "原因 out_of_budget")
	assert_equal(b.get_unit_cell(1), Vector2i(0, 0), "失败零副作用")

	b = _make_board()
	b.place_unit(1, Vector2i(0, 0))
	var far := Displacement.move(b, 1, Vector2i(9, 9), 5)
	assert_equal(far.reason, DisplacementResult.REASON_NO_PATH, "越界目标 no_path")

	b = _make_board()
	b.place_unit(1, Vector2i(0, 0))
	b.place_unit(2, Vector2i(1, 0))
	var occ := Displacement.move(b, 1, Vector2i(1, 0), 2)
	assert_equal(occ.reason, DisplacementResult.REASON_NO_PATH, "目标被占 no_path")

	b = _make_board()
	b.place_unit(1, Vector2i(3, 3))
	var same := Displacement.move(b, 1, Vector2i(3, 3), 2)
	assert_equal(same.reason, DisplacementResult.REASON_SAME_CELL, "同格 same_cell")

	b = _make_board()
	var nou := Displacement.move(b, 99, Vector2i(1, 1), 2)
	assert_equal(nou.reason, DisplacementResult.REASON_NO_UNIT, "无此单位 no_unit")


func _test_push_free() -> void:
	var b := _make_board()
	b.place_unit(1, Vector2i(0, 0))
	var r := Displacement.push(b, 1, Vector2i(1, 0), 2)
	assert_true(r.moved, "击退成功")
	assert_equal(r.to_cell, Vector2i(2, 0), "击退 2 格")
	assert_equal(r.path, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)], "逐格路径")
	assert_equal(b.get_unit_cell(1), Vector2i(2, 0), "位置更新")

	b = _make_board()
	b.place_unit(1, Vector2i(1, 1))
	var diag := Displacement.push(b, 1, Vector2i(1, -1), 1)
	assert_true(diag.moved, "对角击退可行")
	assert_equal(diag.to_cell, Vector2i(2, 0), "对角落点")


func _test_push_blocked_and_edge() -> void:
	var b := _make_board()
	b.place_unit(1, Vector2i(0, 0))
	_wall(b, Vector2i(2, 0))
	var w := Displacement.push(b, 1, Vector2i(1, 0), 3)
	assert_true(w.moved, "击退遇墙仍移动一段")
	assert_equal(w.to_cell, Vector2i(1, 0), "停在墙前")
	assert_equal(w.reason, DisplacementResult.REASON_WALL, "原因 wall")
	assert_equal(w.path, [Vector2i(0, 0), Vector2i(1, 0)], "只经可行格")

	b = _make_board()
	b.place_unit(1, Vector2i(0, 0))
	b.place_unit(2, Vector2i(2, 0))
	var u := Displacement.push(b, 1, Vector2i(1, 0), 3)
	assert_equal(u.to_cell, Vector2i(1, 0), "停在单位前")
	assert_equal(u.reason, DisplacementResult.REASON_UNIT_BLOCK, "原因 unit_block")

	b = _make_board()
	b.place_unit(1, Vector2i(6, 0))
	var e := Displacement.push(b, 1, Vector2i(1, 0), 5)
	assert_true(e.moved, "向盘边仍移动")
	assert_equal(e.to_cell, Vector2i(7, 0), "停在边缘不移出")
	assert_equal(e.reason, DisplacementResult.REASON_EDGE, "原因 edge")


func _test_push_direction_validation() -> void:
	var b := _make_board()
	b.place_unit(1, Vector2i(4, 4))
	var bad := Displacement.push(b, 1, Vector2i(2, 0), 2)
	assert_equal(bad.moved, false, "非法方向拒绝")
	assert_equal(bad.reason, DisplacementResult.REASON_BAD_DIRECTION, "原因 bad_direction")
	var zero := Displacement.push(b, 1, Vector2i.ZERO, 2)
	assert_equal(zero.reason, DisplacementResult.REASON_BAD_DIRECTION, "零方向拒绝")
	var zero_dist := Displacement.push(b, 1, Vector2i(1, 0), 0)
	assert_equal(zero_dist.reason, DisplacementResult.REASON_SAME_CELL, "0 距离不移动")


func _test_teleport() -> void:
	var b := _make_board()
	b.place_unit(1, Vector2i(0, 0))
	var ok := Displacement.teleport(b, 1, Vector2i(7, 7))
	assert_true(ok.moved, "传送到空格")
	assert_equal(ok.to_cell, Vector2i(7, 7), "落点正确")
	assert_equal(b.get_unit_cell(1), Vector2i(7, 7), "位置更新")

	b = _make_board()
	b.place_unit(1, Vector2i(0, 0))
	_wall(b, Vector2i(5, 5))
	var onto_wall := Displacement.teleport(b, 1, Vector2i(5, 5))
	assert_true(onto_wall.moved, "传送忽略地形可走性（§9 字面：盘内+空格）")
	assert_equal(onto_wall.to_cell, Vector2i(5, 5), "落在墙格")

	b = _make_board()
	b.place_unit(1, Vector2i(0, 0))
	b.place_unit(2, Vector2i(3, 3))
	var occ := Displacement.teleport(b, 1, Vector2i(3, 3))
	assert_equal(occ.reason, DisplacementResult.REASON_OCCUPIED, "目标被占 occupied")

	b = _make_board()
	b.place_unit(1, Vector2i(0, 0))
	var oob := Displacement.teleport(b, 1, Vector2i(-1, 0))
	assert_equal(oob.reason, DisplacementResult.REASON_OUT_OF_BOUNDS, "盘外 out_of_bounds")


func _test_swap() -> void:
	var b := _make_board()
	b.place_unit(1, Vector2i(0, 0))
	b.place_unit(2, Vector2i(5, 5))
	assert_true(Displacement.swap(b, Vector2i(0, 0), Vector2i(5, 5)), "交换成功")
	assert_equal(b.get_unit_at(Vector2i(0, 0)), 2, "A 格换入 2")
	assert_equal(b.get_unit_at(Vector2i(5, 5)), 1, "B 格换入 1")
	assert_equal(b.get_unit_cell(1), Vector2i(5, 5), "单位 1 反查正确")
	assert_equal(b.get_unit_cell(2), Vector2i(0, 0), "单位 2 反查正确")

	assert_equal(Displacement.swap(b, Vector2i(0, 0), Vector2i(0, 0)), false, "同格交换拒绝")
	assert_equal(Displacement.swap(b, Vector2i(0, 0), Vector2i(1, 1)), false, "空格无法交换")
	assert_equal(b.get_unit_at(Vector2i(0, 0)), 2, "失败后占用不变")
