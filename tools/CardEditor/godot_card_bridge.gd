extends SceneTree
## Card Editor -> Godot 资源桥。
## Python 只传 JSON；真正的 CardDef / EffectDef / ContentCatalog 都由 Godot 自己构建并保存。


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		quit(2)
		return
	var request_path := String(args[0])
	var raw := FileAccess.get_file_as_string(request_path)
	var request: Variant = JSON.parse_string(raw)
	if not request is Dictionary:
		quit(2)
		return
	var data := request as Dictionary
	var result_path := String(data.get("result_path", ""))
	var result := _save_card(data)
	if not result_path.is_empty():
		var file := FileAccess.open(result_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(result, "\t"))
	quit(0 if bool(result.get("ok", false)) else 1)


func _save_card(data: Dictionary) -> Dictionary:
	var card_id := StringName(String(data.get("card_id", "")))
	if card_id.is_empty():
		return {"ok": false, "error": "card_id 不能为空"}
	var resource_path := String(data.get("resource_path", ""))
	if resource_path.is_empty() or not resource_path.begins_with("res://content/cards/"):
		return {"ok": false, "error": "resource_path 必须位于 res://content/cards/"}

	var absolute_dir := ProjectSettings.globalize_path(resource_path.get_base_dir())
	var make_dir_error := DirAccess.make_dir_recursive_absolute(absolute_dir)
	if make_dir_error != OK:
		return {"ok": false, "error": "无法创建卡牌目录: %s" % make_dir_error}

	var catalog := load("res://content/catalog.tres") as ContentCatalog
	if catalog == null:
		return {"ok": false, "error": "content/catalog.tres 加载失败"}

	for other: CardDef in catalog.cards:
		if other == null:
			continue
		if other.card_id == card_id and other.resource_path != resource_path:
			return {
				"ok": false,
				"error": "card_id 已存在于其他资源: %s" % other.resource_path,
			}

	var card: CardDef = null
	if ResourceLoader.exists(resource_path):
		card = load(resource_path) as CardDef
	if card == null:
		card = CardDef.new()

	card.card_id = card_id
	card.card_number = maxi(0, int(data.get("card_number", 0)))
	card.card_category = clampi(
		int(data.get("card_category", CardDef.CardCategory.UNASSIGNED)),
		CardDef.CardCategory.UNASSIGNED,
		CardDef.CardCategory.DEFENSE
	) as CardDef.CardCategory
	card.visual_key = StringName(String(data.get("visual_key", "")).strip_edges())
	card.display_name = String(data.get("display_name", String(card_id)))
	card.description = String(data.get("description", ""))
	card.base_cost = maxi(0, int(data.get("base_cost", 0)))
	card.reward_pool_enabled = bool(data.get("reward_pool_enabled", card.reward_pool_enabled))
	card.exhaust_on_play = bool(data.get("exhaust_on_play", false))
	card.attack_range = maxi(0, int(data.get("attack_range", 1)))
	card.requires_los = bool(data.get("requires_los", true))
	card.play_count_weight = clampi(int(data.get("play_count_weight", 1)), 0, 8)
	card.content_target_kind = int(data.get("target_kind", 0)) as CardDef.ContentTargetKind
	card.content_target_team = clampi(int(data.get("target_team", 2)), 0, 3)

	var tags: Array[StringName] = []
	for value: Variant in Array(data.get("tags", [])):
		var tag := StringName(String(value).strip_edges())
		if not tag.is_empty():
			tags.append(tag)
	card.tags = tags

	var effects: Array[EffectDef] = []
	for raw_effect: Variant in Array(data.get("effects", [])):
		if not raw_effect is Dictionary:
			continue
		var effect_data := raw_effect as Dictionary
		var type_key := StringName(String(effect_data.get("type", "")))
		if type_key.is_empty():
			continue
		var params: Dictionary = Dictionary(effect_data.get("params", {})).duplicate(true)
		if params.has("status_id"):
			params["status_id"] = StringName(String(params["status_id"]))
		var effect := ConfiguredEffectDef.new()
		effect.type_key = type_key
		effect.params = params
		effects.append(effect)
	card.effects = effects

	var save_error := ResourceSaver.save(card, resource_path)
	if save_error != OK:
		return {"ok": false, "error": "CardDef 保存失败: %s" % save_error}

	var saved_card := load(resource_path) as CardDef
	if saved_card == null:
		return {"ok": false, "error": "保存后无法重新加载 CardDef"}
	var replaced := false
	for index: int in range(catalog.cards.size()):
		var existing := catalog.cards[index]
		if existing != null and existing.resource_path == resource_path:
			catalog.cards[index] = saved_card
			replaced = true
			break
	if not replaced:
		catalog.cards.append(saved_card)

	var catalog_error := ResourceSaver.save(catalog, "res://content/catalog.tres")
	if catalog_error != OK:
		return {"ok": false, "error": "catalog.tres 保存失败: %s" % catalog_error}
	return {
		"ok": true,
		"card_id": String(card_id),
		"resource_path": resource_path,
		"catalog_count": catalog.cards.size(),
	}
