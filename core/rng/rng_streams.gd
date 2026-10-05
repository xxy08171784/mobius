class_name RngStreams
extends RefCounted
## 分流的确定性随机。每局从 run seed 派生，随 game_version 固定（combat_rules.md §12）。
## seed 与每流 state 都需保存；64 位值存为十进制字符串，避免 JSON 精度丢失。

const STREAM_IDS := [&"route", &"encounter", &"battle", &"reward"]

## StringName -> RandomNumberGenerator
var _streams: Dictionary = {}

## run seed（十进制字符串）。
var _seed: String = ""


## 用固定算法（建议 splitmix64(run_seed, stream_id)）派生各流。
## 禁止 seed(run_seed + i) 之类脆弱写法。
func derive_streams(run_seed: String) -> void:
	_seed = run_seed
	# TODO: 为每个 STREAM_IDS 派生独立 RandomNumberGenerator。
	pass


## 返回可存档/可克隆的快照；预览与存档共用。
func snapshot() -> Dictionary:
	# TODO: { "seed": ..., "states": { stream_id: state_string } }
	return {}


## 先恢复 seed 再恢复每流 state。
func restore(data: Dictionary) -> void:
	# TODO
	pass


## 战斗随机流。注意：预览必须 clone 后使用，禁止推进正式流。
func battle_rng() -> RandomNumberGenerator:
	# TODO
	return _streams.get(&"battle", RandomNumberGenerator.new())


## 独立克隆（预览用），不影响正式流。
func clone() -> RngStreams:
	var copy := RngStreams.new()
	copy.restore(snapshot())
	return copy
