class_name ShopDef
extends Resource
## 商店配置（设计数据，只读）。决定卖什么、价格。

@export var id: StringName = &""

## 卡池：可出售的卡牌定义 ID。ShopSystem 从中无重复抽 offer_count 张。
@export var card_pool: Array[StringName] = []
@export var pool: CardPoolDef = null

## 每次光顾展示的卡牌商品数（<= 卡池大小）。
@export var offer_count: int = 4

@export var card_price: int = 50
@export var remove_price: int = 75
@export var heal_price: int = 30
@export var heal_amount: int = 10


func is_valid() -> bool:
	return not id.is_empty() and (pool != null or not card_pool.is_empty()) and card_price >= 0 and remove_price >= 0 and heal_price >= 0 and offer_count > 0
