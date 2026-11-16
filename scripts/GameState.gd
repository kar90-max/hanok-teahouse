extends Node
## 게임 전체 상태 — 엽전, 하트, 재고, 레시피 정의를 한 곳에서 관리한다.
## 오토로드 이름: GameState

signal coins_changed(value: int)
signal hearts_changed(value: int)
signal stock_changed()
signal toasted(text: String)

const ITEMS := ["mugwort", "rice", "mugwort_injeolmi", "songpyeon", "green_tea"]

const ITEM_NAMES := {
	"mugwort": "쑥",
	"rice": "쌀",
	"mugwort_injeolmi": "쑥인절미",
	"songpyeon": "송편",
	"green_tea": "녹차",
}

## recipe_id 로 조회하는 레시피 표.
## station: 사용하는 설비 id / cost: 드는 재료 / time: 만드는 시간(초) / price: 엽전 / hearts: 하트
const RECIPES := {
	"mugwort_injeolmi": {
		"name": "쑥인절미",
		"station": "mortar",
		"cost": {"mugwort": 1, "rice": 1},
		"time": 2.6,
		"price": 24,
		"hearts": 2,
		"hint": "절구에서 쑥 1 + 쌀 1",
	},
	"songpyeon": {
		"name": "송편",
		"station": "steamer",
		"cost": {"rice": 2},
		"time": 3.0,
		"price": 18,
		"hearts": 1,
		"hint": "찜기에서 쌀 2",
	},
	"green_tea": {
		"name": "녹차",
		"station": "tea_set",
		"cost": {},
		"time": 3.4,
		"price": 10,
		"hearts": 1,
		"hint": "다기에서 바로 우려내기 (재료 없음)",
	},
}

var coins: int = 0
var hearts: int = 0
var served: int = 0
var stock: Dictionary = {
	"mugwort": 0,
	"rice": 0,
	"mugwort_injeolmi": 0,
	"songpyeon": 0,
	"green_tea": 0,
}


func _ready() -> void:
	reset()


func reset() -> void:
	coins = 0
	hearts = 0
	served = 0
	for key in stock.keys():
		stock[key] = 0
	coins_changed.emit(coins)
	hearts_changed.emit(hearts)
	stock_changed.emit()


func add_coins(amount: int) -> void:
	coins = max(0, coins + amount)
	coins_changed.emit(coins)


func add_hearts(amount: int) -> void:
	hearts = max(0, hearts + amount)
	hearts_changed.emit(hearts)


func add_stock(item: String, amount: int = 1) -> void:
	if not stock.has(item):
		stock[item] = 0
	stock[item] = max(0, int(stock[item]) + amount)
	stock_changed.emit()


func stock_of(item: String) -> int:
	return int(stock.get(item, 0))


func item_name(item: String) -> String:
	return String(ITEM_NAMES.get(item, item))


func can_pay(cost: Dictionary) -> bool:
	for item in cost.keys():
		if stock_of(item) < int(cost[item]):
			return false
	return true


func pay(cost: Dictionary) -> bool:
	if not can_pay(cost):
		return false
	for item in cost.keys():
		stock[item] = int(stock[item]) - int(cost[item])
	stock_changed.emit()
	return true


func missing_text(cost: Dictionary) -> String:
	var parts: Array[String] = []
	for item in cost.keys():
		var need := int(cost[item]) - stock_of(item)
		if need > 0:
			parts.append("%s %d개" % [item_name(item), need])
	return ", ".join(parts)


## 레시피 제작: 재료를 내고 완성품을 재고에 넣는다.
func craft(recipe_id: String) -> bool:
	if not RECIPES.has(recipe_id):
		return false
	var recipe: Dictionary = RECIPES[recipe_id]
	if not pay(recipe["cost"]):
		return false
	add_stock(recipe_id, 1)
	return true


func consume(item: String) -> bool:
	if stock_of(item) <= 0:
		return false
	stock[item] = int(stock[item]) - 1
	stock_changed.emit()
	return true
