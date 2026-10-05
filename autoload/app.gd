extends Node
## 当前 Profile / Run 生命周期。autoload。
## 约束（architecture_review.md 中优先级）：只暴露 create_run/load_run/end_run 等生命周期 API，
## 玩法方法一律不挂本类，防止变成 God Object。

var current_profile: RefCounted = null
var current_run: RunState = null
var current_session: RunSession = null


## 读取局外配置，生成一份确定的初始 RunState（并挂好 RunSession）。
func create_run(character_id: StringName = &"character.hero", seed_text: String = "") -> RunState:
	if not ContentDB.ensure_loaded():
		push_error("App.create_run: content catalog not loaded")
		return null
	var actual_seed := seed_text if not seed_text.is_empty() else str(Time.get_unix_time_from_system())
	var run := RunSession.create_run(character_id, actual_seed, ContentDB)
	current_run = run
	current_session = null
	if run != null:
		var session := RunSession.new()
		session.setup(run, ContentDB, null, SaveService)
		current_session = session
	return run


## 读档恢复一局（RunState 经 SaveService + SaveCodec 还原）。
func load_run() -> RunState:
	var loaded := SaveService.load_run() as RunState
	if loaded == null:
		return null
	current_run = loaded
	current_session = RunSession.new()
	current_session.setup(loaded, ContentDB, null, SaveService)
	return loaded


## 结束本局：结算永久货币/解锁，用 run ID 防重复发放。
func end_run(_result: RefCounted = null) -> void:
	current_run = null
	current_session = null
	# TODO: ProfileState 落地后在此结算永久货币/解锁（用 run_id 防重复）。
