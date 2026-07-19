extends "res://scripts/towers/tower_base.gd"

## Procedural cannon — heavy mortar, arcing shell, shockwave blast.

const V := preload("res://scripts/towers/tower_visuals.gd")
const CORE := Color(1.0, 0.55, 0.2)
const HOT := Color(1.0, 0.75, 0.25)

var _turret: Node2D
var _barrel: Polygon2D
var _muzzle: Node2D
var _mount_glow: Polygon2D
var _recoil: float = 0.0
var _idle_t: float = 0.0

func _ready() -> void:
	configure("cannon", "Cannon", CORE, 520.0, 1.1, 120)
	super._ready()

func unlock() -> void:
	super.unlock()
	V.play_unlock(self)

func _build_visual() -> void:
	var platform := V.build_platform(self, V.BaseStyle.HEAVY, CORE)
	body = platform.body
	_mount_glow = platform.mount_glow

	_turret = Node2D.new()
	_turret.position = Vector2(0, -6)
	_turret.z_index = 2
	add_child(_turret)

	var housing := Polygon2D.new()
	housing.polygon = PackedVector2Array([
		Vector2(-22, 8), Vector2(-24, -2), Vector2(-18, -14), Vector2(-4, -18),
		Vector2(12, -14), Vector2(18, -2), Vector2(14, 10), Vector2(-8, 12)
	])
	housing.color = Color(0.1, 0.08, 0.07)
	_turret.add_child(housing)
	V.add_housing_edge(_turret, housing.polygon)

	# Ammo drum
	var drum := Polygon2D.new()
	drum.polygon = V.ellipse_points(Vector2(10, 10), 10)
	drum.position = Vector2(-14, 0)
	drum.color = V.HULL_LIT.darkened(0.25)
	_turret.add_child(drum)

	_barrel = Polygon2D.new()
	_barrel.polygon = PackedVector2Array([
		Vector2(8, -18), Vector2(14, -16), Vector2(48, -12), Vector2(52, -8),
		Vector2(52, -4), Vector2(48, 0), Vector2(14, -4), Vector2(8, -6)
	])
	_barrel.color = V.HULL_LIT.darkened(0.05)
	_turret.add_child(_barrel)

	var bore := Polygon2D.new()
	bore.polygon = V.scale_poly(V.hex_points(6, 8), Vector2(1, 1))
	bore.position = Vector2(50, -8)
	bore.color = Color(CORE.r, CORE.g, CORE.b, 0.45)
	_turret.add_child(bore)

	_muzzle = Node2D.new()
	_muzzle.position = Vector2(52, -8)
	_turret.add_child(_muzzle)

	label = V.add_label(self, "CANNON", CORE, 22)
	_turret.rotation = -PI / 2.0

func _process(delta: float) -> void:
	if not unlocked:
		return
	_idle_t += delta
	_recoil = move_toward(_recoil, 0.0, delta * 45.0)
	V.aim_turret(_turret, _find_target(), delta, 8.0)
	if _mount_glow:
		_mount_glow.modulate.a = 0.5 + sin(_idle_t * 3.0) * 0.15
	if _barrel and _muzzle:
		var axis := Vector2.from_angle(_turret.rotation)
		var kick := axis * _recoil * 0.15
		_barrel.position = -kick
		_muzzle.position = Vector2(52, -8) - kick
	super._process(delta)

func _fire(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var impact: Vector2 = target.global_position
	var blast_r := 180.0
	_recoil = 14.0
	_spawn_shell_arc(impact)
	_spawn_blast(impact, blast_r)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or enemy.get("is_dying") == true:
			continue
		if impact.distance_to(enemy.global_position) <= blast_r:
			_hit_enemy(enemy, _scaled_damage(), 140.0)

func _spawn_shell_arc(impact: Vector2) -> void:
	var shell := Polygon2D.new()
	shell.polygon = V.scale_poly(V.hex_points(4, 6), Vector2(1, 1))
	shell.color = HOT
	shell.z_index = 6
	add_child(shell)
	var from_l: Vector2 = _muzzle.global_position - global_position if _muzzle else Vector2.ZERO
	var to_l: Vector2 = impact - global_position
	shell.position = from_l
	var mid := (from_l + to_l) * 0.5 + Vector2(randf_range(-20, 20), -80)
	var tw := create_tween()
	tw.tween_method(func(t: float):
		if not is_instance_valid(shell):
			return
		var a := 1.0 - t
		shell.position = a * a * from_l + 2.0 * a * t * mid + t * t * to_l
	, 0.0, 1.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(shell.queue_free)
	V.muzzle_sparks(_muzzle, CORE, HOT, 8)

func _spawn_blast(world_pos: Vector2, radius: float) -> void:
	var local := world_pos - global_position
	# Core fireball
	var core := Polygon2D.new()
	core.polygon = V.ellipse_points(Vector2(radius * 0.18, radius * 0.18), 20)
	core.position = local
	core.color = Color(HOT.r, HOT.g, HOT.b, 0.75)
	core.z_index = 7
	add_child(core)
	# Shock rings
	for i in 3:
		var ring := Line2D.new()
		ring.points = V.ellipse_points(Vector2(radius * 0.15, radius * 0.15), 24)
		ring.position = local
		ring.width = 3.0 - i * 0.6
		ring.default_color = Color(CORE.r, CORE.g, CORE.b, 0.65 - i * 0.15)
		ring.closed = true
		ring.z_index = 6
		add_child(ring)
		var delay: float = float(i) * 0.04
		var tw := create_tween()
		if delay > 0.0:
			tw.tween_interval(delay)
		tw.tween_property(ring, "scale", Vector2(5.5 + i, 5.5 + i), 0.28)
		tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.28)
		tw.tween_callback(ring.queue_free)
	var ctw := create_tween()
	ctw.tween_property(core, "scale", Vector2(5.5, 5.5), 0.24)
	ctw.parallel().tween_property(core, "modulate:a", 0.0, 0.24)
	ctw.tween_callback(core.queue_free)
	# Debris sparks
	for i in 8:
		var spark := Polygon2D.new()
		spark.polygon = V.scale_poly(V.hex_points(3, 4), Vector2(1, 1))
		spark.position = local
		spark.color = HOT if i % 2 == 0 else CORE
		spark.z_index = 8
		add_child(spark)
		var stw := create_tween()
		var dir := Vector2.from_angle(float(i) / 8.0 * TAU) * randf_range(40, 90)
		stw.tween_property(spark, "position", local + dir, 0.22)
		stw.parallel().tween_property(spark, "modulate:a", 0.0, 0.22)
		stw.tween_callback(spark.queue_free)
