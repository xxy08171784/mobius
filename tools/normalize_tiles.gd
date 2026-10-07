extends SceneTree
## 一次性归一化工具：把一批几何不齐的地块 PNG 重裁到冻结规格（见 docs/battle_board_art_requirements.md §2）。
## 画布 340×300；顶面菱形 300×200；菱形四角 (170,20)/(320,120)/(170,220)/(20,120)。
## 做法：量菱形 bbox → **各向异性**缩放使菱形精确为 300×200（x/y 各自缩放到目标，
##      源图透视本就不一致，均匀缩放凑不齐统一菱形；各向误差 ≤~7%）→ 底对齐 y=220、中心 x=170。
##
## 用法：<godot> --headless --path D:/mobius --script res://tools/normalize_tiles.gd -- <源目录> [输出目录]

const CANVAS_W := 340
const CANVAS_H := 300
const DIAMOND_W := 300
const DIAMOND_H := 200
const ANCHOR_X := 170
const ANCHOR_BOTTOM_Y := 220  # 菱形底边所在 y；下方 80px 为侧壁区


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var src_dir: String = args[0] if args.size() > 0 else "res://assets/textures/tiles/act1"
	var out_dir: String = args[1] if args.size() > 1 else src_dir.path_join("normalized")

	var dir := DirAccess.open(src_dir)
	if dir == null:
		print("[norm] 打不开源目录: %s" % src_dir)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)

	var names: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".png"):
			names.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	names.sort()

	print("[norm] 源 %s -> 输出 %s，共 %d 张" % [src_dir, out_dir, names.size()])
	var ok := 0
	for fname: String in names:
		var img := Image.load_from_file(src_dir.path_join(fname))
		if img == null:
			print("[norm] 载入失败: %s" % fname)
			continue
		var result := _normalize(img, fname)
		if bool(result.get("ok", false)):
			var out_path := out_dir.path_join(fname)
			var err: int = result["image"].save_png(out_path)
			if err == OK:
				ok += 1
				print("[norm] %s  菱形 %dx%d  拉伸 x %.1f%% y %.1f%%  -> %s" % [
					fname, result["W_d"], result["H_d"],
					float(result["stretch_x"]) * 100.0, float(result["stretch_y"]) * 100.0,
					out_path
				])
			else:
				print("[norm] %s 保存失败 err=%d" % [fname, err])
		else:
			print("[norm] %s 处理失败" % fname)
	print("[norm] 完成：%d/%d" % [ok, names.size()])
	quit(0 if ok == names.size() else 1)


func _normalize(img: Image, fname_b: String) -> Dictionary:
	var geo := _measure(img)
	var w_d: int = geo["W"]
	var h_d: int = geo["H"]
	if w_d <= 0 or h_d <= 0:
		return {"ok": false}

	var box_x := int(geo["x0"])
	var box_y := int(geo["y0"])
	var box_w := int(geo["x1"]) - box_x + 1
	var box_h := int(geo["y1"]) - box_y + 1

	# 各向异性：x/y 各自缩放到目标菱形尺寸。源图透视不一，均匀缩放凑不齐。
	var sx := float(DIAMOND_W) / float(w_d)
	var sy := float(DIAMOND_H) / float(h_d)
	var content := img.get_region(Rect2i(box_x, box_y, box_w, box_h))
	content.resize(
		maxi(1, roundi(box_w * sx)),
		maxi(1, roundi(box_h * sy)),
		Image.INTERPOLATE_LANCZOS
	)

	# 菱形精确 300×200 → 四角固定：(170,20)/(320,120)/(170,220)/(20,120)，落点 (20,20)。
	var dst := Image.create_empty(CANVAS_W, CANVAS_H, false, Image.FORMAT_RGBA8)
	var dst_x := roundi(float(ANCHOR_X) - float(DIAMOND_W) * 0.5)
	var dst_y := roundi(float(ANCHOR_BOTTOM_Y) - float(DIAMOND_H))
	dst.blit_rect(content, Rect2i(0, 0, content.get_width(), content.get_height()), Vector2i(dst_x, dst_y))

	var stretch_x := absf(sx - 1.0)
	var stretch_y := absf(sy - 1.0)
	if stretch_x > 0.10 or stretch_y > 0.10:
		push_warning("[norm] %s 各向拉伸超 10%%（x %.1f%%, y %.1f%%），建议重新出图" % [
			fname_b, stretch_x * 100.0, stretch_y * 100.0
		])
	return {
		"ok": true,
		"image": dst,
		"W_d": w_d,
		"H_d": h_d,
		"scale": sx,
		"stretch_x": stretch_x,
		"stretch_y": stretch_y,
	}


## 与 tools/measure_tiles.gd 同款：alpha 轮廓菱形测量。
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
	# 找"最宽行"用于推算菱形高：用容差取**首个接近最大值**的行。
	# 起因：菱形顶面+侧壁的六边形轮廓里，侧壁宽度与顶面对角线几乎相同；
	# 逐像素严格取最大会被侧壁 1px 抖动带到平台底部，把厚度当成菱形高，
	# 导致偏高的假象（实测 2地块新3/新4）。
	var band := first
	var tolerance := 2
	for y in range(first, last + 1):
		if row_max[y] - row_min[y] + 1 >= max_w - tolerance:
			band = y
			break
	var H := 2 * (band - first)
	var x0 := 99999
	var x1 := -1
	for y in range(first, last + 1):
		if row_min[y] >= 0:
			x0 = mini(x0, row_min[y])
			x1 = maxi(x1, row_max[y])
	return {"x0": x0, "x1": x1, "y0": first, "y1": last, "W": max_w, "H": H}
