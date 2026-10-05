class_name ShopState
extends RefCounted
## 一次商店光顾的瞬态商品状态。不随存档持久化：进入商店时按 ShopDef + RNG 确定性重生成。
## 玩家一旦离开已访问节点便不可返回，故瞬态足够。

var offers: Array[StringName] = []
var sold: Array[bool] = []
var remove_used: bool = false
var heal_used: bool = false


func offer_count() -> int:
	return offers.size()


func is_sold(index: int) -> bool:
	return index >= 0 and index < sold.size() and sold[index]
