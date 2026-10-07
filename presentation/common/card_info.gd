class_name CardInfo
extends RefCounted
## 卡牌 / 遗物 / 状态的展示文案生成（表现层，只读 Def，不碰规则状态）。
## 用于手牌与卡组的悬浮详情、休息处升级前后对比、遗物说明。

const CATEGORY_LABELS := {
	CardDef.TAG_ATTACK: "攻击",
	CardDef.TAG_TECHNIQUE: "招式",
	CardDef.TAG_DEFENSE: "防御",
	CardDef.TAG_SKILL: "技能",
	CardDef.TAG_ABILITY: "能力",
}

const COURAGE_DESCRIPTION := "每层使普通攻击伤害 +1；自己的回合结束时保留一半，向下取整。"


static func display_name_of(def: CardDef, level: int = 0) -> String:
	if def == null:
		return ""
	return def.get_display_name(level)


static func display_name_of_relic(def: RelicDef) -> String:
	if def == null:
		return ""
	if not def.display_name.is_empty():
		return def.display_name
	return String(def.relic_id)


## 类别文本，如「攻击」/「防御」；无识别 tag 时空串。
static func category_text(def: CardDef, level: int = 0) -> String:
	if def == null:
		return ""
	var names: Array[String] = []
	for tag: StringName in def.get_tags(level):
		if CATEGORY_LABELS.has(tag):
			var label: String = CATEGORY_LABELS[tag]
			if not names.has(label):
				names.append(label)
	return "/".join(names)


static func status_name_of(status_id: StringName) -> String:
	var definition: StatusDef = ContentDB.get_status(status_id)
	if definition != null and not definition.display_name.is_empty():
		return definition.display_name
	return String(status_id)


## 把效果列表渲染成中文行（按 level 的升级覆盖）。
static func effect_lines(def: CardDef, level: int = 0) -> Array[String]:
	var lines: Array[String] = []
	if def == null:
		return lines
	for effect_value: Variant in def.get_effects(level):
		var effect := effect_value as EffectDef
		if effect == null:
			continue
		var line := _effect_line(effect.type_key, effect.params)
		if not line.is_empty():
			lines.append(line)
	return lines


## 该卡 effect 里引用的状态 ID（去重，供悬浮展开说明）。
static func referenced_status_ids(def: CardDef, level: int = 0) -> Array[StringName]:
	var ids: Array[StringName] = []
	if def == null:
		return ids
	for effect_value: Variant in def.get_effects(level):
		var effect := effect_value as EffectDef
		if effect == null:
			continue
		var status_id := StringName(String(effect.params.get("status_id", "")))
		if not status_id.is_empty() and not ids.has(status_id):
			ids.append(status_id)
	return ids


## 效果摘要（单行），供升级对比。
static func effect_summary(def: CardDef, level: int = 0) -> String:
	if def != null and (level == 0 or def._upgrade_data(level).has("description")):
		return description_for(def, level)
	var lines := effect_lines(def, level)
	if lines.is_empty():
		return "无变化"
	return "，".join(lines)


## 悬浮详情：名称 / 费用 / 类别 / 描述（或按效果生成）/ 相关状态说明。
static func tooltip_for(def: CardDef, level: int = 0, card: BattleCardState = null, state: BattleState = null) -> String:
	if def == null:
		return ""
	var lines: Array[String] = []
	lines.append(display_name_of(def, level))
	var category := category_text(def, level)
	var cost_line := "费用 %d" % (card.effective_cost(def) if card != null else def.get_cost(level))
	if not category.is_empty():
		cost_line += " · " + category
	lines.append(cost_line)
	var body := description_for(def, level, card, state)
	if not body.is_empty():
		lines.append(body)
	var status_notes: Array[String] = []
	if def.card_number in [3, 8, 9, 29, 47]:
		status_notes.append("勇气：" + COURAGE_DESCRIPTION)
	for status_id: StringName in referenced_status_ids(def, level):
		var status_def: StatusDef = ContentDB.get_status(status_id)
		if status_def == null:
			continue
		var note := "%s：%s" % [
			status_name_of(status_id),
			status_def.description if not status_def.description.is_empty() else "（暂无说明）",
		]
		status_notes.append(note)
	if not status_notes.is_empty():
		lines.append("相关状态：\n" + "\n".join(status_notes))
	return "\n".join(lines)


## 升级前后对比（供休息处升级界面按钮文字直接展示升级后效果）。
static func upgrade_line(def: CardDef) -> String:
	if def == null:
		return ""
	var before := effect_summary(def, 0)
	var after := effect_summary(def, 1)
	var parts: Array[String] = []
	if before != after:
		parts.append("%s → %s" % [before, after])
	else:
		parts.append(before)
	var cost_before := def.get_cost(0)
	var cost_after := def.get_cost(1)
	if cost_before != cost_after:
		parts.append("费用 %d → %d" % [cost_before, cost_after])
	return "%s：%s" % [display_name_of(def), "；".join(parts)]


## 升级前后完整提示（当前 + 升级后两段）。
static func upgrade_tooltip(def: CardDef) -> String:
	if def == null:
		return ""
	return "%s\n\n── 升级后 ──\n%s" % [tooltip_for(def, 0), tooltip_for(def, 1)]


static func relic_tooltip(def: RelicDef) -> String:
	if def == null:
		return ""
	var description := def.description if not def.description.is_empty() else "（暂无说明）"
	return "%s\n%s" % [display_name_of_relic(def), description]


static func _body_text(def: CardDef, level: int) -> String:
	# 未升级优先用策划写的描述（含射程等语境）；升级后描述不会自动更新，用效果生成。
	if (level <= 0 or def._upgrade_data(level).has("description")) and not def.description.is_empty():
		return def.get_description(level)
	var lines := effect_lines(def, level)
	return "\n".join(lines)


static func _effect_line(type_key: StringName, params: Dictionary) -> String:
	match type_key:
		&"damage":
			return "造成 %d 点伤害" % int(params.get("amount", 0))
		&"block":
			return "获得 %d 点护盾" % int(params.get("amount", 0))
		&"draw":
			return "抽 %d 张牌" % int(params.get("count", 0))
		&"apply_status":
			var status_id := StringName(String(params.get("status_id", "")))
			return "%s %d 层%s（%d 回合）" % [
				"获得" if _is_self_buff(status_id) else "施加",
				int(params.get("stacks", 1)),
				status_name_of(status_id),
				int(params.get("duration", 1)),
			]
		&"move":
			return "移动"
		&"push":
			return "击退 %d 格" % int(params.get("distance", params.get("amount", 1)))
		_:
			return String(type_key)


static func _is_self_buff(status_id: StringName) -> bool:
	return status_id == StatusRules.FOCUS


## 同一个只读入口服务卡面、悬浮和牌堆，动态值不写回 Resource。
static func description_for(def: CardDef, level: int = 0, card: BattleCardState = null, state: BattleState = null) -> String:
	if def == null:
		return ""
	var stored := int(card.runtime_data.get("stacked_block", 0)) if card != null else 0
	var charge := int(card.runtime_data.get("heal_charge", 0)) if card != null else 0
	var actor: UnitState = null
	if state != null and not state.player_ids().is_empty():
		actor = state.get_unit(state.player_ids()[0])
	var base_block := float(actor.get_resource(&"courage") if actor != null else 0) * def.get_rule_value("per_courage", level, 2)
	var expected := StatSystem.compute(base_block, card.block_modifier if card != null else 0, StatusRules.outgoing_block_percent(actor), 0, INF)
	var body := _body_text(def, level).replace("{stored_block}", str(stored)).replace("{heal_charge}", str(charge)).replace("{cautious_block}", str(expected))
	var live: Array[String] = []
	if card != null:
		match def.card_number:
			3: live.append("当前预计获得 %d 护盾" % expected)
			37: live.append("本牌储备护盾：%d" % stored)
			46: live.append("当前蓄积治疗：%d" % charge)
		if card.damage_modifier != 0:
			live.append("本场伤害 %+d" % card.damage_modifier)
		if card.block_modifier != 0:
			live.append("本场护盾 %+d" % card.block_modifier)
	return ("\n".join(live) + "\n" if not live.is_empty() else "") + body


## 窄卡面保留操作与实时数值，完整规则始终在同一卡的悬浮详情中。
static func face_text(def: CardDef, card: BattleCardState, state: BattleState = null) -> String:
	var level := card.upgrade_level
	match def.card_number:
		3:
			var live := description_for(def, level, card, state).get_slice("\n", 0)
			return "消耗全部勇气\n" + live.replace("当前预计获得 ", "护盾+").replace(" 护盾", "") + "\n消耗"
		37:
			return "抽到：储备+%d\n当前储备：%d\n打出获得护盾并清空" % [6 if level > 0 else 4, int(card.runtime_data.get("stacked_block", 0))]
		46:
			return "抽到蓄积%d，上限%d\n打出治疗：%d\n消耗" % [4 if level > 0 else 3, 12 if level > 0 else 9, int(card.runtime_data.get("heal_charge", 0))]
		38:
			return "护盾+%d · 抽1\n抽到的牌临时升级\n仅本场，最多一次" % int(def.get_rule_value("block", level, 5) + card.block_modifier)
	return description_for(def, level, card, state)
