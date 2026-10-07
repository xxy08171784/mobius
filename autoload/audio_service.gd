extends Node
## 仅负责表现：音乐、环境循环、短音效池；绝不消费玩法 RNG 或修改存档。
signal cue_started(key: StringName)
signal music_started(key: StringName)

var catalog: AudioCatalog
var scene_key: StringName = &""
var music_key: StringName = &""
var _bgm: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _music_tween: Tween
var _after_music: StringName = &""
var _last_cue_ms: Dictionary = {}
var _voice_cursor := 0
var _quitting := false
var _shutting_down := false


func _ready() -> void:
	# 延迟至运行时加载：首次 --editor --import 时音频尚未生成导入资源。
	if catalog == null:
		catalog = load("res://content/audio/default_audio.tres") as AudioCatalog
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus_name: String in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	_bgm = _player("Music")
	_bgm.finished.connect(_on_music_finished)
	_ambience = _player("SFX")
	for i in 12:
		_voices.append(_player("SFX"))
	SettingsService.changed.connect(_apply_settings)
	_apply_settings()
	get_tree().node_added.connect(_on_node_added)
	_bind_buttons(get_tree().root)
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(quit_game)


func _player(bus_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus_name
	add_child(player)
	return player


func _exit_tree() -> void:
	stop_all()


func stop_all() -> void:
	if _music_tween != null:
		_music_tween.kill()
		_music_tween = null
	for player: AudioStreamPlayer in _voices + [_bgm, _ambience]:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	_after_music = &""
	music_key = &""
	scene_key = &""


func shutdown() -> void:
	_shutting_down = true
	stop_all()
	# 混音线程停止后还需主线程回收播放实例；短至 120ms 在渲染忙时不足。
	# 不受暂停和 Engine.time_scale 影响，关闭期间也不再接收新声音。
	await get_tree().create_timer(0.35, true, false, true).timeout


func quit_game() -> void:
	if _quitting:
		return
	_quitting = true
	await shutdown()
	get_tree().quit()


## 场景重复刷新不重启音乐；奖励读档不会重播胜利音。
func enter_scene(key: StringName) -> void:
	if _shutting_down or scene_key == key:
		return
	var previous := scene_key
	scene_key = key
	if previous == &"route" and key != &"route":
		play_cue(&"map_close")
	if key == &"route":
		play_cue(&"map_open")
	set_campfire(key == &"rest")
	match key:
		&"menu", &"battle":
			play_music(key)
		&"victory", &"defeat":
			play_jingle(key)
		&"reward":
			if previous == &"battle":
				play_jingle(&"victory", &"route")
			else:
				play_music(&"route")
		_:
			play_music(&"route")


func play_music(key: StringName) -> void:
	if not AudioCatalog.MUSIC_KEYS.has(key):
		return
	if music_key == key and (_bgm.playing or (_music_tween != null and _music_tween.is_running())):
		return
	_after_music = &""
	music_key = key
	_transition_music(catalog.get(String(key)), catalog.music_gain_db, key in [&"menu", &"route", &"battle"])


func play_jingle(key: StringName, afterwards: StringName = &"") -> void:
	play_music(key)
	_after_music = afterwards


func play_bgm(stream: AudioStream, volume_db: float = -6.0) -> void:
	music_key = &""
	_after_music = &""
	_transition_music(stream, volume_db, true)


func _transition_music(stream: AudioStream, gain: float, looped: bool) -> void:
	if _shutting_down:
		return
	if _music_tween != null:
		_music_tween.kill()
	_music_tween = create_tween()
	if _bgm.playing:
		_music_tween.tween_property(_bgm, "volume_db", -60.0, 0.18)
	_music_tween.tween_callback(func() -> void:
		_bgm.stop()
		_bgm.stream = _loop_copy(stream, looped)
		_bgm.volume_db = -60.0
		if _bgm.stream != null:
			_bgm.play()
			music_started.emit(music_key)
	)
	_music_tween.tween_property(_bgm, "volume_db", gain, 0.3)


func _on_music_finished() -> void:
	if not _after_music.is_empty():
		var next := _after_music
		_after_music = &""
		play_music(next)


func _loop_copy(stream: AudioStream, looped: bool) -> AudioStream:
	if stream == null:
		return null
	var copy := stream.duplicate() as AudioStream
	if copy is AudioStreamMP3 or copy is AudioStreamOggVorbis:
		copy.loop = looped
	elif copy is AudioStreamWAV:
		copy.loop_mode = AudioStreamWAV.LOOP_FORWARD if looped else AudioStreamWAV.LOOP_DISABLED
	return copy


func set_campfire(enabled: bool) -> void:
	if _shutting_down and enabled:
		return
	if not enabled:
		_ambience.stop()
		return
	if _ambience.playing or catalog.campfire == null:
		return
	_ambience.stream = _loop_copy(catalog.campfire, true)
	_ambience.volume_db = catalog.ambience_gain_db
	_ambience.play()


func play_sfx(stream: AudioStream, gain: float = -4.0) -> void:
	_start_voice(stream, gain, &"")


func play_cue(key: StringName) -> void:
	if _shutting_down:
		return
	if key in [&"victory", &"defeat"]:
		play_jingle(key)
		return
	if not AudioCatalog.CUE_KEYS.has(key) or catalog.get(String(key)) == null:
		return
	# 同一帧的群体攻击/快速补牌只播一次，避免叠加十几层造成爆音。
	var now := Time.get_ticks_msec()
	if now - int(_last_cue_ms.get(key, -1000)) < 75:
		return
	_last_cue_ms[key] = now
	_start_voice(catalog.get(String(key)), catalog.cue_gain_db.get(key, -6.0), key)


func _start_voice(stream: AudioStream, gain: float, key: StringName) -> void:
	if _shutting_down or stream == null or _voices.is_empty():
		return
	var voice: AudioStreamPlayer = null
	var same: Array[AudioStreamPlayer] = []
	for candidate: AudioStreamPlayer in _voices:
		if not candidate.playing and voice == null:
			voice = candidate
		if candidate.playing and candidate.get_meta("cue", &"") == key:
			same.append(candidate)
	if not key.is_empty() and same.size() >= 2:
		voice = same[0]
	if voice == null:
		voice = _voices[_voice_cursor % _voices.size()]
		_voice_cursor += 1
	voice.stop()
	voice.set_meta("cue", key)
	voice.stream = stream
	voice.volume_db = gain
	voice.play()
	cue_started.emit(key)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_bind_button_id.call_deferred(node.get_instance_id())


func _bind_button_id(instance: int) -> void:
	var node := instance_from_id(instance)
	if node is BaseButton:
		_bind_button(node)


func _bind_buttons(node: Node) -> void:
	if node is BaseButton:
		_bind_button(node)
	for child: Node in node.get_children():
		_bind_buttons(child)


func _bind_button(button: BaseButton) -> void:
	if not is_instance_valid(button) or button.is_queued_for_deletion() or button.name == &"HitButton":
		return # 卡牌由自身处理，拖拽释放不会额外播选择音。
	var callback := _on_button_pressed.bind(button)
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _on_button_pressed(button: BaseButton) -> void:
	if is_instance_valid(button):
		play_cue(StringName(button.get_meta("audio_cue", &"click")))


func set_master_volume(db: float) -> void:
	AudioServer.set_bus_volume_db(0, clampf(db, -80.0, 6.0))


func _apply_settings() -> void:
	for item: Array in [["Master", SettingsService.master], ["Music", SettingsService.music], ["SFX", SettingsService.sfx]]:
		var index := AudioServer.get_bus_index(item[0])
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, item[1])))
		AudioServer.set_bus_mute(index, item[1] <= 0.0)
