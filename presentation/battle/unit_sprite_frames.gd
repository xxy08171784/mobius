class_name UnitSpriteFrames
extends RefCounted
## 运行时从单位 PNG 构建 SpriteFrames（无手工编辑器步骤），风格同 IsoBoardTheme。
##
## **动画接口（与玩家完全同一套）**：每个单位两段动画 = 朝屏幕左 / 朝屏幕右（互为镜像）。
## 目录内 `l*.png` / `r*.png` -> 动画 `walk_l` / `walk_r`。**没有**走路/攻击/受击/死亡帧；
## 位移与待机都复用这两段（待机=原地播当前朝向那段）。怪物落地即遵循同一约定，
## 美术只需把 `<appearance_key>/l1.., r1...png` 丢进目录即可生效。
##
## 目录约定：`res://assets/textures/units/<appearance_key>/`。缺素材返回 null，
## UnitView 退回色块菱形（可无头跑）。
## 朝向判定见 UnitView.facing_for / face_dir。

const SPRITE_ROOT := "res://assets/textures/units/"
## 玩家沿用历史目录名（玩家 UnitDef.appearance_key 与目录名不同，故玩家走 get_frames()）。
const PLAYER_DIR_KEY := &"mo_xiaoluo"

const ANIM_LEFT := &"walk_l"
const ANIM_RIGHT := &"walk_r"
## 帧率：配合 BoardView.WALK_PER_STEP（0.35s/格）在一步里能播到约 3-4 帧，走路循环可见。
const FPS := 10.0

## 飞行单位的悬停高度（纹理像素；渲染时精灵与浮标整体上移）。地面单位为 0（踩在格子上）。
const HOVER_PX := {
	&"tomb_bat": 150.0,
	&"tomb_soul_lantern": 120.0,
	&"catacomb_will_o_wisp": 130.0,
}

static var _cache: Dictionary = {}


## 该外观的悬停高度（纹理像素）。未登记 = 0（地面单位）。
static func hover_offset(appearance_key: StringName) -> float:
	return float(HOVER_PX.get(appearance_key, 0.0))


## 玩家精灵（沿用固定目录）。
static func get_frames() -> SpriteFrames:
	return get_frames_for(PLAYER_DIR_KEY)


## 按外观键加载两朝向待机（敌人接口）。key 为空 / 素材缺失返回 null（不抛错）。
## 帧数可变：只加载目录里**实际存在**的 `l*.png` / `r*.png`（3 帧、4 帧都行）。
static func get_frames_for(appearance_key: StringName) -> SpriteFrames:
	if appearance_key == &"":
		return null
	if _cache.has(appearance_key):
		return _cache[appearance_key]
	var dir := SPRITE_ROOT + String(appearance_key)
	var left := _load_directional_frames(dir, "l")
	var right := _load_directional_frames(dir, "r")
	if left.is_empty() and right.is_empty():
		_cache[appearance_key] = null
		return null

	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	_fill(sf, ANIM_LEFT, left)
	_fill(sf, ANIM_RIGHT, right)
	_cache[appearance_key] = sf
	return sf


## 两套动画都可用（用于 UnitView 决定是否走精灵分支）。
static func has_frames() -> bool:
	return get_frames() != null


static func _fill(sf: SpriteFrames, anim: StringName, texs: Array[Texture2D]) -> void:
	if texs.is_empty():
		return
	sf.add_animation(anim)
	sf.set_animation_loop(anim, true)
	sf.set_animation_speed(anim, FPS)
	for tex: Texture2D in texs:
		sf.add_frame(anim, tex)


## 加载某朝向的帧：目录里实际存在的 `<prefix>*.png`，按文件名排序。
static func _load_directional_frames(dir: String, prefix: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for fname: String in _list_pngs(dir, prefix):
		var path := dir.path_join(fname)
		var tex := load(path) as Texture2D
		if tex == null:
			# 兜底：素材尚未导入时退回原始解码（仅编辑器/开发期）。
			var img := Image.load_from_file(path)
			if img != null:
				tex = ImageTexture.create_from_image(img)
		if tex != null:
			out.append(tex)
	return out


static func _list_pngs(dir: String, prefix: String) -> Array[String]:
	var names: Array[String] = []
	var da := DirAccess.open(dir)
	if da == null:
		return names
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		if not da.current_is_dir() and name.begins_with(prefix) and name.ends_with(".png"):
			names.append(name)
		name = da.get_next()
	da.list_dir_end()
	names.sort()
	return names
