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

var _body_anim: AnimatedSprite2D
## Kneeling fire poses keyed by aim direction ({center, left: [...], right: [...]})
var _fire_poses: Dictionary = {}
var _fire_pose_sprite: Sprite2D
## True on frames where the character is actively aiming/firing
var _wants_fire_pose: bool = false

func _ready():
	if health_bar:
		health_bar.max_value = health
		health_bar.value = health
	if shot_timer:
		base_fire_interval = shot_timer.wait_time
	_body_anim = CharacterVisualScript.build_sprite_body(body_lr)
	_fire_poses = CharacterVisualScript.load_fire_poses()
	if not _fire_poses.is_empty():
		_fire_pose_sprite = Sprite2D.new()
		_fire_pose_sprite.name = "FirePose"
		_fire_pose_sprite.z_index = 1
		_fire_pose_sprite.visible = false
		var ps: float = CharacterVisualScript.FIRE_POSE_SCALE
		_fire_pose_sprite.scale = Vector2(ps, ps)
		body_lr.add_child(_fire_pose_sprite)
	body_rotate.scale = Vector2(CharacterVisualScript.COMBAT_SCALE, CharacterVisualScript.COMBAT_SCALE)
	var muzzle_x: float = CharacterVisualScript.SPRITE_MUZZLE_X
	bullet_spawn_pos.position = Vector2(muzzle_x, 0.0)
	shot_effect.position = Vector2(muzzle_x, 0.0)
	hide()

func setup(pos: Vector2):
	position = pos
	rampart_y = pos.y
	show()

func set_arena(width: float, y: float) -> void:
	arena_width = width
	rampart_y = y

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
		_wants_fire_pose = false
		_update_fire_pose()
		move_and_slide()
		return

	velocity = Vector2.ZERO
	if Input.is_action_pressed("move_right"):
		velocity.x += 1
	if Input.is_action_pressed("move_left"):
		velocity.x -= 1

	var is_moving := absf(velocity.x) > 0.0
	var manual_shot := Input.is_action_pressed("shot")

	if manual_fire_only:
		_aim_upward_cone()
		_wants_fire_pose = manual_shot
		if manual_shot and not is_shot_cd:
			_try_shoot()
	elif is_moving:
		_aim_upward_cone()
		_wants_fire_pose = manual_shot
		if manual_shot and not is_shot_cd:
			_try_shoot()
	else:
		var auto_aim := GameSettings.auto_aim_when_idle
		var auto_shoot := GameSettings.auto_shoot_when_idle
		var target: Node2D = _find_closest_enemy() if auto_aim else null

		if auto_aim and target != null:
			_aim_at(target.global_position)
		else:
			_aim_upward_cone()

		_wants_fire_pose = manual_shot or (auto_shoot and (target != null or not auto_aim))

		if auto_shoot and not is_shot_cd:
			if auto_aim:
				if target != null:
					_try_shoot()
			else:
				_try_shoot()
		elif manual_shot and not is_shot_cd:
			_try_shoot()

	if absf(velocity.x) > 0.0:
		velocity = velocity.normalized() * (speed * move_speed_modifier * (1.0 + gear_move_bonus))
		move_trail_effect.emitting = true

	update_body_lr()
	_update_fire_pose()
	move_and_slide()

	position.y = rampart_y
	position.x = clamp(position.x, 40.0, arena_width - 40.0)

func _try_shoot() -> void:
	shoot()
	is_shot_cd = true
	# Always compute from base_fire_interval — Timer.start(t) overwrites wait_time
	var wait: float = max(0.08, base_fire_interval * (1.0 - gear_fire_rate_bonus - skill_fire_rate_bonus))
	shot_timer.start(wait)

func apply_fire_rate_card(mult: float = 0.70) -> void:
	base_fire_interval = max(0.08, base_fire_interval * mult)
	shot_timer.wait_time = base_fire_interval

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
		aim = Vector2.UP
	# Full 180° — anywhere above the horizon; below it, snap to nearest side
	body_rotate.rotation = _clamp_to_upper_half(aim.angle())

func _aim_upward_cone() -> void:
	if not rotate_flag:
		return
	var mouse := get_global_mouse_position()
	var aim := (mouse - global_position)
	if aim.length() < 1.0:
		aim = Vector2.UP
	# Full 180° — from horizontal left to horizontal right
	body_rotate.rotation = _clamp_to_upper_half(aim.angle())

## Limits an aim angle to the upper half-circle (180°). Angles pointing
## below the horizon snap to the nearest horizontal side, avoiding the
## atan2 wrap that would flip a below-left aim over to the right.
func _clamp_to_upper_half(angle: float) -> float:
	if angle > 0.0:
		return 0.0 if angle <= PI / 2.0 else -PI
	return angle

func update_body_lr():
	if not lr_flag:
		return
	var base_scale: float = CharacterVisualScript.COMBAT_SCALE
	var facing_right: bool
	if abs(velocity.x) > 0:
		facing_right = velocity.x > 0
		if velocity.x > 0:
			body_lr_collider.scale.x = -1
			lr = true
		else:
			body_lr_collider.scale.x = 1
			lr = false
	else:
		facing_right = lr

	# Spritesheet art faces right; flip_h when moving/facing left.
	body_lr.scale = Vector2(base_scale, base_scale)

	if not _body_anim:
		return

	_body_anim.flip_h = not facing_right

	if abs(velocity.x) > 0:
		_body_anim.speed_scale = 1.0
		if _body_anim.animation != "walk":
			_body_anim.play("walk")
	else:
		_body_anim.speed_scale = 1.0
		if _body_anim.animation != "idle":
			_body_anim.play("idle")

## Swap the walk/idle body for a kneeling firing pose picked by aim angle
## (mouse direction when aiming manually, target direction when auto-aiming).
func _update_fire_pose() -> void:
	if _fire_pose_sprite == null:
		return
	# Walking cancels the kneel — the walk animation takes over
	var show_pose: bool = _wants_fire_pose and absf(velocity.x) <= 0.01
	if not show_pose:
		_fire_pose_sprite.visible = false
		if _body_anim:
			_body_anim.visible = true
		return

	# Degrees away from straight up: positive = right, negative = left
	var dev: float = rad_to_deg(wrapf(body_rotate.rotation + PI / 2.0, -PI, PI))
	var tex: Texture2D
	var ad: float = absf(dev)
	if ad < 10.0:
		tex = _fire_poses["center"]
	else:
		# Files are named 1 (most horizontal) .. 4 (almost vertical);
		# bins spread evenly across the 180° aim arc
		var idx: int
		if ad < 30.0:
			idx = 3
		elif ad < 50.0:
			idx = 2
		elif ad < 70.0:
			idx = 1
		else:
			idx = 0
		tex = _fire_poses["right"][idx] if dev > 0.0 else _fire_poses["left"][idx]

	var ps: float = CharacterVisualScript.FIRE_POSE_SCALE
	_fire_pose_sprite.texture = tex
	# Keep every pose's feet on the same ground line as the walk sprite
	_fire_pose_sprite.position = Vector2(0.0, CharacterVisualScript.FIRE_POSE_FEET_Y - tex.get_height() * ps * 0.5)
	_fire_pose_sprite.visible = true
	if _body_anim:
		_body_anim.visible = false

func shoot():
	body_rotete_player.play("Shot")
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
