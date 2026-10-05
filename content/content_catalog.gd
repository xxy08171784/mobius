class_name ContentCatalog
extends Resource
## 显式内容清单：既是 ContentDB 的索引输入，也是导出时保留内容资源的根引用。

@export var cards: Array[CardDef] = []
@export var units: Array[UnitDef] = []
@export var enemies: Array[EnemyDef] = []
@export var statuses: Array[StatusDef] = []
@export var relics: Array[RelicDef] = []
