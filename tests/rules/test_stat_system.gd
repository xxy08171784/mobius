extends "res://tests/test_case.gd"
## StatSystem 计算顺序测试（B2）。run() -> Array[String]，空 = 全过。
## 锁定：基础 -> 固定 -> 百分比 -> 上下限 -> 向下取整（评审中优先：顺序写死）。

const NO_LOWER := 0.0
const NO_UPPER := INF


func run() -> Array[String]:
	reset()
	_test_base_and_flat()
	_test_percent_applies_after_flat()
	_test_floor_not_round()
	_test_clamp()
	_test_negative_percent()
	_test_compute_summed()
	return failures()


func _test_base_and_flat() -> void:
	assert_equal(StatSystem.compute(10.0, 0.0, 0.0, NO_LOWER, NO_UPPER), 10, "仅基础值")
	assert_equal(StatSystem.compute(10.0, 5.0, 0.0, NO_LOWER, NO_UPPER), 15, "固定加成")


func _test_percent_applies_after_flat() -> void:
	# 关键判别：若百分比先于固定，则为 10*1.5+10=25；正确顺序应为 (10+10)*1.5=30。
	assert_equal(StatSystem.compute(10.0, 10.0, 0.5, NO_LOWER, NO_UPPER), 30, "百分比作用于固定之后")
	assert_equal(StatSystem.compute(10.0, 0.0, 0.5, NO_LOWER, NO_UPPER), 15, "纯百分比")


func _test_floor_not_round() -> void:
	assert_equal(StatSystem.compute(5.0, 0.0, 0.5, NO_LOWER, NO_UPPER), 7, "7.5 向下取整为 7（非 round 8）")
	assert_equal(StatSystem.compute(5.0, 0.0, -0.5, NO_LOWER, NO_UPPER), 2, "2.5 向下取整为 2")


func _test_clamp() -> void:
	assert_equal(StatSystem.compute(3.0, -10.0, 0.0, 0.0, 99.0), 0, "低于下限钳到 0")
	assert_equal(StatSystem.compute(10.0, 0.0, 0.0, 0.0, 8.0), 8, "高于上限钳到 8")
	assert_equal(StatSystem.compute(5.0, 0.0, 0.0, 4.0, 6.0), 5, "界内不钳")


func _test_negative_percent() -> void:
	assert_equal(StatSystem.compute(10.0, 0.0, -0.25, NO_LOWER, NO_UPPER), 7, "-25% 作用于基础")


func _test_compute_summed() -> void:
	assert_equal(
		StatSystem.compute_summed(10.0, [5.0, 5.0], [0.25, 0.25], NO_LOWER, NO_UPPER),
		30,
		"固定/百分比各自求和后按序计算"
	)
