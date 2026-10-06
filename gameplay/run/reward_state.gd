class_name RewardState
extends RefCounted
## 一次战斗胜利后的奖励，随 RunState.pending_payload 持久化。

var offers: Array[StringName] = []
## 是否已结算（领卡或放弃）。一旦结算不可再领。
var claimed: bool = false
var battle_id: int = -1


func to_dict() -> Dictionary:
	return {"offers": offers.duplicate(), "claimed": claimed, "battle_id": battle_id}


static func from_dict(data: Dictionary) -> RewardState:
	var result := RewardState.new()
	for id: Variant in data.get("offers", []):
		result.offers.append(StringName(String(id)))
	result.claimed = bool(data.get("claimed", false))
	result.battle_id = int(data.get("battle_id", -1))
	return result
