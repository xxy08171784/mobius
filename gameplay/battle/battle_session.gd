class_name BattleSession
extends RefCounted
## 战斗协调器：唯一规则命令入口。拥有 BattleState 与规则服务。
## 具体算法分置于卡牌/棋盘/效果模块；本类只做校验、编排与提交。

const MAX_SEEN_COMMANDS: int = 64

var state: BattleState = null
var _rng: RngStreams = null
var _card_defs: Dictionary = {}
var _enemy_behaviors: Dictionary = {}
var _enemy_actions: Dictionary = {}
var _summon_pool: Array = []
var _target_validator: Callable = Callable()
var _result_cache: Dictionary = {}
var _result_cache_order: Array[int] = []
var _turn_system := TurnSystem.new()
var _combo_planner := ComboPlanner.new()
var _resolver := EffectResolver.new()


## 装配一场战斗。RunState 尚未落地时，initial_state 由 BattleFactory.create_state() 提供。
## SETUP 状态会立即进入首个 ROUND_START，补牌并锁定敌人意图。
func setup(
	rng: RngStreams,
	initial_state: BattleState = null,
	card_defs: Dictionary = {},
	enemy_behaviors: Dictionary = {},
	enemy_actions: Dictionary = {},
	target_validator: Callable = Callable(),
	summon_pool: Array = []
) -> EventBatch:
	state = initial_state if initial_state != null else BattleState.new()
	_card_defs = card_defs.duplicate()
	_enemy_behaviors = enemy_behaviors.duplicate()
	_enemy_actions = enemy_actions.duplicate()
	_summon_pool = summon_pool.duplicate()
	_target_validator = target_validator if target_validator.is_valid() else CardTargetRules.validate_range
	_collect_actions_from_behaviors()
	_result_cache.clear()
	_result_cache_order.clear()

	_rng = RngStreams.new()
	if not state.rng_snapshot.is_empty():
		_rng.restore(state.rng_snapshot)
	elif rng != null:
		_rng.restore(rng.snapshot())
	else:
		_rng.derive_streams("0")

	var events := EventBatch.new()
	if state.phase == BattleState.Phase.SETUP:
		var started := _turn_system.begin_round(state, _rng, _enemy_behaviors)
		if bool(started.get("ok", false)):
			events = started.get("events", events)
	state.rng_snapshot = _rng.snapshot()
	return events


## 唯一命令入口。
## 成功：在工作快照上结算，一次性提交 state_out/rng_out，version+1，返回事件。
## 失败：零副作用，返回错误码与本地化文本键。
func submit(command: GameCommand) -> CommandResult:
	return _evaluate(command, true)


## 与 submit 共用唯一规则路径，但不提交、不记录 command ID、不推进正式 RNG。
func preview(command: GameCommand) -> CommandResult:
	return _evaluate(command, false)


## Presenter 播完 CommandResult.events 后调用。规则层不等待 Tween。
func finish_presentation() -> void:
	if state == null or state.phase != BattleState.Phase.RESOLVING:
		return
	state.phase = state.resume_phase
	state.command_locked = false


func battle_result() -> BattleResult:
	if state == null or not state.is_terminal():
		return null
	var result := BattleResult.new()
	result.battle_id = state.battle_id
	result.run_instance_id = state.run_instance_id
	result.rng_snapshot = state.rng_snapshot.duplicate(true)
	result.victory = state.phase == BattleState.Phase.VICTORY
	var player_hp: Dictionary = {}
	for player_id: int in state.player_ids():
		player_hp[player_id] = state.get_unit(player_id).hp
	result.persistent_changes = state.run_changes.duplicate(true)
	result.persistent_changes["player_hp"] = player_hp
	return result


## 某敌人行为表中的全部行动（威胁格显示用；非 SequenceBehavior 返回空）。
func enemy_actions_for(unit_id: int) -> Array[EnemyActionDef]:
	var out: Array[EnemyActionDef] = []
	var behavior: Variant = _enemy_behaviors.get(unit_id)
	if behavior is SequenceBehaviorDef:
		for action: EnemyActionDef in (behavior as SequenceBehaviorDef).sequence:
			if action != null:
				out.append(action)
	return out


func _evaluate(command: GameCommand, commit: bool) -> CommandResult:
	if state == null or command == null:
		return _reject(command, CommandResult.ErrorCode.PHASE, commit)

	# 1) 去重必须最先。重复命令返回首次结果。
	if commit:
		var duplicate := _duplicate_result(command.command_id)
		if duplicate != null:
			return duplicate

	# 2) 阶段 / 命令锁。
	if state.command_locked:
		return _reject(command, CommandResult.ErrorCode.BUSY, commit)
	if state.phase != BattleState.Phase.PLAYER_INPUT or state.is_terminal():
		return _reject(command, CommandResult.ErrorCode.PHASE, commit)

	# 3) 施法者。
	var actor := state.get_unit(command.actor_id)
	if actor == null or not actor.is_alive() or not actor.is_player():
		return _reject(command, CommandResult.ErrorCode.ACTOR, commit)

	# 4) 命令类型。
	if not (command is PlayCardsCommand or command is MoveCommand or command is EndTurnCommand):
		return _reject(command, CommandResult.ErrorCode.COMMAND_TYPE, commit)
	if command is MoveCommand and state.move_points_per_round <= 0:
		return _reject(command, CommandResult.ErrorCode.COMMAND_TYPE, commit)

	# 5) 费用。
	if command is PlayCardsCommand:
		var cost_check := _known_combo_cost(command as PlayCardsCommand)
		if bool(cost_check.get("known", false)):
			if int(cost_check.get("cost", 0)) > actor.get_resource(TurnSystem.ENERGY_RESOURCE):
				return _reject(command, CommandResult.ErrorCode.COST, commit)
	elif command is MoveCommand:
		var move_cost := _move_cost(command as MoveCommand)
		if move_cost >= 0 and move_cost > actor.get_resource(TurnSystem.MOVE_RESOURCE):
			return _reject(command, CommandResult.ErrorCode.COST, commit)

	# 6/7) 目标与组合，并在独立快照上结算。
	var resolution := _resolve_command(command)
	if not bool(resolution.get("ok", false)):
		return _reject(
			command,
			_map_resolution_error(resolution.get("error_code", &"combo")),
			commit
		)

	var work_state: BattleState = resolution["state_out"]
	var work_rng: RngStreams = resolution["rng_out"]
	var events: EventBatch = resolution.get("events", EventBatch.new())
	if command is PlayCardsCommand:
		RelicSystem.trigger(work_state, &"card_played")
	var took_damage := false
	for id: int in state.player_ids():
		if work_state.get_unit(id) != null and work_state.get_unit(id).hp < state.get_unit(id).hp:
			took_damage = true
	if took_damage:
		RelicSystem.trigger(work_state, &"damage_taken")

	var terminal := _turn_system.evaluate_outcome(work_state)
	if terminal != BattleState.Phase.SETUP:
		work_state.phase = terminal

	if not commit:
		var preview_result := CommandResult.new()
		preview_result.accepted = true
		preview_result.error_code = CommandResult.ErrorCode.OK
		preview_result.text_key = &""
		preview_result.events = events
		preview_result.state_version = state.version
		return preview_result

	work_state.version = state.version + 1
	work_state.rng_snapshot = work_rng.snapshot()
	if not work_state.is_terminal():
		work_state.resume_phase = work_state.phase
		work_state.phase = BattleState.Phase.RESOLVING
		work_state.command_locked = true
	else:
		work_state.resume_phase = work_state.phase
		work_state.command_locked = false

	state = work_state
	_rng = work_rng
	if resolution.has("enemy_behaviors"):
		_enemy_behaviors = resolution.enemy_behaviors
		_enemy_actions = resolution.enemy_actions

	var result := CommandResult.new()
	result.accepted = true
	result.error_code = CommandResult.ErrorCode.OK
	result.events = events
	result.state_version = state.version
	_record_accepted(command.command_id, result)
	return _clone_result(result)


func _resolve_command(command: GameCommand) -> Dictionary:
	if command is PlayCardsCommand:
		var planned := _combo_planner.build_plan_for_actor(
			state,
			state.deck,
			command as PlayCardsCommand,
			_card_defs,
			_rng,
			TurnSystem.ENERGY_RESOURCE,
			_target_validator
		)
		if not bool(planned.get("ok", false)):
			return planned
		var planned_state: BattleState = planned["state_out"]
		var actor := planned_state.get_unit(command.actor_id)
		actor.set_resource(
			TurnSystem.ENERGY_RESOURCE,
			int(planned.get("resource_after", actor.get_resource(TurnSystem.ENERGY_RESOURCE)))
		)
		planned_state.deck = planned["deck_out"]
		return {
			"ok": true,
			"state_out": planned_state,
			"rng_out": planned["rng_out"],
			"events": planned["events"],
		}

	if command is MoveCommand:
		var move := command as MoveCommand
		if not _move_target_valid(move):
			return {"ok": false, "error_code": &"target"}
		var work_state := SaveCodec.new().clone_state(state) as BattleState
		var work_rng := _rng.clone()
		var actor := work_state.get_unit(move.actor_id)
		var from_cell := work_state.board.get_unit_cell(move.actor_id)
		var path := Pathfinder.find_path(work_state.board, from_cell, move.destination)
		var steps := maxi(0, path.size() - 1)
		var resolved := _resolver.resolve(
			work_state,
			{
				"context": {"source_unit_id": move.actor_id},
				"effects": [{
					"type_key": &"move",
					"target": {"cell": move.destination},
					"params": {"move_points": actor.get_resource(TurnSystem.MOVE_RESOURCE)},
				}],
			},
			work_rng
		)
		if not bool(resolved.get("ok", false)):
			return {"ok": false, "error_code": &"target"}
		var out: BattleState = resolved["state_out"]
		out.get_unit(move.actor_id).add_resource(TurnSystem.MOVE_RESOURCE, -steps)
		return {
			"ok": true,
			"state_out": out,
			"rng_out": resolved["rng_out"],
			"events": resolved["events"],
		}

	if command is EndTurnCommand:
		var work_state := SaveCodec.new().clone_state(state) as BattleState
		var work_rng := _rng.clone()
		var work_behaviors := _enemy_behaviors.duplicate()
		var work_actions := _enemy_actions.duplicate()
		var ended := _turn_system.run_end_turn(
			work_state,
			work_rng,
			work_behaviors,
			work_actions,
			_summon_pool
		)
		if not bool(ended.get("ok", false)):
			return {
				"ok": false,
				"error_code": ended.get("error_code", &"combo"),
			}
		return {
			"ok": true,
			"state_out": work_state,
			"rng_out": work_rng,
			"events": ended.get("events", EventBatch.new()),
			"enemy_behaviors": work_behaviors,
			"enemy_actions": work_actions,
		}

	return {"ok": false, "error_code": &"command_type"}


func _known_combo_cost(command: PlayCardsCommand) -> Dictionary:
	var seen: Dictionary = {}
	var total := 0
	for uid: int in command.card_uids:
		if seen.has(uid):
			return {"known": false}
		seen[uid] = true
		var card := state.deck.get_card(uid)
		if card == null:
			return {"known": false}
		var definition: CardDef = _card_defs.get(card.card_id)
		if definition == null:
			definition = _card_defs.get(String(card.card_id))
		if definition == null:
			return {"known": false}
		total += card.effective_cost(definition)
	return {"known": true, "cost": total}


func _move_cost(command: MoveCommand) -> int:
	var from_cell := state.board.get_unit_cell(command.actor_id)
	if from_cell == BoardState.INVALID_CELL:
		return -1
	var path := Pathfinder.find_path(state.board, from_cell, command.destination)
	return -1 if path.is_empty() else path.size() - 1


func _move_target_valid(command: MoveCommand) -> bool:
	if StatusRules.move_locked(state.get_unit(command.actor_id)):
		return false
	if not state.board.is_inside(command.destination):
		return false
	if state.board.is_occupied(command.destination):
		return false
	return _move_cost(command) >= 0


func _map_resolution_error(code: Variant) -> CommandResult.ErrorCode:
	match StringName(String(code)):
		ComboPlanner.ERROR_COST:
			return CommandResult.ErrorCode.COST
		ComboPlanner.ERROR_TARGET, &"target", &"invalid_target":
			return CommandResult.ErrorCode.TARGET
		EffectResolver.ERROR_TRIGGER_OVERFLOW, &"trigger_overflow":
			return CommandResult.ErrorCode.OVERFLOW
		&"command_type":
			return CommandResult.ErrorCode.COMMAND_TYPE
		_:
			return CommandResult.ErrorCode.COMBO


func _reject(
	command: GameCommand,
	error: CommandResult.ErrorCode,
	cache_result: bool
) -> CommandResult:
	var result := CommandResult.new()
	result.accepted = false
	result.error_code = error
	result.text_key = _error_text_key(error)
	result.events = null
	result.state_version = 0 if state == null else state.version
	if cache_result and command != null:
		_cache_result(command.command_id, _snapshot_result(result))
	return result


func _record_accepted(command_id: int, result: CommandResult) -> void:
	var snapshot := _snapshot_result(result)
	_cache_result(command_id, snapshot)
	if not state.seen_command_ids.has(command_id):
		state.seen_command_ids.append(command_id)
	state.command_result_snapshots[command_id] = snapshot
	while state.seen_command_ids.size() > MAX_SEEN_COMMANDS:
		var old_id: int = state.seen_command_ids.pop_front()
		state.command_result_snapshots.erase(old_id)


func _cache_result(command_id: int, snapshot: Dictionary) -> void:
	if _result_cache.has(command_id):
		_result_cache_order.erase(command_id)
	_result_cache[command_id] = snapshot
	_result_cache_order.append(command_id)
	while _result_cache_order.size() > MAX_SEEN_COMMANDS:
		var old_id: int = _result_cache_order.pop_front()
		_result_cache.erase(old_id)


func _duplicate_result(command_id: int) -> CommandResult:
	if _result_cache.has(command_id):
		return _result_from_snapshot(_result_cache[command_id])
	if state.seen_command_ids.has(command_id):
		if state.command_result_snapshots.has(command_id):
			return _result_from_snapshot(state.command_result_snapshots[command_id])
		var missing := CommandResult.new()
		missing.accepted = false
		missing.error_code = CommandResult.ErrorCode.DUPLICATE
		missing.text_key = _error_text_key(CommandResult.ErrorCode.DUPLICATE)
		missing.state_version = state.version
		return missing
	return null


func _snapshot_result(result: CommandResult) -> Dictionary:
	var event_data: Array = []
	if result.events != null:
		for event: GameEvent in result.events.events:
			var payload: Dictionary = {}
			if event is EffectEvent:
				payload = (event as EffectEvent).payload.duplicate(true)
			event_data.append({
				"seq": event.seq,
				"type_key": event.type_key,
				"source_id": event.source_id,
				"target_id": event.target_id,
				"before": event.before.duplicate(true),
				"after": event.after.duplicate(true),
				"payload": payload,
			})
	return {
		"accepted": result.accepted,
		"error_code": int(result.error_code),
		"text_key": result.text_key,
		"state_version": result.state_version,
		"events": event_data,
		"has_events": result.events != null,
	}


func _result_from_snapshot(data: Dictionary) -> CommandResult:
	var result := CommandResult.new()
	result.accepted = bool(data.get("accepted", false))
	result.error_code = int(data.get("error_code", CommandResult.ErrorCode.DUPLICATE))
	result.text_key = StringName(String(data.get("text_key", "")))
	result.state_version = int(data.get("state_version", 0))
	if bool(data.get("has_events", false)):
		result.events = EventBatch.new()
		for event_data: Dictionary in data.get("events", []):
			result.events.push_back(EffectEvent.create(
				int(event_data.get("seq", 0)),
				StringName(String(event_data.get("type_key", ""))),
				int(event_data.get("source_id", -1)),
				int(event_data.get("target_id", -1)),
				event_data.get("before", {}),
				event_data.get("after", {}),
				event_data.get("payload", {})
			))
	return result


func _clone_result(result: CommandResult) -> CommandResult:
	return _result_from_snapshot(_snapshot_result(result))


func _error_text_key(error: CommandResult.ErrorCode) -> StringName:
	match error:
		CommandResult.ErrorCode.DUPLICATE:
			return &"battle.error.duplicate"
		CommandResult.ErrorCode.PHASE:
			return &"battle.error.phase"
		CommandResult.ErrorCode.BUSY:
			return &"battle.error.busy"
		CommandResult.ErrorCode.ACTOR:
			return &"battle.error.actor"
		CommandResult.ErrorCode.COMMAND_TYPE:
			return &"battle.error.command_type"
		CommandResult.ErrorCode.COST:
			return &"battle.error.cost"
		CommandResult.ErrorCode.TARGET:
			return &"battle.error.target"
		CommandResult.ErrorCode.COMBO:
			return &"battle.error.combo"
		CommandResult.ErrorCode.OVERFLOW:
			return &"battle.error.overflow"
		_:
			return &""


func _collect_actions_from_behaviors() -> void:
	for behavior_value: Variant in _enemy_behaviors.values():
		if behavior_value is SequenceBehaviorDef:
			for action: EnemyActionDef in (behavior_value as SequenceBehaviorDef).sequence:
				if action != null:
					_enemy_actions[action.id] = action
