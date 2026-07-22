extends "res://scripts/enemy.gd"

## Rocketeer — shielded gunship. Spawns with a blue energy shield that
## absorbs all damage until it breaks. While shielded it fires one
## destructible rocket every 2s; once the shield is down it fires two
## (one from each wing pod). Explodes on death, damaging nearby enemies.

const ROCKET_SCENE := preload("res://scenes/enemy_rocket.tscn")

const SHIP_TYPE := {
	"id": "rocketeer",
	"category": "ship",
	"texture": "res://assets/sprites/enemy_ship_1.png",
	"sprite_scale": 0.045,
	"collision": Vector2(72, 78),
	"xp": 20
}

const FIRE_INTERVAL := 2.0
const SHIELD_RADIUS := 62.0
const DEATH_AOE_RADIUS := 170.0
const SHIELD_COLOR := Color(0.35, 0.7, 1.0)

var shield_max: int = 150
var shield_hp: int = 150
var rocket_fort_damage: int = 15
var death_aoe_damage: int = 90

var _fire_timer: float = FIRE_INTERVAL
var _shield_node: Node2D
var _shield_fill: Polygon2D
var _shield_ring: Line2D
var _shield_bar: ProgressBar

func _ready() -> void:
	super()
	apply_enemy_type(SHIP_TYPE)
	_build_shield_visual()

## Called by the wave manager after setup_descent to scale with the level.
func setup_combat(shield: int, fort_dmg: int, aoe_dmg: int) -> void:
	shield_max = maxi(1, shield)
	shield_hp = shield_max
	rocket_fort_damage = fort_dmg
	death_aoe_damage = aoe_dmg
	if _shield_bar:
		_shield_bar.max_value = shield_max
		_shield_bar.value = shield_hp

func _build_shield_visual() -> void:
	_shield_node = Node2D.new()
	_shield_node.z_index = 3
	add_child(_shield_node)

	var pts := PackedVector2Array()
	for i in 32:
		pts.append(Vector2.from_angle(float(i) / 32.0 * TAU) * SHIELD_RADIUS)

	_shield_fill = Polygon2D.new()
	_shield_fill.polygon = pts
	_shield_fill.color = Color(SHIELD_COLOR.r, SHIELD_COLOR.g, SHIELD_COLOR.b, 0.16)
	_shield_node.add_child(_shield_fill)

	_shield_ring = Line2D.new()
	var ring_pts := pts.duplicate()
	ring_pts.append(pts[0])
	_shield_ring.points = ring_pts
	_shield_ring.width = 3.0
	_shield_ring.default_color = Color(SHIELD_COLOR.r, SHIELD_COLOR.g, SHIELD_COLOR.b, 0.85)
	_shield_node.add_child(_shield_ring)

	_shield_bar = ProgressBar.new()
	_shield_bar.max_value = shield_max
	_shield_bar.value = shield_hp
	_shield_bar.show_percentage = false
	_shield_bar.position = Vector2(-20, -45)
	_shield_bar.size = Vector2(40, 6)
	_shield_bar.z_index = 10
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.35, 0.75, 1.0)
	_shield_bar.add_theme_stylebox_override("fill", fill)
	add_child(_shield_bar)

func _physics_process(delta):
	super(delta)
	if is_dying:
		return
	_pulse_shield()
	if stun_timer > 0.0:
		return
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = FIRE_INTERVAL
		_fire_rockets()

func _pulse_shield() -> void:
	if _shield_node == null or shield_hp <= 0:
		return
	var pulse: float = 1.0 + sin(_fall_time * 5.0) * 0.04
	_shield_node.scale = Vector2(pulse, pulse)
	var frac: float = float(shield_hp) / float(shield_max)
	# Lerp back from the white hit-flash toward the base blue
	var target := Color(SHIELD_COLOR.r, SHIELD_COLOR.g, SHIELD_COLOR.b, 0.45 + 0.4 * frac)
	_shield_ring.default_color = _shield_ring.default_color.lerp(target, 0.2)
	_shield_fill.color.a = 0.08 + 0.1 * frac

## Ships hover steady — no UFO spin, wing pods must stay left/right.
func _update_fall_visual() -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var pulse: float = 1.0 + sin(_fall_time * 4.0) * 0.03
	sprite.scale = _base_sprite_scale * pulse
	sprite.rotation = 0.0
	if sprite.modulate.a >= 0.99:
		sprite.modulate = Color.WHITE

func _fire_rockets() -> void:
	if shield_hp > 0:
		_spawn_rocket(Vector2(0, 34))
	else:
		_spawn_rocket(Vector2(-36, 20))
		_spawn_rocket(Vector2(36, 20))

func _spawn_rocket(offset: Vector2) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var rocket = ROCKET_SCENE.instantiate()
	scene.add_child(rocket)
	rocket.launch(global_position + offset, fortress, rocket_fort_damage)
	# Muzzle flash puff at the launch port
	var flash := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 8:
		pts.append(Vector2.from_angle(float(i) / 8.0 * TAU) * 8.0)
	flash.polygon = pts
	flash.position = offset
	flash.color = Color(1.0, 0.8, 0.4, 0.9)
	flash.z_index = 6
	add_child(flash)
	var tw := flash.create_tween()
	tw.tween_property(flash, "scale", Vector2(2.0, 2.0), 0.15)
	tw.parallel().tween_property(flash, "modulate:a", 0.0, 0.15)
	tw.tween_callback(flash.queue_free)

## --- Shield absorbs everything until it breaks ---

func take_damage(amount: int, knockback: float = 0.0, apply_ignition_flag: bool = false) -> void:
	if is_dying:
		return
	if shield_hp > 0:
		_damage_shield(amount)
		return
	super(amount, knockback, apply_ignition_flag)

func get_hit(damage: int, bullet_trans: Transform2D, knockback: float = 0.0, apply_ignition_flag: bool = false):
	if is_dying:
		return
	if shield_hp > 0:
		_damage_shield(damage)
		return
	super(damage, bullet_trans, knockback, apply_ignition_flag)

## Burn DoT ticks hull HP directly in the parent — shield must block it too.
func apply_burn(duration: float, dps: float) -> void:
	if shield_hp > 0:
		return
	super(duration, dps)

func _damage_shield(amount: int) -> void:
	shield_hp = maxi(0, shield_hp - amount)
	if _shield_bar:
		_shield_bar.value = shield_hp
	_show_hit_flash(amount)
	if _shield_ring:
		_shield_ring.default_color = Color(0.8, 0.95, 1.0, 1.0)
	if shield_hp <= 0:
		_break_shield()

func _break_shield() -> void:
	if _shield_bar:
		_shield_bar.visible = false
	if _shield_node:
		var tw := _shield_node.create_tween()
		tw.tween_property(_shield_node, "scale", Vector2(1.6, 1.6), 0.3)
		tw.parallel().tween_property(_shield_node, "modulate:a", 0.0, 0.3)
		tw.tween_callback(_shield_node.queue_free)
		_shield_node = null

## --- Death AoE: hurts every other enemy close to the wreck ---

## Guards against mutual recursion: two ships killing each other with their
## death AoEs would otherwise call die() back and forth until stack overflow.
var _aoe_done: bool = false

func die():
	if is_dying:
		return
	if not _aoe_done:
		_aoe_done = true
		_explode_aoe()
	super()

func _explode_aoe() -> void:
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy == self or not is_instance_valid(enemy):
			continue
		if enemy.get("is_dying") == true:
			continue
		if global_position.distance_to(enemy.global_position) > DEATH_AOE_RADIUS:
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(death_aoe_damage, 60.0)
	_spawn_aoe_fx()

func _spawn_aoe_fx() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var core := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 20:
		pts.append(Vector2.from_angle(float(i) / 20.0 * TAU) * DEATH_AOE_RADIUS * 0.25)
	core.polygon = pts
	core.position = global_position
	core.color = Color(1.0, 0.65, 0.3, 0.85)
	core.z_index = 16
	scene.add_child(core)
	var ctw := core.create_tween()
	ctw.tween_property(core, "scale", Vector2(4.0, 4.0), 0.3)
	ctw.parallel().tween_property(core, "modulate:a", 0.0, 0.3)
	ctw.tween_callback(core.queue_free)

	var ring := Line2D.new()
	var rpts := PackedVector2Array()
	for j in 33:
		rpts.append(Vector2.from_angle(float(j) / 32.0 * TAU) * DEATH_AOE_RADIUS * 0.25)
	ring.points = rpts
	ring.width = 4.0
	ring.default_color = Color(1.0, 0.5, 0.2, 0.8)
	ring.closed = true
	ring.position = global_position
	ring.z_index = 16
	scene.add_child(ring)
	var rtw := ring.create_tween()
	rtw.tween_property(ring, "scale", Vector2(4.0, 4.0), 0.35)
	rtw.parallel().tween_property(ring, "modulate:a", 0.0, 0.35)
	rtw.tween_callback(ring.queue_free)
