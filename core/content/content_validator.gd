class_name ContentValidator
extends RefCounted
## 内容完整性检查；返回可供编辑器、CLI 和 CI 展示的问题列表。


static func validate(content: Object, campaign: CampaignDef = null) -> Array[String]:
	var errors: Array[String] = []
	if content == null or not content.is_loaded():
		errors.append("内容目录未加载；检查空 ID、重复 ID 与资源解析错误。")
		return errors
	var resolver := EffectResolver.new()
	for id: StringName in content.character_ids():
		var character: CharacterDef = content.get_character(id)
		_require(content.get_unit(character.unit_def_id), id, character.unit_def_id, errors)
		for card: StringName in character.starter_deck:
			_require(content.get_card(card), id, card, errors)
		for relic: StringName in character.starter_relics:
			_require(content.get_relic(relic), id, relic, errors)
	for id: StringName in content.enemy_ids():
		var enemy: EnemyDef = content.get_enemy(id)
		_require(content.get_unit(enemy.unit_def_id), id, enemy.unit_def_id, errors)
		if not enemy.behavior is SequenceBehaviorDef or enemy.behavior.sequence.is_empty():
			errors.append("%s: 缺少非空 SequenceBehaviorDef" % id)
			continue
		var seen: Dictionary = {}
		for action: EnemyActionDef in enemy.behavior.sequence:
			if action == null or action.id.is_empty():
				errors.append("%s: 行动为空或缺少稳定 ID" % id)
				continue
			if seen.has(action.id) and seen[action.id] != action:
				errors.append("%s: 行动 ID 冲突 %s" % [id, action.id])
			seen[action.id] = action
			if not action.apply_status_id.is_empty():
				_require(content.get_status(action.apply_status_id), id, action.apply_status_id, errors)
	for id: StringName in content.encounter_ids():
		var encounter: EncounterDef = content.get_encounter(id)
		for enemy: StringName in encounter.enemy_ids + encounter.summon_enemy_ids:
			_require(content.get_enemy(enemy), id, enemy, errors)
	for id: StringName in content.monster_pool_ids():
		var pool: MonsterPoolDef = content.get_monster_pool(id)
		for enemy: StringName in pool.enemy_ids:
			_require(content.get_enemy(enemy), id, enemy, errors)
	for id: StringName in content.shop_ids():
		var shop: ShopDef = content.get_shop(id)
		var cards: Array = shop.pool.resolve(content) if shop.pool != null else shop.card_pool
		if cards.is_empty():
			errors.append("%s: 卡池为空" % id)
		for card: StringName in cards:
			_require(content.get_card(card), id, card, errors)
		if shop.pool != null:
			for card: StringName in shop.pool.card_ids:
				_require(content.get_card(card), id, card, errors)
	for id: StringName in content.event_ids():
		var event: EventDef = content.get_event(id)
		for choice: EventChoice in event.choices:
			if choice == null:
				errors.append("%s: 事件选项为空" % id)
			elif not choice.add_card_id.is_empty():
				_require(content.get_card(choice.add_card_id), id, choice.add_card_id, errors)
	for id: StringName in content.card_ids():
		var card: CardDef = content.get_card(id)
		_check_effects(card.effects, id, content, resolver, errors)
		for level: Variant in card.upgrade_overrides:
			if not card.upgrade_overrides[level] is Dictionary:
				errors.append("%s: 升级覆盖必须是 Dictionary" % id)
				continue
			var override: Dictionary = card.upgrade_overrides[level]
			_check_effects(override.get("effects", []), id, content, resolver, errors)
	for id: StringName in content.relic_ids():
		var relic: RelicDef = content.get_relic(id)
		if not relic.trigger_key in RelicSystem.BATTLE_HOOKS + [&"battle_victory"]:
			errors.append("%s: 未实现的遗物触发键 %s" % [id, relic.trigger_key])
	if campaign != null:
		for act in range(1, campaign.act_count() + 1):
			for suffix: String in ["", "_elite"]:
				var pool_id := StringName("monster_pool.act%d%s" % [act, suffix])
				_require(content.get_monster_pool(pool_id), &"campaign", pool_id, errors)
			var boss := StringName("encounter.boss.act%d" % act)
			_require(content.get_encounter(boss), &"campaign", boss, errors)
	return errors


static func _check_effects(effects: Array, owner: StringName, content: Object, resolver: EffectResolver, errors: Array[String]) -> void:
	for value: Variant in effects:
		if not (value is EffectDef or value is Dictionary):
			errors.append("%s: 效果为空或类型不正确" % owner)
			continue
		var item: Dictionary = value.to_plan_item() if value is EffectDef else value
		var key := StringName(item.get("type_key", ""))
		if not resolver.supports(key):
			errors.append("%s: 未注册效果处理器 %s" % [owner, key])
		var params: Dictionary = item.get("params", {})
		if params.has("status_id"):
			_require(content.get_status(StringName(params["status_id"])), owner, StringName(params["status_id"]), errors)


static func _require(value: Variant, owner: StringName, reference: StringName, errors: Array[String]) -> void:
	if value == null:
		errors.append("%s -> 缺少 %s" % [owner, reference])
