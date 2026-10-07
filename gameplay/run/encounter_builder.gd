class_name EncounterBuilder
extends RefCounted
## 纯函数：`EncounterDef + RunState ->` 与 DemoBattleSetup.build() 同形的战斗装配 dict。
## 不改入参；不引用 SceneTree（可无头测试）。战斗结算仍由 BattleSession 负责。
##
## content 为 ContentDB 型“鸭子对象”，需提供：
##   get_character(id) / get_unit(id) / get_enemy(id) / all_cards()
## 在游戏里传 ContentDB autoload；在无头测试里传 ContentDB 脚本实例（autoload 名不注入 -s 运行）。

## 玩家单位固定 ID（与 BattleSession 假设一致）。
const PLAYER_UNIT_ID := 1

## 敌人单位 ID 从这里起递增（确定性稳定顺序 = enemy_ids 顺序）。
const FIRST_ENEMY_UNIT_ID := 2

## 战斗卡 UID 起点。避开 BattleState.next_uid（状态实例 ID）空间，避免与生成卡/状态冲突。
const BATTLE_CARD_UID_BASE := 1000


## 产出：{ rng, state, card_defs, enemy_behaviors, enemy_actions, card_labels }。
## 失败（内容缺失/定义非法）返回空 dict。
## player_start：玩家进场格（开战前由表现层让玩家从外圈选）。合法（盘内）时优先使用，
## 否则回退 encounter.player_start。敌人落在非边缘的内部格（确定性随机，经 encounter 流）。
static func build(
	encounter: EncounterDef,
	run: RunState,
	rng: RngStreams,
	content: Object,
	player_start: Vector2i = Vector2i(-1, -1)
) -> Dictionary:
	if encounter == null or run == null or rng == null or content == null:
		return {}
	if not encounter.is_valid():
		push_error("EncounterBuilder: invalid encounter def")
		return {}

	var character: CharacterDef = content.get_character(run.character_id)
	if character == null:
		push_error("EncounterBuilder: unknown character: %s" % String(run.character_id))
		return {}
	var player_def: UnitDef = content.get_unit(character.unit_def_id)
	if player_def == null:
		push_error("EncounterBuilder: unknown player unit: %s" % String(character.unit_def_id))
		return {}

	var board := BoardState.new(encounter.board_cols, encounter.board_rows)
	var units: Dictionary[int, UnitState] = {}
	var start_cell := _resolve_player_start(encounter, player_start)

	var player := UnitState.create(
		PLAYER_UNIT_ID,
		player_def.id,
		UnitState.Team.PLAYER,
		run.max_hp
	)
	player.hp = clampi(run.hp, 0, run.max_hp)
	units[PLAYER_UNIT_ID] = player
	board.place_unit(PLAYER_UNIT_ID, start_cell)

	var spawns := _plan_enemy_spawns(encounter, start_cell, rng)
	var enemy_behaviors: Dictionary = {}
	var enemy_actions: Dictionary = {}
	var enemy_reactions: Dictionary = {}
	var unit_id := FIRST_ENEMY_UNIT_ID
	var index := 0
	for enemy_content_id: StringName in encounter.enemy_ids:
		var enemy_def: EnemyDef = content.get_enemy(enemy_content_id)
		if enemy_def == null:
			push_error("EncounterBuilder: unknown enemy: %s" % String(enemy_content_id))
			return {}
		var enemy_unit_def: UnitDef = content.get_unit(enemy_def.unit_def_id)
		if enemy_unit_def == null:
			push_error("EncounterBuilder: unknown enemy unit: %s" % String(enemy_def.unit_def_id))
			return {}
		var enemy := UnitState.create(
			unit_id,
			enemy_unit_def.id,
			UnitState.Team.ENEMY,
			enemy_unit_def.base_stat(StatSystem.STAT_MAX_HP)
		)
		enemy.enemy_id = enemy_content_id
		units[unit_id] = enemy
		if not board.place_unit(unit_id, spawns[index]):
			push_error("EncounterBuilder: enemy spawn is occupied")
			return {}
		enemy_behaviors[unit_id] = enemy_def.behavior
		_collect_actions(enemy_actions, enemy_def.behavior)
		enemy_reactions[unit_id] = enemy_def.reactions
		unit_id += 1
		index += 1

	# 随机障碍：敌人落点确定后、用同一条 encounter 流摆放（不依赖玩家起点，预览=实际）。
	if encounter.obstacle_count > 0 and not encounter.obstacle_pool_id.is_empty():
		var obstacle_pool: ObstaclePoolDef = content.get_obstacle_pool(encounter.obstacle_pool_id)
		ObstacleGenerator.place_obstacles(
			board, obstacle_pool, encounter.obstacle_count, rng.get_stream(&"encounter"), content
		)

	var card_defs: Dictionary = content.all_cards()
	var deck := _build_deck(run)
	# 只在新遭遇装配时洗牌。BattleCheckpoint.restore 直接恢复牌区与 RNG，不走此路径。
	CardSystem.new().shuffle_draw(deck, rng.battle_rng())
	var state := BattleFactory.create_state(
		run.next_battle_id,
		board,
		units,
		deck,
		rng,
		encounter.hand_size,
		encounter.energy_per_round,
		encounter.move_points_per_round
	)

	RelicSystem.equip(state, run, content)
	state.run_instance_id = run.instance_id
	# 难度只影响本场实例，不修改共享的 EnemyDef / UnitDef。
	for enemy_id: int in state.enemy_ids():
		var enemy := state.get_unit(enemy_id)
		enemy.max_hp = maxi(1, ceili(enemy.max_hp * (1.0 + 0.1 * run.difficulty)))
		enemy.hp = enemy.max_hp
	return {
		"rng": rng,
		"state": state,
		"card_defs": card_defs,
		"enemy_behaviors": enemy_behaviors,
		"enemy_actions": enemy_actions,
		"enemy_reactions": enemy_reactions,
		"summon_pool": _build_summon_pool(encounter, content),
		"card_labels": _card_labels(card_defs),
	}


## RunState 永久卡组 -> 战斗 DeckState。source_run_uid 回指永久卡，便于战后写回。
static func _build_deck(run: RunState) -> DeckState:
	var deck := DeckState.new()
	var card_system := CardSystem.new()
	var uid := BATTLE_CARD_UID_BASE
	for run_card: RunCardState in run.deck:
		var battle_card := card_system.create_battle_card(run_card, uid)
		deck.add_card(battle_card, DeckState.ZONE_DRAW)
		uid += 1
	return deck


## 玩家进场格：override 盘内时优先，否则用 encounter.player_start。
static func _resolve_player_start(encounter: EncounterDef, override: Vector2i) -> Vector2i:
	if _is_inside(override, encounter.board_cols, encounter.board_rows):
		return override
	return encounter.player_start


## 敌人出生格规划（确定性）：先给显式非边缘出生格，其余从内部格洗牌依次取。
## 落点**不依赖玩家起点**（起点只用于跳过，不参与洗牌），所以可在"选进场格前"预览，
## 且预览与实际开战同 seed 同结果。
static func _plan_enemy_spawns(
	encounter: EncounterDef,
	start_cell: Vector2i,
	rng: RngStreams
) -> Array[Vector2i]:
	var pool := _interior_cells(encounter.board_cols, encounter.board_rows)
	_shuffle_cells(pool, rng.get_stream(&"encounter"))
	var used: Dictionary = {start_cell: true}
	var result: Array[Vector2i] = []
	for index in range(encounter.enemy_ids.size()):
		var cell := Vector2i(-1, -1)
		# 显式配置（设计师可覆盖随机）；必须非边缘且未被占用。
		if index < encounter.enemy_spawns.size():
			var explicit := encounter.enemy_spawns[index]
			if (_is_inside(explicit, encounter.board_cols, encounter.board_rows)
					and not _is_border(explicit, encounter.board_cols, encounter.board_rows)
					and not used.has(explicit)):
				cell = explicit
		# 随机内部格。玩家选格只在**外圈**、敌人只在**内部**，故落点不依赖起点（部署预览与实际一致）。
		if cell == Vector2i(-1, -1):
			for candidate: Vector2i in pool:
				if not used.has(candidate):
					cell = candidate
					break
		# 兜底：任意未占用的盘内格（理论不会触发，防御性）。
		if cell == Vector2i(-1, -1):
			cell = _first_free_cell(encounter, used, start_cell)
		used[cell] = true
		result.append(cell)
	return result


## 内部格 = 不贴棋盘最外圈（x∈[1,cols-2]、y∈[1,rows-2]）。
static func _interior_cells(cols: int, rows: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(1, rows - 1):
		for x in range(1, cols - 1):
			cells.append(Vector2i(x, y))
	return cells


static func _is_border(cell: Vector2i, cols: int, rows: int) -> bool:
	return cell.x <= 0 or cell.y <= 0 or cell.x >= cols - 1 or cell.y >= rows - 1


static func _is_inside(cell: Vector2i, cols: int, rows: int) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < cols and cell.y < rows


static func _first_free_cell(
	encounter: EncounterDef,
	used: Dictionary,
	start_cell: Vector2i
) -> Vector2i:
	for y in range(encounter.board_rows):
		for x in range(encounter.board_cols):
			var cell := Vector2i(x, y)
			if cell == start_cell or used.has(cell):
				continue
			return cell
	return start_cell


## Fisher-Yates 洗牌（就地）。确定性来自 rng 的 encounter 流。
static func _shuffle_cells(cells: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(cells.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := cells[i]
		cells[i] = cells[j]
		cells[j] = tmp


static func _collect_actions(actions: Dictionary, behavior: BehaviorDef) -> void:
	if not behavior is SequenceBehaviorDef:
		return
	for action: EnemyActionDef in (behavior as SequenceBehaviorDef).sequence:
		if action != null and not action.id.is_empty():
			actions[action.id] = action


## 召唤池：把 encounter.summon_enemy_ids 经 content 解析成 TurnSystem 直接可用的 spec 列表。
## 每条 {enemy_id, unit_def_id, max_hp, appearance_key, behavior, actions}。
## 规则层拿不到内容，故内容解析在这里做完，运行期只按 spec 生成单位。
static func _build_summon_pool(encounter: EncounterDef, content: Object) -> Array:
	var out: Array = []
	for enemy_id: StringName in encounter.summon_enemy_ids:
		var enemy_def: EnemyDef = content.get_enemy(enemy_id)
		if enemy_def == null:
			continue
		var unit_def: UnitDef = content.get_unit(enemy_def.unit_def_id)
		if unit_def == null:
			continue
		var actions: Array = []
		if enemy_def.behavior is SequenceBehaviorDef:
			for action: EnemyActionDef in (enemy_def.behavior as SequenceBehaviorDef).sequence:
				if action != null:
					actions.append(action)
		out.append({
			"enemy_id": enemy_id,
			"unit_def_id": enemy_def.unit_def_id,
			"max_hp": unit_def.base_stat(StatSystem.STAT_MAX_HP),
			"appearance_key": enemy_def.appearance_key,
			"behavior": enemy_def.behavior,
			"actions": actions,
		})
	return out


## 展示文本。与 DemoBattleSetup._card_labels 同一格式（占位 UI 共用）。
## TODO：B2-5 接线时抽成 presentation 层共享格式化器，消除两处重复。
static func _card_labels(card_defs: Dictionary) -> Dictionary:
	var labels: Dictionary = {}
	for id: Variant in card_defs:
		var definition := card_defs[id] as CardDef
		if definition == null:
			continue
		labels[id] = "%s\n%d 能量 · %s" % [
			definition.display_name if not definition.display_name.is_empty() else String(definition.card_id),
			definition.base_cost,
			definition.description,
		]
	return labels
