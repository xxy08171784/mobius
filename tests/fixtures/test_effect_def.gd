class_name TestEffectDef
extends EffectDef
## 仅用于规则测试构造简单 EffectDef，不进入 content/。


static func make(key: StringName, effect_params: Dictionary = {}) -> TestEffectDef:
	var effect := TestEffectDef.new()
	effect.type_key = key
	effect.params = effect_params.duplicate(true)
	return effect
