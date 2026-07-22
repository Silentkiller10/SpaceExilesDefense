extends CharacterBody2D

## Falling star fired by the Giant Star boss. Comes in small / medium / large
## sizes with different speed, fortress damage, and hit points.

const TEX_PATH := "res://assets/png/bosses/falling_star.png"

## size_key -> visual + combat profile
const SIZE_PROFILES := {
	"small": {"scale": 0.18, "hits": 1, "damage": 10, "speed": 260.0, "collision": Vector2(10, 28)},
	"medium": {"scale": 0.28, "hits": 2, "damage": 18, "speed": 200.0, "collision": Vector2(14, 40)},
	"large": {"scale": 0.42, "hits": 3, "damage": 28, "speed": 150.0, "collision": Vector2(20, 56)},
}

var fortress: Node2D
var fort_damage: int = 12
var is_dying: bool = false
var hits_left: int = 1
var fall_speed: float = 170.0
var size_key: String = "medium"

var _drift: float = 0.0
var _spin: float = 0.0
var _flash_t: float = 0.0
var _sprite: Sprite2D
var _shape: CollisionShape2D
var _hp_bar: ProgressBar

func _ready() -> void:
	z_index = 6
	collision_layer = 2
	collision_mask = 0
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("enemy")

	_sprite = Sprite2D.new()
	if ResourceLoader.exists(TEX_PATH):
		_sprite.texture = load(TEX_PATH)
	add_child(_sprite)

	_shape = CollisionShape2D.new()
	_shape.shape = RectangleShape2D.new()
	add_child(_shape)

	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.z_index = 10
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.35, 0.25)
	_hp_bar.add_theme_stylebox_override("fill", fill)
	add_child(_hp_bar)

func launch(origin: Vector2, _fortress: Node2D, profile_key: String, damage_scale: float = 1.0) -> void:
	global_position = origin
	fortress = _fortress
	size_key = profile_key if SIZE_PROFILES.has(profile_key) else "medium"
	var p: Dictionary = SIZE_PROFILES[size_key]
	fall_speed = float(p["speed"]) * randf_range(0.92, 1.08)
	fort_damage = maxi(1, int(round(float(p["damage"]) * damage_scale)))
	hits_left = int(p["hits"])
	_drift = 0.0
	_spin = 0.0

	if _sprite:
		var s := float(p["scale"])
		_sprite.scale = Vector2(s, s)
		_sprite.rotation = 0.0
	if _shape and _shape.shape is RectangleShape2D:
		(_shape.shape as RectangleShape2D).size = p["collision"]

	if _hp_bar:
		_hp_bar.max_value = hits_left
		_hp_bar.value = hits_left
		var col: Vector2 = p["collision"]
		_hp_bar.position = Vector2(-col.x * 0.45, -col.y * 0.55)
		_hp_bar.size = Vector2(col.x * 0.9, 6)

func _physics_process(delta: float) -> void:
	if is_dying:
		return
	velocity = Vector2(0.0, fall_speed * _stasis_scale())
	move_and_slide()
	if _sprite:
		if _flash_t > 0.0:
			_flash_t -= delta
			_sprite.modulate = Color(1.8, 1.6, 1.6)
		else:
			_sprite.modulate = Color.WHITE

	var leak_y := 1180.0
	if fortress and fortress.has_method("get_leak_y"):
		leak_y = float(fortress.get_leak_y())
	if global_position.y >= leak_y:
		_impact_fortress()

func _stasis_scale() -> float:
	var scale := 1.0
	if not is_inside_tree():
		return scale
	for z in get_tree().get_nodes_in_group("stasis_zone"):
		if z.has_method("get_slow_for") and is_instance_valid(z):
			scale = minf(scale, float(z.get_slow_for(global_position)))
	return scale

func take_damage(_amount: int, _knockback: float = 0.0, _apply_ignition: bool = false) -> void:
	if is_dying:
		return
	hits_left -= 1
	_flash_t = 0.08
	if _hp_bar:
		_hp_bar.value = hits_left
	if hits_left <= 0:
		_die()

func _impact_fortress() -> void:
	if is_dying:
		return
	is_dying = true
	if fortress and fortress.has_method("take_damage"):
		var mult: float = 1.0
		if "leak_damage_mult" in fortress:
			mult = float(fortress.leak_damage_mult)
		fortress.take_damage(maxi(1, int(round(float(fort_damage) * mult))))
	_spawn_impact_fx()
	queue_free()

func _die() -> void:
	if is_dying:
		return
	is_dying = true
	_spawn_impact_fx()
	queue_free()

func _spawn_impact_fx() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var burst := Polygon2D.new()
	var pts := PackedVector2Array()
	var r := 12.0 + float(hits_left + 1) * 6.0
	for i in 12:
		pts.append(Vector2.from_angle(float(i) / 12.0 * TAU) * r)
	burst.polygon = pts
	burst.position = global_position
	burst.color = Color(1.0, 0.35, 0.2, 0.9)
	burst.z_index = 16
	scene.add_child(burst)
	var tw := burst.create_tween()
	tw.tween_property(burst, "scale", Vector2(2.4, 2.4), 0.22)
	tw.parallel().tween_property(burst, "modulate:a", 0.0, 0.22)
	tw.tween_callback(burst.queue_free)
