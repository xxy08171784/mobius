extends Control
## 稳定根场景，负责装配。App/ContentDB/SaveService/AudioService 为 autoload。
## 启动流程：加载内容 -> 主菜单 -> RunFlow 编排（选角 -> 路线 <-> 战斗/节点）。


func _ready() -> void:
	ContentDB.load_catalog("res://content/catalog.tres")
	var flow := RunFlow.new()
	flow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(flow)
	flow.show_main_menu()
