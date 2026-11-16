extends Node2D
## 한옥 떡집·다방 — 메인 씬.
## 탭 → 주인장 이동 → 채집 / 제작 / 손님 응대 순서를 큐로 처리한다.

const CUSTOMER_SCENE := preload("res://scenes/Customer.tscn")
const KINDS := ["fox", "cat", "duck"]
const ORDERS := ["mugwort_injeolmi", "songpyeon", "green_tea"]
const SLOT_X := [300.0, 540.0, 780.0]
const SLOT_Y := 880.0
const WALK_AREA := Rect2(100, 900, 880, 640)
const COL_GOLD := Color(0.99, 0.80, 0.32, 1.0)
const COL_PINK := Color(1.0, 0.63, 0.68, 1.0)
const COL_GREEN := Color(0.66, 0.87, 0.55, 1.0)
const COL_CREAM := Color(1.0, 0.97, 0.88, 1.0)

@onready var shopkeeper: Shopkeeper = $World/Shopkeeper
@onready var hud: HUD = $UI/HUD
@onready var effects: Node2D = $World/Effects
@onready var world: Node2D = $World

var _stations: Array[Station] = []
var _customers: Array[Customer] = []
var _free_slots: Array[int] = [0, 1, 2]
var _queue: Array[Dictionary] = []
var _running: bool = false
var _spawn_in: float = 4.0
var _decor_on: bool = true


func _ready() -> void:
	randomize()

	for node in get_tree().get_nodes_in_group("station"):
		_stations.append(node as Station)

	GameState.coins_changed.connect(hud.update_coins)
	GameState.hearts_changed.connect(hud.update_hearts)
	GameState.stock_changed.connect(hud.refresh_stock)
	hud.button_pressed.connect(_on_hud_button)

	hud.update_coins(GameState.coins)
	hud.update_hearts(GameState.hearts)
	hud.refresh_stock()
	hud.toast("손님이 오면 말풍선의 떡을 만들어 대접해 보세요")


func _process(delta: float) -> void:
	if _customers.size() >= SLOT_X.size():
		return
	_spawn_in -= delta
	if _spawn_in <= 0.0:
		_spawn_in = randf_range(9.0, 14.0)
		_spawn_customer()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_handle_tap(event.position)


# ------------------------------------------------------------------ 입력 처리
func _handle_tap(point: Vector2) -> void:
	var params := PhysicsPointQueryParameters2D.new()
	params.position = point
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var hits := get_world_2d().direct_space_state.intersect_point(params, 8)
	for hit in hits:
		var collider = hit.get("collider")
		if collider == null:
			continue
		if collider.is_in_group("customer"):
			_enqueue({"type": "customer", "target": collider})
			return
		if collider.is_in_group("station"):
			_enqueue({"type": "station", "target": collider})
			return
	_enqueue({"type": "walk", "point": point})


func _enqueue(intent: Dictionary) -> void:
	_queue.append(intent)
	if not _running:
		_run_queue()


func _run_queue() -> void:
	_running = true
	while not _queue.is_empty():
		var intent: Dictionary = _queue.pop_front()
		match String(intent["type"]):
			"station":
				await _use_station(intent["target"])
			"customer":
				await _serve_customer(intent["target"])
			"walk":
				await _walk_to(intent["point"])
	_running = false


# ------------------------------------------------------------------ 주인장 이동
func _walk_to(point: Vector2) -> void:
	var target := Vector2(
		clampf(point.x, WALK_AREA.position.x, WALK_AREA.end.x),
		clampf(point.y, WALK_AREA.position.y, WALK_AREA.end.y)
	)
	if shopkeeper.global_position.distance_to(target) < 6.0:
		return
	shopkeeper.walk_to(target)
	await shopkeeper.arrived


# ------------------------------------------------------------------ 설비 사용
func _use_station(station: Station) -> void:
	match station.mode:
		"harvest":
			await _harvest(station)
		"craft":
			await _craft(station)
		"counter":
			hud.show_popup("오늘의 레시피", _recipe_text())
		_:
			pass


func _harvest(station: Station) -> void:
	if not station.is_usable():
		hud.toast("%s은(는) 아직 자라는 중이에요" % station.display_name)
		return
	await _walk_to(station.work_point())
	shopkeeper.bob()
	station.harvest()
	GameState.add_stock(station.harvest_item, 1)
	var item_name := GameState.item_name(station.harvest_item)
	_float_text(station.global_position + Vector2(0, -station.art_size().y * 0.55),
			"+1 %s" % item_name, COL_GREEN)


func _craft(station: Station) -> void:
	var recipe: Dictionary = GameState.RECIPES[station.recipe_id]
	if not GameState.can_pay(recipe["cost"]):
		var missing := GameState.missing_text(recipe["cost"])
		hud.toast("재료가 부족해요 — %s 필요" % missing if missing != "" else "아직 만들 수 없어요")
		return
	await _walk_to(station.work_point())
	shopkeeper.bob()
	await station.play_craft(float(recipe["time"]))
	GameState.craft(station.recipe_id)
	_float_text(station.global_position + Vector2(0, -station.art_size().y * 0.6),
			"+1 %s" % String(recipe["name"]), COL_CREAM)
	hud.toast("%s 완성! 손님에게 가져다 드세요" % String(recipe["name"]))


# ------------------------------------------------------------------ 손님
func _spawn_customer() -> void:
	if _free_slots.is_empty():
		return
	var slot: int = _free_slots.pop_front()
	var customer: Customer = CUSTOMER_SCENE.instantiate()
	customer.kind = KINDS[randi() % KINDS.size()]
	customer.order_item = ORDERS[randi() % ORDERS.size()]
	customer.set_meta("slot", slot)
	world.add_child(customer)
	_customers.append(customer)
	customer.tree_exiting.connect(_on_customer_gone.bind(customer))
	customer.walk_in(Vector2(SLOT_X[slot], SLOT_Y))


func _on_customer_gone(customer: Customer) -> void:
	_customers.erase(customer)
	var slot: int = int(customer.get_meta("slot", 0))
	if not _free_slots.has(slot):
		_free_slots.append(slot)


func _serve_customer(customer: Customer) -> void:
	if not is_instance_valid(customer) or not customer.waiting:
		return
	var item: String = customer.order_item
	if GameState.stock_of(item) <= 0:
		customer.hint_missing()
		hud.toast("%s이(가) 없어요. 먼저 만들어 두세요!" % GameState.item_name(item))
		return
	var recipe: Dictionary = GameState.RECIPES[item]
	await _walk_to(Vector2(customer.global_position.x, customer.global_position.y + 90.0))
	if not is_instance_valid(customer):
		return
	GameState.consume(item)
	var price := int(recipe["price"])
	var hearts := int(recipe["hearts"])
	GameState.add_coins(price)
	GameState.add_hearts(hearts)
	GameState.served += 1
	_float_text(customer.global_position + Vector2(0, -150), "+%d 엽전" % price, COL_GOLD)
	_float_text(customer.global_position + Vector2(0, -230), "+%d ♥" % hearts, COL_PINK)
	customer.serve()


# ------------------------------------------------------------------ UI
func _on_hud_button(id: String) -> void:
	match id:
		"book":
			hud.show_popup("오늘의 레시피", _recipe_text())
		"tteok":
			hud.show_popup("떡 보관함", _pantry_text())
		"tea":
			hud.show_popup("다방 안내", _tea_text())
		"decor":
			_toggle_decor()


func _toggle_decor() -> void:
	_decor_on = not _decor_on
	for node in get_tree().get_nodes_in_group("decor"):
		if node is CanvasItem:
			node.visible = _decor_on
	hud.toast("마당 소품 %s" % ("켜짐" if _decor_on else "숨김"))


func _recipe_text() -> String:
	var lines: Array[String] = []
	for id in GameState.RECIPES.keys():
		var recipe: Dictionary = GameState.RECIPES[id]
		lines.append("· %s — %s  →  엽전 %d, 하트 %d" % [
			String(recipe["name"]), String(recipe["hint"]),
			int(recipe["price"]), int(recipe["hearts"])])
	lines.append("")
	lines.append("쑥·쌀은 마당의 밭에서 거두고, 절구·찜기·다기에서 만들어요.")
	return "\n".join(lines)


func _pantry_text() -> String:
	var lines: Array[String] = []
	lines.append("재료")
	lines.append("· 쑥 %d개 / 쌀 %d개" % [GameState.stock_of("mugwort"), GameState.stock_of("rice")])
	lines.append("")
	lines.append("만들어 둔 떡")
	lines.append("· 쑥인절미 %d개" % GameState.stock_of("mugwort_injeolmi"))
	lines.append("· 송편 %d개" % GameState.stock_of("songpyeon"))
	lines.append("· 녹차 %d잔" % GameState.stock_of("green_tea"))
	lines.append("")
	lines.append("지금까지 대접한 손님 %d분 · 엽전 %d냥" % [GameState.served, GameState.coins])
	return "\n".join(lines)


func _tea_text() -> String:
	return "\n".join([
		"다기에서는 재료 없이 녹차를 우려낼 수 있어요.",
		"시간은 조금 더 걸리지만, 쑥과 쌀을 아낄 때 좋아요.",
		"",
		"· 녹차 — 다기에서 천천히 (엽전 10, 하트 1)",
		"· 쑥인절미 — 절구에서 쑥 1 + 쌀 1 (엽전 24, 하트 2)",
		"· 송편 — 찜기에서 쌀 2 (엽전 18, 하트 1)",
		"",
		"손님이 기다리는 동안 다른 일을 해도 괜찮아요.",
	])


func _float_text(pos: Vector2, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 48)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 10)
	label.add_theme_color_override("font_outline_color", Color(0.25, 0.14, 0.08, 0.85))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(340, 64)
	label.position = pos - Vector2(170, 32)
	label.z_index = 200
	effects.add_child(label)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 120.0, 1.25) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.75).set_delay(0.5)
	tw.chain().tween_callback(label.queue_free)
