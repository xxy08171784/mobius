extends SceneTree
## 临时 ASCII dump：把 MapGenerator 生成的图打印出来肉眼比对 StS。
## 用法：godot --headless --path D:/mobius --script res://tools/dump_map.gd
## 用完即删（parse error 会污染整个项目扫描）。


func _initialize() -> void:
	var def := RouteMapDef.new()
	for s in [1, 42, 12345]:
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var g := MapGenerator.generate(def, rng)
		print("=== seed %d  nodes=%d ===" % [s, g.nodes.size()])
		_dump(g, def)
		# 统计每行宽度
		var widths := {}
		for nid in g.nodes:
			var n: MapNodeState = g.nodes[nid]
			widths[n.row] = int(widths.get(n.row, 0)) + 1
		var ws: Array = []
		for r in range(def.rows + 1):
			ws.append("%d:%d" % [r, int(widths.get(r, 0))])
		print("row widths  " + " ".join(ws))
		print("")


func _dump(g: RouteGraph, def: RouteMapDef) -> void:
	# 自顶向下打印：row = rows (boss) 到 0
	for row in range(def.rows, -1, -1):
		var ns := g.get_nodes_at_row(row)
		if ns.is_empty() and row != def.rows:
			continue
		var by_col := {}
		for n in ns:
			by_col[n.col] = n
		var line := "r%02d " % row
		if row == def.rows:
			line += "(boss)"
		else:
			for c in def.cols:
				if by_col.has(c):
					line += "%s " % _ch(by_col[c].type_key)
				else:
					line += ". "
		print(line)


func _ch(t: StringName) -> String:
	match t:
		RouteMapDef.TYPE_MONSTER: return "M"
		RouteMapDef.TYPE_ELITE: return "E"
		RouteMapDef.TYPE_REST: return "R"
		RouteMapDef.TYPE_SHOP: return "$"
		RouteMapDef.TYPE_TREASURE: return "T"
		RouteMapDef.TYPE_EVENT: return "?"
		RouteMapDef.TYPE_BOSS: return "B"
	return " "
