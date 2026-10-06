extends Node2D
## 【原型·一次性】等轴测战斗棋盘观感预览。不接任何规则层，只为确认：
##   1) 菱形地块能否无缝铺成斜 45° 棋盘；2) 有厚度的侧壁与 y 排序是否自然；
##   3) 点击→格子拾取是否正确；4) 5 张源图几何是否一致（不一致会自动归一化并告警）。
## 跑法：直接 F6 运行本场景；命令行加 `--shot`（放在 -- 之后）自动截图后退出。

const SRC_PATHS: Array[String] = [
	"res://temp/preview_block_01.png",
	"res://temp/preview_block_02.png",
	"res://temp/preview_block_03.png",
	"res://temp/preview_block_04.png",
	"res://temp/preview_block_05.png",
]

## 统一菱形尺寸（取地块1测得值；其余源图缩放归一化到它）。
const STD_W := 444
const STD_H := 286
## 单元贴图高度：2 × 最大的“侧壁下延”（实测各图 191–213），保证侧壁都装得下。
const BLOCK_W := STD_W
const BLOCK_H := 426
const TOP_PAD := (BLOCK_H - STD_H) / 2

const COLS := 8
const ROWS := 8

@export var board_scale: float = 0.22

var _tile_layer: TileMapLayer = null
var _ysort_root: Node2D = null
var _hud: Label = null
var _overlay: Control = null

var _source_ids: Array[int] = []
var _diamond := Vector2i(STD_W, STD_H)
var _block := Vector2i(BLOCK_W, BLOCK_H)
var _hover: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	_build_tileset()
	_build_board()
	_build_units()
	_center_board()
	_build_hud_and_overlay()
	_self_check()
	var user_args := OS.get_cmdline_user_args()
	if user_args.has("--shot") or OS.get_cmdline_args().has("--shot"):
		_capture_and_quit()


# ---- 1. 量图 + 归一化生成“菱形中心居中”的单元贴图 ----

func _build_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_RIGHT
	ts.tile_size = Vector2i(STD_W, STD_H)

	for i in range(SRC_PATHS.size()):
		var img := Image.load_from_file(SRC_PATHS[i])
		if img == null:
			push_error("载入失败: %s" % SRC_PATHS[i])
			continue
		var geo := _measure(img)
		_geometry_report(SRC_PATHS[i], geo)
		var tex := _make_cell_texture(img, geo)
		var src := TileSetAtlasSource.new()
		src.texture = tex
		src.texture_region_size = Vector2i(BLOCK_W, BLOCK_H)
		src.create_tile(Vector2i(0, 0))
		_source_ids.append(ts.add_source(src))

	if _source_ids.is_empty():
		push_error("没有可用地块。")
		return

	_tile_layer = TileMapLayer.new()
	_tile_layer.tile_set = ts
	_tile_layer.y_sort_enabled = true
	print("[预览] 单元统一为菱形 %dx%d，纹理 %dx%d，菱形中心居中，侧壁下延 %d" % [
		STD_W, STD_H, BLOCK_W, BLOCK_H, BLOCK_H / 2 - STD_H / 2,
	])


func _geometry_report(path: String, geo: Dictionary) -> void:
	print("[预览] %s  外框 x[%d..%d] y[%d..%d]  菱形 %dx%d" % [
		path.get_file(), geo["x0"], geo["x1"], geo["y0"], geo["y1"],
		geo["W"], geo["H"],
	])
	if geo["W"] != STD_W or geo["H"] != STD_H:
		push_warning("几何不一致：%s 菱形 %dx%d，缩放归一化到 %dx%d（非等比，约 %.1f%%）" % [
			path.get_file(), geo["W"], geo["H"], STD_W, STD_H,
			maxf(absf(float(STD_W) / float(geo["W"]) - 1.0), absf(float(STD_H) / float(geo["H"]) - 1.0)) * 100.0,
		])


## 量图：alpha 轮廓法测出顶面菱形 W/H 与外框。
func _measure(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var row_min := PackedInt32Array()
	var row_max := PackedInt32Array()
	row_min.resize(h)
	row_max.resize(h)
	var first := -1
	var last := -1
	var max_w := 0
	for y in range(h):
		var lo := -1
		var hi := -1
		for x in range(w):
			if img.get_pixel(x, y).a > 0.5:
				if lo < 0:
					lo = x
				hi = x
		row_min[y] = lo
		row_max[y] = hi
		if hi >= 0:
			if first < 0:
				first = y
			last = y
			max_w = maxi(max_w, hi - lo + 1)
	var band := first
	for y in range(first, last + 1):
		if row_max[y] - row_min[y] + 1 >= max_w - 1:
			band = y
			break
	var H := 2 * (band - first)
	var x0 := 99999
	var x1 := -1
	for y in range(first, last + 1):
		if row_min[y] >= 0:
			x0 = mini(x0, row_min[y])
			x1 = maxi(x1, row_max[y])
	return {
		"x0": x0, "x1": x1, "y0": first, "y1": last,
		"W": max_w, "H": H,
	}


## 裁剪出菱形+侧壁内容，缩放使菱形精确为 STD_W×STD_H，再放入以菱形中心居中的画布。
func _make_cell_texture(img: Image, geo: Dictionary) -> ImageTexture:
	var content := img.get_region(Rect2i(
		geo["x0"], geo["y0"], geo["W"], int(geo["y1"]) - int(geo["y0"]) + 1
	))
	var scale_y := float(STD_H) / float(geo["H"])
	var target_h := maxi(1, roundi(float(int(geo["y1"]) - int(geo["y0"]) + 1) * scale_y))
	content.resize(STD_W, target_h, Image.INTERPOLATE_BILINEAR)
	var dest := Image.create_empty(BLOCK_W, BLOCK_H, false, Image.FORMAT_RGBA8)
	dest.blit_rect(content, Rect2i(0, 0, STD_W, target_h), Vector2i(0, TOP_PAD))
	return ImageTexture.create_from_image(dest)


# ---- 2. 铺棋盘 ----

func _build_board() -> void:
	if _tile_layer == null:
		return
	_ysort_root = Node2D.new()
	_ysort_root.y_sort_enabled = true
	_ysort_root.scale = Vector2(board_scale, board_scale)
	add_child(_ysort_root)
	_ysort_root.add_child(_tile_layer)

	for row in range(ROWS):
		for col in range(COLS):
			var cell := Vector2i(col, row)
			var variant := absi(col * 7 + row * 3 + col * row) % _source_ids.size()
			_tile_layer.set_cell(cell, _source_ids[variant], Vector2i(0, 0))


# ---- 3. 两个单位标记（演示厚度排序） ----

func _build_units() -> void:
	if _tile_layer == null:
		return
	_add_marker(Vector2i(1, 1), Color(0.35, 0.70, 1.0), "玩家 20/20")
	_add_marker(Vector2i(5, 3), Color(1.0, 0.45, 0.45), "敌人 12/12")


func _add_marker(cell: Vector2i, color: Color, text: String) -> void:
	var center: Vector2 = _tile_layer.map_to_local(cell)
	var marker := Node2D.new()
	marker.position = center
	var poly := Polygon2D.new()
	var rw := float(_diamond.x) * 0.18
	var rh := float(_diamond.y) * 0.18
	poly.polygon = PackedVector2Array([
		Vector2(0, -rh), Vector2(rw, 0), Vector2(0, rh), Vector2(-rw, 0),
	])
	poly.color = color
	poly.position = Vector2(0, -float(_diamond.y) * 0.16)
	marker.add_child(poly)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 28)
	label.position = Vector2(-90, -float(_diamond.y) * 0.16 - rh - 34)
	label.custom_minimum_size = Vector2(180, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.add_child(label)
	_ysort_root.add_child(marker)


# ---- 4. 居中 ----

func _center_board() -> void:
	if _tile_layer == null or _ysort_root == null:
		return
	var minp := Vector2(1e9, 1e9)
	var maxp := Vector2(-1e9, -1e9)
	for row in range(ROWS):
		for col in range(COLS):
			var p: Vector2 = _tile_layer.map_to_local(Vector2i(col, row))
			minp = minp.min(p)
			maxp = maxp.max(p)
	var board_center: Vector2 = (minp + maxp) * 0.5
	var view_center: Vector2 = get_viewport_rect().size * 0.5
	_ysort_root.position = view_center - board_center * board_scale


# ---- 5. HUD + 拾取覆盖层 ----

func _build_hud_and_overlay() -> void:
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 18)
	add_child(_hud)
	_update_hud(Vector2i(-1, -1))

	_overlay = Control.new()
	_overlay.position = Vector2.ZERO
	_overlay.size = get_viewport_rect().size
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.draw.connect(_draw_overlay)
	_overlay.gui_input.connect(_on_overlay_input)
	_overlay.mouse_exited.connect(func() -> void:
		_hover = Vector2i(-1, -1)
		_update_hud(_hover)
		_overlay.queue_redraw())
	add_child(_overlay)


func _on_overlay_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := _cell_at(get_global_mouse_position())
		if cell != _hover:
			_hover = cell
			_update_hud(cell)
			_overlay.queue_redraw()
	elif event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _cell_at(get_global_mouse_position())
		if _inside(cell):
			print("[预览] 点击格子 %s  ->  %s" % [str(cell), _cell_name(cell)])
			_update_hud(cell)


## 屏幕坐标 -> 格子：全程走 TileMapLayer 的逆变换（与画地块同一来源）。
func _cell_at(global_pos: Vector2) -> Vector2i:
	if _tile_layer == null:
		return Vector2i(-1, -1)
	var local: Vector2 = _tile_layer.get_global_transform().affine_inverse() * global_pos
	return _tile_layer.local_to_map(local)


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < COLS and cell.y < ROWS


func _cell_name(cell: Vector2i) -> String:
	if cell == Vector2i(1, 1):
		return "玩家"
	if cell == Vector2i(5, 3):
		return "敌人"
	return "空格"


func _draw_overlay() -> void:
	if _tile_layer == null or not _inside(_hover):
		return
	# overlay 位于 (0,0) 且无变换，其局部坐标 == 全局坐标，可直接画。
	var center: Vector2 = _tile_layer.to_global(_tile_layer.map_to_local(_hover))
	var s: float = board_scale
	var rx := float(_diamond.x) * 0.5 * s
	var ry := float(_diamond.y) * 0.5 * s
	var pts := PackedVector2Array([
		center + Vector2(0, -ry), center + Vector2(rx, 0),
		center + Vector2(0, ry), center + Vector2(-rx, 0),
	])
	_overlay.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 0.9, 0.2, 0.95), 2.0)


func _update_hud(cell: Vector2i) -> void:
	if _hud == null:
		return
	_hud.text = "等轴测棋盘预览  菱形 %dx%d  纹理 %dx%d  缩放 %.2f\n悬停/点击格子: %s" % [
		_diamond.x, _diamond.y, _block.x, _block.y, board_scale,
		("(%d, %d)" % [cell.x, cell.y]) if _inside(cell) else "—",
	]


# ---- 6. 自检 ----

func _self_check() -> void:
	if _tile_layer == null:
		return
	var bad := 0
	for row in range(ROWS):
		for col in range(COLS):
			var cell := Vector2i(col, row)
			var back: Vector2i = _tile_layer.local_to_map(_tile_layer.map_to_local(cell))
			if back != cell:
				bad += 1
	print("[预览] 自检 local_to_map(map_to_local(c))：%s" % ("全部通过" if bad == 0 else "%d 格不匹配" % bad))


# ---- 7. 截图（--shot） ----

func _capture_and_quit() -> void:
	for i in range(6):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("截图失败：viewport 无纹理。")
		get_tree().quit(1)
		return
	var out := "user://iso_preview.png"
	img.save_png(out)
	print("[预览] 截图: %s" % ProjectSettings.globalize_path(out))
	get_tree().quit()
