class_name RelicSystem
extends RefCounted
## 遗物钩子数据化：Def 只读，战斗计数存 BattleState，局内计数存 RelicState。
const BATTLE_HOOKS := [&"battle_start", &"round_start", &"card_played", &"damage_taken"]


static func equip(battle: BattleState, run: RunState, content: Object) -> void:
	for relic: RelicState in run.relics:
		var definition: RelicDef = content.get_relic(relic.relic_id)
		if definition == null or not BATTLE_HOOKS.has(definition.trigger_key):
			continue
		battle.relic_hooks.append({
			"id": relic.relic_id, "instance_id": relic.instance_id,
			"hook": definition.trigger_key, "params": definition.trigger_params.duplicate(true),
			"priority": definition.priority, "count": 0,
		})
	battle.relic_hooks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["priority"]) < int(b["priority"]) if a["priority"] != b["priority"] else int(a["instance_id"]) < int(b["instance_id"])
	)


static func trigger(battle: BattleState, hook: StringName) -> void:
	for entry: Dictionary in battle.relic_hooks:
		if StringName(entry["hook"]) != hook:
			continue
		var params: Dictionary = entry["params"]
		var limit := int(params.get("max_triggers_per_battle", 0))
		if limit > 0 and int(entry["count"]) >= limit:
			continue
		for id: int in battle.alive_player_ids():
			var player := battle.get_unit(id)
			player.block += maxi(0, int(params.get("block", 0)))
			player.hp = mini(player.max_hp, player.hp + maxi(0, int(params.get("heal", 0))))
			for resource: StringName in [&"energy", &"move_points"]:
				player.set_resource(resource, player.get_resource(resource) + int(params.get(String(resource), 0)))
		entry["count"] = int(entry["count"]) + 1


static func on_victory(run: RunState, content: Object) -> void:
	for relic: RelicState in run.relics:
		var definition: RelicDef = content.get_relic(relic.relic_id)
		if definition == null or definition.trigger_key != &"battle_victory":
			continue
		run.gold += maxi(0, int(definition.trigger_params.get("reward_bonus", 0)))
		run.hp = mini(run.max_hp, run.hp + maxi(0, int(definition.trigger_params.get("heal", 0))))
		relic.add_counter(&"victories")
