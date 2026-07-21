extends Node2D

## Grenade lobbed by the Cyborg boss at a tower. Arcs from the boss to
## the tower's position, detonates in an EMP burst, and disables the
## tower for a few seconds (it stays visible but stops firing).

const FLIGHT_TIME := 1.3
const ARC_HEIGHT := 170.0

var target_tower: Node2D
var disable_duration: float = 5.0

var _start: Vector2 = Vector2.ZERO
var _end: Vector2 = Vector2.ZERO
var _t: float = 0.0
var _body: Polygon2D
var _light: Polygon2D

func _ready() -> void:
	z_index = 12
	_body = Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 10:
		pts.append(Vector2.from_angle(float(i) / 10.0 * TAU) * 8.0)
	_body.polygon = pts
	_body.color = Color(0.2, 0.25, 0.3)
	add_child(_body)

	_light = Polygon2D.new()
	var lpts := PackedVector2Array()
	for i in 6:
		lpts.append(Vector2.from_angle(float(i) / 6.0 * TAU) * 3.0)
	_light.polygon = lpts
	_light.color = Color(1.0, 0.25, 0.2)
	add_child(_light)

func launch(from: Vector2, tower: Node2D, duration: float) -> void:
	_start = from
	target_tower = tower
	disable_duration = duration
	_end = tower.global_position
	global_position = from

func _process(delta: float) -> void:
	_t += delta / FLIGHT_TIME
	if _t >= 1.0:
		_detonate()
		return
	# Track the tower slot (towers are static, but stay safe if it frees)
	if target_tower and is_instance_valid(target_tower):
		_end = target_tower.global_position
	global_position = _start.lerp(_end, _t) + Vector2(0.0, -ARC_HEIGHT * sin(PI * _t))
	rotation += 9.0 * delta
	# Arming light blinks faster as it closes in
	_light.visible = int(_t * (6.0 + _t * 14.0)) % 2 == 0

func _detonate() -> void:
	set_process(false)
	if target_tower and is_instance_valid(target_tower):
		global_position = target_tower.global_position
		if target_tower.has_method("apply_disable"):
			target_tower.apply_disable(disable_duration)
	var scene := get_tree().current_scene
	if scene:
		# EMP ring
		var ring := Line2D.new()
		var pts := PackedVector2Array()
		for i in 25:
			pts.append(Vector2.from_angle(float(i) / 24.0 * TAU) * 14.0)
		ring.points = pts
		ring.width = 3.0
		ring.default_color = Color(0.5, 0.75, 1.0, 0.95)
		ring.position = global_position
		ring.z_index = 15
		scene.add_child(ring)
		var tw := ring.create_tween()
		tw.tween_property(ring, "scale", Vector2(4.5, 4.5), 0.35)
		tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.35)
		tw.tween_callback(ring.queue_free)

		# Floating "DISABLED" callout so the effect reads in the chaos
		var label := Label.new()
		label.text = "DISABLED"
		label.add_theme_font_size_override("font_size", 13)
		label.modulate = Color(0.6, 0.85, 1.0)
		label.position = global_position + Vector2(-32.0, -46.0)
		label.z_index = 30
		scene.add_child(label)
		var ltw := label.create_tween()
		ltw.tween_property(label, "position:y", label.position.y - 26.0, 0.9)
		ltw.parallel().tween_property(label, "modulate:a", 0.0, 0.9)
		ltw.tween_callback(label.queue_free)
	queue_free()
