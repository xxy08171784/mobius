class_name BattleCardView
extends Control
## 单张动态卡牌显示：卡框 + 技能图标 + 名称 + 费用 + 描述。
## 视觉位置都放在 battle_card_view.tscn，HandView 只负责实例化和排序。

signal card_pressed(card_uid: int)

var card_uid: int = -1

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


func setup(
	card: BattleCardState,
	definition: CardDef,
	selected_order: int = -1,
	busy: bool = false
) -> void:
	if card == null or definition == null:
		visible = false
		return
	visible = true
	card_uid = card.battle_uid
	_frame.texture = CardVisuals.frame_for(definition)
	_icon.texture = CardVisuals.icon_for(definition)
	_name_label.text = definition.display_name
	_description.text = definition.description
	_cost_label.text = str(maxi(0, definition.get_cost(card.upgrade_level) + card.cost_modifier))
	_hit_button.tooltip_text = CardInfo.tooltip_for(definition, card.upgrade_level)
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
	card_pressed.emit(card_uid)


func _on_mouse_entered() -> void:
	_content.pivot_offset = size * 0.5
	_content.scale = Vector2(1.045, 1.045)
	z_index = 30


func _on_mouse_exited() -> void:
	_content.scale = Vector2.ONE
	z_index = 0
