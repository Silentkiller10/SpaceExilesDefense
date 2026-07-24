extends "res://scripts/enemy.gd"

## Giant Star boss — massive slow celestial body that drifts across the
## upper arena and rains falling stars of mixed sizes. At lower HP she
## escalates into meteor barrages. Spawns on stages after 10.

const FALLING_SCRIPT := preload("res://scripts/boss_star_falling.gd")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const EnemyScript := preload("res://scripts/enemy.gd")

const STAR_TYPE := {
	"id": "giant_star",
	"category": "ship",
	"texture": "res://assets/png/bosses/giant_star_boss.png",
	"strip_background": true,
	"sprite_scale": 1.02,
	"collision": Vector2(480, 480),
	"xp": 200
}

const HOVER_Y_MIN := 110.0
const HOVER_Y_MAX := 210.0
const EDGE_MARGIN := 220.0
## Base falling-star cadence (phase 0). Lower HP shortens this further.
const FIRE_INTERVAL_MIN := 0.45
const FIRE_INTERVAL_MAX := 0.85
const VOLLEY_CHANCE := 0.85
## Slow entrance from above before combat starts
const ENTER_DURATION := 4.5
const ENTER_END_Y := 160.0

var star_damage_scale: float = 1.0
var _arena_w: float = 720.0
var _move_target: Vector2 = Vector2.ZERO
var _move_pause: float = 0.8
var _fire_cd: float = 2.5
var _meteor_cd: float = 0.0
var _pulse_t: float = 0.0
var _entering: bool = true
var _enter_t: float = 0.0
var _enter_start: Vector2 = Vector2.ZERO
var _enter_end: Vector2 = Vector2.ZERO

func _ready() -> void:
	super()
	apply_enemy_type(STAR_TYPE)
	is_boss = true
	# Soft red corona instead of ship engine trails
	if _fall_trail and is_instance_valid(_fall_trail):
		_fall_trail.emitting = false
	if _ember_trail and is_instance_valid(_ember_trail):
		_ember_trail.emitting = false
	_begin_entrance()

func setup_star(dmg_scale: float) -> void:
	star_damage_scale = dmg_scale
	if fortress:
		_arena_w = fortress.global_position.x * 2.0
	_begin_entrance()

func _begin_entrance() -> void:
	_entering = true
	_enter_t = 0.0
	_enter_start = global_position
	if _enter_start.y > -80.0:
		_enter_start.y = -220.0
		global_position = _enter_start
	_enter_end = Vector2(_arena_w * 0.5 if _arena_w > 1.0 else global_position.x, ENTER_END_Y)
	_move_target = _enter_end
	if sprite:
		sprite.modulate.a = 0.0
		sprite.scale = _base_sprite_scale * 0.55

func _physics_process(delta):
	if is_dying:
		return

	if stun_timer > 0.0 and not _entering:
		stun_timer -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		_process_burn(delta)
		return

	_fall_time += delta
	_pulse_t += delta
	if _entering:
		_update_entrance(delta)
	else:
		_update_movement(delta)
		_update_firing(delta)
	_update_star_visual()
	_process_burn(delta)

func _update_entrance(delta: float) -> void:
	_enter_t += delta
	var t: float = clampf(_enter_t / ENTER_DURATION, 0.0, 1.0)
	# Ease-in-out so it drifts in, then settles
	var ease_t: float = t * t * (3.0 - 2.0 * t)
	global_position = _enter_start.lerp(_enter_end, ease_t)
	velocity = Vector2.ZERO
	if sprite:
		sprite.modulate.a = ease_t
		sprite.scale = _base_sprite_scale * lerpf(0.55, 1.0, ease_t)
	if t >= 1.0:
		_entering = false
		_move_target = global_position
		_move_pause = 0.6
		_fire_cd = 0.9
		_meteor_cd = 1.2
		if sprite:
			sprite.modulate.a = 1.0
			sprite.scale = _base_sprite_scale

func _update_movement(delta: float) -> void:
	if _move_pause > 0.0:
		_move_pause -= delta
		velocity = Vector2.ZERO
	else:
		var to_target := _move_target - global_position
		if to_target.length() < 18.0:
			_move_pause = randf_range(0.7, 1.6)
			_pick_move_target()
			velocity = Vector2.ZERO
		else:
			# Intentionally sluggish — a giant star does not dart
			velocity = to_target.normalized() * speed * get_move_speed_scale()
	move_and_slide()
	global_position.x = clampf(global_position.x, EDGE_MARGIN, _arena_w - EDGE_MARGIN)
	global_position.y = clampf(global_position.y, HOVER_Y_MIN, HOVER_Y_MAX)

func _pick_move_target() -> void:
	_move_target = Vector2(
		randf_range(EDGE_MARGIN + 40.0, _arena_w - EDGE_MARGIN - 40.0),
		randf_range(HOVER_Y_MIN, HOVER_Y_MAX)
	)

## 0 = >75% HP, 1 = ≤75%, 2 = ≤50%, 3 = ≤25%
func _rage_tier() -> int:
	var frac := float(health) / float(maxi(1, max_health))
	if frac <= 0.25:
		return 3
	if frac <= 0.50:
		return 2
	if frac <= 0.75:
		return 1
	return 0

func _update_firing(delta: float) -> void:
	var tier := _rage_tier()
	_fire_cd -= delta
	if _fire_cd <= 0.0:
		var rate_mult := 1.0 - float(tier) * 0.18
		_fire_cd = randf_range(FIRE_INTERVAL_MIN, FIRE_INTERVAL_MAX) * rate_mult
		_fire_star_volley(tier)
	if tier >= 1:
		_meteor_cd -= delta
		if _meteor_cd <= 0.0:
			_meteor_cd = _meteor_interval(tier)
			_fire_meteor_volley(tier)

func _meteor_interval(tier: int) -> float:
	match tier:
		1:
			return randf_range(0.9, 1.35)
		2:
			return randf_range(0.55, 0.85)
		_:
			return randf_range(0.28, 0.48)

func _fire_star_volley(tier: int) -> void:
	var count := 4
	if randf() < VOLLEY_CHANCE:
		count = 5 if randf() < 0.5 else 6
	count += tier * 2  # 4–6 base, up to +6 at 25% HP
	for i in count:
		var delay := float(i) * 0.08
		if delay <= 0.001:
			_spawn_falling_star()
		else:
			get_tree().create_timer(delay).timeout.connect(_spawn_falling_star)

func _fire_meteor_volley(tier: int) -> void:
	var count := 2
	match tier:
		1:
			count = 2 if randf() < 0.55 else 3
		2:
			count = 4 if randf() < 0.5 else 5
		_:
			count = 6 + (2 if randf() < 0.55 else 3)  # 8–9
	for i in count:
		var delay := float(i) * 0.09
		if delay <= 0.001:
			_spawn_meteor()
		else:
			get_tree().create_timer(delay).timeout.connect(_spawn_meteor)

func _spawn_falling_star() -> void:
	if is_dying or _entering or not is_inside_tree():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var roll := randf()
	var size_key := "medium"
	if roll < 0.38:
		size_key = "small"
	elif roll < 0.78:
		size_key = "medium"
	else:
		size_key = "large"
	var star := CharacterBody2D.new()
	star.set_script(FALLING_SCRIPT)
	scene.add_child(star)
	var origin := global_position + Vector2(randf_range(-80.0, 80.0), 120.0)
	star.launch(origin, fortress, size_key, star_damage_scale)

func _spawn_meteor() -> void:
	if is_dying or _entering or not is_inside_tree():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var roll := randf()
	var type_id := "small"
	if roll < 0.45:
		type_id = "small"
	elif roll < 0.85:
		type_id = "normal"
	else:
		type_id = "heavy"
	var etype := EnemyScript.get_enemy_type(type_id)
	var meteor = ENEMY_SCENE.instantiate()
	scene.add_child(meteor)
	if meteor.has_method("apply_enemy_type"):
		meteor.apply_enemy_type(etype)
	var base_hp := int(etype.get("base_hp", 120))
	var hp := maxi(40, int(round(float(base_hp) * 0.55 * star_damage_scale)))
	var spd := float(etype.get("base_speed", 50.0)) * randf_range(0.95, 1.2)
	var origin := global_position + Vector2(randf_range(-100.0, 100.0), 90.0)
	if meteor.has_method("setup_descent"):
		meteor.setup_descent(origin, player, fortress, hp, spd)
	_register_spawned_enemy(meteor, scene)

func _register_spawned_enemy(enemy: Node, scene: Node) -> void:
	# Prefer the live WaveManager so kill/clear tracking stays correct.
	var wm: Node = null
	if scene.has_node("WaveManager"):
		wm = scene.get_node("WaveManager")
	else:
		for child in scene.get_children():
			if child.has_method("_on_enemy_destroyed") and "active_enemies" in child:
				wm = child
				break
	if wm == null:
		return
	if enemy.has_signal("enemy_destroyed") and wm.has_method("_on_enemy_destroyed"):
		enemy.connect("enemy_destroyed", wm._on_enemy_destroyed)
	wm.active_enemies.append(enemy)
	if wm.has_signal("creep_spawned"):
		wm.creep_spawned.emit(enemy)

func take_damage(amount: int, knockback: float = 0.0, apply_ignition: bool = false) -> void:
	# Invulnerable while slowly entering the arena
	if _entering:
		return
	super.take_damage(amount, knockback, apply_ignition)

func _update_star_visual() -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	if _entering:
		return
	var tier := _rage_tier()
	var pulse: float = 1.0 + sin(_pulse_t * (1.6 + float(tier) * 0.5)) * (0.035 + float(tier) * 0.01)
	sprite.scale = _base_sprite_scale * pulse
	sprite.rotation = sin(_pulse_t * 0.35) * 0.08
	if sprite.modulate.a >= 0.99:
		var heat := 0.08 * float(tier)
		var glow := 0.92 + 0.08 * sin(_pulse_t * (2.4 + float(tier)))
		sprite.modulate = Color(glow, 0.85 + 0.1 * sin(_pulse_t * 1.8) - heat * 0.3, 0.85 - heat * 0.5, 1.0)
