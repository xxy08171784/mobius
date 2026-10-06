class_name BattleCardHud
extends Control
## 手牌/牌堆/结束回合 UI 的数据绑定层。
## 所有位置、大小和层级都放在 battle_card_hud.tscn 中，方便在 2D 编辑器直接拖拽。

@onready var end_turn_button: TextureButton = %EndTurnButton
@onready var _deck_count: Label = %DeckCount
@onready var _discard_count: Label = %DiscardCount
@onready var _energy_count: Label = %CardEnergyCount


func render_state(state: BattleState) -> void:
	if state == null:
		return

	_deck_count.text = str(state.deck.draw.size())
	_discard_count.text = str(state.deck.discard.size())

	var energy := 0
	var players := state.alive_player_ids()
	if not players.is_empty():
		var player := state.get_unit(int(players[0]))
		if player != null:
			energy = player.get_resource(TurnSystem.ENERGY_RESOURCE)
	_energy_count.text = str(energy)
