class_name BattleCardHud
extends Control
## 手牌/牌堆/结束回合 UI 的数据绑定层。
## 所有位置、大小和层级都放在 battle_card_hud.tscn 中，方便在 2D 编辑器直接拖拽。

@onready var end_turn_button: TextureButton = %EndTurnButton
@onready var _deck_count: Label = %DeckCount
@onready var _discard_count: Label = %DiscardCount
@onready var _energy_count: Label = %CardEnergyCount
@onready var _movement_count: Label = %MovementCount


func _ready() -> void:
	$DeckPile.texture = UIArt.texture(&"deck")
	$DeckPile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	$DiscardPile.texture = UIArt.texture(&"discard")
	$EnergyBadge.texture = UIArt.texture(&"energy")
	$MovementBadge.texture = UIArt.texture(&"movement")
	end_turn_button.texture_normal = UIArt.texture(&"end_turn")
	end_turn_button.mouse_entered.connect(func() -> void: end_turn_button.self_modulate = Color(1.2, 1.2, 1.2))
	end_turn_button.mouse_exited.connect(func() -> void: end_turn_button.self_modulate = Color.WHITE)
	end_turn_button.button_down.connect(func() -> void: end_turn_button.self_modulate = Color(0.7, 0.8, 0.7))
	end_turn_button.button_up.connect(func() -> void: end_turn_button.self_modulate = Color.WHITE)


func render_state(state: BattleState) -> void:
	if state == null:
		return
	var end_key := OS.get_keycode_string(SettingsService.keys["battle_end_turn"])
	$EndTurnButton/EndTurnTitle.text = "结束回合 [%s]" % end_key
	end_turn_button.tooltip_text = $EndTurnButton/EndTurnTitle.text

	_deck_count.text = "抽牌堆 %d" % state.deck.draw.size()
	_discard_count.text = "弃牌堆 %d" % state.deck.discard.size()

	var energy := 0
	var movement := 0
	var locked := false
	var players := state.alive_player_ids()
	if not players.is_empty():
		var player := state.get_unit(int(players[0]))
		if player != null:
			energy = player.get_resource(TurnSystem.ENERGY_RESOURCE)
			movement = player.get_resource(TurnSystem.MOVE_RESOURCE)
			locked = StatusRules.move_locked(player)
	_energy_count.text = "%d/%d" % [energy, state.energy_per_round]
	_movement_count.text = "缠绕" if locked else "%d/%d" % [movement, state.move_points_per_round]
	$MovementBadge.self_modulate = Color(0.5, 0.5, 0.5) if locked or movement <= 0 else Color.WHITE
	$EnergyBadge.self_modulate = Color(0.5, 0.5, 0.5) if energy <= 0 else Color.WHITE
	end_turn_button.modulate = Color.WHITE if state.accepts_input() else Color(0.48, 0.48, 0.48)
