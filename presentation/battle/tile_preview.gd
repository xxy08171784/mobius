extends Node2D
## 【预览·一次性】把归一化后的 16 张地块（assets/textures/tiles/act1/normalized）
## 按冻结规格（docs/battle_board_art_requirements.md）铺成等轴测棋盘，验证观感与对齐。
## 跑法：编辑器 F6 直接运行；命令行加 `-- --shot` 自动截图到 user://tile_preview.png 后退出。
## 对齐探针：画出 cell(0,0) 处理论菱形（300×200，中心=map_to_local），对照实际贴图菱形看是否重合。

const SRC_DIR := "res://assets/textures/tiles/act1/normalized"
const TILE_W := 300
const TILE_H := 200
const BLOCK_W := 340
const BLOCK_H := 300
const COLS := 6
const ROWS := 6

@export var board_scale: float = 0.55
@export var texture_origin := Vector2i(0, 0)   # TileData.texture_origin 补偿，暂默认 0

var _tile_layer: TileMapLayer = null
var _ysort_root: Node2D = null
var _source_ids: Array[int] = []
var _probe: Line2D = null


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var show_dots := args.has("--dots")
	_parse_origin(args)
	_build_tileset(show_dots)
	_build_board()
	_build_probe()
	_center_board()
	_add_legend(show_dots)
	if args.has("--shot"):
		_capture_and_quit()


func _parse_origin(args: Array) -> void:
	var i := 0
	while i < args.size():
		if args[i] == "--origin_x" and i + 1 < args.size():
			texture_origin.x = int(args[i + 1])
			i += 2
		elif args[i] == "--origin_y" and i + 1 < args.size():
			texture_origin.y = int(args[i + 1])
			i += 2
		else:
			i += 1
	print("[preview] texture_origin = ", texture_origin)


func _build_tileset(show_dots: bool) -> void:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_RIGHT
	ts.tile_size = Vector2i(TILE_W, TILE_H)

	var dir := DirAccess.open(SRC_DIR)
	if dir == null:
		push_error("[preview] 打不开 %s（先跑 tools/normalize_tiles.gd）" % SRC_DIR)
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".png"):
			names.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	names.sort()

	for fname: String in names:
		var img := Image.load_from_file(SRC_DIR.path_join(fname))
		if img == null:
			continue
		if show_dots:
			_stamp_center_dot(img)
		var tex := ImageTexture.create_from_image(img)
		var src := TileSetAtlasSource.new()
		src.texture = tex
		src.texture_region_size = Vector2i(BLOCK_W, BLOCK_H)
		src.create_tile(Vector2i(0, 0))
		var tile_data := src.get_tile_data(Vector2i(0, 0), 0)
		tile_data.texture_origin = texture_origin
		_source_ids.append(ts.add_source(src))

	if _source_ids.is_empty():
		push_error("[preview] 没有可用地块。")
		return

	_tile_layer = TileMapLayer.new()
	_tile_layer.tile_set = ts
	_tile_layer.y_sort_enabled = true


## 调试：在画布菱形中心 (170,120) 打红点，暴露实际绘制位置（对照 map_to_local 探针）。
func _stamp_center_dot(img: Image) -> void:
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			var p := Vector2i(170 + dx, 120 + dy)
			if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
				img.set_pixelv(p, Color(1, 0, 0, 1))


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


func _build_probe() -> void:
	if _tile_layer == null:
		return
	var center: Vector2 = _tile_layer.map_to_local(Vector2i(0, 0))
	var rx := float(TILE_W) * 0.5
	var ry := float(TILE_H) * 0.5
	_probe = Line2D.new()
	_probe.width = 4.0
	_probe.default_color = Color(0.2, 0.9, 1.0, 0.95)
	var pts := PackedVector2Array([
		center + Vector2(0, -ry), center + Vector2(rx, 0),
		center + Vector2(0, ry), center + Vector2(-rx, 0), center + Vector2(0, -ry),
	])
	_probe.points = pts
	_ysort_root.add_child(_probe)

	# 再加两个示意单位（色块菱形），看遮挡与尺度的直观感受。
	_add_marker(Vector2i(1, 1), Color(0.35, 0.7, 1.0, 0.95), "玩家")
	_add_marker(Vector2i(4, 2), Color(1.0, 0.45, 0.45, 0.95), "敌人")


func _add_marker(cell: Vector2i, color: Color, text: String) -> void:
	var center: Vector2 = _tile_layer.map_to_local(cell)
	var marker := Node2D.new()
	marker.position = center
	var poly := Polygon2D.new()
	var rw := float(TILE_W) * 0.16
	var rh := float(TILE_H) * 0.16
	poly.polygon = PackedVector2Array([
		Vector2(0, -rh), Vector2(rw, 0), Vector2(0, rh), Vector2(-rw, 0),
	])
	poly.color = color
	poly.position = Vector2(0, -float(TILE_H) * 0.22)
	marker.add_child(poly)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.position = Vector2(-70, -float(TILE_H) * 0.28)
	label.custom_minimum_size = Vector2(140, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.add_child(label)
	_ysort_root.add_child(marker)


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


func _add_legend(show_dots: bool) -> void:
	var hud := Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_font_size_override("font_size", 16)
	hud.text = "TilePreview · 画布 340×300 · 菱形 300×200\n" \
		+ "青色线 = cell(0,0) 的 map_to_local（=理论菱形中心）\n" \
		+ ("红点 = 每格贴图菱形中心(170,120) 实际落点（--dots 调试）\n" if show_dots else "") \
		+ "texture_origin = %s\n" % [texture_origin] \
		+ "F6 运行 · 命令行加 -- --shot 截图到 user://tile_preview.png"
	add_child(hud)


func _capture_and_quit() -> void:
	for i in range(6):
		await get_tree().process_frame
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("[preview] 截图失败：viewport 无纹理。")
		get_tree().quit(1)
		return
	var out := "user://tile_preview.png"
	img.save_png(out)
	print("[preview] 截图: %s" % ProjectSettings.globalize_path(out))
	get_tree().quit()
