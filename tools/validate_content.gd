extends SceneTree
## godot --headless --path . -s res://tools/validate_content.gd
func _init() -> void:
	var content := load("res://autoload/content_db.gd").new() as Node
	if not content.load_catalog():
		content.free()
		quit(1)
		return
	var errors := ContentValidator.validate(content, load(RunSession.CAMPAIGN_PATH))
	for message: String in errors:
		printerr(message)
	print("Content validation: %d errors" % errors.size())
	content.free()
	quit(0 if errors.is_empty() else 1)
