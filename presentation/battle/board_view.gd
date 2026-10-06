class_name BoardView
extends Control
## 等轴测棋盘视图：地板由 TileMapLayer 铺 16 张地块，单位/高亮/悬停叠加其上。
## 只投影 BattleState / 部署参数，不修改规则状态。
##
## 对外接口与旧 GridContainer 版一致（cell_pressed / render_state / pulse_unit），
## 战斗屏/表现层/输入层无需因换美术而改动；另加 render_deployment 供进场选格屏复用。

signal cell_pressed(cell: Vector2i)

## 内嵌高亮层：在本层绘制菱形（与地块同在 _world 局部空间，位于地块之上、单位之下）。
class _HighlightLayer:
	extends Node2D
	var view: BoardView = null

	func _draw() -> void:
		if view != null:
			view._draw_highlights_on(self)


const REACHABLE_COLOR := Color(0.35, 0.95, 0.55, 0.30)
const INTENT_COLOR := Color(1.0, 0.35, 0.35, 0.40)
const TARGET_COLOR := Color(1.0, 0.85, 0.25, 0.50)
const WALL_COLOR := Color(0.0, 0.0, 0.0, 0.45)
const HOVER_COLOR := Color(1.0, 0.9, 0.2, 0.95)
const MARGIN := 8.0

var _world: Node2D = null
var _tile_layer: TileMapLayer = null
var _highlight_layer: _HighlightLayer = null
var _unit_root: Node2D = null

var _units: Dictionary[int, UnitView] = {}
var _highlights: Dictionary[Vector2i, Color] = {}
var _hover: Vector2i = Vector2i(-1, -1)
var _cols: int = 0
var _rows: int = 0
var _tiles_built: bool = false

## 部署模式允许拾取/悬停的格子（由 render_deployment 传入的外圈）；空 = 非部署视图，
## 任意盘内格都可点（合法性由规则层/调用方判断）。
var _allowed_cells: Array[Vector2i] = []

## 行走加速倍率（>1 = 格子间位移更快）。只缩短位移 tween 时长，
## 完全不改 AnimatedSprite2D 的帧率——所以动画速度不变，只有移动变快。
## static 版用于跨场次保留（run_flow 每场战斗都新建一个 BattleScreen/BoardView）。
static var last_speed_multiplier: float = 1.0
var speed_multiplier: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(560, 380)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_ensure_world()
	speed_multiplier = last_speed_multiplier
	resized.connect(_layout_world)


# ---- 对外接口 ------------------------------------------------------------

## 战斗棋盘：由 BattleState 驱动。
func render_state(state: BattleState, selected_target_unit: int = -1, busy: bool = false) -> void:
	if state == null or state.board == null:
		return
	_ensure_world()
	var board := state.board
	_rebuild_tiles(board.cols, board.rows)

	var highlights: Dictionary[Vector2i, Color] = {}
	# 不可走格：叠暗色（正式墙美术到位前的最小可见回退）。
	for row in range(board.rows):
		for col in range(board.cols):
			var cell := Vector2i(col, row)
			if not board.is_traversable(cell):
				highlights[cell] = WALL_COLOR
	# 可移动格。
	var players := state.alive_player_ids()
	if state.accepts_input() and not players.is_empty():
		var player_id := int(players[0])
		var from_cell := board.get_unit_cell(player_id)
		var budget := state.get_unit(player_id).get_resource(TurnSystem.MOVE_RESOURCE)
		for cell: Vector2i in BoardQuery.reachable_cells(board, from_cell, budget):
			highlights[cell] = REACHABLE_COLOR
	# 敌人意图覆盖格。
	for enemy_id: int in state.enemy_intents:
		var intent: IntentState = state.enemy_intents[enemy_id]
		if intent == null:
			continue
		for cell: Vector2i in intent.affected_cells:
			highlights[cell] = INTENT_COLOR
	# 已选目标单位格。
	if selected_target_unit >= 0:
		var target_cell := board.get_unit_cell(selected_target_unit)
		if target_cell != BoardState.INVALID_CELL:
			highlights[target_cell] = TARGET_COLOR

	_highlights = highlights
	_sync_units(state)
	# 战斗视图：点任意格，可点击合法性交给规则层（清掉部署模式的限定格）。
	_allowed_cells.clear()
	if _highlight_layer != null:
		_highlight_layer.queue_redraw()


## 进场选格盘：只铺地板并高亮可选格，无单位。
func render_deployment(cols: int, rows: int, allowed_cells: Array[Vector2i] = [], busy: bool = false) -> void:
	_ensure_world()
	_rebuild_tiles(cols, rows)
	var highlights: Dictionary[Vector2i, Color] = {}
	for cell: Vector2i in allowed_cells:
		highlights[cell] = REACHABLE_COLOR
	_highlights = highlights
	_allowed_cells = allowed_cells.duplicate()
	_clear_units()
	if _highlight_layer != null:
		_highlight_layer.queue_redraw()


func pulse_unit(unit_id: int) -> Tween:
	var view: UnitView = _units.get(unit_id)
	if view == null:
		return null
	return view.pulse()


## 每格行走时长（秒）。移动按步数乘它，保证走路循环可读、朝向翻转看得见。
## 实际时长 = 此值 / speed_multiplier（加速按钮），动画帧率不受影响。
const WALK_PER_STEP := 0.35

## 设置行走加速倍率（并跨场次保留）。下限 0.1 防止 0/负值把 tween 时长打崩。
func set_speed_multiplier(value: float) -> void:
	speed_multiplier = maxf(0.1, value)
	last_speed_multiplier = speed_multiplier


## 移动表现：沿真实路径逐格走（不拉直线，避免"斜穿格子"的错觉），每步定朝向 + 播行走。
## path 含起点与终点；返回 Tween 供动画队列等待。
func animate_unit_move(unit_id: int, path: Array[Vector2i], per_step: float = WALK_PER_STEP) -> Tween:
	var view: UnitView = _units.get(unit_id)
	if view == null or _tile_layer == null or _tile_layer.tile_set == null or path.size() < 2:
		return null
	view.position = IsoGrid.center_of(_tile_layer, path[0])
	var step_time := maxf(0.05, per_step) / maxf(0.1, speed_multiplier)
	var tween := create_tween()
	for i in range(1, path.size()):
		tween.tween_callback(view.walk_step.bind(path[i] - path[i - 1]))
		tween.tween_property(
			view, "position", IsoGrid.center_of(_tile_layer, path[i]), step_time
		)
	tween.tween_callback(view.play_idle)
	return tween


## 攻击撞击：玩家棋子朝目标方向前冲一小段再回弹（纯表现，不改规则状态）。
## 朝向按棋盘格差（col/row），不用屏幕方向。返回 Tween 供动画队列等待。
func bump_attack(attacker_id: int, target_id: int) -> Tween:
	var view: UnitView = _units.get(attacker_id)
	var target: UnitView = _units.get(target_id)
	if view == null or not view.is_player() or target == null or _tile_layer == null:
		return null
	view.face_dir(
		IsoGrid.cell_at(_tile_layer, target.position) - IsoGrid.cell_at(_tile_layer, view.position)
	)
	var base := view.position
	var to_target := target.position - base
	var lunge := to_target.normalized() * (float(IsoGrid.DIAMOND_W) * 0.30) if to_target.length() > 0.01 else Vector2.ZERO
	var tween := create_tween()
	tween.tween_property(view, "position", base + lunge, 0.05).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(view, "position", base, 0.07).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	return tween


# ---- 输入 ----------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var cell := _cell_at(get_global_mouse_position())
		var next := cell if _clickable(cell) else Vector2i(-1, -1)
		if next != _hover:
			_hover = next
			if _highlight_layer != null:
				_highlight_layer.queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var cell := _cell_at(get_global_mouse_position())
		if _clickable(cell):
			cell_pressed.emit(cell)


func _cell_at(global_pos: Vector2) -> Vector2i:
	if _tile_layer == null or _tile_layer.tile_set == null:
		return Vector2i(-1, -1)
	return IsoGrid.cell_at(_tile_layer, _tile_layer.to_local(global_pos))


func _inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _cols and cell.y < _rows


## 可否拾取/悬停：部署模式下仅限 allowed 外圈；非部署模式（allowed 为空）盘内任意格皆可。
func _clickable(cell: Vector2i) -> bool:
	if not _inside(cell):
		return false
	if _allowed_cells.is_empty():
		return true
	return _allowed_cells.has(cell)


# ---- 内部：世界构建 / 铺盘 / 布局 ----------------------------------------

func _ensure_world() -> void:
	if _world != null:
		return
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	_tile_layer = TileMapLayer.new()
	_tile_layer.name = "Tiles"
	_tile_layer.tile_set = IsoBoardTheme.get_tileset()
	_tile_layer.y_sort_enabled = true
	_world.add_child(_tile_layer)
	_highlight_layer = _HighlightLayer.new()
	_highlight_layer.name = "Highlights"
	_highlight_layer.view = self
	_world.add_child(_highlight_layer)
	_unit_root = Node2D.new()
	_unit_root.name = "Units"
	_world.add_child(_unit_root)


func _rebuild_tiles(cols: int, rows: int) -> void:
	if _tile_layer == null:
		return
	if cols == _cols and rows == _rows and _tiles_built:
		return
	_tile_layer.clear()
	_cols = cols
	_rows = rows
	if _tile_layer.tile_set != null:
		for row in range(rows):
			for col in range(cols):
				var cell := Vector2i(col, row)
				_tile_layer.set_cell(cell, IsoBoardTheme.floor_source_for(cell), Vector2i(0, 0))
	_tiles_built = true
	_layout_world()


func _layout_world() -> void:
	if _world == null or _tile_layer == null or _cols <= 0 or _rows <= 0:
		return
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var bounds := IsoGrid.board_bounds(_tile_layer, _cols, _rows)
	var scale := IsoGrid.fit_scale(bounds.size, size, MARGIN)
	_world.scale = Vector2(scale, scale)
	_world.position = size * 0.5 - bounds.get_center() * scale


# ---- 内部：单位 ----------------------------------------------------------

func _sync_units(state: BattleState) -> void:
	if _unit_root == null:
		return
	var wanted: Dictionary[int, bool] = {}
	for unit_id: int in state.board.get_unit_ids():
		var unit := state.get_unit(unit_id)
		if unit == null:
			continue
		var cell := state.board.get_unit_cell(unit_id)
		if cell == BoardState.INVALID_CELL:
			continue
		wanted[unit_id] = true
		var view: UnitView = _units.get(unit_id)
		if view == null:
			view = UnitView.new()
			_unit_root.add_child(view)
			view.setup(unit_id, unit.is_player())
			_units[unit_id] = view
		view.position = IsoGrid.center_of(_tile_layer, cell)
		view.update(unit)
	for unit_id: int in _units.keys():
		if not wanted.has(unit_id):
			var stale: UnitView = _units[unit_id]
			stale.queue_free()
			_units.erase(unit_id)


func _clear_units() -> void:
	for unit_id: int in _units.keys():
		var view: UnitView = _units[unit_id]
		view.queue_free()
	_units.clear()


# ---- 内部：高亮绘制 ------------------------------------------------------

func _draw_highlights_on(layer: Node2D) -> void:
	if _tile_layer == null:
		return
	var hw := float(IsoGrid.DIAMOND_W) * 0.5
	var hh := float(IsoGrid.DIAMOND_H) * 0.5
	# 无贴图（素材缺失）时画素色地板，保证仍可辨认棋盘。
	if _tile_layer.tile_set == null:
		for row in range(_rows):
			for col in range(_cols):
				var cell := Vector2i(col, row)
				layer.draw_colored_polygon(
					IsoGrid.diamond_points(IsoGrid.center_of(_tile_layer, cell), hw, hh),
					Color(0.24, 0.26, 0.31)
				)
	for cell: Vector2i in _highlights:
		layer.draw_colored_polygon(
			IsoGrid.diamond_points(IsoGrid.center_of(_tile_layer, cell), hw, hh),
			_highlights[cell]
		)
	if _inside(_hover):
		layer.draw_polyline(
			IsoGrid.diamond_points(IsoGrid.center_of(_tile_layer, _hover), hw, hh),
			HOVER_COLOR, 3.0, true
		)
