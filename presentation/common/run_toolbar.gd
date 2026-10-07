@tool
class_name RunToolbar
extends HBoxContainer

func _ready() -> void:
	$Deck.icon = UIArt.texture(&"deck")
	$Pause.icon = UIArt.texture(&"settings")
	$Gold/Icon.texture = UIArt.texture(&"gold")


func set_gold(amount: int) -> void:
	$Gold/Value.text = str(amount)
