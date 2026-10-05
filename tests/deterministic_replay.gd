class_name DeterministicReplay
extends RefCounted
## seed + 命令序列 -> 最终状态哈希 + 事件流哈希 的公共测试壳。
## Phase 0 只提供通用壳；Phase 3 接上 BattleSession.submit 后复用。


static func replay(
	run_seed: String,
	initial_state: RefCounted,
	commands: Array,
	stepper: Callable
) -> Dictionary:
	var codec := SaveCodec.new()
	var state := codec.clone_state(initial_state)
	var rng := RngStreams.new()
	rng.derive_streams(run_seed)
	var event_stream: Array = []

	for command: Variant in commands:
		var step: Dictionary = stepper.call(state, command, rng)
		if step.has("state"):
			state = step["state"]
		if step.has("rng"):
			rng = step["rng"]
		if step.has("events"):
			var events: Array = step["events"]
			event_stream.append_array(events)

	return {
		"state_hash": hash_variant(codec.encode_state(state)),
		"event_hash": hash_variant(event_stream),
		"rng_hash": hash_variant(rng.snapshot()),
	}


static func summarize(state: RefCounted, event_stream: Array) -> Dictionary:
	var codec := SaveCodec.new()
	return {
		"state_hash": hash_variant(codec.encode_state(state)),
		"event_hash": hash_variant(event_stream),
	}


static func hash_variant(value: Variant) -> String:
	var canonical := _canonical_string(value)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(canonical.to_utf8_buffer())
	return context.finish().hex_encode()


static func _canonical_string(value: Variant) -> String:
	if value is Dictionary:
		var data := value as Dictionary
		var keys: Array = data.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool:
			return str(a) < str(b)
		)
		var parts: Array[String] = []
		for key: Variant in keys:
			parts.append("%s:%s" % [_canonical_string(key), _canonical_string(data[key])])
		return "{%s}" % ",".join(parts)
	if value is Array:
		var array_parts: Array[String] = []
		for item: Variant in value:
			array_parts.append(_canonical_string(item))
		return "[%s]" % ",".join(array_parts)
	return "%d:%s" % [typeof(value), var_to_str(value)]
