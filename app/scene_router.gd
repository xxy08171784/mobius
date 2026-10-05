extends Node
## 菜单 / 路线 / 战斗之间的切换（占位）。


func goto_scene(path: String) -> void:
	get_tree().change_scene_to_file(path)
