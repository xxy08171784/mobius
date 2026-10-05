class_name RngStreams
extends RefCounted
## 分流的确定性随机。每局从 run seed 派生，随 game_version 固定（combat_rules.md §12）。
## seed 与每流 state 都需保存；64 位值存为十进制字符串，避免 JSON 精度丢失。

const STREAM_IDS := [&"route", &"encounter", &"battle", &"reward"]
const _STREAM_NUMERIC_IDS := {
	&"route": 1,
	&"encounter": 2,
	&"battle": 3,
	&"reward": 4,
}

# SplitMix64 constants represented as signed int64.
const _SM64_GAMMA: int = -7046029254386353131
const _SM64_MUL_1: int = -4658895280553007687
const _SM64_MUL_2: int = -7723592293110705685

## StringName -> RandomNumberGenerator
var _streams: Dictionary = {}

## run seed（十进制字符串）。
var _seed: String = ""


## 用固定算法（建议 splitmix64(run_seed, stream_id)）派生各流。
## 禁止 seed(run_seed + i) 之类脆弱写法。
func derive_streams(run_seed: String) -> void:
	_seed = run_seed
	_streams.clear()
	var base_seed := run_seed.to_int()
	for stream_id: StringName in STREAM_IDS:
		var numeric_id: int = _STREAM_NUMERIC_IDS[stream_id]
		var rng := RandomNumberGenerator.new()
		rng.seed = _splitmix64(base_seed ^ numeric_id)
		_streams[stream_id] = rng


## 返回可存档/可克隆的快照；预览与存档共用。
func snapshot() -> Dictionary:
	var states: Dictionary = {}
	for stream_id: StringName in STREAM_IDS:
		var rng: RandomNumberGenerator = _streams.get(stream_id)
		if rng != null:
			states[String(stream_id)] = str(rng.state)
	return {
		"seed": _seed,
		"states": states,
	}


## 先恢复 seed 再恢复每流 state。
func restore(data: Dictionary) -> void:
	derive_streams(String(data.get("seed", "0")))
	var states: Dictionary = data.get("states", {})
	for stream_id: StringName in STREAM_IDS:
		var key := String(stream_id)
		if not states.has(key):
			continue
		var rng: RandomNumberGenerator = _streams[stream_id]
		rng.state = String(states[key]).to_int()


## 战斗随机流。注意：预览必须 clone 后使用，禁止推进正式流。
func battle_rng() -> RandomNumberGenerator:
	return get_stream(&"battle")


## 获取指定确定性子流。调用前必须先 derive_streams()/restore()。
func get_stream(stream_id: StringName) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = _streams.get(stream_id)
	if rng == null:
		push_error("RngStreams: stream '%s' is not initialized" % stream_id)
	return rng


## 独立克隆（预览用），不影响正式流。
func clone() -> RngStreams:
	var copy := RngStreams.new()
	copy.restore(snapshot())
	return copy


## 固定的 SplitMix64 派生。逻辑右移不能直接用有符号 >>，因此显式屏蔽高位。
static func _splitmix64(value: int) -> int:
	var z := value + _SM64_GAMMA
	z = (z ^ _logical_shift_right(z, 30)) * _SM64_MUL_1
	z = (z ^ _logical_shift_right(z, 27)) * _SM64_MUL_2
	return z ^ _logical_shift_right(z, 31)


static func _logical_shift_right(value: int, bits: int) -> int:
	if bits == 0:
		return value
	var mask := (1 << (64 - bits)) - 1
	return (value >> bits) & mask
