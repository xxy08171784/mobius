class_name EventDef
extends Resource
## 事件定义（设计数据，只读）：标题 + 正文 + 一组选项。

@export var id: StringName = &""
@export var title: String = ""
@export_multiline var body: String = ""
@export var choices: Array[EventChoice] = []


func is_valid() -> bool:
	return not id.is_empty() and not choices.is_empty()
