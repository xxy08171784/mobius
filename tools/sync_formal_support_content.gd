extends SceneTree
## 将正式卡牌依赖的 token / 状态资源加入 ContentCatalog；可重复运行。

const CATALOG_PATH := "res://content/catalog.tres"
const CARD_PATHS := [
	"res://content/cards/tokens/fist.tres",
]
const STATUS_PATHS := [
	"res://content/statuses/stun.tres",
	"res://content/statuses/slow.tres",
	"res://content/statuses/knife_mark.tres",
]


func _init() -> void:
	var catalog := load(CATALOG_PATH) as ContentCatalog
	if catalog == null:
		printerr("formal support sync: missing catalog")
		quit(1)
		return
	for path: String in CARD_PATHS:
		var definition := load(path) as CardDef
		if definition == null:
			printerr("formal support sync: missing card %s" % path)
			quit(1)
			return
		var exists := false
		for current: CardDef in catalog.cards:
			if current != null and current.card_id == definition.card_id:
				exists = true
				break
		if not exists:
			catalog.cards.append(definition)
	for path: String in STATUS_PATHS:
		var definition := load(path) as StatusDef
		if definition == null:
			printerr("formal support sync: missing status %s" % path)
			quit(1)
			return
		var exists := false
		for current: StatusDef in catalog.statuses:
			if current != null and current.status_id == definition.status_id:
				exists = true
				break
		if not exists:
			catalog.statuses.append(definition)
	var error := ResourceSaver.save(catalog, CATALOG_PATH)
	if error != OK:
		printerr("formal support sync: save failed %d" % error)
		quit(1)
		return
	print("formal support sync: cards=%d statuses=%d" % [catalog.cards.size(), catalog.statuses.size()])
	quit(0)
