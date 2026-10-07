extends "res://tests/test_case.gd"
## IsoGrid 等轴测几何测试。run() -> Array[String]，空 = 全过。
## 覆盖：冻结尺寸常量 / 菱形几何 / cell↔局部坐标往返 / 与 map_to_local 一致 / 无 TileSet 兜底 / 包围盒 / 自适应缩放。
## 只用最小 TileSet（设 shape/layout/tile_size），不加载贴图——纯几何，可无头跑。


func run() -> Array[String]:
	reset()
	_test_frozen_constants()
	_test_diamond_geometry()
	_test_round_trip()
	_test_center_matches_map_to_local()
	_test_geometry_without_tileset()
	_test_bounds_cover_all_centers()
	_test_fit_scale()
	return failures()


func _make_layer() -> TileMapLayer:
	# 使用正式缺图回退，保证没有纹理时几何和拾取仍能覆盖 64 个不同格子。
	var ts := IsoBoardTheme.create_geometry_tileset()
	var layer := TileMapLayer.new()
	layer.tile_set = ts
	return layer


func _test_frozen_constants() -> void:
	assert_equal(IsoGrid.DIAMOND_W, 300, "菱形宽冻结 300")
	assert_equal(IsoGrid.DIAMOND_H, 200, "菱形高冻结 200")
	assert_equal(IsoGrid.CANVAS_W, 340, "画布宽冻结 340")
	assert_equal(IsoGrid.CANVAS_H, 300, "画布高冻结 300")
	assert_equal(IsoGrid.CENTER_OFFSET, Vector2i(0, -30), "菱形中心偏移")


func _test_diamond_geometry() -> void:
	var pts := IsoGrid.diamond_points(Vector2(10, 20), 3.0, 4.0)
	assert_equal(pts.size(), 5, "菱形 4 角 + 闭合点")
	assert_equal(pts[0], pts[4], "首尾闭合")
	assert_equal(pts[0], Vector2(10, 16), "上角")
	assert_equal(pts[1], Vector2(13, 20), "右角")
	assert_equal(pts[2], Vector2(10, 24), "下角")
	assert_equal(pts[3], Vector2(7, 20), "左角")


func _test_round_trip() -> void:
	var layer := _make_layer()
	var bad := 0
	var centers := {}
	for row in range(8):
		for col in range(8):
			var cell := Vector2i(col, row)
			centers[IsoGrid.center_of(layer, cell)] = true
			if IsoGrid.cell_at(layer, IsoGrid.center_of(layer, cell)) != cell:
				bad += 1
	assert_equal(bad, 0, "cell → 中心 → cell 往返（8×8 全覆盖）")
	assert_equal(centers.size(), 64, "缺图时 64 个格子不能叠在同一点")
	layer.free()


func _test_center_matches_map_to_local() -> void:
	var layer := _make_layer()
	var cell := Vector2i(3, 5)
	var expected := layer.map_to_local(cell) + Vector2(IsoGrid.CENTER_OFFSET)
	assert_equal(IsoGrid.center_of(layer, cell), expected, "中心 = map_to_local + CENTER_OFFSET")
	layer.free()


func _test_geometry_without_tileset() -> void:
	# 素材缺失时 tile_set 为 null：map_to_local 会报错并返回零向量，IsoGrid 必须改用常量公式，
	# 使几何与有 tile_set 时完全一致（否则纯色地板/单位会全部堆到原点）。
	var bare := TileMapLayer.new()  # 不设 tile_set
	var reference := _make_layer()
	var bad := 0
	for row in range(8):
		for col in range(8):
			var cell := Vector2i(col, row)
			if IsoGrid.center_of(bare, cell) != IsoGrid.center_of(reference, cell):
				bad += 1
			if IsoGrid.cell_at(bare, IsoGrid.center_of(bare, cell)) != cell:
				bad += 1
	assert_equal(bad, 0, "无 TileSet 时几何与有 TileSet 一致且可往返")
	assert_true(IsoGrid.board_bounds(bare, 8, 8).size.x > 0.0, "无 TileSet 时包围盒有效")
	bare.free()
	reference.free()


func _test_bounds_cover_all_centers() -> void:
	var layer := _make_layer()
	var bounds := IsoGrid.board_bounds(layer, 8, 8)
	assert_true(bounds.size.x > 0.0 and bounds.size.y > 0.0, "包围盒尺寸为正")
	var covered := true
	for row in range(8):
		for col in range(8):
			if not bounds.has_point(IsoGrid.center_of(layer, Vector2i(col, row))):
				covered = false
	assert_true(covered, "包围盒覆盖全部格中心")
	assert_equal(IsoGrid.board_bounds(layer, 0, 0), Rect2(), "空盘包围盒为空")
	layer.free()


func _test_fit_scale() -> void:
	var content := Vector2(1000, 500)
	assert_true(IsoGrid.fit_scale(content, Vector2(1000, 500), 0.0) > 0.0, "缩放为正")
	assert_equal(IsoGrid.fit_scale(content, Vector2(1000, 500), 0.0), 1.0, "恰好容纳 = 1.0")
	assert_equal(IsoGrid.fit_scale(content, Vector2(500, 500), 0.0), 0.5, "宽度受限取小")
	assert_equal(IsoGrid.fit_scale(content, Vector2(1000, 250), 0.0), 0.5, "高度受限取小")
	assert_true(IsoGrid.fit_scale(content, Vector2(200, 200), 0.0) < 1.0, "空间小则缩小")
	assert_equal(IsoGrid.fit_scale(Vector2.ZERO, Vector2(100, 100), 0.0), 1.0, "空内容退化 1.0")
