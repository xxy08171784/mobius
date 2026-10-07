extends Node
## 播放真实导入资源，验证场景切换、音量总线、结算触发、静默预演及循环终止。
var failures: Array[String] = []
var cues: Array[StringName] = []
var screen: BattleScreen


func _ready() -> void:
	get_tree().create_timer(30.0).timeout.connect(func() -> void: get_tree().quit(1))
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		printerr("[FAIL] " + message)


func reset_cues() -> void:
	cues.clear()
	AudioService._last_cue_ms.clear()


func settle() -> void:
	while screen._battle_input._busy:
		await get_tree().process_frame
	await get_tree().process_frame


func _run() -> void:
	AudioService.cue_started.connect(func(key: StringName) -> void: cues.append(key))
	for key: StringName in AudioCatalog.MUSIC_KEYS + AudioCatalog.CUE_KEYS + [&"campfire"]:
		var stream: AudioStream = AudioService.catalog.get(String(key))
		check(stream != null and stream.get_length() > 0.05, "audio imports and decodes " + String(key))
	AudioService.enter_scene(&"menu")
	await get_tree().create_timer(0.4).timeout
	check(AudioService._bgm.playing and AudioService._bgm.stream.loop, "menu music actually plays and loops")
	check(not AudioService.catalog.menu.loop, "loop uses a copy without mutating catalog")
	var original_stream := AudioService._bgm.stream
	AudioService.enter_scene(&"menu")
	check(AudioService._bgm.stream == original_stream, "same scene doesn't restart music")
	reset_cues()
	AudioService.enter_scene(&"route")
	AudioService.enter_scene(&"rest")
	check(cues.has(&"map_open") and cues.has(&"map_close"), "map transitions play open and close")
	check(AudioService._ambience.playing, "rest starts campfire")
	AudioService.enter_scene(&"menu")
	check(not AudioService._ambience.playing, "leaving rest stops campfire")
	AudioService.enter_scene(&"battle")
	AudioService.enter_scene(&"reward")
	await get_tree().create_timer(0.65).timeout
	check(AudioService.music_key == &"victory" and not AudioService._bgm.stream.loop, "reward plays victory once")
	AudioService._bgm.stop()
	AudioService._bgm.finished.emit()
	await get_tree().create_timer(0.4).timeout
	check(AudioService.music_key == &"route" and AudioService._bgm.stream.loop, "victory naturally returns to route music")
	AudioService.enter_scene(&"battle")
	AudioService.enter_scene(&"reward")
	AudioService.enter_scene(&"menu")
	await get_tree().create_timer(0.65).timeout
	check(AudioService.music_key == &"menu" and AudioService._after_music.is_empty(), "fast menu exit cancels pending victory continuation")
	AudioService.enter_scene(&"reward")
	check(AudioService.music_key == &"route", "restoring reward doesn't replay battle victory")
	AudioService.enter_scene(&"defeat")
	await get_tree().create_timer(0.65).timeout
	check(AudioService.music_key == &"defeat" and not AudioService._bgm.stream.loop, "defeat replaces battle music and doesn't loop")

	SettingsService.sfx = 0.0
	SettingsService.apply()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "SFX setting mutes effects and ambience")
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "SFX setting leaves music independent")
	SettingsService.sfx = 0.8
	SettingsService.music = 0.0
	SettingsService.apply()
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")), "music setting also controls victory and defeat")
	SettingsService.music = 0.7
	SettingsService.apply()
	var button := Button.new()
	add_child(button)
	await get_tree().process_frame
	reset_cues()
	button.pressed.emit()
	button.pressed.emit()
	check(cues.count(&"click") == 1, "buttons auto-bind once and rapid repeats are limited")
	get_tree().paused = true
	button.set_meta("audio_cue", &"confirm")
	button.pressed.emit()
	check(cues.has(&"confirm"), "pause-menu UI audio remains available")
	get_tree().paused = false
	button.queue_free()

	ContentDB.ensure_loaded()
	SettingsService.reduced_motion = true
	var state := FormalCardFixture.state(60, 80, 100)
	state.move_points_per_round = 2
	FormalCardFixture.add_token(state, &"card.reward.18", 201)
	FormalCardFixture.add_token(state, &"card.starter.defend", 202)
	FormalCardFixture.add_token(state, &"card.reward.38", 203)
	FormalCardFixture.add_token(state, &"card.starter.attack", 204, DeckState.ZONE_DRAW)
	screen = load("res://presentation/battle/battle_screen.tscn").instantiate()
	screen.demo_autostart = false
	add_child(screen)
	screen.configure({"state": state, "rng": FormalCardFixture.rng("audio"), "card_defs": ContentDB.all_cards(), "card_labels": {}, "enemy_behaviors": {}, "enemy_actions": {}})
	await get_tree().process_frame
	reset_cues()
	screen._presenter.refresh()
	screen._battle_input.drop_status(201, Vector2i(3, 2))
	check(cues.is_empty(), "refresh and accepted preview remain silent")
	screen._battle_input.play_dropped(201, Vector2i(-1, -1))
	check(cues.is_empty(), "invalid release doesn't play combat sound")
	screen._battle_input.play_dropped(201, Vector2i(3, 2))
	await settle()
	check(cues.count(&"card_use") == 1 and cues.has(&"sword"), "accepted sword card plays use and matching hit")
	check(not cues.has(&"punch"), "sword doesn't use fist sound")
	reset_cues()
	screen._battle_input.play_dropped(202, Vector2i(4, 4))
	await settle()
	check(cues.has(&"shield") and not cues.has(&"player_hurt"), "gaining shield plays defense")
	reset_cues()
	screen._battle_input.play_dropped(203, Vector2i(4, 4))
	await settle()
	check(cues.has(&"card_draw") and cues.has(&"card_upgrade"), "hold back draws and upgrades with audio")
	reset_cues()
	SettingsService.reduced_motion = false
	screen._presenter._animation_queue.step_seconds = 0.0
	screen._board_view.set_speed_multiplier(10.0)
	screen._battle_input.on_cell_pressed(Vector2i(1, 2))
	await settle()
	check(cues.has(&"step_grass"), "animated movement plays step at destination")
	reset_cues()
	var feedback := BattleAudioFeedback.new()
	var hit := EffectEvent.create(1, &"damage", 2, 1, {"hp": 80}, {"hp": 77}, {"amount": 3, "hp_damage": 3})
	feedback.play_event(hit, screen._session.state, false)
	check(cues == [&"player_hurt"], "enemy hit uses player hurt, without a player sword cue")
	reset_cues()
	var before := SaveCodec.new().clone_state(screen._session.state) as BattleState
	var after := SaveCodec.new().clone_state(before) as BattleState
	after.round_index += 1
	feedback.begin_result(EndTurnCommand.new(), before, after)
	feedback.finish_result()
	check(cues.has(&"card_draw"), "round refill sounds even if reshuffle redraws identical UIDs")
	reset_cues()
	var water := CellState.new()
	water.terrain_key = &"water"
	after.board.set_cell(Vector2i(0, 0), water)
	feedback.play_step(after, Vector2i.ZERO)
	check(cues.has(&"step_water"), "explicit water terrain selects water steps")
	check(not cues.has(&"dice") and not cues.has(&"water_appear") and not cues.has(&"poison_trap"), "reserved cues don't trigger without a mechanic")
	# 录制游戏内部 SFX 总线，不访问麦克风；验证解码/混音输出确实有波形。
	var sfx_bus := AudioServer.get_bus_index("SFX")
	var recorder := AudioEffectRecord.new()
	AudioServer.add_bus_effect(sfx_bus, recorder)
	var effect_index := AudioServer.get_bus_effect_count(sfx_bus) - 1
	recorder.set_recording_active(true)
	reset_cues()
	AudioService.play_cue(&"punch")
	await get_tree().create_timer(1.2).timeout
	recorder.set_recording_active(false)
	var recording := recorder.get_recording()
	check(recording != null and recording.data.size() > 1000 and recording.data.count(0) < recording.data.size(), "SFX decoder and mixer produce audible waveform")
	if recording != null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.validation"))
		recording.save_to_wav("res://.validation/audio_mix.wav")
	AudioServer.remove_bus_effect(sfx_bus, effect_index)
	screen.queue_free()
	await get_tree().process_frame
	await AudioService.shutdown()
	print("Audio smoke: %d failures" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
