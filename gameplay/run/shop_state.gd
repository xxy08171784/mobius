class_name ShopState
extends RefCounted
## 一次商店光顾的商品状态，随 RunState.pending_payload 持久化。

var offers: Array[StringName] = []
var sold: Array[bool] = []
var remove_used: bool = false
var heal_used: bool = false


func to_dict() -> Dictionary:
	return {"offers": offers.duplicate(), "sold": sold.duplicate(), "remove_used": remove_used, "heal_used": heal_used}


static func from_dict(data: Dictionary) -> ShopState:
	var result := ShopState.new()
	for id: Variant in data.get("offers", []):
		result.offers.append(StringName(String(id)))
	for value: Variant in data.get("sold", []):
		result.sold.append(bool(value))
	result.remove_used = bool(data.get("remove_used", false))
	result.heal_used = bool(data.get("heal_used", false))
	return result


func offer_count() -> int:
	return offers.size()


func is_sold(index: int) -> bool:
	return index >= 0 and index < sold.size() and sold[index]
