class_name RouteMapDef
extends Resource
## 选关地图的生成配置（设计数据，只读）。
## 生成算法见 MapGenerator；规则合同见 docs/route_map_rules.md。
## 约定：type_key 是稳定 ID，同时作为内容查找前缀与表现层美术槽位索引（RouteMapSkin.nodes[type_key]）。

## 标准节点类型键（美术/内容/规则共用）。
const TYPE_MONSTER := &"node.monster"
const TYPE_ELITE := &"node.elite"
const TYPE_REST := &"node.rest"
const TYPE_SHOP := &"node.shop"
const TYPE_TREASURE := &"node.treasure"
const TYPE_EVENT := &"node.event"
const TYPE_BOSS := &"node.boss"

## 正常楼层数（0 .. rows-1）。boss 位于隐式的 row = rows。
@export var rows: int = 15

## 列数（每层的横向宽度）。
@export var cols: int = 7

## 独立路径条数（= 入口节点数）。必须 <= cols。
@export var path_count: int = 6

## 行号 -> 强制类型。固定行不参与抽签，也不被降级（其相邻约束仍然生效）。
@export var fixed_floors: Dictionary[int, StringName] = {
	0: TYPE_MONSTER,
	8: TYPE_TREASURE,
	14: TYPE_REST,
}

## 类型 -> 最早可出现的行号（低于下限不参与抽签）。
@export var min_floors: Dictionary[StringName, int] = {
	TYPE_REST: 6,
	TYPE_SHOP: 6,
	TYPE_ELITE: 1,
}

## 类型 -> 基础权重（无需归一化，按总和加权抽签）。
@export var weights: Dictionary[StringName, float] = {
	TYPE_MONSTER: 53.0,
	TYPE_EVENT: 22.0,
	TYPE_ELITE: 8.0,
	TYPE_REST: 12.0,
	TYPE_SHOP: 5.0,
}

## 受"相邻不重复"约束的类型：同一条边两端不得同时是这些类型。
@export var special_types: Array[StringName] = [TYPE_REST, TYPE_SHOP, TYPE_ELITE]

## 抽签池为空（配置异常）时的兜底链，从前往后取第一个满足下限的类型。
@export var fallback_chain: Array[StringName] = [TYPE_EVENT, TYPE_MONSTER]
