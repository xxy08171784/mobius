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


func render_state(state: BattleState, phase_text: String) -> void:
	if state == null:
		return

	_round_label.text = phase_text
	_round_count.text = str(state.round_index)

	var players := state.alive_player_ids()
	if not players.is_empty():
		var player := state.get_unit(int(players[0]))
		if player != null:
			_player_name.text = _unit_name(player)
			_set_bar(_hp_bar, _hp_text, player.hp, player.max_hp, "%d/%d" % [player.hp, player.max_hp])
			_set_bar(
				_shield_bar,
				_shield_text,
				player.block,
				maxi(1, player.max_hp),
				"护盾 %d" % player.block
			)
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
			_status_icons.render(player)

	var enemies := state.alive_enemy_ids()
	if enemies.is_empty():
		_enemy_name.text = "敌人"
		_set_bar(_enemy_hp_bar, _enemy_hp_text, 0, 1, "已击败")
		_set_bar(_enemy_shield_bar, _enemy_shield_text, 0, 1, "护盾 0")
	else:
		var enemy := state.get_unit(int(enemies[0]))
		if enemy != null:
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
				maxi(1, enemy.max_hp),
				"护盾 %d" % enemy.block
			)

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
	match unit.def_id:
		&"unit.hero.prototype":
			return "玩家"
		&"unit.enemy.ring_stalker":
			return "环影猎手"
		&"unit.enemy.echo_guard":
			return "回声守卫"
		&"unit.enemy.loop_hound":
			return "循环猎犬"
		&"unit.enemy.mobius_warden":
			return "莫比乌斯守望者"
		_:
			return String(unit.def_id)
