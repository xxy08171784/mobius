extends "res://tests/test_case.gd"
## 攻击范围形状测试：方框（含对角，切比雪夫）/ 菱形（曼哈顿）/ 无视距离（全盘）。
## 兼容入口 BoardQuery.get_target_cells 保持旧菱形语义不变。


func run() -> Array[String]:
	reset()
	_test_box_includes_diagonals()
	_test_diamond_unchanged()
	_test_within_range_and_distance()
	_test_unlimited()
	_test_los_filter()
	return failures()


func _board() -> BoardState:
	return BoardState.new(8, 8)


func _pillar(board: BoardState, cell: Vector2i) -> void:
	var cs := CellState.new()
	cs.blocks_los = true
	board.set_cell(cell, cs)


func _test_box_includes_diagonals() -> void:
	var b := _board()
	var box1 := BoardQuery.get_target_cells_shaped(b, Vector2i(4, 4), 1, BoardQuery.RangeShape.BOX, false)
	assert_equal(box1.size(), 8, "方框半径1 = 8 邻格（含对角）")
	assert_true(box1.has(Vector2i(5, 5)), "方框含对角格")
	var box2 := BoardQuery.get_target_cells_shaped(b, Vector2i(4, 4), 2, BoardQuery.RangeShape.BOX, false)
	assert_equal(box2.size(), 24, "方框半径2 = 24 格（5x5 减自身）")
	assert_true(box2.has(Vector2i(6, 6)), "方框半径2 含远对角")


func _test_diamond_unchanged() -> void:
	var b := _board()
	# 兼容入口 = 菱形（旧语义），现有卡牌/测试不受影响。
	assert_equal(BoardQuery.get_target_cells(b, Vector2i(4, 4), 1, false).size(), 4, "兼容入口半径1 = 4 邻格")
	assert_equal(BoardQuery.get_target_cells(b, Vector2i(4, 4), 2, false).size(), 12, "兼容入口半径2 = 12 格")
	var dia := BoardQuery.get_target_cells_shaped(b, Vector2i(4, 4), 1, BoardQuery.RangeShape.DIAMOND, false)
	assert_equal(dia.has(Vector2i(5, 5)), false, "菱形不含对角")


func _test_within_range_and_distance() -> void:
	var a := Vector2i(4, 4)
	var diag := Vector2i(5, 5)
	assert_true(BoardQuery.within_range(BoardQuery.RangeShape.BOX, a, diag, 1), "方框含对角(半径1)")
	assert_equal(BoardQuery.within_range(BoardQuery.RangeShape.DIAMOND, a, diag, 1), false, "菱形对角超出半径1")
	assert_equal(BoardQuery.cell_distance(BoardQuery.RangeShape.BOX, a, diag), 1, "方框距离 = 切比雪夫")
	assert_equal(BoardQuery.cell_distance(BoardQuery.RangeShape.DIAMOND, a, diag), 2, "菱形距离 = 曼哈顿")


func _test_unlimited() -> void:
	var b := _board()
	var all := BoardQuery.get_target_cells_shaped(b, Vector2i(0, 0), 0, BoardQuery.RangeShape.UNLIMITED, false)
	assert_equal(all.size(), 63, "无视距离 = 全盘 64 格减自身")
	assert_true(all.has(Vector2i(7, 7)), "无视距离含远角")
	assert_true(
		BoardQuery.within_range(BoardQuery.RangeShape.UNLIMITED, Vector2i(0, 0), Vector2i(7, 7), 0),
		"无视距离恒真"
	)


func _test_los_filter() -> void:
	var b := _board()
	_pillar(b, Vector2i(4, 5))
	var los := BoardQuery.get_target_cells_shaped(b, Vector2i(4, 4), 2, BoardQuery.RangeShape.BOX, true)
	assert_true(los.has(Vector2i(4, 5)), "障碍格自身可为目标（端格不挡）")
	assert_equal(los.has(Vector2i(4, 6)), false, "障碍后方被 LoS 过滤")
	var nolos := BoardQuery.get_target_cells_shaped(b, Vector2i(4, 4), 2, BoardQuery.RangeShape.BOX, false)
	assert_true(nolos.has(Vector2i(4, 6)), "不要求 LoS 时含障碍后方")
