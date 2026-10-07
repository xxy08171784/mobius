extends Node
## 双通道音乐/音效；内容从 AudioCatalog 注入。
var catalog: AudioCatalog = preload("res://content/audio/default_audio.tres")
var _bgm: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []


func _ready() -> void:
	for bus_name: String in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
	_bgm = AudioStreamPlayer.new()
	_bgm.bus = "Music"
	add_child(_bgm)
	_bgm.finished.connect(func() -> void: _bgm.play())
	for i in 8:
		var voice := AudioStreamPlayer.new()
		voice.bus = "SFX"
		add_child(voice)
		_voices.append(voice)
	SettingsService.changed.connect(_apply_settings)
	_apply_settings()


func play_bgm(stream: AudioStream, volume_db: float = -12.0) -> void:
	if _bgm.stream == stream and _bgm.playing:
		return
	_bgm.stop()
	_bgm.stream = stream
	_bgm.volume_db = volume_db
	if stream != null:
		_bgm.play()


func play_sfx(stream: AudioStream) -> void:
	if stream == null:
		return
	for voice: AudioStreamPlayer in _voices:
		if not voice.playing:
			voice.stream = stream
			voice.play()
			return


func play_music(key: StringName) -> void:
	if key in [&"menu", &"route", &"battle", &"opening"]:
		play_bgm(catalog.get(String(key)))


func play_cue(key: StringName) -> void:
	if key in [&"victory", &"defeat", &"click"]:
		play_sfx(catalog.get(String(key)))


func set_master_volume(db: float) -> void:
	AudioServer.set_bus_volume_db(0, clampf(db, -80.0, 6.0))


func _apply_settings() -> void:
	for item: Array in [["Master", SettingsService.master], ["Music", SettingsService.music], ["SFX", SettingsService.sfx]]:
		var index := AudioServer.get_bus_index(item[0])
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, item[1])))
		AudioServer.set_bus_mute(index, item[1] <= 0.0)
