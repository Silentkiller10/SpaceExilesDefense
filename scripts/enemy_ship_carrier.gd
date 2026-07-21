extends "res://scripts/enemy.gd"

## Carrier — mother ship. Holds its spawn height and patrols left-right
## instead of descending, so it can never leak into the base: it has to
## be shot down. While alive it deploys a mini copy of itself every 3s
## (only the mother has this ability — and only the minis shoot). On
## death it splits into 2 minis side by side.

const MINI_SCENE := preload("res://scenes/enemy_ship_carrier_mini.tscn")

const SHIP_TYPE := {
	"id": "carrier",
	"category": "ship",
	"texture": "res://assets/sprites/enemy_ship_3.png",
	"sprite_scale": 0.05,
	"collision": Vector2(86, 100),
	"xp": 25
}

const DEPLOY_INTERVAL := 3.0
const EDGE_MARGIN := 110.0
const DEATH_SPLIT_COUNT := 2
const DEATH_SPLIT_SPACING := 70.0

var mini_hp: int = 60
var mini_speed: float = 55.0
var mini_bullet_damage: int = 4
## Set by the wave manager so deployed minis join active_enemies,
## get the XP hookup, and count toward wave clearing.
var mini_registrar: Callable

var _patrol_dir: float = 1.0
var _home_y: float = 0.0
var _deploy_timer: float = DEPLOY_INTERVAL
var _arena_w: float = 1152.0
var _split_done: bool = false

func _ready() -> void:
	super()
	apply_enemy_type(SHIP_TYPE)
	_patrol_dir = 1.0 if randf() < 0.5 else -1.0

## Called by the wave manager after setup_descent.
func setup_carrier(m_hp: int, m_spd: float, m_bullet_dmg: int) -> void:
	mini_hp = m_hp
	mini_speed = m_spd
	mini_bullet_damage = m_bullet_dmg
	_home_y = global_position.y
	if fortress:
		_arena_w = fortress.global_position.x * 2.0

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

	# Left-right patrol at spawn height — never advances on the base
	velocity = Vector2(speed * _patrol_dir, 0.0)
	move_and_slide()
	if global_position.x <= EDGE_MARGIN:
		_patrol_dir = 1.0
	elif global_position.x >= _arena_w - EDGE_MARGIN:
		_patrol_dir = -1.0
	global_position.x = clampf(global_position.x, EDGE_MARGIN, _arena_w - EDGE_MARGIN)
	# Gentle hover bob around the spawn line
	global_position.y = _home_y + sin(_fall_time * 1.6) * 6.0

	_deploy_timer -= delta
	if _deploy_timer <= 0.0:
		_deploy_timer = DEPLOY_INTERVAL
		_deploy_mini(global_position + Vector2(randf_range(-30.0, 30.0), 55.0))

	_update_fall_visual()
	_process_burn(delta)

## Hover in place: pulse + lean into the patrol direction, no spin.
func _update_fall_visual() -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var pulse: float = 1.0 + sin(_fall_time * 3.5) * 0.03
	sprite.scale = _base_sprite_scale * pulse
	sprite.rotation = lerpf(sprite.rotation, _patrol_dir * 0.08, 0.1)
	if sprite.modulate.a >= 0.99:
		sprite.modulate = Color.WHITE

func _deploy_mini(at: Vector2) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var mini = MINI_SCENE.instantiate()
	scene.add_child(mini)
	var x := clampf(at.x, 50.0, _arena_w - 50.0)
	mini.setup_descent(Vector2(x, at.y), player, fortress, mini_hp, mini_speed)
	mini.setup_mini(mini_bullet_damage)
	if mini_registrar.is_valid():
		mini_registrar.call(mini)
	# Drop-off shimmer so the deploy reads visually
	var ring := Line2D.new()
	var pts := PackedVector2Array()
	for i in 17:
		pts.append(Vector2.from_angle(float(i) / 16.0 * TAU) * 16.0)
	ring.points = pts
	ring.width = 2.0
	ring.default_color = Color(0.4, 0.9, 1.0, 0.8)
	ring.position = Vector2(x, at.y)
	ring.z_index = 8
	scene.add_child(ring)
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector2(2.4, 2.4), 0.25)
	tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.25)
	tw.tween_callback(ring.queue_free)

## Death split: the wreck breaks into 3 minis side by side.
func die():
	if is_dying:
		return
	if not _split_done and is_inside_tree():
		_split_done = true
		var half := float(DEATH_SPLIT_COUNT - 1) * 0.5
		for i in DEATH_SPLIT_COUNT:
			var offset_x := (float(i) - half) * DEATH_SPLIT_SPACING
			_deploy_mini(global_position + Vector2(offset_x, 30.0))
	super()
