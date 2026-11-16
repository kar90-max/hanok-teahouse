extends Node
## 개발용 스크린샷 캡처 (에디터/CI 밖에서 실행).
## Xvfb :99 & DISPLAY=:99 godot --path . --rendering-driver opengl3 --resolution 1080x1920 res://tests/shot.tscn

var _main: Node2D


func _ready() -> void:
	await get_tree().process_frame
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	for i in 20:
		await get_tree().process_frame
	await _shot("res://shot_1_main.png")

	# 손님 등장 + 말풍선
	GameState.add_stock("mugwort", 2)
	GameState.add_stock("rice", 3)
	_main._spawn_customer()
	await get_tree().create_timer(2.2).timeout
	for i in 10:
		await get_tree().process_frame
	await _shot("res://shot_2_customer.png")

	# 절구에서 제작 중 (진행바)
	for s in get_tree().get_nodes_in_group("station"):
		if (s as Station).station_id == "mortar":
			_main._enqueue({"type": "station", "target": s})
	await get_tree().create_timer(2.4).timeout
	await _shot("res://shot_3_craft.png")

	# 레시피 팝업
	await get_tree().create_timer(2.0).timeout
	_main._on_hud_button("book")
	for i in 10:
		await get_tree().process_frame
	await _shot("res://shot_4_popup.png")

	get_tree().quit()


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("shot saved: ", path, " ", img.get_size())
