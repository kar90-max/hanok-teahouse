extends Area2D
class_name Station
## 떡집 뜰의 설비(절구·찜기·다기)와 밭(쑥·쌀) 한 칸.
## 스스로 밭의 재생 쿨다운과 제작 진행바를 관리하고, 탭은 Main 이 처리한다.

signal tapped(station: Area2D)

@export_enum("harvest", "craft", "counter") var mode: String = "craft"
@export var station_id: String = "mortar"
@export var display_name: String = "절구"
@export var texture: Texture2D
@export var badge_icon: Texture2D
@export var art_scale: float = 0.5
@export var harvest_item: String = ""
@export var recipe_id: String = ""
@export var cooldown: float = 7.0
@export var work_offset: Vector2 = Vector2(0, 70)

var ready_to_use: bool = true

@onready var sprite: Sprite2D = $Sprite
@onready var shadow: Sprite2D = $Shadow
@onready var tag: Label = $Tag
@onready var badge: Sprite2D = $Badge
@onready var bar: Panel = $Bar
@onready var bar_fill: Panel = $Bar/Fill
@onready var shape: CollisionShape2D = $CollisionShape2D

var _timer: Timer
var _art_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("station")
	if texture != null:
		_art_size = texture.get_size()
	var vis := _art_size * art_scale
	sprite.texture = texture
	sprite.scale = Vector2(art_scale, art_scale)
	sprite.offset = Vector2(0.0, -_art_size.y / 2.0)
	shadow.scale = Vector2(vis.x * 0.62 / 256.0, vis.x * 0.20 / 256.0)
	shadow.position = Vector2(0, -vis.x * 0.02)
	tag.text = display_name
	tag.position = Vector2(-130.0, -vis.y - 46.0)
	tag.size = Vector2(260, 40)
	badge.texture = badge_icon
	badge.position = Vector2(vis.x * 0.36, -vis.y * 0.64)
	badge.scale = Vector2(0.14, 0.14)
	badge.visible = badge_icon != null
	tag.z_as_relative = false
	tag.z_index = 10
	badge.z_as_relative = false
	badge.z_index = 9
	bar.z_as_relative = false
	bar.z_index = 10
	bar.visible = false
	bar.position = Vector2(-110.0, -vis.y - 96.0)
	bar.size = Vector2(220, 22)
	bar_fill.size = Vector2(0, 16)
	if mode == "counter":
		tag.position = Vector2(-160.0, -vis.y * 0.4165 - 34.0)
		tag.size = Vector2(320, 64)
		tag.add_theme_font_size_override("font_size", 46)
		tag.add_theme_constant_override("outline_size", 0)

	var rect := RectangleShape2D.new()
	rect.size = Vector2(maxf(vis.x * 0.82, 90.0), maxf(vis.y * 0.6, 90.0))
	shape.shape = rect
	shape.position = Vector2(0, -rect.size.y * 0.5)

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = cooldown
	_timer.timeout.connect(_on_grown)
	add_child(_timer)


func art_size() -> Vector2:
	return _art_size * art_scale


## 주인장이 서서 일할 자리(발 기준).
func work_point() -> Vector2:
	return global_position + work_offset


func is_usable() -> bool:
	return ready_to_use


func harvest() -> void:
	_set_regrowing(true)
	_timer.start(cooldown)


func _set_regrowing(value: bool) -> void:
	ready_to_use = not value
	sprite.modulate = Color(0.72, 0.75, 0.68, 1.0) if value else Color.WHITE
	badge.visible = badge_icon != null and not value


func _on_grown() -> void:
	_set_regrowing(false)
	pulse()


## 제작 진행바를 채우고 끝나면 돌아온다.
func play_craft(duration: float) -> void:
	bar.visible = true
	bar_fill.size = Vector2(0, 16)
	var tw := create_tween()
	tw.tween_property(bar_fill, "size:x", 214.0, maxf(duration, 0.2))
	await tw.finished
	bar.visible = false
	pulse()


func pulse() -> void:
	var tw := create_tween()
	tw.tween_property(sprite, "scale", Vector2(art_scale * 1.06, art_scale * 0.94), 0.12)
	tw.tween_property(sprite, "scale", Vector2(art_scale, art_scale), 0.18)
