extends Node
## 稳定内容 ID -> 只读定义。autoload。
## 启动时从显式 catalog 加载，既检查引用，也保证导出时保留资源。
## 约定：Def 资源只读，运行时禁止修改。

const DEFAULT_CATALOG := "res://content/catalog.tres"

var _loaded_path: String = ""
var _cards: Dictionary = {}
var _units: Dictionary = {}
var _enemies: Dictionary = {}
var _statuses: Dictionary = {}
var _relics: Dictionary = {}
var _characters: Dictionary = {}
var _encounters: Dictionary = {}
var _shops: Dictionary = {}
var _events: Dictionary = {}
var _monster_pools: Dictionary = {}
var _obstacles: Dictionary = {}
var _obstacle_pools: Dictionary = {}


func load_catalog(path: String = DEFAULT_CATALOG) -> bool:
	_clear_indexes()
	var raw := load(path)
	if not raw is ContentCatalog:
		push_error("ContentDB: catalog is missing or has wrong type: %s" % path)
		return false
	var catalog := raw as ContentCatalog
	var ok := true
	for definition: CardDef in catalog.cards:
		ok = _register(_cards, definition.card_id if definition != null else &"", definition, "card") and ok
	for definition: UnitDef in catalog.units:
		ok = _register(_units, definition.id if definition != null else &"", definition, "unit") and ok
	for definition: EnemyDef in catalog.enemies:
		ok = _register(_enemies, definition.id if definition != null else &"", definition, "enemy") and ok
	for definition: StatusDef in catalog.statuses:
		ok = _register(_statuses, definition.status_id if definition != null else &"", definition, "status") and ok
	for definition: RelicDef in catalog.relics:
		ok = _register(_relics, definition.relic_id if definition != null else &"", definition, "relic") and ok
	for definition: CharacterDef in catalog.characters:
		ok = _register(_characters, definition.id if definition != null else &"", definition, "character") and ok
	for definition: EncounterDef in catalog.encounters:
		ok = _register(_encounters, definition.id if definition != null else &"", definition, "encounter") and ok
	for definition: ShopDef in catalog.shops:
		ok = _register(_shops, definition.id if definition != null else &"", definition, "shop") and ok
	for definition: EventDef in catalog.events:
		ok = _register(_events, definition.id if definition != null else &"", definition, "event") and ok
	for definition: MonsterPoolDef in catalog.monster_pools:
		ok = _register(_monster_pools, definition.id if definition != null else &"", definition, "monster_pool") and ok
	for definition: ObstacleDef in catalog.obstacles:
		ok = _register(_obstacles, definition.id if definition != null else &"", definition, "obstacle") and ok
	for definition: ObstaclePoolDef in catalog.obstacle_pools:
		ok = _register(_obstacle_pools, definition.id if definition != null else &"", definition, "obstacle_pool") and ok
	if not ok:
		_clear_indexes()
		return false
	_loaded_path = path
	return true


func ensure_loaded(path: String = DEFAULT_CATALOG) -> bool:
	if is_loaded() and _loaded_path == path:
		return true
	return load_catalog(path)


func is_loaded() -> bool:
	return not _loaded_path.is_empty()


func get_card(id: StringName) -> CardDef:
	return _cards.get(id) as CardDef


func get_unit(id: StringName) -> UnitDef:
	return _units.get(id) as UnitDef


func get_enemy(id: StringName) -> EnemyDef:
	return _enemies.get(id) as EnemyDef


func get_status(id: StringName) -> StatusDef:
	return _statuses.get(id) as StatusDef


func get_relic(id: StringName) -> RelicDef:
	return _relics.get(id) as RelicDef


func get_character(id: StringName) -> CharacterDef:
	return _characters.get(id) as CharacterDef


func get_encounter(id: StringName) -> EncounterDef:
	return _encounters.get(id) as EncounterDef


func get_shop(id: StringName) -> ShopDef:
	return _shops.get(id) as ShopDef


func get_event(id: StringName) -> EventDef:
	return _events.get(id) as EventDef


func get_monster_pool(id: StringName) -> MonsterPoolDef:
	return _monster_pools.get(id) as MonsterPoolDef


func get_obstacle(id: StringName) -> ObstacleDef:
	return _obstacles.get(id) as ObstacleDef


func get_obstacle_pool(id: StringName) -> ObstaclePoolDef:
	return _obstacle_pools.get(id) as ObstaclePoolDef


func all_cards() -> Dictionary:
	return _cards.duplicate()


func card_ids() -> Array:
	return _sorted_ids(_cards)


## 仅返回当前真正可玩的奖励卡；设计已入库但规则未实现的卡不会污染可玩闭环。
func reward_card_ids() -> Array:
	var pool := load("res://content/pools/formal_cards.tres") as CardPoolDef
	return pool.resolve(self)


func enemy_ids() -> Array:
	return _sorted_ids(_enemies)


func status_ids() -> Array:
	return _sorted_ids(_statuses)


func relic_ids() -> Array:
	return _sorted_ids(_relics)


func character_ids() -> Array:
	return _sorted_ids(_characters)


func encounter_ids() -> Array:
	return _sorted_ids(_encounters)


func shop_ids() -> Array:
	return _sorted_ids(_shops)


func event_ids() -> Array:
	return _sorted_ids(_events)


func monster_pool_ids() -> Array:
	return _sorted_ids(_monster_pools)


func obstacle_ids() -> Array:
	return _sorted_ids(_obstacles)


func obstacle_pool_ids() -> Array:
	return _sorted_ids(_obstacle_pools)


func _register(index: Dictionary, id: StringName, definition: Variant, kind: String) -> bool:
	if definition == null or id.is_empty():
		push_error("ContentDB: invalid %s definition" % kind)
		return false
	if index.has(id):
		push_error("ContentDB: duplicate %s id: %s" % [kind, String(id)])
		return false
	if definition.has_method("is_valid") and not bool(definition.call("is_valid")):
		push_error("ContentDB: invalid %s content: %s" % [kind, String(id)])
		return false
	index[id] = definition
	return true


func _clear_indexes() -> void:
	_loaded_path = ""
	_cards.clear()
	_units.clear()
	_enemies.clear()
	_statuses.clear()
	_relics.clear()
	_characters.clear()
	_encounters.clear()
	_shops.clear()
	_events.clear()
	_monster_pools.clear()
	_obstacles.clear()
	_obstacle_pools.clear()


func _sorted_ids(index: Dictionary) -> Array:
	var ids := index.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return String(a) < String(b))
	return ids
