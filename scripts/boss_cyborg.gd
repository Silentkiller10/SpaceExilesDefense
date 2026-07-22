extends "res://scripts/enemy.gd"

## Cyborg boss — PHASE 1 (sandbox prototype, placeholder art for now).
## A jet-flying cyborg that strafes between hover points along the top
## of the arena and never descends, so it has to be shot down.
##
## Phase 1 kit:
##   Gun     — locks onto the player for 1s (laser-sight telegraph that
##             burns from yellow to red), then snaps off a fast bullet
##             at their position.
##   Grenade — lobbed onto a random active tower, disabling it for 5s.
##   Fleet   — keeps 2 Carrier motherships deployed. A 15s resupply
##             timer re-deploys any carrier that died.
##
## Phase 2 (jet dash + sword) will be added later.

const CARRIER_SCENE := preload("res://scenes/enemy_ship_carrier.tscn")
const BULLET_SCRIPT := preload("res://scripts/boss_cyborg_bullet.gd")
const GRENADE_SCRIPT := preload("res://scripts/boss_cyborg_grenade.gd")

const SHIP_TYPE := {
	"id": "cyborg_boss",
	"category": "ship",
	"texture": "res://assets/sprites/enemy_ship_2.png",  # placeholder art
	"sprite_scale": 0.07,
	"collision": Vector2(84, 96),
	"xp": 120
}

const AIM_TIME := 1.0
const GUN_COOLDOWN := 3.2
const GRENADE_COOLDOWN := 8.0
const TOWER_DISABLE_TIME := 5.0
const FLEET_SIZE := 2
const DEPLOY_INTERVAL := 15.0
const FIRST_DEPLOY_DELAY := 2.0
const HOVER_Y_MIN := 90.0
const HOVER_Y_MAX := 230.0
const EDGE_MARGIN := 120.0

## Combat stats — overridden by the wave manager via setup_cyborg().
var gun_damage: int = 12
var carrier_hp: int = 200
var carrier_speed: float = 60.0
var mini_hp: int = 70
var mini_speed: float = 48.0
var mini_bullet_damage: int = 3
## Set by the wave manager so deployed carriers (and their minis) join
## active_enemies, give XP, and count toward wave clearing.
var deploy_registrar: Callable

var _arena_w: float = 720.0
var _move_target: Vector2 = Vector2.ZERO
var _move_pause: float = 0.0
var _facing: float = 1.0
var _gun_cd: float = 1.5
var _aim_left: float = 0.0
var _aim_line: Line2D
var _grenade_cd: float = 4.5
var _deploy_timer: float = FIRST_DEPLOY_DELAY
var _fleet: Array = []

func _ready() -> void:
	super()
	apply_enemy_type(SHIP_TYPE)
	is_boss = true

## Called by the wave manager after setup_descent.
func setup_cyborg(g_dmg: int, c_hp: int, c_spd: float, m_hp: int, m_spd: float, m_dmg: int) -> void:
	gun_damage = g_dmg
	carrier_hp = c_hp
	carrier_speed = c_spd
	mini_hp = m_hp
	mini_speed = m_spd
	mini_bullet_damage = m_dmg
	if fortress:
		_arena_w = fortress.global_position.x * 2.0
	_move_target = global_position

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
	_update_movement(delta)
	_update_gun(delta)
	_update_grenade(delta)
	_update_fleet(delta)
	_update_fall_visual()
	_process_burn(delta)

## --- Jet movement: strafe between hover points in the top band ---

func _update_movement(delta: float) -> void:
	# Nearly hold position while aiming so the laser sight reads
	var speed_mult := 0.15 if _aim_left > 0.0 else 1.0
	if _move_pause > 0.0:
		_move_pause -= delta
		velocity = Vector2.ZERO
	else:
		var to_target := _move_target - global_position
		if to_target.length() < 14.0:
			_move_pause = randf_range(0.35, 0.9)
			_pick_move_target()
			velocity = Vector2.ZERO
		else:
			velocity = to_target.normalized() * speed * speed_mult * get_move_speed_scale()
	if absf(velocity.x) > 5.0:
		_facing = signf(velocity.x)
	move_and_slide()
	global_position.x = clampf(global_position.x, EDGE_MARGIN, _arena_w - EDGE_MARGIN)
	global_position.y = clampf(global_position.y, HOVER_Y_MIN, HOVER_Y_MAX + 24.0)

func _pick_move_target() -> void:
	_move_target = Vector2(
		randf_range(EDGE_MARGIN, _arena_w - EDGE_MARGIN),
		randf_range(HOVER_Y_MIN, HOVER_Y_MAX)
	)

## Hover: pulse + lean into travel, no spin (the base ship visual spins).
func _update_fall_visual() -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var pulse: float = 1.0 + sin(_fall_time * 3.0) * 0.03
	sprite.scale = _base_sprite_scale * pulse
	sprite.rotation = lerpf(sprite.rotation, _facing * 0.07, 0.1)
	if sprite.modulate.a >= 0.99:
		sprite.modulate = Color.WHITE

## --- Gun: 1s laser-sight lock-on, then a fast bullet ---

func _update_gun(delta: float) -> void:
	if _aim_left > 0.0:
		_aim_left -= delta
		_update_aim_line()
		if _aim_left <= 0.0:
			_fire_gun()
		return
	_gun_cd -= delta
	if _gun_cd <= 0.0 and _player_alive():
		_gun_cd = GUN_COOLDOWN
		_aim_left = AIM_TIME
		_make_aim_line()

func _player_alive() -> bool:
	return player != null and is_instance_valid(player) and player.visible

func _make_aim_line() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	_aim_line = Line2D.new()
	_aim_line.width = 2.0
	_aim_line.z_index = 20
	scene.add_child(_aim_line)
	_update_aim_line()

func _update_aim_line() -> void:
	if _aim_line == null or not is_instance_valid(_aim_line):
		return
	if not _player_alive():
		return
	_aim_line.points = PackedVector2Array([global_position, player.global_position])
	# Sight burns from faint yellow to hot red as the shot charges
	var charge := 1.0 - clampf(_aim_left / AIM_TIME, 0.0, 1.0)
	_aim_line.default_color = Color(
		1.0,
		lerpf(0.9, 0.15, charge),
		lerpf(0.35, 0.1, charge),
		lerpf(0.45, 0.9, charge)
	)

func _clear_aim_line() -> void:
	if _aim_line and is_instance_valid(_aim_line):
		_aim_line.queue_free()
	_aim_line = null

func _fire_gun() -> void:
	_clear_aim_line()
	if not _player_alive() or not is_inside_tree():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var dir := (player.global_position - global_position).normalized()
	var bullet := CharacterBody2D.new()
	bullet.set_script(BULLET_SCRIPT)
	scene.add_child(bullet)
	bullet.launch(global_position + dir * 46.0, dir, player, fortress, gun_damage)
	# Muzzle flash
	var flash := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 6:
		pts.append(Vector2.from_angle(float(i) / 6.0 * TAU) * 10.0)
	flash.polygon = pts
	flash.color = Color(1.0, 0.8, 0.4, 0.95)
	flash.position = global_position + dir * 46.0
	flash.z_index = 15
	scene.add_child(flash)
	var tw := flash.create_tween()
	tw.tween_property(flash, "scale", Vector2(0.2, 0.2), 0.12)
	tw.parallel().tween_property(flash, "modulate:a", 0.0, 0.12)
	tw.tween_callback(flash.queue_free)

## --- Grenade: disables a random active tower for 5s ---

func _update_grenade(delta: float) -> void:
	_grenade_cd -= delta
	if _grenade_cd > 0.0:
		return
	var tower := _pick_tower()
	if tower == null:
		# No valid target right now — check again shortly
		_grenade_cd = 1.0
		return
	_grenade_cd = GRENADE_COOLDOWN
	var scene := get_tree().current_scene
	if scene == null:
		return
	var grenade := Node2D.new()
	grenade.set_script(GRENADE_SCRIPT)
	scene.add_child(grenade)
	grenade.launch(global_position + Vector2(0.0, 30.0), tower, TOWER_DISABLE_TIME)

func _pick_tower() -> Node2D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var towers = scene.get("towers")
	if not towers is Dictionary:
		return null
	var candidates: Array = []
	for t in towers.values():
		if t == null or not is_instance_valid(t):
			continue
		if t.has_method("is_unlocked") and not t.is_unlocked():
			continue
		if t.get("sandbox_disabled") == true:
			continue
		if t.has_method("is_disabled") and t.is_disabled():
			continue
		candidates.append(t)
	if candidates.is_empty():
		return null
	return candidates[randi() % candidates.size()]

## --- Fleet: keep 2 carriers alive, resupply check every 15s ---

func _update_fleet(delta: float) -> void:
	_deploy_timer -= delta
	if _deploy_timer > 0.0:
		return
	_deploy_timer = DEPLOY_INTERVAL
	_fleet = _fleet.filter(func(c): return is_instance_valid(c) and c.get("is_dying") != true)
	var missing := FLEET_SIZE - _fleet.size()
	for i in missing:
		var side := -1.0 if (_fleet.size() + i) % 2 == 0 else 1.0
		_deploy_carrier(global_position + Vector2(side * 90.0, 40.0))

func _deploy_carrier(at: Vector2) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var carrier = CARRIER_SCENE.instantiate()
	scene.add_child(carrier)
	var x := clampf(at.x, 140.0, _arena_w - 140.0)
	carrier.setup_descent(Vector2(x, at.y), player, fortress, carrier_hp, carrier_speed)
	carrier.setup_carrier(mini_hp, mini_speed, mini_bullet_damage)
	if deploy_registrar.is_valid():
		carrier.mini_registrar = deploy_registrar
		deploy_registrar.call(carrier)
	_fleet.append(carrier)
	# Warp-in shimmer so the resupply reads visually
	var ring := Line2D.new()
	var pts := PackedVector2Array()
	for i in 21:
		pts.append(Vector2.from_angle(float(i) / 20.0 * TAU) * 22.0)
	ring.points = pts
	ring.width = 2.5
	ring.default_color = Color(0.4, 0.9, 1.0, 0.85)
	ring.position = Vector2(x, at.y)
	ring.z_index = 8
	scene.add_child(ring)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector2(3.0, 3.0), 0.3)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.3)
	tw.tween_callback(ring.queue_free)

func die():
	if is_dying:
		return
	_clear_aim_line()
	super()
