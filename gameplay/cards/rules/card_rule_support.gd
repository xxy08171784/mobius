class_name CardRuleSupport
extends RefCounted
## 规则处理器共享的效果、空间、牌区辅助函数；不持有运行状态。

const TOKEN_FIST: StringName = &"card.token.fist"
const STARTER_CHARGE: StringName = &"card.starter.charge"
const STARTER_RELENTLESS: StringName = &"card.starter.relentless"
const IMPLEMENTED_ATOMIC := [7, 8, 24, 28, 29, 32, 34, 36, 40, 42]


static func _damage(
	state: BattleState,
	rng: Variant,
	actor_id: int,
	card: BattleCardState,
	target: Variant,
	base_amount: float,
	prior_events: EventBatch = null
) -> Dictionary:
	return _apply(
		state, rng, actor_id, card.battle_uid, target,
		[{"type_key": &"damage", "params": {
			"amount": _damage_amount(card, state.round_index, base_amount)
		}}],
		prior_events
	)

static func _block(
	state: BattleState,
	rng: Variant,
	actor_id: int,
	card: BattleCardState,
	base_amount: float,
	prior_events: EventBatch = null
) -> Dictionary:
	return _apply(
		state, rng, actor_id, card.battle_uid, null,
		[{"type_key": &"block", "params": {
			"amount": maxf(0.0, base_amount + float(card.block_modifier)),
			"target_mode": &"source",
		}}],
		prior_events
	)

static func _apply(
	state: BattleState,
	rng: Variant,
	actor_id: int,
	card_uid: int,
	target: Variant,
	effects: Array,
	prior_events: EventBatch = null
) -> Dictionary:
	if effects.is_empty():
		return _success(state, rng, prior_events)
	var result := EffectResolver.new().resolve(
		state,
		{
			"context": {
				"source_unit_id": actor_id,
				"source_card_uid": card_uid,
				"target": target,
			},
			"effects": effects,
		},
		rng
	)
	if not bool(result.get("ok", false)):
		return _failure(state, rng)
	var events := EventBatch.new()
	_append_events(events, prior_events)
	_append_events(events, result.get("events"))
	return {
		"handled": true,
		"ok": true,
		"state_out": result["state_out"],
		"rng_out": result["rng_out"],
		"events": events,
	}

static func _success(
	state: BattleState, rng: Variant, events: EventBatch = null
) -> Dictionary:
	return {
		"handled": true,
		"ok": true,
		"state_out": state,
		"rng_out": rng,
		"events": events if events != null else EventBatch.new(),
	}

static func _failure(state: BattleState, rng: Variant) -> Dictionary:
	return {
		"handled": true,
		"ok": false,
		"state_out": state,
		"rng_out": rng,
		"events": EventBatch.new(),
	}

static func _damage_amount(card: BattleCardState, round_index: int, base_amount: float) -> float:
	return maxf(0.0, base_amount + float(_damage_bonus(card, round_index)))

static func _damage_bonus(card: BattleCardState, round_index: int) -> int:
	if card == null:
		return 0
	var value := card.damage_modifier
	if int(card.runtime_data.get("turn_damage_bonus_round", -999999)) == round_index:
		value += int(card.runtime_data.get("turn_damage_bonus", 0))
	return value

static func _estimate_technique_damage(
	state: BattleState,
	card: BattleCardState,
	definition: CardDef,
	target: Variant
) -> float:
	if card == null or definition == null:
		return 0.0
	var base := 0.0
	match definition.card_number:
		13:
			var direction: Variant = EffectStateAccess.target_direction(_context(-1, target))
			var moved := 0
			if direction is Vector2i:
				moved = _dash_distance(state, state.player_ids()[0] if not state.player_ids().is_empty() else -1, direction)
			base = 10.0 + float(moved * 5)
		14:
			base = 9.0
		15:
			base = 5.0
		16:
			base = 5.0
		17:
			base = 8.0
		_:
			for raw: Variant in definition.get_effects(card.upgrade_level):
				var item: Variant = (raw as EffectDef).to_plan_item() if raw is EffectDef else raw
				if item is Dictionary and StringName(String(item.get("type_key", ""))) == &"damage":
					base = float((item as Dictionary).get("params", {}).get("amount", 0.0))
					break
	return _damage_amount(card, state.round_index, base)

static func _dash_distance(state: BattleState, actor_id: int, direction: Variant) -> int:
	if state == null or actor_id < 0 or not direction is Vector2i:
		return 0
	var cur := state.board.get_unit_cell(actor_id)
	var moved := 0
	for _i in range(3):
		var next := cur + (direction as Vector2i)
		if not state.board.is_inside(next) or not state.board.is_traversable(next) or state.board.is_occupied(next):
			break
		cur = next
		moved += 1
	return moved

static func _enemies_within(state: BattleState, actor_id: int, range_: int) -> Array[int]:
	var out: Array[int] = []
	if state == null:
		return out
	var source := state.board.get_unit_cell(actor_id)
	for enemy_id: int in state.alive_enemy_ids():
		if _manhattan(source, state.board.get_unit_cell(enemy_id)) <= range_:
			out.append(enemy_id)
	return out

static func _enemies_adjacent(state: BattleState, actor_id: int) -> Array[int]:
	var out: Array[int] = []
	if state == null:
		return out
	var source := state.board.get_unit_cell(actor_id)
	for enemy_id: int in state.alive_enemy_ids():
		var cell := state.board.get_unit_cell(enemy_id)
		if maxi(absi(cell.x - source.x), absi(cell.y - source.y)) == 1:
			out.append(enemy_id)
	return out

static func _adjacent(state: BattleState, a: int, b: int) -> bool:
	if state == null or a < 0 or b < 0:
		return false
	var ca := state.board.get_unit_cell(a)
	var cb := state.board.get_unit_cell(b)
	return maxi(absi(ca.x - cb.x), absi(ca.y - cb.y)) == 1

static func _straight_line(a: Vector2i, b: Vector2i) -> bool:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return (dx == 0 and dy > 0) or (dy == 0 and dx > 0) or (dx == dy and dx > 0)

static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

static func _knife_count(unit: UnitState) -> int:
	return StatusRules.stacks(unit, StatusRules.KNIFE_MARK)

static func _remove_knives(unit: UnitState) -> int:
	if unit == null:
		return 0
	var count := 0
	var remove_ids: Array[int] = []
	for instance_id: int in unit.status_ids():
		var status := unit.get_status(instance_id)
		if status != null and status.status_id == StatusRules.KNIFE_MARK and not status.is_expired():
			count += maxi(0, status.stacks)
			remove_ids.append(instance_id)
	for instance_id: int in remove_ids:
		unit.remove_status(instance_id)
	return count

static func _allocate_card_uid(deck: DeckState) -> int:
	var uid := 1000
	for raw: Variant in deck.cards.keys():
		uid = maxi(uid, int(raw) + 1)
	return uid

static func _hand_has_category(
	deck: DeckState, card_defs: Dictionary, category: CardDef.CardCategory
) -> bool:
	for uid: int in deck.hand:
		var card := deck.get_card(uid)
		var definition := _def_for_card(card_defs, card)
		if definition != null and definition.card_category == category:
			return true
	return false

static func _def_for_card(card_defs: Dictionary, card: BattleCardState) -> CardDef:
	if card == null:
		return null
	if card_defs.has(card.card_id):
		return card_defs[card.card_id] as CardDef
	if card_defs.has(String(card.card_id)):
		return card_defs[String(card.card_id)] as CardDef
	return null

static func _target_unit_id(target: Variant) -> int:
	var context := EffectContext.new()
	context.target = target
	return EffectStateAccess.target_unit_id(context)

static func _context(actor_id: int, target: Variant) -> EffectContext:
	var context := EffectContext.new()
	context.source_unit_id = actor_id
	context.target = target
	return context

static func _choice_array(command: PlayCardsCommand, source_uid: int) -> Array[int]:
	var out: Array[int] = []
	if command == null:
		return out
	var raw: Variant = command.choices.get(source_uid, command.choices.get(str(source_uid), []))
	if raw is Array:
		for value: Variant in raw:
			out.append(int(value))
	return out

static func _battle_rng(rng: Variant) -> RandomNumberGenerator:
	if rng is RngStreams:
		return (rng as RngStreams).battle_rng()
	if rng is RandomNumberGenerator:
		return rng as RandomNumberGenerator
	return RandomNumberGenerator.new()

static func _append_events(destination: EventBatch, source: Variant) -> void:
	if destination == null or not source is EventBatch:
		return
	for event: GameEvent in (source as EventBatch).events:
		destination.push_back(event)

static func _resolve_area_damage(
	state: BattleState,
	rng: Variant,
	actor_id: int,
	card: BattleCardState,
	range_: int,
	base_amount: float,
	chebyshev: bool
) -> Dictionary:
	var effects: Array = []
	var actor_cell := state.board.get_unit_cell(actor_id)
	for enemy_id: int in state.alive_enemy_ids():
		var cell := state.board.get_unit_cell(enemy_id)
		var in_range := (
			maxi(absi(cell.x - actor_cell.x), absi(cell.y - actor_cell.y)) <= range_
			if chebyshev
			else _manhattan(actor_cell, cell) <= range_
		)
		if in_range:
			effects.append({
				"type_key": &"damage",
				"target": enemy_id,
				"params": {"amount": _damage_amount(card, state.round_index, base_amount)},
			})
	return _apply(state, rng, actor_id, card.battle_uid, null, effects)

static func _starter_charge_destination(
	state: BattleState, actor_id: int, target_id: int
) -> Vector2i:
	if state == null:
		return BoardState.INVALID_CELL
	var board := state.board
	var from := board.get_unit_cell(actor_id)
	var target_cell := board.get_unit_cell(target_id)
	if from == BoardState.INVALID_CELL or target_cell == BoardState.INVALID_CELL:
		return BoardState.INVALID_CELL
	var best := BoardState.INVALID_CELL
	var best_distance := 999999
	for direction: Vector2i in Pathfinder.ORTHO_DIRS:
		var candidate := target_cell + direction
		if not board.is_inside(candidate) or not board.is_traversable(candidate):
			continue
		if candidate != from and board.is_occupied(candidate):
			continue
		if candidate == from:
			return from
		var path := Pathfinder.find_path(board, from, candidate)
		if path.is_empty():
			continue
		var distance := path.size() - 1
		if distance > 2:
			continue
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best
