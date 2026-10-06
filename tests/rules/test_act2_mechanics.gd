extends "res://tests/test_case.gd"
## 第二幕（墓道）新机制测试：虚弱、减速/缠绕、随机数值区间、拖拽、贯穿、净化，以及内容注册。

const CONTENT_DB_SCRIPT := preload("res://autoload/content_db.gd")


func run() -> Array[String]:
	reset()
	_test_weak_reduces_outgoing_damage()
	_test_slow_and_entangle_move_budget()
	_test_pull_drags_player_toward_caster()
	_test_pierce_hits_cell_behind_target()
	_test_damage_variance_within_range()
	_test_cleanse_removes_negative_keeps_positive()
	_test_catacomb_content()
	return failures()


func _status(instance_id: int, status_id: StringName, stacks: int, duration: int) -> StatusState:
	var s := StatusState.new()
	s.instance_id = instance_id
	s.status_id = status_id
	s.stacks = stacks
	s.duration = duration
	return s


func _action(id: StringName, kind: EnemyActionDef.Kind, damage: int = 0) -> EnemyActionDef:
	var a := EnemyActionDef.new()
	a.id = id
	a.kind = kind
	a.target_policy = EnemyActionDef.TargetPolicy.PLAYER
	a.damage = damage
	a.range = 1
	a.range_shape = BoardQuery.RangeShape.DIAMOND
	return a


func _behavior(actions: Array[EnemyActionDef]) -> SequenceBehaviorDef:
	var b := SequenceBehaviorDef.new()
	b.id = &"behavior.act2"
	b.sequence = actions
	return b


func _lock(state: BattleState, behavior: BehaviorDef) -> void:
	state.enemy_intents[2] = EnemyPlanner.plan(
		state.board, state.get_unit(2), behavior, 0, [state.get_unit(1)]
	)


## 虚弱：拥有者造成普通伤害 -25%（向下取整）。无虚弱不变。
func _test_weak_reduces_outgoing_damage() -> void:
	var streams := Phase3Fixture.rng("weak")
	var state := Phase3Fixture.base_state(streams, 30, 30, Vector2i(0, 0), Vector2i(1, 0))
	var resolved := EffectResolver.new().resolve(
		state,
		{"context": {"source_unit_id": 1}, "effects": [{"type_key": &"damage", "target": 2, "params": {"amount": 20}}]},
		streams
	)
	var out := resolved["state_out"] as BattleState
	assert_equal(out.get_unit(2).hp, 10, "无虚弱：20 点原样命中")

	state.get_unit(1).set_status(30, _status(30, StatusRules.WEAK, 1, 2))
	var weakened := EffectResolver.new().resolve(
		state,
		{"context": {"source_unit_id": 1}, "effects": [{"type_key": &"damage", "target": 2, "params": {"amount": 20}}]},
		streams
	)
	var out2 := weakened["state_out"] as BattleState
	assert_equal(out2.get_unit(2).hp, 15, "虚弱：20 × 0.75 = 15（向下取整）")


## 减速每层 -1 移动力；缠绕直接锁死（开局在 TurnSystem.begin_round 结算）。
func _test_slow_and_entangle_move_budget() -> void:
	var slow1 := _begin_round_move(StatusRules.SLOW, 1, 2)
	assert_equal(slow1, 1, "减速1层：移动 2-1 = 1")
	var slow2 := _begin_round_move(StatusRules.SLOW, 2, 2)
	assert_equal(slow2, 0, "减速2层：移动 2-2 = 0")
	var locked := _begin_round_move(StatusRules.ENTANGLE, 1, 3)
	assert_equal(locked, 0, "缠绕：移动力锁死为 0（即便基础 3）")


func _begin_round_move(status_id: StringName, stacks: int, base_move: int) -> int:
	var streams := Phase3Fixture.rng("move-%s-%d" % [status_id, stacks])
	var state := Phase3Fixture.base_state(streams, 30, 30, Vector2i(0, 0), Vector2i(1, 0), null, 0, 3, base_move)
	state.phase = BattleState.Phase.ROUND_END
	state.get_unit(1).set_status(31, _status(31, status_id, stacks, 2))
	TurnSystem.new().begin_round(state, streams, {})
	return state.get_unit(1).get_resource(TurnSystem.MOVE_RESOURCE)


## 拖拽（勾魂）：把玩家朝施法者拉近，伤害 = 每步 × 步数。
func _test_pull_drags_player_toward_caster() -> void:
	var streams := Phase3Fixture.rng("pull")
	# 玩家 (0,0)，敌人 (0,5)：拉近 2 格 -> (0,2)。
	var state := Phase3Fixture.base_state(streams, 40, 40, Vector2i(0, 0), Vector2i(0, 5))
	state.phase = BattleState.Phase.PLAYER_INPUT
	var hook := _action(&"hook", EnemyActionDef.Kind.PULL, 0)
	hook.range_shape = BoardQuery.RangeShape.UNLIMITED
	hook.move_steps = 2
	hook.dash_damage_per_step = 3
	var behavior := _behavior([hook])
	_lock(state, behavior)
	var result := TurnSystem.new().run_end_turn(state, streams, {2: behavior}, {hook.id: hook})
	assert_true(bool(result.get("ok", false)), "勾魂应结算成功")
	assert_equal(state.board.get_unit_cell(1), Vector2i(0, 2), "玩家被拉近 2 格")
	assert_equal(state.get_unit(1).hp, 34, "伤害 = 0 + 2 步 × 3 = 6")


## 贯穿（阴兵过境）：主目标身后一格的玩家阵营单位吃同额伤害。
func _test_pierce_hits_cell_behind_target() -> void:
	var streams := Phase3Fixture.rng("pierce")
	# 玩家1 (0,3)，敌人 (0,4)，援军玩家3 (0,2) 在玩家1"身后"。
	var state := Phase3Fixture.base_state(streams, 40, 40, Vector2i(0, 3), Vector2i(0, 4))
	var ally := UnitState.create(3, &"unit.player.2", UnitState.Team.PLAYER, 30)
	state.units[3] = ally
	state.board.place_unit(3, Vector2i(0, 2))
	state.phase = BattleState.Phase.PLAYER_INPUT
	var march := _action(&"march", EnemyActionDef.Kind.ATTACK, 10)
	march.pierce = true
	var behavior := _behavior([march])
	_lock(state, behavior)
	var result := TurnSystem.new().run_end_turn(state, streams, {2: behavior}, {march.id: march})
	assert_true(bool(result.get("ok", false)), "贯穿应结算成功")
	assert_equal(state.get_unit(1).hp, 30, "主目标受 10 伤害")
	assert_equal(state.get_unit(3).hp, 20, "身后一格玩家阵营单位也受 10 伤害")


## 随机数值区间：多次掷值都落在 [min,max]，且不止一个取值。
func _test_damage_variance_within_range() -> void:
	var low := 1 << 30
	var high := -1
	for i in range(40):
		var streams := Phase3Fixture.rng("variance-%d" % i)
		var state := Phase3Fixture.base_state(streams, 100, 40, Vector2i(0, 0), Vector2i(1, 0))
		state.phase = BattleState.Phase.PLAYER_INPUT
		var bite := _action(&"bite", EnemyActionDef.Kind.ATTACK, 0)
		bite.damage_min = 6
		bite.damage_max = 8
		var behavior := _behavior([bite])
		_lock(state, behavior)
		TurnSystem.new().run_end_turn(state, streams, {2: behavior}, {bite.id: bite})
		var dealt := 100 - state.get_unit(1).hp
		low = mini(low, dealt)
		high = maxi(high, dealt)
	assert_true(low >= 6 and high <= 8, "随机伤害应落在 [6,8] 内（实测 %d..%d）" % [low, high])
	assert_true(low < high, "多次掷值应有变化（非固定值）")


## 净化（阴气护体）：移除负面、保留正面，并给护盾。
func _test_cleanse_removes_negative_keeps_positive() -> void:
	var streams := Phase3Fixture.rng("cleanse")
	var state := Phase3Fixture.base_state(streams, 30, 30, Vector2i(0, 0), Vector2i(3, 3))
	state.phase = BattleState.Phase.PLAYER_INPUT
	var enemy := state.get_unit(2)
	enemy.set_status(40, _status(40, StatusRules.POISON, 3, 3))
	enemy.set_status(41, _status(41, StatusRules.SLOW, 1, 3))
	enemy.set_status(42, _status(42, StatusRules.FOCUS, 2, 3))
	var ward := _action(&"ward", EnemyActionDef.Kind.DEFEND)
	ward.target_policy = EnemyActionDef.TargetPolicy.SELF
	ward.block = 12
	ward.cleanse = true
	var behavior := _behavior([ward])
	_lock(state, behavior)
	var result := TurnSystem.new().run_end_turn(state, streams, {2: behavior}, {ward.id: ward})
	assert_true(bool(result.get("ok", false)), "阴气护体应结算成功")
	# 结算后 state.units 被克隆替换，须重新取单位引用。
	var live := state.get_unit(2)
	assert_equal(live.get_status(40), null, "中毒（负面）被清除")
	assert_equal(live.get_status(41), null, "减速（负面）被清除")
	assert_true(live.get_status(42) != null, "专注（正面）保留")
	assert_equal(live.hp, 30, "净化后不再吃中毒 DoT")
	assert_equal(live.block, 12, "同时获得 12 护盾")


## 内容注册：第二幕池/Boss 可解析，构成符合设计。
func _test_catacomb_content() -> void:
	var db := CONTENT_DB_SCRIPT.new()
	assert_true(db.load_catalog("res://content/catalog.tres"), "catalog should load")
	var mob := db.get_monster_pool(&"monster_pool.act2")
	assert_true(mob != null, "act-2 小怪池应存在")
	if mob != null:
		assert_equal(mob.enemy_ids.size(), 4, "第二幕小怪池 4 只")
		for id: StringName in mob.enemy_ids:
			assert_true(db.get_enemy(id) != null, "池成员 %s 应能解析" % id)
	var elite := db.get_monster_pool(&"monster_pool.act2_elite")
	assert_true(elite != null, "act-2 精英池应存在")
	if elite != null:
		assert_equal(elite.enemy_ids.size(), 3, "第二幕精英池 3 只")
	var boss := db.get_encounter(&"encounter.boss.act2")
	assert_true(boss != null, "act-2 Boss 遭遇应存在")
	if boss != null:
		assert_equal(boss.enemy_ids[0], &"enemy.catacomb.ghost_soldier", "Boss = 阴兵")
		assert_true(boss.summon_enemy_ids.size() >= 1, "Boss 应有召唤池")
