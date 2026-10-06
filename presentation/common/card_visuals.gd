class_name CardVisuals
extends RefCounted
## 动态卡面素材入口：卡框 + 技能图标。
## generated/ 下旧的整卡 PNG 仅保留为参考，不再用于战斗手牌。

const FRAME_DIR := "res://assets/textures/cards/frames"
const ICON_DIR := "res://assets/textures/cards/icons"
const FRAME_SKILL := FRAME_DIR + "/技能牌卡框.png"
const FRAME_TECHNIQUE := FRAME_DIR + "/招式牌卡框.png"
const FRAME_ATTACK := FRAME_DIR + "/攻击牌卡框.png"
const FRAME_DEFENSE := FRAME_DIR + "/防御牌卡框.png"


static func frame_for(definition: CardDef) -> Texture2D:
	if definition == null:
		return null
	var path := _frame_path(definition)
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func icon_for(definition: CardDef) -> Texture2D:
	if definition == null:
		return null
	var key := String(definition.get_icon_key())
	if key.is_empty():
		key = "icon_01"
	var path := "%s/%s.png" % [ICON_DIR, key]
	if not ResourceLoader.exists(path):
		path = "%s/icon_01.png" % ICON_DIR
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func _frame_path(definition: CardDef) -> String:
	match definition.card_category:
		CardDef.CardCategory.SKILL:
			return FRAME_SKILL
		CardDef.CardCategory.TECHNIQUE:
			return FRAME_TECHNIQUE
		CardDef.CardCategory.DEFENSE:
			return FRAME_DEFENSE
		CardDef.CardCategory.ATTACK:
			return FRAME_ATTACK
	var tags := definition.get_tags()
	if tags.has(CardDef.TAG_DEFENSE):
		return FRAME_DEFENSE
	if tags.has(CardDef.TAG_TECHNIQUE):
		return FRAME_TECHNIQUE
	if tags.has(CardDef.TAG_SKILL):
		return FRAME_SKILL
	return FRAME_ATTACK
