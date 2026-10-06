extends SceneTree
## 将 content/cards/card_catalog_49.json 同步为正式 CardDef 资源并注册进 ContentCatalog。
## 只同步策划已经明确的数据；不会猜测未实现卡牌的 TargetSpec / EffectDef。

const SOURCE_PATH := "res://content/cards/card_catalog_49.json"
const OUTPUT_DIR := "res://content/cards/reward"
const CATALOG_PATH := "res://content/catalog.tres"

const CATEGORY_MAP := {
	"skill": CardDef.CardCategory.SKILL,
	"technique": CardDef.CardCategory.TECHNIQUE,
	"attack": CardDef.CardCategory.ATTACK,
	"defense": CardDef.CardCategory.DEFENSE,
}
const TARGET_KIND_MAP := {
	"none": CardDef.ContentTargetKind.NONE,
	"unit": CardDef.ContentTargetKind.UNIT,
	"cell": CardDef.ContentTargetKind.CELL,
	"direction": CardDef.ContentTargetKind.DIRECTION,
}
const TARGET_TEAM_MAP := {
	"any": 0,
	"ally": 1,
	"enemy": 2,
	"self": 3,
}


func _init() -> void:
	var source_text := FileAccess.get_file_as_string(SOURCE_PATH)
	var parsed: Variant = JSON.parse_string(source_text)
	if not parsed is Dictionary:
		printerr("reward-card import: invalid JSON")
		quit(1)
		return
	var rows: Array = (parsed as Dictionary).get("cards", [])
	if rows.size() != 49:
		printerr("reward-card import: expected 49 cards, got %d" % rows.size())
		quit(1)
		return

	var catalog := load(CATALOG_PATH) as ContentCatalog
	if catalog == null:
		printerr("reward-card import: cannot load catalog")
		quit(1)
		return

	var output_dir_abs := ProjectSettings.globalize_path(OUTPUT_DIR)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(output_dir_abs)
	if mkdir_error != OK:
		printerr("reward-card import: cannot create output dir (%d)" % mkdir_error)
		quit(1)
		return

	var by_id: Dictionary = {}
	for definition: CardDef in catalog.cards:
		if definition != null:
			by_id[definition.card_id] = definition

	var imported := 0
	for row_value: Variant in rows:
		if not row_value is Dictionary:
			continue
		var row := row_value as Dictionary
		var number := int(row.get("number", 0))
		var card_id := StringName(String(row.get("card_id", "")))
		if number < 1 or number > 49 or card_id.is_empty():
			printerr("reward-card import: invalid card row: %s" % row)
			quit(1)
			return
		var category_text := String(row.get("category", ""))
		if not CATEGORY_MAP.has(category_text):
			printerr("reward-card import: invalid category for %s" % card_id)
			quit(1)
			return

		var resource_path := "%s/card_%02d.tres" % [OUTPUT_DIR, number]
		var definition := load(resource_path) as CardDef if ResourceLoader.exists(resource_path) else CardDef.new()
		definition.card_id = card_id
		definition.card_number = number
		definition.card_category = int(CATEGORY_MAP[category_text]) as CardDef.CardCategory
		definition.visual_key = StringName(String(row.get("visual_key", "card_%02d" % number)))
		definition.icon_key = StringName("icon_%02d" % number)
		definition.display_name = String(row.get("display_name", card_id))
		definition.description = String(row.get("effect_text", ""))
		definition.base_cost = maxi(0, int(row.get("base_cost", 0)))
		definition.reward_pool_enabled = bool(row.get("reward_pool_enabled", false))
		definition.tags = [StringName(category_text)]
		definition.effects = _runtime_effects(row)
		definition.exhaust_on_play = bool(row.get("exhaust_on_play", false))
		definition.play_count_weight = clampi(int(row.get("play_count_weight", 1)), 0, 8)
		_apply_runtime_target(definition, row)
		definition.target_rule = null

		var save_error := ResourceSaver.save(definition, resource_path)
		if save_error != OK:
			printerr("reward-card import: failed to save %s (%d)" % [resource_path, save_error])
			quit(1)
			return
		var saved := load(resource_path) as CardDef
		by_id[card_id] = saved
		imported += 1

	# 保留原有 catalog 顺序，再把 01~49 放在末尾且按永久编号排序。
	var next_cards: Array[CardDef] = []
	for old: CardDef in catalog.cards:
		if old != null and not String(old.card_id).begins_with("card.reward."):
			next_cards.append(old)
	for number in range(1, 50):
		var id := StringName("card.reward.%02d" % number)
		var formal := by_id.get(id) as CardDef
		if formal == null:
			printerr("reward-card import: missing saved card %s" % id)
			quit(1)
			return
		next_cards.append(formal)
	catalog.cards = next_cards
	var catalog_error := ResourceSaver.save(catalog, CATALOG_PATH)
	if catalog_error != OK:
		printerr("reward-card import: failed to save catalog (%d)" % catalog_error)
		quit(1)
		return

	print("reward-card import: %d cards synced; catalog cards=%d" % [imported, catalog.cards.size()])
	quit(0)


func _runtime_effects(row: Dictionary) -> Array[EffectDef]:
	var effects: Array[EffectDef] = []
	for raw_value: Variant in Array(row.get("runtime_effects", [])):
		if not raw_value is Dictionary:
			continue
		var raw := raw_value as Dictionary
		var type_key := StringName(String(raw.get("type", "")).strip_edges())
		if type_key.is_empty():
			continue
		var effect := ConfiguredEffectDef.new()
		effect.type_key = type_key
		effect.params = Dictionary(raw.get("params", {})).duplicate(true)
		effects.append(effect)
	return effects


func _apply_runtime_target(definition: CardDef, row: Dictionary) -> void:
	var raw_value: Variant = row.get("runtime_target", {})
	if not raw_value is Dictionary:
		definition.content_target_kind = CardDef.ContentTargetKind.NONE
		return
	var raw := raw_value as Dictionary
	var kind_key := String(raw.get("kind", "none")).to_lower()
	definition.content_target_kind = int(
		TARGET_KIND_MAP.get(kind_key, CardDef.ContentTargetKind.NONE)
	) as CardDef.ContentTargetKind
	var team_key := String(raw.get("team", "enemy")).to_lower()
	definition.content_target_team = int(TARGET_TEAM_MAP.get(team_key, 2))
	definition.attack_range = maxi(0, int(raw.get("range", 1)))
	definition.requires_los = bool(raw.get("requires_los", true))
