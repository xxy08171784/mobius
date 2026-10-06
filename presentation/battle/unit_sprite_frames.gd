class_name UnitSpriteFrames
extends RefCounted
## 运行时从角色 PNG 构建 SpriteFrames（无手工编辑器步骤），风格同 IsoBoardTheme。
## 目录缺失/素材未导入时返回 null，UnitView 退回色块菱形（可无头跑）。
##
## 帧命名约定：l* = 朝屏幕左（左上/左下移动），r* = 朝屏幕右（右上/右下移动）。
## 判定规则见 UnitView.facing_for / face_dir。

const SPRITE_DIR := "res://assets/textures/units/mo_xiaoluo"
const LEFT_FRAMES: Array[String] = ["l1.png", "l2.png", "l3.png", "l4.png"]
const RIGHT_FRAMES: Array[String] = ["r1.png", "r2.png", "r3.png", "r4.png"]

const ANIM_LEFT := &"walk_l"
const ANIM_RIGHT := &"walk_r"
## 帧率：配合 BoardView.WALK_PER_STEP（0.35s/格）在一步里能播到约 3-4 帧，走路循环可见。
const FPS := 10.0

static var _frames: SpriteFrames = null


## 首次调用构建并缓存；两套帧都加载失败时返回 null（不抛错）。
static func get_frames() -> SpriteFrames:
	if _frames != null:
		return _frames
	var left := _load_frames(LEFT_FRAMES)
	var right := _load_frames(RIGHT_FRAMES)
	if left.is_empty() and right.is_empty():
		push_warning("UnitSpriteFrames: %s 角色 PNG 均无法加载（退回色块）" % SPRITE_DIR)
		return null

	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	_fill(sf, ANIM_LEFT, left)
	_fill(sf, ANIM_RIGHT, right)
	_frames = sf
	return _frames


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


static func _load_frames(names: Array[String]) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for fname: String in names:
		var path := SPRITE_DIR.path_join(fname)
		var tex := load(path) as Texture2D
		if tex == null:
			# 兜底：素材尚未导入时退回原始解码（仅编辑器/开发期）。
			var img := Image.load_from_file(path)
			if img != null:
				tex = ImageTexture.create_from_image(img)
		if tex != null:
			out.append(tex)
	return out
