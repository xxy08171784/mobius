class_name RewardState
extends RefCounted
## 一次战斗胜利后的奖励瞬态：3 张可选卡牌。不随存档持久化（战后再生成）。

var offers: Array[StringName] = []
## 是否已结算（领卡或放弃）。一旦结算不可再领。
var claimed: bool = false
