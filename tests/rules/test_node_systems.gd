extends "res://tests/test_case.gd"
## 非战斗节点系统：RestSystem / ShopSystem / EventSystem 规则测试。

const CONTENT_DB_SCRIPT := preload("res://autoload/content_db.gd")


func run() -> Array[String]:
	reset()
	var content := _content()
	if content == null:
		_failures.append("catalog 加载失败")
		return failures()
	_test_rest(content)
	_test_shop(content)
	_test_event(content)
	return failures()


func _content() -> Object:
	var db: Object = CONTENT_DB_SCRIPT.new()
	if not bool(db.call("load_catalog", "res://content/catalog.tres")):
		return null
	return db


func _run(content: Object, hp: int = 20, gold: int = 99) -> RunState:
	var run: RunState = RunSession.create_run(&"character.hero", "node-systems", content)
	run.hp = hp
	run.gold = gold
	return run


func _test_rest(content: Object) -> void:
	var run := _run(content, 20)
	assert_equal(RestSystem.heal_amount(run), 24, "80 max_hp 的 30% 向下取整 = 24")

	var healed := RestSystem.apply(run, RestSystem.OPTION_HEAL)
	assert_true(bool(healed.get("ok", false)), "回血成功")
	assert_equal(run.hp, 44, "回血 24 点")
	# 满血时回 0，不超上限。
	run.hp = 80
	assert_equal(int(RestSystem.apply(run, RestSystem.OPTION_HEAL).get("healed", -1)), 0, "满血回 0")

	# 升级：0 -> 1，再次升级被拒。
	var card: RunCardState = run.deck[0]
	assert_true(RestSystem.can_upgrade(card), "初始可升级")
	var up := RestSystem.apply(run, RestSystem.OPTION_UPGRADE, card.run_uid)
	assert_true(bool(up.get("ok", false)), "升级成功")
	assert_equal(card.upgrade_level, 1, "升级等级 +1")
	assert_true(not RestSystem.can_upgrade(card), "已达上限")
	assert_true(
		not bool(RestSystem.apply(run, RestSystem.OPTION_UPGRADE, card.run_uid).get("ok", false)),
		"重复升级被拒"
	)
	assert_true(
		not bool(RestSystem.apply(run, RestSystem.OPTION_UPGRADE, 999999).get("ok", false)),
		"不存在卡升级被拒"
	)
	assert_true(not bool(RestSystem.apply(run, &"nope").get("ok", false)), "未知选项被拒")


func _test_shop(content: Object) -> void:
	var def: ShopDef = content.call("get_shop", &"shop.route")
	assert_true(def != null, "商店定义存在")
	if def == null:
		return

	# 生成确定性。
	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 7
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 7
	var shop_a := ShopSystem.generate(def, rng_a, content)
	var shop_b := ShopSystem.generate(def, rng_b, content)
	assert_equal(shop_a.offer_count(), def.offer_count, "商品数 = offer_count")
	assert_equal(shop_a.offers, shop_b.offers, "同 seed 商品确定")

	var run := _run(content, 20, 99)
	var first_offer: StringName = shop_a.offers[0]
	var deck_before := run.deck.size()
	var buy := ShopSystem.buy_card(run, shop_a, def, 0)
	assert_true(bool(buy.get("ok", false)), "买卡成功")
	assert_equal(run.gold, 99 - def.card_price, "扣金币")
	assert_equal(run.deck.size(), deck_before + 1, "卡组 +1")
	assert_equal(run.deck[run.deck.size() - 1].card_id, first_offer, "买入的是货架卡")
	assert_true(not bool(ShopSystem.buy_card(run, shop_a, def, 0).get("ok", false)), "重复购买被拒")
	assert_true(not bool(ShopSystem.buy_card(run, shop_a, def, 999).get("ok", false)), "非法下标被拒")
	# 金币不足。
	run.gold = 0
	assert_equal(
		String(ShopSystem.buy_card(run, shop_a, def, 1).get("error_code", "")),
		"not_enough_gold",
		"金币不足"
	)

	# 删卡：需金币充足且卡组 > 1。
	var rich := _run(content, 20, 200)
	var remove_target := rich.deck[0]
	var rich_deck := rich.deck.size()
	var rm := ShopSystem.buy_remove(rich, ShopState.new(), def, remove_target.run_uid)
	assert_true(bool(rm.get("ok", false)), "删卡成功")
	assert_equal(rich.deck.size(), rich_deck - 1, "卡组 -1")
	assert_equal(rich.gold, 200 - def.remove_price, "删卡扣金币")
	# 只剩一张时不可删。
	var tiny := _run(content, 20, 200)
	while tiny.deck.size() > 1:
		tiny.remove_card(tiny.deck[0].run_uid)
	assert_equal(
		String(ShopSystem.buy_remove(tiny, ShopState.new(), def, tiny.deck[0].run_uid).get("error_code", "")),
		"last_card",
		"最后一张不可删"
	)

	# 回血服务。
	var hurt := _run(content, 10, 99)
	var heal := ShopSystem.buy_heal(hurt, ShopState.new(), def)
	assert_true(bool(heal.get("ok", false)), "商店回血成功")
	assert_equal(hurt.hp, 10 + def.heal_amount, "回血量")
	assert_equal(hurt.gold, 99 - def.heal_price, "回血扣金币")


func _test_event(content: Object) -> void:
	var def: EventDef = content.call("get_event", &"event.loop_temptation")
	assert_true(def != null and def.is_valid(), "事件定义存在")
	if def == null:
		return
	var run := _run(content, 20, 10)
	# 选项 0：-5 HP, +60 金币。
	var out := EventSystem.resolve(run, def, 0)
	assert_true(bool(out.get("ok", false)), "事件选项成功")
	assert_equal(run.hp, 15, "HP -5")
	assert_equal(run.gold, 70, "金币 +60")
	# 非法选项。
	assert_true(not bool(EventSystem.resolve(run, def, 99).get("ok", false)), "非法选项被拒")

	# 加卡 + HP 钳制。
	var campfire: EventDef = content.call("get_event", &"event.forgotten_campfire")
	var run2 := _run(content, 25, 0)
	var deck_before := run2.deck.size()
	EventSystem.resolve(run2, campfire, 0)   # +10 HP -> 35（未超 80 上限）
	assert_equal(run2.hp, 35, "HP +10 = 35")
	EventSystem.resolve(run2, campfire, 1)   # 加卡
	assert_equal(run2.deck.size(), deck_before + 1, "事件加卡")
	assert_true(bool(EventSystem.resolve(run2, campfire, 0).get("ok", false)), "可重复选择（原型无一次性限制）")
