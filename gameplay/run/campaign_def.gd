class_name CampaignDef
extends Resource
## 一次完整游玩（Campaign）的三章配置。StS 同款：章与章结构相同、内容/难度不同。
## 本轮每章复用同一 RouteMapDef 结构，靠**每章独立种子**得到不同地图；
## 后续内容绑定（更难的权重、不同 boss）时，在 acts 里各放一份调参后的 RouteMapDef 即可。

const ACT_COUNT := 3

## 各章地图生成配置（索引 = 章号）。为空时按 ACT_COUNT 走 RouteMapDef 默认。
@export var acts: Array[RouteMapDef] = []


func act_count() -> int:
	if acts.is_empty():
		return ACT_COUNT
	return acts.size()


## 第 index 章的地图配置；越界或缺省时返回一份新的默认配置。
func act_def(index: int) -> RouteMapDef:
	if index >= 0 and index < acts.size() and acts[index] != null:
		return acts[index]
	return RouteMapDef.new()


## 由 run seed + 章号派生该章的确定性种子。
## 过渡实现：待 RngStreams 落地后改用 splitmix64(run_seed, stream_id)（见 combat_rules §12）。
static func derive_act_seed(run_seed: int, act_index: int) -> int:
	var x := run_seed + act_index * 0x9E3779B1
	x = (x ^ (x >> 16)) * 0x45D9F3B
	x = x ^ (x >> 16)
	return x
