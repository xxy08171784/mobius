class_name MapNodeState
extends RefCounted
## 选关地图上的一个节点。纯数据，不含生成逻辑（生成见 MapGenerator）。
## 表现状态（available/locked/visited/current）是派生值，不在此存储，避免与存档不同步。

## 图的稳定节点 ID，由 MapGenerator 按生成顺序单调分配（确定性给定 config+rng）。
var id: int = -1

var row: int = 0
var col: int = 0

## 稳定类型键，见 RouteMapDef.TYPE_*。也是美术槽位索引。
var type_key: StringName = &""

## 该节点产出的具体内容 ID（如遭遇/事件），由 EncounterBuilder 之后填充；本轮留空。
var content_id: StringName = &""

## 是否已被访问（渐进状态；唯一随本局持久化的节点标志）。
var visited: bool = false

## 是否为第 0 行入口节点。
var is_entry: bool = false

## 低行（来路）与高行（去路）的邻居 ID。边方向：玩家自低行走向 boss。
var prev_ids: Array[int] = []
var next_ids: Array[int] = []


func cell() -> Vector2i:
	return Vector2i(col, row)


func add_next(nid: int) -> void:
	if not next_ids.has(nid):
		next_ids.append(nid)


func add_prev(pid: int) -> void:
	if not prev_ids.has(pid):
		prev_ids.append(pid)
