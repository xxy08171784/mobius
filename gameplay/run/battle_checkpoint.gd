class_name BattleCheckpoint
extends RefCounted
## 仅保存值与稳定内容 ID。读档不重新生成遭遇、不抽 RNG、不重放开场效果。


static func capture(data: Dictionary) -> Dictionary:
	var summon_ids: Array = []
	for spec: Dictionary in data.get("summon_pool", []):
		summon_ids.append(spec["enemy_id"])
	return {"battle": SaveCodec.new().encode_state(data["state"]), "summon_ids": summon_ids}


static func restore(payload: Dictionary, content: Object) -> Dictionary:
	var state := SaveCodec.new().decode_state(payload.get("battle", {})) as BattleState
	if state == null:
		return {}
	if state.phase == BattleState.Phase.RESOLVING:
		state.phase = state.resume_phase
		state.command_locked = false
	var behaviors: Dictionary = {}
	var actions: Dictionary = {}
	for id: int in state.enemy_ids():
		var enemy: EnemyDef = content.get_enemy(state.get_unit(id).enemy_id)
		if enemy == null:
			return {}
		behaviors[id] = enemy.behavior
		EncounterBuilder._collect_actions(actions, enemy.behavior)
	var encounter := EncounterDef.new()
	for id: Variant in payload.get("summon_ids", []):
		encounter.summon_enemy_ids.append(StringName(String(id)))
	var rng := RngStreams.new()
	rng.restore(state.rng_snapshot)
	var cards: Dictionary = content.all_cards()
	return {
		"state": state, "rng": rng, "card_defs": cards,
		"enemy_behaviors": behaviors, "enemy_actions": actions,
		"summon_pool": EncounterBuilder._build_summon_pool(encounter, content),
		"card_labels": EncounterBuilder._card_labels(cards),
	}
