extends "res://scripts/towers/tower_base.gd"

## Sprite flamethrower — tripod base + rotating cannon head, layered fire cone.

const V := preload("res://scripts/towers/tower_visuals.gd")
const TEX_BASE_PATH := "res://assets/png/towers/flamethrower_base.png"
const TEX_HEAD_PATH := "res://assets/png/towers/flamethrower_head.png"

const CORE := Color(1.0, 0.45, 0.1)
const HOT := Color(1.0, 0.75, 0.15)
const CORE_INNER := Color(1.0, 0.95, 0.35)

const TOWER_SCALE := 0.792
## Base/head art is 1000x1000 (head points along +X).
const BASE_SCALE := 0.154 * TOWER_SCALE
const HEAD_SCALE := 0.14 * TOWER_SCALE
const AIM_SPEED := 12.0
const HEAD_FACING_OFFSET := 0.0
const PIVOT_OFFSET := Vector2(-5.0, -30.0) * TOWER_SCALE
const BASE_Y_OFFSET := 6.0 * TOWER_SCALE
const SHADOW_RADIUS := 18.0 * TOWER_SCALE
const LABEL_Y := 24.0 * TOWER_SCALE
## Head-local nudge for flame origin (barrel points +X; +Y shifts beam right when aimed up).
const MUZZLE_OFFSET := Vector2(0.0, 30.0) * TOWER_SCALE

var _base_sprite: Sprite2D
var _pivot: Node2D
var _head_sprite: Sprite2D
var _glow_sprite: Sprite2D
var _muzzle: Node2D
var _head_mount_tex: Vector2
var _muzzle_tex: Vector2
var _heat: float = 0.0
var _recoil: float = 0.0
var _idle_t: float = 0.0

func _ready() -> void:
	configure("flamethrower", "Flame Thrower", CORE, 450.0, 0.12, 28)
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
	_pivot.position = _base_sprite.position + PIVOT_OFFSET
	_pivot.z_index = 1
	add_child(_pivot)

	var head_size: Vector2 = tex_head.get_size() if tex_head else Vector2(1000, 1000)
	## Rear mount on fuel tank; barrel axis near vertical center of square art.
	_head_mount_tex = Vector2(-head_size.x * 0.32, head_size.y * 0.02)
	_muzzle_tex = Vector2(head_size.x * 0.44, head_size.y * 0.02)

	_head_sprite = Sprite2D.new()
	_head_sprite.texture = tex_head
	_head_sprite.scale = Vector2(HEAD_SCALE, HEAD_SCALE)
	_head_sprite.position = -_head_mount_tex * HEAD_SCALE
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
	_muzzle.position = (_muzzle_tex - _head_mount_tex) * HEAD_SCALE + MUZZLE_OFFSET
	_head_sprite.add_child(_muzzle)

	label = V.add_label(self, "FLAME", CORE, LABEL_Y)
	_pivot.rotation = -PI / 2.0

func _process(delta: float) -> void:
	if not unlocked or sandbox_disabled:
		return
	_idle_t += delta
	_heat = move_toward(_heat, 0.0, delta * 2.0)
	_recoil = move_toward(_recoil, 0.0, delta * 70.0)
	_aim_pivot(_find_target(), delta)
	_update_head_fx()
	super._process(delta)

func _aim_pivot(target: Node2D, delta: float) -> void:
	if _pivot == null:
		return
	var desired: float = -PI / 2.0
	if target:
		desired = _pivot.global_position.direction_to(target.global_position).angle()
		desired += HEAD_FACING_OFFSET
	_pivot.rotation = lerp_angle(_pivot.rotation, desired, 1.0 - exp(-AIM_SPEED * delta))

func _update_head_fx() -> void:
	if _head_sprite == null:
		return
	var pulse: float = 0.5 + 0.5 * sin(_idle_t * 6.0)
	var kick: float = _recoil * 0.015
	var axis := Vector2.from_angle(_pivot.rotation)
	_head_sprite.position = -_head_mount_tex * HEAD_SCALE - axis * kick
	if _glow_sprite:
		_glow_sprite.position = _head_sprite.position
		var fire: float = clampf(_heat, 0.0, 1.0)
		var bloom: float = 1.0 + pulse * 0.04 + fire * 0.14
		_glow_sprite.scale = _head_sprite.scale * bloom
		var glow_a: float = pulse * 0.08 + fire * 0.72
		var glow_c: Color = HOT.lerp(CORE_INNER, fire * 0.65)
		_glow_sprite.modulate = Color(glow_c.r, glow_c.g, glow_c.b, glow_a)
	if _muzzle:
		_muzzle.position = (_muzzle_tex - _head_mount_tex) * HEAD_SCALE + MUZZLE_OFFSET - axis * kick * 0.5
	var fire_t: float = clampf(_heat, 0.0, 1.0)
	var tint: float = 1.0 + pulse * 0.04 + fire_t * 0.18
	_head_sprite.modulate = Color(tint + fire_t * 0.22, tint + fire_t * 0.08, tint - fire_t * 0.12, 1.0)

func _fire(target: Node2D) -> void:
	_heat = 1.0
	_recoil = 6.0
	var aim_pos: Vector2 = target.global_position if target else global_position + Vector2(0, -120)
	_spawn_flame_cone(aim_pos)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or enemy.get("is_dying") == true:
			continue
		if global_position.distance_to(enemy.global_position) <= range_px:
			_hit_enemy(enemy, _scaled_damage())
			if enemy.has_method("apply_burn"):
				enemy.apply_burn(2.5, 45.0)

func _spawn_flame_cone(to: Vector2) -> void:
	var origin: Vector2 = _muzzle.global_position if _muzzle else global_position
	var origin_local: Vector2 = origin - global_position
	var dir := (to - origin).normalized()
	var angle := dir.angle()
	var length := clampf(origin.distance_to(to), 60.0, range_px)

	var layers := [
		{"len": length, "width": 28.8, "color": Color(CORE.r, CORE.g, CORE.b, 0.22), "z": -1},
		{"len": length * 0.85, "width": 19.2, "color": Color(HOT.r, HOT.g, HOT.b, 0.35), "z": -1},
		{"len": length * 0.65, "width": 11.2, "color": Color(CORE_INNER.r, CORE_INNER.g, CORE_INNER.b, 0.5), "z": -1},
	]

	for layer in layers:
		var flame := Polygon2D.new()
		var w: float = layer.width
		var l: float = layer.len
		flame.polygon = PackedVector2Array([
			Vector2(-w * 0.5, 0), Vector2(w * 0.5, 0),
			Vector2(w * 0.35, -l), Vector2(-w * 0.35, -l)
		])
		flame.color = layer.color
		flame.z_index = layer.z
		add_child(flame)
		flame.position = origin_local
		flame.rotation = angle + PI / 2.0
		var tw := create_tween()
		tw.tween_property(flame, "modulate:a", 0.0, 0.16)
		tw.parallel().tween_property(flame, "scale", Vector2(1.08, 1.12), 0.16)
		tw.tween_callback(flame.queue_free)

	# Embers along cone
	for i in 10:
		var ember := Polygon2D.new()
		ember.polygon = V.scale_poly(V.hex_points(2.5, 4), Vector2(1, 1))
		ember.color = HOT if i % 3 == 0 else CORE_INNER
		ember.z_index = -1
		add_child(ember)
		ember.global_position = origin
		var spread := randf_range(-0.35, 0.35)
		var dist := randf_range(length * 0.3, length * 0.9)
		var fly_dir := Vector2.from_angle(angle + spread)
		var tw2 := create_tween()
		tw2.tween_property(ember, "global_position", origin + fly_dir * dist * 0.25, 0.14)
		tw2.parallel().tween_property(ember, "modulate:a", 0.0, 0.14)
		tw2.tween_callback(ember.queue_free)
