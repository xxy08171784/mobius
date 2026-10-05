class_name ContentCatalog
extends Resource
## 显式内容清单：既是 ContentDB 的索引输入，也是导出时保留内容资源的根引用。

@export var cards: Array[CardDef] = []
@export var units: Array[UnitDef] = []
@export var enemies: Array[EnemyDef] = []
@export var statuses: Array[StatusDef] = []
@export var relics: Array[RelicDef] = []
## B 线新增：角色与遭遇（Run/Route 使用）。
@export var characters: Array[CharacterDef] = []
@export var encounters: Array[EncounterDef] = []
## B 线第二轮：商店与事件。
@export var shops: Array[ShopDef] = []
@export var events: Array[EventDef] = []
