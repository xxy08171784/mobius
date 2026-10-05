class_name EnemyPlanner
extends RefCounted
## 意图规划（纯函数，**只规划不执行**；执行是 Track A 的 resolve()，Phase 3 接线）。
## 依据 development_split §3 B3：锁定格子优先、目标策略；被击退/堵路有明确降级路径（数据）。
##
## 目标策略：PLAYER 取最近玩家（Manhattan，平手取较小 unit_id，确定性）；SELF 锁自身；NONE 无目标。
## 降级：目标缺失/无法接近时改用 behavior.fallback_action_id（标记 is_fallback）；无 fallback 则返回空意图。
## §5.6 原规则不在仓库内：以下为据此的设计，需与架构文档/队友核对。


## 产出一份已锁定的意图。step = 敌人自增行动计数（回合系统维护）。
static func plan(board: BoardState, enemy: UnitState, behavior: BehaviorDef, step: int, players: Array[UnitState]) -> IntentState:
	var intent := IntentState.new()
	intent.actor_id = enemy.unit_id
	if not enemy.is_alive() or board.get_unit_cell(enemy.unit_id) == BoardState.INVALID_CELL:
		return intent  # 非在场敌人 -> 空意图
	if behavior == null:
		return intent
	var action := behavior.action_def_for(step)
	if action == null:
		return _degrade(board, enemy, behavior, players, intent)

	intent.action_id = action.id
	intent.target_policy = action.target_policy
	var enemy_cell := board.get_unit_cell(enemy.unit_id)

	var target := _resolve_target(board, enemy, enemy_cell, action.target_policy, players)
	if action.target_policy != EnemyActionDef.TargetPolicy.NONE and target == null:
		return _degrade(board, enemy, behavior, players, intent)
	if target != null:
		intent.locked_unit_id = target.unit_id
		intent.locked_cell = board.get_unit_cell(target.unit_id)

	match action.kind:
		EnemyActionDef.Kind.ATTACK, EnemyActionDef.Kind.CHARGE:
			intent.affected_cells = [intent.locked_cell]
			intent.magnitude = action.damage
		EnemyActionDef.Kind.DEFEND:
			intent.locked_unit_id = enemy.unit_id
			intent.locked_cell = enemy_cell
			intent.affected_cells = [enemy_cell]
			intent.magnitude = action.block
		EnemyActionDef.Kind.APPROACH:
			if target == null:
				return _degrade(board, enemy, behavior, players, intent)
			var dest := _approach_dest(board, enemy_cell, board.get_unit_cell(target.unit_id), action.move_steps)
			if dest == BoardState.INVALID_CELL:
				return _degrade(board, enemy, behavior, players, intent)
			intent.locked_cell = dest  # 锁定格子优先
			intent.affected_cells = [dest]
	return intent


## 按策略解析目标单位：PLAYER=最近玩家；SELF=自身；NONE=null。
static func _resolve_target(board: BoardState, enemy: UnitState, enemy_cell: Vector2i, policy: EnemyActionDef.TargetPolicy, players: Array[UnitState]) -> UnitState:
	match policy:
		EnemyActionDef.TargetPolicy.SELF:
			return enemy
		EnemyActionDef.TargetPolicy.PLAYER:
			return _nearest_player(board, enemy_cell, players)
		_:
			return null


## 最近的在世玩家（Manhattan；平手取较小 unit_id）。无则 null。
static func _nearest_player(board: BoardState, from_cell: Vector2i, players: Array[UnitState]) -> UnitState:
	var best: UnitState = null
	var best_dist := 1 << 30
	for p: UnitState in players:
		if not p.is_alive():
			continue
		var cell := board.get_unit_cell(p.unit_id)
		if cell == BoardState.INVALID_CELL:
			continue
		var dist := absi(cell.x - from_cell.x) + absi(cell.y - from_cell.y)
		if dist < best_dist or (dist == best_dist and best != null and p.unit_id < best.unit_id):
			best = p
			best_dist = dist
	return best


## 接近落点：在 move_steps 内可达（含原地）的格中，取离目标格最近者；平手按 (y,x)。
## 若最佳仍是原地（已贴脸/无可推进）返回 INVALID_CELL，交由调用方降级。
static func _approach_dest(board: BoardState, from_cell: Vector2i, target_cell: Vector2i, move_steps: int) -> Vector2i:
	var candidates := Pathfinder.reachable_cells(board, from_cell, move_steps)
	candidates.append(from_cell)
	var best := from_cell
	var best_dist := absi(target_cell.x - from_cell.x) + absi(target_cell.y - from_cell.y)
	for cell: Vector2i in candidates:
		var dist := absi(target_cell.x - cell.x) + absi(target_cell.y - cell.y)
		if dist < best_dist or (dist == best_dist and _precedes(cell, best)):
			best = cell
			best_dist = dist
	if best == from_cell:
		return BoardState.INVALID_CELL
	return best


static func _precedes(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


## 降级：改用 fallback_action_id，锁定最近玩家格；无 fallback 或无玩家则空意图（action_id 保持空）。
static func _degrade(board: BoardState, enemy: UnitState, behavior: BehaviorDef, players: Array[UnitState], intent: IntentState) -> IntentState:
	intent.is_fallback = true
	# 先清空原意图，再按 fallback 重建；无 fallback 则留下空意图。
	intent.action_id = &""
	intent.locked_unit_id = -1
	intent.locked_cell = Vector2i(-1, -1)
	intent.affected_cells = []
	intent.magnitude = 0
	if behavior.fallback_action_id == &"":
		return intent
	intent.action_id = behavior.fallback_action_id
	intent.target_policy = EnemyActionDef.TargetPolicy.PLAYER
	var enemy_cell := board.get_unit_cell(enemy.unit_id)
	var target := _nearest_player(board, enemy_cell, players)
	if target != null:
		intent.locked_unit_id = target.unit_id
		intent.locked_cell = board.get_unit_cell(target.unit_id)
		intent.affected_cells = [intent.locked_cell]
	return intent
