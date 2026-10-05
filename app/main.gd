extends Control
## 稳定根场景，负责装配。App/ContentDB/SaveService/AudioService 为 autoload。
## 场景切换交给 SceneRouter。


func _ready() -> void:
	# TODO: 启动流程（加载内容 -> 读取设置/档案 -> 进入主菜单）。
	ContentDB.load_catalog("res://content/catalog.tres")
