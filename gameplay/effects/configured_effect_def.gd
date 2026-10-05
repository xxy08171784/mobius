class_name ConfiguredEffectDef
extends EffectDef
## 可直接由代码/资源配置的通用 EffectDef。
## 规则仍由 EffectResolver 的 handler 实现；这里只承载 type_key + params。


static func make(effect_type: StringName, parameters: Dictionary = {}) -> ConfiguredEffectDef:
	var definition := ConfiguredEffectDef.new()
	definition.type_key = effect_type
	definition.params = parameters.duplicate(true)
	return definition
