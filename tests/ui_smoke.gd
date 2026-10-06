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
	await _snapshot("04-route")
	var session: RunSession = app.current_session
	var node_id := session.available_node_ids()[0]
	flow._on_route_node_activated(node_id)
	await _snapshot("05-deployment")
	var battle := _find(flow, BattleScreen) as BattleScreen
	_check(battle != null and battle._deployment_mode, "deployment in battle scene")
	battle.deployment_cell_chosen.emit(Vector2i.ZERO)
	await _snapshot("06-battle")
	_check(not battle.demo_autostart, "formal battle disables demo")
	_check(battle.get_node("BattleHud/EnemyHUD").visible, "enemy HUD visible")
	_check(not battle.get_node("BattleHud").get_node("%EnemyName").text.begins_with("unit."), "enemy display name from content")
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
	flow._on_reward_chose({"action": "reward_choice", "index": 0})
	_check(session.state.flow_phase == &"route", "claim returns map")
	saves.clear_run()
	main.queue_free()
	await get_tree().process_frame
	print("UI smoke: %d failures" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)


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
