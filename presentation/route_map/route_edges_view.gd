class_name RouteEdgesView
extends Control
## 绘制节点之间的连接线。本轮用纯色（未采用贴图）。

var _graph: RouteGraph = null
var _centers: Dictionary[int, Vector2] = {}

var color: Color = Color(0.82, 0.77, 0.62, 0.75)
var width: float = 4.0


## 由 route_map.gd 在布局后调用；centers: 节点 ID -> 中心点（本控件坐标系）。
func setup(graph: RouteGraph, centers: Dictionary[int, Vector2], line_color: Color, line_width: float) -> void:
	_graph = graph
	_centers = centers
	color = line_color
	width = line_width
	queue_redraw()


func _draw() -> void:
	if _graph == null:
		return
	for id in _graph.nodes:
		if not _centers.has(id):
			continue
		var from: Vector2 = _centers[id]
		for nid in _graph.nodes[id].next_ids:
			if _centers.has(nid):
				_draw_edge(id, nid, from, _centers[nid])


## 用采样的二次贝塞尔画一条微弯连线，比直线更贴近 StS。
## 斜向边顺其水平方向微弯；竖直边用 (from_id,to_id) 散列出的确定性小弯，避免画成直线。
func _draw_edge(from_id: int, to_id: int, a: Vector2, b: Vector2) -> void:
	var dx := b.x - a.x
	var bow := dx * 0.25
	if absf(dx) < 0.5:
		bow = _hash_bow(from_id, to_id) * minf(20.0, a.distance_to(b) * 0.12)
	var ctrl := (a + b) * 0.5 + Vector2(bow, 0.0)
	var pts := PackedVector2Array()
	var steps := 12
	for i in steps + 1:
		var t := float(i) / float(steps)
		var u := 1.0 - t
		pts.append(u * u * a + 2.0 * u * t * ctrl + t * t * b)
	draw_polyline(pts, color, width, true)


## 由 (from_id,to_id) 决定的确定性符号（±1）；同一条边每次绘制一致。
static func _hash_bow(from_id: int, to_id: int) -> float:
	var h := (from_id * 73856093) ^ (to_id * 19349663)
	return 1.0 if (h & 1) == 1 else -1.0
