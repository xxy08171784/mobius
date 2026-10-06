extends SceneTree
## 一次性怪物动画归一化工具（用完即删）。
## 把 <源目录> 的 l*.png / r*.png（任意画布：1280/2560/5120）归一化到玩家单位同款规格：
##   1280×1280 画布、脚底 y=FEET_Y、水平居中 x=640；内容按最长边只降不升（≤ MAX_DIM）。
## 这样 UnitView 现有的玩家常量（SPRITE_SCALE 0.22 / SPRITE_FEET_OFFSET (0,-579)）对怪物直接生效。
## 每朝向以"该朝向全部帧的并集 bbox"统一裁剪/缩放，保证待机循环内脚底锚定不抖动。
##
## 用法：<godot> --headless --path D:/mobius --script res://tools/normalize_monsters.gd -- <源目录> <appearance_key> [输出目录]

const CANVAS := 1280
const FEET_Y := 1219    # 与玩家一致：脚底所在 y
const MAX_DIM := 940    # 内容最长边上限（只降不升，保持自然比例/相对大小）


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("[norm-m] 用法: -- <源目录> <appearance_key> [输出目录]")
		quit(1)
		return
	var src_dir: String = args[0]
	var key: String = args[1]
	var out_dir: String = (
		args[2] if args.size() > 2
		else "res://assets/textures/units/%s" % key
	)

	var dir := DirAccess.open(src_dir)
	if dir == null:
		print("[norm-m] 打不开源目录: %s" % src_dir)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)

	var left: Array[String] = []
	var right: Array[String] = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.ends_with(".png"):
			name = dir.get_next()
			continue
		if name.begins_with("l"):
			left.append(name)
		elif name.begins_with("r"):
			right.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	left.sort()
	right.sort()

	var ok := _normalize_group(src_dir, out_dir, left)
	ok = _normalize_group(src_dir, out_dir, right) and ok
	print("[norm-m] %s 完成: L%d R%d -> %s" % [key, left.size(), right.size(), out_dir])
	quit(0 if ok else 1)


## 一组帧（同一朝向）：按方向级并集 bbox 归一化。
func _normalize_group(src_dir: String, out_dir: String, names: Array[String]) -> bool:
	if names.is_empty():
		return true
	var images: Array[Image] = []
	var union_box := Rect2i(0, 0, 0, 0)
	for fname: String in names:
		var img := Image.load_from_file(src_dir.path_join(fname))
		if img == null:
			print("[norm-m] 载入失败: %s" % fname)
			continue
		images.append(img)
		var box := _content_box(img)
		if union_box.size.x <= 0 and union_box.size.y <= 0:
			union_box = box
		else:
			union_box = _union(union_box, box)
	if images.is_empty():
		return false

	var ok := true
	for i in range(images.size()):
		var img := images[i]
		var content := img.get_region(union_box)
		var scale := minf(1.0, float(MAX_DIM) / float(maxi(content.get_width(), content.get_height())))
		if scale < 1.0:
			content.resize(
				maxi(1, roundi(content.get_width() * scale)),
				maxi(1, roundi(content.get_height() * scale)),
				Image.INTERPOLATE_LANCZOS
			)
		var dst := Image.create_empty(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
		var dst_x := (CANVAS - content.get_width()) / 2
		var dst_y := FEET_Y - content.get_height()
		dst.blit_rect(content, Rect2i(0, 0, content.get_width(), content.get_height()), Vector2i(dst_x, dst_y))
		var err := dst.save_png(out_dir.path_join(names[i]))
		if err == OK:
			print("[norm-m] %s  内容 %dx%d 缩放 %.2f -> %s" % [
				names[i], content.get_width(), content.get_height(), scale, out_dir.path_join(names[i])
			])
		else:
			print("[norm-m] %s 保存失败 err=%d" % [names[i], err])
			ok = false
	return ok


## alpha 轮廓 bbox（RGBA8 字节扫描，比 get_pixel 快）。
func _content_box(img: Image) -> Rect2i:
	img.convert(Image.FORMAT_RGBA8)
	var data := img.get_data()
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in range(h):
		var row := y * w * 4
		for x in range(w):
			if data[row + x * 4 + 3] > 127:
				if x < x0:
					x0 = x
				if x > x1:
					x1 = x
				if y < y0:
					y0 = y
				if y > y1:
					y1 = y
	if x1 < 0:
		return Rect2i(0, 0, 0, 0)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


func _union(a: Rect2i, b: Rect2i) -> Rect2i:
	var x0 := mini(a.position.x, b.position.x)
	var y0 := mini(a.position.y, b.position.y)
	var x1 := maxi(a.position.x + a.size.x, b.position.x + b.size.x)
	var y1 := maxi(a.position.y + a.size.y, b.position.y + b.size.y)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)
