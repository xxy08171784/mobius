class_name TreasureSystem
extends RefCounted
## 宝箱节点规则：奖励一件遗物 + 固定金币。数值集中在此便于策划调参。

const GOLD_REWARD := 40


## 发放奖励。relic_id 由调用方（RunSession 用 encounter 流）确定性选出。
## 成功返回 {ok, kind, relic_id, relic_instance_id, gold}；失败零副作用。
static func claim(run: RunState, relic_id: StringName) -> Dictionary:
	if run == null:
		return {"ok": false, "error_code": &"run_not_ready"}
	if relic_id.is_empty():
		return {"ok": false, "error_code": &"invalid_relic"}
	var relic := run.add_relic(relic_id)
	run.gold += GOLD_REWARD
	return {
		"ok": true,
		"kind": &"treasure",
		"relic_id": relic_id,
		"relic_instance_id": relic.instance_id,
		"gold": GOLD_REWARD,
	}
