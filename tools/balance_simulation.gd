extends RefCounted
## 固定策略压力测试；不代表真人胜率。只通过正式规则规划和 BattleSession 提交。
const DB_SCRIPT := preload("res://autoload/content_db.gd")
var _db: Node
var _command_id := 100
var _planner := ComboPlanner.new()

func run(samples: int = 6) -> void:
	_db = DB_SCRIPT.new()
	_db.load_catalog()
	var results: Array = []
	for act in range(1, 4):
		for tier: String in ["monster", "elite", "boss"]:
			for i in range(samples):
				var result := _battle(act, tier, 1000 + i * 131 + act * 17)
				results.append(result)
			print("SIM_PROGRESS act=", act, " tier=", tier, " completed=", results.size())
	var output := {"policy": "greedy single-card, approach movement, no retreat, no relics, independent full-health fights", "samples_per_group": samples, "results": results}
	var file := FileAccess.open("res://.validation/balance_simulation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	_db.free()
	_db = null
	_planner = null
	print("SIMULATION_OK fights=", results.size())

func _battle(act: int, tier: String, seed_value: int) -> Dictionary:
	var run := RunSession.create_run(&"character.hero", str(seed_value), _db)
	run.act_index = act - 1
	# 成长样本是明确固定的牌组，不能用来声称随机路线必然形成这些构筑。
	if act >= 2:
		for i in range(2):
			run.deck.pop_back()
		for n: int in [29, 17, 38, 36]:
			run.add_card(StringName("card.reward.%02d" % n))
		run.deck[0].upgrade_level = 1
		run.deck[3].upgrade_level = 1
	if act >= 3:
		for n: int in [16, 23, 31, 22]:
			run.add_card(StringName("card.reward.%02d" % n))
		for i in range(1, run.deck.size(), 3):
			run.deck[i].upgrade_level = 1
	var rng := RngStreams.new()
	rng.derive_streams(str(seed_value))
	var pool := load("res://content/pools/act%d_monsters.tres" % act) as MonsterPoolDef
	var encounter: EncounterDef
	if tier == "boss":
		encounter = load("res://content/encounters/boss_act%d.tres" % act) as EncounterDef
	elif tier == "elite":
		var elite := load("res://content/pools/act%d_elite.tres" % act) as MonsterPoolDef
		encounter = MonsterPool.build_elite_encounter(elite, pool, 5, rng.get_stream(&"encounter"))
	else:
		encounter = MonsterPool.build_encounter(pool, 5, rng.get_stream(&"encounter"))
	var setup := EncounterBuilder.build(encounter, run, rng, _db, Vector2i(2, 7))
	var session := BattleSession.new()
	session.setup(setup.rng, setup.state, setup.card_defs, setup.enemy_behaviors, setup.enemy_actions, CardTargetRules.validate_range, setup.summon_pool)
	var rounds := 0
	var rejected := 0
	var steps := 0
	while not session.state.is_terminal() and rounds < 40:
		rounds += 1
		var moved := false
		for _action in range(24):
			if session.state.is_terminal():
				break
			var command := _best_card(session, setup.card_defs)
			if command == null and not moved:
				command = _approach(session.state)
				moved = true
			if command == null:
				break
			_stamp(command)
			var result := session.submit(command)
			steps += 1
			if not result.accepted:
				rejected += 1
				break
			session.finish_presentation()
		if not session.state.is_terminal():
			var end := EndTurnCommand.new()
			_stamp(end)
			if not session.submit(end).accepted:
				rejected += 1
				break
			session.finish_presentation()
	return {"act": act, "tier": tier, "seed": seed_value, "enemies": encounter.enemy_ids, "victory": session.state.phase == BattleState.Phase.VICTORY, "rounds": rounds, "hp": session.state.get_unit(1).hp, "hp_lost": run.hp - session.state.get_unit(1).hp, "timeout": rounds >= 40, "rejected": rejected, "actions": steps, "final_units": _unit_summary(session.state)}

func _best_card(session: BattleSession, defs: Dictionary) -> GameCommand:
	var state := session.state
	var best: GameCommand = null
	var best_score := 0.1
	var end := EndTurnCommand.new()
	end.actor_id = 1
	var next: Dictionary = session._resolve_command(end)
	var incoming := 0.0
	if bool(next.get("ok", false)):
		incoming = _incoming(next.get("events"))
	for uid: int in state.deck.hand:
		var card := state.deck.get_card(uid)
		var def := defs[card.card_id] as CardDef
		if card.effective_cost(def) > state.get_unit(1).get_resource(&"energy"):
			continue
		var rule := def.get_target_rule(card.upgrade_level)
		var targets: Array = [null]
		if rule is TargetSpec.UnitTarget or rule is TargetSpec.CellTarget:
			targets.clear()
			for id: int in state.alive_enemy_ids():
				if rule is TargetSpec.UnitTarget:
					var t := TargetSpec.UnitTarget.new()
					t.unit_id = id
					targets.append(t)
				else:
					var t := TargetSpec.CellTarget.new()
					t.cell = state.board.get_unit_cell(id)
					targets.append(t)
		elif rule is TargetSpec.DirectionTarget:
			targets.clear()
			for dir: Vector2i in Pathfinder.ORTHO_DIRS:
				var t := TargetSpec.DirectionTarget.new()
				t.direction = dir
				targets.append(t)
		for target: Variant in targets:
			var command := PlayCardsCommand.new()
			command.actor_id = 1
			command.card_uids = [uid]
			command.targets = [target]
			var choice := FormalCardRules.choice_request(state, uid, [uid], defs)
			if not choice.is_empty():
				if Array(choice.candidates).size() < int(choice.min_count):
					continue
				command.choices[uid] = Array(choice.candidates).slice(0, maxi(1, int(choice.min_count)))
			var result := _planner.build_plan_for_actor(state, state.deck, command, defs, session._rng, &"energy", CardTargetRules.validate_range)
			if not bool(result.get("ok", false)):
				continue
			var out := result["state_out"] as BattleState
			var score := _score(state, out, incoming) - float(card.effective_cost(def)) * 0.15
			if score > best_score:
				best_score = score
				best = command
	return best

func _score(before: BattleState, after: BattleState, incoming: float) -> float:
	var score := 0.0
	for id: int in before.alive_enemy_ids():
		var a := before.get_unit(id)
		var b := after.get_unit(id)
		score += a.hp - b.hp + (a.block - b.block) * 0.35
		if not b.is_alive():
			score += 8.0
		for status: StringName in [StatusRules.POISON, StatusRules.STUN, StatusRules.SLOW]:
			score += (StatusRules.stacks(b, status) - StatusRules.stacks(a, status)) * (6.0 if status == StatusRules.STUN else 1.7)
	var a := before.get_unit(1)
	var b := after.get_unit(1)
	score += (b.hp - a.hp) * 2.0
	score += minf(incoming, maxf(0, b.block - a.block)) * 0.9
	score += (b.get_resource(&"courage") - a.get_resource(&"courage")) * 2.0
	score += (after.deck.hand.size() - before.deck.hand.size() + 1) * 2.0
	for uid: int in after.deck.hand:
		if before.deck.get_card(uid) != null:
			score += (after.deck.get_card(uid).upgrade_level - before.deck.get_card(uid).upgrade_level) * 2.0
	return score

func _incoming(events: EventBatch) -> float:
	var damage := 0.0
	if events != null:
		for event: GameEvent in events.events:
			if event is EffectEvent and event.type_key == &"damage" and event.target_id == 1:
				damage += float(event.payload.get("hp_damage", 0))
	return damage

func _approach(state: BattleState) -> GameCommand:
	var actor := state.get_unit(1)
	if StatusRules.move_locked(actor):
		return null
	var from := state.board.get_unit_cell(1)
	var target := BoardState.INVALID_CELL
	var distance := 999
	for id: int in state.alive_enemy_ids():
		var cell := state.board.get_unit_cell(id)
		var dist := absi(cell.x - from.x) + absi(cell.y - from.y)
		if dist < distance:
			distance = dist
			target = cell
	if distance <= 1:
		return null
	var best := from
	for cell: Vector2i in Pathfinder.reachable_cells(state.board, from, actor.get_resource(&"move_points")):
		var dist := absi(cell.x - target.x) + absi(cell.y - target.y)
		if dist < distance:
			distance = dist
			best = cell
	if best == from:
		return null
	var command := MoveCommand.new()
	command.actor_id = 1
	command.destination = best
	return command

func _stamp(command: GameCommand) -> void:
	_command_id += 1
	command.command_id = _command_id
	command.actor_id = 1


func _unit_summary(state: BattleState) -> Array:
	var units: Array = []
	for id: int in state.units:
		units.append({"id": id, "hp": state.get_unit(id).hp, "cell": str(state.board.get_unit_cell(id))})
	return units
