class_name BattleCardView
extends Control
## 单张动态卡牌显示：卡框 + 技能图标 + 名称 + 费用 + 描述。
## 视觉位置都放在 battle_card_view.tscn，HandView 只负责实例化和排序。

signal card_pressed(card_uid: int)

var card_uid: int = -1
var drag_validator: Callable
var _drag_started := false

@onready var _content: Control = %CardContent
@onready var _frame: TextureRect = %Frame
@onready var _icon: TextureRect = %SkillIcon
@onready var _name_label: Label = %CardName
@onready var _description: Label = %Description
@onready var _cost_label: Label = %CostLabel
@onready var _selection: Panel = %SelectionOverlay
@onready var _hit_button: Button = %HitButton


func _ready() -> void:
	_hit_button.pressed.connect(_on_pressed)
	_hit_button.mouse_entered.connect(_on_mouse_entered)
	_hit_button.mouse_exited.connect(_on_mouse_exited)
	_hit_button.focus_entered.connect(_on_mouse_entered)
	_hit_button.focus_exited.connect(_on_mouse_exited)
	_hit_button.set_drag_forwarding(_make_drag_data, Callable(), Callable())


func setup(
	card: BattleCardState,
	definition: CardDef,
	selected_order: int = -1,
	busy: bool = false,
	state: BattleState = null
) -> void:
	if card == null or definition == null:
		visible = false
		return
	visible = true
	card_uid = card.battle_uid
	_frame.texture = CardVisuals.frame_for(definition)
	_icon.texture = CardVisuals.icon_for(definition)
	_name_label.text = definition.get_display_name(card.upgrade_level)
	_description.text = CardInfo.face_text(definition, card, state)
	_cost_label.text = str(maxi(0, definition.get_cost(card.upgrade_level) + card.cost_modifier))
	_hit_button.tooltip_text = CardInfo.tooltip_for(definition, card.upgrade_level, card, state)
	_hit_button.disabled = busy
	set_selected(selected_order >= 0)


func set_interactable(enabled: bool) -> void:
	_hit_button.disabled = not enabled


func set_selected(selected: bool) -> void:
	_selection.visible = selected
	# 不再上移整张卡。ScrollContainer 会裁剪超出顶部的像素，
	# 这也是之前“选中后卡框上沿消失”的根因。
	_content.position = Vector2.ZERO


func _on_pressed() -> void:
	if not _drag_started:
		card_pressed.emit(card_uid)


func set_affordable(affordable: bool) -> void:
	_content.modulate = Color.WHITE if affordable else Color(0.47, 0.47, 0.50, 0.85)


func _make_drag_data(_position: Vector2) -> Variant:
	if _hit_button.disabled or not drag_validator.is_valid() or not drag_validator.call(card_uid):
		return null
	_drag_started = true
	var preview := _content.duplicate() as Control
	preview.get_node("HitButton").free()
	preview.modulate = Color(1, 1, 1, 0.88)
	preview.scale = Vector2.ONE
	preview.position = -size * 0.5
	_hit_button.set_drag_preview(preview)
	return {"kind": &"battle_card", "card_uid": card_uid}


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_reset_drag.call_deferred()


func _reset_drag() -> void:
	_drag_started = false


func _on_mouse_entered() -> void:
	_content.pivot_offset = size * 0.5
	_content.scale = Vector2(1.045, 1.045)
	z_index = 30


func _on_mouse_exited() -> void:
	_content.scale = Vector2.ONE
	z_index = 0
