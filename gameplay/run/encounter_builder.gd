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
static func build(
	encounter: EncounterDef,
	run: RunState,
	rng: RngStreams,
	content: Object
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

	var player := UnitState.create(
		PLAYER_UNIT_ID,
		player_def.id,
		UnitState.Team.PLAYER,
		run.max_hp
	)
	player.hp = clampi(run.hp, 0, run.max_hp)
	units[PLAYER_UNIT_ID] = player
	board.place_unit(PLAYER_UNIT_ID, encounter.player_start)

	var enemy_behaviors: Dictionary = {}
	var enemy_actions: Dictionary = {}
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
		units[unit_id] = enemy
		board.place_unit(unit_id, _spawn_for(encounter, index))
		enemy_behaviors[unit_id] = enemy_def.behavior
		_collect_actions(enemy_actions, enemy_def.behavior)
		unit_id += 1
		index += 1

	var card_defs: Dictionary = content.all_cards()
	var state := BattleFactory.create_state(
		run.next_battle_id,
		board,
		units,
		_build_deck(run),
		rng,
		encounter.hand_size,
		encounter.energy_per_round,
		encounter.move_points_per_round
	)

	return {
		"rng": rng,
		"state": state,
		"card_defs": card_defs,
		"enemy_behaviors": enemy_behaviors,
		"enemy_actions": enemy_actions,
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


## 出生格：优先用 encounter.enemy_spawns[index]，否则用默认布局（玩家上方一行，横向铺开）。
static func _spawn_for(encounter: EncounterDef, index: int) -> Vector2i:
	if index < encounter.enemy_spawns.size():
		return encounter.enemy_spawns[index]
	var row := maxi(0, encounter.board_rows - 4)
	var col := 2 + index * 2
	if col >= encounter.board_cols:
		col = 2 + (index % maxi(1, encounter.board_cols / 2)) * 2
	return Vector2i(clampi(col, 0, encounter.board_cols - 1), row)


static func _collect_actions(actions: Dictionary, behavior: BehaviorDef) -> void:
	if not behavior is SequenceBehaviorDef:
		return
	for action: EnemyActionDef in (behavior as SequenceBehaviorDef).sequence:
		if action != null and not action.id.is_empty():
			actions[action.id] = action


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
