extends CharacterBody2D

@export var speed: float = 320.0
@export var lr_flag: bool = true
@export var rotate_flag: bool = true
@export var health: int = 100

@export var damage_multiplier: float = 1.0
@export var move_speed_modifier: float = 1.0
@export var pierce_count: int = 0
@export var bonus_projectiles: int = 0
@export var knockback_strength: float = 0.0
## KINETIC PUSH stacks (0–3). Values are upward impulse (px/s).
const KINETIC_BASE := 10.0
const KINETIC_LEVEL_BONUS := [0.0, 1.0, 2.0]
var kinetic_level: int = 0
## Chance (0–1) that a bullet explodes on hit.
var bullet_explode_chance: float = 0.0
## Splash radius in pixels for bullet explosions.
var bullet_explode_radius: float = 70.0

# Gear bonuses (applied from GearSystem)
var gear_damage_bonus: float = 0.0
var gear_fire_rate_bonus: float = 0.0
var gear_move_bonus: float = 0.0
var gear_cooldown_reduction: float = 0.0
var gear_fork_count: int = 0
var gear_pierce: int = 0
var gear_projectiles: int = 0
var gear_ignition: bool = false
## Extra forks from run upgrade cards
var bonus_fork: int = 0

var skill_damage_bonus: float = 0.0
var skill_fire_rate_bonus: float = 0.0
var skill_pierce: int = 0
var skill_projectiles: int = 0

var is_shot_cd: bool = false
var invincible: bool = false
var lr: bool = true
var arena_width: float = 1152.0
var arena_height: float = 1280.0
## Vertical play band (above towers, below HUD).
var move_min_y: float = 200.0
var move_max_y: float = 980.0
## Kept for callers that still read the old locked rail Y.
var rampart_y: float = 560.0
## Sandbox: no auto-aim/auto-fire — only shoots while click/hold on "shot"
var manual_fire_only: bool = false
## Kamikaze base explosion locks the character out for a moment
var stun_timer: float = 0.0

@onready var body_lr: Node2D = $BodyLR
@onready var body_rotate: Node2D = $BodyRotate
@onready var body_rotete_player: AnimationPlayer = $BodyRotatePlayer
@onready var move_trail_effect: GPUParticles2D = $MovementTrailEffect
@onready var bullet_scene = preload("res://scenes/bullet.tscn")
@onready var bullet_spawn_pos: Node2D = $BodyRotate/BulletSpawnPoint
@onready var shot_timer: Timer = $ShotTimer
@onready var shot_effect: GPUParticles2D = $BodyRotate/ShootingEffect
@onready var body_lr_collider: CollisionShape2D = $CollisionBodyLR
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var health_bar: ProgressBar = $ProgressBar

## Stable base shot interval — never shrink this via Timer.start()
var base_fire_interval: float = 0.9

const CharacterVisualScript = preload("res://scripts/character_visual.gd")

var _body_anim: PlayerJetpackBody

func _ready():
	if health_bar:
		health_bar.max_value = health
		health_bar.value = health
	if shot_timer:
		base_fire_interval = shot_timer.wait_time
	_body_anim = CharacterVisualScript.build_sprite_body(body_lr)
	body_rotate.scale = Vector2(CharacterVisualScript.COMBAT_SCALE, CharacterVisualScript.COMBAT_SCALE)
	var muzzle_x: float = CharacterVisualScript.SPRITE_MUZZLE_X
	bullet_spawn_pos.position = Vector2(muzzle_x, 0.0)
	shot_effect.position = Vector2(muzzle_x, 0.0)
	hide()

func setup(pos: Vector2):
	position = pos
	rampart_y = pos.y
	show()

func set_arena(width: float, height: float) -> void:
	arena_width = width
	arena_height = height
	# Match the open field above the tower row (towers sit near height - 55).
	move_min_y = 180.0
	move_max_y = height - 140.0
	rampart_y = clampf(rampart_y, move_min_y, move_max_y)

func apply_stun(duration: float) -> void:
	stun_timer = maxf(stun_timer, duration)

func _physics_process(delta):
	if stun_timer > 0.0:
		stun_timer -= delta
		velocity = Vector2.ZERO
		# Flicker while stunned; no moving, aiming, or shooting
		modulate = Color(0.6, 0.7, 1.0) if int(stun_timer * 12.0) % 2 == 0 else Color(0.85, 0.9, 1.05)
		if stun_timer <= 0.0:
			modulate = Color.WHITE
		move_and_slide()
		return

	velocity = Vector2.ZERO
	if Input.is_action_pressed("move_right"):
		velocity.x += 1
	if Input.is_action_pressed("move_left"):
		velocity.x -= 1
	if Input.is_action_pressed("move_up"):
		velocity.y -= 1
	if Input.is_action_pressed("move_down"):
		velocity.y += 1

	var target: Node2D = _find_closest_enemy()
	var has_enemy := target != null

	# Full 360° aim — at the nearest enemy, or mouse if none.
	if has_enemy:
		_aim_at(target.global_position)
	else:
		_aim_at(get_global_mouse_position())

	# Only fire when an enemy exists (sandbox still requires click/hold).
	if has_enemy and not is_shot_cd:
		if manual_fire_only:
			if Input.is_action_pressed("shot"):
				_try_shoot()
		else:
			_try_shoot()

	if velocity.length() > 0.0:
		velocity = velocity.normalized() * (speed * move_speed_modifier * (1.0 + gear_move_bonus))
		move_trail_effect.emitting = true
	else:
		move_trail_effect.emitting = false

	update_body_lr()
	move_and_slide()

	position.x = clampf(position.x, 40.0, arena_width - 40.0)
	position.y = clampf(position.y, move_min_y, move_max_y)

func _try_shoot() -> void:
	shoot()
	is_shot_cd = true
	# Always compute from base_fire_interval — Timer.start(t) overwrites wait_time
	var wait: float = max(0.08, base_fire_interval * (1.0 - gear_fire_rate_bonus - skill_fire_rate_bonus))
	shot_timer.start(wait)

func apply_fire_rate_card(mult: float = 0.70) -> void:
	base_fire_interval = max(0.08, base_fire_interval * mult)
	shot_timer.wait_time = base_fire_interval

func apply_kinetic_push_level() -> void:
	kinetic_level = mini(3, kinetic_level + 1)
	var bonus: float = KINETIC_LEVEL_BONUS[kinetic_level - 1]
	knockback_strength = KINETIC_BASE * (1.0 + bonus)

func _find_closest_enemy() -> Node2D:
	var best: Node2D = null
	var best_dist: float = INF
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		if enemy.get("is_dying") == true:
			continue
		var d: float = global_position.distance_to(enemy.global_position)
		if d < best_dist:
			best_dist = d
			best = enemy
	return best

func _aim_at(world_pos: Vector2) -> void:
	if not rotate_flag:
		return
	var aim: Vector2 = world_pos - global_position
	if aim.length() < 1.0:
		return
	body_rotate.rotation = aim.angle()

func update_body_lr():
	if not lr_flag:
		return
	var base_scale: float = CharacterVisualScript.COMBAT_SCALE
	var facing_right: bool
	if absf(velocity.x) > 0.05:
		facing_right = velocity.x > 0
		if velocity.x > 0:
			body_lr_collider.scale.x = -1
			lr = true
		else:
			body_lr_collider.scale.x = 1
			lr = false
	else:
		# Face toward aim direction when mostly moving vertically / idle.
		facing_right = cos(body_rotate.rotation) >= 0.0
		lr = facing_right

	# Spritesheet art faces right; flip_h when moving/facing left.
	body_lr.scale = Vector2(base_scale, base_scale)

	if not _body_anim:
		return

	_body_anim.flip_h = not facing_right

	if velocity.length() > 0.05:
		_body_anim.speed_scale = 1.0
		if _body_anim.animation != "walk":
			_body_anim.play("walk")
	else:
		_body_anim.speed_scale = 1.0
		if _body_anim.animation != "idle":
			_body_anim.play("idle")

func shoot():
	shot_effect.emitting = true
	audio_player.play()

	var total_bullets = 1 + bonus_projectiles + skill_projectiles + gear_projectiles
	var spread_angle = deg_to_rad(4.0)
	var start_angle = -spread_angle * (total_bullets - 1.0) / 2.0

	for i in range(total_bullets):
		var bullet = bullet_scene.instantiate()
		bullet.damage = int(93.0 * (damage_multiplier + gear_damage_bonus + skill_damage_bonus))
		bullet.penetration = pierce_count + skill_pierce + gear_pierce
		bullet.knockback = knockback_strength
		bullet.apply_ignition = gear_ignition
		bullet.fork_count = gear_fork_count + bonus_fork
		bullet.explode_chance = bullet_explode_chance
		bullet.explode_radius = bullet_explode_radius
		var angle_offset = start_angle + (i * spread_angle)
		var spawn_trans = bullet_spawn_pos.global_transform.rotated_local(angle_offset)
		bullet.setup(spawn_trans)
		get_tree().current_scene.add_child(bullet)

func _on_shot_timer_timeout():
	is_shot_cd = false

func take_damage(amount: int):
	if invincible:
		return
	health -= amount
	if health_bar:
		health_bar.value = health
	invincible = true
	await get_tree().create_timer(0.4).timeout
	invincible = false
	if health <= 0:
		die()

func die():
	hide()
	set_physics_process(false)
