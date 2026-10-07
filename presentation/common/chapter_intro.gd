class_name ChapterIntro
extends Control
## 纯表现层章节过场：不推进流程或随机数，点击/确认键可跳过。
@export_range(0, 2) var chapter_index: int = 0
@export var hold_seconds: float = 1.25
var _tween: Tween


func _ready() -> void:
	$Center/Emblem.texture = UIArt.texture(StringName("act%d" % (chapter_index + 1)))
	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.05 if SettingsService.reduced_motion else 0.4)
	_tween.tween_interval(hold_seconds)
	_tween.tween_property(self, "modulate:a", 0.0, 0.05 if SettingsService.reduced_motion else 0.5)
	_tween.tween_callback(queue_free)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed):
		get_viewport().set_input_as_handled()
		dismiss()


func dismiss() -> void:
	if _tween != null:
		_tween.kill()
	queue_free()
