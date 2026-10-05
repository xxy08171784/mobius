class_name EffectStateAccess
extends RefCounted
## A/B 两条线之间的窄适配层。
## A1 只按“稳定 unit ID + 核心字段”工作，不依赖 B 线 UnitState/BoardState 的具体类。


static func has_field(holder: Variant, field: StringName) -> bool:
	if holder is Dictionary:
		var data := holder as Dictionary
		return data.has(field) or data.has(String(field))
	if holder is Object:
		for property: Dictionary in (holder as Object).get_property_list():
			if StringName(property.get("name", "")) == field:
				return true
	return false


static func get_field(holder: Variant, field: StringName, default_value: Variant = null) -> Variant:
	if holder is Dictionary:
		var data := holder as Dictionary
		if data.has(field):
			return data[field]
		if data.has(String(field)):
			return data[String(field)]
		return default_value
	if holder is Object and has_field(holder, field):
		return (holder as Object).get(field)
	return default_value


static func set_field(holder: Variant, field: StringName, value: Variant) -> bool:
	if holder is Dictionary:
		var data := holder as Dictionary
		if data.has(String(field)):
			data[String(field)] = value
		else:
			data[field] = value
		return true
	if holder is Object and has_field(holder, field):
		(holder as Object).set(field, value)
		return true
	return false


static func get_unit(state: Variant, unit_id: int) -> Variant:
	var units: Variant = get_field(state, &"units")
	if not units is Dictionary:
		return null
	var by_id := units as Dictionary
	if by_id.has(unit_id):
		return by_id[unit_id]
	if by_id.has(str(unit_id)):
		return by_id[str(unit_id)]
	return null


static func get_board(state: Variant) -> BoardState:
	var board: Variant = get_field(state, &"board")
	return board as BoardState


static func target_unit_id(context: EffectContext) -> int:
	if context.target is TargetSpec.UnitTarget:
		return (context.target as TargetSpec.UnitTarget).unit_id
	if context.target is int:
		return int(context.target)
	if context.target is Dictionary:
		var target_dict := context.target as Dictionary
		if target_dict.has("unit_id"):
			return int(target_dict["unit_id"])
		if target_dict.has(&"unit_id"):
			return int(target_dict[&"unit_id"])
	if context.target is Object:
		var unit_id: Variant = get_field(context.target, &"unit_id")
		if unit_id != null:
			return int(unit_id)
	return -1


static func target_cell(context: EffectContext) -> Variant:
	if context.target is TargetSpec.CellTarget:
		return (context.target as TargetSpec.CellTarget).cell
	if context.target is Vector2i:
		return context.target
	if context.target is Dictionary:
		var target_dict := context.target as Dictionary
		if target_dict.has("cell"):
			return target_dict["cell"]
		if target_dict.has(&"cell"):
			return target_dict[&"cell"]
	if context.target is Object:
		var cell: Variant = get_field(context.target, &"cell")
		if cell is Vector2i:
			return cell
	return null


static func target_direction(context: EffectContext) -> Variant:
	if context.target is TargetSpec.DirectionTarget:
		return (context.target as TargetSpec.DirectionTarget).direction
	if context.target is Vector2i:
		return context.target
	if context.target is Dictionary:
		var target_dict := context.target as Dictionary
		if target_dict.has("direction"):
			return target_dict["direction"]
		if target_dict.has(&"direction"):
			return target_dict[&"direction"]
	if context.target is Object:
		var direction: Variant = get_field(context.target, &"direction")
		if direction is Vector2i:
			return direction
	return null


static func allocate_event_seq(state: Variant) -> int:
	var current := int(get_field(state, &"next_event_seq", 0))
	if has_field(state, &"next_event_seq"):
		set_field(state, &"next_event_seq", current + 1)
	return current


static func allocate_uid(state: Variant) -> int:
	var current := int(get_field(state, &"next_uid", 1))
	if has_field(state, &"next_uid"):
		set_field(state, &"next_uid", current + 1)
	return current


static func call_state_or_service(
	state: Variant,
	state_method: StringName,
	service_field: StringName,
	service_method: StringName,
	args: Array
) -> Variant:
	if state is Object and (state as Object).has_method(state_method):
		return (state as Object).callv(state_method, args)
	var service: Variant = get_field(state, service_field)
	if service is Object and (service as Object).has_method(service_method):
		return (service as Object).callv(service_method, args)
	return null
