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
## 短章节：7 层 —— 只保证三处：入口全战斗、row 3 全宝箱、进 boss 前一行全休息；
## 其余行（1/2/4/5）按权重随机（战斗/事件/精英/休息/商店）。
@export var rows: int = 7

## 列数（每层的横向宽度）。
@export var cols: int = 7

## 独立路径条数（= 入口节点数）。必须 <= cols。
@export var path_count: int = 6

## 行号 -> 强制类型。固定行不参与抽签，也不被降级（其相邻约束仍然生效）。
## 三处保证：row 0 全战斗（入口）、row 3 全宝箱、row 6 全休息（进 boss 前）。
@export var fixed_floors: Dictionary[int, StringName] = {
	0: TYPE_MONSTER,
	3: TYPE_TREASURE,
	6: TYPE_REST,
}

## 类型 -> 最早可出现的行号（低于下限不参与抽签）：精英/休息/商店不要太靠前。
@export var min_floors: Dictionary[StringName, int] = {
	TYPE_ELITE: 2,
	TYPE_REST: 3,
	TYPE_SHOP: 3,
}

## 类型 -> 基础权重（无需归一化，按总和加权抽签）。行 1/2/4/5 按此抽签，
## 受相邻约束与下限过滤；战斗为主、事件其次，精英/休息/商店偶发。
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
