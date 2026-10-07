extends Node
## 实际场景和信号集成。--headless 可跑；-- --capture 在有渲染器时输出截图。
var _failures: Array[String] = []
var _capture: bool = false


var root: Window


func _ready() -> void:
	root = get_tree().root
	get_tree().create_timer(40.0).timeout.connect(func() -> void: get_tree().quit(1))
	_capture = OS.get_cmdline_user_args().has("--capture")
	_run.call_deferred()


func _check(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)
		printerr("[ASSERT] " + message)


func _run() -> void:
	var saves := root.get_node("SaveService")
	saves.run_path = "user://tests/ui/current.json"
	saves.profile_path = "user://tests/ui/profile.json"
	saves.clear_run()
	var app := root.get_node("App")
	app.current_profile = ProfileState.new()
	app.current_profile.tutorial_seen = true
	var main := load("res://app/main.tscn").instantiate() as Control
	root.add_child(main)
	await get_tree().process_frame
	var flow := main.get_child(0) as RunFlow
	_check(flow != null, "root builds RunFlow")
	await _snapshot("01-menu")
	flow._open_settings()
	await _snapshot("02-settings")
	var settings := _find(flow, SettingsScreen) as SettingsScreen
	_check(settings != null, "settings scene opens")
	settings.closed.emit()
	flow._show_character_select()
	await _snapshot("03-character")
	_check(flow.start_run(&"character.hero", "ui-smoke"), "new run")
	_check(saves.has_run(), "new run immediately saved")
	_check(not app.end_run(), "active run cannot be settled as a defeat")
	var intro := _find(flow, ChapterIntro) as ChapterIntro
	_check(intro != null, "first chapter intro opens")
	if intro != null:
		intro.dismiss()
	await _snapshot("04-route")
	var session: RunSession = app.current_session
	var node_id := session.available_node_ids()[0]
	flow._on_route_node_activated(node_id)
	await _snapshot("05-deployment")
	var battle := _find(flow, BattleScreen) as BattleScreen
	_check(battle != null and battle._deployment_mode, "deployment in battle scene")
	_check(battle._board_view._tile_layer.tile_set.get_source_count() == 16, "deployment loads all floor textures")
	_check(battle._board_view._tile_layer.get_used_cells().size() == 64, "deployment has 64 distinct tiles")
	battle.deployment_cell_chosen.emit(Vector2i.ZERO)
	await _snapshot("06-battle")
	_check(not battle.demo_autostart, "formal battle disables demo")
	_check(not battle.get_node("BattleHud/EnemyHUD").visible, "enemy HUD hidden until selected")
	var enemy_id: int = battle._session.state.alive_enemy_ids()[0]
	battle._on_cell_pressed(battle._session.state.board.get_unit_cell(enemy_id))
	_check(battle.get_node("BattleHud/EnemyHUD").visible, "click enemy shows details")
	_check(not battle._board_view.unit_view(enemy_id)._label.visible, "overhead HP hidden")
	_check(not battle.get_node("BattleHud").get_node("%EnemyName").text.begins_with("unit."), "enemy display name from content")
	await _snapshot("06b-selected-enemy")
	# A far empty tile collapses selection, while its invalid move consumes no resources.
	battle._on_cell_pressed(Vector2i(7, 7))
	_check(not battle.get_node("BattleHud/EnemyHUD").visible, "empty tile hides details")
	# Return and continue a live battle through the same menu path as the player.
	var round_before := battle._session.state.round_index
	flow.show_main_menu()
	flow._on_continue_run()
	battle = _find(flow, BattleScreen) as BattleScreen
	_check(battle != null, "continue restores battle scene")
	_check(battle._session.state.round_index == round_before, "continue does not repeat round start")
	# Exercise the actual BattleScreen defeat signal, including RunFlow/App archive.
	battle._session.state.get_unit(1).hp = 0
	battle._session.state.phase = BattleState.Phase.DEFEAT
	battle._on_battle_input_finished(battle._session.battle_result())
	await _snapshot("07-defeat")
	_check(not saves.has_run(), "defeat archive removes continue")
	_check(app.current_session == null, "defeat calls App.end_run")
	flow.show_main_menu()
	flow._show_library()
	await _snapshot("08-library")
	flow._show_history()
	await _snapshot("09-history")
	flow.start_run(&"character.hero", "ui-reward")
	session = app.current_session
	flow._on_route_node_activated(session.available_node_ids()[0])
	battle = _find(flow, BattleScreen) as BattleScreen
	battle.deployment_cell_chosen.emit(Vector2i.ZERO)
	for id: int in battle._session.state.enemy_ids():
		battle._session.state.get_unit(id).hp = 0
	battle._session.state.phase = BattleState.Phase.VICTORY
	battle._on_battle_input_finished(battle._session.battle_result())
	await _snapshot("10-reward")
	_check(session.state.flow_phase == &"reward", "victory displays persisted reward")
	var reward_screen := _find(flow, NodeChoiceScreen) as NodeChoiceScreen
	_check(reward_screen._options_box.get_child(0).get_child_count() == 3, "three real card reward views")
	flow._on_reward_chose({"action": "reward_choice", "index": 0})
	_check(session.state.flow_phase == &"route", "claim returns map")
	await _art_scenarios(flow)
	await _live_card_scenario(flow)
	saves.clear_run()
	main.queue_free()
	await get_tree().process_frame
	print("UI smoke: %d failures" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


func _art_scenarios(flow: RunFlow) -> void:
	var db := root.get_node("ContentDB")
	for act in 3:
		flow._clear_screen()
		var run := RunSession.create_run(&"character.hero", "visual-act-%d" % act, db)
		var encounter := db.get_encounter(StringName("encounter.boss.act%d" % (act + 1))).duplicate(true) as EncounterDef
		if act == 1:
			encounter.enemy_ids.append(&"enemy.catacomb.spider")
			encounter.enemy_ids.append(&"enemy.catacomb.corpse_beetle")
		var rng := RngStreams.new()
		rng.derive_streams(run.seed)
		var data := EncounterBuilder.build(encounter, run, rng, db)
		var state: BattleState = data.state
		var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(3, 3), Vector2i(5, 2), Vector2i(2, 5)]
		var ids: Array[int] = state.board.get_unit_ids()
		for id: int in ids:
			state.board.remove_unit(id)
		for i in ids.size():
			state.board.place_unit(ids[i], cells[i])
		var screen: BattleScreen = load("res://presentation/battle/battle_screen.tscn").instantiate()
		screen.demo_autostart = false
		screen.chapter_index = act
		flow.add_child(screen)
		screen.configure(data)
		var player := screen._session.state.get_unit(1)
		player.set_resource(&"courage", 5)
		var status_ids := [StatusRules.POISON, StatusRules.IGNITE, StatusRules.SLOW, StatusRules.ENTANGLE, StatusRules.CORRODE, StatusRules.WEAK]
		for i in status_ids.size():
			var status := StatusState.new()
			status.instance_id = 500 + i
			status.status_id = status_ids[i]
			status.stacks = 2
			status.duration = 3
			player.set_status(status.instance_id, status)
		screen._on_cell_pressed(cells[1])
		await _snapshot("11-act%d-boss" % (act + 1))
		_check(screen._board_view.unit_view(ids[1])._sprite.scale.x > UnitView.SPRITE_SCALE, "boss visually enlarged")
		var view := screen._board_view.unit_view(ids[1])
		var body_point := view.to_global(Vector2(0, -110))
		_check(screen._board_view._cell_at(body_point) == cells[1], "click boss body picks its tile")
		_check(screen.get_node("BattleHud").get_node("%PlayerStatusIcons").get_child_count() == 7, "all supplied status icons rendered")
		var intro: ChapterIntro = load("res://presentation/common/chapter_intro.tscn").instantiate()
		intro.chapter_index = act
		flow.add_child(intro)
		intro._tween.pause()
		intro.modulate.a = 1.0
		await _snapshot("12-act%d-intro" % (act + 1))
		intro.dismiss()
	flow._clear_screen()
	flow._shop_def = db.get_shop(&"shop.route")
	flow._shop_state = ShopState.new()
	flow._node_mode = &"shop"
	flow._rebuild_shop()
	await _snapshot("13-shop")
	var shop := _find(flow, NodeChoiceScreen) as NodeChoiceScreen
	var leaves := 1 if shop._leave_button.visible else 0
	for child: Node in shop._options_box.get_children():
		if child is Button and child.text == "离开":
			leaves += 1
	_check(leaves == 1, "shop has one leave button")


func _find(parent: Node, type: Script) -> Node:
	for child: Node in parent.get_children():
		if is_instance_of(child, type):
			return child
	return null


func _snapshot(label: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not _capture:
		return
	await RenderingServer.frame_post_draw
	var directory := "res://.validation/screenshots/%dx%d" % [root.size.x, root.size.y]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))


func _live_card_scenario(flow: RunFlow) -> void:
	flow._clear_screen()
	var panel := ColorRect.new()
	panel.color = Color("20212b")
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flow.add_child(panel)
	var state := FormalCardFixture.state(10, 80)
	state.get_unit(1).set_resource(&"courage", 4)
	var corrosion := StatusState.new()
	corrosion.status_id = StatusRules.CORRODE
	state.get_unit(1).set_status(900, corrosion)
	var i := 0
	for number: int in [3, 37, 46, 38]:
		var card := FormalCardFixture.add_card(state, number, number)
		card.upgrade_level = 1
		FormalCardRules.on_card_drawn(card)
		FormalCardRules.on_card_drawn(card)
		var def := ContentDB.get_card(card.card_id)
		var view: BattleCardView = load("res://presentation/cards/battle_card_view.tscn").instantiate()
		panel.add_child(view)
		view.position = Vector2(100 + 280 * i, 130)
		view.scale = Vector2(2, 2)
		view.setup(card, def, -1, false, state)
		_check(view.get_node("%CardName").text.ends_with("+"), "upgraded card name has single plus")
		var text: String = view.get_node("%Description").text
		_check(not text.contains("{"), "live card text has no unresolved placeholders")
		if number == 3:
			_check(text.contains("护盾+9"), "cautious forecast includes courage and corrosion")
		if number == 37:
			_check(text.contains("当前储备：12"), "stacked guard displays real reserve")
		if number == 46:
			_check(text.contains("打出治疗：8"), "heal displays real accumulated amount")
		_check(not CardInfo.upgrade_line(def).contains("无变化"), "special upgrade comparison describes actual effect")
		i += 1
	await _snapshot("14-live-upgraded-cards")
