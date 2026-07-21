extends "res://scripts/towers/tower_base.gd"

## Sprite cannon — heavy base + rotating gun head, arcing shell, shockwave blast.

const V := preload("res://scripts/towers/tower_visuals.gd")
const TEX_BASE_PATH := "res://assets/png/towers/cannon_base.png"
const TEX_HEAD_PATH := "res://assets/png/towers/cannon_head.png"
const SFX_SHOT_PATH := "res://assets/sound_effects/cannon_shot.wav"

const CORE := Color(0.35, 1.0, 0.45)
const HOT := Color(0.75, 1.0, 0.35)

const TOWER_SCALE := 0.792
## Base/head art is 1000x1000 (head barrel points along +X).
const BASE_SCALE := 0.154 * TOWER_SCALE
const HEAD_SCALE := 0.145 * TOWER_SCALE
const AIM_SPEED := 8.0
const HEAD_FACING_OFFSET := 0.0

## Tower-local alignment (screen space at default aim): X = left/right, Y = up/down.
@export_group("Head Alignment")
@export var pivot_offset := Vector2(0.0, -32.0)
@export var head_offset := Vector2(0.0, 10.0)
@export var muzzle_offset := Vector2(0.0, 0.0)

const BASE_Y_OFFSET := 6.0 * TOWER_SCALE
const SHADOW_RADIUS := 20.0 * TOWER_SCALE
const LABEL_Y := 24.0 * TOWER_SCALE

var _base_sprite: Sprite2D
var _pivot: Node2D
var _head_sprite: Sprite2D
var _glow_sprite: Sprite2D
var _muzzle: Node2D
var _head_mount_tex: Vector2
var _muzzle_tex: Vector2
var _recoil: float = 0.0
var _idle_t: float = 0.0
var _charge: float = 0.0

func _ready() -> void:
	configure("cannon", "Cannon", CORE, 520.0, 1.1, 120)
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
	## Rear pod mount (left of art); muzzle at barrel tip (right).
	_head_mount_tex = Vector2(-head_size.x * 0.22, head_size.y * 0.04)
	_muzzle_tex = Vector2(head_size.x * 0.42, head_size.y * 0.0)

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

	label = V.add_label(self, "CANNON", CORE, LABEL_Y)
	_pivot.rotation = -PI / 2.0

func _process(delta: float) -> void:
	if not unlocked or sandbox_disabled:
		return
	_idle_t += delta
	_recoil = move_toward(_recoil, 0.0, delta * 45.0)
	_charge = move_toward(_charge, 0.0, delta * 2.0)
	_aim_pivot(_find_target(), delta)
	var pulse: float = 0.5 + 0.5 * sin(_idle_t * 3.5)
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
	var kick: float = _recoil * 0.15
	var axis := Vector2.from_angle(_pivot.rotation)
	_head_sprite.position = -_head_mount_tex * HEAD_SCALE + _head_offset_pivot_local() - axis * kick
	if _glow_sprite:
		_glow_sprite.position = _head_sprite.position
		_glow_sprite.scale = _head_sprite.scale * (1.0 + pulse * 0.03 + _charge * 0.12)
		_glow_sprite.modulate.a = pulse * 0.16 + _charge * 0.5
	if _muzzle:
		_muzzle.position = (_muzzle_tex - _head_mount_tex) * HEAD_SCALE + muzzle_offset * TOWER_SCALE - axis * kick * 0.5
	var tint: float = 1.0 + pulse * 0.05 + _charge * 0.2
	_head_sprite.modulate = Color(tint, tint + 0.12, tint + 0.05, 1.0)

func _fire(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var impact: Vector2 = target.global_position
	var blast_r := 180.0
	_recoil = 14.0
	_charge = 1.0
	_play_shot_sfx()
	_spawn_shell_arc(impact)
	_spawn_blast(impact, blast_r)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or enemy.get("is_dying") == true:
			continue
		if impact.distance_to(enemy.global_position) <= blast_r:
			_hit_enemy(enemy, _scaled_damage(), 140.0)

func _play_shot_sfx() -> void:
	var stream: AudioStream = load(SFX_SHOT_PATH) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "Towers"
	player.volume_db = -4.0
	player.pitch_scale = randf_range(0.94, 1.06)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _spawn_shell_arc(impact: Vector2) -> void:
	## Layered energy shell: soft glow + plasma orb + hot core + trailing sparks.
	var shell := Node2D.new()
	shell.z_index = 8
	add_child(shell)

	var glow := Polygon2D.new()
	glow.polygon = V.ellipse_points(Vector2(16, 16), 16)
	glow.color = Color(CORE.r, CORE.g, CORE.b, 0.22)
	shell.add_child(glow)

	var plasma := Polygon2D.new()
	plasma.polygon = V.ellipse_points(Vector2(10, 10), 14)
	plasma.color = Color(CORE.r, CORE.g, CORE.b, 0.85)
	shell.add_child(plasma)

	var rim := Line2D.new()
	rim.points = V.ellipse_points(Vector2(10, 10), 16)
	rim.width = 2.0
	rim.default_color = Color(HOT.r, HOT.g, HOT.b, 0.75)
	rim.closed = true
	shell.add_child(rim)

	var core := Polygon2D.new()
	core.polygon = V.ellipse_points(Vector2(4.5, 4.5), 10)
	core.color = Color(1.0, 1.0, 0.85, 0.95)
	shell.add_child(core)

	var sparks: Array[Polygon2D] = []
	for i in 5:
		var spark := Polygon2D.new()
		spark.polygon = V.scale_poly(V.hex_points(1.6, 4), Vector2(1, 1))
		spark.color = HOT if i % 2 == 0 else CORE
		spark.modulate.a = 0.7
		shell.add_child(spark)
		sparks.append(spark)

	var from_l: Vector2 = _muzzle.global_position - global_position if _muzzle else Vector2.ZERO
	var to_l: Vector2 = impact - global_position
	shell.position = from_l
	var mid := (from_l + to_l) * 0.5 + Vector2(randf_range(-20, 20), -80)
	var prev_pos := from_l
	var pulse_t := 0.0
	var tw := create_tween()
	tw.tween_method(func(t: float):
		if not is_instance_valid(shell):
			return
		var a := 1.0 - t
		var pos := a * a * from_l + 2.0 * a * t * mid + t * t * to_l
		var delta_pos := pos - prev_pos
		shell.position = pos
		pulse_t += 0.35
		var pulse: float = 1.0 + 0.12 * sin(pulse_t * 10.0)
		glow.scale = Vector2(pulse, pulse)
		plasma.scale = Vector2(0.95 + 0.08 * sin(pulse_t * 14.0), 0.95 + 0.08 * sin(pulse_t * 14.0))
		core.scale = Vector2(pulse * 0.9, pulse * 0.9)
		# Trail sparks lag behind the motion
		if delta_pos.length_squared() > 0.01:
			var back := -delta_pos.normalized()
			for i in sparks.size():
				var s: Polygon2D = sparks[i]
				if not is_instance_valid(s):
					continue
				var lag := 6.0 + float(i) * 4.5
				s.position = back * lag + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
				s.modulate.a = 0.75 - float(i) * 0.12
				s.scale = Vector2.ONE * (1.0 - float(i) * 0.12)
		prev_pos = pos
	, 0.0, 1.0, 0.30).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(shell.queue_free)
	V.muzzle_sparks(_muzzle, CORE, HOT, 8)

func _spawn_blast(world_pos: Vector2, radius: float) -> void:
	var local := world_pos - global_position
	var core := Polygon2D.new()
	core.polygon = V.ellipse_points(Vector2(radius * 0.18, radius * 0.18), 20)
	core.position = local
	core.color = Color(HOT.r, HOT.g, HOT.b, 0.75)
	core.z_index = 7
	add_child(core)
	for i in 3:
		var ring := Line2D.new()
		ring.points = V.ellipse_points(Vector2(radius * 0.15, radius * 0.15), 24)
		ring.position = local
		ring.width = 3.0 - i * 0.6
		ring.default_color = Color(CORE.r, CORE.g, CORE.b, 0.65 - i * 0.15)
		ring.closed = true
		ring.z_index = 6
		add_child(ring)
		var delay: float = float(i) * 0.04
		var tw := create_tween()
		if delay > 0.0:
			tw.tween_interval(delay)
		tw.tween_property(ring, "scale", Vector2(5.5 + i, 5.5 + i), 0.28)
		tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.28)
		tw.tween_callback(ring.queue_free)
	var ctw := create_tween()
	ctw.tween_property(core, "scale", Vector2(5.5, 5.5), 0.24)
	ctw.parallel().tween_property(core, "modulate:a", 0.0, 0.24)
	ctw.tween_callback(core.queue_free)
	for i in 8:
		var spark := Polygon2D.new()
		spark.polygon = V.scale_poly(V.hex_points(3, 4), Vector2(1, 1))
		spark.position = local
		spark.color = HOT if i % 2 == 0 else CORE
		spark.z_index = 8
		add_child(spark)
		var stw := create_tween()
		var dir := Vector2.from_angle(float(i) / 8.0 * TAU) * randf_range(40, 90)
		stw.tween_property(spark, "position", local + dir, 0.22)
		stw.parallel().tween_property(spark, "modulate:a", 0.0, 0.22)
		stw.tween_callback(spark.queue_free)
