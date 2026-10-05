class_name RestSystem
extends RefCounted
## 休息节点规则：回血 / 升级一张卡。纯规则，无 UI。
## 数值集中在此便于策划调参；改字段需同步测试。

const OPTION_HEAL := &"heal"
const OPTION_UPGRADE := &"upgrade"

## 回血 = max_hp 的比例（向下取整）。
const HEAL_PERCENT := 0.3

## 卡牌最高升级等级（CardDef.upgrade_overrides 目前提供 level 1）。
const MAX_UPGRADE_LEVEL := 1


static func heal_amount(run: RunState) -> int:
	return int(floor(float(run.max_hp) * HEAL_PERCENT))


static func can_upgrade(card: RunCardState) -> bool:
	return card != null and card.upgrade_level < MAX_UPGRADE_LEVEL


## 可升级的卡 UID（升序，确定性）。
static func upgradable_card_uids(run: RunState) -> Array[int]:
	var ids: Array[int] = []
	for card: RunCardState in run.deck:
		if can_upgrade(card):
			ids.append(card.run_uid)
	ids.sort()
	return ids


## 应用一个休息选项。成功返回 {ok, kind, ...}；失败零副作用。
static func apply(run: RunState, option: StringName, card_run_uid: int = -1) -> Dictionary:
	if run == null:
		return {"ok": false, "error_code": &"run_not_ready"}
	match option:
		OPTION_HEAL:
			var healed := maxi(0, mini(heal_amount(run), run.max_hp - run.hp))
			run.hp += healed
			return {"ok": true, "kind": OPTION_HEAL, "healed": healed}
		OPTION_UPGRADE:
			var card := run.get_card(card_run_uid)
			if not can_upgrade(card):
				return {"ok": false, "error_code": &"cannot_upgrade"}
			card.upgrade_level += 1
			return {
				"ok": true,
				"kind": OPTION_UPGRADE,
				"card_run_uid": card_run_uid,
				"upgrade_level": card.upgrade_level,
			}
	return {"ok": false, "error_code": &"unknown_option"}
