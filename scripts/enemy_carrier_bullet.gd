extends Node2D

## Bullet fired by the Carrier's deployed mini ships.
## Flies straight down and hits the fortress when it crosses the leak
## line. Small and fast — not shootable, unlike the Rocketeer's rockets.

const TEX_PATH := "res://assets/sprites/machine_gun_bullet.png"
const BULLET_SCALE := Vector2(0.05, 0.05)
const SPEED := 340.0
## Red-hot tint so hostile bullets read differently from tower fire
const TINT := Color(1.0, 0.45, 0.4)

var fortress: Node2D
var fort_damage: int = 5

func _ready() -> void:
	z_index = 5
	var sprite := Sprite2D.new()
	if ResourceLoader.exists(TEX_PATH):
		sprite.texture = load(TEX_PATH)
	sprite.scale = BULLET_SCALE
	# The art points right — rotate to fly nose-down
	sprite.rotation = PI / 2.0
	sprite.modulate = TINT
	add_child(sprite)

func launch(origin: Vector2, _fortress: Node2D, damage_to_fortress: int) -> void:
	global_position = origin
	fortress = _fortress
	fort_damage = damage_to_fortress

func _physics_process(delta: float) -> void:
	global_position.y += SPEED * delta
	if global_position.y >= _leak_line_y():
		_hit_fortress()
	elif global_position.y > 2400.0:
		queue_free()

func _leak_line_y() -> float:
	if fortress and fortress.has_method("get_leak_y"):
		return float(fortress.get_leak_y())
	return 1180.0

func _hit_fortress() -> void:
	if fortress and fortress.has_method("take_damage"):
		var mult: float = 1.0
		if "leak_damage_mult" in fortress:
			mult = float(fortress.leak_damage_mult)
		fortress.take_damage(maxi(1, int(round(float(fort_damage) * mult))))
	var scene := get_tree().current_scene
	if scene:
		var burst := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in 8:
			pts.append(Vector2.from_angle(float(i) / 8.0 * TAU) * 7.0)
		burst.polygon = pts
		burst.position = global_position
		burst.color = Color(1.0, 0.6, 0.3, 0.9)
		burst.z_index = 15
		scene.add_child(burst)
		var tw := burst.create_tween()
		tw.tween_property(burst, "scale", Vector2(2.2, 2.2), 0.2)
		tw.parallel().tween_property(burst, "modulate:a", 0.0, 0.2)
		tw.tween_callback(burst.queue_free)
	queue_free()
