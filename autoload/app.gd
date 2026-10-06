extends Node
## Profile / Run 生命周期；所有玩法操作由 Session 完成。
var current_profile: ProfileState = null
var current_run: RunState = null
var current_session: RunSession = null
var selected_difficulty: int = 0


func ensure_profile() -> ProfileState:
	if current_profile == null:
		current_profile = SaveService.load_profile()
		if current_profile == null:
			current_profile = ProfileState.new()
	return current_profile


func create_run(character_id: StringName = &"character.hero", seed_text: String = "") -> RunState:
	if not ContentDB.ensure_loaded():
		return null
	var profile := ensure_profile()
	var character: CharacterDef = ContentDB.get_character(character_id)
	if character == null or (character.unlock_cost > 0 and not profile.unlocked_characters.has(character_id)):
		return null
	var previous := SaveService.load_run(true) as RunState
	if previous != null:
		if previous.is_active():
			previous.outcome = &"abandoned"
		elif previous.outcome.is_empty():
			previous.outcome = &"defeat"
		previous.flow_phase = &"run_over"
		if not _finalize(previous):
			return null
	var actual_seed := seed_text if not seed_text.is_empty() else str(Time.get_unix_time_from_system())
	var run := RunSession.create_run(character_id, actual_seed, ContentDB)
	if run == null:
		return null
	run.instance_id = "%s-%s" % [str(Time.get_unix_time_from_system()).replace(".", "-"), Time.get_ticks_usec()]
	run.difficulty = clampi(selected_difficulty, 0, profile.unlocked_difficulty)
	_bind(run)
	current_session.save()
	return current_run


func load_run() -> RunState:
	if not ContentDB.ensure_loaded():
		return null
	var loaded := SaveService.load_run() as RunState
	if loaded == null:
		return null
	_bind(loaded)
	return current_run


func _bind(run: RunState) -> void:
	current_run = run
	current_session = RunSession.new()
	current_session.setup(run, ContentDB, null, SaveService)
	current_session.state_changed.connect(func(updated: RunState) -> void: current_run = updated)


func end_run(_result: RefCounted = null) -> bool:
	if current_session != null:
		current_run = current_session.state
	if current_run == null:
		return true
	if current_run.is_active():
		return false
	if not _finalize(current_run):
		return false
	current_run = null
	current_session = null
	return true


func _finalize(run: RunState) -> bool:
	# 先持久化终态，再 Profile 幂等结算，最后归档；任意位置中断均可重试。
	if not SaveService.save_run(run):
		return false
	var work := ProfileState.from_dict(ensure_profile().to_dict())
	work.record_run(run)
	if not SaveService.save_profile(work):
		return false
	current_profile = work
	return SaveService.archive_run(run)


func unlock_character(id: StringName) -> bool:
	var character: CharacterDef = ContentDB.get_character(id)
	var profile := ensure_profile()
	if character == null or profile.unlocked_characters.has(id) or profile.currency < character.unlock_cost:
		return false
	var work := ProfileState.from_dict(profile.to_dict())
	work.currency -= character.unlock_cost
	work.unlocked_characters.append(id)
	if not SaveService.save_profile(work):
		return false
	current_profile = work
	return true


func recover_ended_run() -> bool:
	var run := SaveService.load_run(true) as RunState
	if run == null or run.is_active():
		return true
	run.flow_phase = &"run_over"
	if run.outcome.is_empty():
		run.outcome = &"defeat"
	return _finalize(run)
