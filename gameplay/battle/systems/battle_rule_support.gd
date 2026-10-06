class_name BattleRuleSupport
extends RefCounted
const ENERGY_RESOURCE: StringName = &"energy"
const MOVE_RESOURCE: StringName = &"move_points"
const SUMMON_RADIUS := 2
var _resolver := EffectResolver.new()
var _card_system := CardSystem.new()

func _copy_resolved_state_into(target: BattleState, source: BattleState) -> void:
	target.board = source.board
	target.units = source.units
	target.deck = source.deck
	target.scheduled_effects = source.scheduled_effects
	target.ground_items = source.ground_items
	target.collected_items = source.collected_items
	target.run_changes = source.run_changes
	target.next_uid = source.next_uid
	target.next_event_seq = source.next_event_seq
	target.enemy_intents = source.enemy_intents
	target.enemy_steps = source.enemy_steps
	target.enemy_charge_remaining = source.enemy_charge_remaining
	target.enemy_charge_intents = source.enemy_charge_intents

func _restore_rng_from_resolution(target: RngStreams, resolved_rng: Variant) -> void:
	if resolved_rng is RngStreams:
		target.restore((resolved_rng as RngStreams).snapshot())

func _append_events(destination: EventBatch, source: Variant) -> void:
	if not source is EventBatch:
		return
	for event: GameEvent in (source as EventBatch).events:
		destination.push_back(event)

func _copy_intent(source: IntentState) -> IntentState:
	var copy := IntentState.new()
	copy.action_id = source.action_id
	copy.actor_id = source.actor_id
	copy.target_policy = source.target_policy
	copy.locked_unit_id = source.locked_unit_id
	copy.locked_cell = source.locked_cell
	copy.affected_cells = source.affected_cells.duplicate()
	copy.magnitude = source.magnitude
	copy.is_fallback = source.is_fallback
	return copy
