class_name IsoGrid
extends RefCounted
## 等轴测棋盘的纯几何工具（无状态、可无头测试）。
##
## 逻辑坐标恒为 BoardState 的 Vector2i(col=x, row=y)，直接作为 TileMapLayer 的 cell。
## 地块规格见 docs/battle_board_art_requirements.md：画布 340×300、顶面菱形 300×200、菱形中心 (170,120)。
##
## 与 TileMapLayer 的关系（关键）：
##   - Godot 以 map_to_local(cell) 为中心绘制整张画布（region 340×300），再按 -texture_origin 偏移。
##   - 因此菱形中心并不正好落在 map_to_local(cell)，而是偏移 CENTER_OFFSET（见下）。
##   - 本类把“cell ↔ 菱形中心”这一对换算收口，高亮、单位摆放、鼠标拾取全部只走这两个函数。

## 顶面菱形尺寸（与 TileSet.tile_size 一致；决定错位步长，不可随意改）。
const DIAMOND_W := 300
const DIAMOND_H := 200
## 单格画布尺寸（含侧壁；与 TileSetAtlasSource.texture_region_size 一致）。
const CANVAS_W := 340
const CANVAS_H := 300

## 菱形中心相对 map_to_local(cell) 的固定偏移。
## 推导：画布中心 (170,150) 落在 map_to_local，而菱形中心在画布内为 (170,120)（高 30px），
## 故菱形中心 = map_to_local - (0,30) = map_to_local + CENTER_OFFSET。
## 目视若发现单位/高亮整体纵向偏 ~30px，改这一个常量即可（备选值 (20,20)，取决于 Godot 用的是
## texture_region_size 还是 tile_size 做居中基准）。
const CENTER_OFFSET := Vector2i(0, -30)


## cell → 该格菱形中心的 tile-layer 局部坐标。
static func center_of(tile_layer: TileMapLayer, cell: Vector2i) -> Vector2:
	return tile_layer.map_to_local(cell) + Vector2(CENTER_OFFSET)


## tile-layer 局部坐标 → cell（center_of 的逆）。
static func cell_at(tile_layer: TileMapLayer, local_pos: Vector2) -> Vector2i:
	return tile_layer.local_to_map(local_pos - Vector2(CENTER_OFFSET))


## 以 center 为中心的菱形四角（闭合，首尾同点），供填充/描边绘制。
static func diamond_points(center: Vector2, half_w: float, half_h: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0, -half_h),
		center + Vector2(half_w, 0),
		center + Vector2(0, half_h),
		center + Vector2(-half_w, 0),
		center + Vector2(0, -half_h),
	])


## 整盘地块的局部包围盒（含画布边距与侧壁），供自动缩放居中。
static func board_bounds(tile_layer: TileMapLayer, cols: int, rows: int) -> Rect2:
	if cols <= 0 or rows <= 0:
		return Rect2()
	var min_point := Vector2(INF, INF)
	var max_point := Vector2(-INF, -INF)
	for row in range(rows):
		for col in range(cols):
			var center := center_of(tile_layer, Vector2i(col, row))
			var top_left := center - Vector2(float(CANVAS_W) * 0.5, float(CANVAS_H) * 0.5)
			var bottom_right := top_left + Vector2(CANVAS_W, CANVAS_H)
			min_point = min_point.min(top_left)
			max_point = max_point.max(bottom_right)
	return Rect2(min_point, max_point - min_point)


## 让整盘贴合可用区域（含边距）的缩放系数。
static func fit_scale(content_size: Vector2, avail_size: Vector2, margin: float) -> float:
	var usable := avail_size - Vector2(margin, margin) * 2.0
	if content_size.x <= 0.0 or content_size.y <= 0.0:
		return 1.0
	var sx := usable.x / content_size.x
	var sy := usable.y / content_size.y
	return maxf(0.01, minf(sx, sy))
