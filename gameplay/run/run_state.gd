class_name RunState
extends RefCounted
## 一局完整游玩的权威状态（跨场景）。规则层，不引用场景节点。
## 战斗进/出只经 EncounterBuilder / BattleResult；本类本身不做战斗结算。
##
## 持久 HP 是 run <-> battle 唯一的桥：BattleResult.persistent_changes["player_hp"] 写回本类。
## next_card_uid / next_relic_uid / next_battle_id 必须随存档持久化（combat_rules.md §12.4：
## 单调计数器不存会导致读档后 UID/顺序改变、确定性破坏）。
## RNG 只存快照（与 BattleState.rng_snapshot 同构），活的 RngStreams 由 RunSession 持有。

## 本局稳定 ID，用于结算防重复发放（同一 run 只发一次永久奖励）。
var run_id: int = -1

## run seed（十进制字符串，沿用 RngStreams 约定）。
var seed: String = ""

## 角色稳定 ID（CharacterDef.id）。
var character_id: StringName = &""

## 当前章号（0 起）与当前章地图。
var act_index: int = 0
var map: RouteGraph = null

## 当前所在节点；-1 = 尚未进入任何节点（地图初始态）。
var current_node_id: int = -1

## 跨战斗持久 HP。
var hp: int = 1
var max_hp: int = 1

## 局内货币（商店等使用）。
var gold: int = 0

## 永久卡组与遗物（局内状态实例，不是 Def）。
var deck: Array[RunCardState] = []
var relics: Array[RelicState] = []

## 单调计数器（必须持久化）。
var next_card_uid: int = 1
var next_relic_uid: int = 1
var next_battle_id: int = 1

## 正式 RNG 的可持久化快照。
var rng_snapshot: Dictionary = {}

## 磁盘恢复的流程真相；visited 表示已经进入，pending 表示尚未完成。
var flow_phase: StringName = &"route"
var pending_node_id: int = -1
var pending_content_id: StringName = &""
var pending_battle_id: int = -1
var pending_payload: Dictionary = {}
var settled_battle_ids: Array[int] = []
var outcome: StringName = &""
## App 分配的局实例键；相同种子的多次游戏仍是不同的历史记录。
var instance_id: String = ""
var difficulty: int = 0


func is_active() -> bool:
	return is_alive() and flow_phase != &"run_over"


func clear_pending() -> void:
	flow_phase = &"route"
	pending_node_id = -1
	pending_content_id = &""
	pending_battle_id = -1
	pending_payload = {}


func is_alive() -> bool:
	return hp > 0


func get_card(run_uid: int) -> RunCardState:
	for card: RunCardState in deck:
		if card.run_uid == run_uid:
			return card
	return null


func get_relic(instance_id: int) -> RelicState:
	for relic: RelicState in relics:
		if relic.instance_id == instance_id:
			return relic
	return null


func has_relic(relic_id: StringName) -> bool:
	for relic: RelicState in relics:
		if relic.relic_id == relic_id:
			return true
	return false


## 分配并推进战斗 ID。
func allocate_battle_id() -> int:
	var id := next_battle_id
	next_battle_id += 1
	return id


## 新建一张永久卡（不加入卡组；调用方决定放置位置）。
func make_card(card_id: StringName, upgrade_level: int = 0) -> RunCardState:
	var card := RunCardState.new()
	card.run_uid = next_card_uid
	next_card_uid += 1
	card.card_id = card_id
	card.upgrade_level = upgrade_level
	return card


## 新建并加入卡组。
func add_card(card_id: StringName, upgrade_level: int = 0) -> RunCardState:
	var card := make_card(card_id, upgrade_level)
	deck.append(card)
	return card


## 新建并加入遗物。
func add_relic(relic_id: StringName) -> RelicState:
	var relic := RelicState.new()
	relic.instance_id = next_relic_uid
	next_relic_uid += 1
	relic.relic_id = relic_id
	relics.append(relic)
	return relic


## 从卡组移除（按 run_uid）。
func remove_card(run_uid: int) -> bool:
	for i in range(deck.size()):
		if deck[i].run_uid == run_uid:
			deck.remove_at(i)
			return true
	return false


## 当前地图上该节点是否可进入（委托 RouteGraph，带上当前位置；无图时 false）。
## StS 式：只能进入当前节点的直接后继，或（尚未进入任何节点时）入口。
func can_enter(node_id: int) -> bool:
	return is_active() and flow_phase == &"route" and map != null and map.can_enter(node_id, current_node_id)


## 深拷贝：统一走 SaveCodec（encode -> decode），与磁盘存档同一路径，避免第二套 clone（评审 H2）。
func duplicate_state() -> RunState:
	return SaveCodec.new().clone_state(self) as RunState
