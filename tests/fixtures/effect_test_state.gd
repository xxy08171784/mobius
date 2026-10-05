class_name EffectTestState
extends Resource
## A1 独立测试桩。只存在于 tests/，不会与 B 线 UnitState/BoardState 竞争实现。

var next_uid: int = 100
var next_event_seq: int = 1
var units: Dictionary = {
	1: {"hp": 20, "block": 0, "alive": true, "statuses": {}},
	2: {"hp": 10, "block": 3, "alive": true, "statuses": {}},
}
var positions: Dictionary = {
	1: Vector2i(0, 0),
	2: Vector2i(2, 0),
}
var draw_pile: Array = [101, 102, 103, 104]


## 深拷贝：Resource.duplicate(true) 不复制非导出脚本变量，会把这些字段重置为默认值，
## 因此必须像 IntegratedBattleState 一样显式实现 duplicate_state()。
func duplicate_state() -> EffectTestState:
	var copy := EffectTestState.new()
	copy.next_uid = next_uid
	copy.next_event_seq = next_event_seq
	copy.units = units.duplicate(true)
	copy.positions = positions.duplicate(true)
	copy.draw_pile = draw_pile.duplicate()
	return copy


func draw_cards(_unit_id: int, count: int, _rng: RandomNumberGenerator) -> Dictionary:
	var drawn: Array = []
	for _i: int in range(mini(count, draw_pile.size())):
		drawn.append(draw_pile.pop_front())
	return {"ok": true, "cards": drawn}


func move_unit(unit_id: int, destination: Vector2i) -> Dictionary:
	if not positions.has(unit_id):
		return {"ok": false, "error_code": &"unknown_unit"}
	var before: Vector2i = positions[unit_id]
	positions[unit_id] = destination
	return {
		"ok": true,
		"before": {"cell": before},
		"after": {"cell": destination},
	}


func push_unit(unit_id: int, direction: Vector2i, steps: int) -> Dictionary:
	if not positions.has(unit_id):
		return {"ok": false, "error_code": &"unknown_unit"}
	var before: Vector2i = positions[unit_id]
	var after := before + direction * steps
	positions[unit_id] = after
	return {
		"ok": true,
		"before": {"cell": before},
		"after": {"cell": after},
	}
