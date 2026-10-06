class_name BattleResult
extends RefCounted
## 战斗结束后交给 RunSession 的结果。
## 只携带"明确允许持久化"的变化；临时护盾/战斗增益/抽牌顺序不写回单局。

var battle_id: int = -1
var run_instance_id: String = ""
var rng_snapshot: Dictionary = {}
var victory: bool = false

## 持久 HP、跨战斗保留的卡牌变化等；字段级白名单见 §6 持久性矩阵。
var persistent_changes: Dictionary = {}
