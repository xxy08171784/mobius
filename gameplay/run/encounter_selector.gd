class_name EncounterSelector
extends RefCounted
## 按幕选择普通池、精英池和 Boss。正式 Campaign 缺内容明确报错，不隐式回退旧演示敌人。
var _content: Object


func setup(content: Object) -> void:
	_content = content


func resolve(work: RunState, rng: RngStreams, kind: StringName, player_start: Vector2i) -> Dictionary:
	var result: Dictionary
	match kind:
		RouteMapDef.TYPE_MONSTER:
			result = _resolve_monster_pool(work, rng, player_start)
		RouteMapDef.TYPE_ELITE:
			result = _resolve_elite_encounter(work, rng, player_start)
		_:
			result = _resolve_boss_encounter(work, rng, player_start)
	return _fail(&"act_content_missing") if result.is_empty() else result


func _resolve_monster_pool(work: RunState, rng: RngStreams, player_start: Vector2i) -> Dictionary:
	if _content == null or not _content.has_method("get_monster_pool"):
		return {}
	var pool: MonsterPoolDef = _content.get_monster_pool(StringName("monster_pool.act%d" % (work.act_index + 1)))
	if pool == null:
		return {}
	var encounter := MonsterPool.build_encounter(pool, work.next_battle_id, rng.get_stream(&"encounter"))
	if encounter == null:
		return _fail(&"monster_pool_empty")
	var battle := EncounterBuilder.build(encounter, work, rng, _content, player_start)
	if battle.is_empty():
		return _fail(&"encounter_build")
	return {
		"ok": true,
		"error_code": &"ok",
		"kind": &"battle",
		"content_id": encounter.id,
		"encounter_id": encounter.id,
		"battle": battle,
	}


## 本幕精英战：1 精英（精英池随机）+ 2 小怪（小怪池有放回）。缺少资源时向上返回明确错误。
func _resolve_elite_encounter(work: RunState, rng: RngStreams, player_start: Vector2i) -> Dictionary:
	if _content == null or not _content.has_method("get_monster_pool"):
		return {}
	var act := work.act_index + 1
	var elite_pool: MonsterPoolDef = _content.get_monster_pool(StringName("monster_pool.act%d_elite" % act))
	var mob_pool: MonsterPoolDef = _content.get_monster_pool(StringName("monster_pool.act%d" % act))
	if elite_pool == null or mob_pool == null:
		return {}
	var encounter := MonsterPool.build_elite_encounter(
		elite_pool, mob_pool, work.next_battle_id, rng.get_stream(&"encounter")
	)
	if encounter == null:
		return _fail(&"monster_pool_empty")
	return _battle_transition(encounter, work, rng, player_start)


## 本幕 Boss：按 act 编号取得对应 Boss 遭遇。
func _resolve_boss_encounter(work: RunState, rng: RngStreams, player_start: Vector2i) -> Dictionary:
	if _content == null or not _content.has_method("get_encounter"):
		return {}
	var encounter: EncounterDef = _content.get_encounter(StringName("encounter.boss.act%d" % (work.act_index + 1)))
	if encounter == null:
		return {}
	return _battle_transition(encounter, work, rng, player_start)


## 装配一场战斗的转移 dict（供池/精英/Boss 共用）。
func _battle_transition(encounter: EncounterDef, work: RunState, rng: RngStreams, player_start: Vector2i) -> Dictionary:
	var battle := EncounterBuilder.build(encounter, work, rng, _content, player_start)
	if battle.is_empty():
		return _fail(&"encounter_build")
	return {
		"ok": true,
		"error_code": &"ok",
		"kind": &"battle",
		"content_id": encounter.id,
		"encounter_id": encounter.id,
		"battle": battle,
	}


static func _fail(code: StringName) -> Dictionary:
	return {"ok": false, "error_code": code}
