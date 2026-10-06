extends "res://tests/test_case.gd"

class MemorySave extends RefCounted:
	var data: Dictionary = {}
	var fail: bool = false
	func save_run(state: RunState) -> bool:
		if fail:
			return false
		data = SaveCodec.new().encode_state(state)
		return true

var db: Node


func run() -> Array[String]:
	reset()
	db = load("res://autoload/content_db.gd").new()
	assert_true(db.load_catalog(), "catalog")
	_deployment_and_battle()
	_node_recovery()
	_rewards_and_idempotence()
	_terminal_and_profile()
	_save_failure()
	_campaign_replay()
	db.free()
	return failures()


func _session(kind: StringName = &"") -> RunSession:
	var state := RunSession.create_run(&"character.hero", "lifecycle-seed", db)
	state.instance_id = "test-instance"
	if not kind.is_empty():
		state.map = RouteGraph.new()
		state.map.rows = 1
		state.map.cols = 1
		state.map.add_node(0, 0, true).type_key = kind
	var session := RunSession.new()
	session.setup(state, db)
	return session


func _reload(session: RunSession) -> RunSession:
	var codec := SaveCodec.new()
	var json: Dictionary = JSON.parse_string(JSON.stringify(codec.encode_state(session.state)))
	var restored := RunSession.new()
	restored.setup(codec.decode_state(json), db)
	return restored


func _result(session: RunSession, won: bool = true) -> BattleResult:
	var result := BattleResult.new()
	result.battle_id = session.state.pending_battle_id
	result.run_instance_id = session.state.instance_id
	result.victory = won
	result.persistent_changes = {"player_hp": {1: session.state.max_hp if won else 0}}
	return result


func _deployment_and_battle() -> void:
	var session := _session()
	var id := session.available_node_ids()[0]
	var rng_before := session.state.rng_snapshot.duplicate(true)
	assert_true(session.begin_deployment(id).ok, "begin deployment")
	assert_true(not session.state.map.get_node(id).visited, "deployment does not consume node")
	assert_equal(session.state.rng_snapshot, rng_before, "preview RNG unchanged")
	var restored := _reload(session)
	assert_equal(restored.state.flow_phase, &"deployment", "deployment resumes")
	assert_equal(restored.resume_pending_flow().preview, session.resume_pending_flow().preview, "same enemy preview")
	assert_true(restored.cancel_deployment(), "cancel deployment")
	assert_true(restored.can_enter(id), "cancel releases node")
	var transition := session.enter_node(id, Vector2i.ZERO)
	var data: Dictionary = transition.battle
	var battle := BattleSession.new()
	battle.setup(data.rng, data.state, data.card_defs, data.enemy_behaviors, data.enemy_actions, Callable(), data.summon_pool)
	var command := EndTurnCommand.new()
	command.command_id = 10000
	command.actor_id = 1
	assert_true(battle.submit(command).accepted, "accepted end turn")
	assert_true(session.checkpoint_battle(battle.state), "checkpoint while animation is resolving")
	restored = _reload(session)
	var restored_transition := restored.resume_pending_flow()
	assert_true(restored_transition.get("ok", false), "battle checkpoint restores content bindings")
	if not restored_transition.get("ok", false):
		return
	var resumed_data: Dictionary = restored_transition.battle
	var resumed: BattleState = resumed_data.state
	assert_equal(resumed.phase, BattleState.Phase.PLAYER_INPUT, "resolving lock cleared on resume")
	assert_true(not resumed.command_locked, "input unlocked")
	assert_equal(resumed.round_index, battle.state.round_index, "round unchanged")
	assert_equal(resumed.rng_snapshot, battle.state.rng_snapshot, "battle RNG unchanged")
	assert_equal(resumed.deck.hand, battle.state.deck.hand, "hand unchanged")
	assert_true(resumed.seen_command_ids.has(10000), "command ID persisted")
	assert_true(not restored.can_enter(restored.state.current_node_id), "pending battle cannot be bypassed")


func _node_recovery() -> void:
	var shop := _session(RouteMapDef.TYPE_SHOP)
	shop.state.gold = 500
	shop.enter_node(shop.available_node_ids()[0])
	var before := ShopState.from_dict(shop.state.pending_payload.shop)
	assert_true(shop.resolve_node_action(&"buy", {"index": 0}).ok, "shop purchase")
	var restored := _reload(shop)
	var saved: ShopState = restored.resume_pending_flow().shop
	assert_equal(saved.offers, before.offers, "shop offers persisted")
	assert_true(saved.is_sold(0), "sold state persisted")
	assert_true(not restored.resolve_node_action(&"buy", {"index": 0}).ok, "cannot buy sold offer")
	assert_true(restored.resolve_node_action(&"leave").ok, "leave shop")
	var rest := _session(RouteMapDef.TYPE_REST)
	rest.state.hp = 10
	rest.enter_node(rest.available_node_ids()[0])
	rest = _reload(rest)
	assert_equal(rest.state.flow_phase, &"rest", "rest resumes")
	assert_true(rest.resolve_node_action(&"heal").ok, "rest heal")
	assert_true(not rest.resolve_node_action(&"heal").ok, "rest cannot repeat")
	var event := _session(RouteMapDef.TYPE_EVENT)
	event.enter_node(event.available_node_ids()[0])
	var event_id := event.state.pending_content_id
	event = _reload(event)
	assert_equal(event.state.pending_content_id, event_id, "same event resumes")
	assert_true(not event.resolve_node_action(&"leave").ok, "event cannot be skipped implicitly")
	assert_true(event.resolve_node_action(&"event_choice", {"index": 0}).ok, "event choice")
	assert_true(not event.resolve_node_action(&"event_choice", {"index": 0}).ok, "event choice once")
	var treasure := _session(RouteMapDef.TYPE_TREASURE)
	treasure.enter_node(treasure.available_node_ids()[0])
	var gold := treasure.state.gold
	treasure = _reload(treasure)
	treasure.resume_pending_flow()
	assert_equal(treasure.state.gold, gold, "treasure not re-awarded on resume")
	assert_true(treasure.resolve_node_action(&"leave").ok, "treasure acknowledged")


func _rewards_and_idempotence() -> void:
	var session := _session()
	session.enter_node(session.available_node_ids()[0])
	var bad := _result(session)
	bad.run_instance_id = "previous-run"
	assert_true(not session.on_battle_finished(bad).ok, "cross-run battle rejected")
	bad = _result(session)
	bad.battle_id += 1
	assert_true(not session.on_battle_finished(bad).ok, "wrong battle rejected")
	var victory := _result(session)
	victory.persistent_changes["max_hp_delta"] = 3
	assert_true(session.on_battle_finished(victory).ok, "victory committed")
	var codec := SaveCodec.new()
	var snapshot := codec.encode_state(session.state)
	assert_true(not session.on_battle_finished(victory).ok, "duplicate result rejected")
	assert_equal(codec.encode_state(session.state), snapshot, "duplicate is side effect free")
	var reward := session.generate_reward()
	var restored := _reload(session)
	assert_equal(restored.generate_reward().offers, reward.offers, "same persisted reward")
	assert_equal(restored.state.rng_snapshot, session.state.rng_snapshot, "reward RNG persisted")
	var count := restored.state.deck.size()
	assert_true(restored.claim_reward(reward, 0).ok, "claim reward")
	assert_equal(restored.state.deck.size(), count + 1, "one card awarded")
	assert_true(not restored.claim_reward(reward, 0).ok, "stale reward rejected")
	assert_equal(restored.state.flow_phase, &"route", "reward returns route")


func _terminal_and_profile() -> void:
	var session := _session()
	session.enter_node(session.available_node_ids()[0])
	session.on_battle_finished(_result(session, false))
	assert_equal(session.state.flow_phase, &"run_over", "defeat terminal")
	assert_true(not session.state.is_active(), "dead run not continuable")
	var profile := ProfileState.new()
	assert_true(profile.record_run(session.state), "profile first result")
	var currency := profile.currency
	assert_true(not profile.record_run(session.state), "profile duplicate rejected")
	assert_equal(profile.currency, currency, "profile no duplicate currency")
	var clone := ProfileState.from_dict(profile.to_dict())
	assert_equal(clone.history, profile.history, "profile history roundtrip")
	var boss := _session(RouteMapDef.TYPE_BOSS)
	var campaign := CampaignDef.new()
	campaign.acts = [RouteMapDef.new()]
	boss.setup(boss.state, db, campaign)
	boss.enter_node(boss.available_node_ids()[0])
	assert_equal(boss.on_battle_finished(_result(boss)).kind, RunSession.KIND_RUN_COMPLETE, "last boss completes campaign")
	assert_true(not boss.state.is_active(), "completed run not continuable")


func _save_failure() -> void:
	var session := _session()
	var service := MemorySave.new()
	service.fail = true
	session.setup(session.state, db, null, service)
	var messages: Array[String] = []
	session.save_failed.connect(func(message: String) -> void: messages.append(message))
	session.enter_node(session.available_node_ids()[0])
	assert_true(not session.last_save_ok and not messages.is_empty(), "save failure propagated")
	service.fail = false
	assert_true(session.save(), "retry persists current in-memory transaction")
	assert_equal((SaveCodec.new().decode_state(service.data) as RunState).flow_phase, &"battle", "retry keeps pending battle")


func _campaign_replay() -> void:
	var continuous := _session()
	var resumed := _session()
	for step in 180:
		_drive(continuous)
		_drive(resumed)
		resumed = _reload(resumed)
		assert_equal(SaveCodec.new().encode_state(continuous.state), SaveCodec.new().encode_state(resumed.state), "campaign restart determinism step %d" % step)
		if not continuous.state.is_active():
			break
	assert_equal(continuous.state.outcome, RunSession.KIND_RUN_COMPLETE, "three-act lifecycle reaches completion")
	assert_equal(continuous.state.act_index, 2, "all three acts exercised")


func _drive(session: RunSession) -> void:
	match session.state.flow_phase:
		&"route":
			var ids := session.available_node_ids()
			assert_true(not ids.is_empty(), "active route has next node")
			if not ids.is_empty():
				session.enter_node(ids[0])
		&"battle":
			session.on_battle_finished(_result(session))
		&"reward":
			session.claim_reward(session.generate_reward(), 0)
		&"rest", &"shop", &"treasure":
			session.resolve_node_action(&"leave")
		&"event":
			session.resolve_node_action(&"event_choice", {"index": 0})
