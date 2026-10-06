class_name FormalCardRuleRegistry
extends RefCounted
## 稳定 card_id -> Callable。扩展卡无需修改编号大 switch。handler 必须遵守 resolve_card 的工作副本契约。
static var _handlers: Dictionary = {}
static var _initialized: bool = false


static func _ensure_defaults() -> void:
	if _initialized:
		return
	_initialized = true
	for number in range(1, 50):
		if CardRuleSupport.IMPLEMENTED_ATOMIC.has(number):
			continue
		var handler: Callable = SkillCardRules.resolve if number <= 12 else (OffenseCardRules.resolve if number <= 35 else DefenseCardRules.resolve)
		_handlers[StringName("card.reward.%02d" % number)] = handler
	_handlers[CardRuleSupport.STARTER_CHARGE] = OffenseCardRules.resolve
	_handlers[CardRuleSupport.STARTER_RELENTLESS] = OffenseCardRules.resolve


static func register_rule(card_id: StringName, handler: Callable) -> bool:
	_ensure_defaults()
	if card_id.is_empty() or not handler.is_valid():
		return false
	_handlers[card_id] = handler
	return true


static func has_rule(card_id: StringName) -> bool:
	_ensure_defaults()
	return _handlers.has(card_id)


static func resolve(
	state: BattleState,
	rng: Variant,
	actor_id: int,
	card: BattleCardState,
	definition: CardDef,
	target: Variant,
	command: PlayCardsCommand,
	combo_metadata: Dictionary,
	card_defs: Dictionary
) -> Dictionary:
	_ensure_defaults()
	var handler: Callable = _handlers.get(definition.card_id, Callable())
	if not handler.is_valid():
		return {"handled": false}
	return handler.call(state, rng, actor_id, card, definition, target, command, combo_metadata, card_defs)
