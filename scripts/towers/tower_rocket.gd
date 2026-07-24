extends "res://scripts/towers/tower_base.gd"

## Sprite rocket launcher — quad-pod turret, explosive AoE rockets.

const V := preload("res://scripts/towers/tower_visuals.gd")
const ROCKET_SCENE := preload("res://scenes/towers/tower_rocket_projectile.tscn")
const TEX_LOADED_PATH := "res://assets/Rocket lancher tower/rocket launcher tower rockets loaded.png"
const TEX_UNLOADED_PATH := "res://assets/Rocket lancher tower/rocket launcher tower rockets unloaded.png"
const SFX_LAUNCH_PATH := "res://assets/sound_effects/rocket_launch.wav"

const CORE := Color(0.35, 0.9, 0.95)
const HOT := Color(0.55, 0.95, 1.0)

const TOWER_SCALE := 0.792
## Full-tower sprite; launch tubes point straight up.
const SPRITE_SCALE := 0.065 * TOWER_SCALE
const MUZZLE_TEX_FALLBACK := Vector2(0.0, -420.0)
const FOOT_MARGIN := 14.0
const SHADOW_RADIUS := 12.0 * TOWER_SCALE
const LABEL_Y := 20.0 * TOWER_SCALE
## Brief empty-tubes frame after a salvo, then reload art.
const RELOAD_FLASH := 0.28

const BLAST_RADIUS := 90.0

var _sprite: Sprite2D
var _tex_loaded: Texture2D
var _tex_unloaded: Texture2D
var _sprite_base_pos: Vector2 = Vector2.ZERO
var _muzzle: Node2D
var _aoe_mult: float = 1.0
var _idle_t: float = 0.0
var _salvo_alt: int = 0
var _reload_t: float = 0.0

func _ready() -> void:
	## Volley of 6 rockets every 3 seconds, spread across multiple targets.
	configure("rocket", "Rocket Launcher", CORE, 1440.0, 3.0, 38)
	bonus_shots = 5
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

	_tex_loaded = load(TEX_LOADED_PATH) as Texture2D
	_tex_unloaded = load(TEX_UNLOADED_PATH) as Texture2D
	var tex: Texture2D = _tex_loaded if _tex_loaded else _tex_unloaded

	_sprite = Sprite2D.new()
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	# Foot-pinned so loaded ↔ unloaded swaps don't jump.
	_sprite.centered = false
	_sprite_base_pos = Vector2(0.0, FOOT_MARGIN)
	_sprite.position = _sprite_base_pos
	_sprite.z_index = 1
	add_child(_sprite)

	_muzzle = Node2D.new()
	_sprite.add_child(_muzzle)
	_apply_tower_tex(tex)

	label = V.add_label(self, "ROCKET", CORE, LABEL_Y)

func _apply_tower_tex(tex: Texture2D) -> void:
	if _sprite == null or tex == null:
		return
	_sprite.texture = tex
	var tex_size: Vector2 = tex.get_size()
	_sprite.offset = Vector2(-tex_size.x * 0.5, -tex_size.y)
	# Foot at y=0; texture top (tube tips) is at y = -tex_h.
	if _muzzle:
		_muzzle.position = Vector2(0.0, -tex_size.y * 0.97)

func _process(delta: float) -> void:
	if not unlocked or sandbox_disabled:
		return
	_idle_t += delta
	if _reload_t > 0.0:
		_reload_t = maxf(0.0, _reload_t - delta)
		if _reload_t <= 0.0 and _tex_loaded:
			_apply_tower_tex(_tex_loaded)
	if _sprite:
		_sprite.position = _sprite_base_pos
	super._process(delta)

func _fire(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_salvo_alt += 1
	# Empty tubes for one flash per salvo, then reload art.
	if _reload_t <= 0.0 and _tex_unloaded:
		_apply_tower_tex(_tex_unloaded)
		_reload_t = RELOAD_FLASH
	# Spawn at the tube tips; small left/right barrel stagger only.
	var side: float = 1.0 if _salvo_alt % 2 == 0 else -1.0
	var origin: Vector2 = _muzzle.global_position if _muzzle else global_position
	origin += Vector2(side * 4.0, 0.0)
	var direction: Vector2 = origin.direction_to(target.global_position)
	if direction.length_squared() < 0.0001:
		direction = Vector2.UP
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
