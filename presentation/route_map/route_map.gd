class_name RouteMapScreen
extends Control
## 选关地图屏：按当前章（CampaignDef.act_index）生成地图、摆放节点、处理点击。
## 进入 boss 节点 → 发出 act_completed 并自动推进到下一章（原型用）。
## 规则走 RouteGraph.can_enter/enter；不依赖 RunSession（后续接线点）。

## 选中节点后发出（携带 MapNodeState）。
signal node_selected(node: MapNodeState)
## 进入 boss、本章完成时发出（携带本章号）。
signal act_completed(act_index: int)
## RunSession 驱动模式下，节点进入成功时发出转移 dict（{kind, battle?, content_id?}）。
signal node_entered(transition: Dictionary)
## RunSession 驱动模式下，玩家点击可进入节点时发出 id；由 RunFlow 决定进入流程
## （战斗节点需先选进场格）。视图自身不再调用 enter_node。
signal activated(node_id: int)

## 三章配置。缺省时用 3 份默认 RouteMapDef。
@export var campaign: CampaignDef = null
@export var skin: RouteMapSkin = null
## 当前章号。
@export var act_index: int = 0
## run 种子（缺省固定，便于复现；接线 RunState 后由其决定）。
@export var run_seed: int = 12345
@export var col_spacing: float = 150.0
@export var row_spacing: float = 160.0
@export var margin: float = 140.0
@export var node_cell: float = 88.0

## 每节点布局抖动幅度（按节点 ID 散列，确定性），让摆放更有机而非严格网格。
@export var col_jitter: float = 30.0
@export var row_jitter: float = 22.0

## 卷轴最上方/最下方各留的比例不放节点（入口在最下带线、boss 在最上带线）。
## 注意：这个比例是节点"图标外沿"的安全线；布局时还会再内缩半个节点尺寸，
## 否则中心放 5% 线上，88px 的图标+抖动会压进背景图的上/下装饰带。
@export var edge_fraction: float = 0.12

var graph: RouteGraph = null
var _current_id: int = -1

## RunSession 驱动模式：图/访问态/章节流转都交由 RunSession，本视图只投影。
var _session: RunSession = null

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


## 由 RunSession 驱动：图/访问态/章节流转都交给规则层，本视图只投影。
## 之后刷新必须经 refresh_from_session()（enter_node 会替换 session.state）。
func bind_run_session(session: RunSession) -> void:
	_session = session
	if session == null or session.state == null or session.state.map == null:
		return
	act_index = session.state.act_index
	graph = session.state.map
	_current_id = session.state.current_node_id
	_clear()
	_apply_background()
	_layout_views()
	_scroll_to_bottom()


## enter_node 提交后调用：重新指到新 RunState 的地图并刷新派生状态。
func refresh_from_session() -> void:
	if _session == null or _session.state == null or _session.state.map == null:
		return
	act_index = _session.state.act_index
	graph = _session.state.map
	_current_id = _session.state.current_node_id
	_refresh_all()


func _current_def() -> RouteMapDef:
	# RunSession 驱动时按实际图尺寸布局，不重新生成。
	if _session != null and _session.state != null and _session.state.map != null:
		var def := RouteMapDef.new()
		def.rows = _session.state.map.rows
		def.cols = _session.state.map.cols
		return def
	return campaign.act_def(act_index)


func _act_seed() -> int:
	return CampaignDef.derive_act_seed(run_seed, act_index)


func _apply_background() -> void:
	# 卷轴背景是 Canvas 的首个子节点：随 Scroll 一起滚动，节点图标画在它上面。
	$Scroll/Canvas/Background.texture = skin.background_for(act_index)


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
	var canvas_w := margin * 2.0 + maxf(float(def.cols - 1), 0.0) * col_spacing
	var canvas_h := margin * 2.0 + float(def.rows) * row_spacing
	var bg: Texture2D = skin.background_for(act_index)
	if bg != null and bg.get_width() > 0:
		# 画布高度按卷轴贴图等比推得：宽高比一致 → 整幅可见、不裁剪（宽度仍由列间距决定）。
		canvas_h = canvas_w * float(bg.get_height()) / float(bg.get_width())
	canvas.custom_minimum_size = Vector2(canvas_w, canvas_h)

	# 顶部/底部各 edge_fraction 不放节点；再内缩半个节点尺寸，使节点"图标外沿"
	# 恰好落在安全线上（入口 row 0 贴下带线内侧，boss 贴上带线内侧）。
	var top_edge := canvas_h * edge_fraction + node_cell * 0.5
	var bottom_edge := canvas_h * (1.0 - edge_fraction) - node_cell * 0.5
	var row_steps := maxf(float(def.rows), 1.0)

	for id in graph.nodes:
		var n: MapNodeState = graph.nodes[id]
		var t := float(n.row) / row_steps
		var center := Vector2(
			margin + float(n.col) * col_spacing,
			lerpf(bottom_edge, top_edge, t))
		if n.id == graph.boss_id:
			# boss 视觉居中（图内 col 仍是 0，只调布局），row 各节点曲线扇入。
			center.x = margin + float(def.cols - 1) * 0.5 * col_spacing
		else:
			var j := _cell_jitter(n.id)
			center += Vector2(j.x * col_jitter, j.y * row_jitter)
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


## 由节点 ID 散列出的确定性抖动 ∈ [-1,1]^2。只影响布局观感，不改图与存档。
static func _cell_jitter(id: int) -> Vector2:
	var h := absi(id) * 2654435761
	var hx := (h >> 8) & 0xFFFF
	var hy := (h >> 24) & 0xFFFF
	return Vector2(
		float(hx) / 65535.0 * 2.0 - 1.0,
		float(hy) / 65535.0 * 2.0 - 1.0)


func _scroll_to_bottom() -> void:
	await get_tree().process_frame
	var vbar: ScrollBar = $Scroll.get_v_scroll_bar()
	$Scroll.scroll_vertical = int(vbar.max_value)


## 派生状态：current > visited > available > locked。
## available 必须带当前位置（StS 式）：RunSession 驱动时问规则层，原型模式用本视图 _current_id。
func _state_for(n: MapNodeState) -> StringName:
	if n.id == _current_id:
		return &"current"
	if n.visited:
		return &"visited"
	var enterable := false
	if _session != null:
		enterable = _session.can_enter(n.id)
	elif graph != null:
		enterable = graph.can_enter(n.id, _current_id)
	return &"available" if enterable else &"locked"


func _refresh_all() -> void:
	for id in _node_views:
		_node_views[id].apply_state(_state_for(graph.get_node(id)))


func _on_node_activated(id: int) -> void:
	# RunSession 驱动模式：视图只上报点击，进入/选进场格由 RunFlow 编排。
	if _session != null:
		activated.emit(id)
		return

	# 独立原型模式（无 RunSession）：旧行为。
	if not graph.enter(id, _current_id):
		return
	_current_id = id
	var n := graph.get_node(id)
	_refresh_all()
	node_selected.emit(n)
	if n.type_key == RouteMapDef.TYPE_BOSS:
		act_completed.emit(act_index)
		if act_index + 1 < campaign.act_count():
			set_act(act_index + 1)
