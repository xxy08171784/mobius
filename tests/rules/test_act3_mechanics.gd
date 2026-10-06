extends "res://tests/test_case.gd"
## 第三幕（内墓）新机制测试：腐蚀（防御 -25%）、着火（火焰 DoT 每层 5）、净化、内容注册。

const CONTENT_DB_SCRIPT := preload("res://autoload/content_db.gd")


func run() -> Array[String]:
	reset()
	_test_corrode_reduces_block_gain()
	_test_ignite_fire_dot_decays_stacks()
	_test_cleanse_removes_crypt_debuffs()
	_test_crypt_content()
	return failures()


func _status(instance_id: int, status_id: StringName, stacks: int, duration: int) -> StatusState:
	var s := StatusState.new()
	s.instance_id = instance_id
	s.status_id = status_id
	s.stacks = stacks
	s.duration = duration
	return s


func _defend(id: StringName = &"d.defend") -> EnemyActionDef:
	var a := EnemyActionDef.new()
	a.id = id
	a.kind = EnemyActionDef.Kind.DEFEND
	a.target_policy = EnemyActionDef.TargetPolicy.SELF
	a.block = 3
	return a


func _behavior(actions: Array[EnemyActionDef]) -> SequenceBehaviorDef:
	var b := SequenceBehaviorDef.new()
	b.id = &"behavior.act3"
	b.sequence = actions
	return b


func _lock(state: BattleState, behavior: BehaviorDef) -> void:
	state.enemy_intents[2] = EnemyPlanner.plan(
		state.board, state.get_unit(2), behavior, 0, [state.get_unit(1)]
	)


## 腐蚀：获得护盾 -25%（向下取整）。无腐蚀不变。
func _test_corrode_reduces_block_gain() -> void:
	var streams := Phase3Fixture.rng("corrode")
	var state := Phase3Fixture.base_state(streams, 30, 30, Vector2i(0, 0), Vector2i(1, 0))
	var plain := EffectResolver.new().resolve(
		state,
		{"context": {"source_unit_id": 1}, "effects": [{"type_key": &"block", "target": 1, "params": {"amount": 8}}]},
		streams
	)
	assert_equal((plain["state_out"] as BattleState).get_unit(1).block, 8, "无腐蚀：8 护盾原样")

	state.get_unit(1).set_status(50, _status(50, StatusRules.CORRODE, 2, 2))
	var reduced := EffectResolver.new().resolve(
		state,
		{"context": {"source_unit_id": 1}, "effects": [{"type_key": &"block", "target": 1, "params": {"amount": 8}}]},
		streams
	)
	assert_equal((reduced["state_out"] as BattleState).get_unit(1).block, 6, "腐蚀：8 × 0.75 = 6（向下取整）")


## 着火：回合结束按 层数×5 掉血并减层（吃护盾，不无视护甲）。
func _test_ignite_fire_dot_decays_stacks() -> void:
	var streams := Phase3Fixture.rng("ignite")
	var state := Phase3Fixture.base_state(streams, 40, 40, Vector2i(0, 0), Vector2i(1, 0))
	state.phase = BattleState.Phase.PLAYER_INPUT
	state.get_unit(1).set_status(50, _status(50, StatusRules.IGNITE, 2, 99))
	var defend := _defend()
	var behavior := _behavior([defend])
	_lock(state, behavior)
	var result := TurnSystem.new().run_end_turn(state, streams, {2: behavior}, {defend.id: defend})
	assert_true(bool(result.get("ok", false)), "着火结算应成功")
	var live := state.get_unit(1)
	assert_equal(live.hp, 30, "着火2层：回合结束 2×5 = 10 伤害")
	assert_equal(StatusRules.stacks(live, StatusRules.IGNITE), 1, "着火减层 2→1")


## 净化：腐蚀/着火作为负面状态会被 cleanse 清除。
func _test_cleanse_removes_crypt_debuffs() -> void:
	var streams := Phase3Fixture.rng("crypt-cleanse")
	var state := Phase3Fixture.base_state(streams, 40, 40, Vector2i(0, 0), Vector2i(3, 3))
	state.phase = BattleState.Phase.PLAYER_INPUT
	var enemy := state.get_unit(2)
	enemy.set_status(60, _status(60, StatusRules.CORRODE, 2, 3))
	enemy.set_status(61, _status(61, StatusRules.IGNITE, 1, 3))
	enemy.set_status(62, _status(62, StatusRules.FOCUS, 1, 3))
	var ward := EnemyActionDef.new()
	ward.id = &"ward"
	ward.kind = EnemyActionDef.Kind.DEFEND
	ward.target_policy = EnemyActionDef.TargetPolicy.SELF
	ward.block = 10
	ward.cleanse = true
	var behavior := _behavior([ward])
	_lock(state, behavior)
	TurnSystem.new().run_end_turn(state, streams, {2: behavior}, {ward.id: ward})
	var live := state.get_unit(2)
	assert_equal(live.get_status(60), null, "腐蚀被清除")
	assert_equal(live.get_status(61), null, "着火被清除")
	assert_true(live.get_status(62) != null, "专注保留")


## 内容注册：第三幕池/Boss 可解析，构成符合设计。
func _test_crypt_content() -> void:
	var db := CONTENT_DB_SCRIPT.new()
	assert_true(db.load_catalog("res://content/catalog.tres"), "catalog should load")
	var mob := db.get_monster_pool(&"monster_pool.act3")
	assert_true(mob != null, "act-3 小怪池应存在")
	if mob != null:
		assert_equal(mob.enemy_ids.size(), 4, "第三幕小怪池 4 只")
	var elite := db.get_monster_pool(&"monster_pool.act3_elite")
	assert_true(elite != null, "act-3 精英池应存在")
	if elite != null:
		assert_equal(elite.enemy_ids.size(), 3, "第三幕精英池 3 只")
	var boss := db.get_encounter(&"encounter.boss.act3")
	assert_true(boss != null, "act-3 Boss 遭遇应存在")
	if boss != null:
		assert_equal(boss.enemy_ids[0], &"enemy.crypt.tomb_master", "Boss = 墓主人")
		assert_true(boss.summon_enemy_ids.size() >= 1, "Boss 应有召唤池")
	for status_id: StringName in [&"status.corrode", &"status.ignite"]:
		assert_true(db.get_status(status_id) != null, "第三幕状态 %s 应能解析" % status_id)
