extends "res://tests/test_case.gd"
## UnitView.facing_for 朝向映射测试。
## 回归：曾按逻辑轴 dx/dy 单轴分组，把 (0,+1)（屏幕右下）误判为 walk_l、(0,-1)（屏幕左上）
## 误判为 walk_r。等轴测 TILE_LAYOUT_DIAMOND_RIGHT 的屏幕横向位移 ∝ (dx+dy)，见 unit_view.gd。


func run() -> Array[String]:
	reset()
	_test_single_axis()
	_test_diagonals()
	_test_zero()
	return failures()


func _test_single_axis() -> void:
	assert_equal(
		UnitView.facing_for(Vector2i(1, 0)),
		UnitSpriteFrames.ANIM_RIGHT,
		"(1,0)=屏幕右上 → walk_r"
	)
	assert_equal(
		UnitView.facing_for(Vector2i(0, 1)),
		UnitSpriteFrames.ANIM_RIGHT,
		"(0,1)=屏幕右下 → walk_r（曾反）"
	)
	assert_equal(
		UnitView.facing_for(Vector2i(-1, 0)),
		UnitSpriteFrames.ANIM_LEFT,
		"(-1,0)=屏幕左下 → walk_l"
	)
	assert_equal(
		UnitView.facing_for(Vector2i(0, -1)),
		UnitSpriteFrames.ANIM_LEFT,
		"(0,-1)=屏幕左上 → walk_l（曾反）"
	)


func _test_diagonals() -> void:
	assert_equal(
		UnitView.facing_for(Vector2i(1, 1)),
		UnitSpriteFrames.ANIM_RIGHT,
		"(1,1)=屏幕水平右 → walk_r"
	)
	assert_equal(
		UnitView.facing_for(Vector2i(-1, -1)),
		UnitSpriteFrames.ANIM_LEFT,
		"(-1,-1)=屏幕水平左 → walk_l"
	)
	assert_equal(
		UnitView.facing_for(Vector2i(1, -1)),
		&"",
		"(1,-1)=屏幕竖直上 → 不变朝向"
	)
	assert_equal(
		UnitView.facing_for(Vector2i(-1, 1)),
		&"",
		"(-1,1)=屏幕竖直下 → 不变朝向"
	)


func _test_zero() -> void:
	assert_equal(
		UnitView.facing_for(Vector2i.ZERO),
		&"",
		"零位移 → 不变朝向"
	)
