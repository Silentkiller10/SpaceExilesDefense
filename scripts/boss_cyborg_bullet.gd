extends CharacterBody2D

## Fast aimed shot from the Cyborg boss's gun. The heading is locked at
## fire time (end of the 1s aim), so a moving player can still dodge it.
## Hits the player on contact; if it misses it keeps flying and chips
## the fortress at the leak line. Shootable: one hit destroys it.

const TEX_PATH := "res://assets/sprites/machine_gun_bullet.png"
const BULLET_SCALE := Vector2(0.07, 0.07)
const SPEED := 760.0
const PLAYER_HIT_RADIUS := 32.0
## Hot magenta-red so the boss's sniper shot reads apart from carrier fire
const TINT := Color(1.0, 0.3, 0.55)

var player: CharacterBody2D
var fortress: Node2D
var damage_to_player: int = 12
var is_dying: bool = false
var _dir: Vector2 = Vector2.DOWN

func _ready() -> void:
	z_index = 6
	collision_layer = 2
	collision_mask = 0
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("enemy")

	var sprite := Sprite2D.new()
	if ResourceLoader.exists(TEX_PATH):
		sprite.texture = load(TEX_PATH)
	sprite.scale = BULLET_SCALE
	sprite.modulate = TINT
	add_child(sprite)

	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(22, 14)
	shape_node.shape = rect
	add_child(shape_node)

func launch(origin: Vector2, dir: Vector2, _player: CharacterBody2D, _fortress: Node2D, dmg: int) -> void:
	global_position = origin
	_dir = dir.normalized()
	player = _player
	fortress = _fortress
	damage_to_player = dmg
	# The art points right — rotate the whole bullet along the heading
	rotation = _dir.angle()

func _physics_process(delta: float) -> void:
	if is_dying:
		return
	velocity = _dir * SPEED
	move_and_slide()

	if player and is_instance_valid(player) and player.visible:
		if global_position.distance_to(player.global_position) <= PLAYER_HIT_RADIUS:
			if player.has_method("take_damage"):
				player.take_damage(damage_to_player)
			_pop(true)
			return

	if global_position.y >= _leak_line_y():
		_hit_fortress()
	elif global_position.y > 2400.0 or absf(global_position.x) > 3000.0:
		queue_free()

func _leak_line_y() -> float:
	if fortress and fortress.has_method("get_leak_y"):
		return float(fortress.get_leak_y())
	return 1180.0

## Player bullets — one hit destroys it.
func get_hit(_damage: int, _bullet_trans: Transform2D, _knockback: float = 0.0, _apply_ignition: bool = false) -> void:
	_pop(false)

## Tower / AoE damage — same one-hit rule.
func take_damage(_amount: int, _knockback: float = 0.0, _apply_ignition: bool = false) -> void:
	_pop(false)

func _hit_fortress() -> void:
	if fortress and fortress.has_method("take_damage"):
		var mult: float = 1.0
		if "leak_damage_mult" in fortress:
			mult = float(fortress.leak_damage_mult)
		var dmg := maxi(1, int(round(float(damage_to_player) * 0.5 * mult)))
		fortress.take_damage(dmg)
	_pop(true)

func _pop(hit_something: bool) -> void:
	if is_dying:
		return
	is_dying = true
	set_physics_process(false)
	var scene := get_tree().current_scene
	if scene:
		var burst := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in 8:
			pts.append(Vector2.from_angle(float(i) / 8.0 * TAU) * 8.0)
		burst.polygon = pts
		burst.position = global_position
		burst.color = Color(1.0, 0.4, 0.6, 0.9) if hit_something else Color(1.0, 0.85, 0.4, 0.9)
		burst.z_index = 15
		scene.add_child(burst)
		var tw := burst.create_tween()
		tw.tween_property(burst, "scale", Vector2(2.4, 2.4), 0.2)
		tw.parallel().tween_property(burst, "modulate:a", 0.0, 0.2)
		tw.tween_callback(burst.queue_free)
	queue_free()
