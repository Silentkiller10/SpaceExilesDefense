extends "res://scripts/towers/tower_base.gd"

## Sprite machine gun — base + rotating gatling head, bullet projectiles.

const V := preload("res://scripts/towers/tower_visuals.gd")
const BULLET_SCENE := preload("res://scenes/towers/tower_mg_bullet.tscn")
const TEX_BASE_PATH := "res://assets/sprites/machine_gun_base.png"
const TEX_HEAD_PATH := "res://assets/sprites/machine_gun_head.png"

const CORE := Color(0.35, 0.95, 1.0)
const HOT := Color(0.85, 1.0, 0.35)

const TOWER_SCALE := 0.792
const BASE_SCALE := 0.36 * TOWER_SCALE
const HEAD_SCALE := 0.28 * TOWER_SCALE
const AIM_SPEED := 16.0
const HEAD_FACING_OFFSET := 0.0
const PIVOT_OFFSET := Vector2(13.0, -22.0) * TOWER_SCALE
const BASE_Y_OFFSET := 6.0 * TOWER_SCALE
const SHADOW_RADIUS := 18.0 * TOWER_SCALE
const LABEL_Y := 22.0 * TOWER_SCALE

var _base_sprite: Sprite2D
var _pivot: Node2D
var _head_sprite: Sprite2D
var _muzzle: Node2D
var _head_mount_tex: Vector2
var _muzzle_tex: Vector2
var _spin: float = 0.0
var _recoil: float = 0.0
var _idle_t: float = 0.0

func _ready() -> void:
	configure("machinegun", "Machine Gun", Color(0.85, 0.9, 1.0), 500.0, 0.05, 16)
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

	var head_size: Vector2 = tex_head.get_size() if tex_head else Vector2(512, 512)
	_head_mount_tex = Vector2(-head_size.x * 0.34, head_size.y * 0.06)
	_muzzle_tex = Vector2(head_size.x * 0.47, 0.0)

	_head_sprite = Sprite2D.new()
	_head_sprite.texture = tex_head
	_head_sprite.scale = Vector2(HEAD_SCALE, HEAD_SCALE)
	_head_sprite.position = -_head_mount_tex * HEAD_SCALE
	_head_sprite.z_index = 1
	_pivot.add_child(_head_sprite)

	_muzzle = Node2D.new()
	_muzzle.position = (_muzzle_tex - _head_mount_tex) * HEAD_SCALE
	_head_sprite.add_child(_muzzle)

	label = V.add_label(self, "MG", CORE, LABEL_Y)
	_pivot.rotation = -PI / 2.0

func _process(delta: float) -> void:
	if not unlocked or sandbox_disabled:
		return
	_idle_t += delta
	_spin = move_toward(_spin, 0.0, delta * 20.0)
	_recoil = move_toward(_recoil, 0.0, delta * 90.0)
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
	var pulse: float = 0.5 + 0.5 * sin(_idle_t * 8.0)
	var fire: float = clampf(_spin / 28.0, 0.0, 1.0)
	var kick: float = _recoil * 0.015
	var axis := Vector2.from_angle(_pivot.rotation)
	_head_sprite.position = -_head_mount_tex * HEAD_SCALE - axis * kick
	if _muzzle:
		_muzzle.position = (_muzzle_tex - _head_mount_tex) * HEAD_SCALE - axis * kick * 0.5
	var tint: float = 1.0 + pulse * 0.06 + fire * 0.12
	_head_sprite.modulate = Color(tint, tint + 0.12, tint + 0.18, 1.0)

func _fire(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_spin = 28.0
	_recoil = 5.0
	var origin: Vector2 = _muzzle.global_position if _muzzle else global_position
	var direction: Vector2 = origin.direction_to(target.global_position)
	var world: Node = get_parent().get_parent() if get_parent() else get_tree().current_scene
	if world == null:
		world = get_tree().current_scene
	var bullet = BULLET_SCENE.instantiate()
	world.add_child(bullet)
	if bullet.has_method("launch"):
		bullet.launch(origin, direction, _scaled_damage(), 10.0, range_px)
	V.muzzle_sparks(_muzzle, CORE, HOT, 4)
