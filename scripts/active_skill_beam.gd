extends Node2D

## BEAM — first active skill. Unlocked in the skill tree (Active Skills
## column). A round ability button sits on the left side of the screen:
## press it to arm the skill (button + aiming reticle light up), then
## click anywhere on the field to fire a laser-tower-style beam from the
## player's gun head through every enemy on that line. 25s cooldown;
## damage scales with wave so it can one-shot the Carrier mother ship.

const V := preload("res://scripts/towers/tower_visuals.gd")
const BTN_ICON_PATH := "res://assets/png/skill_icons/Beam.png"

const CORE := Color(0.35, 1.0, 0.55)
const HOT := Color(0.85, 1.0, 0.35)
const ARMED_COLOR := Color(0.8, 0.5, 1.0)

const COOLDOWN := 10.0
## Enemies within this distance of the beam line get hit
const BEAM_HALF_WIDTH := 46.0
const BEAM_LENGTH := 2600.0
const BTN_RADIUS := 30.0

var player: CharacterBody2D
var wave_manager: Node

var _cooldown_left: float = 0.0
var _armed: bool = false
var _beams: Array[Line2D] = []
var _beam_tween: Tween
var _button: Control
var _btn_icon: Texture2D
var _reticle: Node2D
var _pulse_t: float = 0.0

func setup(p: CharacterBody2D, wm: Node, ui_layer: CanvasLayer, arena: Vector2) -> void:
	player = p
	wave_manager = wm
	z_index = 20
	_beams = [
		V.make_beam(self, 26.0, Color(CORE.r, CORE.g, CORE.b, 0.12), 6),
		V.make_beam(self, 14.0, Color(CORE.r, CORE.g, CORE.b, 0.35), 7),
		V.make_beam(self, 6.0, Color(1.0, 1.0, 0.95, 0.95), 8)
	]
	_build_button(ui_layer, arena)
	_build_reticle()

## --- Ability button (left side of the screen) ---

func _build_button(ui_layer: CanvasLayer, arena: Vector2) -> void:
	if ResourceLoader.exists(BTN_ICON_PATH):
		_btn_icon = load(BTN_ICON_PATH)
	_button = Control.new()
	var d := BTN_RADIUS * 2.0 + 8.0
	_button.custom_minimum_size = Vector2(d, d)
	_button.size = Vector2(d, d)
	_button.position = Vector2(12.0, arena.y * 0.52 - d * 0.5)
	_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_button.gui_input.connect(_on_button_input)
	_button.draw.connect(_draw_button)
	ui_layer.add_child(_button)

func _on_button_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _cooldown_left > 0.0:
			return
		_armed = not _armed
		if _reticle:
			_reticle.visible = _armed
		_button.queue_redraw()
		_button.accept_event()

func _draw_button() -> void:
	var c := _button.size * 0.5
	# Body
	_button.draw_circle(c, BTN_RADIUS, Color(0.05, 0.08, 0.14, 0.95))
	# Skill icon art (dimmed while recharging)
	if _btn_icon:
		var icon_half := BTN_RADIUS - 4.0
		var tint := Color.WHITE if _cooldown_left <= 0.0 else Color(0.45, 0.45, 0.55, 0.85)
		_button.draw_texture_rect(_btn_icon, Rect2(c - Vector2(icon_half, icon_half), Vector2(icon_half, icon_half) * 2.0), false, tint)
	# Cooldown sweep (fills back up clockwise as the skill recharges)
	if _cooldown_left > 0.0:
		var frac := 1.0 - _cooldown_left / COOLDOWN
		_button.draw_arc(c, BTN_RADIUS - 4.0, -PI / 2.0, -PI / 2.0 + TAU * frac, 40, Color(CORE.r, CORE.g, CORE.b, 0.35), 6.0)
	# Rim: purple glow while armed, green when ready, grey while cooling
	var rim: Color
	if _armed:
		var glow := 0.6 + 0.4 * sin(_pulse_t * 7.0)
		rim = Color(ARMED_COLOR.r, ARMED_COLOR.g, ARMED_COLOR.b, glow)
		_button.draw_arc(c, BTN_RADIUS + 3.5, 0.0, TAU, 48, Color(ARMED_COLOR.r, ARMED_COLOR.g, ARMED_COLOR.b, glow * 0.5), 3.0)
	elif _cooldown_left <= 0.0:
		rim = Color(CORE.r, CORE.g, CORE.b, 0.9)
	else:
		rim = Color(0.4, 0.45, 0.55, 0.8)
	_button.draw_arc(c, BTN_RADIUS, 0.0, TAU, 48, rim, 2.5)

	var font := ThemeDB.fallback_font
	if _cooldown_left > 0.0:
		var secs := str(int(ceil(_cooldown_left)))
		_button.draw_string(font, c + Vector2(-BTN_RADIUS, 5.0), secs, HORIZONTAL_ALIGNMENT_CENTER, BTN_RADIUS * 2.0, 18, Color(0.9, 0.95, 1.0))
	elif _btn_icon == null:
		_button.draw_string(font, c + Vector2(-BTN_RADIUS, 4.0), "BEAM", HORIZONTAL_ALIGNMENT_CENTER, BTN_RADIUS * 2.0, 12, Color(0.85, 1.0, 0.9))

## --- Targeting reticle (follows the mouse while armed) ---

func _build_reticle() -> void:
	_reticle = Node2D.new()
	_reticle.z_index = 30
	_reticle.visible = false
	add_child(_reticle)

	var fill := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 24:
		pts.append(Vector2.from_angle(float(i) / 24.0 * TAU) * 26.0)
	fill.polygon = pts
	fill.color = Color(ARMED_COLOR.r, ARMED_COLOR.g, ARMED_COLOR.b, 0.15)
	_reticle.add_child(fill)

	var ring := Line2D.new()
	var rpts := pts.duplicate()
	rpts.append(pts[0])
	ring.points = rpts
	ring.width = 2.5
	ring.default_color = Color(ARMED_COLOR.r, ARMED_COLOR.g, ARMED_COLOR.b, 0.9)
	_reticle.add_child(ring)

	var dot := Polygon2D.new()
	var dpts := PackedVector2Array()
	for i in 10:
		dpts.append(Vector2.from_angle(float(i) / 10.0 * TAU) * 3.0)
	dot.polygon = dpts
	dot.color = Color(1.0, 1.0, 1.0, 0.9)
	_reticle.add_child(dot)

## Sandbox helper — instantly ready again.
func reset_cooldown() -> void:
	_cooldown_left = 0.0
	if _button:
		_button.queue_redraw()

func _process(delta: float) -> void:
	_pulse_t += delta
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(0.0, _cooldown_left - delta)
	if _armed and _reticle:
		_reticle.global_position = get_global_mouse_position()
		var pulse := 1.0 + sin(_pulse_t * 6.0) * 0.08
		_reticle.scale = Vector2(pulse, pulse)
	if _button:
		_button.queue_redraw()

## Armed click anywhere on the field fires the beam at that point.
func _unhandled_input(event: InputEvent) -> void:
	if not _armed or get_tree().paused:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_fire_at(get_global_mouse_position())
		get_viewport().set_input_as_handled()

## --- Firing ---

## Scales with wave/stage just ahead of the Carrier's HP formula
## ((190 + 27.5w) * mult), so a fresh beam always one-shots the mother ship.
func _beam_damage() -> int:
	var wave: int = 0
	var mult: float = 1.0
	if wave_manager:
		wave = int(wave_manager.wave)
		mult = float(wave_manager._stage_hp_mult())
	return int((240.0 + 34.0 * float(wave)) * mult)

func _fire_at(target: Vector2) -> void:
	_armed = false
	_cooldown_left = COOLDOWN
	if _reticle:
		_reticle.visible = false

	var origin: Vector2 = player.global_position
	if player.bullet_spawn_pos and is_instance_valid(player.bullet_spawn_pos):
		origin = player.bullet_spawn_pos.global_position
	var dir := (target - origin)
	if dir.length() < 1.0:
		dir = Vector2.UP
	dir = dir.normalized()
	var end := origin + dir * BEAM_LENGTH

	# Swing the character's gun toward the shot
	if player.has_method("_aim_at"):
		player._aim_at(target)

	# Pierce: every living enemy near the origin→end line takes full damage
	var dmg := _beam_damage()
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or enemy.get("is_dying") == true:
			continue
		var p: Vector2 = enemy.global_position
		var closest := Geometry2D.get_closest_point_to_segment(p, origin, end)
		if p.distance_to(closest) > BEAM_HALF_WIDTH:
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(dmg)
		V.impact_burst(self, to_local(closest), CORE, HOT)

	V.show_beam_lines(_beams, to_local(origin), to_local(end))
	if _beam_tween and _beam_tween.is_valid():
		_beam_tween.kill()
	_beam_tween = V.fade_lines(self, _beams, [0.22, 0.28, 0.34], func():
		for line in _beams:
			if is_instance_valid(line):
				line.visible = false
	)
	V.impact_burst(self, to_local(target), CORE, HOT)
