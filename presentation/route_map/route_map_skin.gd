class_name RouteMapSkin
extends Resource
## 选关地图的美术槽位（发给美术的资源类型）。
## 接入优先级：显式槽位（Inspector 拖入）> PNG 命名约定自动加载 > 占位色块/代码绘制。
## 命名约定目录：res://assets/textures/ui/map/，文件名 = 类型键去掉点（node.monster -> node_monster.png）。

const DIR := "res://assets/textures/ui/map/"

const NODE_TYPES: Array[StringName] = [
	RouteMapDef.TYPE_MONSTER,
	RouteMapDef.TYPE_ELITE,
	RouteMapDef.TYPE_REST,
	RouteMapDef.TYPE_SHOP,
	RouteMapDef.TYPE_TREASURE,
	RouteMapDef.TYPE_EVENT,
	RouteMapDef.TYPE_BOSS,
]

## 地图背景（默认/兜底）。
@export var background: Texture2D

## 各章背景（索引 = 章号）。为空的章回退到 background。
@export var act_backgrounds: Array[Texture2D] = []

## 路径线纯色（本轮未采用贴图，先用纯色替代）。
@export var path_color: Color = Color(0.82, 0.77, 0.62, 0.75)
@export var path_width: float = 3.0

## 节点图标槽位：type_key -> 贴图。
@export var node_icons: Dictionary[StringName, Texture2D] = {}

## 节点按钮尺寸（含边缘）。
@export var icon_size: float = 64.0

## 表现色（无贴图时的代码绘制）。
@export var current_marker_color: Color = Color(1.0, 0.85, 0.3, 1.0)
@export var available_glow_color: Color = Color(1.0, 1.0, 1.0, 0.35)

## 状态调色（压暗/去色）。
@export var locked_modulate: Color = Color(0.35, 0.35, 0.42, 1.0)
@export var visited_modulate: Color = Color(0.6, 0.6, 0.66, 1.0)


## 用命名约定补缺：仅当槽位为空时加载对应文件。
func load_defaults() -> void:
	var act_names := ["bg_act1.png", "bg_act2.png", "bg_act3.png"]
	if act_backgrounds.is_empty():
		for n in act_names:
			act_backgrounds.append(_tex(n))
	if background == null:
		for t in act_backgrounds:
			if t != null:
				background = t
				break
	for t in NODE_TYPES:
		if node_icons.has(t):
			continue
		var tex := _tex("%s.png" % String(t).replace(".", "_"))
		if tex != null:
			node_icons[t] = tex


## 第 act_index 章的背景；该章无贴图时回退到 background（本轮 act2/3 因此用 act1 背景）。
func background_for(act_index: int) -> Texture2D:
	if act_index >= 0 and act_index < act_backgrounds.size() and act_backgrounds[act_index] != null:
		return act_backgrounds[act_index]
	return background


func icon_for(type_key: StringName) -> Texture2D:
	if node_icons.has(type_key):
		return node_icons[type_key]
	var tex := _tex("%s.png" % String(type_key).replace(".", "_"))
	if tex != null:
		node_icons[type_key] = tex
	return tex


func _tex(file: String) -> Texture2D:
	var p := DIR + file
	if ResourceLoader.exists(p):
		return load(p)
	return null
