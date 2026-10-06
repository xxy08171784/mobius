extends "res://tests/test_case.gd"
## 反应系统 v1 测试：反伤、自爆 AoE、亡灵意志、食尸鬼体质、限深、治疗钳制、内容注册。

const CONTENT_DB_SCRIPT := preload("res://autoload/content_db.gd")


func run() -> Array[String]:
	reset()
	_test_thorns_reflects_to_attacker()
	_test_self_destruct_aoes_around_death()
	_test_undead_will_buffs_allies_on_death()
	_test_ghoul_constitution_on_any_death()
	_test_reaction_depth_limit()
	_test_heal_clamps_to_max()
	_test_content_reactions()
	return failures()


func _thorns(amount: int) -> ReactionDef:
	var r := ReactionDef.new()
	r.event_type = &"on_damaged"
	r.kind = ReactionDef.Kind.DAMAGE_ATTACKER
	r.amount = amount
	return r


func _boom() -> ReactionDef:
	var r := ReactionDef.new()
	r.event_type = &"on_death"
	r.kind = ReactionDef.Kind.AOE_AROUND_SELF
	r.amount = 6
	r.radius = 1
	return r


func _undead_will() -> ReactionDef:
	var r := ReactionDef.new()
	r.event_type = &"on_death"
	r.kind = ReactionDef.Kind.BUFF_ALLIES
	r.status_id = &"status.rage"
	r.stacks = 1
	r.duration = 1
	return r


func _ghoul_heal() -> ReactionDef:
	var r := ReactionDef.new()
	r.event_type = &"on_any_death"
	r.kind = ReactionDef.Kind.HEAL_SELF
	r.amount = 7
	return r


func _ghoul_rage() -> ReactionDef:
	var r := ReactionDef.new()
	r.event_type = &"on_any_death"
	r.kind = ReactionDef.Kind.BUFF_SELF
	r.status_id = &"status.rage"
	r.stacks = 1
	r.duration = 1
	return r


## 反伤：敌人受击 -> 对攻击者造成 amount。
func _test_thorns_reflects_to_attacker() -> void:
	var streams := Phase3Fixture.rng("thorns")
	var state := Phase3Fixture.base_state(streams, 30, 20, Vector2i(0, 0), Vector2i(1, 0))
	var resolved := EffectResolver.new().resolve(
		state,
		{"context": {"source_unit_id": 1}, "effects": [{"type_key": &"damage", "target": 2, "params": {"amount": 5}}]},
		streams,
		{2: [_thorns(3)]}
	)
	assert_true(bool(resolved.get("ok", false)), "反伤结算成功")
	var out := resolved["state_out"] as BattleState
	assert_equal(out.get_unit(2).hp, 15, "敌人吃 5 伤害")
	assert_equal(out.get_unit(1).hp, 27, "反伤 3：玩家掉 3")


## 自爆：敌人死亡 -> 以死亡格为中心的 3×3 内敌对单位吃 6。
func _test_self_destruct_aoes_around_death() -> void:
	var streams := Phase3Fixture.rng("boom")
	var state := Phase3Fixture.base_state(streams, 40, 6, Vector2i(1, 2), Vector2i(1, 1))
	var resolved := EffectResolver.new().resolve(
		state,
		{"context": {"source_unit_id": 1}, "effects": [{"type_key": &"damage", "target": 2, "params": {"amount": 20}}]},
		streams,
		{2: [_boom()]}
	)
	assert_true(bool(resolved.get("ok", false)), "自爆结算成功")
	var out := resolved["state_out"] as BattleState
	assert_equal(out.get_unit(2).hp, 0, "敌人被击杀")
	assert_equal(out.get_unit(1).hp, 34, "3×3 内玩家吃 6（即便敌人已离场，用死亡格定位）")


## 亡灵意志：地狱骷髅死亡 -> 同阵营存活单位获得怒火。
func _test_undead_will_buffs_allies_on_death() -> void:
	var streams := Phase3Fixture.rng("undead")
	var state := Phase3Fixture.base_state(streams, 40, 6, Vector2i(0, 0), Vector2i(1, 0))
	var boss := UnitState.create(3, &"unit.enemy.boss", UnitState.Team.ENEMY, 50)
	state.units[3] = boss
	state.board.place_unit(3, Vector2i(3, 3))
	var resolved := EffectResolver.new().resolve(
		state,
		{"context": {"source_unit_id": 1}, "effects": [{"type_key": &"damage", "target": 2, "params": {"amount": 20}}]},
		streams,
		{2: [_undead_will()]}
	)
	assert_true(bool(resolved.get("ok", false)), "亡灵意志结算成功")
	var live_boss := (resolved["state_out"] as BattleState).get_unit(3)
	assert_true(
		StatusRules.stacks(live_boss, StatusRules.RAGE) >= 1,
		"同阵营存活单位获得怒火（死亡的骷髅被过滤）"
	)


## 食尸鬼体质：任意单位死亡 -> 食尸鬼自愈 +7 且获得怒火。
func _test_ghoul_constitution_on_any_death() -> void:
	var streams := Phase3Fixture.rng("ghoul")
	var state := Phase3Fixture.base_state(streams, 40, 20, Vector2i(0, 0), Vector2i(1, 1))
	state.get_unit(2).hp = 13
	var other := UnitState.create(3, &"unit.enemy.other", UnitState.Team.ENEMY, 5)
	state.units[3] = other
	state.board.place_unit(3, Vector2i(3, 3))
	var resolved := EffectResolver.new().resolve(
		state,
		{"context": {"source_unit_id": 1}, "effects": [{"type_key": &"damage", "target": 3, "params": {"amount": 20}}]},
		streams,
		{2: [_ghoul_heal(), _ghoul_rage()]}
	)
	assert_true(bool(resolved.get("ok", false)), "食尸鬼体质结算成功")
	var live_ghoul := (resolved["state_out"] as BattleState).get_unit(2)
	assert_equal(live_ghoul.hp, 20, "任意单位死亡：自愈 +7（钳制到 max）")
	assert_true(StatusRules.stacks(live_ghoul, StatusRules.RAGE) >= 1, "食尸鬼获得怒火")


## 限深：双方都带反伤互打不会死循环（反应产出的触发不再展开反应）。
func _test_reaction_depth_limit() -> void:
	var streams := Phase3Fixture.rng("thorns-loop")
	var state := Phase3Fixture.base_state(streams, 30, 20, Vector2i(0, 0), Vector2i(1, 0))
	var resolved := EffectResolver.new().resolve(
		state,
		{"context": {"source_unit_id": 1}, "effects": [{"type_key": &"damage", "target": 2, "params": {"amount": 5}}]},
		streams,
		{1: [_thorns(2)], 2: [_thorns(3)]}
	)
	assert_true(bool(resolved.get("ok", false)), "双反伤不应触发死循环（结算成功）")
	var out := resolved["state_out"] as BattleState
	assert_equal(out.get_unit(1).hp, 27, "玩家只吃一次反伤 3（限深一层）")
	assert_equal(out.get_unit(2).hp, 15, "敌人吃 5")


## 治疗钳制：不超 max_hp。
func _test_heal_clamps_to_max() -> void:
	var streams := Phase3Fixture.rng("heal")
	var state := Phase3Fixture.base_state(streams, 10, 20, Vector2i(0, 0), Vector2i(1, 0))
	state.get_unit(1).hp = 8
	var resolved := EffectResolver.new().resolve(
		state,
		{"context": {"source_unit_id": 1}, "effects": [{"type_key": &"heal", "target": 1, "params": {"amount": 5}}]},
		streams
	)
	assert_equal((resolved["state_out"] as BattleState).get_unit(1).hp, 10, "治疗不超 max_hp")


## 内容：4 只怪已注册反应。
func _test_content_reactions() -> void:
	var db := CONTENT_DB_SCRIPT.new()
	assert_true(db.load_catalog("res://content/catalog.tres"), "catalog should load")
	for id: StringName in [
		&"enemy.catacomb.will_o_wisp",
		&"enemy.catacomb.stone_figure",
		&"enemy.crypt.hell_skeleton",
		&"enemy.crypt.ghoul",
	]:
		var enemy: EnemyDef = db.get_enemy(id)
		assert_true(enemy != null and enemy.reactions.size() > 0, "%s 应注册反应" % id)
