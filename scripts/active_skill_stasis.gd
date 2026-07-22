extends Node2D

## STASIS ZONE — active skill. Arm with the left-side button, then click
## anywhere to place a field that slows enemies 70% and deals light DoT.
## Zone lasts 6s; 15s cooldown from placement.

const COOLDOWN := 15.0
const DURATION := 6.0
const SLOW_FACTOR := 0.30  ## 70% slow → move at 30% speed
const BTN_RADIUS := 30.0
const ZONE_W_FRAC := 4.40  ## previous 0.88 × 5
const ZONE_H_FRAC := 0.26
const DOT_INTERVAL := 0.45
const DOT_DAMAGE := 6

const CORE := Color(0.35, 0.85, 1.0)
const ACTIVE := Color(0.45, 0.95, 1.0)
const ARMED_COLOR := Color(0.55, 0.9, 1.0)

var _arena: Vector2 = Vector2(720, 1280)
var _zone_size: Vector2 = Vector2(600, 320)
var _zone_rect: Rect2 = Rect2()
var _cooldown_left: float = 0.0
var _active_left: float = 0.0
var _dot_cd: float = 0.0
var _armed: bool = false
var _button: Control
var _zone_visual: Node2D
var _zone_fill: Polygon2D
var _ghost: Node2D
var _pulse_t: float = 0.0

func setup(_player: CharacterBody2D, _wm: Node, ui_layer: CanvasLayer, arena: Vector2) -> void:
	_arena = arena
	_zone_size = Vector2(arena.x * ZONE_W_FRAC, arena.y * ZONE_H_FRAC)
	z_index = 4
	add_to_group("stasis_zone")
	_build_button(ui_layer)
	_build_zone_visual()
	_build_ghost()

func get_slow_for(world_pos: Vector2) -> float:
	if _active_left <= 0.0:
		return 1.0
	if _zone_rect.has_point(world_pos):
		return SLOW_FACTOR
	return 1.0

func reset_cooldown() -> void:
	_cooldown_left = 0.0
	if _button:
		_button.queue_redraw()

func _build_button(ui_layer: CanvasLayer) -> void:
	_button = Control.new()
	var d := BTN_RADIUS * 2.0 + 8.0
	_button.custom_minimum_size = Vector2(d, d)
	_button.size = Vector2(d, d)
	_button.position = Vector2(12.0, _arena.y * 0.52 - d * 0.5 + 72.0)
	_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_button.gui_input.connect(_on_button_input)
	_button.draw.connect(_draw_button)
	ui_layer.add_child(_button)

func _on_button_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_button.accept_event()
		if _cooldown_left > 0.0 or _active_left > 0.0:
			return
		_armed = not _armed
		if _ghost:
			_ghost.visible = _armed
		_button.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not _armed or get_tree().paused:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_place_at(get_global_mouse_position())
		get_viewport().set_input_as_handled()

func _place_at(world_pos: Vector2) -> void:
	_armed = false
	if _ghost:
		_ghost.visible = false
	_zone_rect = _clamped_rect_at(world_pos)
	_sync_zone_visual()
	_active_left = DURATION
	_cooldown_left = COOLDOWN
	_dot_cd = 0.0
	if _zone_visual:
		_zone_visual.visible = true
	_button.queue_redraw()

func _clamped_rect_at(center: Vector2) -> Rect2:
	var pos := center - _zone_size * 0.5
	# Wider than the arena: keep centered on X so the field always covers the playfield.
	if _zone_size.x >= _arena.x - 16.0:
		pos.x = (_arena.x - _zone_size.x) * 0.5
	else:
		pos.x = clampf(pos.x, 8.0, maxf(8.0, _arena.x - _zone_size.x - 8.0))
	pos.y = clampf(pos.y, 40.0, maxf(40.0, _arena.y - _zone_size.y - 80.0))
	return Rect2(pos, _zone_size)

func _sync_zone_visual() -> void:
	if _zone_visual == null:
		return
	_zone_visual.position = _zone_rect.position
	var sz := _zone_rect.size
	if _zone_fill:
		_zone_fill.polygon = PackedVector2Array([
			Vector2.ZERO, Vector2(sz.x, 0.0), sz, Vector2(0.0, sz.y)
		])

func _build_zone_visual() -> void:
	_zone_visual = Node2D.new()
	_zone_visual.z_index = 3
	_zone_visual.visible = false
	add_child(_zone_visual)

	_zone_fill = Polygon2D.new()
	_zone_fill.color = Color(CORE.r, CORE.g, CORE.b, 0.14)
	_zone_visual.add_child(_zone_fill)
	_sync_zone_visual()

func _build_ghost() -> void:
	_ghost = Node2D.new()
	_ghost.z_index = 30
	_ghost.visible = false
	add_child(_ghost)

	var fill := Polygon2D.new()
	fill.polygon = PackedVector2Array([
		-_zone_size * 0.5,
		Vector2(_zone_size.x * 0.5, -_zone_size.y * 0.5),
		_zone_size * 0.5,
		Vector2(-_zone_size.x * 0.5, _zone_size.y * 0.5)
	])
	fill.color = Color(ARMED_COLOR.r, ARMED_COLOR.g, ARMED_COLOR.b, 0.12)
	_ghost.add_child(fill)

func _apply_dot() -> void:
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or enemy.get("is_dying") == true:
			continue
		if not _zone_rect.has_point(enemy.global_position):
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(DOT_DAMAGE)

func _draw_button() -> void:
	var c := _button.size * 0.5
	_button.draw_circle(c, BTN_RADIUS, Color(0.05, 0.08, 0.14, 0.95))

	var ready := _cooldown_left <= 0.0 and _active_left <= 0.0
	var tint := Color(CORE.r, CORE.g, CORE.b, 1.0) if ready or _active_left > 0.0 or _armed else Color(0.45, 0.5, 0.6, 0.85)
	var icon := Rect2(c.x - 14.0, c.y - 10.0, 28.0, 20.0)
	_button.draw_rect(icon, Color(tint.r, tint.g, tint.b, 0.25), true)
	_button.draw_rect(icon, tint, false, 2.0)

	if _cooldown_left > 0.0:
		var frac := 1.0 - _cooldown_left / COOLDOWN
		_button.draw_arc(c, BTN_RADIUS - 4.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 40, Color(CORE.r, CORE.g, CORE.b, 0.35), 6.0)

	var rim: Color
	if _armed:
		var glow := 0.6 + 0.4 * sin(_pulse_t * 7.0)
		rim = Color(ARMED_COLOR.r, ARMED_COLOR.g, ARMED_COLOR.b, glow)
		_button.draw_arc(c, BTN_RADIUS + 3.5, 0.0, TAU, 48, Color(ARMED_COLOR.r, ARMED_COLOR.g, ARMED_COLOR.b, glow * 0.45), 3.0)
	elif _active_left > 0.0:
		var glow2 := 0.6 + 0.4 * sin(_pulse_t * 7.0)
		rim = Color(ACTIVE.r, ACTIVE.g, ACTIVE.b, glow2)
	elif _cooldown_left <= 0.0:
		rim = Color(CORE.r, CORE.g, CORE.b, 0.9)
	else:
		rim = Color(0.4, 0.45, 0.55, 0.8)
	_button.draw_arc(c, BTN_RADIUS, 0.0, TAU, 48, rim, 2.5)

	var font := ThemeDB.fallback_font
	if _cooldown_left > 0.0 and _active_left <= 0.0:
		var secs := str(int(ceil(_cooldown_left)))
		_button.draw_string(font, c + Vector2(-BTN_RADIUS, 5.0), secs, HORIZONTAL_ALIGNMENT_CENTER, BTN_RADIUS * 2.0, 18, Color(0.9, 0.95, 1.0))

func _process(delta: float) -> void:
	_pulse_t += delta
	if _armed and _ghost:
		_ghost.global_position = get_global_mouse_position()
		var pulse := 1.0 + sin(_pulse_t * 5.0) * 0.03
		_ghost.scale = Vector2(pulse, pulse)
	if _active_left > 0.0:
		_active_left = maxf(0.0, _active_left - delta)
		_dot_cd -= delta
		if _dot_cd <= 0.0:
			_dot_cd = DOT_INTERVAL
			_apply_dot()
		if _zone_visual:
			_zone_visual.visible = _active_left > 0.0
			_zone_visual.modulate.a = 0.85 + 0.15 * sin(_pulse_t * 4.0)
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if _button:
		_button.queue_redraw()
