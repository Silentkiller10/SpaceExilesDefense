extends "res://scripts/towers/tower_base.gd"

## Sprite laser turret — tripod base + rotating head art, beam VFX.

const V := preload("res://scripts/towers/tower_visuals.gd")
const TEX_BASE := preload("res://assets/png/towers/laser_base.png")
const TEX_HEAD := preload("res://assets/png/towers/laser_head.png")

const CORE := Color(0.35, 1.0, 0.55)
const HOT := Color(0.85, 1.0, 0.35)

const TOWER_SCALE := 0.72
const BASE_SCALE := 0.36 * TOWER_SCALE
const HEAD_SCALE := 0.28 * TOWER_SCALE
const AIM_SPEED := 16.0
## Head art points along +X at rotation 0.
const HEAD_FACING_OFFSET := 0.0
## Fine-tune beam origin on the barrel (head-local pixels).
const MUZZLE_OFFSET := Vector2(0.0, 40.0 * TOWER_SCALE)
const PIVOT_OFFSET := Vector2(4.0, -30.0) * TOWER_SCALE
const BASE_Y_OFFSET := 6.0 * TOWER_SCALE
const SHADOW_RADIUS := 18.0 * TOWER_SCALE
const LABEL_Y := 22.0 * TOWER_SCALE
const BEAM_WIDTH_MULT := 4.0

var _base_sprite: Sprite2D
var _pivot: Node2D
var _head_sprite: Sprite2D
var _glow_sprite: Sprite2D
var _muzzle: Node2D
var _head_mount_tex: Vector2
var _muzzle_tex: Vector2
var _beams: Array[Line2D] = []
var _beam_tween: Tween
var _idle_t: float = 0.0
var _charge: float = 0.0
var _recoil: float = 0.0

func _ready() -> void:
	configure("laser", "Laser", Color(1.0, 0.25, 0.55), 560.0, 0.04, 18)
	super._ready()

func unlock() -> void:
	super.unlock()
	V.play_unlock(self)

func _build_visual() -> void:
	V.add_shadow(self, SHADOW_RADIUS)

	body = Polygon2D.new()
	body.visible = false
	add_child(body)

	_base_sprite = Sprite2D.new()
	_base_sprite.texture = TEX_BASE
	_base_sprite.scale = Vector2(BASE_SCALE, BASE_SCALE)
	_base_sprite.position = Vector2(0, BASE_Y_OFFSET)
	_base_sprite.z_index = 0
	add_child(_base_sprite)

	_pivot = Node2D.new()
	_pivot.position = _base_sprite.position + PIVOT_OFFSET
	_pivot.z_index = 1
	add_child(_pivot)

	var head_size: Vector2 = TEX_HEAD.get_size()
	_head_mount_tex = Vector2(-head_size.x * 0.34, head_size.y * 0.06)
	_muzzle_tex = Vector2(head_size.x * 0.47, 0.0)

	_head_sprite = Sprite2D.new()
	_head_sprite.texture = TEX_HEAD
	_head_sprite.scale = Vector2(HEAD_SCALE, HEAD_SCALE)
	_head_sprite.position = -_head_mount_tex * HEAD_SCALE
	_head_sprite.z_index = 1
	_pivot.add_child(_head_sprite)

	_glow_sprite = Sprite2D.new()
	_glow_sprite.texture = TEX_HEAD
	_glow_sprite.scale = _head_sprite.scale
	_glow_sprite.position = _head_sprite.position
	_glow_sprite.z_index = 0
	_glow_sprite.modulate = Color(CORE.r, CORE.g, CORE.b, 0.0)
	_pivot.add_child(_glow_sprite)
	_pivot.move_child(_glow_sprite, 0)

	_muzzle = Node2D.new()
	_muzzle.position = (_muzzle_tex - _head_mount_tex) * HEAD_SCALE + MUZZLE_OFFSET
	_head_sprite.add_child(_muzzle)

	_beams = [
		V.make_beam(self, 22.0 * TOWER_SCALE * BEAM_WIDTH_MULT, Color(CORE.r, CORE.g, CORE.b, 0.12), 6),
		V.make_beam(self, 12.0 * TOWER_SCALE * BEAM_WIDTH_MULT, Color(CORE.r, CORE.g, CORE.b, 0.35), 7),
		V.make_beam(self, 5.0 * TOWER_SCALE * BEAM_WIDTH_MULT, Color(1.0, 1.0, 0.95, 0.95), 8)
	]
	label = V.add_label(self, "LASER", CORE, LABEL_Y)
	_pivot.rotation = -PI / 2.0

func _process(delta: float) -> void:
	if not unlocked:
		return
	_idle_t += delta
	_recoil = move_toward(_recoil, 0.0, delta * 85.0)
	_charge = move_toward(_charge, 0.0, delta * 3.5)
	var pulse: float = 0.5 + 0.5 * sin(_idle_t * 5.5)
	_aim_pivot(_find_target(), delta)
	_update_head_fx(pulse)
	super._process(delta)

func _aim_pivot(target: Node2D, delta: float) -> void:
	if _pivot == null:
		return
	var desired: float = -PI / 2.0
	if target:
		desired = _pivot.global_position.direction_to(target.global_position).angle()
		desired += HEAD_FACING_OFFSET
	_pivot.rotation = lerp_angle(_pivot.rotation, desired, 1.0 - exp(-AIM_SPEED * delta))

func _update_head_fx(pulse: float) -> void:
	if _head_sprite == null:
		return
	var kick: float = _recoil * 0.015
	var axis := Vector2.from_angle(_pivot.rotation)
	_head_sprite.position = -_head_mount_tex * HEAD_SCALE - axis * kick
	if _glow_sprite:
		_glow_sprite.position = _head_sprite.position
		_glow_sprite.scale = _head_sprite.scale * (1.0 + pulse * 0.04 + _charge * 0.12)
		_glow_sprite.modulate.a = pulse * 0.22 + _charge * 0.45
	if _muzzle:
		_muzzle.position = (_muzzle_tex - _head_mount_tex) * HEAD_SCALE + MUZZLE_OFFSET - axis * kick * 0.5
	var tint: float = 1.0 + pulse * 0.08 + _charge * 0.25
	_head_sprite.modulate = Color(tint, tint + 0.15, tint + 0.1, 1.0)

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
