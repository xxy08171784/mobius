@abstract
class_name EffectHandler
extends RefCounted
## 基础效果处理器接口。handler 只修改 EffectResolver 创建的工作状态。


@abstract
func get_type_key() -> StringName


@abstract
func apply(
	work_state: Variant,
	effect: Dictionary,
	context: EffectContext,
	rng: RandomNumberGenerator
) -> Dictionary
