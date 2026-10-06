class_name MapNodeView
extends Control
## 单个地图节点：图标 + 状态表现（locked/available/visited/current）。
## 状态是派生值（见 route_graph.can_enter），本视图只投影，不存进度。

## 点击发出（仅 available 状态会 emit，见 _gui_input）。
signal activated(node_id: int)

## 可进入（available）节点的呼吸式缩放：绕中心枢轴放大缩小的循环动画。
@export_range(1.0, 1.5, 0.01) var pulse_max_scale: float = 1.08
@export_range(0.1, 2.0, 0.05) var pulse_half_period: float = 0.55

var node_id: int = -1
var node_type: StringName = &""

## locked / available / visited / current。
var state: StringName = &"locked"

var _skin: RouteMapSkin
var _icon: TextureRect = null
var _pulse_tween: Tween = null


func _ready() -> void:
	_pivot_center()
	resized.connect(_pivot_center)


## 以中心为缩放枢轴（size 由父节点摆好后才确定；resize 时同步更新）。
func _pivot_center() -> void:
	pivot_offset = size * 0.5


func setup(id: int, type_key: StringName, skin: RouteMapSkin) -> void:
	node_id = id
	node_type = type_key
	_skin = skin


func apply_state(new_state: StringName) -> void:
	state = new_state
	if _icon == null:
		_icon = get_node_or_null("Icon")
	if _icon != null:
		_icon.texture = _skin.icon_for(node_type) if _skin != null else null
		match state:
			&"locked":
				_icon.modulate = _skin.locked_modulate if _skin != null else Color.GRAY
			&"visited":
				_icon.modulate = _skin.visited_modulate if _skin != null else Color(0.7, 0.7, 0.7)
			_:
				_icon.modulate = Color.WHITE
	if state == &"available":
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_start_pulse()
	else:
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		_stop_pulse()
	queue_redraw()


## 高亮环/当前标记：无贴图时用代码画（美术出图后可替换为贴图叠加）。
func _draw() -> void:
	if _skin == null or state == &"locked" or state == &"visited":
		return
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 2.0
	if state == &"current":
		draw_arc(c, r, 0.0, TAU, 64, _skin.current_marker_color, 5.0, true)
	elif state == &"available":
		draw_arc(c, r, 0.0, TAU, 64, _skin.available_glow_color, 4.0, true)


## 开始循环缩放；已在播放则不重启（避免每次刷新跳一下）。
func _start_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		return
	var peak := Vector2(pulse_max_scale, pulse_max_scale)
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(self, "scale", peak, pulse_half_period) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(self, "scale", Vector2.ONE, pulse_half_period) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 停止缩放并复位到原始大小。
func _stop_pulse() -> void:
	if _pulse_tween != null:
		_pulse_tween.kill()
		_pulse_tween = null
	scale = Vector2.ONE


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# 只有当前可进入的节点响应点击；visited/current/locked 一律不响应（StS 式）。
		if state == &"available":
			activated.emit(node_id)
			accept_event()
