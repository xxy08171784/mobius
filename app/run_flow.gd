class_name RunFlow
extends Control
## 一局游玩的场景编排：路线地图 <-> 战斗 <-> 非战斗节点（休息/商店/事件）。
## 规则全部在 RunSession / RestSystem / ShopSystem / EventSystem；本类只负责切换界面与转发选择。
##
## 依赖 autoload：App（生命周期）、ContentDB、SaveService。

const ROUTE_SCENE := preload("res://presentation/route_map/route_map.tscn")
const BATTLE_SCENE := preload("res://presentation/battle/battle_screen.tscn")

var _session: RunSession = null
var _status: Label = null
var _hud: Label = null

## 非战斗节点屏的当前模式与瞬态数据。
var _node_mode: StringName = &""
var _shop_def: ShopDef = null
var _shop_state: ShopState = null
var _event_def: EventDef = null
var _reward_pending: RewardState = null


func _ready() -> void:
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 16)
	_hud.modulate = Color(0.9, 0.9, 0.95)
	add_child(_hud)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 20)
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(_status)
	_status.visible = false


## 开一局新 run 并进入地图。返回是否成功。
func start_run(character_id: StringName = &"character.hero", seed_text: String = "") -> bool:
	var run := App.create_run(character_id, seed_text)
	if run == null:
		_show_status("创建 Run 失败（内容未加载？）")
		return false
	_session = App.current_session
	_show_route()
	return true


func _show_route() -> void:
	_clear_screen()
	_update_hud()
	var route: RouteMapScreen = ROUTE_SCENE.instantiate()
	add_child(route)
	route.bind_run_session(_session)
	route.node_entered.connect(_on_node_entered)


func _on_node_entered(transition: Dictionary) -> void:
	match StringName(String(transition.get("kind", ""))):
		RunSession.KIND_BATTLE:
			_show_battle(transition.get("battle", {}))
		&"rest":
			_show_rest()
		&"shop":
			_show_shop(transition)
		&"event":
			_show_event(StringName(String(transition.get("content_id", ""))))
		&"treasure":
			_show_treasure(transition)
		_:
			_show_route()


# ---- 战斗 ----------------------------------------------------------------

func _show_battle(data: Dictionary) -> void:
	_clear_screen()
	var screen: Control = BATTLE_SCENE.instantiate()
	screen.set("demo_autostart", false)   # 必须在 add_child 前设，避免 _ready 自动开 demo
	add_child(screen)
	screen.call("configure", data)
	screen.connect("battle_finished", _on_battle_finished)


func _on_battle_finished(result: BattleResult) -> void:
	if _session == null:
		return
	var outcome := _session.on_battle_finished(result)
	match StringName(String(outcome.get("kind", ""))):
		RunSession.KIND_DEFEAT:
			_show_defeat()
		RunSession.KIND_RUN_COMPLETE:
			_show_run_complete()
		_:
			_show_reward(StringName(String(outcome.get("kind", ""))))


# ---- 入口 / 收尾 ----------------------------------------------------------

## 主菜单（游戏入口）。继续按钮仅在存在存档时可用。
func show_main_menu() -> void:
	_clear_screen()
	_update_hud()
	var menu := MainMenuScreen.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	menu.setup(SaveService.has_run())
	menu.new_game.connect(_show_character_select)
	menu.continue_run.connect(_on_continue_run)
	menu.quit.connect(func() -> void: get_tree().quit())


func _show_character_select() -> void:
	_clear_screen()
	var screen := CharacterSelectScreen.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	var characters: Array = []
	for id_value: Variant in ContentDB.character_ids():
		var id := StringName(String(id_value))
		var definition := ContentDB.get_character(id)
		var label := String(id)
		if definition != null and not definition.display_name.is_empty():
			label = definition.display_name
		characters.append({"id": id, "label": label})
	screen.setup(characters)
	screen.chosen.connect(_on_character_chosen)
	screen.back.connect(show_main_menu)


func _on_character_chosen(character_id: StringName) -> void:
	start_run(character_id)


func _on_continue_run() -> void:
	if App.load_run() == null:
		show_main_menu()
		return
	_session = App.current_session
	_show_route()


func _show_defeat() -> void:
	var screen := _make_node_screen("你倒下了", "回环吞没了这次冒险。", show_main_menu)
	screen.set_leave_text("返回主菜单")


func _show_run_complete() -> void:
	var screen := _make_node_screen("通关！", "你走出了莫比乌斯之环。", show_main_menu)
	screen.set_leave_text("返回主菜单")


# ---- 休息 ----------------------------------------------------------------

func _show_rest() -> void:
	var run := _session.state
	_node_mode = &"rest"
	var screen := _make_node_screen("休息", "你在营火旁稍作喘息。")
	var options: Array = []
	if run.hp < run.max_hp:
		options.append({
			"text": "休息：回复 %d 点生命" % RestSystem.heal_amount(run),
			"data": {"action": "heal"},
		})
	for uid: int in RestSystem.upgradable_card_uids(run):
		var card := run.get_card(uid)
		options.append({
			"text": "升级：%s" % _card_name(card.card_id),
			"data": {"action": "upgrade", "uid": uid},
		})
	options.append({"text": "什么都不做", "data": {"action": "leave"}})
	screen.set_options(options)


func _on_rest_chose(data: Dictionary) -> void:
	var run := _session.state
	match StringName(String(data.get("action", ""))):
		&"heal":
			RestSystem.apply(run, RestSystem.OPTION_HEAL)
		&"upgrade":
			RestSystem.apply(run, RestSystem.OPTION_UPGRADE, int(data.get("uid", -1)))
		_:
			pass
	_session.save()
	_show_route()


# ---- 商店 ----------------------------------------------------------------

func _show_shop(transition: Dictionary) -> void:
	_node_mode = &"shop"
	_shop_def = ContentDB.get_shop(StringName(String(transition.get("content_id", ""))))
	_shop_state = transition.get("shop", null) as ShopState
	if _shop_def == null or _shop_state == null:
		_show_route()
		return
	_rebuild_shop()


func _rebuild_shop() -> void:
	var run := _session.state
	var screen := _make_node_screen("商店", "金币：%d" % run.gold)
	var options: Array = []
	for i in _shop_state.offer_count():
		var sold := _shop_state.is_sold(i)
		var afford := run.gold >= _shop_def.card_price
		var text := "%s — %d 金币" % [_card_name(_shop_state.offers[i]), _shop_def.card_price]
		if sold:
			text += "（已售）"
		options.append({
			"text": text,
			"disabled": sold or not afford,
			"data": {"action": "buy", "index": i},
		})
	options.append({
		"text": "回复 %d 点生命 — %d 金币" % [_shop_def.heal_amount, _shop_def.heal_price],
		"disabled": _shop_state.heal_used or run.gold < _shop_def.heal_price or run.hp >= run.max_hp,
		"data": {"action": "heal"},
	})
	options.append({"text": "删除一张卡 — %d 金币" % _shop_def.remove_price,
		"disabled": _shop_state.remove_used or run.gold < _shop_def.remove_price,
		"data": {"action": "remove_menu"}})
	options.append({"text": "离开", "data": {"action": "leave"}})
	screen.set_options(options)


func _on_shop_chose(data: Dictionary) -> void:
	var run := _session.state
	match StringName(String(data.get("action", ""))):
		&"buy":
			ShopSystem.buy_card(run, _shop_state, _shop_def, int(data.get("index", -1)))
			_session.save()
			_rebuild_shop()
		&"heal":
			ShopSystem.buy_heal(run, _shop_state, _shop_def)
			_session.save()
			_rebuild_shop()
		&"remove_menu":
			_show_remove_menu()
		&"remove":
			ShopSystem.buy_remove(run, _shop_state, _shop_def, int(data.get("uid", -1)))
			_session.save()
			_rebuild_shop()
		&"back":
			_rebuild_shop()
		_:
			_show_route()


## 删卡子菜单：列出当前卡组，选一张删除。
func _show_remove_menu() -> void:
	var run := _session.state
	var screen := _make_node_screen("商店 · 删除卡牌", "选择要移除的卡。（金币：%d）" % run.gold)
	var options: Array = []
	for card: RunCardState in run.deck:
		options.append({
			"text": _card_name(card.card_id),
			"disabled": run.deck.size() <= 1,
			"data": {"action": "remove", "uid": card.run_uid},
		})
	options.append({"text": "返回", "data": {"action": "back"}})
	screen.set_options(options)


# ---- 事件 ----------------------------------------------------------------

func _show_event(event_id: StringName) -> void:
	_event_def = ContentDB.get_event(event_id)
	if _event_def == null:
		_show_route()
		return
	_node_mode = &"event"
	var screen := _make_node_screen(_event_def.title, _event_def.body)
	var options: Array = []
	for i in _event_def.choices.size():
		var choice: EventChoice = _event_def.choices[i]
		options.append({"text": choice.label, "data": {"action": "event_choice", "index": i}})
	screen.set_options(options)


func _on_event_chose(data: Dictionary) -> void:
	if StringName(String(data.get("action", ""))) == &"event_choice":
		EventSystem.resolve(_session.state, _event_def, int(data.get("index", -1)))
		_session.save()
	_show_route()


# ---- 宝箱 ----------------------------------------------------------------

func _show_treasure(transition: Dictionary) -> void:
	_node_mode = &"treasure"
	var relic_id := StringName(String(transition.get("relic_id", "")))
	var screen := _make_node_screen(
		"宝箱",
		"获得遗物：%s\n金币 +%d" % [_relic_name(relic_id), int(transition.get("gold", 0))]
	)
	screen.set_options([{"text": "收下", "data": {"action": "leave"}}])


# ---- 奖励（战后三选一） ---------------------------------------------------

func _show_reward(_kind: StringName) -> void:
	_reward_pending = _session.generate_reward()
	if _reward_pending == null or _reward_pending.offers.is_empty():
		_show_route()
		return
	_node_mode = &"reward"
	var screen := _make_node_screen(
		"战利品",
		"选择一张牌加入卡组（金币 +%d 已入账）。" % RewardSystem.GOLD_REWARD
	)
	var options: Array = []
	for i in _reward_pending.offers.size():
		options.append({
			"text": _card_name(_reward_pending.offers[i]),
			"data": {"action": "reward_choice", "index": i},
		})
	options.append({"text": "放弃", "data": {"action": "reward_skip"}})
	screen.set_options(options)


func _on_reward_chose(data: Dictionary) -> void:
	var action := StringName(String(data.get("action", "")))
	if action == &"reward_choice":
		_session.claim_reward(_reward_pending, int(data.get("index", -1)))
	elif action == &"reward_skip":
		_session.claim_reward(_reward_pending, -1)
	_show_route()


# ---- 通用 ----------------------------------------------------------------

func _make_node_screen(title: String, body: String, on_leave: Callable = Callable()) -> NodeChoiceScreen:
	_clear_screen()
	_update_hud()
	var screen := NodeChoiceScreen.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	screen.set_content(title, body)
	screen.chose.connect(_on_node_chose)
	screen.leave_requested.connect(on_leave if on_leave.is_valid() else _show_route)
	return screen


func _on_node_chose(data: Dictionary) -> void:
	match _node_mode:
		&"rest":
			_on_rest_chose(data)
		&"shop":
			_on_shop_chose(data)
		&"event":
			_on_event_chose(data)
		&"reward":
			_on_reward_chose(data)
		_:
			_show_route()


func _card_name(card_id: StringName) -> String:
	var definition := ContentDB.get_card(card_id)
	if definition != null and not definition.display_name.is_empty():
		return definition.display_name
	return String(card_id)


func _relic_name(relic_id: StringName) -> String:
	var definition := ContentDB.get_relic(relic_id)
	if definition != null and not definition.display_name.is_empty():
		return definition.display_name
	return String(relic_id)


func _update_hud() -> void:
	if _hud == null:
		return
	if _session == null or _session.state == null:
		_hud.text = ""
		return
	var run := _session.state
	_hud.text = "第 %d 章 · HP %d/%d · 金币 %d · 卡组 %d 张" % [
		run.act_index + 1, run.hp, run.max_hp, run.gold, run.deck.size()
	]


func _clear_screen() -> void:
	for child: Node in get_children():
		if child != _status and child != _hud:
			child.queue_free()


func _show_status(text: String) -> void:
	_clear_screen()
	_status.text = text
	_status.visible = true
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
