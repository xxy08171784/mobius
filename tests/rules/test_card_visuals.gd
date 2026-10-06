extends "res://tests/test_case.gd"


func run() -> Array[String]:
	reset()
	var definition := load("res://content/cards/reward/card_01.tres") as CardDef
	assert_true(definition != null, "formal reward card resource should load")
	if definition == null:
		return failures()

	var frame := CardVisuals.frame_for(definition)
	var icon := CardVisuals.icon_for(definition)
	assert_true(frame != null, "formal card should resolve its category frame")
	assert_true(icon != null, "formal card should resolve icon by card number")
	if frame != null:
		assert_equal(frame.get_size(), Vector2(420, 600), "card frame should preserve 420x600 size")
	if icon != null:
		assert_equal(icon.get_size(), Vector2(256, 256), "card icon should preserve 256x256 size")
	return failures()
