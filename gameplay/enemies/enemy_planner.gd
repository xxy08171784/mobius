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
		EnemyActionDef.Kind.ATTACK, EnemyActionDef.Kind.CHARGE, EnemyActionDef.Kind.DASH:
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
			var target_cell := board.get_unit_cell(target.unit_id)
			var path := plan_move(board, enemy, target_cell, action.move_steps, action)
			if path.size() < 2:
				return _degrade(board, enemy, behavior, players, intent)
			intent.locked_cell = path[path.size() - 1]  # 锁定格子优先（预告；执行时按当前目标重算）
			intent.affected_cells = [intent.locked_cell]
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


## 移动规划（纯函数）：返回 from->dest 的**真实路径**（含起点；长度 ≤ move_budget+1）。
## 空数组 = 原地不动。近战/远程由 action.kiting 决定：
##   近战(kiting=false)：优先"能打到目标"的落点（离目标最近）；都打不到则尽量接近；已能攻击即原地。
##   远程(kiting=true)：能打到目标时取**离目标最远**的落点（风筝）；都打不到则接近以进入射程。
## 平手按 (dist, y, x) 确定性裁决。执行层按**当前**目标格调用本函数即得到"持续接近/拉开"。
static func plan_move(
	board: BoardState,
	enemy: UnitState,
	target_cell: Vector2i,
	move_budget: int,
	action: EnemyActionDef
) -> Array[Vector2i]:
	if enemy == null or action == null or move_budget <= 0:
		return []
	var from_cell := board.get_unit_cell(enemy.unit_id)
	if from_cell == BoardState.INVALID_CELL or not board.is_inside(target_cell):
		return []
	var kiting := action.kiting

	var best := from_cell
	var best_hit := _can_hit(board, from_cell, target_cell, action)
	var best_dist := _metric(from_cell, target_cell)

	# 近战已能攻击 -> 停手，不为了"更近"做无意义的横向挪动。
	if not kiting and best_hit:
		return []

	for cell: Vector2i in Pathfinder.reachable_cells(board, from_cell, move_budget):
		var hit := _can_hit(board, cell, target_cell, action)
		var dist := _metric(cell, target_cell)
		if hit != best_hit:
			# 能打到的一律优于打不到的；同态下再比距离。
			if hit:
				best = cell
				best_hit = true
				best_dist = dist
			continue
		var better := (dist > best_dist) if (kiting and hit) else (dist < best_dist)
		if better or (dist == best_dist and _precedes(cell, best)):
			best = cell
			best_dist = dist

	if best == from_cell:
		return []
	return Pathfinder.find_path(board, from_cell, best)


## 纯接近（不看能否命中）：朝 target_cell 走 up to move_budget，返回真实路径（含起点）；无推进返回 []。
## DASH（横冲直撞）用——它总是想冲过去，不像 plan_move 近战那样"已能攻击就停手"。
static func plan_approach(board: BoardState, enemy_id: int, target_cell: Vector2i, move_budget: int) -> Array[Vector2i]:
	var from_cell := board.get_unit_cell(enemy_id)
	if move_budget <= 0 or from_cell == BoardState.INVALID_CELL or not board.is_inside(target_cell):
		return []
	var best := from_cell
	var best_dist := _metric(from_cell, target_cell)
	for cell: Vector2i in Pathfinder.reachable_cells(board, from_cell, move_budget):
		var dist := _metric(cell, target_cell)
		if dist < best_dist or (dist == best_dist and _precedes(cell, best)):
			best = cell
			best_dist = dist
	if best == from_cell:
		return []
	return Pathfinder.find_path(board, from_cell, best)


## 走位评分格距（曼哈顿）——与射程形状无关：形状只管"能否命中"，距离只管"更近/更远"。
## 用固定度量，UNLIMITED 射程的远程怪才能正确"拉开距离"。
static func _metric(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## cell 处能否命中 target_cell（射程形状 + 可选 LoS）。纯查询。
static func _can_hit(board: BoardState, cell: Vector2i, target_cell: Vector2i, action: EnemyActionDef) -> bool:
	if not BoardQuery.within_range(action.range_shape, cell, target_cell, action.range):
		return false
	if action.requires_los and not BoardQuery.has_line_of_sight(board, cell, target_cell):
		return false
	return true


## 该敌人在**当前格**上"所有攻击类行动射程的并集"（威胁格显示；纯查询，无副作用）。
## UNLIMITED 行动即全盘可见格。结果按 (y,x) 排序；无攻击行动或无该敌人时为空。
static func threat_cells(board: BoardState, enemy_id: int, actions: Array[EnemyActionDef]) -> Array[Vector2i]:
	var enemy_cell := board.get_unit_cell(enemy_id)
	if enemy_cell == BoardState.INVALID_CELL:
		return []
	var seen: Dictionary[Vector2i, bool] = {}
	for action: EnemyActionDef in actions:
		if action == null:
			continue
		if action.kind != EnemyActionDef.Kind.ATTACK \
			and action.kind != EnemyActionDef.Kind.CHARGE \
			and action.kind != EnemyActionDef.Kind.DASH:
			continue
		for cell: Vector2i in BoardQuery.get_target_cells_shaped(
			board, enemy_cell, action.range, action.range_shape, action.requires_los
		):
			seen[cell] = true
	var out := seen.keys()
	out.sort_custom(Pathfinder._by_y_then_x)
	return out


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
