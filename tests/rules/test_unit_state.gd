extends "res://tests/test_case.gd"
## UnitState 测试（B2）。run() -> Array[String]，空 = 全过。
## 重点：位置不在 UnitState（从 BoardState 查）、StatusState 接口、资源/状态访问器。


func run() -> Array[String]:
	reset()
	_test_create_and_basics()
	_test_resources()
	_test_block()
	_test_status_container()
	_test_position_authority_in_board()
	return failures()


func _test_create_and_basics() -> void:
	var u := UnitState.create(101, &"unit.warrior", UnitState.Team.PLAYER, 30)
	assert_equal(u.unit_id, 101, "unit_id")
	assert_equal(u.def_id, &"unit.warrior", "def_id")
	assert_equal(u.max_hp, 30, "max_hp")
	assert_equal(u.hp, 30, "初始满血")
	assert_true(u.is_alive(), "存活")
	assert_true(u.is_player(), "玩家阵营")
	u.hp = 0
	assert_equal(u.is_alive(), false, "0 血死亡")


func _test_resources() -> void:
	var u := UnitState.create(1, &"u", UnitState.Team.ENEMY, 10)
	assert_equal(u.get_resource(&"energy"), 0, "缺省资源为 0")
	u.set_resource(&"energy", 3)
	assert_equal(u.get_resource(&"energy"), 3, "set 生效")
	u.add_resource(&"energy", -1)
	assert_equal(u.get_resource(&"energy"), 2, "add 生效")
	u.add_resource(&"action", 1)
	assert_equal(u.get_resource(&"action"), 1, "新键 add 从 0 起")


func _test_block() -> void:
	var u := UnitState.create(1, &"u", UnitState.Team.ENEMY, 10)
	u.block = 15
	assert_equal(u.block, 15, "护盾可设")
	u.clear_block()
	assert_equal(u.block, 0, "回合开始清零")
	var e := UnitState.create(2, &"u", UnitState.Team.ENEMY, 10)
	assert_equal(e.is_player(), false, "敌人阵营")


func _test_status_container() -> void:
	var u := UnitState.create(1, &"u", UnitState.Team.ENEMY, 10)
	var poison := StatusState.new()
	poison.instance_id = 7
	poison.status_id = &"poison"
	u.set_status(7, poison)
	assert_true(u.has_status(7), "持有状态")
	assert_true(u.get_status(7) is StatusState, "状态容器使用 A1 StatusState")
	assert_equal(u.get_status(7).status_id, &"poison", "状态定义 ID 保存在 StatusState")
	var guard := StatusState.new()
	guard.instance_id = 3
	guard.status_id = &"guard"
	u.set_status(3, guard)
	assert_equal(u.status_ids(), [3, 7], "状态实例 ID 升序")
	u.remove_status(3)
	assert_equal(u.has_status(3), false, "移除生效")
	assert_equal(u.status_ids(), [7], "移除后序列")


func _test_position_authority_in_board() -> void:
	# 位置权威在 BoardState：UnitState 不存坐标，只能经盘查询。
	var u := UnitState.create(5, &"u", UnitState.Team.ENEMY, 10)
	assert_equal(u.get("cell"), null, "UnitState 无位置字段")
	var b := BoardState.new(8, 8)
	b.place_unit(u.unit_id, Vector2i(2, 3))
	assert_equal(b.get_unit_cell(u.unit_id), Vector2i(2, 3), "位置由 BoardState 权威查询")
	b.move_unit(u.unit_id, Vector2i(6, 6))
	assert_equal(b.get_unit_cell(u.unit_id), Vector2i(6, 6), "移动后由盘反映")
