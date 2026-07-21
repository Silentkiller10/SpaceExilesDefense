extends "res://scripts/towers/tower_base.gd"

## Sprite railgun — heavy base + rotating rail head, charge glow, massive beam.

const V := preload("res://scripts/towers/tower_visuals.gd")
const TEX_BASE_PATH := "res://assets/png/towers/railgun_base.png"
const TEX_HEAD_PATH := "res://assets/png/towers/railgun_head.png"
const SFX_SHOT_PATH := "res://assets/sound_effects/railgun_shot.wav"

const CORE := Color(0.45, 0.85, 1.0)
const HOT := Color(0.75, 0.95, 1.0)

const TOWER_SCALE := 0.792
## Base/head art is 1000x1000 (head barrel points along +X).
const BASE_SCALE := 0.154 * TOWER_SCALE
const HEAD_SCALE := 0.145 * TOWER_SCALE
const AIM_SPEED := 6.0
const HEAD_FACING_OFFSET := 0.0

## Tower-local alignment (screen space at default aim): X = left/right, Y = up/down.
@export_group("Head Alignment")
@export var pivot_offset := Vector2(0.0, -32.0)
@export var head_offset := Vector2(10.0, -4.0)
@export var muzzle_offset := Vector2(0.0, 0.0)

const BASE_Y_OFFSET := 6.0 * TOWER_SCALE
const SHADOW_RADIUS := 20.0 * TOWER_SCALE
const LABEL_Y := 24.0 * TOWER_SCALE
const BEAM_WIDTH_MULT := 1.0

var _base_sprite: Sprite2D
var _pivot: Node2D
var _head_sprite: Sprite2D
var _glow_sprite: Sprite2D
var _muzzle: Node2D
var _head_mount_tex: Vector2
var _muzzle_tex: Vector2
var _beams: Array[Line2D] = []
var _beam_tween: Tween
var _charge: float = 0.0
var _recoil: float = 0.0
var _idle_t: float = 0.0

func _ready() -> void:
	configure("railgun", "Railgun", CORE, 5000.0, 2.4, 520)
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
	add_child(_base_sprite)

	_pivot = Node2D.new()
	_pivot.position = _base_sprite.position + pivot_offset * TOWER_SCALE
	_pivot.z_index = 1
	add_child(_pivot)

	var head_size: Vector2 = tex_head.get_size() if tex_head else Vector2(1000, 1000)
	## Rear housing mount (left of art); muzzle at barrel tip (right).
	_head_mount_tex = Vector2(-head_size.x * 0.20, head_size.y * 0.06)
	_muzzle_tex = Vector2(head_size.x * 0.44, head_size.y * 0.0)

	_head_sprite = Sprite2D.new()
	_head_sprite.texture = tex_head
	_head_sprite.scale = Vector2(HEAD_SCALE, HEAD_SCALE)
	_head_sprite.position = -_head_mount_tex * HEAD_SCALE + _head_offset_pivot_local()
	_head_sprite.z_index = 1
	_pivot.add_child(_head_sprite)

	_glow_sprite = Sprite2D.new()
	_glow_sprite.texture = tex_head
	_glow_sprite.scale = _head_sprite.scale
	_glow_sprite.position = _head_sprite.position
	_glow_sprite.z_index = 0
	var glow_mat := CanvasItemMaterial.new()
	glow_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_sprite.material = glow_mat
	_glow_sprite.modulate = Color(CORE.r, CORE.g, CORE.b, 0.0)
	_pivot.add_child(_glow_sprite)
	_pivot.move_child(_glow_sprite, 0)

	_muzzle = Node2D.new()
	_muzzle.position = (_muzzle_tex - _head_mount_tex) * HEAD_SCALE + muzzle_offset * TOWER_SCALE
	_head_sprite.add_child(_muzzle)

	_beams = [
		V.make_beam(self, 18.0 * TOWER_SCALE * BEAM_WIDTH_MULT, Color(CORE.r, CORE.g, CORE.b, 0.1), 6),
		V.make_beam(self, 9.0 * TOWER_SCALE * BEAM_WIDTH_MULT, Color(CORE.r, CORE.g, CORE.b, 0.3), 7),
		V.make_beam(self, 3.5 * TOWER_SCALE * BEAM_WIDTH_MULT, Color(1.0, 1.0, 1.0, 0.95), 8)
	]
	label = V.add_label(self, "RAIL", CORE, LABEL_Y)
	_pivot.rotation = -PI / 2.0

func _process(delta: float) -> void:
	if not unlocked or sandbox_disabled:
		return
	_idle_t += delta
	_recoil = move_toward(_recoil, 0.0, delta * 35.0)
	var target := _find_target()
	_aim_pivot(target, delta)
	# Charge capacitors when a target is in range and nearly ready to fire
	if target and cd_left <= cooldown * 0.35:
		_charge = move_toward(_charge, 1.0, delta * 1.8)
	else:
		_charge = move_toward(_charge, 0.0, delta * 2.5)
	var pulse: float = 0.5 + 0.5 * sin(_idle_t * 4.0)
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

func _update_head_fx(pulse: float) -> void:
	if _head_sprite == null:
		return
	var kick: float = _recoil * 0.2
	var axis := Vector2.from_angle(_pivot.rotation)
	_head_sprite.position = -_head_mount_tex * HEAD_SCALE + _head_offset_pivot_local() - axis * kick
	if _glow_sprite:
		_glow_sprite.position = _head_sprite.position
		_glow_sprite.scale = _head_sprite.scale * (1.0 + pulse * 0.03 + _charge * 0.15)
		_glow_sprite.modulate.a = pulse * 0.18 + _charge * 0.55
	if _muzzle:
		_muzzle.position = (_muzzle_tex - _head_mount_tex) * HEAD_SCALE + muzzle_offset * TOWER_SCALE - axis * kick * 0.5
	var tint: float = 1.0 + pulse * 0.06 + _charge * 0.3
	_head_sprite.modulate = Color(tint, tint + 0.08, tint + 0.18, 1.0)

func _fire(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_hit_enemy(target, _scaled_damage(), 40.0)
	_charge = 0.0
	_recoil = 18.0
	_play_shot_sfx()
	var from_l: Vector2 = _muzzle.global_position - global_position if _muzzle else Vector2.ZERO
	var to_l: Vector2 = target.global_position - global_position
	V.show_beam_lines(_beams, from_l, to_l)
	if _beam_tween and _beam_tween.is_valid():
		_beam_tween.kill()
	_beam_tween = V.fade_lines(self, _beams, [0.18, 0.2, 0.22], func():
		for line in _beams:
			if is_instance_valid(line):
				line.visible = false
	)
	V.muzzle_sparks(_muzzle, CORE, HOT, 10)
	V.impact_burst(self, to_l, CORE, HOT)
	# Secondary impact rings along beam
	for t in [0.35, 0.65]:
		var pt := from_l.lerp(to_l, t)
		var ring := Line2D.new()
		ring.points = V.ellipse_points(Vector2(8, 8), 10)
		ring.position = pt
		ring.width = 2.0
		ring.default_color = Color(CORE.r, CORE.g, CORE.b, 0.5)
		ring.closed = true
		ring.z_index = 5
		add_child(ring)
		var tw := create_tween()
		tw.tween_property(ring, "scale", Vector2(3, 3), 0.15)
		tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.15)
		tw.tween_callback(ring.queue_free)

func _play_shot_sfx() -> void:
	var stream: AudioStream = load(SFX_SHOT_PATH) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "Towers"
	player.volume_db = -6.5
	player.pitch_scale = randf_range(0.95, 1.05)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
