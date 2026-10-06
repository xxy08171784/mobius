class_name CharacterSelectScreen
extends Control
signal chosen(character_id: StringName)
signal back
signal unlock_requested(character_id: StringName)


func _ready() -> void:
	%Back.pressed.connect(func() -> void: back.emit())


func setup(characters: Array, max_difficulty: int = 0) -> void:
	%Difficulty.clear()
	for level in range(max_difficulty + 1):
		%Difficulty.add_item("难度 %d · 敌人生命 +%d%%" % [level, level * 10], level)
	for character: Dictionary in characters:
		var button := Button.new()
		button.text = String(character.get("label", ""))
		button.custom_minimum_size = Vector2(0, 48)
		var id := StringName(character.get("id", ""))
		var locked := bool(character.get("locked", false))
		button.disabled = bool(character.get("disabled", false))
		button.pressed.connect(func() -> void:
			if locked:
				unlock_requested.emit(id)
			else:
				chosen.emit(id)
		)
		%Characters.add_child(button)
	UIFocus.take_later(%Back)


func seed_text() -> String:
	return %Seed.text.strip_edges()


func difficulty() -> int:
	return %Difficulty.get_selected_id()
