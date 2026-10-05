class_name BattleState
extends RefCounted
## 一场战斗的权威运行状态。不引用场景节点（规则层可脱离 SceneTree 运行）。
## 深拷贝统一走 SaveCodec 往返，禁止另写 clone()。

enum Phase {
	SETUP,
	ROUND_START,
	PLAYER_INPUT,
	RESOLVING,
	PLAYER_END,
	ENEMY_ACT,
	ROUND_END,
	VICTORY,
	DEFEAT,
}

var phase: Phase = Phase.SETUP

## 展示期间 phase=RESOLVING；动画播完后回到这个逻辑阶段。
var resume_phase: Phase = Phase.PLAYER_INPUT

## 战斗稳定 ID；Phase 3 MVP 用 int，未来由 RunState/Encounter 分配。
var battle_id: int = -1
var round_index: int = 0

## 每次成功提交 +1；UI 用它与 CommandResult.state_version 拒绝过期预览。
var version: int = 0

## 全局单调计数器，随存档持久化（combat_rules.md §12.4）。
var next_uid: int = 1
var next_event_seq: int = 1

## 命令锁：结算/表现期间禁止提交（combat_rules.md §3）。
var command_locked: bool = false

## 最近已见命令 ID（有界 FIFO），用于幂等去重。
var seen_command_ids: Array[int] = []

## 最近已接受命令的结果快照。与 seen_command_ids 同步 FIFO，保证重复提交可返回首次结果。
## 值仅保存纯数据（accepted/error/text/events/version），由 BattleSession 还原为 CommandResult。
var command_result_snapshots: Dictionary = {}

## 正式战斗数据。
var board: BoardState = BoardState.new()
var units: Dictionary[int, UnitState] = {}
var deck: DeckState = DeckState.new()

## ROUND_START 锁定，ENEMY_ACT 直接执行同一 IntentState。
var enemy_intents: Dictionary[int, IntentState] = {}
var enemy_steps: Dictionary[int, int] = {}

## CHARGE 跨回合运行状态。充能期间沿用第一次锁定的 Intent，不重新选目标。
var enemy_charge_remaining: Dictionary[int, int] = {}
var enemy_charge_intents: Dictionary[int, IntentState] = {}

## 正式 RNG 的可持久化快照。BattleSession 持有 RngStreams 实例，并在提交后同步到这里。
var rng_snapshot: Dictionary = {}

## Phase 3 原型战斗配置。之后可由 RunState/EncounterDef 注入。
var hand_size: int = 5
var energy_per_round: int = 3
var move_points_per_round: int = 0


func is_terminal() -> bool:
	return phase == Phase.VICTORY or phase == Phase.DEFEAT


func accepts_input() -> bool:
	return phase == Phase.PLAYER_INPUT and not command_locked


func get_unit(unit_id: int) -> UnitState:
	return units.get(unit_id)


func player_ids() -> Array[int]:
	return _ids_for_team(UnitState.Team.PLAYER)


func enemy_ids() -> Array[int]:
	return _ids_for_team(UnitState.Team.ENEMY)


func alive_player_ids() -> Array[int]:
	return _alive_ids_for_team(UnitState.Team.PLAYER)


func alive_enemy_ids() -> Array[int]:
	return _alive_ids_for_team(UnitState.Team.ENEMY)


func _ids_for_team(team: UnitState.Team) -> Array[int]:
	var ids: Array[int] = []
	for unit_id: int in units:
		var unit: UnitState = units[unit_id]
		if unit.team == team:
			ids.append(unit_id)
	ids.sort()
	return ids


func _alive_ids_for_team(team: UnitState.Team) -> Array[int]:
	var ids: Array[int] = []
	for unit_id: int in units:
		var unit: UnitState = units[unit_id]
		if unit.team == team and unit.is_alive():
			ids.append(unit_id)
	ids.sort()
	return ids
