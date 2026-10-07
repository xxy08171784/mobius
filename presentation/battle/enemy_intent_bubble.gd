class_name EnemyIntentBubble
extends Control
## 意图以图标 + 数值表达；详细说明放 tooltip，点击可查看对应怪物。
signal pressed

const BUBBLE_SIZE := Vector2(174.0, 60.0)
const BG_COLOR := Color(0.10, 0.085, 0.12, 0.96)
const BORDER_COLOR := Color(0.62, 0.67, 0.63, 1.0)

var _label: Label = null
var _icon: TextureRect
var _secondary: TextureRect
var icon_key: StringName = &""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = BUBBLE_SIZE
	size = BUBBLE_SIZE
	visible = false

	var panel := PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_color = BORDER_COLOR
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 13
	style.corner_radius_top_right = 13
	style.corner_radius_bottom_right = 13
	style.corner_radius_bottom_left = 13
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(46, 46)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_icon)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.text = "…"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 30)
	_label.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.04, 0.95))
	_label.add_theme_constant_override("outline_size", 4)
	row.add_child(_label)
	_secondary = TextureRect.new()
	_secondary.custom_minimum_size = Vector2(30, 40)
	_secondary.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_secondary.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_secondary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_secondary)

	var pointer := Polygon2D.new()
	pointer.polygon = PackedVector2Array([Vector2(-10, 0), Vector2(10, 0), Vector2(0, 11)])
	pointer.position = Vector2(BUBBLE_SIZE.x * 0.5, BUBBLE_SIZE.y - 1.0)
	pointer.color = BG_COLOR
	add_child(pointer)


func set_intent(text_value: String, detail: String = "", icon: StringName = &"", secondary: StringName = &"") -> void:
	if text_value.is_empty():
		visible = false
		return
	visible = true
	if _label != null:
		_label.text = text_value
	icon_key = icon
	_icon.texture = UIArt.texture(icon)
	_icon.visible = _icon.texture != null
	_secondary.texture = UIArt.texture(secondary)
	_secondary.visible = _secondary.texture != null
	tooltip_text = detail


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()
