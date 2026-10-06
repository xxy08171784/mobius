class_name CardPoolDef
extends Resource
## 奖励/商店共享卡池；在 Inspector 配置显式 ID 或按标签选取。
@export var id: StringName = &"pool.cards.formal"
@export var include_reward_enabled: bool = true
@export var card_ids: Array[StringName] = []
@export var required_tags: Array[StringName] = []
@export var excluded_tags: Array[StringName] = []


func resolve(content: Object) -> Array[StringName]:
	var result: Array[StringName] = []
	var cards: Dictionary = content.all_cards()
	for key: Variant in cards:
		var card: CardDef = cards[key]
		if not card_ids.has(card.card_id) and not (include_reward_enabled and card.reward_pool_enabled):
			continue
		var allowed := true
		for tag: StringName in required_tags:
			allowed = allowed and card.tags.has(tag)
		for tag: StringName in excluded_tags:
			allowed = allowed and not card.tags.has(tag)
		if allowed:
			result.append(card.card_id)
	result.sort()
	return result
