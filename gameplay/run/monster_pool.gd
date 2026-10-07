class_name MonsterPool
extends RefCounted
## 怪物池抽取（纯函数，确定性）。规则（设计 `游戏机制.md`）：
##   普通战斗：前 2 个战斗节点固定 2 只，其后随机 2~3 只；**有放回**（允许同种重复）。
##   精英战斗：1 精英（精英池随机）+ 1 小怪（小怪池有放回）。
## battle_index = RunState.next_battle_id（1 起、每进一个战斗节点 +1、已随存档持久化）。
## 随机取自调用方传入的 RandomNumberGenerator（encounter 流），本类不用全局随机。

const EARLY_BATTLES := 2   # 前 N 个战斗节点
const EARLY_COUNT := 2     # 前 N 个战斗节点的固定数量
const MIN_COUNT := 2       # 随机下限
const MAX_COUNT := 3       # 随机上限
const ELITE_MOB_COUNT := 1 # 精英战附带的小怪数量


## 抽取数量：battle_index <= EARLY_BATTLES -> 2；否则 [MIN_COUNT, MAX_COUNT]。
static func draw_count(battle_index: int, rng: RandomNumberGenerator) -> int:
	if battle_index <= EARLY_BATTLES:
		return EARLY_COUNT
	return rng.randi_range(MIN_COUNT, MAX_COUNT)


## 从池中有放回均匀抽 count 个 ID（确定性来自传入 rng）。空池/rng 为空/非正数返回空。
static func draw_n(pool: MonsterPoolDef, count: int, rng: RandomNumberGenerator) -> Array[StringName]:
	var out: Array[StringName] = []
	if pool == null or rng == null or pool.enemy_ids.is_empty():
		return out
	for _i in maxi(0, count):
		out.append(pool.enemy_ids[rng.randi_range(0, pool.enemy_ids.size() - 1)])
	return out


## 按 battle_index 规则抽 ID。
static func draw_ids(pool: MonsterPoolDef, battle_index: int, rng: RandomNumberGenerator) -> Array[StringName]:
	if pool == null or rng == null or pool.enemy_ids.is_empty():
		return []
	return draw_n(pool, draw_count(battle_index, rng), rng)


## 精英战组成：1 精英（精英池随机）+ 1 小怪（小怪池有放回）。
static func draw_elite_composition(
	elite_pool: MonsterPoolDef,
	mob_pool: MonsterPoolDef,
	rng: RandomNumberGenerator
) -> Array[StringName]:
	var out: Array[StringName] = []
	if elite_pool == null or mob_pool == null or rng == null:
		return out
	if elite_pool.enemy_ids.is_empty():
		return out
	out.append(elite_pool.enemy_ids[rng.randi_range(0, elite_pool.enemy_ids.size() - 1)])
	out.append_array(draw_n(mob_pool, ELITE_MOB_COUNT, rng))
	return out


## 合成一个临时 EncounterDef（抽到的 ids + 池的棋盘模板），供 EncounterBuilder.build 复用。
## 池非法/空池返回 null。
static func build_encounter(pool: MonsterPoolDef, battle_index: int, rng: RandomNumberGenerator) -> EncounterDef:
	if pool == null or not pool.is_valid():
		return null
	var ids := draw_ids(pool, battle_index, rng)
	if ids.is_empty():
		return null
	return _compose(StringName("%s.draw%d" % [String(pool.id), battle_index]), ids, pool, pool.tier)


## 合成精英遭遇：1 精英 + 1 小怪（棋盘模板取小怪池）。
static func build_elite_encounter(
	elite_pool: MonsterPoolDef,
	mob_pool: MonsterPoolDef,
	battle_index: int,
	rng: RandomNumberGenerator
) -> EncounterDef:
	if elite_pool == null or mob_pool == null:
		return null
	var ids := draw_elite_composition(elite_pool, mob_pool, rng)
	if ids.is_empty():
		return null
	return _compose(
		StringName("%s.draw%d" % [String(elite_pool.id), battle_index]),
		ids,
		mob_pool,
		&"elite"
	)


## 用模板池的棋盘/回合参数装配 EncounterDef。
static func _compose(id: StringName, ids: Array[StringName], template: MonsterPoolDef, tier: StringName) -> EncounterDef:
	var encounter := EncounterDef.new()
	encounter.id = id
	encounter.enemy_ids = ids
	encounter.board_cols = template.board_cols
	encounter.board_rows = template.board_rows
	encounter.player_start = template.player_start
	encounter.hand_size = template.hand_size
	encounter.energy_per_round = template.energy_per_round
	encounter.move_points_per_round = template.move_points_per_round
	encounter.tier = tier
	return encounter
