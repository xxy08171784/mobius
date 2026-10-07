class_name IsoBoardTheme
extends RefCounted
## 运行时从各幕 normalized/*.png 构建并缓存等轴测 TileSet（无手工编辑器步骤）。
## 规格冻结于 docs/battle_board_art_requirements.md；铺法沿用 tile_preview.gd。
## 章节缺图时回退第一幕；第一幕也缺时才返回纯几何 TileSet（BoardView 退化为可拾取纯色地板）。

const TILE_DIRS: Array[String] = [
	"res://assets/textures/tiles/act1/normalized",
	"res://assets/textures/tiles/act2/normalized",
	"res://assets/textures/tiles/act3/normalized",
]

static var _tilesets: Dictionary = {}    # int -> TileSet
static var _source_ids: Dictionary = {}  # int -> Array[int]
static var _floor_tables: Dictionary = {}  # int -> Array[int]（按权重展开的索引表）

## 每幕地板出现权重（下标 = normalized 目录内文件名排序后的位置，0 起）。
## 未列出的下标权重 1（均匀）；调大某下标即提高该地块出现频率。
const FLOOR_WEIGHTS: Array[Dictionary] = [
	{},       # act1：均匀
	{1: 3},   # act2：tile_02 权重 ×3
	{0: 3},   # act3：tile_01 权重 ×3
]


static func chapter_count() -> int:
	return TILE_DIRS.size()


## 地块缺图不能丢失几何；map_to_local/local_to_map 都依赖 TileSet。
static func create_geometry_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_RIGHT
	ts.tile_size = Vector2i(IsoGrid.DIAMOND_W, IsoGrid.DIAMOND_H)
	return ts


## 通过资源目录读取原始逻辑名称；导出包内的 PNG 实际存为导入资源。
static func get_tileset(chapter: int = 0) -> TileSet:
	var index := clampi(chapter, 0, TILE_DIRS.size() - 1)
	if _tilesets.has(index):
		return _tilesets[index]
	var own := _build_for(index)
	if bool(own.get("ok", false)):
		_tilesets[index] = own["tileset"]
		_source_ids[index] = own["source_ids"]
		return _tilesets[index]
	# 本幕缺图：回退第一幕，避免棋盘退成纯色。仅第一幕也缺才用纯几何。
	if index != 0:
		var fallback := get_tileset(0)
		_tilesets[index] = fallback
		_source_ids[index] = _source_ids.get(0, [])
		return fallback
	var geometry := create_geometry_tileset()
	_tilesets[0] = geometry
	_source_ids[0] = []
	return geometry


static func has_tiles(chapter: int = 0) -> bool:
	return not floor_source_ids(chapter).is_empty()


static func floor_source_ids(chapter: int = 0) -> Array[int]:
	var index := clampi(chapter, 0, TILE_DIRS.size() - 1)
	if not _source_ids.has(index):
		get_tileset(index)
	return _source_ids.get(index, []).duplicate()


## 确定性地板变体（同 (def) 恒同格）。该幕权重非均匀时按“展开权重表”抽取。
static func floor_source_for(cell: Vector2i, chapter: int = 0) -> int:
	var ids := floor_source_ids(chapter)
	if ids.is_empty():
		return -1
	if _is_uniform(chapter):
		# 均匀：沿用原公式，第一幕布局逐格不变。
		return ids[absi(cell.x * 7 + cell.y * 3 + cell.x * cell.y) % ids.size()]
	var table := _floor_table(chapter)
	return ids[table[_hash_cell(cell) % table.size()]]


## 该幕各地板权重（与 floor_source_ids 等长；缺省 1）。
static func floor_weights(chapter: int = 0) -> Array[int]:
	var index := clampi(chapter, 0, TILE_DIRS.size() - 1)
	var count := floor_source_ids(index).size()
	var spec: Dictionary = FLOOR_WEIGHTS[index] if index < FLOOR_WEIGHTS.size() else {}
	var out: Array[int] = []
	for i in range(count):
		out.append(maxi(1, int(spec.get(i, 1))))
	return out


static func _is_uniform(chapter: int) -> bool:
	for w: int in floor_weights(chapter):
		if w != 1:
			return false
	return true


static func _floor_table(chapter: int) -> Array[int]:
	if _floor_tables.has(chapter):
		return _floor_tables[chapter]
	var weights := floor_weights(chapter)
	var table: Array[int] = []
	for i in range(weights.size()):
		for _k in range(weights[i]):
			table.append(i)
	if table.is_empty():
		table = [0]
	_floor_tables[chapter] = table
	return table


## 空间混淆：对任意模数分布均匀，避免原公式在小棋盘取模后退化（如 mod 7 会整行同格）。
static func _hash_cell(cell: Vector2i) -> int:
	var h: int = cell.x * 92837111 ^ cell.y * 689287499
	h = (h ^ (h >> 15)) * 2246822519
	return absi(h ^ (h >> 13))


## 墙/陷阱正式美术未入库：返回 -1，BoardView 退回地板并叠色块标记（接缝）。
static func wall_source_for(_cell: Vector2i) -> int:
	return -1


static func trap_source_for(_cell: Vector2i) -> int:
	return -1


static func _build_for(index: int) -> Dictionary:
	var dir_path := TILE_DIRS[index]
	var ts := create_geometry_tileset()
	var ids: Array[int] = []
	if not DirAccess.dir_exists_absolute(dir_path):
		return {"ok": false}
	var names: Array[String] = []
	for fname: String in ResourceLoader.list_directory(dir_path):
		if fname.ends_with(".png"):
			names.append(fname)
	names.sort()
	for fname: String in names:
		var tex := load(dir_path.path_join(fname)) as Texture2D
		if tex == null:
			continue
		var src := TileSetAtlasSource.new()
		src.texture = tex
		src.texture_region_size = Vector2i(IsoGrid.CANVAS_W, IsoGrid.CANVAS_H)
		src.create_tile(Vector2i(0, 0))
		ids.append(ts.add_source(src))
	if ids.is_empty():
		push_warning("IsoBoardTheme: %s 没有可加载的地块 PNG" % dir_path)
		return {"ok": false}
	return {"ok": true, "tileset": ts, "source_ids": ids}
