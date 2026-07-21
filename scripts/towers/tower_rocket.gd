extends "res://scripts/towers/tower_base.gd"

## Sprite rocket launcher — quad-pod turret, explosive AoE rockets.

const V := preload("res://scripts/towers/tower_visuals.gd")
const ROCKET_SCENE := preload("res://scenes/towers/tower_rocket_projectile.tscn")
const TEX_PATH := "res://assets/png/towers/rocket_launcher.png"
const SFX_LAUNCH_PATH := "res://assets/sound_effects/rocket_launch.wav"

const CORE := Color(0.4, 0.75, 1.0)
const HOT := Color(0.7, 0.9, 1.0)

const TOWER_SCALE := 0.792
## Art is 841x1024, barrels point straight up.
const SPRITE_SCALE := 0.132 * TOWER_SCALE
const NATURAL_ANGLE := -PI / 2.0
## Barrel cluster tip in texture pixels from center.
const MUZZLE_TEX := Vector2(0.0, -420.0)
## How far the sprite's bottom edge sits below the slot position,
## matching the platform foot of the procedural towers.
const FOOT_MARGIN := 14.0
const SHADOW_RADIUS := 18.0 * TOWER_SCALE
const LABEL_Y := 26.0 * TOWER_SCALE

const BLAST_RADIUS := 90.0

var _sprite: Sprite2D
var _sprite_base_pos: Vector2 = Vector2.ZERO
var _muzzle: Node2D
var _aoe_mult: float = 1.0
var _recoil: float = 0.0
var _idle_t: float = 0.0
var _salvo_alt: int = 0

func _ready() -> void:
	## Volley of 4 rockets every 3 seconds, spread across multiple targets.
	configure("rocket", "Rocket Launcher", CORE, 1440.0, 3.0, 38)
	bonus_shots = 3
	super._ready()

func unlock() -> void:
	super.unlock()
	V.play_unlock(self)

func apply_aoe_mult(mult_add: float) -> void:
	_aoe_mult *= (1.0 + mult_add)

func _build_visual() -> void:
	V.add_shadow(self, SHADOW_RADIUS)

	body = Polygon2D.new()
	body.visible = false
	add_child(body)

	var tex: Texture2D = load(TEX_PATH) as Texture2D

	_sprite = Sprite2D.new()
	_sprite.texture = tex
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	# Lift the centered sprite so its bottom edge rests on the slot line.
	var tex_h: float = tex.get_size().y if tex else 1024.0
	_sprite_base_pos = Vector2(0.0, FOOT_MARGIN - tex_h * 0.5 * SPRITE_SCALE)
	_sprite.position = _sprite_base_pos
	_sprite.z_index = 1
	add_child(_sprite)

	# Child of the scaled sprite, so its position is in texture pixels.
	_muzzle = Node2D.new()
	_muzzle.position = MUZZLE_TEX
	_sprite.add_child(_muzzle)

	label = V.add_label(self, "ROCKET", CORE, LABEL_Y)

func _process(delta: float) -> void:
	if not unlocked or sandbox_disabled:
		return
	_idle_t += delta
	_recoil = move_toward(_recoil, 0.0, delta * 30.0)
	# Static turret — only a recoil kick along the barrel axis.
	if _sprite:
		_sprite.position = _sprite_base_pos - Vector2.from_angle(NATURAL_ANGLE) * _recoil * 0.35
	super._process(delta)

func _fire(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_recoil = 6.0
	_salvo_alt += 1
	var origin: Vector2 = _muzzle.global_position if _muzzle else global_position
	var direction: Vector2 = origin.direction_to(target.global_position)
	## Alternate barrels: tiny lateral offset + spread so salvos read as separate tubes
	var side: float = 1.0 if _salvo_alt % 2 == 0 else -1.0
	origin += direction.orthogonal() * side * 5.0
	direction = direction.rotated(deg_to_rad(randf_range(-2.0, 2.0)))

	var world: Node = get_parent().get_parent() if get_parent() else get_tree().current_scene
	if world == null:
		world = get_tree().current_scene
	var rocket = ROCKET_SCENE.instantiate()
	world.add_child(rocket)
	if rocket.has_method("launch"):
		rocket.launch(origin, direction, target, _scaled_damage(), BLAST_RADIUS * _aoe_mult, range_px * 1.2)
	_play_launch_sfx()
	V.muzzle_sparks(_muzzle, CORE, HOT, 5)

func _play_launch_sfx() -> void:
	var stream: AudioStream = load(SFX_LAUNCH_PATH) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "Towers"
	player.volume_db = -6.0
	player.pitch_scale = randf_range(0.92, 1.08)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
