extends SceneTree
## 注册 5 种通用初始牌，并让旧 warrior 原型牌退出正式奖励池。

const CATALOG_PATH := "res://content/catalog.tres"
const STARTER_PATHS := [
	"res://content/cards/starter/punch.tres",
	"res://content/cards/starter/attack.tres",
	"res://content/cards/starter/charge.tres",
	"res://content/cards/starter/relentless.tres",
	"res://content/cards/starter/defend.tres",
]


func _init() -> void:
	var catalog := load(CATALOG_PATH) as ContentCatalog
	if catalog == null:
		printerr("starter sync: catalog missing")
		quit(1)
		return
	var starters: Dictionary = {}
	for path: String in STARTER_PATHS:
		var definition := load(path) as CardDef
		if definition == null:
			printerr("starter sync: missing %s" % path)
			quit(1)
			return
		starters[definition.card_id] = definition
	var next_cards: Array[CardDef] = []
	for definition: CardDef in catalog.cards:
		if definition == null:
			continue
		if String(definition.card_id).begins_with("card.starter."):
			continue
		if String(definition.card_id).begins_with("card.warrior."):
			definition.reward_pool_enabled = false
			if not definition.resource_path.is_empty():
				ResourceSaver.save(definition, definition.resource_path)
		next_cards.append(definition)
	for path: String in STARTER_PATHS:
		var definition := load(path) as CardDef
		next_cards.append(definition)
	catalog.cards = next_cards
	var error := ResourceSaver.save(catalog, CATALOG_PATH)
	if error != OK:
		printerr("starter sync: save failed %d" % error)
		quit(1)
		return
	print("starter sync: catalog cards=%d" % catalog.cards.size())
	quit(0)
