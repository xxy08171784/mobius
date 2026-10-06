class_name RoundEffectSystem
extends BattleRuleSupport

func _run_scheduled_round_start(state: BattleState, rng: RngStreams) -> Dictionary:
	var events := EventBatch.new()
	var due: Array[Dictionary] = []
	var pending: Array[Dictionary] = []
	for entry: Dictionary in state.scheduled_effects:
		if int(entry.get("round", -1)) <= state.round_index:
			due.append(entry)
		else:
			pending.append(entry)
	state.scheduled_effects = pending
	for entry: Dictionary in due:
		var kind := StringName(String(entry.get("kind", "")))
		var source_id := int(entry.get("source_unit_id", -1))
		var effects: Array = []
		match kind:
			&"draw":
				effects = [{
					"type_key": &"draw",
					"params": {"count": maxi(0, int(entry.get("count", 0)))},
				}]
			&"block":
				effects = [{
					"type_key": &"block",
					"params": {"amount": maxi(0, int(entry.get("amount", 0))), "target_mode": &"source"},
				}]
			_:
				continue
		var resolved := _resolver.resolve(
			state,
			{"context": {"source_unit_id": source_id}, "effects": effects},
			rng
		)
		if not bool(resolved.get("ok", false)):
			return {"ok": false, "events": EventBatch.new()}
		_copy_resolved_state_into(state, resolved["state_out"])
		_restore_rng_from_resolution(rng, resolved["rng_out"])
		_append_events(events, resolved["events"])
	return {"ok": true, "events": events}
