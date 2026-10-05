class_name SaveCodec
extends RefCounted
## 运行状态 <-> Dictionary 的唯一编解码路径。
## 约定（architecture_review.md H2）：clone = encode(state) -> decode()，
## 避免维护第二套手写 clone()；新字段漏进 codec 会被往返测试立刻抓到。
## 需手动编码 Vector2i；64 位整数存为十进制字符串。

const _STATE_TYPE_BATTLE := "BattleState"

func encode_state(state: RefCounted) -> Dictionary:
	if state is BattleState:
		return _encode_battle_state(state as BattleState)
	push_error("SaveCodec: unsupported state type")
	return {}


func decode_state(data: Dictionary) -> RefCounted:
	var migrator := SaveMigrator.new()
	if not migrator.can_load(data):
		push_error("SaveCodec: unsupported schema_version")
		return null
	var migrated := migrator.migrate(data.duplicate(true))
	match String(migrated.get("state_type", "")):
		_STATE_TYPE_BATTLE:
			return _decode_battle_state(migrated)
		_:
			push_error("SaveCodec: unsupported state_type")
			return null


## 规则层统一深拷贝入口。禁止为各 State 再维护第二套 clone()。
func clone_state(state: RefCounted) -> RefCounted:
	return decode_state(encode_state(state))


## JSON 安全 Variant 编码：int64 用十进制字符串，Vector2i 显式拆分。
## 未来 Board/Unit/Card 状态进入 BattleState 时复用这一条路径。
func encode_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_INT:
			return {"__type": "int64", "value": str(value)}
		TYPE_STRING_NAME:
			return {"__type": "StringName", "value": String(value)}
		TYPE_VECTOR2I:
			var cell := value as Vector2i
			return {"__type": "Vector2i", "x": str(cell.x), "y": str(cell.y)}
		TYPE_ARRAY:
			var encoded_array: Array = []
			for item: Variant in value:
				encoded_array.append(encode_value(item))
			return encoded_array
		TYPE_DICTIONARY:
			var entries: Array = []
			for key: Variant in value:
				entries.append({
					"key": encode_value(key),
					"value": encode_value(value[key]),
				})
			entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return JSON.stringify(a["key"]) < JSON.stringify(b["key"])
			)
			return {"__type": "Dictionary", "entries": entries}
		_:
			push_error("SaveCodec: unsupported Variant type %s" % typeof(value))
			return null


func decode_value(value: Variant) -> Variant:
	if value is Array:
		var decoded_array: Array = []
		for item: Variant in value:
			decoded_array.append(decode_value(item))
		return decoded_array
	if not value is Dictionary:
		return value

	var data := value as Dictionary
	var type_key := String(data.get("__type", ""))
	match type_key:
		"int64":
			return String(data.get("value", "0")).to_int()
		"StringName":
			return StringName(String(data.get("value", "")))
		"Vector2i":
			return Vector2i(
				String(data.get("x", "0")).to_int(),
				String(data.get("y", "0")).to_int()
			)
		"Dictionary":
			var decoded_dict: Dictionary = {}
			for entry: Dictionary in data.get("entries", []):
				decoded_dict[decode_value(entry.get("key"))] = decode_value(entry.get("value"))
			return decoded_dict
		_:
			var plain: Dictionary = {}
			for key: Variant in data:
				plain[key] = decode_value(data[key])
			return plain


func _encode_battle_state(state: BattleState) -> Dictionary:
	return {
		"schema_version": SaveMigrator.CURRENT_SCHEMA_VERSION,
		"state_type": _STATE_TYPE_BATTLE,
		"state": {
			"phase": int(state.phase),
			"version": encode_value(state.version),
			"next_uid": encode_value(state.next_uid),
			"next_event_seq": encode_value(state.next_event_seq),
			"command_locked": state.command_locked,
			"seen_command_ids": encode_value(state.seen_command_ids),
		},
	}


func _decode_battle_state(data: Dictionary) -> BattleState:
	var payload: Dictionary = data.get("state", {})
	var state := BattleState.new()
	state.phase = int(payload.get("phase", BattleState.Phase.SETUP))
	state.version = int(decode_value(payload.get("version", encode_value(0))))
	state.next_uid = int(decode_value(payload.get("next_uid", encode_value(1))))
	state.next_event_seq = int(decode_value(payload.get("next_event_seq", encode_value(1))))
	state.command_locked = bool(payload.get("command_locked", false))
	state.seen_command_ids.clear()
	var seen: Array = decode_value(payload.get("seen_command_ids", []))
	for command_id: Variant in seen:
		state.seen_command_ids.append(int(command_id))
	return state
