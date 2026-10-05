extends "res://tests/test_case.gd"
## RunState 存档编解码 / 版本门禁 / 深拷贝独立性 / SaveService 磁盘往返测试。

const CONTENT_DB_SCRIPT := preload("res://autoload/content_db.gd")
const SAVE_SERVICE_SCRIPT := preload("res://autoload/save_service.gd")
const RUN_PATH := "user://runs/current.json"


func run() -> Array[String]:
	reset()
	var content := _content()
	if content == null:
		_failures.append("catalog 加载失败")
		return failures()
	_test_round_trip(content)
	_test_clone_independence_via_codec(content)
	_test_schema_version_gate(content)
	_test_disk_round_trip(content)
	return failures()


func _content() -> Object:
	var db: Object = CONTENT_DB_SCRIPT.new()
	if not bool(db.call("load_catalog", "res://content/catalog.tres")):
		return null
	return db


## 建一局并进入一个节点，制造非平凡的 visited/content_id/计数器。
func _played_run(content: Object) -> RunState:
	var run: RunState = RunSession.create_run(&"character.hero", "save-seed", content)
	var session := RunSession.new()
	session.setup(run, content)
	var target := int(session.available_node_ids()[0])
	session.enter_node(target)
	run = session.state
	run.add_card(&"card.warrior.execute")   # 模拟战后加卡
	run.relics[0].set_counter(&"used", 2)   # 模拟遗物计数
	return run


func _test_round_trip(content: Object) -> void:
	var run := _played_run(content)
	var codec := SaveCodec.new()
	var decoded := codec.decode_state(codec.encode_state(run)) as RunState
	assert_true(decoded != null, "RunState 往返非空")
	if decoded == null:
		return
	assert_equal(decoded.run_id, run.run_id, "run_id")
	assert_equal(decoded.seed, run.seed, "seed")
	assert_equal(decoded.character_id, run.character_id, "character_id")
	assert_equal(decoded.hp, run.hp, "hp")
	assert_equal(decoded.max_hp, run.max_hp, "max_hp")
	assert_equal(decoded.gold, run.gold, "gold")
	assert_equal(decoded.current_node_id, run.current_node_id, "current_node_id")
	assert_equal(decoded.act_index, run.act_index, "act_index")
	assert_equal(decoded.next_card_uid, run.next_card_uid, "next_card_uid")
	assert_equal(decoded.next_battle_id, run.next_battle_id, "next_battle_id")
	assert_equal(decoded.deck.size(), run.deck.size(), "卡组数量")
	assert_equal(decoded.relics.size(), run.relics.size(), "遗物数量")
	assert_equal(decoded.relics[0].get_counter(&"used"), 2, "遗物计数")
	assert_equal(_sig(decoded), _sig(run), "整体状态签名一致")
	assert_true(decoded.map.boss_id == run.map.boss_id, "map.boss_id")
	assert_equal(decoded.map.entry_ids, run.map.entry_ids, "map.entry_ids")


func _test_clone_independence_via_codec(content: Object) -> void:
	var run := _played_run(content)
	var copy := SaveCodec.new().clone_state(run) as RunState
	assert_true(copy != null, "clone 非空")
	copy.hp = 1
	copy.current_node_id = 123456
	copy.next_battle_id = 999
	copy.map.mark_visited(copy.map.entry_ids[0])
	copy.relics[0].set_counter(&"used", 77)
	assert_equal(run.hp, run.max_hp, "clone 改 hp 不影响原")
	assert_not_equal(run.current_node_id, 123456, "clone 改 current 不影响原")
	assert_not_equal(run.next_battle_id, 999, "clone 改计数器不影响原")
	assert_equal(run.relics[0].get_counter(&"used"), 2, "clone 改遗物不影响原")


func _test_schema_version_gate(content: Object) -> void:
	var run := _played_run(content)
	var codec := SaveCodec.new()
	var data := codec.encode_state(run)
	data["schema_version"] = SaveMigrator.CURRENT_SCHEMA_VERSION + 1
	assert_true(codec.decode_state(data) == null, "更高 schema 版本被拒绝")


func _test_disk_round_trip(content: Object) -> void:
	# 不覆盖开发者真实存档：仅在无存档时跑磁盘往返。
	if FileAccess.file_exists(RUN_PATH):
		return
	var service: Node = SAVE_SERVICE_SCRIPT.new()
	var run := _played_run(content)
	assert_true(service.call("save_run", run), "save_run 成功")
	var loaded := service.call("load_run") as RunState
	assert_true(loaded != null, "load_run 非空")
	if loaded != null:
		assert_equal(_sig(loaded), _sig(run), "磁盘往返状态一致")
		assert_equal(loaded.relics[0].get_counter(&"used"), 2, "磁盘往返遗物计数")
	# 清理测试写入。
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_PATH))
	if FileAccess.file_exists(RUN_PATH + ".bak"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(RUN_PATH + ".bak"))
	service.free()


## 与遍历顺序无关的状态签名（含地图细节）。
func _sig(run: RunState) -> String:
	var parts: Array[String] = [
		"run=%d" % run.run_id,
		"seed=%s" % run.seed,
		"char=%s" % String(run.character_id),
		"hp=%d/%d" % [run.hp, run.max_hp],
		"gold=%d" % run.gold,
		"act=%d" % run.act_index,
		"cur=%d" % run.current_node_id,
		"ncard=%d" % run.next_card_uid,
		"nrelic=%d" % run.next_relic_uid,
		"nbattle=%d" % run.next_battle_id,
		"boss=%d" % run.map.boss_id,
		"entries=%s" % str(run.map.entry_ids),
	]
	for card: RunCardState in run.deck:
		parts.append("card:%d:%s:u%d" % [card.run_uid, String(card.card_id), card.upgrade_level])
	for relic: RelicState in run.relics:
		parts.append("relic:%d:%s" % [relic.instance_id, String(relic.relic_id)])
	var ids: Array = run.map.nodes.keys()
	ids.sort()
	for id: int in ids:
		var n: MapNodeState = run.map.nodes[id]
		parts.append("n%d:r%d c%d %s ct=%s v%d e%d ->%s" % [
			n.id, n.row, n.col, String(n.type_key), String(n.content_id),
			1 if n.visited else 0, 1 if n.is_entry else 0, str(n.next_ids),
		])
	return "|".join(parts)
