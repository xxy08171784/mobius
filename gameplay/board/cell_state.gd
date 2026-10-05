class_name CellState
extends RefCounted
## 单格的地形与标志（纯数据）。位置/占用权威在 BoardState，本类不持有单位。
## combat_rules §9/§10 要求把三件事分开，本类只表达地形层面：
##   - traversable=false 阻挡移动（墙/障碍），但**不必然**阻挡视线
##   - blocks_los=true   阻挡视线（柱子/树），但**不必然**阻挡移动
##   - trap=true         可进入，进入时由效果系统触发（§10：陷阱可进入但产生效果）

## 地形稳定键（内容/美术查表用，可空）。规则只读上面的布尔标志，不依赖此键。
var terrain_key: StringName = &""

## 是否阻挡视线（supercover LoS，§10）。
var blocks_los: bool = false

## 是否可走/可站。false = 墙/障碍。
var traversable: bool = true

## 是否为陷阱（可进入，进入触发效果）。
var trap: bool = false
