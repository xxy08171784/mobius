extends Node
## 真场景回归：能量门槛、临时减费、组合点击、拖拽释放、无效取消、护盾与意图。
var failures: Array[String] = []
var screen: BattleScreen
var input_viewport: SubViewport
var container: TextureRect

func _ready() -> void:
	get_tree().create_timer(40.0).timeout.connect(func() -> void: get_tree().quit(1))
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		printerr("[FAIL] " + message)

func _run() -> void:
	ContentDB.ensure_loaded()
	SettingsService.reduced_motion = true
	# 独立 SubViewport 经 TextureRect 显示，避免 SubViewportContainer 把 OS 光标
	# 坐标重新灌入测试。完整 GUI 拖拽使用合成事件，不移动使用者的操作系统光标。
	container = TextureRect.new()
	get_tree().root.add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	input_viewport = SubViewport.new()
	input_viewport.size = Vector2i(1920, 1080)
	input_viewport.size_2d_override = Vector2i(1920, 1080)
	input_viewport.size_2d_override_stretch = true
	input_viewport.gui_embed_subwindows = true
	add_child(input_viewport)
	input_viewport.notify_mouse_entered()
	container.texture = input_viewport.get_texture()
	var state := FormalCardFixture.state(80, 80, 100)
	state.get_unit(2).def_id = &"unit.enemy.tomb.scorpion"
	state.get_unit(2).enemy_id = &"enemy.tomb.scorpion"
	for pair: Array in [[201, &"card.starter.attack"], [202, &"card.starter.defend"], [203, &"card.starter.punch"], [204, &"card.starter.defend"], [205, &"card.reward.02"]]:
		FormalCardFixture.add_token(state, pair[1], pair[0])
	var status_action := EnemyActionDef.new()
	status_action.id = &"test.status"
	status_action.apply_status_id = StatusRules.POISON
	status_action.apply_status_stacks = 2
	var intent := IntentState.new()
	intent.actor_id = 2
	intent.action_id = status_action.id
	state.enemy_intents[2] = intent
	var behavior := SequenceBehaviorDef.new()
	behavior.sequence = [status_action]
	screen = load("res://presentation/battle/battle_screen.tscn").instantiate()
	screen.demo_autostart = false
	input_viewport.add_child(screen)
	screen.configure({"state": state, "rng": FormalCardFixture.rng("7654"),
		"card_defs": ContentDB.all_cards(), "card_labels": {}, "enemy_behaviors": {2: behavior}, "enemy_actions": {status_action.id: status_action}})
	await get_tree().process_frame
	var input := screen._battle_input
	var hud := screen._battle_hud
	var bubble := screen._board_view.unit_view(2)._intent_bubble
	check(bubble.icon_key == &"intent_status" and bubble._label.text == "2", "zero-damage status intent has status icon and stacks")
	check(not hud.get_node("%PlayerShieldBar").visible, "zero player shield hidden")
	state.get_unit(1).block = 12
	state.get_unit(2).block = 7
	screen._presenter.set_selection([], 2)
	check(hud.get_node("%PlayerShieldValue").text == "12", "player shield is numeric")
	check(hud.get_node("%EnemyShieldValue").text == "7", "enemy shield is numeric")
	check(hud.get_node("%PlayerShieldBar").get_global_rect().has_point(hud.get_node("%PlayerShieldValue").get_global_rect().get_center()), "shield value inside icon")
	await snapshot("01-shield-and-status-intent")
	state.get_unit(1).block = 0
	state.get_unit(2).block = 0
	state.get_unit(1).set_resource(&"energy", 0)
	screen._presenter.refresh()
	input.on_card_pressed(201)
	check(input._selected_cards.is_empty(), "zero energy cannot select paid card")
	check(screen._feedback.text == "能量不足" and screen._feedback.visible, "center feedback visible")
	check(not input.can_start_drag(201), "zero energy cannot start paid drag")
	input.on_card_pressed(203)
	check(input._selected_cards == [203], "zero-cost card still selectable")
	check(screen._hand_view._views_by_uid[201]._content.modulate.r < 0.6, "unaffordable card dimmed")
	await snapshot("02-insufficient-energy")
	input.clear_selection()
	state.deck.get_card(201).cost_modifier = -1
	input.on_card_pressed(201)
	check(input._selected_cards == [201], "temporary cost reduction is respected")
	input.clear_selection()
	state.deck.get_card(201).cost_modifier = 0
	state.get_unit(1).set_resource(&"energy", 1)
	input.on_card_pressed(201)
	input.on_card_pressed(202)
	check(input._selected_cards == [201], "combination cannot exceed remaining energy")
	input.on_card_pressed(203)
	input.on_cell_pressed(Vector2i(3, 2))
	check(state.get_unit(2).hp == 100 and state.deck.hand.has(201), "click target only selects; does not play")
	screen._on_play_pressed()
	await settled()
	check(screen._session.state.get_unit(2).hp == 90, "confirmed attack and punch combo resolves together")
	check(not screen.get_node("PreviewLabel").visible, "persistent preview text removed")
	state = screen._session.state
	state.get_unit(1).set_resource(&"energy", 2)
	screen._presenter.refresh()
	var before := SaveCodec.new().encode_state(state)
	check(input.drop_status(202, Vector2i(4, 4)).is_empty(), "self card may drop on board")
	check(SaveCodec.new().encode_state(state) == before, "drop preview leaves battle and RNG unchanged")
	input.play_dropped(202, Vector2i(-1, -1))
	check(state.deck.hand.has(202) and state.get_unit(1).get_resource(&"energy") == 2, "invalid drop consumes nothing")
	# 走真实 Control 拖拽/释放派发，既覆盖 forwarding，也防止松手额外触发点击。
	await drag_card(202, Vector2i(4, 4))
	await settled()
	check(not screen._session.state.deck.hand.has(202), "GUI drag release plays self card")
	check(screen._session.state.get_unit(1).block == 5, "dragged defense gains shield once")
	check(screen._session.state.get_unit(1).get_resource(&"energy") == 1, "drag spends energy once")
	check(input._selected_cards.is_empty(), "drag does not leave accidental click selection")
	var after_defense := SaveCodec.new().encode_state(screen._session.state)
	await drag_card(204, Vector2i(-10, -10))
	check(SaveCodec.new().encode_state(screen._session.state) == after_defense, "release outside board cancels without changes")
	check(input.drop_status(205, Vector2i(4, 4)) == "没有可选择的卡牌", "choice card with no candidates gives feedback")
	FormalCardFixture.add_token(screen._session.state, &"card.starter.attack", 206)
	screen._presenter.refresh()
	await drag_card(206, Vector2i(7, 7))
	check(screen._session.state.deck.hand.has(206), "attack dragged to empty tile does not play")
	await drag_card(206, Vector2i(3, 2))
	await settled()
	check(not screen._session.state.deck.hand.has(206), "attack drag targets and plays without confirm button")
	check(screen._session.state.get_unit(2).hp == 84, "attack drag deals damage once")
	state = screen._session.state
	state.get_unit(1).set_resource(&"energy", 1)
	FormalCardFixture.add_token(state, &"card.starter.attack", 207, DeckState.ZONE_DRAW)
	screen._presenter.refresh()
	var before_choice := SaveCodec.new().encode_state(state)
	await drag_card(205, Vector2i(4, 4))
	var popup: CardChoicePopup = null
	for child: Node in screen.get_children():
		if child is CardChoicePopup:
			popup = child
	check(popup != null, "drag requiring a card choice opens the choice window")
	if popup != null:
		popup._cancel()
	await settled()
	check(SaveCodec.new().encode_state(screen._session.state) == before_choice, "cancel choice after drag consumes nothing")
	input.clear_selection()
	await snapshot("03-after-drag")
	container.queue_free()
	input_viewport.queue_free()
	await get_tree().process_frame
	print("Battle controls: %d failures" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)

func settled() -> void:
	while screen._battle_input._busy:
		await get_tree().process_frame
	await get_tree().process_frame

func drag_card(uid: int, target: Vector2i) -> void:
	var view: BattleCardView = screen._hand_view._views_by_uid[uid]
	var start := view._hit_button.get_global_transform_with_canvas() * (view._hit_button.size * 0.5)
	var board := screen._board_view
	var end := board._tile_layer.get_global_transform_with_canvas() * IsoGrid.center_of(board._tile_layer, target)
	var motion := InputEventMouseMotion.new()
	motion.position = start
	motion.global_position = start
	input_viewport.push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.position = start
	press.global_position = start
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	input_viewport.push_input(press, true)
	await get_tree().process_frame
	motion = InputEventMouseMotion.new()
	motion.position = start + Vector2(0, -25)
	motion.global_position = motion.position
	motion.relative = Vector2(0, -25)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	input_viewport.push_input(motion, true)
	await get_tree().process_frame
	motion = InputEventMouseMotion.new()
	motion.position = end
	motion.global_position = end
	motion.relative = end - start
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	input_viewport.push_input(motion, true)
	await get_tree().process_frame
	check(input_viewport.gui_is_dragging(), "native card drag started")
	var release := InputEventMouseButton.new()
	release.position = end
	release.global_position = end
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	input_viewport.push_input(release, true)
	await get_tree().process_frame

func snapshot(label: String) -> void:
	await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		var dir := "res://.validation/controls-screenshots/%dx%d" % [get_tree().root.size.x, get_tree().root.size.y]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		get_tree().root.get_texture().get_image().save_png(dir.path_join(label + ".png"))
