class_name IsoBoardTheme
extends RefCounted
## 运行时从 normalized/*.png 构建并缓存等轴测 TileSet（无手工编辑器步骤）。
## 规格冻结于 docs/battle_board_art_requirements.md；铺法沿用 tile_preview.gd。
## 素材缺失时仍返回几何 TileSet，BoardView 退化为可正常拾取的纯色地板。

const TILE_DIR := "res://assets/textures/tiles/act1/normalized"

static var _tileset: TileSet = null
static var _source_ids: Array[int] = []


## 地块缺图不能丢失几何；map_to_local/local_to_map 都依赖 TileSet。
static func create_geometry_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_RIGHT
	ts.tile_size = Vector2i(IsoGrid.DIAMOND_W, IsoGrid.DIAMOND_H)
	return ts


## 通过资源目录读取原始逻辑名称；导出包内的 PNG 实际存为导入资源。
static func get_tileset() -> TileSet:
	if _tileset != null:
		return _tileset
	_tileset = create_geometry_tileset()
	_source_ids.clear()
	if not DirAccess.dir_exists_absolute(TILE_DIR):
		push_warning("IsoBoardTheme: 地块目录缺失，使用纯色棋盘")
		return _tileset
	var names: Array[String] = []
	for fname: String in ResourceLoader.list_directory(TILE_DIR):
		if fname.ends_with(".png"):
			names.append(fname)
	names.sort()
	if names.is_empty():
		push_warning("IsoBoardTheme: %s 没有地块 PNG" % TILE_DIR)
		return _tileset

	for fname: String in names:
		var tex := load(TILE_DIR.path_join(fname)) as Texture2D
		if tex == null:
			continue
		var src := TileSetAtlasSource.new()
		src.texture = tex
		src.texture_region_size = Vector2i(IsoGrid.CANVAS_W, IsoGrid.CANVAS_H)
		src.create_tile(Vector2i(0, 0))
		_source_ids.append(_tileset.add_source(src))

	if _source_ids.is_empty():
		push_warning("IsoBoardTheme: 地块 PNG 均无法加载")
	return _tileset


static func has_tiles() -> bool:
	return _tileset != null and not _source_ids.is_empty()


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
