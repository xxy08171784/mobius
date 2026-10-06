class_name ProfileState
extends RefCounted
## 局外进度；结算键使用局实例 ID，与 seed 分离。没有强制消耗货币的升级。
var currency: int = 0
var unlocked_characters: Array[StringName] = [&"character.hero"]
var unlocked_difficulty: int = 0
var completed_runs: Dictionary = {}
var history: Array[Dictionary] = []
var discovered_cards: Array[StringName] = []
var discovered_enemies: Array[StringName] = []
var tutorial_seen: bool = false


func record_run(run: RunState) -> bool:
	if run == null or run.instance_id.is_empty() or completed_runs.has(run.instance_id):
		return false
	var won := run.outcome == &"run_complete"
	var earned := (30 if won else 5) + run.settled_battle_ids.size()
	if run.outcome == &"abandoned":
		earned = 0
	currency += earned
	if won:
		unlocked_difficulty = maxi(unlocked_difficulty, mini(10, run.difficulty + 1))
	completed_runs[run.instance_id] = true
	history.push_front({"id": run.instance_id, "seed": run.seed, "character": String(run.character_id),
		"outcome": String(run.outcome), "act": run.act_index + 1, "battles": run.settled_battle_ids.size(),
		"difficulty": run.difficulty, "earned": earned, "time": Time.get_datetime_string_from_system()})
	if history.size() > 100:
		history.resize(100)
	for card: RunCardState in run.deck:
		if not discovered_cards.has(card.card_id):
			discovered_cards.append(card.card_id)
	return true


func to_dict() -> Dictionary:
	return {"schema_version": 1, "currency": currency, "unlocked_characters": unlocked_characters,
		"unlocked_difficulty": unlocked_difficulty, "completed_runs": completed_runs, "history": history,
		"discovered_cards": discovered_cards, "discovered_enemies": discovered_enemies, "tutorial_seen": tutorial_seen}


static func from_dict(data: Dictionary) -> ProfileState:
	if int(data.get("schema_version", 0)) != 1:
		return null
	var profile := ProfileState.new()
	profile.currency = maxi(0, int(data.get("currency", 0)))
	profile.unlocked_difficulty = clampi(int(data.get("unlocked_difficulty", 0)), 0, 10)
	profile.completed_runs = data.get("completed_runs", {}).duplicate(true)
	for entry: Dictionary in data.get("history", []):
		profile.history.append(entry.duplicate(true))
	for field: String in ["unlocked_characters", "discovered_cards", "discovered_enemies"]:
		var ids: Array[StringName] = []
		for value: Variant in data.get(field, profile.get(field)):
			ids.append(StringName(String(value)))
		profile.set(field, ids)
	profile.tutorial_seen = bool(data.get("tutorial_seen", false))
	return profile
