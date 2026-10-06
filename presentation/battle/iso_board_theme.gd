class_name IsoBoardTheme
extends RefCounted
## 运行时从 normalized/*.png 构建并缓存等轴测 TileSet（无手工编辑器步骤）。
## 规格冻结于 docs/battle_board_art_requirements.md；铺法沿用 tile_preview.gd。
## 若素材目录缺失/为空，get_tileset() 返回 null，BoardView 退化为纯色地板（可无头跑）。

const TILE_DIR := "res://assets/textures/tiles/act1/normalized"

static var _tileset: TileSet = null
static var _source_ids: Array[int] = []


## 首次调用扫描目录构建 TileSet 并缓存；失败返回 null（不抛错）。
static func get_tileset() -> TileSet:
	if _tileset != null:
		return _tileset
	var dir := DirAccess.open(TILE_DIR)
	if dir == null:
		push_warning("IsoBoardTheme: 打不开 %s（棋盘退回纯色地板）" % TILE_DIR)
		return null
	var names: Array[String] = []
	for fname: String in DirAccess.get_files_at(TILE_DIR):
		if fname.ends_with(".png"):
			names.append(fname)
	names.sort()
	if names.is_empty():
		push_warning("IsoBoardTheme: %s 没有地块 PNG" % TILE_DIR)
		return null

	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_RIGHT
	ts.tile_size = Vector2i(IsoGrid.DIAMOND_W, IsoGrid.DIAMOND_H)

	_source_ids.clear()
	for fname: String in names:
		var tex := load(TILE_DIR.path_join(fname)) as Texture2D
		if tex == null:
			# 兜底：素材尚未导入时退回原始解码（仅编辑器/开发期）。
			var img := Image.load_from_file(TILE_DIR.path_join(fname))
			if img != null:
				tex = ImageTexture.create_from_image(img)
		if tex == null:
			continue
		var src := TileSetAtlasSource.new()
		src.texture = tex
		src.texture_region_size = Vector2i(IsoGrid.CANVAS_W, IsoGrid.CANVAS_H)
		src.create_tile(Vector2i(0, 0))
		_source_ids.append(ts.add_source(src))

	if _source_ids.is_empty():
		push_warning("IsoBoardTheme: 地块 PNG 均无法加载")
		return null
	_tileset = ts
	return _tileset


static func has_tiles() -> bool:
	return _tileset != null


static func floor_source_ids() -> Array[int]:
	return _source_ids.duplicate()


## 确定性地板变体（与 tile_preview 同一公式，同 (def) 恒同格）。
static func floor_source_for(cell: Vector2i) -> int:
	if _source_ids.is_empty():
		return -1
	var index := absi(cell.x * 7 + cell.y * 3 + cell.x * cell.y) % _source_ids.size()
	return _source_ids[index]


## 墙/陷阱正式美术未入库：返回 -1，BoardView 退回地板并叠色块标记（接缝）。
static func wall_source_for(_cell: Vector2i) -> int:
	return -1


static func trap_source_for(_cell: Vector2i) -> int:
	return -1
