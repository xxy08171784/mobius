class_name BoardView
extends Control
## 等轴测棋盘视图：地板由 TileMapLayer 铺 16 张地块，单位/高亮/悬停叠加其上。
## 只投影 BattleState / 部署参数，不修改规则状态。
##
## 对外接口与旧 GridContainer 版一致（cell_pressed / render_state / pulse_unit），
## 战斗屏/表现层/输入层无需因换美术而改动；另加 render_deployment 供进场选格屏复用。

signal cell_pressed(cell: Vector2i)
signal card_dropped(uid: int, cell: Vector2i)
signal drop_rejected(message: String)
var drop_validator: Callable
var _drop_cell := Vector2i(-1, -1)
var _drop_error := ""

## 内嵌高亮层：在本层绘制菱形（与地块同在 _world 局部空间，位于地块之上、单位之下）。
class _HighlightLayer:
	extends Node2D
	var view: BoardView = null

	func _draw() -> void:
		if view != null:
			view._draw_highlights_on(self)


const REACHABLE_COLOR := Color(0.35, 0.95, 0.55, 0.30)
const TARGET_COLOR := Color(1.0, 0.85, 0.25, 0.50)
const WALL_COLOR := Color(0.0, 0.0, 0.0, 0.45)
const HOVER_COLOR := Color(1.0, 0.9, 0.2, 0.95)
const THREAT_COLOR := Color(0.75, 0.25, 0.85, 0.45)   # 紫：怪物能打到的格子
const ENEMY_DEPLOY_COLOR := Color(1.0, 0.3, 0.3, 0.55)  # 红：进场选格屏上的敌人位置
const MARGIN := 8.0

var _world: Node2D = null
var _tile_layer: TileMapLayer = null
var _highlight_layer: _HighlightLayer = null
var _unit_root: Node2D = null

var _units: Dictionary[int, UnitView] = {}
var _unit_cells: Dictionary[int, Vector2i] = {}
var _highlights: Dictionary[Vector2i, Color] = {}
var _threat_cells: Array[Vector2i] = []
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
	focus_mode = Control.FOCUS_ALL
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
		var player := state.get_unit(player_id)
		var budget := 0 if StatusRules.move_locked(player) else player.get_resource(TurnSystem.MOVE_RESOURCE)
		for cell: Vector2i in BoardQuery.reachable_cells(board, from_cell, budget):
			highlights[cell] = REACHABLE_COLOR
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


## 进场选格盘：只铺地板并高亮可选格（绿）与敌人所在格（红），无单位。
func render_deployment(cols: int, rows: int, allowed_cells: Array[Vector2i] = [], enemy_cells: Array[Vector2i] = [], busy: bool = false) -> void:
	_ensure_world()
	_rebuild_tiles(cols, rows)
	var highlights: Dictionary[Vector2i, Color] = {}
	for cell: Vector2i in allowed_cells:
		highlights[cell] = REACHABLE_COLOR
	for cell: Vector2i in enemy_cells:
		highlights[cell] = ENEMY_DEPLOY_COLOR
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


## 威胁格显示：某怪物"能打到的格子"（表现层查询，只画不改规则状态）。空数组 = 清除。
func set_threat_cells(cells: Array[Vector2i]) -> void:
	_threat_cells = cells.duplicate()
	if _highlight_layer != null:
		_highlight_layer.queue_redraw()


## 取单位视图（死亡动画等表现层用；无则 null）。
func unit_view(unit_id: int) -> UnitView:
	return _units.get(unit_id)


## 死亡动画：缓缓上升 + 虚化。返回 Tween 供动画队列等待；视图随后由 _sync_units 释放（按棋盘占用）。
func animate_death(unit_id: int) -> Tween:
	var view: UnitView = _units.get(unit_id)
	if view == null:
		return null
	var tween := create_tween()
	tween.tween_property(view, "position:y", view.position.y - 70.0, 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(view, "modulate:a", 0.0, 0.7)
	return tween


## 受击反馈：目标闪红并朝远离攻击方的方向轻弹（玩家/怪物共用）。返回 Tween 供队列等待。
func play_hit(target_id: int, attacker_id: int) -> Tween:
	var target: UnitView = _units.get(target_id)
	if target == null:
		return null
	var away := Vector2.ZERO
	var attacker: UnitView = _units.get(attacker_id)
	if attacker != null and attacker != target:
		away = target.position - attacker.position
	return target.play_hit(away)


## 每格行走时长（秒）。移动按步数乘它，保证走路循环可读、朝向翻转看得见。
## 实际时长 = 此值 / speed_multiplier（加速按钮），动画帧率不受影响。
const WALK_PER_STEP := 0.35

## 每走一格上跳的高度（棋盘局部像素）。棋子式"一跳一跳"：正弦半波起跳再落地。调观感改这一个。
const HOP_HEIGHT := 40.0

## 设置行走加速倍率（并跨场次保留）。下限 0.1 防止 0/负值把 tween 时长打崩。
func set_speed_multiplier(value: float) -> void:
	speed_multiplier = maxf(0.1, value)
	last_speed_multiplier = speed_multiplier


## 移动表现：沿真实路径逐格走（不拉直线，避免"斜穿格子"的错觉），每步定朝向 + 播行走。
## 每格叠一次上跳弧（_hop_arc），落地即格中心 —— 棋子式一跳一跳。path 含起点与终点；
## 返回 Tween 供动画队列等待。
func animate_unit_move(unit_id: int, path: Array[Vector2i], per_step: float = WALK_PER_STEP, step_sound: Callable = Callable()) -> Tween:
	var view: UnitView = _units.get(unit_id)
	if view == null or _tile_layer == null or _tile_layer.tile_set == null or path.size() < 2:
		return null
	view.position = IsoGrid.center_of(_tile_layer, path[0])
	var step_time := maxf(0.05, per_step) / maxf(0.1, speed_multiplier)
	var tween := create_tween()
	for i in range(1, path.size()):
		tween.tween_callback(view.walk_step.bind(path[i] - path[i - 1]))
		tween.tween_method(
			_hop_arc.bind(view, IsoGrid.center_of(_tile_layer, path[i - 1]), IsoGrid.center_of(_tile_layer, path[i])),
			0.0, 1.0, step_time
		)
		if step_sound.is_valid():
			tween.tween_callback(step_sound.bind(path[i]))
	tween.tween_callback(view.play_idle)
	return tween


## 单步一跳的弧线（纯表现，不改规则状态）。t∈[0,1]：平面位置从 from 线性到 to，
## 叠一个 sin 半波上跳（-y 向上）。用 tween_method 一体驱动平面位移与高度，
## 避免平面/高度两个 tween 抢同一 position 属性。
func _hop_arc(t: float, view: UnitView, from: Vector2, to: Vector2) -> void:
	if view == null or not is_instance_valid(view):
		return
	var pos := from.lerp(to, t)
	pos.y -= sin(PI * t) * HOP_HEIGHT
	view.position = pos


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
	var delta := Vector2i.ZERO
	if event.is_action_pressed("ui_left"):
		delta.x = -1
	elif event.is_action_pressed("ui_right"):
		delta.x = 1
	elif event.is_action_pressed("ui_up"):
		delta.y = -1
	elif event.is_action_pressed("ui_down"):
		delta.y = 1
	if delta != Vector2i.ZERO and _cols > 0 and _rows > 0:
		_hover = Vector2i(clampi(_hover.x + delta.x, 0, _cols - 1), clampi(_hover.y + delta.y, 0, _rows - 1))
		_highlight_layer.queue_redraw()
		accept_event()
		return
	if event.is_action_pressed("ui_accept") and _hover.x >= 0:
		if _allowed_cells.is_empty() or _allowed_cells.has(_hover):
			cell_pressed.emit(_hover)
		accept_event()
		return
	if event is InputEventMouseMotion:
		var cell := _cell_at(get_global_mouse_position())
		var next := cell if _clickable(cell) else Vector2i(-1, -1)
		if next != _hover:
			_hover = next
			if _highlight_layer != null:
				_highlight_layer.queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		var cell := _cell_at(get_global_mouse_position())
		if _clickable(cell):
			cell_pressed.emit(cell)


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or data.get("kind") != &"battle_card" or not drop_validator.is_valid():
		return false
	_drop_cell = _cell_at(get_global_transform() * at_position)
	_drop_error = drop_validator.call(int(data.get("card_uid", -1)), _drop_cell)
	_highlight_layer.queue_redraw()
	return _drop_error.is_empty()


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var cell := _cell_at(get_global_transform() * at_position)
	card_dropped.emit(int(data.get("card_uid", -1)), cell)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		if not get_viewport().gui_is_drag_successful() and not _drop_error.is_empty() and get_global_rect().has_point(get_global_mouse_position()):
			drop_rejected.emit(_drop_error)
		_drop_cell = Vector2i(-1, -1)
		_drop_error = ""
		if _highlight_layer != null:
			_highlight_layer.queue_redraw()


func _cell_at(global_pos: Vector2) -> Vector2i:
	var front_to_back: Array = _units.values()
	front_to_back.sort_custom(func(a: UnitView, b: UnitView) -> bool: return a.position.y > b.position.y)
	for view: UnitView in front_to_back:
		if view.contains_pointer(global_pos):
			return _unit_cells.get(view.unit_id(), BoardState.INVALID_CELL)
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
	_unit_root.y_sort_enabled = true
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
				var source := IsoBoardTheme.floor_source_for(cell)
				if source >= 0:
					_tile_layer.set_cell(cell, source, Vector2i(0, 0))
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
		_unit_cells[unit_id] = cell
		var view: UnitView = _units.get(unit_id)
		if view == null:
			view = UnitView.new()
			_unit_root.add_child(view)
			view.inspection_requested.connect(func(id: int) -> void:
				if _unit_cells.has(id):
					cell_pressed.emit(_unit_cells[id])
			)
			var enemy: EnemyDef = ContentDB.get_enemy(unit.enemy_id) if not unit.is_player() else null
			view.setup(unit_id, unit.is_player(), _appearance_key_for(unit), enemy.visual_scale if enemy != null else 1.0)
			_units[unit_id] = view
		view.position = IsoGrid.center_of(_tile_layer, cell)
		view.update(unit)
	for unit_id: int in _units.keys():
		if not wanted.has(unit_id):
			var stale: UnitView = _units[unit_id]
			stale.queue_free()
			_units.erase(unit_id)
			_unit_cells.erase(unit_id)


func _clear_units() -> void:
	for unit_id: int in _units.keys():
		var view: UnitView = _units[unit_id]
		view.queue_free()
	_units.clear()
	_unit_cells.clear()


## 外观键：敌人经 ContentDB 从单位定义解析（表现层只读 Def）。玩家走 UnitSpriteFrames
## 内置目录，无需键。内容未加载/无定义时返回空 -> UnitView 退回色块。
func _appearance_key_for(unit: UnitState) -> StringName:
	if unit == null or unit.is_player() or not ContentDB.is_loaded():
		return &""
	var definition: UnitDef = ContentDB.get_unit(unit.def_id)
	return &"" if definition == null else definition.appearance_key


# ---- 内部：高亮绘制 ------------------------------------------------------

func _draw_highlights_on(layer: Node2D) -> void:
	if _tile_layer == null:
		return
	var hw := float(IsoGrid.DIAMOND_W) * 0.5
	var hh := float(IsoGrid.DIAMOND_H) * 0.5
	# 无贴图（素材缺失）时画素色地板，保证仍可辨认棋盘。
	if _tile_layer.tile_set != null and _tile_layer.tile_set.get_source_count() == 0:
		for row in range(_rows):
			for col in range(_cols):
				var cell := Vector2i(col, row)
				layer.draw_colored_polygon(
					IsoGrid.diamond_points(IsoGrid.center_of(_tile_layer, cell), hw, hh),
					Color(0.24, 0.26, 0.31)
				)
				layer.draw_polyline(
					IsoGrid.diamond_points(IsoGrid.center_of(_tile_layer, cell), hw, hh),
					Color(0.48, 0.50, 0.55), 2.0, true
				)
	for cell: Vector2i in _highlights:
		layer.draw_colored_polygon(
			IsoGrid.diamond_points(IsoGrid.center_of(_tile_layer, cell), hw, hh),
			_highlights[cell]
		)
	# 威胁格（点选怪物时显示它能打到的格子）叠在常规高亮之上。
	for cell: Vector2i in _threat_cells:
		layer.draw_colored_polygon(
			IsoGrid.diamond_points(IsoGrid.center_of(_tile_layer, cell), hw, hh),
			THREAT_COLOR
		)
	if _inside(_hover):
		layer.draw_polyline(
			IsoGrid.diamond_points(IsoGrid.center_of(_tile_layer, _hover), hw, hh),
			HOVER_COLOR, 3.0, true
		)
	if get_viewport().gui_is_dragging() and _inside(_drop_cell):
		layer.draw_polyline(
			IsoGrid.diamond_points(IsoGrid.center_of(_tile_layer, _drop_cell), hw, hh),
			Color(0.6, 1.0, 0.7) if _drop_error.is_empty() else Color(1, 0.35, 0.3), 9.0, true
		)
