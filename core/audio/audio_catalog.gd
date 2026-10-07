class_name AudioCatalog
extends Resource
## 在 Inspector 拖入音轨。空槽保持静音，播放代码无需因补内容而修改。
const MUSIC_KEYS := [&"menu", &"route", &"battle", &"victory", &"defeat"]
const CUE_KEYS := [&"click", &"confirm", &"map_open", &"map_close", &"reward",
	&"card_draw", &"card_use", &"card_upgrade", &"shield", &"player_hurt",
	&"punch", &"sword", &"sword_heavy", &"sword_skill",
	&"step_grass", &"step_stone", &"step_water", &"dice", &"water_appear", &"poison_trap"]

@export_group("音乐")
@export var menu: AudioStream
@export var route: AudioStream
@export var battle: AudioStream
@export var victory: AudioStream
@export var defeat: AudioStream
@export_range(-40.0, 0.0) var music_gain_db: float = -6.0

@export_group("界面与环境")
@export var click: AudioStream
@export var confirm: AudioStream
@export var map_open: AudioStream
@export var map_close: AudioStream
@export var reward: AudioStream
@export var campfire: AudioStream
@export_range(-40.0, 0.0) var ambience_gain_db: float = -12.0

@export_group("战斗")
@export var card_draw: AudioStream
@export var card_use: AudioStream
@export var card_upgrade: AudioStream
@export var shield: AudioStream
@export var player_hurt: AudioStream
@export var punch: AudioStream
@export var sword: AudioStream
@export var sword_heavy: AudioStream
@export var sword_skill: AudioStream
@export var step_grass: AudioStream
@export var step_stone: AudioStream
@export var step_water: AudioStream

@export_group("混音与卡牌映射")
@export var cue_gain_db: Dictionary[StringName, float] = {
	&"click": -10.0, &"confirm": -8.0, &"map_open": -8.0, &"map_close": -8.0,
	&"reward": -4.0, &"card_draw": -6.0, &"card_use": -6.0, &"card_upgrade": -4.0,
	&"shield": -5.0, &"player_hurt": -2.0, &"punch": -3.0,
	&"sword": -3.0, &"sword_heavy": -4.0, &"sword_skill": -4.0,
	&"step_grass": -8.0, &"step_stone": -10.0, &"step_water": -10.0,
}
@export var card_attack_cues: Dictionary[StringName, StringName] = {
	&"card.reward.13": &"sword_skill", &"card.reward.16": &"sword_skill",
	&"card.reward.17": &"sword", &"card.reward.18": &"sword",
	&"card.reward.19": &"sword_skill", &"card.reward.22": &"sword_heavy",
	&"card.reward.28": &"sword", &"card.reward.33": &"sword_heavy",
	&"card.reward.34": &"sword",
}

@export_group("预留：尚无对应玩法")
@export var dice: AudioStream
@export var water_appear: AudioStream
@export var poison_trap: AudioStream


func attack_cue(card_id: StringName) -> StringName:
	return card_attack_cues.get(card_id, &"punch")
