extends SceneTree
## 从运行时资源导出实际数值，供审阅及对照调参表。
func _initialize() -> void:
	var catalog := load("res://content/catalog.tres") as ContentCatalog
	var cards: Array = []
	var enemies: Array = []
	var unit_index: Dictionary = {}
	for unit: UnitDef in catalog.units:
		unit_index[unit.id] = unit
	for card: CardDef in catalog.cards:
		var row := {"id": card.card_id, "name": card.display_name, "path": card.resource_path, "reward": card.reward_pool_enabled, "number": card.card_number, "levels": []}
		for level in range(2):
			var effects: Array = []
			for effect: EffectDef in card.get_effects(level):
				effects.append(effect.to_plan_item())
			row.levels.append({"name": card.get_display_name(level), "cost": card.get_cost(level), "description": card.get_description(level), "effects": effects, "rules": card.rule_values.merged(card._upgrade_data(level).get("rule_values", {}), true)})
		cards.append(row)
	for enemy: EnemyDef in catalog.enemies:
		var actions: Array = []
		if enemy.behavior is SequenceBehaviorDef:
			for action: EnemyActionDef in enemy.behavior.sequence:
				actions.append({"id": action.id, "kind": action.kind, "damage": action.damage, "damage_min": action.damage_min, "damage_max": action.damage_max, "block": action.block, "block_min": action.block_min, "block_max": action.block_max, "hits": action.hit_count, "advance": action.advance_steps, "move": action.move_steps, "per_step": action.dash_damage_per_step, "range": action.range, "shape": action.range_shape, "status": action.apply_status_id, "stacks": action.apply_status_stacks, "duration": action.apply_status_duration})
		enemies.append({"id": enemy.id, "name": enemy.display_name, "hp": (unit_index[enemy.unit_def_id] as UnitDef).base_stat(StatSystem.STAT_MAX_HP), "path": enemy.resource_path, "actions": actions})
	var file := FileAccess.open("res://.validation/balance_catalog.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"cards": cards, "enemies": enemies}, "\t"))
	file.close()
	print("BALANCE_CATALOG_OK cards=", cards.size(), " enemies=", enemies.size())
	quit()
