extends "res://tests/test_case.gd"
## 敌人移动规划测试：近战沿真实路径逼近 / 绕障碍 / 贴脸停手；
## 远程风筝（能打到就远离、打不到就接近）；威胁格并集。


func run() -> Array[String]:
	reset()
	_test_melee_approaches_along_path()
	_test_melee_detours_wall()
	_test_melee_in_range_holds()
	_test_ranged_kites_away()
	_test_ranged_approaches_when_out_of_range()
	_test_unlimited_kiter_already_farthest_holds()
	_test_execution_replans_toward_current_player()
	_test_threat_cells()
	return failures()


func _board() -> BoardState:
	return BoardState.new(8, 8)


func _enemy(board: BoardState, id: int, cell: Vector2i) -> UnitState:
	var e := UnitState.create(id, &"unit.enemy", UnitState.Team.ENEMY, 30)
	board.place_unit(id, cell)
	return e


func _wall(board: BoardState, cell: Vector2i) -> void:
	var cs := CellState.new()
	cs.traversable = false
	board.set_cell(cell, cs)


func _approach(kiting: bool, steps: int, range_: int = 1, shape: BoardQuery.RangeShape = BoardQuery.RangeShape.BOX) -> EnemyActionDef:
	var a := EnemyActionDef.new()
	a.id = &"a.approach"
	a.kind = EnemyActionDef.Kind.APPROACH
	a.target_policy = EnemyActionDef.TargetPolicy.PLAYER
	a.move_steps = steps
	a.range = range_
	a.range_shape = shape
	a.kiting = kiting
	return a


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _behavior(actions: Array[EnemyActionDef]) -> SequenceBehaviorDef:
	var b := SequenceBehaviorDef.new()
	b.id = &"behavior.test"
	b.sequence = actions
	return b


func _test_melee_approaches_along_path() -> void:
	var b := _board()
	var enemy := _enemy(b, 2, Vector2i(0, 0))
	var player := Vector2i(0, 5)
	var path := EnemyPlanner.plan_move(b, enemy, player, 2, _approach(false, 2))
	assert_true(path.size() >= 2, "近战应沿真实路径推进")
	assert_equal(path[0], Vector2i(0, 0), "路径含起点")
	assert_equal(path[path.size() - 1], Vector2i(0, 2), "2 步预算走到离玩家最近的可达格")


func _test_melee_detours_wall() -> void:
	var b := _board()
	_wall(b, Vector2i(1, 0))
	var enemy := _enemy(b, 2, Vector2i(0, 0))
	var player := Vector2i(2, 0)
	var path := EnemyPlanner.plan_move(b, enemy, player, 3, _approach(false, 3))
	assert_true(path.size() >= 2, "被墙挡时应绕行而非原地")
	assert_equal(path.has(Vector2i(1, 0)), false, "路径不穿墙")
	assert_true(_manhattan(path[path.size() - 1], player) < _manhattan(Vector2i(0, 0), player), "落点比起点更接近目标")


func _test_melee_in_range_holds() -> void:
	var b := _board()
	var enemy := _enemy(b, 2, Vector2i(0, 0))
	var player := Vector2i(1, 0)
	var path := EnemyPlanner.plan_move(b, enemy, player, 2, _approach(false, 2))
	assert_equal(path.size(), 0, "近战已贴脸 -> 原地不动（不横向挪动）")


func _test_ranged_kites_away() -> void:
	var b := _board()
	var enemy := _enemy(b, 2, Vector2i(0, 3))
	var player := Vector2i(0, 4)
	var path := EnemyPlanner.plan_move(b, enemy, player, 2, _approach(true, 2, 1))
	assert_true(path.size() >= 2, "远程怪应移动拉开")
	var dest := path[path.size() - 1]
	assert_true(_manhattan(dest, player) > _manhattan(Vector2i(0, 3), player), "远程怪能打到时应远离玩家")


func _test_ranged_approaches_when_out_of_range() -> void:
	var b := _board()
	var enemy := _enemy(b, 2, Vector2i(0, 0))
	var player := Vector2i(0, 6)
	var path := EnemyPlanner.plan_move(b, enemy, player, 2, _approach(true, 2, 2))
	assert_true(path.size() >= 2, "打不到时应移动接近")
	var dest := path[path.size() - 1]
	assert_true(_manhattan(dest, player) < _manhattan(Vector2i(0, 0), player), "打不到时应靠近以进入射程")


func _test_unlimited_kiter_already_farthest_holds() -> void:
	var b := _board()
	var enemy := _enemy(b, 2, Vector2i(0, 0))
	var player := Vector2i(7, 7)
	var path := EnemyPlanner.plan_move(b, enemy, player, 2, _approach(true, 2, 0, BoardQuery.RangeShape.UNLIMITED))
	assert_equal(path.size(), 0, "无视距离远程怪已在最远处 -> 原地")


func _test_execution_replans_toward_current_player() -> void:
	# 关键行为：意图在回合开始锁定，但【移动】在执行时按玩家**当前位置**重算。
	var streams := Phase3Fixture.rng("replan")
	var state := Phase3Fixture.base_state(streams, 20, 30, Vector2i(0, 0), Vector2i(0, 6))
	state.phase = BattleState.Phase.PLAYER_INPUT
	var approach := _approach(false, 2)
	var behavior := _behavior([approach])
	# 锁定意图（此刻玩家在 (0,0)）。
	state.enemy_intents[2] = EnemyPlanner.plan(state.board, state.get_unit(2), behavior, 0, [state.get_unit(1)])
	# 玩家移动到别处；执行时应朝新位置走，而非锁定的旧格。
	state.board.move_unit(1, Vector2i(7, 6))
	var result := TurnSystem.new().run_end_turn(state, streams, {2: behavior}, {approach.id: approach})
	assert_true(bool(result.get("ok", false)), "结束回合应成功")
	var enemy_cell := state.board.get_unit_cell(2)
	assert_true(
		_manhattan(enemy_cell, Vector2i(7, 6)) < _manhattan(Vector2i(0, 6), Vector2i(7, 6)),
		"执行时按玩家当前位置重算 -> 朝新位置走（实际=%s）" % str(enemy_cell)
	)


func _test_threat_cells() -> void:
	var b := _board()
	var enemy := _enemy(b, 2, Vector2i(4, 4))

	var melee := EnemyActionDef.new()
	melee.id = &"t.melee"
	melee.kind = EnemyActionDef.Kind.ATTACK
	melee.target_policy = EnemyActionDef.TargetPolicy.PLAYER
	melee.range = 1
	melee.range_shape = BoardQuery.RangeShape.BOX
	var cells := EnemyPlanner.threat_cells(b, 2, [melee])
	assert_equal(cells.size(), 8, "威胁格 = 3x3 方框（含对角）")
	assert_true(cells.has(Vector2i(5, 5)), "威胁格含对角")

	var sniper := EnemyActionDef.new()
	sniper.id = &"t.snipe"
	sniper.kind = EnemyActionDef.Kind.ATTACK
	sniper.target_policy = EnemyActionDef.TargetPolicy.PLAYER
	sniper.range_shape = BoardQuery.RangeShape.UNLIMITED
	var all := EnemyPlanner.threat_cells(b, 2, [sniper])
	assert_equal(all.size(), 63, "无视距离 -> 全盘可见格")

	var only_approach := EnemyPlanner.threat_cells(b, 2, [_approach(false, 2)])
	assert_equal(only_approach.size(), 0, "只有接近行动 -> 无威胁格")
	assert_equal(EnemyPlanner.threat_cells(b, 99, [melee]).size(), 0, "不存在敌人 -> 无威胁格")
