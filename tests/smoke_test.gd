extends Node
## 헤드리스 스모크 테스트: 채집 → 제작 → 손님 응대 루프를 실제 씬에서 돌려 본다.
## 실행: godot --headless --path . res://tests/smoke_test.tscn

var _fail: int = 0
var _main: Node2D


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await _run()
	print("\n=== 결과: %s (%d 실패) ===" % ["통과" if _fail == 0 else "실패", _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _check(ok: bool, message: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + message)
	if not ok:
		_fail += 1


func _station(id: String) -> Station:
	for s in get_tree().get_nodes_in_group("station"):
		if (s as Station).station_id == id:
			return s
	return null


func _run() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame

	var stations := get_tree().get_nodes_in_group("station")
	_check(stations.size() == 6, "설비 6칸 로드 (실제 %d)" % stations.size())
	_check(_station("mortar") != null and _station("steamer") != null
		and _station("tea_set") != null and _station("mugwort_planter") != null
		and _station("rice_planter") != null and _station("counter") != null,
		"절구/찜기/다기/쑥밭/쌀밭/카운터 모두 존재")

	var keeper: Shopkeeper = _main.get_node("World/Shopkeeper")
	_check(keeper != null, "주인장 인스턴스 있음")
	_check(keeper.sprite.sprite_frames != null
		and keeper.sprite.sprite_frames.get_animation_names().size() == 6,
		"걷기 애니메이션 6종(아래/옆/위 × idle/walk) 생성")

	# 1) 채집
	var mugwort_planter := _station("mugwort_planter")
	var before := keeper.global_position
	await _main._use_station(mugwort_planter)
	_check(GameState.stock_of("mugwort") == 1, "쑥밭에서 쑥 1개 채집")
	_check(keeper.global_position.distance_to(before) > 40.0, "주인장이 밭으로 걸어감")

	var again := GameState.stock_of("mugwort")
	await _main._use_station(mugwort_planter)
	_check(GameState.stock_of("mugwort") == again, "쿨다운 중에는 다시 캐지 않음")
	_check(mugwort_planter.is_usable() == false, "쑥밭이 재생 중 상태")

	# 2) 제작 — 재료가 모자라면 실패해야 한다
	await _main._use_station(_station("mortar"))
	_check(GameState.stock_of("mugwort_injeolmi") == 0, "쌀 없이는 쑥인절미를 만들지 않음")

	GameState.add_stock("rice", 2)
	await _main._use_station(_station("mortar"))
	_check(GameState.stock_of("mugwort_injeolmi") == 1, "쑥인절미 1개 완성")
	_check(GameState.stock_of("mugwort") == 0 and GameState.stock_of("rice") == 1,
		"재료가 소모됨 (쑥 0 / 쌀 1)")

	await _main._use_station(_station("steamer"))
	_check(GameState.stock_of("songpyeon") == 0, "쌀이 1개뿐이면 송편을 만들지 않음")

	GameState.add_stock("rice", 2)
	await _main._use_station(_station("steamer"))
	_check(GameState.stock_of("songpyeon") == 1, "찜기에서 송편 1개 완성")

	await _main._use_station(_station("tea_set"))
	_check(GameState.stock_of("green_tea") == 1, "다기에서 녹차 1잔 완성")

	# 3) 손님 응대
	var customer: Customer = load("res://scenes/Customer.tscn").instantiate()
	customer.kind = "duck"
	customer.order_item = "mugwort_injeolmi"
	_main.get_node("World").add_child(customer)
	customer.global_position = Vector2(540, 880)
	await get_tree().process_frame
	customer.waiting = true
	customer.patience_bar.visible = true

	var coins_before := GameState.coins
	await _main._serve_customer(customer)
	_check(GameState.coins == coins_before + 24, "손님 응대 → 엽전 +24 (현재 %d)" % GameState.coins)
	_check(GameState.hearts == 2, "하트 +2 (현재 %d)" % GameState.hearts)
	_check(GameState.stock_of("mugwort_injeolmi") == 0, "쑥인절미가 손님에게 전달됨")
	_check(GameState.served == 1, "대접한 손님 수 1")

	# 4) HUD 반영
	var hud: HUD = _main.get_node("UI/HUD")
	await get_tree().process_frame
	_check(hud.coin_value.text == str(GameState.coins), "HUD 엽전 표시가 상태와 일치")
	_check(hud._counts["rice"].text == "×%d" % GameState.stock_of("rice"),
		"HUD 쌀 개수 표시가 상태와 일치")

	# 5) 주문이 없으면 응대하지 않음
	GameState.stock["songpyeon"] = 0
	var c2: Customer = load("res://scenes/Customer.tscn").instantiate()
	c2.kind = "fox"
	c2.order_item = "songpyeon"
	_main.get_node("World").add_child(c2)
	c2.global_position = Vector2(780, 880)
	await get_tree().process_frame
	c2.waiting = true
	var coins2 := GameState.coins
	await _main._serve_customer(c2)
	_check(GameState.coins == coins2, "재고가 없으면 엽전이 늘지 않음")

	# 6) 빈 땅 탭 → 이동
	var target := Vector2(800, 1200)
	await _main._walk_to(target)
	_check(keeper.global_position.distance_to(target) < 12.0, "지정한 지점으로 이동")

	_main.queue_free()
