extends CharacterBody2D
signal enemy_destroyed(enemy)

## Enemy roster. Each entry has a "category" that drives visuals/behavior:
##   "meteor" — falls with a fire trail and heat shimmer
##   "ship"   — descends with a cool engine glow, no flames
const ENEMY_TYPES := [
	{
		"id": "small",
		"category": "meteor",
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
		"category": "meteor",
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
		"category": "meteor",
		"texture": "res://assets/png/normal meteor 2.png",
		"base_hp": 320,
		"hp_per_wave": 55,
		"base_speed": 26.0,
		"speed_per_wave": 0.9,
		"sprite_scale": 0.16,
		"collision": Vector2(48, 48),
		"weight": 0.85
	},
	{
		"id": "ufo",
		"category": "ship",
		"texture": "res://assets/sprites/spaceship_1.png",
		# The source PNG has a fake checkerboard "transparency" baked into its
		# pixels — strip it at load time until the asset itself is fixed.
		"strip_background": true,
		"base_hp": 140,
		"hp_per_wave": 30,
		"base_speed": 58.0,
		"speed_per_wave": 1.8,
		"sprite_scale": 0.06,
		"collision": Vector2(44, 44),
		"weight": 0.9
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
var type_id: String = "normal"
var category: String = "meteor"
var _spawn_x: float = 0.0
var _base_sprite_scale: Vector2 = Vector2.ONE
var _fall_trail: GPUParticles2D
var _ember_trail: GPUParticles2D
var _trail_category: String = ""
var _fall_time: float = 0.0

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var damage_text: Label = $DamageTextContainer/DamageText
@onready var blood_particle = preload("res://scenes/blood_particle.tscn")
@onready var kill_sound_scene = preload("res://scenes/bullet_hit_sound.tscn")
@onready var health_bar = $ProgressBar
@onready var sprite: Sprite2D = $Enemy2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

static func pick_enemy_type(rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for t in ENEMY_TYPES:
		total += float(t["weight"])
	var roll := rng.randf() * total
	var acc := 0.0
	for t in ENEMY_TYPES:
		acc += float(t["weight"])
		if roll <= acc:
			return t
	return ENEMY_TYPES[1]

static func get_enemy_type(id: String) -> Dictionary:
	for t in ENEMY_TYPES:
		if String(t["id"]) == id:
			return t
	return ENEMY_TYPES[1]

## Cache of textures that had their fake checkerboard background removed.
static var _clean_texture_cache := {}

## Removes a baked-in checkerboard/white background by flood-filling from the
## image borders and zeroing the alpha of every light, colorless pixel reached.
## Interior highlights survive because the fill can't cross the sprite outline.
static func _load_texture_without_background(path: String) -> Texture2D:
	if _clean_texture_cache.has(path):
		return _clean_texture_cache[path]
	var tex: Texture2D = load(path)
	if tex == null:
		return null
	var img: Image = tex.get_image()
	if img == null:
		return tex
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var visited := PackedByteArray()
	visited.resize(w * h)
	var stack: Array[Vector2i] = []
	for x in range(w):
		stack.append(Vector2i(x, 0))
		stack.append(Vector2i(x, h - 1))
	for y in range(h):
		stack.append(Vector2i(0, y))
		stack.append(Vector2i(w - 1, y))
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		var idx := p.y * w + p.x
		if visited[idx] == 1:
			continue
		visited[idx] = 1
		var c := img.get_pixelv(p)
		var lo: float = minf(c.r, minf(c.g, c.b))
		var hi: float = maxf(c.r, maxf(c.g, c.b))
		var is_background := c.a < 0.1 or (lo >= 0.62 and (hi - lo) <= 0.14)
		if not is_background:
			continue
		img.set_pixelv(p, Color(c.r, c.g, c.b, 0.0))
		stack.append(Vector2i(p.x + 1, p.y))
		stack.append(Vector2i(p.x - 1, p.y))
		stack.append(Vector2i(p.x, p.y + 1))
		stack.append(Vector2i(p.x, p.y - 1))
	var clean := ImageTexture.create_from_image(img)
	_clean_texture_cache[path] = clean
	return clean

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

func apply_enemy_type(type: Dictionary) -> void:
	type_id = String(type.get("id", "normal"))
	category = String(type.get("category", "meteor"))
	if sprite == null:
		sprite = get_node_or_null("Enemy2D") as Sprite2D
	if sprite:
		var path := String(type.get("texture", ""))
		if path != "" and ResourceLoader.exists(path):
			if bool(type.get("strip_background", false)):
				sprite.texture = _load_texture_without_background(path)
			else:
				sprite.texture = load(path)
		var s := float(type.get("sprite_scale", 0.12))
		_base_sprite_scale = Vector2(s, s)
		sprite.scale = _base_sprite_scale
		sprite.rotation = 0.0
		sprite.modulate = Color.WHITE
		if category == "meteor":
			# Rocky core near collision center; flame trails upward
			var tex: Texture2D = sprite.texture
			if tex:
				sprite.offset = Vector2(0, tex.get_height() * 0.18)
		else:
			sprite.offset = Vector2.ZERO
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
		apply_enemy_type(get_enemy_type("heavy"))
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
	# Rebuild trails if the category changed since they were created
	if _fall_trail != null and is_instance_valid(_fall_trail):
		if _trail_category == category:
			_update_trail_intensity()
			return
		_fall_trail.queue_free()
		_fall_trail = null
		if _ember_trail and is_instance_valid(_ember_trail):
			_ember_trail.queue_free()
		_ember_trail = null
	_trail_category = category

	if category == "ship":
		# Cool cyan engine wash — no flames on ships
		_fall_trail = _make_trail_particles(
			14,
			Color(0.45, 0.85, 1.0, 0.85),
			Color(0.15, 0.35, 1.0, 0.0),
			1.8,
			5.0,
			0.45
		)
		_fall_trail.z_index = -1
		add_child(_fall_trail)

		_ember_trail = _make_trail_particles(
			8,
			Color(0.85, 0.98, 1.0, 1.0),
			Color(0.3, 0.6, 1.0, 0.0),
			0.9,
			2.4,
			0.32
		)
		_ember_trail.z_index = -1
		add_child(_ember_trail)
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
	if category == "ship":
		# Ships hover: slow spin + gentle pulse, no heat tint
		var pulse: float = 1.0 + sin(_fall_time * 4.0) * 0.03
		sprite.scale = _base_sprite_scale * pulse
		sprite.rotation = _fall_time * 0.8
		if sprite.modulate.a >= 0.99:
			sprite.modulate = Color.WHITE
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
