class_name EnemyIntentBubble
extends Control
## Lost in Fantaland 风格的单位头顶意图气泡：短动作名 + 数值，详细说明放 tooltip。

const BUBBLE_SIZE := Vector2(142.0, 54.0)
const BG_COLOR := Color(0.10, 0.085, 0.12, 0.96)
const BORDER_COLOR := Color(0.94, 0.72, 0.26, 1.0)

var _label: Label = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.text = "攻击 0"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 21)
	_label.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.04, 0.95))
	_label.add_theme_constant_override("outline_size", 4)
	panel.add_child(_label)

	var pointer := Polygon2D.new()
	pointer.polygon = PackedVector2Array([Vector2(-10, 0), Vector2(10, 0), Vector2(0, 11)])
	pointer.position = Vector2(BUBBLE_SIZE.x * 0.5, BUBBLE_SIZE.y - 1.0)
	pointer.color = BG_COLOR
	add_child(pointer)


func set_intent(text_value: String, detail: String = "") -> void:
	if text_value.is_empty():
		visible = false
		return
	visible = true
	if _label != null:
		_label.text = text_value
	tooltip_text = detail

