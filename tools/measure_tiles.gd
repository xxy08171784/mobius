extends SceneTree
## 一次性量图工具：对目录里所有 PNG 做 alpha 轮廓菱形测量，判定几何是否一致。
## 用法：<godot> --headless --path D:/mobius --script res://tools/measure_tiles.gd -- <图片目录>

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("[measure] 缺少目录参数")
		quit(1)
		return
	var dir_path: String = args[0]
	var dir := DirAccess.open(dir_path)
	if dir == null:
		print("[measure] 打不开目录: %s" % dir_path)
		quit(1)
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".png") and not name.begins_with("."):
			names.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	names.sort()

	print("[measure] 共 %d 张" % names.size())
	print("[measure] file, size, diamond WxH, bbox x0..x1 y0..y1")
	var first_geo: Dictionary = {}
	for fname: String in names:
		var img := Image.load_from_file(dir_path.path_join(fname))
		if img == null:
			print("[measure] 载入失败: %s" % fname)
			continue
		var geo := _measure(img)
		if first_geo.is_empty():
			first_geo = geo
		var flag := ""
		if geo["W"] != first_geo["W"] or geo["H"] != first_geo["H"]:
			flag = "  <-- 几何不一致"
		print("[measure] %s, %dx%d, %dx%d, x[%d..%d] y[%d..%d]%s" % [
			fname, img.get_width(), img.get_height(),
			geo["W"], geo["H"], geo["x0"], geo["x1"], geo["y0"], geo["y1"], flag
		])
	print("[measure] 基准(第一张): diamond %dx%d, bbox x[%d..%d] y[%d..%d]" % [
		first_geo["W"], first_geo["H"], first_geo["x0"], first_geo["x1"], first_geo["y0"], first_geo["y1"]
	])
	quit(0)


func _measure(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var row_min := PackedInt32Array()
	var row_max := PackedInt32Array()
	row_min.resize(h)
	row_max.resize(h)
	var first := -1
	var last := -1
	var max_w := 0
	for y in range(h):
		var lo := -1
		var hi := -1
		for x in range(w):
			if img.get_pixel(x, y).a > 0.5:
				if lo < 0:
					lo = x
				hi = x
		row_min[y] = lo
		row_max[y] = hi
		if hi >= 0:
			if first < 0:
				first = y
			last = y
			max_w = maxi(max_w, hi - lo + 1)
	var band := first
	var widest := 0
	for y in range(first, last + 1):
		var wdt := row_max[y] - row_min[y] + 1
		if wdt > widest:
			widest = wdt
			band = y
	var H := 2 * (band - first)
	var x0 := 99999
	var x1 := -1
	for y in range(first, last + 1):
		if row_min[y] >= 0:
			x0 = mini(x0, row_min[y])
			x1 = maxi(x1, row_max[y])
	return {
		"x0": x0, "x1": x1, "y0": first, "y1": last,
		"W": max_w, "H": H,
	}
