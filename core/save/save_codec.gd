class_name SaveCodec
extends RefCounted
## 运行状态 <-> Dictionary 的唯一编解码路径。
## 约定（architecture_review.md H2）：clone = encode(state) -> decode()，
## 避免维护第二套手写 clone()；新字段漏进 codec 会被往返测试立刻抓到。
## 需手动编码 Vector2i；64 位整数存为十进制字符串。

const _STATE_TYPE_BATTLE := "BattleState"
const _STATE_TYPE_RUN := "RunState"

func encode_state(state: RefCounted) -> Dictionary:
	if state is BattleState:
		return _encode_battle_state(state as BattleState)
	if state is RunState:
		return _encode_run_state(state as RunState)
	push_error("SaveCodec: unsupported state type")
	return {}


func decode_state(data: Dictionary) -> RefCounted:
	var migrator := SaveMigrator.new()
	if not migrator.can_load(data):
		push_error("SaveCodec: unsupported schema_version")
		return null
	var migrated := migrator.migrate(data.duplicate(true))
	match String(migrated.get("state_type", "")):
		_STATE_TYPE_BATTLE:
			return _decode_battle_state(migrated)
		_STATE_TYPE_RUN:
			return _decode_run_state(migrated)
		_:
			push_error("SaveCodec: unsupported state_type")
			return null


## 规则层统一深拷贝入口。禁止为各 State 再维护第二套 clone()。
func clone_state(state: RefCounted) -> RefCounted:
	return decode_state(encode_state(state))


## JSON 安全 Variant 编码：int64 用十进制字符串，Vector2i 显式拆分。
## 未来 Board/Unit/Card 状态进入 BattleState 时复用这一条路径。
func encode_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_INT:
			return {"__type": "int64", "value": str(value)}
		TYPE_STRING_NAME:
			return {"__type": "StringName", "value": String(value)}
		TYPE_VECTOR2I:
			var cell := value as Vector2i
			return {"__type": "Vector2i", "x": str(cell.x), "y": str(cell.y)}
		TYPE_ARRAY:
			var encoded_array: Array = []
			for item: Variant in value:
				encoded_array.append(encode_value(item))
			return encoded_array
		TYPE_DICTIONARY:
			var entries: Array = []
			for key: Variant in value:
				entries.append({
					"key": encode_value(key),
					"value": encode_value(value[key]),
				})
			entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return JSON.stringify(a["key"]) < JSON.stringify(b["key"])
			)
			return {"__type": "Dictionary", "entries": entries}
		_:
			push_error("SaveCodec: unsupported Variant type %s" % typeof(value))
			return null


func decode_value(value: Variant) -> Variant:
	if value is Array:
		var decoded_array: Array = []
		for item: Variant in value:
			decoded_array.append(decode_value(item))
		return decoded_array
	if not value is Dictionary:
		return value

	var data := value as Dictionary
	var type_key := String(data.get("__type", ""))
	match type_key:
		"int64":
			return String(data.get("value", "0")).to_int()
		"StringName":
			return StringName(String(data.get("value", "")))
		"Vector2i":
			return Vector2i(
				String(data.get("x", "0")).to_int(),
				String(data.get("y", "0")).to_int()
			)
		"Dictionary":
			var decoded_dict: Dictionary = {}
			for entry: Dictionary in data.get("entries", []):
				decoded_dict[decode_value(entry.get("key"))] = decode_value(entry.get("value"))
			return decoded_dict
		_:
			var plain: Dictionary = {}
			for key: Variant in data:
				plain[key] = decode_value(data[key])
			return plain


func _encode_battle_state(state: BattleState) -> Dictionary:
	return {
		"schema_version": SaveMigrator.CURRENT_SCHEMA_VERSION,
		"state_type": _STATE_TYPE_BATTLE,
		"state": {
			"phase": int(state.phase),
			"resume_phase": int(state.resume_phase),
			"battle_id": encode_value(state.battle_id),
			"round_index": encode_value(state.round_index),
			"version": encode_value(state.version),
			"next_uid": encode_value(state.next_uid),
			"next_event_seq": encode_value(state.next_event_seq),
			"command_locked": state.command_locked,
			"seen_command_ids": encode_value(state.seen_command_ids),
			"command_result_snapshots": encode_value(state.command_result_snapshots),
			"board": _encode_board(state.board),
			"units": _encode_units(state.units),
			"deck": _encode_deck(state.deck),
			"enemy_intents": _encode_intents(state.enemy_intents),
			"enemy_steps": encode_value(state.enemy_steps),
			"enemy_charge_remaining": encode_value(state.enemy_charge_remaining),
			"enemy_charge_intents": _encode_intents(state.enemy_charge_intents),
			"rng_snapshot": encode_value(state.rng_snapshot),
			"hand_size": encode_value(state.hand_size),
			"energy_per_round": encode_value(state.energy_per_round),
			"move_points_per_round": encode_value(state.move_points_per_round),
		},
	}


func _decode_battle_state(data: Dictionary) -> BattleState:
	var payload: Dictionary = data.get("state", {})
	var state := BattleState.new()
	state.phase = int(payload.get("phase", BattleState.Phase.SETUP))
	state.resume_phase = int(payload.get("resume_phase", BattleState.Phase.PLAYER_INPUT))
	state.battle_id = int(decode_value(payload.get("battle_id", encode_value(-1))))
	state.round_index = int(decode_value(payload.get("round_index", encode_value(0))))
	state.version = int(decode_value(payload.get("version", encode_value(0))))
	state.next_uid = int(decode_value(payload.get("next_uid", encode_value(1))))
	state.next_event_seq = int(decode_value(payload.get("next_event_seq", encode_value(1))))
	state.command_locked = bool(payload.get("command_locked", false))
	state.seen_command_ids.clear()
	var seen: Array = decode_value(payload.get("seen_command_ids", []))
	for command_id: Variant in seen:
		state.seen_command_ids.append(int(command_id))
	state.command_result_snapshots = decode_value(payload.get("command_result_snapshots", encode_value({})))
	state.board = _decode_board(payload.get("board", {}))
	state.units = _decode_units(payload.get("units", []))
	state.deck = _decode_deck(payload.get("deck", {}))
	state.enemy_intents = _decode_intents(payload.get("enemy_intents", []))
	state.enemy_steps = _to_int_int_dictionary(decode_value(payload.get("enemy_steps", encode_value({}))))
	state.enemy_charge_remaining = _to_int_int_dictionary(
		decode_value(payload.get("enemy_charge_remaining", encode_value({})))
	)
	state.enemy_charge_intents = _decode_intents(payload.get("enemy_charge_intents", []))
	state.rng_snapshot = decode_value(payload.get("rng_snapshot", encode_value({})))
	state.hand_size = int(decode_value(payload.get("hand_size", encode_value(5))))
	state.energy_per_round = int(decode_value(payload.get("energy_per_round", encode_value(3))))
	state.move_points_per_round = int(
		decode_value(payload.get("move_points_per_round", encode_value(0)))
	)
	return state


func _encode_board(board: BoardState) -> Dictionary:
	if board == null:
		return {}
	var cells: Array = []
	for y: int in range(board.rows):
		for x: int in range(board.cols):
			var cell := Vector2i(x, y)
			var cell_state := board.get_cell(cell)
			if cell_state == null:
				continue
			cells.append({
				"cell": encode_value(cell),
				"terrain_key": encode_value(cell_state.terrain_key),
				"blocks_los": cell_state.blocks_los,
				"traversable": cell_state.traversable,
				"trap": cell_state.trap,
			})
	var occupants: Array = []
	for unit_id: int in board.get_unit_ids():
		occupants.append({
			"unit_id": encode_value(unit_id),
			"cell": encode_value(board.get_unit_cell(unit_id)),
		})
	return {
		"cols": encode_value(board.cols),
		"rows": encode_value(board.rows),
		"cells": cells,
		"occupants": occupants,
	}


func _decode_board(data: Dictionary) -> BoardState:
	if data.is_empty():
		return BoardState.new()
	var board := BoardState.new(
		int(decode_value(data.get("cols", encode_value(8)))),
		int(decode_value(data.get("rows", encode_value(8))))
	)
	for entry: Dictionary in data.get("cells", []):
		var cell: Vector2i = decode_value(entry.get("cell", encode_value(Vector2i.ZERO)))
		var cell_state := CellState.new()
		cell_state.terrain_key = decode_value(entry.get("terrain_key", encode_value(&"")))
		cell_state.blocks_los = bool(entry.get("blocks_los", false))
		cell_state.traversable = bool(entry.get("traversable", true))
		cell_state.trap = bool(entry.get("trap", false))
		board.set_cell(cell, cell_state)
	for entry: Dictionary in data.get("occupants", []):
		var unit_id := int(decode_value(entry.get("unit_id", encode_value(-1))))
		var cell: Vector2i = decode_value(entry.get("cell", encode_value(BoardState.INVALID_CELL)))
		if unit_id >= 0:
			board.place_unit(unit_id, cell)
	return board


func _encode_units(units: Dictionary[int, UnitState]) -> Array:
	var ids: Array[int] = []
	for unit_id: int in units:
		ids.append(unit_id)
	ids.sort()
	var result: Array = []
	for unit_id: int in ids:
		var unit: UnitState = units[unit_id]
		var statuses: Array = []
		for instance_id: int in unit.status_ids():
			var status: StatusState = unit.statuses[instance_id]
			statuses.append({
				"instance_id": encode_value(status.instance_id),
				"status_id": encode_value(status.status_id),
				"stacks": encode_value(status.stacks),
				"duration": encode_value(status.duration),
				"source_unit_id": encode_value(status.source_unit_id),
			})
		result.append({
			"unit_id": encode_value(unit.unit_id),
			"def_id": encode_value(unit.def_id),
			"team": int(unit.team),
			"hp": encode_value(unit.hp),
			"max_hp": encode_value(unit.max_hp),
			"block": encode_value(unit.block),
			"resources": encode_value(unit.resources),
			"statuses": statuses,
		})
	return result


func _decode_units(data: Array) -> Dictionary[int, UnitState]:
	var units: Dictionary[int, UnitState] = {}
	for entry: Dictionary in data:
		var unit_id := int(decode_value(entry.get("unit_id", encode_value(-1))))
		var unit := UnitState.create(
			unit_id,
			decode_value(entry.get("def_id", encode_value(&""))),
			int(entry.get("team", UnitState.Team.ENEMY)),
			int(decode_value(entry.get("max_hp", encode_value(1))))
		)
		unit.hp = int(decode_value(entry.get("hp", encode_value(unit.max_hp))))
		unit.block = int(decode_value(entry.get("block", encode_value(0))))
		var resources: Dictionary = decode_value(entry.get("resources", encode_value({})))
		for key: Variant in resources:
			unit.resources[StringName(String(key))] = int(resources[key])
		for status_data: Dictionary in entry.get("statuses", []):
			var status := StatusState.new()
			status.instance_id = int(
				decode_value(status_data.get("instance_id", encode_value(-1)))
			)
			status.status_id = decode_value(status_data.get("status_id", encode_value(&"")))
			status.stacks = int(decode_value(status_data.get("stacks", encode_value(1))))
			status.duration = int(decode_value(status_data.get("duration", encode_value(1))))
			status.source_unit_id = int(
				decode_value(status_data.get("source_unit_id", encode_value(-1)))
			)
			unit.statuses[status.instance_id] = status
		units[unit_id] = unit
	return units


func _encode_deck(deck: DeckState) -> Dictionary:
	if deck == null:
		return {}
	var ids: Array[int] = []
	for uid_value: Variant in deck.cards:
		ids.append(int(uid_value))
	ids.sort()
	var cards: Array = []
	for uid: int in ids:
		var card := deck.get_card(uid)
		cards.append({
			"battle_uid": encode_value(card.battle_uid),
			"source_run_uid": encode_value(card.source_run_uid),
			"card_id": encode_value(card.card_id),
			"upgrade_level": encode_value(card.upgrade_level),
			"cost_modifier": encode_value(card.cost_modifier),
			"temporary_tags": encode_value(card.temporary_tags),
			"generated": card.generated,
		})
	return {
		"cards": cards,
		"draw": encode_value(deck.draw),
		"hand": encode_value(deck.hand),
		"discard": encode_value(deck.discard),
		"exhaust": encode_value(deck.exhaust),
		"resolving": encode_value(deck.resolving),
	}


func _decode_deck(data: Dictionary) -> DeckState:
	var deck := DeckState.new()
	if data.is_empty():
		return deck
	for card_data: Dictionary in data.get("cards", []):
		var card := BattleCardState.new()
		card.battle_uid = int(
			decode_value(card_data.get("battle_uid", encode_value(-1)))
		)
		card.source_run_uid = int(
			decode_value(card_data.get("source_run_uid", encode_value(-1)))
		)
		card.card_id = decode_value(card_data.get("card_id", encode_value(&"")))
		card.upgrade_level = int(
			decode_value(card_data.get("upgrade_level", encode_value(0)))
		)
		card.cost_modifier = int(
			decode_value(card_data.get("cost_modifier", encode_value(0)))
		)
		var tags: Array = decode_value(card_data.get("temporary_tags", []))
		for tag: Variant in tags:
			card.temporary_tags.append(StringName(String(tag)))
		card.generated = bool(card_data.get("generated", false))
		deck.cards[card.battle_uid] = card
	deck.draw = _to_int_array(decode_value(data.get("draw", [])))
	deck.hand = _to_int_array(decode_value(data.get("hand", [])))
	deck.discard = _to_int_array(decode_value(data.get("discard", [])))
	deck.exhaust = _to_int_array(decode_value(data.get("exhaust", [])))
	deck.resolving = _to_int_array(decode_value(data.get("resolving", [])))
	return deck


func _encode_intents(intents: Dictionary[int, IntentState]) -> Array:
	var ids: Array[int] = []
	for unit_id: int in intents:
		ids.append(unit_id)
	ids.sort()
	var result: Array = []
	for unit_id: int in ids:
		var intent: IntentState = intents[unit_id]
		result.append({
			"unit_id": encode_value(unit_id),
			"action_id": encode_value(intent.action_id),
			"actor_id": encode_value(intent.actor_id),
			"target_policy": int(intent.target_policy),
			"locked_unit_id": encode_value(intent.locked_unit_id),
			"locked_cell": encode_value(intent.locked_cell),
			"affected_cells": encode_value(intent.affected_cells),
			"magnitude": encode_value(intent.magnitude),
			"is_fallback": intent.is_fallback,
		})
	return result


func _decode_intents(data: Array) -> Dictionary[int, IntentState]:
	var intents: Dictionary[int, IntentState] = {}
	for entry: Dictionary in data:
		var key := int(decode_value(entry.get("unit_id", encode_value(-1))))
		var intent := IntentState.new()
		intent.action_id = decode_value(entry.get("action_id", encode_value(&"")))
		intent.actor_id = int(decode_value(entry.get("actor_id", encode_value(key))))
		intent.target_policy = int(
			entry.get("target_policy", EnemyActionDef.TargetPolicy.PLAYER)
		)
		intent.locked_unit_id = int(
			decode_value(entry.get("locked_unit_id", encode_value(-1)))
		)
		intent.locked_cell = decode_value(
			entry.get("locked_cell", encode_value(BoardState.INVALID_CELL))
		)
		var affected: Array = decode_value(entry.get("affected_cells", []))
		for cell: Variant in affected:
			intent.affected_cells.append(cell as Vector2i)
		intent.magnitude = int(decode_value(entry.get("magnitude", encode_value(0))))
		intent.is_fallback = bool(entry.get("is_fallback", false))
		if key >= 0:
			intents[key] = intent
	return intents


func _encode_run_state(state: RunState) -> Dictionary:
	return {
		"schema_version": SaveMigrator.CURRENT_SCHEMA_VERSION,
		"state_type": _STATE_TYPE_RUN,
		"state": {
			"run_id": encode_value(state.run_id),
			"seed": state.seed,
			"character_id": encode_value(state.character_id),
			"act_index": encode_value(state.act_index),
			"current_node_id": encode_value(state.current_node_id),
			"hp": encode_value(state.hp),
			"max_hp": encode_value(state.max_hp),
			"gold": encode_value(state.gold),
			"next_card_uid": encode_value(state.next_card_uid),
			"next_relic_uid": encode_value(state.next_relic_uid),
			"next_battle_id": encode_value(state.next_battle_id),
			"rng_snapshot": encode_value(state.rng_snapshot),
			"map": _encode_route_graph(state.map),
			"deck": _encode_run_cards(state.deck),
			"relics": _encode_relics(state.relics),
		},
	}


func _decode_run_state(data: Dictionary) -> RunState:
	var payload: Dictionary = data.get("state", {})
	var state := RunState.new()
	state.run_id = int(decode_value(payload.get("run_id", encode_value(-1))))
	state.seed = String(payload.get("seed", ""))
	state.character_id = decode_value(payload.get("character_id", encode_value(&"")))
	state.act_index = int(decode_value(payload.get("act_index", encode_value(0))))
	state.current_node_id = int(decode_value(payload.get("current_node_id", encode_value(-1))))
	state.hp = int(decode_value(payload.get("hp", encode_value(1))))
	state.max_hp = int(decode_value(payload.get("max_hp", encode_value(1))))
	state.gold = int(decode_value(payload.get("gold", encode_value(0))))
	state.next_card_uid = int(decode_value(payload.get("next_card_uid", encode_value(1))))
	state.next_relic_uid = int(decode_value(payload.get("next_relic_uid", encode_value(1))))
	state.next_battle_id = int(decode_value(payload.get("next_battle_id", encode_value(1))))
	state.rng_snapshot = decode_value(payload.get("rng_snapshot", encode_value({})))
	state.map = _decode_route_graph(payload.get("map", {}))
	state.deck = _decode_run_cards(payload.get("deck", []))
	state.relics = _decode_relics(payload.get("relics", []))
	return state


func _encode_route_graph(graph: RouteGraph) -> Dictionary:
	if graph == null:
		return {}
	var nodes: Array = []
	var ids: Array[int] = []
	for id: int in graph.nodes:
		ids.append(id)
	ids.sort()
	for id: int in ids:
		var n: MapNodeState = graph.nodes[id]
		nodes.append({
			"id": encode_value(n.id),
			"row": encode_value(n.row),
			"col": encode_value(n.col),
			"type_key": encode_value(n.type_key),
			"content_id": encode_value(n.content_id),
			"visited": n.visited,
			"is_entry": n.is_entry,
			"prev_ids": encode_value(n.prev_ids),
			"next_ids": encode_value(n.next_ids),
		})
	return {
		"rows": encode_value(graph.rows),
		"cols": encode_value(graph.cols),
		"boss_id": encode_value(graph.boss_id),
		"entry_ids": encode_value(graph.entry_ids),
		"nodes": nodes,
	}


func _decode_route_graph(data: Dictionary) -> RouteGraph:
	if data.is_empty():
		return null
	var graph := RouteGraph.new()
	graph.rows = int(decode_value(data.get("rows", encode_value(0))))
	graph.cols = int(decode_value(data.get("cols", encode_value(0))))
	graph.boss_id = int(decode_value(data.get("boss_id", encode_value(-1))))
	for entry: Dictionary in data.get("nodes", []):
		var n := MapNodeState.new()
		n.id = int(decode_value(entry.get("id", encode_value(-1))))
		n.row = int(decode_value(entry.get("row", encode_value(0))))
		n.col = int(decode_value(entry.get("col", encode_value(0))))
		n.type_key = decode_value(entry.get("type_key", encode_value(&"")))
		n.content_id = decode_value(entry.get("content_id", encode_value(&"")))
		n.visited = bool(entry.get("visited", false))
		n.is_entry = bool(entry.get("is_entry", false))
		n.prev_ids = _to_int_array(decode_value(entry.get("prev_ids", [])))
		n.next_ids = _to_int_array(decode_value(entry.get("next_ids", [])))
		graph.nodes[n.id] = n
		graph.node_by_cell[Vector2i(n.col, n.row)] = n.id
	# _next_id 需大于全部已有 id，保证后续 add_node 不撞号。
	var max_id := -1
	for id: int in graph.nodes:
		if id > max_id:
			max_id = id
	graph._next_id = max_id + 1
	graph.entry_ids = _to_int_array(decode_value(data.get("entry_ids", [])))
	return graph


func _encode_run_cards(cards: Array[RunCardState]) -> Array:
	var out: Array = []
	for card: RunCardState in cards:
		out.append({
			"run_uid": encode_value(card.run_uid),
			"card_id": encode_value(card.card_id),
			"upgrade_level": encode_value(card.upgrade_level),
			"permanent_modifiers": encode_value(card.permanent_modifiers),
		})
	return out


func _decode_run_cards(data: Array) -> Array[RunCardState]:
	var out: Array[RunCardState] = []
	for entry: Dictionary in data:
		var card := RunCardState.new()
		card.run_uid = int(decode_value(entry.get("run_uid", encode_value(-1))))
		card.card_id = decode_value(entry.get("card_id", encode_value(&"")))
		card.upgrade_level = int(decode_value(entry.get("upgrade_level", encode_value(0))))
		card.permanent_modifiers = decode_value(entry.get("permanent_modifiers", encode_value({})))
		out.append(card)
	return out


func _encode_relics(relics: Array[RelicState]) -> Array:
	var out: Array = []
	for relic: RelicState in relics:
		out.append({
			"instance_id": encode_value(relic.instance_id),
			"relic_id": encode_value(relic.relic_id),
			"counters": encode_value(relic.counters),
		})
	return out


func _decode_relics(data: Array) -> Array[RelicState]:
	var out: Array[RelicState] = []
	for entry: Dictionary in data:
		var relic := RelicState.new()
		relic.instance_id = int(decode_value(entry.get("instance_id", encode_value(-1))))
		relic.relic_id = decode_value(entry.get("relic_id", encode_value(&"")))
		relic.counters = decode_value(entry.get("counters", encode_value({})))
		out.append(relic)
	return out


func _to_int_array(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	return result


func _to_int_int_dictionary(values: Dictionary) -> Dictionary[int, int]:
	var result: Dictionary[int, int] = {}
	for key: Variant in values:
		result[int(key)] = int(values[key])
	return result
