class_name EffectContext
extends RefCounted
## 一次效果执行所需的运行上下文。只存稳定 ID / 目标数据，不引用场景节点。

var source_unit_id: int = -1
var source_card_uid: int = -1
var target: Variant = null
var root_trigger_id: int = 0
var depth: int = 0
## 只读式执行元数据：组合出牌信息、来源牌分类等。
## handler 可读取，但不应把场景节点或不可序列化对象塞进来。
var metadata: Dictionary = {}


func duplicate_context() -> EffectContext:
	var copy := EffectContext.new()
	copy.source_unit_id = source_unit_id
	copy.source_card_uid = source_card_uid
	copy.target = target
	copy.root_trigger_id = root_trigger_id
	copy.depth = depth
	copy.metadata = metadata.duplicate(true)
	return copy


static func from_dictionary(data: Dictionary) -> EffectContext:
	var context := EffectContext.new()
	context.source_unit_id = int(data.get("source_unit_id", -1))
	context.source_card_uid = int(data.get("source_card_uid", -1))
	context.target = data.get("target")
	context.root_trigger_id = int(data.get("root_trigger_id", 0))
	context.depth = int(data.get("depth", 0))
	var raw_metadata: Variant = data.get("metadata", {})
	context.metadata = (raw_metadata as Dictionary).duplicate(true) if raw_metadata is Dictionary else {}
	return context
