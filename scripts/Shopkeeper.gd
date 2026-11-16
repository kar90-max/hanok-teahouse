extends CharacterBody2D
class_name Shopkeeper
## 탭 지점까지 부드럽게 걸어가는 떡집 주인장.
## 4x3 걷기 시트(아래/옆/위)를 코드로 SpriteFrames 로 묶어 쓴다.

signal arrived()

const SHEET := preload("res://assets/sprites/shopkeeper_walk.png")
const COLS := 4
const ROWS := 3
const WALK_FPS := 9.0
const DEPTHS := {"down": 0, "side": 1, "up": 2}

@export var speed: float = 360.0
@export var arrive_epsilon: float = 6.0

var _base_scale: Vector2 = Vector2.ONE
var _target: Vector2 = Vector2.ZERO
var _moving: bool = false
var _facing: String = "down"

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var shadow: Sprite2D = $Shadow


func _ready() -> void:
	_build_frames()
	var tex := SHEET
	var fw := tex.get_width() / float(COLS)
	var fh := tex.get_height() / float(ROWS)
	sprite.offset = Vector2(0.0, -fh / 2.0)
	_base_scale = sprite.scale
	shadow.scale = Vector2(0.30, 0.16)
	shadow.position = Vector2(0.0, -3.0)
	_play("idle_down")


func _build_frames() -> void:
	var tex := SHEET
	var fw := tex.get_width() / float(COLS)
	var fh := tex.get_height() / float(ROWS)
	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")
	for dir in DEPTHS.keys():
		var row: int = DEPTHS[dir]
		frames.add_animation("idle_" + dir)
		frames.set_animation_speed("idle_" + dir, 1.0)
		frames.set_animation_loop("idle_" + dir, false)
		frames.add_frame("idle_" + dir, _atlas(tex, 0, row, fw, fh))
		frames.add_animation("walk_" + dir)
		frames.set_animation_speed("walk_" + dir, WALK_FPS)
		frames.set_animation_loop("walk_" + dir, true)
		for col in COLS:
			frames.add_frame("walk_" + dir, _atlas(tex, col, row, fw, fh))
	sprite.sprite_frames = frames


func _atlas(tex: Texture2D, col: int, row: int, fw: float, fh: float) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(col * fw, row * fh, fw, fh)
	return at


func walk_to(point: Vector2) -> void:
	_target = point
	_moving = true
	var dir := point - global_position
	if dir.length() > 1.0:
		_face(dir)


func is_moving() -> bool:
	return _moving


func _physics_process(delta: float) -> void:
	if not _moving:
		velocity = Vector2.ZERO
		return
	var to := _target - global_position
	if to.length() <= arrive_epsilon:
		global_position = _target
		_moving = false
		velocity = Vector2.ZERO
		_play("idle_" + _facing)
		arrived.emit()
		return
	var dir := to.normalized()
	velocity = dir * speed
	move_and_slide()
	_face(dir)
	_play("walk_" + _facing)


func _face(dir: Vector2) -> void:
	if absf(dir.x) > absf(dir.y) * 0.8:
		_facing = "side"
		sprite.flip_h = dir.x < 0.0
	else:
		_facing = "up" if dir.y < 0.0 else "down"
		sprite.flip_h = false


func _play(anim_name: String) -> void:
	if sprite.animation != anim_name:
		sprite.play(anim_name)


## 채집/제작할 때 살짝 몸을 숙이는 동작.
func bob() -> void:
	var tw := create_tween()
	tw.tween_property(sprite, "scale", _base_scale * Vector2(1.06, 0.92), 0.14)
	tw.tween_property(sprite, "scale", _base_scale, 0.18)
