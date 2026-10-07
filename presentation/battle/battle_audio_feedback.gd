class_name BattleAudioFeedback
extends RefCounted
## 只消费已接受命令的状态差异和事件；预演、读档绑定、界面刷新不播放战斗音。
var default_surface: StringName = &"grass"
var _pending_draw := false
var _pending_upgrade := false
var _draw_heard := false


func begin_result(command: GameCommand, before: BattleState, after: BattleState) -> void:
	_pending_draw = false
	_pending_upgrade = false
	_draw_heard = false
	if command is PlayCardsCommand:
		AudioService.play_cue(&"card_use")
	if before == null or after == null:
		return
	if command is EndTurnCommand and after.round_index > before.round_index:
		_pending_draw = not after.deck.hand.is_empty()
	for uid: int in after.deck.hand:
		if not before.deck.hand.has(uid):
			_pending_draw = true
		var previous := before.deck.get_card(uid)
		var current := after.deck.get_card(uid)
		if previous != null and current != null and current.upgrade_level > previous.upgrade_level:
			_pending_upgrade = true


func finish_result() -> void:
	if _pending_draw and not _draw_heard:
		AudioService.play_cue(&"card_draw")
	if _pending_upgrade:
		AudioService.play_cue(&"card_upgrade")
	_pending_draw = false
	_pending_upgrade = false


func play_event(event: GameEvent, state: BattleState, animated: bool) -> void:
	var payload: Dictionary = event.payload if event is EffectEvent else {}
	match event.type_key:
		&"damage":
			var target := state.get_unit(event.target_id)
			if target != null and target.is_player() and int(payload.get("hp_damage", 0)) > 0:
				AudioService.play_cue(&"player_hurt")
			var source := state.get_unit(event.source_id)
			if source != null and source.is_player() and event.target_id != event.source_id \
					and int(payload.get("amount", 0)) > 0 and String(payload.get("status_id", "")).is_empty():
				var card := state.deck.get_card(int(payload.get("card_uid", -1)))
				AudioService.play_cue(AudioService.catalog.attack_cue(card.card_id if card != null else &""))
		&"block_gained":
			if int(payload.get("amount", 0)) > 0:
				AudioService.play_cue(&"shield")
		&"cards_drawn":
			if not Array(payload.get("cards", [])).is_empty():
				AudioService.play_cue(&"card_draw")
				_draw_heard = true
		&"unit_moved":
			var mover := state.get_unit(event.target_id)
			if not animated and mover != null and mover.is_player() and event.before.get("cell") != event.after.get("cell"):
				play_step(state, event.after.get("cell", BoardState.INVALID_CELL))


func play_step(state: BattleState, cell: Vector2i) -> void:
	var terrain := state.board.get_cell(cell)
	var surface := default_surface if terrain == null or terrain.terrain_key.is_empty() else terrain.terrain_key
	match surface:
		&"water", &"terrain.water", &"shallow_water":
			AudioService.play_cue(&"step_water")
		&"grass", &"terrain.grass":
			AudioService.play_cue(&"step_grass")
		_:
			AudioService.play_cue(&"step_stone")
