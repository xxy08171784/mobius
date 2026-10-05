extends "res://tests/test_case.gd"
## EnemyPlanner / 行为表测试（B3）。run() -> Array[String]，空 = 全过。
## 覆盖：目标策略、最近目标与平手、锁定格子优先（接近）、降级路径、序列循环、非法状态空意图。


func run() -> Array[String]:
	reset()
	_test_attack_locks_nearest_player()
	_test_target_tie_break()
	_test_defend_locks_self()
	_test_charge_locks_target()
	_test_approach_locks_cell()
	_test_approach_blocked_degrades()
	_test_no_player_degrades()
	_test_absent_enemy_empty_intent()
	_test_sequence_cycles()
	return failures()


func _make_board() -> BoardState:
	return BoardState.new(8, 8)


func _enemy_at(board: BoardState, unit_id: int, cell: Vector2i) -> UnitState:
	var e := UnitState.create(unit_id, &"unit.enemy", UnitState.Team.ENEMY, 20)
	board.place_unit(unit_id, cell)
	return e


func _player_at(board: BoardState, unit_id: int, cell: Vector2i) -> UnitState:
	var p := UnitState.create(unit_id, &"unit.player", UnitState.Team.PLAYER, 30)
	board.place_unit(unit_id, cell)
	return p


func _action(id: StringName, kind: EnemyActionDef.Kind, policy: EnemyActionDef.TargetPolicy, damage: int = 0, block: int = 0, move_steps: int = 1) -> EnemyActionDef:
	var a := EnemyActionDef.new()
	a.id = id
	a.kind = kind
	a.target_policy = policy
	a.damage = damage
	a.block = block
	a.move_steps = move_steps
	return a


func _behavior(actions: Array[EnemyActionDef], fallback: StringName = &"") -> SequenceBehaviorDef:
	var b := SequenceBehaviorDef.new()
	b.id = &"behavior.test"
	b.sequence = actions
	b.fallback_action_id = fallback
	return b


func _test_attack_locks_nearest_player() -> void:
	var board := _make_board()
	var enemy := _enemy_at(board, 1, Vector2i(0, 0))
	var player := _player_at(board, 2, Vector2i(3, 0))
	var act := _action(&"act.attack", EnemyActionDef.Kind.ATTACK, EnemyActionDef.TargetPolicy.PLAYER, 6)
	var intent := EnemyPlanner.plan(board, enemy, _behavior([act]), 0, [player])
	assert_equal(intent.action_id, &"act.attack", "行动 ID")
	assert_equal(intent.actor_id, 1, "发起者")
	assert_equal(intent.locked_unit_id, 2, "锁定最近玩家")
	assert_equal(intent.locked_cell, Vector2i(3, 0), "锁定目标格")
	assert_equal(intent.affected_cells, [Vector2i(3, 0)], "影响范围")
	assert_equal(intent.magnitude, 6, "预告伤害")
	assert_equal(intent.is_fallback, false, "非降级")


func _test_target_tie_break() -> void:
	var board := _make_board()
	var enemy := _enemy_at(board, 1, Vector2i(0, 0))
	var near := _player_at(board, 9, Vector2i(2, 0))   # 距离 2
	var far := _player_at(board, 3, Vector2i(0, 3))    # 距离 3
	var act := _action(&"a", EnemyActionDef.Kind.ATTACK, EnemyActionDef.TargetPolicy.PLAYER)
	var intent := EnemyPlanner.plan(board, enemy, _behavior([act]), 0, [far, near])
	assert_equal(intent.locked_unit_id, 9, "取更近者")

	# 等距平手 -> 较小 unit_id
	var board2 := _make_board()
	var e2 := _enemy_at(board2, 1, Vector2i(0, 0))
	var p_a := _player_at(board2, 5, Vector2i(2, 0))
	var p_b := _player_at(board2, 7, Vector2i(0, 2))
	var intent2 := EnemyPlanner.plan(board2, e2, _behavior([act]), 0, [p_b, p_a])
	assert_equal(intent2.locked_unit_id, 5, "等距平手取较小 unit_id")


func _test_defend_locks_self() -> void:
	var board := _make_board()
	var enemy := _enemy_at(board, 1, Vector2i(4, 4))
	var act := _action(&"act.defend", EnemyActionDef.Kind.DEFEND, EnemyActionDef.TargetPolicy.SELF, 0, 5)
	var intent := EnemyPlanner.plan(board, enemy, _behavior([act]), 0, [])
	assert_equal(intent.locked_unit_id, 1, "防御锁自身")
	assert_equal(intent.locked_cell, Vector2i(4, 4), "锁定自身格")
	assert_equal(intent.magnitude, 5, "预告护盾")


func _test_charge_locks_target() -> void:
	var board := _make_board()
	var enemy := _enemy_at(board, 1, Vector2i(0, 0))
	var player := _player_at(board, 2, Vector2i(5, 0))
	var act := _action(&"act.charge", EnemyActionDef.Kind.CHARGE, EnemyActionDef.TargetPolicy.PLAYER, 20)
	act.charge_turns = 2
	var intent := EnemyPlanner.plan(board, enemy, _behavior([act]), 0, [player])
	assert_equal(intent.action_id, &"act.charge", "蓄力行动")
	assert_equal(intent.locked_cell, Vector2i(5, 0), "蓄力也先锁定目标")
	assert_equal(intent.magnitude, 20, "预告伤害")


func _test_approach_locks_cell() -> void:
	var board := _make_board()
	var enemy := _enemy_at(board, 1, Vector2i(0, 0))
	var player := _player_at(board, 2, Vector2i(0, 5))
	var act := _action(&"act.approach", EnemyActionDef.Kind.APPROACH, EnemyActionDef.TargetPolicy.PLAYER, 0, 0, 2)
	var intent := EnemyPlanner.plan(board, enemy, _behavior([act]), 0, [player])
	assert_equal(intent.locked_cell, Vector2i(0, 2), "接近落点=离目标最近的可达格")
	assert_equal(intent.is_fallback, false, "可推进不降级")


func _test_approach_blocked_degrades() -> void:
	var board := _make_board()
	var enemy := _enemy_at(board, 1, Vector2i(0, 0))
	var player := _player_at(board, 2, Vector2i(0, 1))  # 已贴脸，无双格可推进
	var act := _action(&"act.approach", EnemyActionDef.Kind.APPROACH, EnemyActionDef.TargetPolicy.PLAYER, 0, 0, 1)
	var intent := EnemyPlanner.plan(board, enemy, _behavior([act], &"act.attack"), 0, [player])
	assert_equal(intent.is_fallback, true, "无法推进 -> 降级")
	assert_equal(intent.action_id, &"act.attack", "降级到 fallback 行动")
	assert_equal(intent.locked_unit_id, 2, "降级仍锁定玩家")

	# 无 fallback -> 空意图
	var board2 := _make_board()
	var e2 := _enemy_at(board2, 1, Vector2i(0, 0))
	var p2 := _player_at(board2, 2, Vector2i(0, 1))
	var intent2 := EnemyPlanner.plan(board2, e2, _behavior([act], &""), 0, [p2])
	assert_equal(intent2.is_empty(), true, "无 fallback 降级为空意图")


func _test_no_player_degrades() -> void:
	var board := _make_board()
	var enemy := _enemy_at(board, 1, Vector2i(0, 0))
	var act := _action(&"a", EnemyActionDef.Kind.ATTACK, EnemyActionDef.TargetPolicy.PLAYER)
	var intent := EnemyPlanner.plan(board, enemy, _behavior([act], &"act.approach"), 0, [])
	assert_equal(intent.is_fallback, true, "无目标 -> 降级")
	assert_equal(intent.has_target(), false, "降级后无目标可锁")


func _test_absent_enemy_empty_intent() -> void:
	var board := _make_board()
	var enemy := _enemy_at(board, 1, Vector2i(0, 0))
	enemy.hp = 0
	var act := _action(&"a", EnemyActionDef.Kind.ATTACK, EnemyActionDef.TargetPolicy.PLAYER)
	assert_equal(EnemyPlanner.plan(board, enemy, _behavior([act]), 0, []).is_empty(), true, "死亡敌人 -> 空意图")

	var board2 := _make_board()
	var ghost := UnitState.create(9, &"u", UnitState.Team.ENEMY, 10)  # 未放置到盘上
	assert_equal(EnemyPlanner.plan(board2, ghost, _behavior([act]), 0, []).is_empty(), true, "不在场 -> 空意图")


func _test_sequence_cycles() -> void:
	var a := _action(&"act.a", EnemyActionDef.Kind.ATTACK, EnemyActionDef.TargetPolicy.PLAYER)
	var b := _action(&"act.b", EnemyActionDef.Kind.DEFEND, EnemyActionDef.TargetPolicy.SELF, 0, 3)
	var behavior := _behavior([a, b])
	assert_equal(behavior.action_def_for(0).id, &"act.a", "step0")
	assert_equal(behavior.action_def_for(1).id, &"act.b", "step1")
	assert_equal(behavior.action_def_for(2).id, &"act.a", "step2 回绕")
	assert_equal(_behavior([]).action_def_for(0), null, "空序列返回 null")
