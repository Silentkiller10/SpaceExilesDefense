extends Node2D
class_name PlayerJetpackBody

## Rear-view soldier (`assets/character.png`) with dual jetpack thruster fire.

const PATH := "res://assets/character.png"
const TARGET_HEIGHT := 145.0
## Texture-space offsets from sprite center → thruster nozzles (bottom of back pods).
const NOZZLE_TEX := Vector2(102.0, -55.0)

var animation: String = "idle"
var speed_scale: float = 1.0
var flip_h: bool = false:
	set(v):
		flip_h = v
		if _sprite:
			_sprite.flip_h = v
		if _thrust_root:
			_thrust_root.scale.x = -1.0 if v else 1.0

var _sprite: Sprite2D
var _thrust_root: Node2D
var _thrust_l: GPUParticles2D
var _thrust_r: GPUParticles2D
var _anim_t: float = 0.0
var _boosting: bool = false
var _thrust_configured: bool = false
var _base_y: float = 8.0

static func create() -> PlayerJetpackBody:
	var body := PlayerJetpackBody.new()
	body.name = "JetpackBody"
	body._build()
	return body

func play(anim_name: StringName) -> void:
	var name_str := String(anim_name)
	if name_str == animation:
		return
	animation = name_str
	_anim_t = 0.0
	_apply_thrust(animation == "walk")

func _process(delta: float) -> void:
	_anim_t += delta * speed_scale
	if _sprite == null:
		return
	var bob := 0.0
	if animation == "walk":
		bob = sin(_anim_t * 14.0) * 3.0
		_apply_thrust(true)
	else:
		bob = sin(_anim_t * 3.2) * 1.5
		_apply_thrust(false)
	var y := _base_y + bob
	_sprite.position.y = y
	if _thrust_root:
		_thrust_root.position.y = y

func _build() -> void:
	var tex: Texture2D = load(PATH)
	if tex == null:
		push_error("PlayerJetpackBody: missing %s" % PATH)
		return

	var s := TARGET_HEIGHT / float(tex.get_height())
	z_index = 1
	position = Vector2.ZERO

	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture = tex
	_sprite.centered = true
	_sprite.scale = Vector2(s, s)
	_sprite.position = Vector2(0.0, _base_y)
	_sprite.z_index = 1
	add_child(_sprite)

	_thrust_root = Node2D.new()
	_thrust_root.name = "Thrusters"
	# Rear-view: nozzles face the camera — draw fire in front of the armor.
	_thrust_root.z_index = 2
	_thrust_root.position = Vector2(0.0, _base_y)
	add_child(_thrust_root)

	var nozzle := Vector2(NOZZLE_TEX.x * s, NOZZLE_TEX.y * s)
	_thrust_l = _make_thruster(Vector2(-nozzle.x, nozzle.y))
	_thrust_r = _make_thruster(Vector2(nozzle.x, nozzle.y))
	_thrust_root.add_child(_thrust_l)
	_thrust_root.add_child(_thrust_r)
	_apply_thrust(false)
	play("idle")

func _make_thruster(pos: Vector2) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.position = pos
	p.amount = 16
	p.lifetime = 0.32
	p.preprocess = 0.2
	p.emitting = true
	p.local_coords = false
	p.visibility_rect = Rect2(-48, -16, 96, 110)

	var mat := ParticleProcessMaterial.new()
	mat.particle_flag_disable_z = true
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 2.2
	# Exhaust trails toward the feet (down the sprite) = upward thrust.
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 14.0
	mat.initial_velocity_min = 38.0
	mat.initial_velocity_max = 85.0
	mat.gravity = Vector3(0, 140, 0)
	mat.damping_min = 6.0
	mat.damping_max = 16.0
	mat.scale_min = 1.0
	mat.scale_max = 2.0

	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.55, 0.55))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	mat.scale_curve = scale_tex

	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.65, 1.0])
	grad.colors = PackedColorArray([
		Color(1.0, 0.98, 0.7, 1.0),
		Color(1.0, 0.55, 0.12, 0.95),
		Color(0.95, 0.2, 0.05, 0.55),
		Color(0.25, 0.05, 0.02, 0.0)
	])
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex

	p.process_material = mat
	p.texture = _soft_particle_tex()
	return p

func _soft_particle_tex() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var center := Vector2(7.5, 7.5)
	for y in 16:
		for x in 16:
			var d := Vector2(x, y).distance_to(center) / 7.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)

func _apply_thrust(moving: bool) -> void:
	if _thrust_configured and moving == _boosting:
		return
	_thrust_configured = true
	_boosting = moving
	for p in [_thrust_l, _thrust_r]:
		if p == null:
			continue
		p.amount = 26 if moving else 12
		p.speed_scale = 1.4 if moving else 0.8
		var mat := p.process_material as ParticleProcessMaterial
		if mat:
			mat.initial_velocity_min = 65.0 if moving else 32.0
			mat.initial_velocity_max = 125.0 if moving else 72.0
