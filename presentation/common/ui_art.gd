class_name UIArt
extends RefCounted
## 新素材的显示裁切，原 PNG 不改写。区域按原图像素登记，自动适应导入尺寸限制。
const ROOT := "res://素材/"
const GENERATED_ROOT := "res://assets/textures/ui/hud_v04/"
const GENERATED_KEYS := [&"energy", &"movement", &"discard", &"end_turn", &"intent_attack", &"intent_status"]
const REGIONS := {
	&"hp": ["HUD/icon_hp.png", Vector2(3136, 1151), Rect2(42, 178, 2915, 934)],
	&"shield": ["HUD/icon_盾.png", Vector2(2048, 1887), Rect2(392, 177, 1262, 1689)],
	&"deck": ["HUD/icon_deck.png", Vector2(2459, 1482), Rect2(383, 231, 1729, 1185)],
	&"back": ["HUD/icon_back.png", Vector2(2144, 1888), Rect2(443, 610, 1659, 1243)],
	&"settings": ["HUD/icon_settings.png", Vector2(2048, 1912), Rect2(329, 362, 1375, 1323)],
	&"gold": ["HUD/icon_gold.png", Vector2(25, 25), Rect2(0, 0, 25, 25)],
	&"act1": ["HUD/icon_act1.png", Vector2(2848, 1492), Rect2(163, 225, 2509, 1243)],
	&"act2": ["HUD/icon_act2.png", Vector2(2848, 1511), Rect2(161, 223, 2514, 1245)],
	&"act3": ["HUD/icon_act3.png", Vector2(2848, 1473), Rect2(84, 279, 2684, 1194)],
	&"status.poison": ["状态/中毒.png", Vector2(2048, 1869), Rect2(437, 358, 1611, 1336)],
	&"resource.courage": ["状态/勇气.png", Vector2(2048, 1872), Rect2(476, 400, 1094, 1472)],
	&"status.stun": ["状态/眩晕.png", Vector2(2048, 1885), Rect2(292, 264, 1485, 1439)],
	&"status.ignite": ["状态/着火.png", Vector2(2048, 1893), Rect2(494, 274, 1058, 1466)],
	&"status.entangle": ["状态/禁锢.png", Vector2(2048, 1903), Rect2(0, 454, 2048, 1449)],
	&"status.slow": ["状态/移动力减少.png", Vector2(2048, 1857), Rect2(181, 257, 1427, 1370)],
	&"status.weak": ["状态/虚弱.png", Vector2(2048, 1912), Rect2(4, 7, 1844, 1830)],
}
static var _cache: Dictionary = {}


static func texture(key: StringName) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	if GENERATED_KEYS.has(key):
		var source := load(GENERATED_ROOT + String(key) + ".png") as Texture2D
		var pixels := source.get_image()
		if pixels.is_compressed():
			pixels.decompress()
		var atlas := AtlasTexture.new()
		atlas.atlas = source
		atlas.region = Rect2(pixels.get_used_rect())
		atlas.filter_clip = true
		_cache[key] = atlas
		return atlas
	if not REGIONS.has(key):
		return null
	var spec: Array = REGIONS[key]
	var source := load(ROOT + String(spec[0])) as Texture2D
	if source == null:
		return null
	var factor: Vector2 = source.get_size() / Vector2(spec[1])
	var region: Rect2 = spec[2]
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = Rect2(region.position * factor, region.size * factor)
	atlas.filter_clip = true
	_cache[key] = atlas
	return atlas


static func background(act_index: int) -> Texture2D:
	return load(ROOT + "背景/bg_act%d.png" % (clampi(act_index, 0, 2) + 1)) as Texture2D
