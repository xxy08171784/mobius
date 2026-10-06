class_name MainMenuScreen
extends Control
signal new_game
signal continue_run
signal quit
signal settings_requested
signal history_requested
signal library_requested
signal help_requested


func _ready() -> void:
	%NewGame.pressed.connect(func() -> void: new_game.emit())
	%Continue.pressed.connect(func() -> void: continue_run.emit())
	%Quit.pressed.connect(func() -> void: quit.emit())
	%Settings.pressed.connect(func() -> void: settings_requested.emit())
	%History.pressed.connect(func() -> void: history_requested.emit())
	%Library.pressed.connect(func() -> void: library_requested.emit())
	%Help.pressed.connect(func() -> void: help_requested.emit())


func setup(has_save: bool) -> void:
	%Continue.disabled = not has_save
	UIFocus.take_later(%Continue if has_save else %NewGame)
