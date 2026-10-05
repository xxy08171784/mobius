@abstract
class_name TargetSpec
extends RefCounted
## 目标指定（development_split.md §4 冻结契约，来源：架构文档 §5.2）。
## 一个目标槽 = 单位 / 格子 / 方向三类之一。同一族类两种用法：
##   - 卡牌定义：card_def.targets 里的槽（未解析：unit_id/cell/direction 留空 + 约束）
##   - 命令：PlayCardsCommand.targets 与 card_uids 一一对应（已解析：填入具体 unit/cell/方向）
## 只承载数据，不含合法性判定（board_query / combo_planner 负责）。
## 变更需双方同意并同步 development_split.md §4（B 线产出，A 的卡牌依赖它）。

enum Kind { UNIT, CELL, DIRECTION }

## 目标的稳定种类。三种用法对应三个子类，子类通过继承表达，不允许运行时改。
@abstract
func kind() -> Kind


## 是否已解析为具体目标。卡牌定义的槽为 false，命令携带的选定目标为 true。
func is_resolved() -> bool:
	return false


## 单位目标：指向一个具体单位（已解析）或"某阵营的一个单位"（未解析的槽）。
class UnitTarget extends TargetSpec:
	enum Team { ANY, ALLY, ENEMY, SELF }

	## 目标单位稳定 ID。>= 0 为已解析；-1 表示未解析（槽，只看 team）。
	var unit_id: int = -1

	## 未解析时按阵营过滤；已解析时仍保留以作一致性检查。
	var team: Team = Team.ENEMY

	func kind() -> Kind:
		return Kind.UNIT

	func is_resolved() -> bool:
		return unit_id >= 0


## 格子目标：指向盘上一格（击退落点、AOE 中心、放置类效果）。
class CellTarget extends TargetSpec:
	## 目标格子。Vector2i(-1, -1) 表示未解析。
	var cell: Vector2i = Vector2i(-1, -1)

	func kind() -> Kind:
		return Kind.CELL

	func is_resolved() -> bool:
		return cell != Vector2i(-1, -1)


## 方向目标：指向八个方向之一（直线冲击、位移推进方向）。
class DirectionTarget extends TargetSpec:
	## 方向单位向量（八个基本方向之一）。Vector2i.ZERO 表示未解析。
	var direction: Vector2i = Vector2i.ZERO

	func kind() -> Kind:
		return Kind.DIRECTION

	func is_resolved() -> bool:
		return direction != Vector2i.ZERO
