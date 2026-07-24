extends Area2D

@export var speed: float = 2000.0
@export var damage: int = 93

var penetration: int = 0
var knockback: float = 0.0
var apply_ignition: bool = false
## How many child bullets to spawn on hit. Forked children have 0 (no chain forks).
var fork_count: int = 0
## Bodies to ignore once (stops forks from re-hitting the same enemy instantly).
var skip_bodies: Array = []
## 0–1 chance to splash on hit. Splash deals EXPLODE_DAMAGE_FRAC of bullet damage.
var explode_chance: float = 0.0
var explode_radius: float = 70.0
const EXPLODE_DAMAGE_FRAC := 0.75

@onready var bullet_particle = preload("res://scenes/bullet_particle.tscn")
@onready var bullet_scene = preload("res://scenes/bullet.tscn")

func _physics_process(delta):
	position += transform.x * speed * delta
	# Despawn if far off arena
	if position.y < -200 or position.y > 2000 or position.x < -200 or position.x > 2000:
		queue_free()

func setup(trans: Transform2D):
	transform = trans

func _on_body_entered(body):
	if body in skip_bodies:
		return
	if body.is_in_group("enemy"):
		if body.has_method("get_hit"):
			body.get_hit(damage, global_transform, knockback, apply_ignition)
		if explode_chance > 0.0 and randf() < explode_chance:
			_explode_at(global_position, body)
		_spawn_forks(body)

	var bullet_effect = bullet_particle.instantiate()
	bullet_effect.setup(global_transform)
	var scene := get_tree().current_scene
	if scene:
		scene.call_deferred("add_child", bullet_effect)

	if penetration > 0:
		penetration -= 1
	else:
		queue_free()

func _explode_at(origin: Vector2, skip_body: Node) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var splash: int = maxi(1, int(round(float(damage) * EXPLODE_DAMAGE_FRAC)))
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy == skip_body or not is_instance_valid(enemy):
			continue
		if enemy.get("is_dying") == true:
			continue
		if origin.distance_to(enemy.global_position) > explode_radius:
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(splash, knockback * 0.35, apply_ignition)
		elif enemy.has_method("get_hit"):
			enemy.get_hit(splash, global_transform, knockback * 0.35, apply_ignition)
	_spawn_explode_vfx(scene, origin)

func _spawn_explode_vfx(scene: Node, origin: Vector2) -> void:
	var ring := Line2D.new()
	ring.width = 3.0
	ring.default_color = Color(1.0, 0.55, 0.2, 0.85)
	ring.z_index = 12
	var pts := PackedVector2Array()
	var steps := 20
	for i in steps + 1:
		var a := TAU * float(i) / float(steps)
		pts.append(origin + Vector2(cos(a), sin(a)) * explode_radius * 0.35)
	ring.points = pts
	scene.add_child(ring)
	var tw := ring.create_tween()
	tw.tween_property(ring, "modulate:a", 0.0, 0.22)
	tw.parallel().tween_method(func(r: float):
		if not is_instance_valid(ring):
			return
		var p2 := PackedVector2Array()
		for i in steps + 1:
			var a := TAU * float(i) / float(steps)
			p2.append(origin + Vector2(cos(a), sin(a)) * r)
		ring.points = p2
	, explode_radius * 0.35, explode_radius, 0.22)
	tw.tween_callback(ring.queue_free)

func _spawn_forks(hit_body: Node) -> void:
	if fork_count <= 0:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return

	var count: int = fork_count
	# Children never fork again
	fork_count = 0

	var spread: float = deg_to_rad(18.0)
	var start_angle: float = -spread * float(count - 1) / 2.0
	var fork_damage: int = maxi(1, int(round(float(damage) * 0.7)))

	for i in range(count):
		var child = bullet_scene.instantiate()
		child.damage = fork_damage
		child.penetration = 0
		child.knockback = knockback * 0.5
		child.apply_ignition = apply_ignition
		child.fork_count = 0
		child.explode_chance = explode_chance
		child.explode_radius = explode_radius
		child.speed = speed * 0.95
		child.skip_bodies = [hit_body]
		var angle_offset: float = start_angle + float(i) * spread
		# Nudge forward so the fork clears the enemy collider
		var spawn_trans: Transform2D = global_transform.rotated_local(angle_offset)
		spawn_trans.origin += spawn_trans.x * 22.0
		child.setup(spawn_trans)
		scene.call_deferred("add_child", child)
