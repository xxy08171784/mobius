@tool
extends VBoxContainer
const CATEGORIES := {"卡牌": "cards", "敌人": "enemies", "单位属性": "units", "状态": "statuses", "角色": "characters", "遗物": "relics", "遭遇": "encounters", "怪物池": "monster_pools", "事件": "events", "商店": "shops"}
const SCENES := {
	"游戏入口": "res://app/main.tscn",
	"主菜单": "res://presentation/screens/main_menu.tscn",
	"角色选择": "res://presentation/screens/character_select.tscn",
	"节点 / 奖励 / 图鉴": "res://presentation/screens/node_screen.tscn",
	"设置": "res://presentation/screens/settings_screen.tscn",
	"路线地图": "res://presentation/route_map/route_map.tscn",
	"战斗 / 部署": "res://presentation/battle/battle_screen.tscn",
	"战斗信息 HUD": "res://presentation/battle/battle_hud.tscn",
	"战斗卡牌 HUD": "res://presentation/battle/battle_card_hud.tscn",
	"单张卡面": "res://presentation/cards/battle_card_view.tscn",
	"局内工具栏": "res://presentation/common/run_toolbar.tscn",
	"手牌排列": "res://presentation/cards/hand_view.tscn",
}
var _resources: Array[Resource] = []


func _ready() -> void:
	for category: String in CATEGORIES:
		%Category.add_item(category)
	for title: String in SCENES:
		%Scene.add_item(title)
	%Category.item_selected.connect(func(_index: int) -> void: _refresh())
	%Filter.text_changed.connect(func(_value: String) -> void: _refresh())
	%Refresh.pressed.connect(_refresh)
	%Items.item_activated.connect(_edit)
	%Edit.pressed.connect(func() -> void:
		var selection: PackedInt32Array = %Items.get_selected_items()
		if not selection.is_empty():
			_edit(selection[0])
	)
	%Catalog.pressed.connect(func() -> void: EditorInterface.edit_resource(load("res://content/catalog.tres")))
	%OpenScene.pressed.connect(func() -> void: EditorInterface.open_scene_from_path(SCENES[%Scene.get_item_text(%Scene.selected)]))
	%Audio.pressed.connect(func() -> void: EditorInterface.edit_resource(load("res://content/audio/default_audio.tres")))
	%Campaign.pressed.connect(func() -> void: EditorInterface.edit_resource(load("res://content/maps/campaign_default.tres")))
	%Validate.pressed.connect(_validate)
	_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return
	%Items.clear()
	_resources.clear()
	var catalog := load("res://content/catalog.tres") as ContentCatalog
	if catalog == null:
		return
	var field: String = CATEGORIES[%Category.get_item_text(%Category.selected)]
	var query: String = %Filter.text.to_lower()
	for resource: Resource in catalog.get(field):
		if resource == null:
			continue
		var id := _resource_id(resource)
		var label := "%s · %s" % [id, resource.resource_path.get_file()]
		if not query.is_empty() and not label.to_lower().contains(query):
			continue
		_resources.append(resource)
		%Items.add_item(label)
	%Status.text = "%d 项。双击在 Inspector 编辑，Ctrl+S 保存。" % _resources.size()


func _edit(index: int) -> void:
	if index >= 0 and index < _resources.size():
		EditorInterface.edit_resource(_resources[index])


func _validate() -> void:
	EditorInterface.save_all_scenes()
	var db := load("res://autoload/content_db.gd").new() as Node
	var errors: Array[String] = []
	if db.load_catalog():
		errors = ContentValidator.validate(db, load(RunSession.CAMPAIGN_PATH))
	else:
		errors.append("目录加载失败；详细原因见输出面板。")
	%Status.text = "校验通过。" if errors.is_empty() else "\n".join(errors)
	db.free()


func _resource_id(resource: Resource) -> String:
	for property: Dictionary in resource.get_property_list():
		if property.name in ["id", "card_id", "status_id", "relic_id"]:
			return String(resource.get(property.name))
	return resource.resource_name
