extends RefCounted
class_name TowerVisuals

const HULL := Color(0.07, 0.08, 0.11, 1.0)
const HULL_LIT := Color(0.14, 0.16, 0.22, 1.0)
const HULL_DARK := Color(0.05, 0.06, 0.09, 1.0)

enum BaseStyle { STANDARD, HEAVY, TRIPOD, RAIL, COMPACT }

static func hex_points(radius: float, segments: int = 6) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	for i in segments:
		var a: float = TAU * float(i) / float(segments) - PI / 2.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts

static func ellipse_points(radii: Vector2, segments: int = 12) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	for i in segments:
		var a: float = TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return pts

static func scale_poly(pts: PackedVector2Array, scale: Vector2) -> PackedVector2Array:
	var out: PackedVector2Array = []
	for p in pts:
		out.append(Vector2(p.x * scale.x, p.y * scale.y))
	return out

static func add_shadow(parent: Node2D, radius: float = 22.0) -> Polygon2D:
	var shadow := Polygon2D.new()
	shadow.polygon = scale_poly(hex_points(radius, 6), Vector2(1.35, 0.55))
	shadow.position = Vector2(0, 14)
	shadow.color = Color(0, 0, 0, 0.35)
	shadow.z_index = -2
	parent.add_child(shadow)
	return shadow

static func build_platform(parent: Node2D, style: BaseStyle, accent: Color) -> Dictionary:
	add_shadow(parent, _shadow_radius(style))
	var body := Polygon2D.new()
	body.polygon = _platform_poly(style)
	body.color = HULL
	body.z_index = 0
	parent.add_child(body)

	for extra in _platform_extras(style):
		parent.add_child(extra)

	var mount := Polygon2D.new()
	mount.polygon = scale_poly(hex_points(_mount_radius(style), 8), Vector2(1.0, 0.45))
	mount.position = Vector2(0, -2)
	mount.color = Color(accent.r, accent.g, accent.b, 0.18)
	mount.z_index = 1
	parent.add_child(mount)

	return {"body": body, "mount_glow": mount}

static func add_label(parent: Node2D, text: String, accent: Color, y: float = 20.0) -> Label:
	var label := Label.new()
	label.text = text
	label.position = Vector2(-18, y)
	label.add_theme_font_size_override("font_size", 9)
	label.modulate = Color(accent.r, accent.g, accent.b, 0.85)
	parent.add_child(label)
	return label

static func play_unlock(tower: Node2D) -> void:
	tower.scale = Vector2(0.15, 0.15)
	tower.modulate.a = 0.0
	var tw := tower.create_tween()
	tw.set_parallel(true)
	tw.tween_property(tower, "scale", Vector2.ONE, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(tower, "modulate:a", 1.0, 0.22)

static func aim_turret(turret: Node2D, target: Node2D, delta: float, speed: float = 14.0) -> void:
	if turret == null:
		return
	var desired: float = -PI / 2.0
	if target:
		desired = turret.global_position.direction_to(target.global_position).angle()
	turret.rotation = lerp_angle(turret.rotation, desired, 1.0 - exp(-speed * delta))

static func make_beam(parent: Node2D, width: float, color: Color, z: int = 8) -> Line2D:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.visible = false
	line.z_index = z
	parent.add_child(line)
	return line

static func fade_lines(tower: Node2D, lines: Array, fade_times: Array, callback: Callable = Callable()) -> Tween:
	var tw := tower.create_tween()
	tw.set_parallel(true)
	for i in lines.size():
		var line: Line2D = lines[i]
		if line == null:
			continue
		var t: float = fade_times[i] if i < fade_times.size() else 0.1
		tw.tween_property(line, "modulate:a", 0.0, t)
	if callback.is_valid():
		tw.chain().tween_callback(callback)
	return tw

static func show_beam_lines(lines: Array, from_local: Vector2, to_local: Vector2) -> void:
	var pts := PackedVector2Array([from_local, to_local])
	for line in lines:
		if line == null:
			continue
		line.visible = true
		line.points = pts
		line.modulate.a = line.default_color.a

static func impact_burst(parent: Node2D, at_local: Vector2, core: Color, hot: Color) -> void:
	var flash := Polygon2D.new()
	flash.polygon = scale_poly(hex_points(10, 8), Vector2(1, 1))
	flash.position = at_local
	flash.color = Color(hot.r, hot.g, hot.b, 0.85)
	flash.z_index = 9
	parent.add_child(flash)

	var ring := Line2D.new()
	ring.points = ellipse_points(Vector2(12, 12), 16)
	ring.position = at_local
	ring.width = 2.5
	ring.default_color = Color(core.r, core.g, core.b, 0.7)
	ring.closed = true
	ring.z_index = 8
	parent.add_child(ring)

	var tw := parent.create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "scale", Vector2(2.0, 2.0), 0.1)
	tw.tween_property(flash, "modulate:a", 0.0, 0.1)
	tw.tween_property(ring, "scale", Vector2(2.5, 2.5), 0.12)
	tw.tween_property(ring, "modulate:a", 0.0, 0.12)
	tw.chain().tween_callback(func():
		if is_instance_valid(flash):
			flash.queue_free()
		if is_instance_valid(ring):
			ring.queue_free()
	)

static func muzzle_sparks(muzzle: Node2D, core: Color, hot: Color, count: int = 6) -> void:
	if muzzle == null:
		return
	for i in count:
		var spark := Polygon2D.new()
		spark.polygon = scale_poly(hex_points(2.0, 4), Vector2(1, 1))
		spark.color = hot if i % 2 == 0 else core
		spark.position = Vector2(randf_range(-2, 2), randf_range(-2, 2))
		muzzle.add_child(spark)
		var tw := muzzle.create_tween()
		var dir := Vector2.from_angle(randf() * TAU) * randf_range(10, 22)
		tw.tween_property(spark, "position", spark.position + dir, 0.07)
		tw.parallel().tween_property(spark, "modulate:a", 0.0, 0.07)
		tw.tween_callback(spark.queue_free)

	var ring := Line2D.new()
	ring.points = ellipse_points(Vector2(8, 8), 12)
	ring.width = 2.0
	ring.default_color = Color(hot.r, hot.g, hot.b, 0.9)
	ring.closed = true
	muzzle.add_child(ring)
	var rtw := muzzle.create_tween()
	rtw.tween_property(ring, "scale", Vector2(2.2, 2.2), 0.07)
	rtw.parallel().tween_property(ring, "modulate:a", 0.0, 0.07)
	rtw.tween_callback(ring.queue_free)

static func add_housing_edge(turret: Node2D, poly: PackedVector2Array) -> void:
	var edge := Line2D.new()
	edge.points = poly
	edge.width = 1.5
	edge.default_color = HULL_LIT
	edge.closed = true
	turret.add_child(edge)

static func _shadow_radius(style: BaseStyle) -> float:
	match style:
		BaseStyle.HEAVY: return 28.0
		BaseStyle.RAIL: return 30.0
		BaseStyle.COMPACT: return 18.0
		_: return 22.0

static func _mount_radius(style: BaseStyle) -> float:
	match style:
		BaseStyle.HEAVY: return 12.0
		BaseStyle.RAIL: return 11.0
		BaseStyle.COMPACT: return 8.0
		_: return 10.0

static func _platform_poly(style: BaseStyle) -> PackedVector2Array:
	match style:
		BaseStyle.HEAVY:
			return PackedVector2Array([
				Vector2(-32, 10), Vector2(-28, 16), Vector2(28, 16), Vector2(32, 10),
				Vector2(26, -2), Vector2(-26, -2)
			])
		BaseStyle.TRIPOD:
			return PackedVector2Array([
				Vector2(-20, 8), Vector2(-16, 14), Vector2(16, 14), Vector2(20, 8),
				Vector2(14, -2), Vector2(-14, -2)
			])
		BaseStyle.RAIL:
			return PackedVector2Array([
				Vector2(-34, 8), Vector2(-30, 14), Vector2(30, 14), Vector2(34, 8),
				Vector2(28, -2), Vector2(-28, -2)
			])
		BaseStyle.COMPACT:
			return PackedVector2Array([
				Vector2(-18, 8), Vector2(-14, 13), Vector2(14, 13), Vector2(18, 8),
				Vector2(12, -2), Vector2(-12, -2)
			])
		_:
			return PackedVector2Array([
				Vector2(-26, 8), Vector2(-22, 14), Vector2(22, 14), Vector2(26, 8),
				Vector2(20, -2), Vector2(-20, -2)
			])

static func _platform_extras(style: BaseStyle) -> Array:
	var out: Array = []
	match style:
		BaseStyle.HEAVY:
			var rim := Line2D.new()
			rim.points = PackedVector2Array([
				Vector2(-30, 8), Vector2(-26, 14), Vector2(26, 14), Vector2(30, 8)
			])
			rim.width = 2.0
			rim.default_color = HULL_LIT
			out.append(rim)
			for side in [-1, 1]:
				var pad := Polygon2D.new()
				pad.polygon = PackedVector2Array([
					Vector2(-8 * side, 12), Vector2(-14 * side, 16), Vector2(-10 * side, 18), Vector2(-4 * side, 14)
				])
				pad.color = HULL_LIT.darkened(0.2)
				out.append(pad)
		BaseStyle.TRIPOD:
			for ang in [-120.0, 0.0, 120.0]:
				var leg := Polygon2D.new()
				var a := deg_to_rad(ang)
				var tip := Vector2(cos(a), sin(a)) * 22.0 + Vector2(0, 10)
				leg.polygon = PackedVector2Array([
					Vector2(-3, 8), Vector2(3, 8), tip + Vector2(2, 0), tip + Vector2(-2, 0)
				])
				leg.color = HULL_LIT.darkened(0.15)
				out.append(leg)
		BaseStyle.RAIL:
			for side in [-1, 1]:
				var rail := Polygon2D.new()
				rail.polygon = PackedVector2Array([
					Vector2(-30 * side, 4), Vector2(-34 * side, 6), Vector2(-34 * side, -6), Vector2(-30 * side, -4)
				])
				rail.color = HULL_LIT.darkened(0.1)
				out.append(rail)
				var cap := Polygon2D.new()
				cap.polygon = scale_poly(hex_points(3, 6), Vector2(1, 1))
				cap.position = Vector2(-32 * side, -5)
				cap.color = Color(0.3, 0.85, 1.0, 0.7)
				out.append(cap)
		BaseStyle.COMPACT:
			var tank := Polygon2D.new()
			tank.polygon = PackedVector2Array([
				Vector2(-16, 6), Vector2(-14, 2), Vector2(14, 2), Vector2(16, 6), Vector2(12, 10), Vector2(-12, 10)
			])
			tank.color = HULL_DARK
			out.append(tank)
		_:
			for side in [-1, 1]:
				var strut := Polygon2D.new()
				strut.polygon = PackedVector2Array([
					Vector2(24 * side, 10), Vector2(32 * side, 16), Vector2(28 * side, 18), Vector2(18 * side, 12)
				])
				strut.color = HULL_LIT.darkened(0.15)
				out.append(strut)
			var rim2 := Line2D.new()
			rim2.points = PackedVector2Array([
				Vector2(-24, 6), Vector2(-20, 12), Vector2(20, 12), Vector2(24, 6)
			])
			rim2.width = 2.0
			rim2.default_color = HULL_LIT
			out.append(rim2)
	return out
