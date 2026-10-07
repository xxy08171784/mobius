extends Node
## 所有游戏脚本、场景、贴图均来自 --main-pack 指定的正式发布包。
var _failures: Array[String] = []
var _capture := false
var _output := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_capture = args.has("--capture")
	_output = args[1]
	get_tree().create_timer(45.0).timeout.connect(func() -> void: get_tree().quit(1))
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		printerr("[FAIL] " + message)


func _run() -> void:
	var tiles := IsoBoardTheme.get_tileset()
	_check(tiles != null and tiles.get_source_count() == 16, "export loads all 16 floor textures")
	_check_frames(UnitSpriteFrames.get_frames(), "player")
	for key: StringName in [&"energy", &"movement", &"discard", &"end_turn", &"intent_attack", &"intent_status"]:
		_check(UIArt.texture(key) != null, "export loads HUD " + String(key))
	ContentDB.ensure_loaded()
	for enemy_id: StringName in ContentDB.enemy_ids():
		var id := String(enemy_id)
		if not (id.begins_with("enemy.tomb.") or id.begins_with("enemy.catacomb.") or id.begins_with("enemy.crypt.")):
			continue
		var enemy := ContentDB.get_enemy(enemy_id)
		var unit := ContentDB.get_unit(enemy.unit_def_id)
		_check_frames(UnitSpriteFrames.get_frames_for(unit.appearance_key), id)
	# 旧包须在这里明确失败，避免缺几何后产生大量 map_to_local 错误。
	if not _failures.is_empty():
		_finish()
		return
	SaveService.run_path = "user://tests/export/current.json"
	SaveService.profile_path = "user://tests/export/profile.json"
	SaveService.clear_run()
	App.current_profile = ProfileState.new()
	App.current_profile.tutorial_seen = true
	SettingsService.reduced_motion = true
	var main: Control = load("res://app/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	var flow := main.get_child(0) as RunFlow
	_check(flow.start_run(&"character.hero", "731927"), "export starts run")
	for child: Node in flow.get_children():
		if child is ChapterIntro:
			child.dismiss()
	await _snapshot("01-route")
	flow._on_route_node_activated(App.current_session.available_node_ids()[0])
	await _snapshot("02-deployment")
	var battle: BattleScreen = null
	for child: Node in flow.get_children():
		if child is BattleScreen:
			battle = child
	_check(battle != null and battle._deployment_mode, "route opens deployment")
	if battle == null:
		_finish()
		return
	var board := battle._board_view
	var centers := {}
	for y in range(8):
		for x in range(8):
			var cell := Vector2i(x, y)
			var local := IsoGrid.center_of(board._tile_layer, cell)
			centers[local] = true
			_check(board._cell_at(board._tile_layer.to_global(local)) == cell, "export tile picking %s" % cell)
	_check(centers.size() == 64, "64 separate board cells")
	_check(board._tile_layer.get_used_cells().size() == 64, "64 textured board cells")
	var chosen: Vector2i = board._allowed_cells[0]
	var position := board._tile_layer.to_global(IsoGrid.center_of(board._tile_layer, chosen))
	var picked := board._cell_at(position)
	_check(board._clickable(picked), "green deployment tile is clickable")
	board.cell_pressed.emit(picked)
	await _snapshot("03-battle")
	_check(not battle._deployment_mode and battle._session != null, "picked tile enters battle")
	for unit_id: int in battle._session.state.board.get_unit_ids():
		_check(board.unit_view(unit_id)._sprite != null, "battle unit has animated sprite")
	_check(not battle.get_node("PreviewLabel").visible, "export hides permanent preview")
	var card_hud := battle._battle_card_hud
	var badge_names := ["EnergyBadge", "MovementBadge", "DeckPile", "DiscardPile", "EndTurnButton"]
	for i in badge_names.size():
		var badge: Control = card_hud.get_node(badge_names[i])
		_check(Rect2(Vector2.ZERO, card_hud.size).encloses(badge.get_rect()), "export HUD stays on screen: " + badge_names[i])
		for j in range(i + 1, badge_names.size()):
			var other: Control = card_hud.get_node(badge_names[j])
			_check(not badge.get_rect().intersects(other.get_rect()), "export HUD icons don't overlap: " + badge_names[i] + "/" + badge_names[j])
	for label_path in ["EnergyBadge/CardEnergyCount", "EnergyBadge/EnergyTitle", "MovementBadge/MovementCount", "MovementBadge/MovementTitle", "DeckPile/DeckCount", "DiscardPile/DiscardCount", "EndTurnButton/EndTurnTitle"]:
		var label: Control = card_hud.get_node(label_path)
		_check(card_hud.get_global_rect().encloses(label.get_global_rect()), "export HUD label stays on screen: " + label_path)
	var defend_uid := -1
	for uid: int in battle._session.state.deck.hand:
		if battle._session.state.deck.get_card(uid).card_id == &"card.starter.defend":
			defend_uid = uid
			break
	_check(defend_uid >= 0, "seeded export hand includes defense for drop test")
	if defend_uid >= 0:
		var player := battle._session.state.get_unit(battle._session.state.alive_player_ids()[0])
		var old_block := player.block
		var old_energy := CardSelectionBudget.energy(battle._session.state)
		var drop_point := board.get_global_transform().affine_inverse() * position
		var data := {"kind": &"battle_card", "card_uid": defend_uid}
		_check(board._can_drop_data(drop_point, data), "export board accepts valid defense drop")
		board._drop_data(drop_point, data)
		while battle._battle_input._busy:
			await get_tree().process_frame
		player = battle._session.state.get_unit(player.unit_id)
		_check(player.block > old_block, "export card drop grants shield")
		_check(CardSelectionBudget.energy(battle._session.state) == old_energy - 1, "export drop pays energy once")
		_check(not battle._session.state.deck.hand.has(defend_uid), "export drop consumes card once")
		await _snapshot("03b-card-dropped")
	var round_before := battle._session.state.round_index
	battle._battle_input.end_turn()
	while battle._battle_input._busy:
		await get_tree().process_frame
	_check(battle._session.state.round_index == round_before + 1, "enemy turn returns to player")
	await _snapshot("04-next-turn")
	flow.show_main_menu()
	flow._on_continue_run()
	await _snapshot("05-continue")
	var restored: BattleScreen = null
	for child: Node in flow.get_children():
		if child is BattleScreen:
			restored = child
	_check(restored != null and restored._session.state.round_index == round_before + 1,
		"continue restores the same battle round")
	SaveService.clear_run()
	main.queue_free()
	await get_tree().process_frame
	_finish()


func _check_frames(frames: SpriteFrames, label: String) -> void:
	_check(frames != null, label + " has sprites in export")
	if frames == null:
		return
	for animation: StringName in [UnitSpriteFrames.ANIM_LEFT, UnitSpriteFrames.ANIM_RIGHT]:
		_check(frames.has_animation(animation) and frames.get_frame_count(animation) > 0,
			label + " has " + String(animation))


func _snapshot(label: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if _capture:
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(_output)
		var result := get_tree().root.get_texture().get_image().save_png(_output.path_join(label + ".png"))
		_check(result == OK, "save export screenshot " + label)


func _finish() -> void:
	print("Export smoke: %d failures" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
