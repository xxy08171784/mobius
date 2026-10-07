class_name PlotIntro
extends Control
## 纯表现层开场剧情：图集分页（每页 2×2 四格），逐格点亮；点/空格推进，ESC 整段跳过。
## 不推进流程或随机数；全部点亮后发 finished，由 RunFlow 接手开新 run。
## 图片按 assets/textures/plot/ 下的文件名数字顺序使用（1.png < 2.png < …）。

signal finished

const PLOT_DIR := "res://assets/textures/plot"
const PANELS_PER_PAGE := 4

## 每格自动点亮的停留秒数（玩家手动推进后重新计时）。
@export var hold_seconds: float = 2.0

var _images: Array[Texture2D] = []
var _panels: Array[TextureRect] = []
var _page := 0
var _revealed := 0
var _total_pages := 0
var _timer: Timer = null
var _fade: Tween = null
var _hint: Label = null
var _done := false


func _ready() -> void:
	_images = _load_images()
	_panels = [$G1, $G2, $G3, $G4]
	_total_pages = maxi(1, ceili(float(_images.size()) / float(PANELS_PER_PAGE)))
	_timer = $Timer
	_timer.wait_time = hold_seconds
	_timer.timeout.connect(_advance)
	_hint = $Hint
	_start_hint()
	_start_page()
	_timer.start()
	AudioService.play_music(&"opening")


## 「点击进入下一步」提示：无 reduced_motion 时循环明暗闪烁，否则保持半亮。
func _start_hint() -> void:
	if _hint == null:
		return
	if SettingsService.reduced_motion:
		_hint.modulate = Color(1, 1, 1, 0.85)
		return
	_hint.modulate = Color(1, 1, 1, 0.3)
	var blink := create_tween()
	blink.set_loops()
	blink.tween_property(_hint, "modulate:a", 1.0, 0.7)
	blink.tween_property(_hint, "modulate:a", 0.3, 0.7)


func _load_images() -> Array[Texture2D]:
	var images: Array[Texture2D] = []
	# 导出包中 DirAccess 只列 *.png.import；资源 API 返回可 load 的逻辑名（同 iso_board_theme）。
	for name: String in ResourceLoader.list_directory(PLOT_DIR):
		if not name.ends_with(".png"):
			continue
		var texture := load(PLOT_DIR.path_join(name)) as Texture2D
		if texture != null:
			images.append(texture)
	# 按文件名里的数字排序，保证点亮顺序（1, 2, …, 9, 10）。
	images.sort_custom(func(a: Texture2D, b: Texture2D) -> bool:
		return int(a.resource_path.get_file().get_basename()) < int(b.resource_path.get_file().get_basename())
	)
	return images


## 翻到当前页：给四格换贴图、全部隐藏，等待逐格点亮。
func _start_page() -> void:
	var base := _page * PANELS_PER_PAGE
	for i: int in _panels.size():
		var index := base + i
		var panel: TextureRect = _panels[i]
		panel.texture = _images[index] if index < _images.size() else null
		panel.visible = false
		panel.modulate.a = 0.0
	_revealed = 0


func _page_panel_count() -> int:
	return mini(PANELS_PER_PAGE, _images.size() - _page * PANELS_PER_PAGE)


## 计时到点或玩家推进：先点亮本页下一格；本页满了翻页，最后一页满了结束。
func _advance() -> void:
	if _done:
		return
	if _revealed < PANELS_PER_PAGE and _revealed < _page_panel_count():
		_reveal(_revealed)
		_revealed += 1
		return
	if _page + 1 < _total_pages:
		_page += 1
		_start_page()
	else:
		_finish()


func _reveal(index: int) -> void:
	var panel: TextureRect = _panels[index]
	if panel.texture == null:
		return
	panel.visible = true
	if _fade != null:
		_fade.kill()
	_fade = create_tween()
	_fade.tween_property(panel, "modulate:a", 1.0, 0.05 if SettingsService.reduced_motion else 0.25)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_finish()
		return
	if event.is_action_pressed("ui_accept") or (event is InputEventMouseButton and event.pressed):
		get_viewport().set_input_as_handled()
		_advance()
		_timer.start()  # 手动推进后重置自动计时


func _finish() -> void:
	if _done:
		return
	_done = true
	if _timer != null and _timer.is_inside_tree():
		_timer.stop()
	finished.emit()
