extends "res://scripts/towers/tower_base.gd"

## Procedural flamethrower — fuel tank, wide nozzle, layered fire cone.

const V := preload("res://scripts/towers/tower_visuals.gd")
const CORE := Color(1.0, 0.45, 0.1)
const HOT := Color(1.0, 0.75, 0.15)
const CORE_INNER := Color(1.0, 0.95, 0.35)

var _turret: Node2D
var _nozzle: Polygon2D
var _tank_glow: Polygon2D
var _muzzle: Node2D
var _mount_glow: Polygon2D
var _heat: float = 0.0
var _idle_t: float = 0.0

func _ready() -> void:
	configure("flamethrower", "Flame Thrower", CORE, 300.0, 0.12, 28)
	super._ready()

func unlock() -> void:
	super.unlock()
	V.play_unlock(self)

func _build_visual() -> void:
	var platform := V.build_platform(self, V.BaseStyle.COMPACT, CORE)
	body = platform.body
	_mount_glow = platform.mount_glow

	_turret = Node2D.new()
	_turret.position = Vector2(0, -3)
	_turret.z_index = 2
	add_child(_turret)

	# Fuel tank
	var tank := Polygon2D.new()
	tank.polygon = PackedVector2Array([
		Vector2(-18, 4), Vector2(-16, -10), Vector2(-6, -14), Vector2(4, -10),
		Vector2(6, 4), Vector2(0, 8), Vector2(-10, 8)
	])
	tank.color = Color(0.12, 0.07, 0.05)
	_turret.add_child(tank)

	_tank_glow = Polygon2D.new()
	_tank_glow.polygon = V.scale_poly(V.hex_points(5, 6), Vector2(1, 1))
	_tank_glow.position = Vector2(-8, -4)
	_tank_glow.color = Color(CORE.r, CORE.g, CORE.b, 0.45)
	_turret.add_child(_tank_glow)

	_nozzle = Polygon2D.new()
	_nozzle.polygon = PackedVector2Array([
		Vector2(6, -6), Vector2(12, -8), Vector2(28, -10), Vector2(32, -6),
		Vector2(32, -2), Vector2(28, 2), Vector2(12, 0), Vector2(6, -2)
	])
	_nozzle.color = V.HULL_LIT.darkened(0.2)
	_turret.add_child(_nozzle)
	V.add_housing_edge(_turret, _nozzle.polygon)

	_muzzle = Node2D.new()
	_muzzle.position = Vector2(32, -4)
	_turret.add_child(_muzzle)

	label = V.add_label(self, "FLAME", CORE, 18)
	_turret.rotation = -PI / 2.0

func _process(delta: float) -> void:
	if not unlocked:
		return
	_idle_t += delta
	_heat = move_toward(_heat, 0.0, delta * 2.5)
	V.aim_turret(_turret, _find_target(), delta, 12.0)
	if _mount_glow:
		_mount_glow.modulate.a = 0.45 + sin(_idle_t * 5.0) * 0.15 + _heat * 0.35
	if _tank_glow:
		_tank_glow.modulate.a = 0.35 + _heat * 0.55 + sin(_idle_t * 7.0) * 0.1
	super._process(delta)

func _fire(target: Node2D) -> void:
	_heat = 1.0
	var aim_pos: Vector2 = target.global_position if target else global_position + Vector2(0, -120)
	_spawn_flame_cone(aim_pos)
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or enemy.get("is_dying") == true:
			continue
		if global_position.distance_to(enemy.global_position) <= range_px:
			_hit_enemy(enemy, _scaled_damage())
			if enemy.has_method("apply_burn"):
				enemy.apply_burn(2.5, 45.0)

func _spawn_flame_cone(to: Vector2) -> void:
	var dir := (to - global_position).normalized()
	var angle := dir.angle()
	var length := clampf(global_position.distance_to(to), 60.0, range_px)

	var layers := [
		{"len": length, "width": 36.0, "color": Color(CORE.r, CORE.g, CORE.b, 0.22), "z": 4},
		{"len": length * 0.85, "width": 24.0, "color": Color(HOT.r, HOT.g, HOT.b, 0.35), "z": 5},
		{"len": length * 0.65, "width": 14.0, "color": Color(CORE_INNER.r, CORE_INNER.g, CORE_INNER.b, 0.5), "z": 6},
	]

	for layer in layers:
		var flame := Polygon2D.new()
		var w: float = layer.width
		var l: float = layer.len
		flame.polygon = PackedVector2Array([
			Vector2(-w * 0.5, 0), Vector2(w * 0.5, 0),
			Vector2(w * 0.35, -l), Vector2(-w * 0.35, -l)
		])
		flame.color = layer.color
		flame.z_index = layer.z
		add_child(flame)
		flame.rotation = angle + PI / 2.0
		var tw := create_tween()
		tw.tween_property(flame, "modulate:a", 0.0, 0.16)
		tw.parallel().tween_property(flame, "scale", Vector2(1.08, 1.12), 0.16)
		tw.tween_callback(flame.queue_free)

	# Embers along cone
	if _muzzle:
		var muzzle_world := _muzzle.global_position
		for i in 10:
			var ember := Polygon2D.new()
			ember.polygon = V.scale_poly(V.hex_points(2.5, 4), Vector2(1, 1))
			ember.color = HOT if i % 3 == 0 else CORE_INNER
			ember.z_index = 7
			add_child(ember)
			ember.global_position = muzzle_world
			var spread := randf_range(-0.35, 0.35)
			var dist := randf_range(length * 0.3, length * 0.9)
			var fly_dir := Vector2.from_angle(angle + spread)
			var tw2 := create_tween()
			tw2.tween_property(ember, "global_position", muzzle_world + fly_dir * dist * 0.25, 0.14)
			tw2.parallel().tween_property(ember, "modulate:a", 0.0, 0.14)
			tw2.tween_callback(ember.queue_free)
