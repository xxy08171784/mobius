class_name StatusIconRow
extends HFlowContainer
## 战斗状态图标条：新素材优先，右下角显示层数，多图标自动换行。

const ICON_ATLAS: Texture2D = preload("res://assets/textures/ui/status_icons.png")
const SOURCE_CELL := 48
const DEFAULT_ICON_SIZE := 40.0

@export var icon_size: float = DEFAULT_ICON_SIZE
@export var animate_icons: bool = false

var _signature: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("h_separation", 4)
	add_theme_constant_override("v_separation", 4)


func render(unit: UnitState) -> void:
	var totals: Dictionary = {}
	if unit != null:
		for instance_id: int in unit.status_ids():
			var status := unit.get_status(instance_id)
			if status == null or status.is_expired():
				continue
			var status_id := status.status_id
			totals[status_id] = int(totals.get(status_id, 0)) + maxi(1, status.stacks)
		if unit.get_resource(&"courage") > 0:
			totals[&"resource.courage"] = unit.get_resource(&"courage")

	var ids: Array = totals.keys()
	ids.sort()
	var signature_parts: Array[String] = []
	for status_id: Variant in ids:
		signature_parts.append("%s:%d" % [String(status_id), int(totals[status_id])])
	var next_signature := "|".join(signature_parts)
	if next_signature == _signature:
		return
	_signature = next_signature
	_rebuild(ids, totals)


func _rebuild(ids: Array, totals: Dictionary) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	for index in range(ids.size()):
		var status_id := StringName(String(ids[index]))
		var count := int(totals.get(status_id, 1))
		add_child(_make_icon(status_id, count, index))


func _make_icon(status_id: StringName, count: int, index: int) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(icon_size, icon_size)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.tooltip_text = "%s ×%d\n%s" % [_status_name(status_id), count, _status_description(status_id)]

	var art := TextureRect.new()
	holder.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture = UIArt.texture(status_id)
	if art.texture == null:
		art.texture = _atlas_texture(_icon_cell(status_id))
	art.pivot_offset = Vector2(icon_size, icon_size) * 0.5

	var amount := Label.new()
	amount.position = Vector2(icon_size - 20.0, icon_size - 20.0)
	amount.size = Vector2(20.0, 20.0)
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	amount.text = str(count)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	amount.add_theme_font_size_override("font_size", maxi(11, int(icon_size * 0.34)))
	amount.add_theme_color_override("font_color", Color.WHITE)
	amount.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.04, 0.98))
	amount.add_theme_constant_override("outline_size", 4)
	holder.add_child(amount)

	if animate_icons:
		var tween := art.create_tween().set_loops()
		tween.tween_interval(float(index) * 0.07)
		tween.tween_property(art, "scale", Vector2(1.07, 1.07), 0.55) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(art, "scale", Vector2.ONE, 0.55) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return holder


func _atlas_texture(cell: Vector2i) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = ICON_ATLAS
	texture.region = Rect2(cell.x * SOURCE_CELL, cell.y * SOURCE_CELL, SOURCE_CELL, SOURCE_CELL)
	return texture


func _icon_cell(status_id: StringName) -> Vector2i:
	match status_id:
		StatusRules.BLEED:
			return Vector2i(0, 0)
		StatusRules.POISON:
			return Vector2i(1, 0)
		StatusRules.VULNERABLE:
			return Vector2i(2, 0)
		StatusRules.FOCUS:
			return Vector2i(3, 0)
		StatusRules.STUN:
			return Vector2i(0, 1)
		StatusRules.SLOW:
			return Vector2i(1, 1)
		StatusRules.KNIFE_MARK:
			return Vector2i(2, 1)
		_:
			return Vector2i(3, 1)


func _status_name(status_id: StringName) -> String:
	if status_id == &"resource.courage":
		return "勇气"
	var content := get_node_or_null("/root/ContentDB")
	if content != null:
		var definition: StatusDef = content.get_status(status_id)
		if definition != null:
			return definition.display_name
	match status_id:
		StatusRules.BLEED:
			return "流血"
		StatusRules.POISON:
			return "中毒"
		StatusRules.VULNERABLE:
			return "易伤"
		StatusRules.FOCUS:
			return "专注"
		StatusRules.STUN:
			return "眩晕"
		StatusRules.SLOW:
			return "减速"
		StatusRules.KNIFE_MARK:
			return "飞刀标记"
		_:
			return String(status_id)


func _status_description(status_id: StringName) -> String:
	if status_id == &"resource.courage":
		return CardInfo.COURAGE_DESCRIPTION
	var definition: StatusDef = ContentDB.get_status(status_id)
	return definition.description if definition != null else ""
