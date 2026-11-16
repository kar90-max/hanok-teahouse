extends Area2D
class_name Customer
## 손님 동물(여우·고양이·오리). 걸어 들어와 말풍선으로 주문을 하고,
## 주문을 받으면 기뻐하며 돌아간다. 인내심이 다하면 아쉬워하며 떠난다.

signal walked_in(customer: Area2D)
signal order_served(customer: Area2D)
signal gave_up(customer: Area2D)

const ART := {
	"fox": preload("res://assets/sprites/customer_fox.png"),
	"cat": preload("res://assets/sprites/customer_cat.png"),
	"duck": preload("res://assets/sprites/customer_duck.png"),
}
const ICONS := {
	"mugwort_injeolmi": preload("res://assets/icons/mugwort_injeolmi.png"),
	"songpyeon": preload("res://assets/icons/songpyeon.png"),
	"green_tea": preload("res://assets/icons/green_tea.png"),
}
const ITEM_NAMES := {
	"mugwort_injeolmi": "쑥인절미",
	"songpyeon": "송편",
	"green_tea": "녹차",
}
const ART_SCALE := 0.34

@export var kind: String = "fox"
@export var order_item: String = "songpyeon"
@export var patience: float = 45.0

var waiting: bool = false
var patrol_time: float = 0.0

@onready var sprite: Sprite2D = $Sprite
@onready var shadow: Sprite2D = $Shadow
@onready var bubble: Sprite2D = $Bubble
@onready var order_icon: Sprite2D = $Bubble/OrderIcon
@onready var order_label: Label = $Bubble/OrderLabel
@onready var patience_bar: Panel = $Patience
@onready var patience_fill: Panel = $Patience/Fill
@onready var shape: CollisionShape2D = $CollisionShape2D

var _left: float = 0.0
var _hop: Tween


func _ready() -> void:
	add_to_group("customer")
	var tex: Texture2D = ART.get(kind, ART["fox"])
	sprite.texture = tex
	var size := tex.get_size() * ART_SCALE
	sprite.scale = Vector2(ART_SCALE, ART_SCALE)
	sprite.offset = Vector2(0, -tex.get_size().y / 2.0)
	shadow.scale = Vector2(size.x * 0.55 / 256.0, size.x * 0.22 / 256.0)

	bubble.position = Vector2(0, -size.y - 46.0)
	bubble.scale = Vector2(0.30, 0.30)
	bubble.z_index = 4
	order_icon.texture = ICONS.get(order_item, ICONS["songpyeon"])
	order_icon.position = Vector2(-235, -6)
	order_icon.scale = Vector2(0.72, 0.72)
	order_label.text = String(ITEM_NAMES.get(order_item, "떡"))
	order_label.position = Vector2(-56, -95)
	order_label.size = Vector2(470, 190)
	order_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	order_label.add_theme_font_size_override("font_size", 112)
	patience_bar.position = Vector2(-70, -size.y - 26.0)
	patience_bar.z_index = 4
	patience_bar.visible = false
	bubble.visible = false

	var rect := RectangleShape2D.new()
	rect.size = Vector2(size.x * 0.62, size.y * 0.5)
	shape.shape = rect
	shape.position = Vector2(0, -rect.size.y * 0.5)

	_left = patience


func _process(delta: float) -> void:
	if not waiting:
		return
	_left -= delta
	var ratio := clampf(_left / patience, 0.0, 1.0)
	patience_fill.size = Vector2(maxf(0.0, (patience_bar.size.x - 4.0) * ratio), patience_bar.size.y - 4.0)
	if _left <= 0.0:
		waiting = false
		gave_up.emit(self)
		_whine()


## 오른쪽 밖에서 걸어 들어와 자리에 선다.
func walk_in(target_pos: Vector2) -> void:
	global_position = Vector2(target_pos.x + 420.0, target_pos.y + 40.0)
	patience_bar.visible = false
	var tw := create_tween()
	tw.tween_property(self, "global_position", target_pos, 1.35).set_trans(Tween.TRANS_SINE)
	await tw.finished
	waiting = true
	patience_bar.visible = true
	patience_fill.size = Vector2(patience_bar.size.x - 4.0, patience_bar.size.y - 4.0)
	bubble.visible = true
	bubble.scale = Vector2(0.02, 0.02)
	create_tween().tween_property(bubble, "scale", Vector2(0.30, 0.30), 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	walked_in.emit(self)


## 주문을 받았다: 말풍선이 통통 튀고 하트가 뜬 뒤 돌아간다.
func serve() -> void:
	waiting = false
	patience_bar.visible = false
	bubble.visible = false
	var base := Vector2(ART_SCALE, ART_SCALE)
	var tw := create_tween()
	tw.tween_property(sprite, "scale", base * Vector2(1.12, 0.9), 0.12)
	tw.tween_property(sprite, "scale", base, 0.16)
	await tw.finished
	order_served.emit(self)
	_leave()


func _whine() -> void:
	bubble.visible = false
	var tw := create_tween()
	tw.tween_property(sprite, "rotation", deg_to_rad(-6.0), 0.12)
	tw.tween_property(sprite, "rotation", deg_to_rad(6.0), 0.16)
	tw.tween_property(sprite, "rotation", 0.0, 0.12)
	await tw.finished
	_leave()


func _leave() -> void:
	var tw := create_tween()
	tw.tween_property(self, "global_position",
		global_position + Vector2(460, 60), 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(queue_free)


## 주문이 없을 때 살짝 고개를 갸웃하는 대기 모션.
func hint_missing() -> void:
	var tw := create_tween()
	tw.tween_property(sprite, "rotation", deg_to_rad(5.0), 0.1)
	tw.tween_property(sprite, "rotation", deg_to_rad(-3.0), 0.12)
	tw.tween_property(sprite, "rotation", 0.0, 0.1)
