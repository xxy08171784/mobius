class_name RunFlow
extends Control
## 一局游玩的场景编排：路线地图 <-> 战斗 <-> 非战斗节点（休息/商店/事件）。
## 规则全部在 RunSession / RestSystem / ShopSystem / EventSystem；本类只负责切换界面与转发选择。
##
## 依赖 autoload：App（生命周期）、ContentDB、SaveService。

const ROUTE_SCENE := preload("res://presentation/route_map/route_map.tscn")
const BATTLE_SCENE := preload("res://presentation/battle/battle_screen.tscn")
const PLOT_INTRO_SCENE := preload("res://presentation/common/plot_intro.tscn")

var _session: RunSession = null
var _status: Label = null
var _save_warning: AcceptDialog = null
var _hud: Label = null

## 常驻顶部条（地图/节点/战斗各屏都显示）：遗物按钮 + 查看卡组。
var _top_bar: RunToolbar = null
var _relic_box: HBoxContainer = null

## 非战斗节点屏的当前模式与瞬态数据。
var _node_mode: StringName = &""
var _shop_def: ShopDef = null
var _shop_state: ShopState = null
var _event_def: EventDef = null
var _reward_pending: RewardState = null
var _announced_chapter: String = ""


func _ready() -> void:
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 16)
	_hud.modulate = Color(0.9, 0.9, 0.95)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)

	_build_top_bar()

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 20)
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(_status)
	_status.visible = false

	child_entered_tree.connect(_on_child_entered)
	resized.connect(_place_top_bar)
	SaveService.persistence_error.connect(_show_save_error)
	_save_warning = AcceptDialog.new()
	_save_warning.process_mode = Node.PROCESS_MODE_ALWAYS
	_save_warning.title = "存档未保存"
	_save_warning.ok_button_text = "重试保存"
	_save_warning.confirmed.connect(_retry_save)
	add_child(_save_warning)


## 常驻顶部条：遗物按钮 + 「查看卡组」。位于右上角，跨屏常驻（见 _clear_screen 豁免）。
func _build_top_bar() -> void:
	_top_bar = preload("res://presentation/common/run_toolbar.tscn").instantiate()
	add_child(_top_bar)
	_relic_box = _top_bar.get_node("Relics")
	_top_bar.get_node("Deck").pressed.connect(_on_view_deck)
	_top_bar.get_node("Pause").pressed.connect(_show_pause)
	_refresh_top_bar()


func _refresh_top_bar() -> void:
	if _relic_box == null:
		return
	for child: Node in _relic_box.get_children():
		_relic_box.remove_child(child)
		child.queue_free()
	if _session != null and _session.state != null:
		for relic: RelicState in _session.state.relics:
			var definition: RelicDef = ContentDB.get_relic(relic.relic_id)
			if definition == null or not definition.enabled:
				continue
			var button := Button.new()
			button.text = CardInfo.display_name_of_relic(definition)
			button.tooltip_text = CardInfo.relic_tooltip(definition)
			button.focus_mode = Control.FOCUS_NONE
			_relic_box.add_child(button)
	if _session != null:
		_top_bar.set_gold(_session.state.gold)
	_place_top_bar()


func _place_top_bar() -> void:
	if _top_bar == null:
		return
	_top_bar.size = _top_bar.get_combined_minimum_size()
	_top_bar.position = Vector2(get_viewport_rect().size.x - _top_bar.size.x - 10, 10)


## 各界面（主菜单/地图/节点屏/战斗屏）都是铺满全屏且 STOP 的 Control，会盖住常驻顶栏抢点击；
## 每当有这类子节点进场，就把顶栏提到最上层。DeckPopup 是模态弹层，必须保持最上，跳过。
func _on_child_entered(node: Node) -> void:
	if _top_bar == null:
		return
	if node == _top_bar or node == _hud or node == _status:
		return
	if node is DeckPopup:
		return
	move_child(_hud, get_child_count() - 1)
	move_child(_top_bar, get_child_count() - 1)


func _on_view_deck() -> void:
	if _session == null or _session.state == null:
		return
	add_child(DeckPopup.for_run(_session.state))


## 开一局新 run 并进入地图。返回是否成功。
func start_run(character_id: StringName = &"character.hero", seed_text: String = "") -> bool:
	var run := App.create_run(character_id, seed_text)
	if run == null:
		_show_status("创建 Run 失败（内容未加载？）")
		return false
	_session = App.current_session
	_resume_flow()
	if not App.ensure_profile().tutorial_seen:
		_show_help(_resume_flow)
	return true


func _show_route() -> void:
	AudioService.play_music(&"route")
	_clear_screen()
	_update_hud()
	var route: RouteMapScreen = ROUTE_SCENE.instantiate()
	route.demo_autostart = false
	add_child(route)
	route.bind_run_session(_session)
	route.activated.connect(_on_route_node_activated)
	var chapter_key := "%s:%d" % [_session.state.instance_id, _session.state.act_index]
	if App.ensure_profile().tutorial_seen and _announced_chapter != chapter_key:
		_announced_chapter = chapter_key
		var intro: ChapterIntro = preload("res://presentation/common/chapter_intro.tscn").instantiate()
		intro.chapter_index = _session.state.act_index
		add_child(intro)
		move_child(intro, get_child_count() - 1)


## 地图节点被点击。战斗节点先让玩家选进场格，再进入；其余直接进入并派发。
func _on_route_node_activated(node_id: int) -> void:
	if _session == null:
		return
	if _session.is_battle_node(node_id):
		if bool(_session.begin_deployment(node_id).get("ok", false)):
			_show_deployment(node_id)
		return
	var transition := _session.enter_node(node_id)
	if not bool(transition.get("ok", false)):
		return
	_on_node_entered(transition)


## 开战前选进场格：复用 BattleScreen 的 BoardZone 和 DeploymentUI。
## 这里仅负责 RunSession -> BattleScreen 的数据/导航，不再动态创建任何战斗 UI。
func _show_deployment(node_id: int) -> void:
	_clear_screen()
	_update_hud()
	var screen: BattleScreen = BATTLE_SCENE.instantiate()
	screen.demo_autostart = false
	screen.chapter_index = _session.state.act_index
	add_child(screen)
	screen.battle_finished.connect(_on_battle_finished)
	screen.checkpoint_requested.connect(_session.checkpoint_battle)
	screen.deployment_cancelled.connect(func() -> void:
		_session.cancel_deployment()
		_show_route()
	)
	screen.deployment_cell_chosen.connect(func(cell: Vector2i) -> void: _on_deploy_cell(node_id, cell, screen))
	var preview: Dictionary = _session.state.pending_payload.get("preview", {})
	screen.configure_deployment(preview)


func _on_deploy_cell(node_id: int, cell: Vector2i, screen: BattleScreen) -> void:
	var transition := _session.enter_node(node_id, cell)
	if not bool(transition.get("ok", false)):
		return
	if StringName(String(transition.get("kind", ""))) == RunSession.KIND_BATTLE:
		# 不销毁/重建场景，原地把同一个 BattleScreen 从部署模式切为战斗模式。
		# BoardZone 因而不会发生位置或尺寸跳变。
		if is_instance_valid(screen):
			_update_hud()
			AudioService.play_music(&"battle")
			screen.configure(transition.get("battle", {}))
	else:
		_on_node_entered(transition)


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
	AudioService.play_music(&"battle")
	_clear_screen()
	_update_hud()
	var screen: BattleScreen = BATTLE_SCENE.instantiate()
	screen.demo_autostart = false   # 必须在 add_child 前设，避免 _ready 自动开 demo
	screen.chapter_index = _session.state.act_index
	add_child(screen)
	screen.battle_finished.connect(_on_battle_finished)
	screen.checkpoint_requested.connect(_session.checkpoint_battle)
	# 先接完成信号再注入数据，避免 configure() 将来出现同步终局路径时漏掉结果。
	screen.configure(data)


func _on_battle_finished(result: BattleResult) -> void:
	if _session == null:
		return
	var outcome := _session.on_battle_finished(result)
	if not bool(outcome.get("ok", false)):
		return
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
	App.recover_ended_run()
	AudioService.play_music(&"menu")
	_session = null
	_clear_screen()
	_update_hud()
	var menu: MainMenuScreen = preload("res://presentation/screens/main_menu.tscn").instantiate()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	menu.setup(SaveService.has_run())
	menu.new_game.connect(_show_character_select)
	menu.continue_run.connect(_on_continue_run)
	menu.settings_requested.connect(_open_settings)
	menu.history_requested.connect(_show_history)
	menu.library_requested.connect(_show_library)
	menu.help_requested.connect(func() -> void: _show_help(show_main_menu))
	menu.quit.connect(func() -> void: get_tree().quit())


func _show_character_select() -> void:
	_clear_screen()
	var screen: CharacterSelectScreen = preload("res://presentation/screens/character_select.tscn").instantiate()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	var characters: Array = []
	for id_value: Variant in ContentDB.character_ids():
		var id := StringName(String(id_value))
		var definition := ContentDB.get_character(id)
		var label := String(id)
		if definition != null and not definition.display_name.is_empty():
			label = definition.display_name
		var profile := App.ensure_profile()
		var locked := definition.unlock_cost > 0 and not profile.unlocked_characters.has(id)
		if locked:
			label += " · 解锁 %d 回响（持有 %d）" % [definition.unlock_cost, profile.currency]
		characters.append({"id": id, "label": label, "locked": locked, "disabled": locked and profile.currency < definition.unlock_cost})
	screen.setup(characters, App.ensure_profile().unlocked_difficulty)
	screen.chosen.connect(func(id: StringName) -> void:
		App.selected_difficulty = screen.difficulty()
		# 先取出 seed：剧情播放前 _clear_screen 会释放角色选择屏，回调里不能再引用 screen。
		var run_seed := screen.seed_text()
		_show_plot_intro(func() -> void: start_run(id, run_seed))
	)
	screen.unlock_requested.connect(func(id: StringName) -> void:
		App.unlock_character(id)
		_show_character_select()
	)
	screen.back.connect(show_main_menu)


## 开场剧情：纯表现层，播完回调 next（开新 run）。期间隐藏常驻顶栏，结束后恢复。
func _show_plot_intro(next: Callable) -> void:
	_clear_screen()
	_update_hud()
	if _top_bar != null:
		_top_bar.visible = false
	var intro: PlotIntro = PLOT_INTRO_SCENE.instantiate()
	intro.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(intro)
	intro.finished.connect(func() -> void:
		if _top_bar != null:
			_top_bar.visible = true
		next.call()
	)


func _on_character_chosen(character_id: StringName) -> void:
	start_run(character_id)


func _on_continue_run() -> void:
	if App.load_run() == null:
		show_main_menu()
		return
	_session = App.current_session
	_resume_flow()


func _show_defeat() -> void:
	AudioService.play_cue(&"defeat")
	App.end_run()
	var screen := _make_node_screen("你倒下了", "这次冒险已经结束。", show_main_menu)
	screen.set_leave_text("返回主菜单")


func _show_run_complete() -> void:
	AudioService.play_cue(&"victory")
	App.end_run()
	var screen := _make_node_screen("通关！", "你完成了三章挑战。", show_main_menu)
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
	if not RestSystem.upgradable_card_uids(run).is_empty():
		options.append({"text": "升级卡牌", "data": {"action": "upgrade_menu"}})
	options.append({"text": "什么都不做", "data": {"action": "leave"}})
	screen.set_options(options)


## 升级子菜单：只列未升级卡，按钮直接显示升级后效果，悬浮看完整前后对比。
func _show_upgrade_menu() -> void:
	_node_mode = &"rest"
	var screen := _make_node_screen(
		"休息 · 升级卡牌",
		"选择一张未升级的卡升级（悬浮可查看升级效果）。"
	)
	var options: Array = []
	for uid: int in RestSystem.upgradable_card_uids(_session.state):
		var card: RunCardState = _session.state.get_card(uid)
		if card == null:
			continue
		var definition: CardDef = ContentDB.get_card(card.card_id)
		if definition == null:
			continue
		options.append({
			"text": CardInfo.upgrade_line(definition),
			"tooltip": CardInfo.upgrade_tooltip(definition),
			"data": {"action": "upgrade", "uid": uid},
		})
	options.append({"text": "返回", "data": {"action": "back"}})
	screen.set_options(options)


func _on_rest_chose(data: Dictionary) -> void:
	var action := StringName(data.get("action", ""))
	if action == &"upgrade_menu":
		_show_upgrade_menu()
	elif action == &"back":
		_show_rest()
	else:
		_resolve_action(action, data)


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
	screen.set_options(options)


func _on_shop_chose(data: Dictionary) -> void:
	var action := StringName(data.get("action", ""))
	if action == &"remove_menu":
		_show_remove_menu()
	elif action == &"back":
		_rebuild_shop()
	else:
		_resolve_action(action, data)


## 删卡子菜单：列出当前卡组，选一张删除。
func _show_remove_menu() -> void:
	var run := _session.state
	var screen := _make_node_screen("商店 · 删除卡牌", "选择要移除的卡。（金币：%d）" % run.gold)
	var options: Array = []
	for card: RunCardState in run.deck:
		options.append({
			"text": _card_name(card.card_id, card.upgrade_level),
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
	screen.set_leave_visible(false)
	var options: Array = []
	for i in _event_def.choices.size():
		var choice: EventChoice = _event_def.choices[i]
		options.append({"text": choice.label, "disabled": _session.state.gold + choice.gold_delta < 0, "data": {"action": "event_choice", "index": i}})
	screen.set_options(options)


func _on_event_chose(data: Dictionary) -> void:
	_resolve_action(StringName(data.get("action", "")), data)


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
			"card_id": _reward_pending.offers[i],
			"index": i,
			"data": {"action": "reward_choice", "index": i},
		})
	screen.set_card_options(options)


func _on_reward_chose(data: Dictionary) -> void:
	var action := StringName(String(data.get("action", "")))
	var result: Dictionary = {}
	if action == &"reward_choice":
		result = _session.claim_reward(_reward_pending, int(data.get("index", -1)))
	elif action == &"reward_skip":
		result = _session.claim_reward(_reward_pending, -1)
	if bool(result.get("ok", false)):
		_resume_flow()


# ---- 通用 ----------------------------------------------------------------

func _make_node_screen(title: String, body: String, on_leave: Callable = Callable()) -> NodeChoiceScreen:
	_clear_screen()
	_update_hud()
	var screen: NodeChoiceScreen = preload("res://presentation/screens/node_screen.tscn").instantiate()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	screen.set_content(title, body)
	screen.chose.connect(_on_node_chose)
	screen.leave_requested.connect(on_leave if on_leave.is_valid() else _leave_node)
	return screen


func _on_node_chose(data: Dictionary) -> void:
	if _node_mode == &"library":
		return
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
			_leave_node()


func _card_name(card_id: StringName, level: int = 0) -> String:
	var definition := ContentDB.get_card(card_id)
	if definition != null and not definition.display_name.is_empty():
		return definition.get_display_name(level)
	return String(card_id)


func _relic_name(relic_id: StringName) -> String:
	var definition := ContentDB.get_relic(relic_id)
	if definition != null and not definition.display_name.is_empty():
		return definition.display_name
	return String(relic_id)


func _update_hud() -> void:
	if _hud == null:
		return
	_top_bar.visible = _session != null and _session.state != null and _session.state.is_active()
	if _session == null or _session.state == null:
		_hud.text = ""
		return
	var run := _session.state
	_hud.visible = run.flow_phase not in [&"battle", &"deployment"]
	_hud.text = "第 %d 章 · HP %d/%d · 金币 %d · 卡组 %d 张" % [
		run.act_index + 1, run.hp, run.max_hp, run.gold, run.deck.size()
	]
	_refresh_top_bar()


func _clear_screen() -> void:
	for child: Node in get_children():
		if child != _status and child != _hud and child != _top_bar and child != _save_warning:
			remove_child(child)
			child.queue_free()
	_status.visible = false


func _show_status(text: String) -> void:
	_clear_screen()
	_status.text = text
	_status.visible = true
	_status.set_anchors_and_offsets_preset(Control.PRESET_CENTER)


func _resume_flow() -> void:
	if _session == null:
		return
	var transition := _session.resume_pending_flow()
	if not bool(transition.get("ok", false)):
		_show_status("无法恢复当前进度：%s。请检查内容目录，存档已保留。" % transition.get("error_code", ""))
		return
	match _session.state.flow_phase:
		&"route":
			_show_route()
		&"deployment":
			_show_deployment(_session.state.pending_node_id)
		&"reward":
			_show_reward(&"victory")
		&"run_over":
			if _session.state.outcome == RunSession.KIND_RUN_COMPLETE:
				_show_run_complete()
			else:
				_show_defeat()
		_:
			_on_node_entered(transition)


func _resolve_action(action: StringName, data: Dictionary = {}) -> void:
	var result := _session.resolve_node_action(action, data)
	if bool(result.get("ok", false)):
		_resume_flow()
	else:
		for child: Node in get_children():
			if child is NodeChoiceScreen:
				child.set_status("操作未完成：%s" % result.get("error_code", ""))


func _leave_node() -> void:
	if _session == null:
		return
	if _session.state.flow_phase == &"reward":
		_on_reward_chose({"action": "reward_skip"})
	elif _session.state.flow_phase == &"event":
		return # 事件必须明确选择，不能无声消耗节点。
	else:
		_resolve_action(&"leave")


func _show_save_error(message: String) -> void:
	if _save_warning != null:
		_save_warning.dialog_text = message + "\n当前进度仍在内存中，请重试成功后再退出。"
		_save_warning.popup_centered(Vector2i(620, 220))


func _retry_save() -> void:
	if _session != null and _session.state.flow_phase == &"run_over":
		App.end_run()
	elif _session != null:
		_session.save()
	elif App.current_run != null:
		App.end_run()
	else:
		App.recover_ended_run()


func _show_pause() -> void:
	if _session == null or get_tree().paused:
		return
	var screen: NodeChoiceScreen = preload("res://presentation/screens/node_screen.tscn").instantiate()
	screen.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(screen)
	move_child(screen, get_child_count() - 1)
	get_tree().paused = true
	screen.set_content("暂停", "每次操作结算后会自动保存。")
	screen.set_options([
		{"text": "继续游戏", "data": {"action": "resume"}},
		{"text": "设置", "data": {"action": "settings"}},
		{"text": "保存并返回主菜单", "data": {"action": "menu"}},
	])
	screen.set_leave_visible(false)
	screen.chose.connect(func(data: Dictionary) -> void:
		if data["action"] == "settings":
			_open_settings()
			return
		if data["action"] == "menu" and not _session.save():
			screen.set_status("保存失败，请重试。")
			return
		get_tree().paused = false
		remove_child(screen)
		screen.queue_free()
		if data["action"] == "menu":
			show_main_menu()
	)


func _open_settings() -> void:
	var screen: SettingsScreen = preload("res://presentation/screens/settings_screen.tscn").instantiate()
	screen.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(screen)
	move_child(screen, get_child_count() - 1)
	screen.closed.connect(func() -> void:
		remove_child(screen)
		screen.queue_free()
	)


func _show_history() -> void:
	var profile := App.ensure_profile()
	var screen := _make_node_screen("冒险记录", "回响：%d · 已解锁难度：%d" % [profile.currency, profile.unlocked_difficulty], show_main_menu)
	var options: Array = []
	for entry: Dictionary in profile.history:
		options.append({"text": "%s · %s · 第%d幕 · %d战 · 种子 %s" % [entry.get("time", ""), entry.get("outcome", ""), entry.get("act", 1), entry.get("battles", 0), entry.get("seed", "")], "disabled": true})
	screen.set_options(options)
	screen.set_leave_text("返回")


func _show_library(kind: StringName = &"cards") -> void:
	var screen := _make_node_screen("图鉴", "查看卡牌、敌人和遗物的已注册内容。", show_main_menu)
	_node_mode = &"library"
	var options: Array = [
		{"text": "卡牌", "data": {"kind": &"cards"}},
		{"text": "敌人", "data": {"kind": &"enemies"}},
		{"text": "遗物", "data": {"kind": &"relics"}},
	]
	var ids: Array = ContentDB.reward_card_ids() if kind == &"cards" else (ContentDB.enemy_ids() if kind == &"enemies" else ContentDB.relic_ids())
	for id: StringName in ids:
		var label := ""
		if kind == &"cards":
			var card := ContentDB.get_card(id)
			label = "%s · %d 能量\n%s" % [card.display_name, card.base_cost, card.description]
		elif kind == &"enemies":
			var enemy := ContentDB.get_enemy(id)
			var unit := ContentDB.get_unit(enemy.unit_def_id)
			label = "%s · HP %d" % [enemy.display_name, unit.base_stat(StatSystem.STAT_MAX_HP)]
		else:
			var relic := ContentDB.get_relic(id)
			if not relic.enabled:
				continue
			label = "%s\n%s" % [relic.display_name, relic.description]
		options.append({"text": label, "disabled": true})
	screen.set_options(options)
	screen.chose.connect(func(data: Dictionary) -> void: _show_library(data.get("kind", &"cards")))
	screen.set_leave_text("返回")


func _show_help(on_done: Callable) -> void:
	var screen := _make_node_screen("操作说明", "1. 沿路线选择节点；战斗前从棋盘外圈部署。\n2. 拖动单张手牌到敌人或格子，松手出牌；无目标牌可拖到棋盘内。\n   点击手牌仍选择组合，点击目标后按出牌键确认。\n3. 攻击与招式可组合；防御单独成组；技能单独出。\n4. 没有选牌时点击空格移动；能量不足的牌变暗并禁止选入组合。\n   拖到棋盘外取消；完整卡牌说明在悬浮详情中查看。\n5. Q 出牌，E 结束回合，Backspace 清除选择；设置中可改键。\n6. Tab 切换焦点；棋盘方向键移动光标，Enter 确认；数字键选前 9 张手牌。\n7. 手柄方向键导航，A 确认，X 出牌，Y 结束回合，B 清除。\n8. 每次操作后自动保存；暂停菜单可返回主菜单继续。", func() -> void:
		App.ensure_profile().tutorial_seen = true
		SaveService.save_profile(App.current_profile)
		on_done.call()
	)
	screen.set_options([])
	screen.set_leave_text("开始 / 返回")
