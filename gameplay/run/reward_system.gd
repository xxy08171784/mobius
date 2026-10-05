class_name RewardSystem
extends RefCounted
## 战后奖励规则：从卡池无重复抽 N 张供选一；领取加入卡组，或放弃。
## 纯规则，用传入 rng 保证确定性；金币奖励为固定值（无随机）。

## 三选一的选项数。
const OFFER_COUNT := 3

## 每场胜利的金币奖励（固定，无随机）。
const GOLD_REWARD := 15


## 从 pool（卡牌定义 ID 列表）无重复抽 OFFER_COUNT 张。确定性 = (pool, rng 状态)。
static func generate(pool: Array, rng: RandomNumberGenerator) -> RewardState:
	var state := RewardState.new()
	var candidates: Array = pool.duplicate()
	_shuffle(candidates, rng)
	var count := mini(OFFER_COUNT, candidates.size())
	for i in count:
		state.offers.append(StringName(String(candidates[i])))
	return state


## 领取第 index 张（加入卡组）；index < 0 表示放弃。两者都标记已结算。
## 失败零副作用。
static func claim(run: RunState, reward: RewardState, index: int) -> Dictionary:
	if run == null or reward == null:
		return {"ok": false, "error_code": &"not_ready"}
	if reward.claimed:
		return {"ok": false, "error_code": &"reward_used"}
	if index < 0:
		reward.claimed = true
		return {"ok": true, "kind": &"skip"}
	if index >= reward.offers.size():
		return {"ok": false, "error_code": &"invalid_offer"}
	var card := run.add_card(reward.offers[index])
	reward.claimed = true
	return {
		"ok": true,
		"kind": &"card_reward",
		"card_id": card.card_id,
		"card_run_uid": card.run_uid,
	}


static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp: Variant = values[i]
		values[i] = values[j]
		values[j] = temp
