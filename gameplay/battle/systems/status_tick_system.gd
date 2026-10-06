class_name StatusTickSystem
extends BattleRuleSupport

func _finish_owner_turn(state: BattleState, rng: RngStreams, team: UnitState.Team) -> Dictionary:
	var events := EventBatch.new()
	var ids := state.player_ids() if team == UnitState.Team.PLAYER else state.enemy_ids()
	for unit_id: int in ids:
		var result := _finish_single_owner_turn(state, rng, unit_id)
		if not bool(result.get("ok", false)):
			return {"ok": false, "events": EventBatch.new()}
		_append_events(events, result.get("events"))
	return {"ok": true, "events": events}

func _finish_single_owner_turn(state: BattleState, rng: RngStreams, unit_id: int) -> Dictionary:
	var events := EventBatch.new()
	var unit := state.get_unit(unit_id)
	if unit == null:
		return {"ok": true, "events": events}

	# 回合结束 DoT（流血/中毒）：逐状态结算，层数即伤害（忽略加成，§6 取整前）。
	# 中毒无视护甲（不吃盾，§8）且按层数递减；流血吃盾、按持续递减。
	for dot_id: StringName in StatusRules.DOT_STATUSES:
		if not unit.is_alive():
			break
		var dot_damage := StatusRules.dot_tick_damage(dot_id, StatusRules.stacks(unit, dot_id))
		if dot_damage <= 0:
			continue
		var resolved := _resolver.resolve(
			state,
			{
				"context": {"source_unit_id": -1},
				"effects": [{
					"type_key": &"damage",
					"target": unit_id,
					"params": {
						"amount": dot_damage,
						"ignore_status_modifiers": true,
						"ignore_block": StatusRules.is_armor_ignoring(dot_id),
						"status_id": dot_id,
					},
				}],
			},
			rng
		)
		if not bool(resolved.get("ok", false)):
			return {"ok": false, "events": EventBatch.new()}
		_copy_resolved_state_into(state, resolved["state_out"])
		_restore_rng_from_resolution(rng, resolved["rng_out"])
		_append_events(events, resolved["events"])
		unit = state.get_unit(unit_id)
		if StatusRules.is_stack_decaying(dot_id):
			StatusRules.decay_stacks(unit, dot_id)

	# 勇气每次自己的回合结束保留一半，向下取整。
	unit.set_resource(&"courage", unit.get_resource(&"courage") / 2)
	var expired: Array[int] = []
	for instance_id: int in unit.status_ids():
		var status := unit.get_status(instance_id)
		# 层数驱动的状态不吃持续递减（由层数决定寿命）。
		if not StatusRules.is_stack_decaying(status.status_id):
			status.decrease_duration()
		if status.is_expired():
			expired.append(instance_id)
	for instance_id: int in expired:
		unit.remove_status(instance_id)
	return {"ok": true, "events": events}
