extends Control
class_name HUD
## 상단 HUD(엽전·하트·재고), 하단 원형 버튼 4개, 토스트, 팝업.

signal button_pressed(id: String)

const COL_TEXT := Color(0.36, 0.24, 0.16, 1.0)

@onready var coin_value: Label = $TopBar/CoinBar/Value
@onready var heart_value: Label = $TopBar/HeartBar/Value
@onready var toast_label: Label = $Toast
@onready var popup: Control = $Popup
@onready var popup_title: Label = $Popup/Panel/Margin/VBox/Title
@onready var popup_body: Label = $Popup/Panel/Margin/VBox/Body
@onready var close_button: Button = $Popup/Panel/Margin/VBox/Close

var _counts: Dictionary = {}
var _toast_tween: Tween


func _ready() -> void:
	_counts = {
		"mugwort": $Pantry/Margin/Slots/Mugwort/Count,
		"rice": $Pantry/Margin/Slots/Rice/Count,
		"mugwort_injeolmi": $Pantry/Margin/Slots/Injeolmi/Count,
		"songpyeon": $Pantry/Margin/Slots/Songpyeon/Count,
		"green_tea": $Pantry/Margin/Slots/GreenTea/Count,
	}
	$BottomBar/BtnBook.pressed.connect(func() -> void: button_pressed.emit("book"))
	$BottomBar/BtnTteok.pressed.connect(func() -> void: button_pressed.emit("tteok"))
	$BottomBar/BtnTea.pressed.connect(func() -> void: button_pressed.emit("tea"))
	$BottomBar/BtnDecor.pressed.connect(func() -> void: button_pressed.emit("decor"))
	close_button.pressed.connect(close_popup)
	popup.visible = false
	toast_label.modulate.a = 0.0
	update_coins(GameState.coins)
	update_hearts(GameState.hearts)
	refresh_stock()


func update_coins(value: int) -> void:
	coin_value.text = str(value)


func update_hearts(value: int) -> void:
	heart_value.text = str(value)


func refresh_stock() -> void:
	for item in _counts.keys():
		var label: Label = _counts[item]
		label.text = "×%d" % GameState.stock_of(item)


func toast(text: String) -> void:
	toast_label.text = text
	toast_label.modulate.a = 0.0
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast_label, "modulate:a", 1.0, 0.16)
	_toast_tween.tween_interval(1.7)
	_toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.55)


func show_popup(title: String, body: String) -> void:
	popup_title.text = title
	popup_body.text = body
	popup.visible = true
	popup.modulate.a = 0.0
	create_tween().tween_property(popup, "modulate:a", 1.0, 0.14)


func close_popup() -> void:
	popup.visible = false


func is_popup_open() -> bool:
	return popup.visible
