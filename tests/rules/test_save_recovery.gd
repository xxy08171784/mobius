extends "res://tests/test_case.gd"
const Service := preload("res://autoload/save_service.gd")

class FailingReplace extends Service:
	var fail_replace: bool = false
	func _replace_file(source: String, destination: String) -> bool:
		if fail_replace:
			return false
		return super._replace_file(source, destination)


func run() -> Array[String]:
	reset()
	var db := load("res://autoload/content_db.gd").new() as Node
	db.load_catalog()
	var service := FailingReplace.new()
	# 永远不触碰开发者的 current.json/profile.json，包括备份。
	var directory := "user://tests/save-recovery-%d" % Time.get_ticks_usec()
	service.run_path = directory + "/current.json"
	service.profile_path = directory + "/profile.json"
	var state := RunSession.create_run(&"character.hero", "save-recovery", db)
	state.instance_id = "test-save-recovery"
	assert_true(service.save_run(state), "first save")
	state.gold = 200
	assert_true(service.save_run(state), "second save preserves first backup")
	var broken := FileAccess.open(service.run_path, FileAccess.WRITE)
	broken.store_string("{broken")
	broken.close()
	var loaded := service.load_run() as RunState
	assert_true(loaded != null, "corrupt primary restores backup")
	assert_equal(loaded.gold, 99, "backup was last valid version")
	assert_true(service.recovered_from_backup, "recovery reported")
	assert_true(service.has_run(), "recovered run playable")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(service.run_path))
	assert_true(service.load_run() != null, "missing primary restores backup")
	service.fail_replace = true
	assert_true(not service.save_run(state), "rename failure reported")
	assert_true(not service.last_error.is_empty(), "save failure has reason")
	assert_equal((service.load_run() as RunState).gold, 99, "failed write preserves old primary")
	service.fail_replace = false
	assert_true(service.save_run(state), "retry succeeds")
	var profile := ProfileState.new()
	profile.currency = 12
	assert_true(service.save_profile(profile), "profile saves")
	profile.currency = 24
	assert_true(service.save_profile(profile), "profile second save")
	assert_equal((service.load_run() as RunState).gold, 200, "profile backup does not overwrite run")
	broken = FileAccess.open(service.profile_path, FileAccess.WRITE)
	broken.store_string("broken")
	broken.close()
	assert_equal(service.load_profile().currency, 12, "profile backup restores")
	state.flow_phase = &"run_over"
	state.outcome = &"defeat"
	state.hp = 0
	service.save_run(state)
	assert_true(not service.has_run(), "defeat cannot continue")
	state.hp = state.max_hp
	state.outcome = &"run_complete"
	service.save_run(state)
	assert_true(not service.has_run(), "victory cannot continue")
	assert_true(service.archive_run(state), "archive and clear")
	assert_true(not service.has_run(), "archive removes backups too")
	assert_true(FileAccess.file_exists(directory + "/history/test-save-recovery.json"), "terminal snapshot archived")
	# v2 -> v3 adds safe defaults; old versions cannot recreate lost pending state.
	var encoded := SaveCodec.new().encode_state(state)
	encoded.schema_version = 2
	for field: String in ["flow_phase", "pending_payload", "settled_battle_ids", "outcome"]:
		encoded.state.erase(field)
	var migrated := SaveCodec.new().decode_state(encoded) as RunState
	assert_equal(migrated.flow_phase, &"route", "legacy migration defaults route")
	encoded.schema_version = SaveMigrator.CURRENT_SCHEMA_VERSION + 1
	assert_true(not SaveMigrator.new().can_load(encoded), "future schema rejected")
	service.free()
	db.free()
	return failures()
