extends "res://scripts/towers/tower_base.gd"

## Sprite laser turret — tripod base + rotating head art, beam VFX.

const V := preload("res://scripts/towers/tower_visuals.gd")
const TEX_BASE_PATH := "res://assets/Laser Tower/Laser Tower Base.png"
const TEX_HEAD_PATH := "res://assets/Laser Tower/Laser Tower Head.png"
const SFX_LASER_PATH := "res://assets/sound_effects/tower_laser.wav"

const CORE := Color(0.35, 1.0, 0.45)
const HOT := Color(0.75, 1.0, 0.35)
## Soft dark tint over base/head art.
const OVERLAY := Color(0.78, 0.78, 0.80, 1.0)

## 40% smaller than the previous on-field size.
const TOWER_SCALE := 0.792 * 0.6
## LR-94 art is high-res; keep on-field size close to other towers.
const BASE_SCALE := 0.13 * TOWER_SCALE
const HEAD_SCALE := 0.12 * TOWER_SCALE
const AIM_SPEED := 16.0
## Head barrel points along +X at rotation 0.
const HEAD_FACING_OFFSET := 0.0

## Tower-local alignment (screen space at default aim): X = left/right, Y = up/down.
@export_group("Head Alignment")
@export var pivot_offset := Vector2(0.0, -56.0)
@export var head_offset := Vector2(0.0, -14.0)
@export var muzzle_offset := Vector2(0.0, 0.0)

const BASE_Y_OFFSET := 6.0 * TOWER_SCALE
const SHADOW_RADIUS := 18.0 * TOWER_SCALE
const LABEL_Y := 22.0 * TOWER_SCALE
const BEAM_WIDTH_MULT := 4.0

var _base_sprite: Sprite2D
var _pivot: Node2D
var _head_sprite: Sprite2D
var _muzzle: Node2D
var _head_mount_tex: Vector2
var _muzzle_tex: Vector2
var _beams: Array[Line2D] = []
var _beam_tween: Tween
var _idle_t: float = 0.0
var _charge: float = 0.0
var _recoil: float = 0.0
var _sfx_player: AudioStreamPlayer
var _sfx_cd: float = 0.0
const SFX_INTERVAL := 0.12

func _ready() -> void:
	configure("laser", "Laser", CORE, 560.0, 0.04, 18)
	super._ready()

func unlock() -> void:
	super.unlock()
	V.play_unlock(self)

func _build_visual() -> void:
	V.add_shadow(self, SHADOW_RADIUS)

	body = Polygon2D.new()
	body.visible = false
	add_child(body)

	var tex_base: Texture2D = load(TEX_BASE_PATH) as Texture2D
	var tex_head: Texture2D = load(TEX_HEAD_PATH) as Texture2D

	_base_sprite = Sprite2D.new()
	_base_sprite.texture = tex_base
	_base_sprite.scale = Vector2(BASE_SCALE, BASE_SCALE)
	_base_sprite.position = Vector2(0, BASE_Y_OFFSET)
	_base_sprite.z_index = 0
	_base_sprite.modulate = OVERLAY
	add_child(_base_sprite)

	_pivot = Node2D.new()
	_pivot.position = _base_sprite.position + pivot_offset * TOWER_SCALE
	_pivot.z_index = 1
	add_child(_pivot)

	var head_size: Vector2 = tex_head.get_size() if tex_head else Vector2(1024, 1024)
	# Rear chassis mount (left); muzzle at barrel tip (right).
	_head_mount_tex = Vector2(-head_size.x * 0.28, head_size.y * 0.02)
	_muzzle_tex = Vector2(head_size.x * 0.45, 0.0)

	_head_sprite = Sprite2D.new()
	_head_sprite.texture = tex_head
	_head_sprite.scale = Vector2(HEAD_SCALE, HEAD_SCALE)
	_head_sprite.position = -_head_mount_tex * HEAD_SCALE + _head_offset_pivot_local()
	_head_sprite.z_index = 1
	_head_sprite.modulate = OVERLAY
	_pivot.add_child(_head_sprite)

	_muzzle = Node2D.new()
	_muzzle.position = (_muzzle_tex - _head_mount_tex) * HEAD_SCALE + muzzle_offset * TOWER_SCALE
	_head_sprite.add_child(_muzzle)

	# Draw beams behind the tower sprites (shadow is -2; base/head are 0/1).
	_beams = [
		V.make_beam(self, 22.0 * TOWER_SCALE * BEAM_WIDTH_MULT, Color(CORE.r, CORE.g, CORE.b, 0.12), -1),
		V.make_beam(self, 12.0 * TOWER_SCALE * BEAM_WIDTH_MULT, Color(CORE.r, CORE.g, CORE.b, 0.35), -1),
		V.make_beam(self, 5.0 * TOWER_SCALE * BEAM_WIDTH_MULT, Color(1.0, 1.0, 0.95, 0.95), -1)
	]
	label = V.add_label(self, "LASER", CORE, LABEL_Y)
	_pivot.rotation = -PI / 2.0

func _process(delta: float) -> void:
	if not unlocked or sandbox_disabled:
		return
	_idle_t += delta
	_sfx_cd = maxf(0.0, _sfx_cd - delta)
	_recoil = move_toward(_recoil, 0.0, delta * 85.0)
	_charge = move_toward(_charge, 0.0, delta * 3.5)
	var pulse: float = 0.5 + 0.5 * sin(_idle_t * 5.5)
	_aim_pivot(_find_target(), delta)
	_update_head_fx(pulse)
	super._process(delta)

func _head_offset_pivot_local() -> Vector2:
	if _pivot == null:
		return head_offset * TOWER_SCALE
	return (head_offset * TOWER_SCALE).rotated(-_pivot.rotation)

func _aim_pivot(target: Node2D, delta: float) -> void:
	if _pivot == null:
		return
	var desired: float = -PI / 2.0
	if target:
		desired = _pivot.global_position.direction_to(target.global_position).angle()
		desired += HEAD_FACING_OFFSET
	_pivot.rotation = lerp_angle(_pivot.rotation, desired, 1.0 - exp(-AIM_SPEED * delta))

func _update_head_fx(_pulse: float) -> void:
	if _head_sprite == null:
		return
	var kick: float = _recoil * 0.015
	var axis := Vector2.from_angle(_pivot.rotation)
	_head_sprite.position = -_head_mount_tex * HEAD_SCALE + _head_offset_pivot_local() - axis * kick
	_head_sprite.modulate = OVERLAY
	if _muzzle:
		_muzzle.position = (_muzzle_tex - _head_mount_tex) * HEAD_SCALE + muzzle_offset * TOWER_SCALE - axis * kick * 0.5

func _fire(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_hit_enemy(target, _scaled_damage())
	_charge = 1.0
	_recoil = 7.0
	var from_l: Vector2 = _muzzle.global_position - global_position if _muzzle else Vector2.ZERO
	var to_l: Vector2 = target.global_position - global_position
	V.show_beam_lines(_beams, from_l, to_l)
	if _beam_tween and _beam_tween.is_valid():
		_beam_tween.kill()
	_beam_tween = V.fade_lines(self, _beams, [0.08, 0.1, 0.12], func():
		for line in _beams:
			if is_instance_valid(line):
				line.visible = false
	)
	V.muzzle_sparks(_muzzle, CORE, HOT)
	V.impact_burst(self, to_l, CORE, HOT)
	_play_laser_sfx()

func _play_laser_sfx() -> void:
	if _sfx_cd > 0.0:
		return
	_sfx_cd = SFX_INTERVAL
	if _sfx_player == null:
		var stream: AudioStream = load(SFX_LASER_PATH) as AudioStream
		if stream == null:
			return
		_sfx_player = AudioStreamPlayer.new()
		_sfx_player.stream = stream
		_sfx_player.bus = "Towers"
		_sfx_player.volume_db = -10.0
		add_child(_sfx_player)
	_sfx_player.pitch_scale = randf_range(0.96, 1.06)
	_sfx_player.play()
