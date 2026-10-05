class_name RouteMapScreen
extends Control
## 选关地图屏：按当前章（CampaignDef.act_index）生成地图、摆放节点、处理点击。
## 进入 boss 节点 → 发出 act_completed 并自动推进到下一章（原型用）。
## 规则走 RouteGraph.can_enter/enter；不依赖 RunSession（后续接线点）。

## 选中节点后发出（携带 MapNodeState）。
signal node_selected(node: MapNodeState)
## 进入 boss、本章完成时发出（携带本章号）。
signal act_completed(act_index: int)

## 三章配置。缺省时用 3 份默认 RouteMapDef。
@export var campaign: CampaignDef = null
@export var skin: RouteMapSkin = null
## 当前章号。
@export var act_index: int = 0
## run 种子（缺省固定，便于复现；接线 RunState 后由其决定）。
@export var run_seed: int = 12345
@export var col_spacing: float = 150.0
@export var row_spacing: float = 175.0
@export var margin: float = 140.0
@export var node_cell: float = 88.0

var graph: RouteGraph = null
var _current_id: int = -1

var _node_views: Dictionary[int, MapNodeView] = {}
var _centers: Dictionary[int, Vector2] = {}


func _ready() -> void:
	if campaign == null:
		campaign = CampaignDef.new()
	if skin == null:
		skin = RouteMapSkin.new()
		skin.load_defaults()
	set_act(act_index, run_seed)


## 切换到第 index 章（0 起）。用该章的配置 + 独立种子重新生成地图。
func set_act(index: int, seed_value: int = -1) -> void:
	act_index = maxi(index, 0)
	if seed_value >= 0:
		run_seed = seed_value
	_clear()
	_apply_background()
	_build_map()
	_scroll_to_bottom()


func rebuild() -> void:
	set_act(act_index, run_seed)


## 从外部接管（接线 RunState 后）：传已生成好的图，按当前章尺寸布局。
func set_graph(g: RouteGraph) -> void:
	graph = g
	_clear()
	_apply_background()
	_layout_views()
	_scroll_to_bottom()


func _current_def() -> RouteMapDef:
	return campaign.act_def(act_index)


func _act_seed() -> int:
	return CampaignDef.derive_act_seed(run_seed, act_index)


func _apply_background() -> void:
	$Background.texture = skin.background_for(act_index)


func _clear() -> void:
	for v in _node_views.values():
		v.queue_free()
	_node_views.clear()
	_centers.clear()
	_current_id = -1
	if $Scroll/Canvas/Edges.is_inside_tree():
		$Scroll/Canvas/Edges.queue_redraw()


func _build_map() -> void:
	var def := _current_def()
	var rng := RandomNumberGenerator.new()
	rng.seed = _act_seed()
	graph = MapGenerator.generate(def, rng)
	_layout_views()


func _layout_views() -> void:
	var def := _current_def()
	var canvas: Control = $Scroll/Canvas
	canvas.custom_minimum_size = Vector2(
		margin * 2.0 + maxf(float(def.cols - 1), 0.0) * col_spacing,
		margin * 2.0 + float(def.rows) * row_spacing)

	for id in graph.nodes:
		var n: MapNodeState = graph.nodes[id]
		var center := Vector2(
			margin + float(n.col) * col_spacing,
			margin + float(def.rows - n.row) * row_spacing)
		_centers[id] = center
		var view: MapNodeView = load("res://presentation/route_map/map_node_view.tscn").instantiate()
		view.setup(id, n.type_key, skin)
		view.size = Vector2(node_cell, node_cell)
		view.position = center - view.size * 0.5
		view.activated.connect(_on_node_activated)
		$Scroll/Canvas/Nodes.add_child(view)
		_node_views[id] = view

	$Scroll/Canvas/Edges.setup(graph, _centers, skin.path_color, skin.path_width)
	_refresh_all()


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	var vbar: ScrollBar = $Scroll.get_v_scroll_bar()
	$Scroll.scroll_vertical = int(vbar.max_value)


## 派生状态：current > visited > available > locked。
func _state_for(n: MapNodeState) -> StringName:
	if n.id == _current_id:
		return &"current"
	if n.visited:
		return &"visited"
	if graph.can_enter(n.id):
		return &"available"
	return &"locked"


func _refresh_all() -> void:
	for id in _node_views:
		_node_views[id].apply_state(_state_for(graph.get_node(id)))


func _on_node_activated(id: int) -> void:
	if not graph.enter(id):
		return
	_current_id = id
	var n := graph.get_node(id)
	_refresh_all()
	node_selected.emit(n)
	if n.type_key == RouteMapDef.TYPE_BOSS:
		act_completed.emit(act_index)
		if act_index + 1 < campaign.act_count():
			set_act(act_index + 1)
