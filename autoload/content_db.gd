class_name ContentDB
extends Node
## 稳定内容 ID -> 只读定义。autoload。
## 启动时从显式 catalog 加载，既检查引用，也保证导出时保留资源。
## 约定：Def 资源只读，运行时禁止修改。


func load_catalog(_path: String) -> void:
	# TODO: 加载 catalog.tres 并建立 ID 索引。
	pass


func get_card(_id: StringName) -> RefCounted:
	# TODO
	return null


func get_enemy(_id: StringName) -> RefCounted:
	# TODO
	return null
