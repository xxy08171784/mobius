class_name UnitView
extends Node2D
## 等轴测棋盘上的单位棋子。
## 玩家单位：莫小洛角色精灵（AnimatedSprite2D，walk_l/walk_r，见 UnitSpriteFrames）；
## 无独立待机帧，待机直接复用行走循环原地播（play_idle）。
## 敌人/素材缺失：色块菱形。上方数值浮标（HP/护盾/状态）两类共用。
## 只投影 UnitState，不修改规则状态。

const PLAYER_COLOR := Color(0.35, 0.70, 1.0, 0.95)
const ENEMY_COLOR := Color(1.0, 0.45, 0.45, 0.95)

## 精灵缩放：角色内容约 940px 高 → 盘上约 200px（配 300×200 地块）。调观感改这一个。
const SPRITE_SCALE := 0.22
## 脚底锚点：画布 1280×1280、脚底 y≈1219，相对画布中心 (640,640) 即 (0,-579)。
## 让角色脚踩在格子菱形中心（画布中心落在节点原点，见 iso_grid.gd 说明）。
const SPRITE_FEET_OFFSET := Vector2(0.0, -579.0)
## 角色头顶在节点局部的大约 y（由 (内容顶 280 - 脚底 1219) * SPRITE_SCALE 推得）。
const SPRITE_HEAD_Y := -206.0

var _unit_id: int = -1
var _is_player: bool = false
var _poly: Polygon2D = null
var _sprite: AnimatedSprite2D = null
var _label: Label = null
var _facing: StringName = UnitSpriteFrames.ANIM_RIGHT


func unit_id() -> int:
	return _unit_id


func is_player() -> bool:
	return _is_player


func setup(unit_id_value: int, is_player: bool) -> void:
	_unit_id = unit_id_value
	_is_player = is_player
	var hw := float(IsoGrid.DIAMOND_W) * 0.18
	var hh := float(IsoGrid.DIAMOND_H) * 0.18
	var lift := -float(IsoGrid.DIAMOND_H) * 0.10
	var label_y := lift - hh - 44.0

	if is_player:
		var frames := UnitSpriteFrames.get_frames()
		if frames != null and frames.has_animation(UnitSpriteFrames.ANIM_LEFT):
			_sprite = AnimatedSprite2D.new()
			_sprite.sprite_frames = frames
			_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
			_sprite.offset = SPRITE_FEET_OFFSET
			_sprite.animation = _facing
			_sprite.frame = 0
			add_child(_sprite)
			_sprite.play(_facing)   # 待机即行走循环：进场就开始播
			label_y = SPRITE_HEAD_Y - 38.0

	if _sprite == null:
		_poly = Polygon2D.new()
		_poly.polygon = PackedVector2Array([
			Vector2(0, -hh), Vector2(hw, 0), Vector2(0, hh), Vector2(-hw, 0),
		])
		_poly.color = PLAYER_COLOR if is_player else ENEMY_COLOR
		_poly.position = Vector2(0, lift)
		add_child(_poly)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	_label.custom_minimum_size = Vector2(160, 0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-80, label_y)
	add_child(_label)


func update(unit: UnitState) -> void:
	if _label == null or unit == null:
		return
	var parts: Array[String] = ["HP %d/%d" % [unit.hp, unit.max_hp]]
	if unit.block > 0:
		parts.append("盾 %d" % unit.block)
	var status := status_text(unit)
	if not status.is_empty():
		parts.append(status)
	_label.text = "\n".join(parts)


## 朝向判定（纯函数，可测）：按**屏幕左右**分，不按逻辑轴。
## 等轴测 TILE_LAYOUT_DIAMOND_RIGHT 下实测：逻辑 +x=屏幕右上、-x=左下、+y=右下、-y=左上，
## 故屏幕横向位移 ∝ (dx + dy)。(dx+dy)<0（左上/左下）→ walk_l；(dx+dy)>0（右上/右下）→ walk_r。
## 注意：不能按 dx / dy 单轴分组——那会把 (0,+1)（屏幕右下）当成"下=左"、(0,-1)（屏幕上左）
## 当成"上=右"，导致左上、右下两个方向朝向相反（已修）。
## dx+dy==0 为屏幕竖直（纯斜向），返回空串，调用方保持当前朝向。
static func facing_for(delta: Vector2i) -> StringName:
	var lateral := delta.x + delta.y
	if lateral < 0:
		return UnitSpriteFrames.ANIM_LEFT
	if lateral > 0:
		return UnitSpriteFrames.ANIM_RIGHT
	return &""


## 面朝方向：按屏幕左右切 walk_l / walk_r（见 facing_for）。
func face_dir(delta: Vector2i) -> void:
	if _sprite == null:
		return
	var decided := facing_for(delta)
	if decided == &"" or decided == _facing:
		return
	_facing = decided
	if _sprite.sprite_frames.has_animation(_facing):
		_sprite.play(_facing)


## 播放行走动画（保持当前朝向）。
func play_walk() -> void:
	if _sprite != null and _sprite.sprite_frames.has_animation(_facing):
		_sprite.play(_facing)


## 走一格：按该步的棋盘位移定朝向并播行走（供移动动画逐格调用）。
func walk_step(delta: Vector2i) -> void:
	face_dir(delta)
	play_walk()


## 待机：不复用独立待机帧，直接接着走行走动画循环（停步=保持当前朝向继续播）。
## 移动结束调用，与走路无缝衔接，不再冻结首帧。
func play_idle() -> void:
	play_walk()


## 受击脉冲（替代旧按钮 pulse）。返回 Tween 供动画队列等待。
func pulse() -> Tween:
	var tween := create_tween()
	scale = Vector2(0.85, 0.85)
	tween.tween_property(self, "scale", Vector2.ONE, 0.12)
	return tween


## 状态文案（沿用旧 BoardView 的展示规则）。
static func status_text(unit: UnitState) -> String:
	if unit == null or unit.statuses.is_empty():
		return ""
	var parts: Array[String] = []
	for instance_id: int in unit.status_ids():
		var status := unit.get_status(instance_id)
		if status == null or status.is_expired():
			continue
		match status.status_id:
			StatusRules.BLEED:
				parts.append("流血%d(%d)" % [status.stacks, status.duration])
			StatusRules.VULNERABLE:
				parts.append("易伤(%d)" % status.duration)
			StatusRules.FOCUS:
				parts.append("专注%d(%d)" % [status.stacks, status.duration])
			_:
				parts.append(String(status.status_id))
	return " ".join(parts)
