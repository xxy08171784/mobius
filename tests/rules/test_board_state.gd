extends "res://tests/test_case.gd"
## BoardState 占用原语测试（B1）。run() -> Array[String]，空 = 全过。
## 覆盖：越界 / 放置 / 一格一单位 / 墙 / 移动 / 移除 / 双向索引一致性 / 反查。


func run() -> Array[String]:
	reset()
	_test_default_board_and_bounds()
	_test_place_round_trip()
	_test_one_unit_per_cell()
	_test_place_blocks_wall_and_bounds()
	_test_no_implicit_move_on_re_place()
	_test_remove_frees_cell()
	_test_move_updates_indices()
	_test_move_failures_are_zero_side_effect()
	_test_default_open_cell_vs_wall_and_trap()
	_test_get_unit_ids_sorted()
	return failures()


func _make_board() -> BoardState:
	return BoardState.new(8, 8)


func _test_default_board_and_bounds() -> void:
	var b := _make_board()
	assert_equal(b.cols, 8, "default cols 8")
	assert_equal(b.rows, 8, "default rows 8")
	assert_true(b.is_inside(Vector2i(0, 0)), "origin inside")
	assert_true(b.is_inside(Vector2i(7, 7)), "max corner inside")
	assert_false_inside(b, Vector2i(8, 0), "x 越界")
	assert_false_inside(b, Vector2i(0, -1), "y 越界")
	assert_true(b.is_traversable(Vector2i(3, 3)), "缺省格可走")


func assert_false_inside(b: BoardState, cell: Vector2i, msg: String) -> void:
	assert_equal(b.is_inside(cell), false, msg)


func _test_place_round_trip() -> void:
	var b := _make_board()
	assert_true(b.place_unit(101, Vector2i(2, 3)), "放置 101@(2,3)")
	assert_equal(b.get_unit_at(Vector2i(2, 3)), 101, "占格反查")
	assert_equal(b.get_unit_cell(101), Vector2i(2, 3), "单位反查格")
	assert_true(b.is_occupied(Vector2i(2, 3)), "该格被占")
	assert_true(b.has_unit(101), "单位已放置")


func _test_one_unit_per_cell() -> void:
	var b := _make_board()
	assert_true(b.place_unit(1, Vector2i(4, 4)), "先放 1@(4,4)")
	assert_equal(b.place_unit(2, Vector2i(4, 4)), false, "同一格再放被拒")
	assert_equal(b.get_unit_at(Vector2i(4, 4)), 1, "占用未被覆盖")
	assert_equal(b.has_unit(2), false, "被拒单位未入盘")


func _test_place_blocks_wall_and_bounds() -> void:
	var b := _make_board()
	assert_equal(b.place_unit(1, Vector2i(20, 0)), false, "越界放置被拒")
	var wall := CellState.new()
	wall.traversable = false
	b.set_cell(Vector2i(1, 1), wall)
	assert_equal(b.place_unit(1, Vector2i(1, 1)), false, "墙格放置被拒")
	assert_equal(b.is_traversable(Vector2i(1, 1)), false, "墙格不可走")


func _test_no_implicit_move_on_re_place() -> void:
	var b := _make_board()
	assert_true(b.place_unit(1, Vector2i(0, 0)), "先放 1@(0,0)")
	assert_equal(b.place_unit(1, Vector2i(5, 5)), false, "已放置单位不可隐式搬移")
	assert_equal(b.get_unit_cell(1), Vector2i(0, 0), "位置未变")


func _test_remove_frees_cell() -> void:
	var b := _make_board()
	assert_true(b.place_unit(7, Vector2i(3, 3)), "放置 7@(3,3)")
	assert_true(b.remove_unit(7), "移除成功")
	assert_equal(b.get_unit_at(Vector2i(3, 3)), -1, "格已空")
	assert_equal(b.get_unit_cell(7), BoardState.INVALID_CELL, "单位已不在盘上")
	assert_equal(b.remove_unit(7), false, "重复移除返回 false")
	assert_equal(b.remove_unit(999), false, "移除未放置单位返回 false")


func _test_move_updates_indices() -> void:
	var b := _make_board()
	assert_true(b.place_unit(1, Vector2i(2, 2)), "放置 1@(2,2)")
	assert_true(b.move_unit(1, Vector2i(5, 6)), "移动到 (5,6)")
	assert_equal(b.get_unit_cell(1), Vector2i(5, 6), "反查新格")
	assert_equal(b.get_unit_at(Vector2i(2, 2)), -1, "旧格已空")
	assert_equal(b.get_unit_at(Vector2i(5, 6)), 1, "新格被占")
	assert_equal(b.move_unit(1, Vector2i(5, 6)), true, "移动到同格为幂等 true")


func _test_move_failures_are_zero_side_effect() -> void:
	var b := _make_board()
	assert_true(b.place_unit(1, Vector2i(2, 2)), "放置 1@(2,2)")
	assert_true(b.place_unit(2, Vector2i(3, 3)), "放置 2@(3,3)")
	var wall := CellState.new()
	wall.traversable = false
	b.set_cell(Vector2i(7, 7), wall)
	assert_equal(b.move_unit(1, Vector2i(3, 3)), false, "移入被占格被拒")
	assert_equal(b.move_unit(1, Vector2i(7, 7)), false, "移入墙格被拒")
	assert_equal(b.move_unit(1, Vector2i(10, 10)), false, "移出盘外被拒")
	assert_equal(b.move_unit(999, Vector2i(0, 0)), false, "未放置单位移动被拒")
	assert_equal(b.get_unit_cell(1), Vector2i(2, 2), "失败后位置不变")
	assert_equal(b.get_unit_at(Vector2i(2, 2)), 1, "失败后占用不变")
	assert_equal(b.get_unit_at(Vector2i(3, 3)), 2, "目标格占用不变")


func _test_default_open_cell_vs_wall_and_trap() -> void:
	var b := _make_board()
	assert_equal(b.blocks_los(Vector2i(0, 0)), false, "缺省格不挡视线")
	var pillar := CellState.new()
	pillar.blocks_los = true
	b.set_cell(Vector2i(6, 0), pillar)
	assert_equal(b.blocks_los(Vector2i(6, 0)), true, "柱子挡视线")
	assert_equal(b.is_traversable(Vector2i(6, 0)), true, "柱子不挡移动")
	var trap := CellState.new()
	trap.trap = true
	b.set_cell(Vector2i(4, 5), trap)
	assert_equal(b.is_trap(Vector2i(4, 5)), true, "陷阱格识别")
	assert_equal(b.is_traversable(Vector2i(4, 5)), true, "陷阱可进入")


func _test_get_unit_ids_sorted() -> void:
	var b := _make_board()
	b.place_unit(3, Vector2i(0, 0))
	b.place_unit(1, Vector2i(1, 0))
	b.place_unit(2, Vector2i(2, 0))
	assert_equal(b.get_unit_ids(), [1, 2, 3], "unit id 升序")
