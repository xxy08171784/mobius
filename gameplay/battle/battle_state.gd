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

## 每次成功提交 +1；UI 用它与 CommandResult.state_version 拒绝过期预览。
var version: int = 0

## 全局单调计数器，随存档持久化（combat_rules.md §12.4）。
var next_uid: int = 1
var next_event_seq: int = 1

## 命令锁：结算/表现期间禁止提交（combat_rules.md §3）。
var command_locked: bool = false

## 最近已见命令 ID（有界 FIFO），用于幂等去重。
var seen_command_ids: Array[int] = []


func is_terminal() -> bool:
	return phase == Phase.VICTORY or phase == Phase.DEFEAT


func accepts_input() -> bool:
	return phase == Phase.PLAYER_INPUT and not command_locked
