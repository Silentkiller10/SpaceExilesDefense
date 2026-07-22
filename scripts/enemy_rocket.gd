extends CharacterBody2D

## Rocket fired by the Rocketeer enemy ship. Falls toward the fortress,
## launches with a short boost, then keeps accelerating the longer it lives
## while its heat tint shifts toward red. Dies after 3 player/tower hits
## (each hit strips a third of its HP) regardless of the hit's damage.

const TEX_PATH := "res://assets/png/towers/rocket_projectile.png"
## Tower rockets use 0.045 — this one is intentionally a bit bigger.
const ROCKET_SCALE := 0.07
const MAX_HITS := 3

const BOOST_SPEED := 300.0
const BOOST_TIME := 0.35
## Speed gained every 0.5s of flight after the boost ends.
const ACCEL_STEP := 24.0
const ACCEL_INTERVAL := 0.5
const HEAT_COLOR := Color(1.0, 0.25, 0.18)

var fortress: Node2D
var fort_damage: int = 15
var is_dying: bool = false
var hits_left: int = MAX_HITS
var base_speed: float = 95.0

var _time: float = 0.0
var _accel_timer: float = 0.0
var _trail_t: float = 0.0
var _flash_t: float = 0.0
var _sprite: Sprite2D
var _hp_bar: ProgressBar

func _ready() -> void:
	z_index = 5
	collision_layer = 2
	collision_mask = 0
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	add_to_group("enemy")

	_sprite = Sprite2D.new()
	if ResourceLoader.exists(TEX_PATH):
		_sprite.texture = load(TEX_PATH)
	_sprite.scale = Vector2(ROCKET_SCALE, ROCKET_SCALE)
	# Art points right; rotate to point down toward the fortress.
	_sprite.rotation = PI / 2.0
	add_child(_sprite)

	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(22, 58)
	shape_node.shape = rect
	add_child(shape_node)

	_hp_bar = ProgressBar.new()
	_hp_bar.max_value = MAX_HITS
	_hp_bar.value = MAX_HITS
	_hp_bar.show_percentage = false
	_hp_bar.position = Vector2(-16, -46)
	_hp_bar.size = Vector2(32, 6)
	_hp_bar.z_index = 10
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.55, 0.2)
	_hp_bar.add_theme_stylebox_override("fill", fill)
	add_child(_hp_bar)

func launch(origin: Vector2, _fortress: Node2D, damage_to_fortress: int) -> void:
	global_position = origin
	fortress = _fortress
	fort_damage = damage_to_fortress

func _physics_process(delta: float) -> void:
	if is_dying:
		return
	_time += delta

	var spd: float
	if _time < BOOST_TIME:
		spd = BOOST_SPEED
	else:
		_accel_timer += delta
		while _accel_timer >= ACCEL_INTERVAL:
			_accel_timer -= ACCEL_INTERVAL
			base_speed += ACCEL_STEP
		spd = base_speed

	velocity = Vector2(0.0, spd * _stasis_scale())
	move_and_slide()

	# Heat up: shift toward red the longer the rocket survives
	var heat: float = clampf((_time - BOOST_TIME) / 6.0, 0.0, 1.0)
	if _sprite:
		if _flash_t > 0.0:
			_flash_t -= delta
			_sprite.modulate = Color(1.8, 1.8, 1.8)
		else:
			_sprite.modulate = Color.WHITE.lerp(HEAT_COLOR, heat)
	_emit_trail(delta, heat)

	var leak_y := 1180.0
	if fortress and fortress.has_method("get_leak_y"):
		leak_y = fortress.get_leak_y()
	if global_position.y >= leak_y:
		_hit_fortress()

func _stasis_scale() -> float:
	var scale := 1.0
	if not is_inside_tree():
		return scale
	for z in get_tree().get_nodes_in_group("stasis_zone"):
		if z.has_method("get_slow_for") and is_instance_valid(z):
			scale = minf(scale, float(z.get_slow_for(global_position)))
	return scale

func _emit_trail(delta: float, heat: float) -> void:
	_trail_t -= delta
	if _trail_t > 0.0:
		return
	_trail_t = 0.05
	var scene := get_tree().current_scene
	if scene == null:
		return
	var puff := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 8:
		pts.append(Vector2.from_angle(float(i) / 8.0 * TAU) * 5.0)
	puff.polygon = pts
	puff.position = global_position + Vector2(0, -30)
	puff.color = Color(1.0, 0.75 - heat * 0.45, 0.3 - heat * 0.15, 0.5)
	puff.z_index = 4
	scene.add_child(puff)
	var tw := puff.create_tween()
	tw.tween_property(puff, "scale", Vector2(2.0, 2.0), 0.3)
	tw.parallel().tween_property(puff, "modulate:a", 0.0, 0.3)
	tw.tween_callback(puff.queue_free)

## Player bullets — every shot removes a third of the rocket's HP.
func get_hit(_damage: int, _bullet_trans: Transform2D, _knockback: float = 0.0, _apply_ignition: bool = false) -> void:
	_take_hit()

## Tower damage — same 3-hit rule.
func take_damage(_amount: int, _knockback: float = 0.0, _apply_ignition: bool = false) -> void:
	_take_hit()

func _take_hit() -> void:
	if is_dying:
		return
	hits_left -= 1
	if _hp_bar:
		_hp_bar.value = hits_left
	_flash_t = 0.1
	if hits_left <= 0:
		_explode(false)

func _hit_fortress() -> void:
	if fortress and fortress.has_method("take_damage"):
		var mult: float = 1.0
		if "leak_damage_mult" in fortress:
			mult = float(fortress.leak_damage_mult)
		fortress.take_damage(maxi(1, int(round(float(fort_damage) * mult))))
	_explode(true)

func _explode(reached_fortress: bool) -> void:
	if is_dying:
		return
	is_dying = true
	set_physics_process(false)
	if _hp_bar:
		_hp_bar.visible = false
	if _sprite:
		_sprite.visible = false
	var scene := get_tree().current_scene
	if scene:
		var burst := Polygon2D.new()
		var pts := PackedVector2Array()
		for i in 12:
			pts.append(Vector2.from_angle(float(i) / 12.0 * TAU) * 12.0)
		burst.polygon = pts
		burst.position = global_position
		burst.color = Color(1.0, 0.5, 0.2, 0.9) if reached_fortress else Color(1.0, 0.85, 0.4, 0.9)
		burst.z_index = 15
		scene.add_child(burst)
		var tw := burst.create_tween()
		tw.tween_property(burst, "scale", Vector2(3.0, 3.0), 0.25)
		tw.parallel().tween_property(burst, "modulate:a", 0.0, 0.25)
		tw.tween_callback(burst.queue_free)
	queue_free()
