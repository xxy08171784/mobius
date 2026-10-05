class_name ShopSystem
extends RefCounted
## 商店规则：确定性生成商品；买卡 / 删卡 / 回血。校验先行，失败零副作用。


## 从 ShopDef.card_pool 无重复抽 offer_count 张（用传入 rng，确定性）。
static func generate(def: ShopDef, rng: RandomNumberGenerator) -> ShopState:
	var state := ShopState.new()
	if def == null:
		return state
	var pool: Array[StringName] = def.card_pool.duplicate()
	_shuffle(pool, rng)
	var count := mini(def.offer_count, pool.size())
	for i in count:
		state.offers.append(pool[i])
		state.sold.append(false)
	return state


## 买第 index 个商品卡。成功加入卡组并扣金币。
static func buy_card(run: RunState, shop: ShopState, def: ShopDef, index: int) -> Dictionary:
	if run == null or shop == null or def == null:
		return {"ok": false, "error_code": &"not_ready"}
	if index < 0 or index >= shop.offers.size() or shop.is_sold(index):
		return {"ok": false, "error_code": &"invalid_offer"}
	if run.gold < def.card_price:
		return {"ok": false, "error_code": &"not_enough_gold"}
	var card := run.add_card(shop.offers[index])
	run.gold -= def.card_price
	shop.sold[index] = true
	return {"ok": true, "kind": &"buy_card", "card_id": card.card_id, "card_run_uid": card.run_uid}


## 删除一张卡（一次性服务）。不允许删到空卡组。
static func buy_remove(run: RunState, shop: ShopState, def: ShopDef, card_run_uid: int) -> Dictionary:
	if run == null or shop == null or def == null:
		return {"ok": false, "error_code": &"not_ready"}
	if shop.remove_used:
		return {"ok": false, "error_code": &"service_used"}
	if run.gold < def.remove_price:
		return {"ok": false, "error_code": &"not_enough_gold"}
	if run.deck.size() <= 1:
		return {"ok": false, "error_code": &"last_card"}
	if run.get_card(card_run_uid) == null:
		return {"ok": false, "error_code": &"no_card"}
	run.remove_card(card_run_uid)
	run.gold -= def.remove_price
	shop.remove_used = true
	return {"ok": true, "kind": &"remove_card", "card_run_uid": card_run_uid}


## 回血服务（一次性）。回血量不超过 max_hp。
static func buy_heal(run: RunState, shop: ShopState, def: ShopDef) -> Dictionary:
	if run == null or shop == null or def == null:
		return {"ok": false, "error_code": &"not_ready"}
	if shop.heal_used:
		return {"ok": false, "error_code": &"service_used"}
	if run.gold < def.heal_price:
		return {"ok": false, "error_code": &"not_enough_gold"}
	var healed := maxi(0, mini(def.heal_amount, run.max_hp - run.hp))
	run.hp += healed
	run.gold -= def.heal_price
	shop.heal_used = true
	return {"ok": true, "kind": &"heal", "healed": healed}


static func _shuffle(values: Array[StringName], rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp: StringName = values[i]
		values[i] = values[j]
		values[j] = temp
