extends Area2D

## Rocket launcher projectile — guided rocket, explodes with AoE on impact.

const TEX_PATH: String = "res://assets/png/towers/rocket_projectile.png"
## Art is 948x225, points right; ~42px long on screen.
const ROCKET_SCALE := Vector2(0.045, 0.045)

const CORE := Color(0.4, 0.75, 1.0)
const HOT := Color(0.75, 0.95, 1.0)

@export var speed: float = 950.0
## How hard the rocket curves toward its target (rad/sec).
const TURN_RATE: float = 5.0

var damage: int = 30
var blast_radius: float = 90.0
var _range_left: float = 600.0
var _target: Node2D
var _sprite: Sprite2D
var _trail_t: float = 0.0
var _exploded: bool = false

func _ready() -> void:
	z_index = 15
	monitoring = true
	collision_layer = 4
	collision_mask = 2

	var tex: Texture2D = load(TEX_PATH) as Texture2D
	_sprite = Sprite2D.new()
	if tex:
		_sprite.texture = tex
	else:
		_sprite.texture = _make_fallback_texture()
	_sprite.scale = ROCKET_SCALE
	add_child(_sprite)

	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(30, 10)
	shape_node.shape = rect
	add_child(shape_node)

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _make_fallback_texture() -> Texture2D:
	var img := Image.create(64, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in img.get_width():
		for y in img.get_height():
			if y >= 4 and y <= 11:
				img.set_pixel(x, y, HOT.lerp(CORE, float(x) / 63.0))
	return ImageTexture.create_from_image(img)

func launch(origin: Vector2, direction: Vector2, target: Node2D, dmg: int, aoe_radius: float, max_range: float) -> void:
	global_position = origin
	if direction.length_squared() < 0.0001:
		direction = Vector2.UP
	rotation = direction.normalized().angle()
	_target = target
	damage = dmg
	blast_radius = aoe_radius
	_range_left = max_range

func _physics_process(delta: float) -> void:
	if _exploded:
		return
	# Steer toward target while it is alive
	if _target and is_instance_valid(_target) and _target.get("is_dying") != true:
		var desired: float = global_position.direction_to(_target.global_position).angle()
		rotation = rotate_toward(rotation, desired, TURN_RATE * delta)
	var step: float = speed * delta
	position += transform.x * step
	_range_left -= step
	_emit_trail(delta)
	if _range_left <= 0.0:
		_explode()
		return
	var gp := global_position
	if gp.y < -400.0 or gp.y > 2400.0 or gp.x < -400.0 or gp.x > 2400.0:
		queue_free()

func _emit_trail(delta: float) -> void:
	_trail_t -= delta
	if _trail_t > 0.0:
		return
	_trail_t = 0.03
	var parent := get_parent()
	if parent == null:
		return
	var puff := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 8:
		pts.append(Vector2.from_angle(float(i) / 8.0 * TAU) * 5.0)
	puff.polygon = pts
	puff.position = global_position - transform.x * 18.0
	puff.color = Color(HOT.r, HOT.g, HOT.b, 0.5)
	puff.z_index = 14
	parent.add_child(puff)
	var tw := puff.create_tween()
	tw.tween_property(puff, "scale", Vector2(2.2, 2.2), 0.3)
	tw.parallel().tween_property(puff, "modulate:a", 0.0, 0.3)
	tw.tween_callback(puff.queue_free)

func _on_body_entered(body: Node) -> void:
	if _exploded:
		return
	if body == null or not is_instance_valid(body):
		return
	if not body.is_in_group("enemy"):
		return
	if body.get("is_dying") == true:
		return
	_explode()

func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	set_deferred("monitoring", false)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or enemy.get("is_dying") == true:
			continue
		if global_position.distance_to(enemy.global_position) > blast_radius:
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage, 80.0)
		elif enemy.has_method("get_hit"):
			enemy.get_hit(damage, global_transform, 80.0)
	_spawn_blast_fx()
	if _sprite:
		_sprite.visible = false
	# Keep the node alive briefly so blast tweens finish, then free.
	var tw := create_tween()
	tw.tween_interval(0.4)
	tw.tween_callback(queue_free)

func _spawn_blast_fx() -> void:
	var core := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 20:
		pts.append(Vector2.from_angle(float(i) / 20.0 * TAU) * blast_radius * 0.2)
	core.polygon = pts
	core.color = Color(HOT.r, HOT.g, HOT.b, 0.85)
	core.z_index = 16
	add_child(core)
	var ctw := create_tween()
	ctw.tween_property(core, "scale", Vector2(5.0, 5.0), 0.22)
	ctw.parallel().tween_property(core, "modulate:a", 0.0, 0.22)
	ctw.tween_callback(core.queue_free)

	for i in 2:
		var ring := Line2D.new()
		var rpts := PackedVector2Array()
		for j in 25:
			rpts.append(Vector2.from_angle(float(j) / 24.0 * TAU) * blast_radius * 0.2)
		ring.points = rpts
		ring.width = 3.0 - i
		ring.default_color = Color(CORE.r, CORE.g, CORE.b, 0.7 - i * 0.2)
		ring.closed = true
		ring.z_index = 16
		add_child(ring)
		var rtw := create_tween()
		if i > 0:
			rtw.tween_interval(0.05)
		rtw.tween_property(ring, "scale", Vector2(5.0 + i, 5.0 + i), 0.26)
		rtw.parallel().tween_property(ring, "modulate:a", 0.0, 0.26)
		rtw.tween_callback(ring.queue_free)

	for i in 7:
		var spark := Polygon2D.new()
		var spts := PackedVector2Array()
		for j in 3:
			spts.append(Vector2.from_angle(float(j) / 3.0 * TAU) * 4.0)
		spark.polygon = spts
		spark.color = HOT if i % 2 == 0 else CORE
		spark.z_index = 17
		add_child(spark)
		var stw := create_tween()
		var dir := Vector2.from_angle(float(i) / 7.0 * TAU) * randf_range(blast_radius * 0.4, blast_radius * 0.8)
		stw.tween_property(spark, "position", dir, 0.24)
		stw.parallel().tween_property(spark, "modulate:a", 0.0, 0.24)
		stw.tween_callback(spark.queue_free)
