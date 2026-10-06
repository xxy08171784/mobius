class_name FormalCardRules
extends RefCounted
## 01~49 正式卡的集中规则层。
## 复杂卡不把条件/牌区/空间逻辑塞进 UI 或 EffectHandler；ComboPlanner 在工作快照上调用本服务。
##
## 策划未给出的默认值集中在这里，便于之后单点替换：
## - “拳牌”暂定：0 费、4 伤害、攻击牌、消耗。
## - “眩晕 1 回合”：敌人下一次行动跳过。
## - “钝足 1 回合”：敌人下一次接近移动少 1 格。
## - “紧邻/周围一圈”：八邻域（Chebyshev 距离 1）。
## - #27 同时有多张招式时，取组合顺序中的第一张招式计算 150% 伤害。
## - #13 冲刺斩沿所选 8 方向前进，遇到第一个敌人停在其前并造成伤害。

const TOKEN_FIST: StringName = &"card.token.fist"
const STARTER_CHARGE: StringName = &"card.starter.charge"
const STARTER_RELENTLESS: StringName = &"card.starter.relentless"
const IMPLEMENTED_ATOMIC := [7, 8, 24, 28, 29, 32, 34, 36, 40, 42]


static func on_card_drawn(card: BattleCardState) -> void:
	if card == null:
		return
	match card.card_id:
		&"card.reward.37":
			card.runtime_data["stacked_block"] = int(card.runtime_data.get("stacked_block", 0)) + 4
		&"card.reward.46":
			card.runtime_data["heal_charge"] = mini(9, int(card.runtime_data.get("heal_charge", 0)) + 3)


static func choice_request(
	state: BattleState,
	source_uid: int,
	selected_uids: Array[int],
	card_defs: Dictionary
) -> Dictionary:
	if state == null:
		return {}
	var source := state.deck.get_card(source_uid)
	var definition := _def_for_card(card_defs, source)
	if source == null or definition == null:
		return {}
	var number := definition.card_number
	var zone := DeckState.ZONE_HAND
	var min_count := 1
	var max_count := 1
	var title := ""
	match number:
		2:
			zone = DeckState.ZONE_DRAW
			title = "立刻征用：选择抽牌堆中的 1 张攻击牌"
		5:
			title = "招式领悟：选择手牌中的 1 张招式牌"
		6:
			title = "遣散：选择最多 2 张手牌"
			min_count = 0
			max_count = 2
		12:
			title = "复制：选择 1 张手牌（能力类除外）"
		44:
			title = "应激格挡：选择 1 张手牌放入弃牌堆"
		_:
			return {}
	var candidates: Array[int] = []
	var values: Variant = state.deck.get_zone(zone)
	if values is Array:
		for value: Variant in values:
			var uid := int(value)
			if selected_uids.has(uid):
				continue
			var card := state.deck.get_card(uid)
			var candidate_def := _def_for_card(card_defs, card)
			if card == null or candidate_def == null:
				continue
			if number == 2 and candidate_def.card_category != CardDef.CardCategory.ATTACK:
				continue
			if number == 5 and candidate_def.card_category != CardDef.CardCategory.TECHNIQUE:
				continue
			if number == 12 and card.effective_tags(candidate_def).has(CardDef.TAG_ABILITY):
				continue
			candidates.append(uid)
	return {
		"title": title,
		"source_uid": source_uid,
		"zone": zone,
		"min_count": min_count,
		"max_count": max_count,
		"candidates": candidates,
	}


static func validate_command_choices(
	state: BattleState,
	command: PlayCardsCommand,
	card_defs: Dictionary
) -> bool:
	if state == null or command == null:
		return false
	for source_uid: int in command.card_uids:
		var request := choice_request(state, source_uid, command.card_uids, card_defs)
		if request.is_empty():
			continue
		var selected := _choice_array(command, source_uid)
		var min_count := int(request.get("min_count", 0))
		var max_count := int(request.get("max_count", 0))
		if selected.size() < min_count or selected.size() > max_count:
			return false
		var seen: Dictionary = {}
		var candidates: Array = request.get("candidates", [])
		for uid: int in selected:
			if seen.has(uid) or not candidates.has(uid):
				return false
			seen[uid] = true
	return true


static func apply_combo_pre_modifiers(
	state: BattleState,
	command: PlayCardsCommand,
	card_defs: Dictionary
) -> void:
	if state == null or command == null:
		return
	for source_uid: int in command.card_uids:
		var source := state.deck.get_card(source_uid)
		var source_def := _def_for_card(card_defs, source)
		if source == null or source_def == null:
			continue
		match source_def.card_number:
			26:
				for uid: int in command.card_uids:
					if uid == source_uid:
						continue
					var other := state.deck.get_card(uid)
					var other_def := _def_for_card(card_defs, other)
					if other != null and other_def != null and other_def.card_category == CardDef.CardCategory.TECHNIQUE:
						other.damage_modifier += 3
			49:
				for uid: int in command.card_uids:
					if uid == source_uid:
						continue
					var other := state.deck.get_card(uid)
					if other != null:
						other.block_modifier += 3


static func prepare_effects(
	card: BattleCardState,
	definition: CardDef,
	round_index: int
) -> Array:
	var out: Array = []
	if card == null or definition == null:
		return out
	var has_block := false
	for raw: Variant in definition.get_effects(card.upgrade_level):
		var item: Dictionary = {}
		if raw is EffectDef:
			item = (raw as EffectDef).to_plan_item()
		elif raw is Dictionary:
			item = (raw as Dictionary).duplicate(true)
		if item.is_empty():
			continue
		var params: Dictionary = Dictionary(item.get("params", {})).duplicate(true)
		var type_key := StringName(String(item.get("type_key", "")))
		if type_key == &"damage":
			params["amount"] = float(params.get("amount", 0.0)) + float(_damage_bonus(card, round_index))
		elif type_key == &"block":
			has_block = true
			params["amount"] = float(params.get("amount", 0.0)) + float(card.block_modifier)
		item["params"] = params
		out.append(item)
	if card.block_modifier > 0 and not has_block:
		out.append({
			"type_key": &"block",
			"params": {"amount": card.block_modifier, "target_mode": &"source"},
		})
	return out


static func validate_target(
	state: BattleState,
	actor_id: int,
	definition: CardDef,
	target: Variant
) -> Dictionary:
	if state == null or definition == null:
		return {"ok": false, "fizzle": false}
	if definition.card_id == STARTER_CHARGE:
		var target_id := _target_unit_id(target)
		return {
			"ok": target_id >= 0 and _starter_charge_destination(state, actor_id, target_id) != BoardState.INVALID_CELL,
			"fizzle": false,
		}
	var number := definition.card_number
	if number == 1:
		var cell: Variant = EffectStateAccess.target_cell(_context(actor_id, target))
		if not cell is Vector2i:
			return {"ok": false, "fizzle": false}
		var from := state.board.get_unit_cell(actor_id)
		var to := cell as Vector2i
		if not _straight_line(from, to) or _manhattan(from, to) > 2:
			return {"ok": false, "fizzle": false}
		var target_id := state.board.get_unit_at(to)
		var has_knife := target_id >= 0 and _knife_count(state.get_unit(target_id)) > 0
		var items: Variant = state.ground_items.get(to, [])
		return {"ok": has_knife or (items is Array and not (items as Array).is_empty()), "fizzle": false}
	if number in [15, 17]:
		var target_id := _target_unit_id(target)
		var from := state.board.get_unit_cell(actor_id)
		var to := state.board.get_unit_cell(target_id)
		return {"ok": _straight_line(from, to), "fizzle": false}
	if number == 25:
		var target_id := _target_unit_id(target)
		return {"ok": _adjacent(state, actor_id, target_id), "fizzle": false}
	return {"ok": true, "fizzle": false}


static func is_special(definition: CardDef) -> bool:
	if definition == null:
		return false
	if definition.card_id in [STARTER_CHARGE, STARTER_RELENTLESS]:
		return true
	return definition.card_number > 0 and not IMPLEMENTED_ATOMIC.has(definition.card_number)


static func resolve_card(
	state: BattleState,
	rng: Variant,
	actor_id: int,
	card: BattleCardState,
	definition: CardDef,
	target: Variant,
	command: PlayCardsCommand,
	combo_metadata: Dictionary,
	card_defs: Dictionary
) -> Dictionary:
	if not is_special(definition):
		return {"handled": false}
	if state == null or card == null:
		return _failure(state, rng)
	match definition.card_id:
		STARTER_CHARGE:
			return _resolve_starter_charge(state, rng, actor_id, card, target)
		STARTER_RELENTLESS:
			return _resolve_starter_relentless(state, rng, actor_id, card, target)
	var number := definition.card_number
	var choices := _choice_array(command, card.battle_uid)
	match number:
		1:
			return _resolve_lasso(state, rng, actor_id, target)
		2:
			return _resolve_requisition(state, rng, card, choices)
		3:
			return _resolve_cautious(state, rng, actor_id, card)
		4:
			return _resolve_generate_fists(state, rng)
		5:
			return _resolve_technique_insight(state, rng, choices)
		6:
			return _resolve_dismiss(state, rng, actor_id, card, choices)
		9:
			return _resolve_inspire(state, rng, actor_id)
		10:
			return _apply(
				state, rng, actor_id, card.battle_uid, target,
				[{"type_key": &"push", "params": {"steps": 2, "direction_mode": &"away_from_source"}}]
			)
		11:
			return _resolve_area_damage(state, rng, actor_id, card, 2, 12.0, false)
		12:
			return _resolve_copy(state, rng, choices)
		13:
			return _resolve_dash_slash(state, rng, actor_id, card, target)
		14:
			return _resolve_kick_backflip(state, rng, actor_id, card, target)
		15:
			return _resolve_hook(state, rng, actor_id, card, target)
		16:
			return _resolve_whirlwind(state, rng, actor_id, card)
		17:
			return _resolve_throwing_knife(state, rng, actor_id, card, target)
		18:
			return _resolve_blood_sword(state, rng, actor_id, card, target)
		19:
			return _resolve_demon_blade(state, rng, actor_id, card, target)
		20:
			return _resolve_damage_status(state, rng, actor_id, card, target, 12.0, StatusRules.STUN)
		21:
			var amount := 6.0 + 3.0 * float(maxi(0, command.card_uids.size() - 1))
			return _damage(state, rng, actor_id, card, target, amount)
		22:
			var unit := state.get_unit(_target_unit_id(target))
			var amount := 18.0 if StatusRules.has_negative_status(unit) else 6.0
			return _damage(state, rng, actor_id, card, target, amount)
		23:
			var result := _damage(state, rng, actor_id, card, target, 15.0)
			if bool(result.get("ok", false)):
				var out := result["state_out"] as BattleState
				out.scheduled_effects.append({
					"round": out.round_index + 1,
					"kind": &"draw",
					"count": 1,
					"source_unit_id": actor_id,
				})
			return result
		25:
			return _damage(state, rng, actor_id, card, target, 13.0)
		26:
			return _success(state, rng)
		27:
			return _resolve_technique_synergy(
				state, rng, actor_id, card, target, command, card_defs
			)
		30:
			var amount := float(_enemies_within(state, actor_id, 2).size() * 5)
			return _damage(state, rng, actor_id, card, target, amount)
		31:
			return _resolve_damage_status(state, rng, actor_id, card, target, 9.0, StatusRules.SLOW)
		33:
			return _resolve_overflow(state, rng, actor_id, card, target)
		35:
			return _resolve_rooted_attack(state, rng, actor_id, card, target)
		37:
			var amount := int(card.runtime_data.get("stacked_block", 0))
			card.runtime_data["stacked_block"] = 0
			return _block(state, rng, actor_id, card, float(amount))
		38:
			return _resolve_hold_back(state, rng, actor_id, card)
		39:
			var amount := 5.0 + 3.0 * float(maxi(0, command.card_uids.size() - 1))
			return _block(state, rng, actor_id, card, amount)
		41:
			var has_technique := _hand_has_category(state.deck, card_defs, CardDef.CardCategory.TECHNIQUE)
			return _block(state, rng, actor_id, card, 16.0 if has_technique else 5.0)
		43:
			var result := _block(state, rng, actor_id, card, 9.0)
			if bool(result.get("ok", false)):
				var out := result["state_out"] as BattleState
				out.scheduled_effects.append({
					"round": out.round_index + 1,
					"kind": &"block",
					"amount": 9,
					"source_unit_id": actor_id,
				})
			return result
		44:
			return _resolve_stress_block(state, rng, actor_id, card, choices)
		45:
			var amount := float(_enemies_within(state, actor_id, 2).size() * 8)
			return _block(state, rng, actor_id, card, amount)
		46:
			var amount := int(card.runtime_data.get("heal_charge", 0))
			return _apply(
				state, rng, actor_id, card.battle_uid, null,
				[{"type_key": &"heal", "params": {"amount": amount, "target_mode": &"source"}}]
			)
		47:
			var result := _block(state, rng, actor_id, card, 13.0)
			if not bool(result.get("ok", false)):
				return result
			var out := result["state_out"] as BattleState
			if not _enemies_adjacent(out, actor_id).is_empty():
				return _apply(
					out, result["rng_out"], actor_id, card.battle_uid, null,
					[{"type_key": &"resource", "params": {
						"key": &"courage", "operation": &"add", "amount": 5, "target_mode": &"source"
					}}],
					result["events"]
				)
			return result
		48:
			return _resolve_rooted_defense(state, rng, actor_id, card)
		49:
			return _success(state, rng)
		_:
			return {"handled": false}


static func _resolve_lasso(state: BattleState, rng: Variant, actor_id: int, target: Variant) -> Dictionary:
	var cell: Variant = EffectStateAccess.target_cell(_context(actor_id, target))
	if not cell is Vector2i:
		return _failure(state, rng)
	var target_cell := cell as Vector2i
	var unit_id := state.board.get_unit_at(target_cell)
	if unit_id >= 0:
		var target_unit := state.get_unit(unit_id)
		var knives := _remove_knives(target_unit)
		if knives <= 0:
			return _failure(state, rng)
		return _apply(
			state, rng, actor_id, -1, unit_id,
			[{"type_key": &"damage", "params": {"amount": knives * 6}}]
		)
	var raw_items: Variant = state.ground_items.get(target_cell, [])
	if not raw_items is Array or (raw_items as Array).is_empty():
		return _failure(state, rng)
	for value: Variant in raw_items:
		state.collected_items.append(StringName(String(value)))
	state.ground_items.erase(target_cell)
	return _success(state, rng)


static func _resolve_requisition(
	state: BattleState, rng: Variant, _source: BattleCardState, choices: Array[int]
) -> Dictionary:
	if choices.size() != 1:
		return _failure(state, rng)
	var picked := state.deck.get_card(choices[0])
	if picked == null or not state.deck.move_card(picked.battle_uid, DeckState.ZONE_DRAW, DeckState.ZONE_HAND):
		return _failure(state, rng)
	picked.runtime_data["turn_damage_bonus"] = 6
	picked.runtime_data["turn_damage_bonus_round"] = state.round_index
	return _success(state, rng)


static func _resolve_cautious(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState
) -> Dictionary:
	var actor := state.get_unit(actor_id)
	if actor == null:
		return _failure(state, rng)
	var courage := maxi(0, actor.get_resource(&"courage"))
	actor.set_resource(&"courage", 0)
	return _block(state, rng, actor_id, card, float(courage * 2))


static func _resolve_generate_fists(state: BattleState, rng: Variant) -> Dictionary:
	var card_system := CardSystem.new()
	for _i in range(3):
		var uid := _allocate_card_uid(state.deck)
		var generated := card_system.create_generated_card(TOKEN_FIST, uid)
		state.deck.add_card(generated, DeckState.ZONE_HAND)
	return _success(state, rng)


static func _resolve_technique_insight(
	state: BattleState, rng: Variant, choices: Array[int]
) -> Dictionary:
	if choices.size() != 1:
		return _failure(state, rng)
	var picked := state.deck.get_card(choices[0])
	if picked == null:
		return _failure(state, rng)
	picked.cost_modifier -= 1
	return _success(state, rng)


static func _resolve_dismiss(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, choices: Array[int]
) -> Dictionary:
	if choices.size() > 2:
		return _failure(state, rng)
	for uid: int in choices:
		if not state.deck.move_card(uid, DeckState.ZONE_HAND, DeckState.ZONE_EXHAUST):
			return _failure(state, rng)
	return _block(state, rng, actor_id, card, float(choices.size() * 8))


static func _resolve_inspire(state: BattleState, rng: Variant, actor_id: int) -> Dictionary:
	var actor := state.get_unit(actor_id)
	if actor == null:
		return _failure(state, rng)
	var amount := 7 if actor.get_resource(&"courage") <= 0 else 3
	return _apply(
		state, rng, actor_id, -1, null,
		[{"type_key": &"resource", "params": {
			"key": &"courage", "operation": &"add", "amount": amount, "target_mode": &"source"
		}}]
	)


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


static func _resolve_copy(state: BattleState, rng: Variant, choices: Array[int]) -> Dictionary:
	if choices.size() != 1:
		return _failure(state, rng)
	var source := state.deck.get_card(choices[0])
	if source == null:
		return _failure(state, rng)
	var copy := source.duplicate_state()
	copy.battle_uid = _allocate_card_uid(state.deck)
	copy.source_run_uid = -1
	copy.generated = true
	if not state.deck.add_card(copy, DeckState.ZONE_HAND):
		return _failure(state, rng)
	return _success(state, rng)


static func _resolve_dash_slash(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	var direction: Variant = EffectStateAccess.target_direction(_context(actor_id, target))
	if not direction is Vector2i or (direction as Vector2i) == Vector2i.ZERO:
		return _failure(state, rng)
	var dir := direction as Vector2i
	var board := state.board
	var from := board.get_unit_cell(actor_id)
	var cur := from
	var moved := 0
	var hit_id := -1
	for _step in range(3):
		var next := cur + dir
		if not board.is_inside(next) or not board.is_traversable(next):
			break
		if board.is_occupied(next):
			var candidate := board.get_unit_at(next)
			var unit := state.get_unit(candidate)
			if unit != null and unit.team == UnitState.Team.ENEMY and unit.is_alive():
				hit_id = candidate
			break
		cur = next
		moved += 1
	var events := EventBatch.new()
	if cur != from:
		board.move_unit(actor_id, cur)
		events.push_back(EffectEvent.create(
			EffectStateAccess.allocate_event_seq(state),
			&"unit_moved",
			actor_id,
			actor_id,
			{"cell": from},
			{"cell": cur},
			{"path": [from, cur], "move_points": moved}
		))
	if hit_id < 0:
		return _success(state, rng, events)
	var amount := 10.0 + float(moved * 5)
	return _damage(state, rng, actor_id, card, hit_id, amount, events)


static func _resolve_starter_charge(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	var target_id := _target_unit_id(target)
	if target_id < 0:
		return _failure(state, rng)
	var destination := _starter_charge_destination(state, actor_id, target_id)
	if destination == BoardState.INVALID_CELL:
		return _failure(state, rng)
	var board := state.board
	var from := board.get_unit_cell(actor_id)
	var events := EventBatch.new()
	if destination != from:
		var displacement := Displacement.move(board, actor_id, destination, 2)
		if not displacement.moved:
			return _failure(state, rng)
		events.push_back(EffectEvent.create(
			EffectStateAccess.allocate_event_seq(state),
			&"unit_moved",
			actor_id,
			actor_id,
			{"cell": displacement.from_cell},
			{"cell": displacement.to_cell},
			{
				"path": displacement.path.duplicate(),
				"move_points": maxi(0, displacement.path.size() - 1),
			}
		))
	return _damage(state, rng, actor_id, card, target, 5.0, events)


static func _resolve_starter_relentless(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	var used_once := bool(card.runtime_data.get("relentless_used_once", false))
	var amount := 11.0 if used_once else 6.0
	var result := _damage(state, rng, actor_id, card, target, amount)
	if bool(result.get("ok", false)):
		var out := result["state_out"] as BattleState
		var out_card := out.deck.get_card(card.battle_uid)
		if out_card != null:
			out_card.runtime_data["relentless_used_once"] = true
	return result


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


static func _resolve_kick_backflip(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	var target_id := _target_unit_id(target)
	var target_cell := state.board.get_unit_cell(target_id)
	var source_cell := state.board.get_unit_cell(actor_id)
	var result := _damage(state, rng, actor_id, card, target, 9.0)
	if not bool(result.get("ok", false)):
		return result
	var out := result["state_out"] as BattleState
	var events := result["events"] as EventBatch
	var target_unit := out.get_unit(target_id)
	if target_unit != null and target_unit.is_alive():
		var pushed := _apply(
			out, result["rng_out"], actor_id, card.battle_uid, target,
			[{"type_key": &"push", "params": {"steps": 1, "direction_mode": &"away_from_source"}}],
			events
		)
		if not bool(pushed.get("ok", false)):
			return pushed
		out = pushed["state_out"]
		result = pushed
	var retreat := Vector2i(signi(source_cell.x - target_cell.x), signi(source_cell.y - target_cell.y))
	if retreat != Vector2i.ZERO:
		var self_push := _apply(
			out, result["rng_out"], actor_id, card.battle_uid, actor_id,
			[{"type_key": &"push", "direction": retreat, "params": {"steps": 1}}],
			result["events"]
		)
		if bool(self_push.get("ok", false)):
			return self_push
	return result


static func _resolve_hook(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	var target_id := _target_unit_id(target)
	var before := state.board.get_unit_cell(target_id)
	var source := state.board.get_unit_cell(actor_id)
	var direction := Vector2i(signi(source.x - before.x), signi(source.y - before.y))
	var pulled := _apply(
		state, rng, actor_id, card.battle_uid, target,
		[{"type_key": &"push", "direction": direction, "params": {"steps": 2}}]
	)
	if not bool(pulled.get("ok", false)):
		return pulled
	var out := pulled["state_out"] as BattleState
	var after := out.board.get_unit_cell(target_id)
	var moved := maxi(absi(after.x - before.x), absi(after.y - before.y))
	var amount := 5.0 * (1.0 + 0.12 * float(moved))
	return _damage(
		out, pulled["rng_out"], actor_id, card, target, amount, pulled["events"]
	)


static func _resolve_whirlwind(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState
) -> Dictionary:
	var hits := _enemies_adjacent(state, actor_id)
	var effects: Array = []
	for enemy_id: int in hits:
		effects.append({
			"type_key": &"damage",
			"target": enemy_id,
			"params": {"amount": _damage_amount(card, state.round_index, 5.0)},
		})
	if not hits.is_empty():
		effects.append({
			"type_key": &"block",
			"params": {"amount": hits.size() * 2 + card.block_modifier, "target_mode": &"source"},
		})
	return _apply(state, rng, actor_id, card.battle_uid, null, effects)


static func _resolve_throwing_knife(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	return _apply(
		state, rng, actor_id, card.battle_uid, target,
		[
			{"type_key": &"damage", "params": {"amount": _damage_amount(card, state.round_index, 8.0)}},
			{"type_key": &"apply_status", "params": {
				"status_id": StatusRules.KNIFE_MARK, "stacks": 1, "persistent": true
			}},
		]
	)


static func _resolve_blood_sword(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	var target_id := _target_unit_id(target)
	var result := _damage(state, rng, actor_id, card, target, 9.0)
	if not bool(result.get("ok", false)):
		return result
	var out := result["state_out"] as BattleState
	var target_unit := out.get_unit(target_id)
	if target_unit != null and target_unit.is_alive():
		return result
	var actor := out.get_unit(actor_id)
	if actor == null:
		return result
	actor.max_hp += 3
	out.run_changes["max_hp_delta"] = int(out.run_changes.get("max_hp_delta", 0)) + 3
	return _apply(
		out, result["rng_out"], actor_id, card.battle_uid, null,
		[{"type_key": &"heal", "params": {"amount": 3, "target_mode": &"source"}}],
		result["events"]
	)


static func _resolve_demon_blade(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	var target_id := _target_unit_id(target)
	var before := state.get_unit(target_id)
	var hp_before := before.hp if before != null else 0
	var result := _damage(state, rng, actor_id, card, target, 6.0)
	if bool(result.get("ok", false)):
		var after := (result["state_out"] as BattleState).get_unit(target_id)
		if after != null and after.hp < hp_before:
			var out_card := (result["state_out"] as BattleState).deck.get_card(card.battle_uid)
			if out_card != null:
				out_card.damage_modifier += 4
	return result


static func _resolve_damage_status(
	state: BattleState,
	rng: Variant,
	actor_id: int,
	card: BattleCardState,
	target: Variant,
	amount: float,
	status_id: StringName
) -> Dictionary:
	return _apply(
		state, rng, actor_id, card.battle_uid, target,
		[
			{"type_key": &"damage", "params": {"amount": _damage_amount(card, state.round_index, amount)}},
			{"type_key": &"apply_status", "params": {"status_id": status_id, "stacks": 1, "duration": 1}},
		]
	)


static func _resolve_technique_synergy(
	state: BattleState,
	rng: Variant,
	actor_id: int,
	card: BattleCardState,
	target: Variant,
	command: PlayCardsCommand,
	card_defs: Dictionary
) -> Dictionary:
	var technique_value := 0.0
	for index: int in range(command.card_uids.size()):
		var uid := command.card_uids[index]
		if uid == card.battle_uid:
			continue
		var other := state.deck.get_card(uid)
		var other_def := _def_for_card(card_defs, other)
		if other_def != null and other_def.card_category == CardDef.CardCategory.TECHNIQUE:
			var other_target: Variant = command.targets[index] if index < command.targets.size() else null
			technique_value = _estimate_technique_damage(state, other, other_def, other_target)
			break
	return _damage(state, rng, actor_id, card, target, technique_value * 1.5)


static func _resolve_overflow(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	var target_id := _target_unit_id(target)
	var target_unit := state.get_unit(target_id)
	if target_unit == null:
		return _failure(state, rng)
	var hp_before := target_unit.hp
	var target_cell := state.board.get_unit_cell(target_id)
	var result := _damage(state, rng, actor_id, card, target, 7.0)
	if not bool(result.get("ok", false)):
		return result
	var out := result["state_out"] as BattleState
	var after := out.get_unit(target_id)
	if after != null and after.is_alive():
		return result
	var overflow := 0
	var batch := result["events"] as EventBatch
	for event: GameEvent in batch.events:
		if event is EffectEvent and event.type_key == &"damage" and event.target_id == target_id:
			overflow = maxi(0, int((event as EffectEvent).payload.get("hp_damage", 0)) - hp_before)
	if overflow <= 0:
		return result
	var effects: Array = []
	for enemy_id: int in out.alive_enemy_ids():
		if enemy_id == target_id:
			continue
		var cell := out.board.get_unit_cell(enemy_id)
		if maxi(absi(cell.x - target_cell.x), absi(cell.y - target_cell.y)) <= 1:
			effects.append({"type_key": &"damage", "target": enemy_id, "params": {"amount": overflow}})
	return _apply(out, result["rng_out"], actor_id, card.battle_uid, null, effects, batch)


static func _resolve_rooted_attack(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, target: Variant
) -> Dictionary:
	var actor := state.get_unit(actor_id)
	if actor == null:
		return _failure(state, rng)
	var move := maxi(0, actor.get_resource(TurnSystem.MOVE_RESOURCE))
	actor.set_resource(TurnSystem.MOVE_RESOURCE, 0)
	return _damage(state, rng, actor_id, card, target, float(move * 4))


static func _resolve_hold_back(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState
) -> Dictionary:
	var result := _block(state, rng, actor_id, card, 5.0)
	if not bool(result.get("ok", false)):
		return result
	var out := result["state_out"] as BattleState
	var card_system := CardSystem.new()
	var draw_result := card_system.draw_cards(out.deck, 1, _battle_rng(result["rng_out"]))
	var drawn: Array = draw_result.get("cards", [])
	if not drawn.is_empty():
		var drawn_card := out.deck.get_card(int(drawn[0]))
		if drawn_card != null:
			drawn_card.upgrade_level += 1
	return result


static func _resolve_stress_block(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState, choices: Array[int]
) -> Dictionary:
	if choices.size() != 1 or not state.deck.move_card(choices[0], DeckState.ZONE_HAND, DeckState.ZONE_DISCARD):
		return _failure(state, rng)
	return _block(state, rng, actor_id, card, 10.0)


static func _resolve_rooted_defense(
	state: BattleState, rng: Variant, actor_id: int, card: BattleCardState
) -> Dictionary:
	var actor := state.get_unit(actor_id)
	if actor == null:
		return _failure(state, rng)
	var move := maxi(0, actor.get_resource(TurnSystem.MOVE_RESOURCE))
	actor.set_resource(TurnSystem.MOVE_RESOURCE, 0)
	return _block(state, rng, actor_id, card, float(move * 3))


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
