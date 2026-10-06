@tool
class_name BattleHud
extends Control
## 纯数据绑定层。HUD 的位置、大小、层级全部在 battle_hud.tscn 里可视化编辑。

const ATLAS: Texture2D = preload("res://assets/textures/ui/battle_hud_atlas.png")
const R_ENERGY_BADGE_FULL := Rect2(365, 652, 264, 262)
const R_ENERGY_BADGE_EMPTY := Rect2(650, 652, 259, 262)

@onready var _player_name: Label = %PlayerName
@onready var _hp_bar: TextureProgressBar = %PlayerHPBar
@onready var _hp_text: Label = %PlayerHPValue
@onready var _shield_bar: TextureProgressBar = %PlayerShieldBar
@onready var _shield_text: Label = %PlayerShieldValue
@onready var _status_icons: StatusIconRow = %PlayerStatusIcons

@onready var _round_label: Label = %RoundLabel
@onready var _round_count: Label = %RoundCount

@onready var _enemy_name: Label = %EnemyName
@onready var _enemy_hp_bar: TextureProgressBar = %EnemyHPBar
@onready var _enemy_hp_text: Label = %EnemyHPValue
@onready var _enemy_shield_bar: TextureProgressBar = %EnemyShieldBar
@onready var _enemy_shield_text: Label = %EnemyShieldValue

@onready var _energy_badge: TextureRect = %EnergyBadge
@onready var _energy_badge_text: Label = %EnergyCount
@onready var _energy_text: Label = %EnergyText


func _ready() -> void:
	for bar: TextureProgressBar in [_hp_bar, _enemy_hp_bar]:
		bar.texture_under = UIArt.texture(&"hp")
		bar.texture_progress = UIArt.texture(&"hp")
		bar.tint_under = Color(0.28, 0.3, 0.34, 0.85)
	for bar: TextureProgressBar in [_shield_bar, _enemy_shield_bar]:
		bar.texture_under = UIArt.texture(&"shield")
		bar.texture_progress = UIArt.texture(&"shield")


func render_state(state: BattleState, phase_text: String, selected_enemy_id: int = -1) -> void:
	if state == null:
		return

	_round_label.text = phase_text
	_round_count.text = str(state.round_index)

	var players := state.player_ids()
	if not players.is_empty():
		var player := state.get_unit(int(players[0]))
		if player != null:
			_player_name.text = _unit_name(player)
			_set_bar(_hp_bar, _hp_text, player.hp, player.max_hp, "%d/%d" % [player.hp, player.max_hp])
			_set_bar(
				_shield_bar,
				_shield_text,
				player.block,
				maxi(1, player.block),
				str(player.block)
			)
			_shield_bar.visible = player.block > 0
			_shield_text.visible = player.block > 0
			var energy := player.get_resource(TurnSystem.ENERGY_RESOURCE)
			var move := player.get_resource(TurnSystem.MOVE_RESOURCE)
			_energy_badge.texture = _atlas(
				R_ENERGY_BADGE_FULL if energy > 0 else R_ENERGY_BADGE_EMPTY
			)
			_energy_badge_text.text = str(energy)
			_energy_text.text = "能量 %d/%d    移动 %d/%d" % [
				energy,
				state.energy_per_round,
				move,
				state.move_points_per_round,
			]
			%ResourceSummary.text = "能量 %d / %d\n移动 %d / %d" % [energy, state.energy_per_round, move, state.move_points_per_round]
			_status_icons.render(player)
			_fit_panel($PlayerHUD, _status_icons, player.block > 0)

	var enemies := state.alive_enemy_ids()
	$EnemyHUD.visible = enemies.has(selected_enemy_id)
	%EnemyCount.text = "存活敌人 %d" % enemies.size()
	if $EnemyHUD.visible:
		var enemy := state.get_unit(selected_enemy_id)
		if enemy != null:
			%EnemyStatusIcons.render(enemy)
			_enemy_name.text = _unit_name(enemy)
			_set_bar(
				_enemy_hp_bar,
				_enemy_hp_text,
				enemy.hp,
				enemy.max_hp,
				"%d/%d" % [enemy.hp, enemy.max_hp]
			)
			_set_bar(
				_enemy_shield_bar,
				_enemy_shield_text,
				enemy.block,
				maxi(1, enemy.block),
				str(enemy.block)
			)
			_enemy_shield_bar.visible = enemy.block > 0
			_enemy_shield_text.visible = enemy.block > 0
			_fit_panel($EnemyHUD, %EnemyStatusIcons, enemy.block > 0, %EnemyCount)


func _fit_panel(panel: Control, icons: StatusIconRow, has_shield: bool, footer: Label = null) -> void:
	var top := 252.0 if has_shield else 174.0
	icons.position.y = top
	var rows := ceili(float(icons.get_child_count()) / 5.0)
	var height := top + rows * 48.0 + 12.0
	if footer != null:
		footer.position.y = height
		footer.size.y = 36
		height += 44
	panel.get_node("Backdrop").size.y = height

func _atlas(region: Rect2) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = ATLAS
	texture.region = region
	return texture


func _set_bar(
	bar: TextureProgressBar,
	label: Label,
	value: int,
	max_value: int,
	text_value: String
) -> void:
	if bar == null:
		return
	bar.max_value = float(maxi(1, max_value))
	bar.value = float(clampi(value, 0, maxi(1, max_value)))
	if label != null:
		label.text = text_value


func _unit_name(unit: UnitState) -> String:
	if unit.is_player():
		return "莫小洛"
	var content := get_node_or_null("/root/ContentDB")
	if content != null:
		var definition: EnemyDef = content.get_enemy(unit.enemy_id)
		if definition != null and not definition.display_name.is_empty():
			return definition.display_name
	return String(unit.def_id)
