class_name ObstacleVisuals
extends RefCounted
## 运行时按 appearance_key 加载障碍贴图（静态缓存；缺图返回 null，板面回退暗色格）。

const TEXTURE_ROOT := "res://assets/textures/obstacles/"

static var _cache: Dictionary = {}


static func texture_for(appearance_key: StringName) -> Texture2D:
	if appearance_key == &"":
		return null
	if _cache.has(appearance_key):
		return _cache[appearance_key]
	var tex := load(TEXTURE_ROOT + String(appearance_key) + ".png") as Texture2D
	if tex == null:
		push_warning("ObstacleVisuals: 缺图 %s" % String(appearance_key))
	_cache[appearance_key] = tex
	return tex
