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
				draw_line(from, _centers[nid], color, width, true)
