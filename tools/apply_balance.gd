extends SceneTree
## 一次性将指定 JSON 调参表同步到 Resource；运行游戏只读取 .tres。
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Usage: -s res://tools/apply_balance.gd -- res://tools/balance_v03.json")
		quit(1)
		return
	var rows: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if not rows is Array:
		quit(1)
		return
	for row: Dictionary in rows:
		var definition := load(String(row["path"])) as CardDef
		if definition == null:
			quit(1)
			return
		for key: String in row.get("base", {}):
			definition.set(key, _effects(row["base"][key]) if key == "effects" else row["base"][key])
		var upgraded: Dictionary = row["upgrade"].duplicate(true)
		if upgraded.has("effects"):
			upgraded["effects"] = _effects(upgraded["effects"])
		definition.upgrade_overrides = {1: upgraded}
		if ResourceSaver.save(definition, row["path"]) != OK:
			quit(1)
			return
	print("BALANCE_SYNC_OK cards=", rows.size())
	quit(0)


func _effects(rows: Array) -> Array[EffectDef]:
	var result: Array[EffectDef] = []
	for row: Dictionary in rows:
		var effect := ConfiguredEffectDef.new()
		effect.type_key = StringName(row["type_key"])
		effect.params = row.get("params", {}).duplicate(true)
		result.append(effect)
	return result
