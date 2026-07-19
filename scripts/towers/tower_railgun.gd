extends "res://scripts/towers/tower_base.gd"

## Procedural railgun — capacitor rails, charge glow, massive beam.

const V := preload("res://scripts/towers/tower_visuals.gd")
const CORE := Color(0.45, 0.85, 1.0)
const HOT := Color(0.75, 0.95, 1.0)

var _turret: Node2D
var _barrel: Polygon2D
var _muzzle_glow: Polygon2D
var _muzzle: Node2D
var _mount_glow: Polygon2D
var _capacitors: Array[Polygon2D] = []
var _beams: Array[Line2D] = []
var _beam_tween: Tween
var _charge: float = 0.0
var _recoil: float = 0.0
var _idle_t: float = 0.0

func _ready() -> void:
	configure("railgun", "Railgun", CORE, 5000.0, 2.4, 520)
	super._ready()

func unlock() -> void:
	super.unlock()
	V.play_unlock(self)

func _build_visual() -> void:
	var platform := V.build_platform(self, V.BaseStyle.RAIL, CORE)
	body = platform.body
	_mount_glow = platform.mount_glow

	_turret = Node2D.new()
	_turret.position = Vector2(0, -5)
	_turret.z_index = 2
	add_child(_turret)

	var housing := Polygon2D.new()
	housing.polygon = PackedVector2Array([
		Vector2(-20, 8), Vector2(-22, -4), Vector2(-14, -14), Vector2(6, -16),
		Vector2(16, -8), Vector2(14, 6), Vector2(-4, 10)
	])
	housing.color = Color(0.08, 0.1, 0.13)
	_turret.add_child(housing)
	V.add_housing_edge(_turret, housing.polygon)

	for side in [-1, 1]:
		var cap := Polygon2D.new()
		cap.polygon = PackedVector2Array([
			Vector2(-6 * side, -12), Vector2(-2 * side, -12), Vector2(-2 * side, 8), Vector2(-6 * side, 8)
		])
		cap.color = Color(CORE.r, CORE.g, CORE.b, 0.35)
		_turret.add_child(cap)
		_capacitors.append(cap)

	_barrel = Polygon2D.new()
	_barrel.polygon = PackedVector2Array([
		Vector2(10, -10), Vector2(14, -8), Vector2(70, -6), Vector2(74, -4),
		Vector2(74, 0), Vector2(70, 2), Vector2(14, 0), Vector2(10, -2)
	])
	_barrel.color = V.HULL_LIT.darkened(0.05)
	_turret.add_child(_barrel)

	# Rail lines
	for y in [-5.0, -1.0]:
		var rail := Line2D.new()
		rail.points = PackedVector2Array([Vector2(12, y), Vector2(72, y)])
		rail.width = 1.5
		rail.default_color = Color(CORE.r, CORE.g, CORE.b, 0.8)
		_turret.add_child(rail)

	_muzzle_glow = Polygon2D.new()
	_muzzle_glow.polygon = V.scale_poly(V.hex_points(10, 10), Vector2(1, 1))
	_muzzle_glow.position = Vector2(72, -4)
	_muzzle_glow.color = Color(HOT.r, HOT.g, HOT.b, 0.4)
	_turret.add_child(_muzzle_glow)

	_muzzle = Node2D.new()
	_muzzle.position = Vector2(72, -4)
	_turret.add_child(_muzzle)

	_beams = [
		V.make_beam(self, 18.0, Color(CORE.r, CORE.g, CORE.b, 0.1), 6),
		V.make_beam(self, 9.0, Color(CORE.r, CORE.g, CORE.b, 0.3), 7),
		V.make_beam(self, 3.5, Color(1.0, 1.0, 1.0, 0.95), 8)
	]
	label = V.add_label(self, "RAIL", CORE, 22)
	_turret.rotation = -PI / 2.0

func _process(delta: float) -> void:
	if not unlocked:
		return
	_idle_t += delta
	_recoil = move_toward(_recoil, 0.0, delta * 35.0)
	var target := _find_target()
	V.aim_turret(_turret, target, delta, 6.0)
	# Charge capacitors when a target is in range and nearly ready to fire
	if target and cd_left <= cooldown * 0.35:
		_charge = move_toward(_charge, 1.0, delta * 1.8)
	else:
		_charge = move_toward(_charge, 0.0, delta * 2.5)
	var pulse: float = 0.5 + 0.5 * sin(_idle_t * 4.0)
	if _mount_glow:
		_mount_glow.modulate.a = 0.45 + pulse * 0.2 + _charge * 0.45
	for cap in _capacitors:
		cap.modulate = Color(1, 1, 1, 0.35 + _charge * 0.65)
	if _muzzle_glow:
		var s: float = 1.0 + _charge * 0.35 + pulse * 0.08
		_muzzle_glow.scale = Vector2(s, s)
		_muzzle_glow.modulate.a = 0.35 + _charge * 0.6
	if _barrel and _muzzle:
		var kick := Vector2.from_angle(_turret.rotation) * _recoil * 0.2
		_barrel.position = -kick
		_muzzle.position = Vector2(72, -4) - kick
		_muzzle_glow.position = _muzzle.position
	super._process(delta)

func _fire(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_hit_enemy(target, _scaled_damage(), 40.0)
	_charge = 0.0
	_recoil = 18.0
	var from_l: Vector2 = _muzzle.global_position - global_position if _muzzle else Vector2.ZERO
	var to_l: Vector2 = target.global_position - global_position
	V.show_beam_lines(_beams, from_l, to_l)
	if _beam_tween and _beam_tween.is_valid():
		_beam_tween.kill()
	_beam_tween = V.fade_lines(self, _beams, [0.18, 0.2, 0.22], func():
		for line in _beams:
			if is_instance_valid(line):
				line.visible = false
	)
	V.muzzle_sparks(_muzzle, CORE, HOT, 10)
	V.impact_burst(self, to_l, CORE, HOT)
	# Secondary impact rings along beam
	for t in [0.35, 0.65]:
		var pt := from_l.lerp(to_l, t)
		var ring := Line2D.new()
		ring.points = V.ellipse_points(Vector2(8, 8), 10)
		ring.position = pt
		ring.width = 2.0
		ring.default_color = Color(CORE.r, CORE.g, CORE.b, 0.5)
		ring.closed = true
		ring.z_index = 5
		add_child(ring)
		var tw := create_tween()
		tw.tween_property(ring, "scale", Vector2(3, 3), 0.15)
		tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.15)
		tw.tween_callback(ring.queue_free)
