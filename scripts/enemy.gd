extends CharacterBody2D
signal enemy_destroyed(enemy)

## Three meteor variants — small (fast/fragile), normal (balanced), heavy (tanky/slow).
const METEOR_TYPES := [
	{
		"id": "small",
		"texture": "res://assets/png/small meteor.png",
		"base_hp": 90,
		"hp_per_wave": 22,
		"base_speed": 78.0,
		"speed_per_wave": 2.2,
		"sprite_scale": 0.28,
		"collision": Vector2(28, 28),
		"weight": 1.15
	},
	{
		"id": "normal",
		"texture": "res://assets/png/normal meteor.png",
		"base_hp": 180,
		"hp_per_wave": 35,
		"base_speed": 42.0,
		"speed_per_wave": 1.5,
		"sprite_scale": 0.11,
		"collision": Vector2(40, 40),
		"weight": 1.0
	},
	{
		"id": "heavy",
		"texture": "res://assets/png/normal meteor 2.png",
		"base_hp": 320,
		"hp_per_wave": 55,
		"base_speed": 26.0,
		"speed_per_wave": 0.9,
		"sprite_scale": 0.16,
		"collision": Vector2(48, 48),
		"weight": 0.85
	},
]

@export var health: int = 180
@export var speed: float = 40.0

var player: CharacterBody2D
var fortress: Node2D
var is_dying: bool = false
var is_boss: bool = false
var stun_timer: float = 0.0
var burn_timer: float = 0.0
var burn_dps: float = 0.0
var pull_force: Vector2 = Vector2.ZERO
var meteor_id: String = "normal"
var _spawn_x: float = 0.0
var _base_sprite_scale: Vector2 = Vector2.ONE
var _fall_trail: GPUParticles2D
var _ember_trail: GPUParticles2D
var _fall_time: float = 0.0

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var damage_text: Label = $DamageTextContainer/DamageText
@onready var blood_particle = preload("res://scenes/blood_particle.tscn")
@onready var kill_sound_scene = preload("res://scenes/bullet_hit_sound.tscn")
@onready var health_bar = $ProgressBar
@onready var sprite: Sprite2D = $Enemy2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

static func pick_meteor_type(rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for t in METEOR_TYPES:
		total += float(t["weight"])
	var roll := rng.randf() * total
	var acc := 0.0
	for t in METEOR_TYPES:
		acc += float(t["weight"])
		if roll <= acc:
			return t
	return METEOR_TYPES[1]

static func get_meteor_type(id: String) -> Dictionary:
	for t in METEOR_TYPES:
		if String(t["id"]) == id:
			return t
	return METEOR_TYPES[1]

func _ready():
	damage_text.visible = false
	if health_bar:
		health_bar.max_value = health
		health_bar.value = health
	if sprite:
		_base_sprite_scale = sprite.scale
	add_to_group("enemy")
	# Disable old walk squash animation — meteors use fall VFX instead
	if animation_tree:
		animation_tree.active = false

func setup(pos: Vector2, _player: CharacterBody2D):
	setup_descent(pos, _player, null, health, speed)

func setup_descent(pos: Vector2, _player: CharacterBody2D, _fortress: Node2D, hp: int, spd: float) -> void:
	position = pos
	_spawn_x = pos.x
	player = _player
	fortress = _fortress
	health = hp
	speed = spd
	if health_bar:
		health_bar.max_value = health
		health_bar.value = health
	_ensure_fall_vfx()

func apply_meteor_type(type: Dictionary) -> void:
	meteor_id = String(type.get("id", "normal"))
	if sprite == null:
		sprite = get_node_or_null("Enemy2D") as Sprite2D
	if sprite:
		var path := String(type.get("texture", ""))
		if path != "" and ResourceLoader.exists(path):
			sprite.texture = load(path)
		var s := float(type.get("sprite_scale", 0.12))
		_base_sprite_scale = Vector2(s, s)
		sprite.scale = _base_sprite_scale
		sprite.rotation = 0.0
		# Rocky core near collision center; flame trails upward
		var tex: Texture2D = sprite.texture
		if tex:
			sprite.offset = Vector2(0, tex.get_height() * 0.18)
	if collision_shape == null:
		collision_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision_shape and collision_shape.shape is RectangleShape2D:
		var sz: Vector2 = type.get("collision", Vector2(36, 36))
		var shape := (collision_shape.shape as RectangleShape2D).duplicate() as RectangleShape2D
		shape.size = sz
		collision_shape.shape = shape
	_ensure_fall_vfx()

func set_as_boss(value: bool) -> void:
	is_boss = value
	if value:
		apply_meteor_type(get_meteor_type("heavy"))
		scale = Vector2(2.4, 2.4)

func apply_stun(duration: float) -> void:
	stun_timer = max(stun_timer, duration)

func apply_burn(duration: float, dps: float) -> void:
	burn_timer = max(burn_timer, duration)
	burn_dps = max(burn_dps, dps)

func apply_pull(force: Vector2) -> void:
	# Vertical only — never slide sideways
	pull_force.y += force.y

func _ensure_fall_vfx() -> void:
	if _fall_trail != null and is_instance_valid(_fall_trail):
		_update_trail_intensity()
		return

	_fall_trail = _make_trail_particles(
		18,
		Color(1.0, 0.55, 0.15, 0.9),
		Color(1.0, 0.2, 0.05, 0.0),
		2.5,
		7.0,
		0.5
	)
	_fall_trail.z_index = -1
	add_child(_fall_trail)

	_ember_trail = _make_trail_particles(
		12,
		Color(1.0, 0.92, 0.45, 1.0),
		Color(1.0, 0.35, 0.0, 0.0),
		1.2,
		3.2,
		0.38
	)
	_ember_trail.z_index = -1
	add_child(_ember_trail)
	_update_trail_intensity()

func _make_trail_particles(amount: int, color_a: Color, color_b: Color, scale_min: float, scale_max: float, lifetime: float) -> GPUParticles2D:
	var particles := GPUParticles2D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.preprocess = 0.25
	particles.emitting = true
	particles.local_coords = false
	particles.position = Vector2(0, -22)

	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 7.0
	# Trail streams upward while the meteor falls down
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 16.0
	mat.initial_velocity_min = 55.0
	mat.initial_velocity_max = 110.0
	mat.gravity = Vector3(0, -40, 0)
	mat.damping_min = 10.0
	mat.damping_max = 22.0
	mat.scale_min = scale_min
	mat.scale_max = scale_max

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	mat.scale_curve = scale_tex

	var grad := Gradient.new()
	grad.colors = PackedColorArray([color_a, color_b])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex

	particles.process_material = mat
	return particles

func _update_trail_intensity() -> void:
	var speed_factor: float = clampf(speed / 50.0, 0.75, 2.4)
	if _fall_trail:
		_fall_trail.amount = clampi(int(16.0 * speed_factor), 10, 36)
		_fall_trail.speed_scale = speed_factor
	if _ember_trail:
		_ember_trail.amount = clampi(int(10.0 * speed_factor), 6, 24)
		_ember_trail.speed_scale = speed_factor

func _physics_process(delta):
	if is_dying:
		return

	if stun_timer > 0.0:
		stun_timer -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		_process_burn(delta)
		return

	_fall_time += delta

	# Strict vertical fall — lock X so nothing can push sideways
	velocity = Vector2(0.0, speed + pull_force.y)
	pull_force = Vector2(0.0, lerpf(pull_force.y, 0.0, 8.0 * delta))
	move_and_slide()
	global_position.x = _spawn_x
	velocity.x = 0.0

	_update_fall_visual()
	_process_burn(delta)

	var leak_y := 560.0
	if fortress and fortress.has_method("get_leak_y"):
		leak_y = fortress.get_leak_y()
	if global_position.y >= leak_y:
		_leak_into_fortress()

func _update_fall_visual() -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	# Flame stays upright; stretch + heat shimmer sell the fall
	var stretch: float = 1.0 + clampf(speed / 220.0, 0.0, 0.2)
	var shimmer: float = 1.0 + sin(_fall_time * 14.0) * 0.035
	sprite.scale = Vector2(_base_sprite_scale.x * shimmer, _base_sprite_scale.y * stretch * shimmer)
	sprite.rotation = 0.0
	var heat: float = 0.9 + 0.1 * (0.5 + 0.5 * sin(_fall_time * 10.0))
	if sprite.modulate.a >= 0.99:
		sprite.modulate = Color(1.0, heat, heat * 0.9, 1.0)

func _process_burn(delta: float) -> void:
	if burn_timer <= 0.0:
		return
	burn_timer -= delta
	var dmg := int(burn_dps * delta)
	if dmg > 0:
		health -= dmg
		if health_bar:
			health_bar.value = health
		if health <= 0:
			die()

func _leak_into_fortress() -> void:
	if fortress and fortress.has_method("take_damage"):
		var dmg := 25 if is_boss else 10
		var mult: float = 1.0
		if "leak_damage_mult" in fortress:
			mult = float(fortress.leak_damage_mult)
		dmg = maxi(1, int(round(float(dmg) * mult)))
		fortress.take_damage(dmg)
	is_dying = true
	queue_free()

## Tower / AoE damage — sync, no blood spam (safe for high fire-rate lasers).
func take_damage(amount: int, knockback: float = 0.0, apply_ignition: bool = false) -> void:
	if is_dying:
		return
	health -= amount
	if health_bar:
		health_bar.value = health
	_show_hit_flash(amount)
	if knockback > 0.0:
		pull_force.y -= knockback * 0.35
	if apply_ignition:
		apply_burn(2.5, 18.0)
	if health <= 0:
		die()

func get_hit(damage: int, bullet_trans: Transform2D, knockback: float = 0.0, apply_ignition: bool = false):
	if is_dying:
		return

	health -= damage

	if health_bar:
		health_bar.value = health

	_show_hit_flash(damage)

	# Knockback only slows/pushes vertically — never sideways
	if knockback > 0.0:
		pull_force.y -= knockback * 0.35

	if apply_ignition:
		apply_burn(2.5, 18.0)

	# Death before VFX so a particle error can never leave a zombie meteor.
	if health <= 0:
		die()
		_spawn_blood(bullet_trans)
		return

	_spawn_blood(bullet_trans)
	await get_tree().create_timer(0.1).timeout
	if is_instance_valid(self) and not is_dying:
		if sprite:
			sprite.modulate = Color.WHITE

func _show_hit_flash(amount: int) -> void:
	if damage_text:
		damage_text.text = str(amount)
		damage_text.visible = true
	if sprite:
		sprite.modulate = Color(1.6, 1.35, 1.1)

func _spawn_blood(bullet_trans: Transform2D) -> void:
	if blood_particle == null or not is_inside_tree():
		return
	var fx = blood_particle.instantiate()
	# Spawn at the meteor, oriented by the shot transform.
	var spawn_at := global_position
	get_tree().root.add_child(fx)
	if fx.has_method("setup"):
		var t := bullet_trans
		t.origin = spawn_at
		fx.setup(t)
	else:
		fx.global_position = spawn_at

func die():
	if is_dying:
		return
	is_dying = true
	_play_kill_sound()
	if _fall_trail:
		_fall_trail.emitting = false
	if _ember_trail:
		_ember_trail.emitting = false
	if health_bar:
		health_bar.visible = false
	if damage_text:
		damage_text.visible = false
	if sprite and is_inside_tree():
		var tw := create_tween()
		tw.tween_property(sprite, "modulate:a", 0.0, 0.3)
		tw.parallel().tween_property(sprite, "scale", sprite.scale * 1.35, 0.3)
	if is_inside_tree():
		await get_tree().create_timer(0.35).timeout
	destroy()

func _play_kill_sound() -> void:
	var scene = get_tree().current_scene
	if scene == null or kill_sound_scene == null:
		return
	var sfx = kill_sound_scene.instantiate()
	scene.add_child(sfx)
	if sfx.has_method("play"):
		sfx.play()

func destroy():
	enemy_destroyed.emit(self)
	queue_free()
