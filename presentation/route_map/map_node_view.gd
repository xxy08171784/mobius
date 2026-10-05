class_name MapNodeView
extends Control
## 单个地图节点：图标 + 状态表现（locked/available/visited/current）。
## 状态是派生值（见 route_graph.can_enter），本视图只投影，不存进度。

## 点击（状态非 locked 时）发出。
signal activated(node_id: int)

var node_id: int = -1
var node_type: StringName = &""

## locked / available / visited / current。
var state: StringName = &"locked"

var _skin: RouteMapSkin
var _icon: TextureRect = null


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
	if state == &"locked":
		mouse_default_cursor_shape = Control.CURSOR_ARROW
	else:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
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


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if state != &"locked":
			activated.emit(node_id)
			accept_event()
