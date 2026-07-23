extends "res://scripts/enemy.gd"

## Kamikaze — suicide diver. Starts fast and keeps accelerating (+gain
## every 0.1s). Five red orbs orbit it; one pops every 0.5s (or instantly
## when shot down), and each pop makes the ship dash diagonally with a
## ~20 degree course change — but never one that would carry it off the
## map. If it reaches the base it explodes, damaging the fortress and
## stunning the player for 1 second.

const ORB_SCRIPT := preload("res://scripts/enemy_ship_kamikaze_orb.gd")
const SFX_SPAWN_PATH := "res://assets/sound_effects/kamikaze_spawn.wav"
const SFX_DEATH_PATH := "res://assets/sound_effects/kamikaze_death.wav"

const SHIP_TYPE := {
	"id": "kamikaze",
	"category": "ship",
	"texture": "res://assets/sprites/enemy_ship_2.png",
	"sprite_scale": 0.04,
	"collision": Vector2(64, 70),
	"xp": 15
}

const ORB_COUNT := 5
const ORB_ORBIT_RADIUS := 52.0
const ORB_ORBIT_SPEED := 2.2
## Seconds between automatic orb pops
const POP_INTERVAL := 0.5
## Speed gained every 0.1 seconds of flight
const SPEED_GAIN := 2.5
## Extra burst speed added by each pop's dash (decays quickly)
const DASH_BOOST := 260.0
const DASH_DECAY := 620.0
## Course change per pop, in degrees
const TURN_DEGREES := 38.0
## Consecutive same-direction dodges must differ by at least this fraction
const MIN_DODGE_DIFF := 0.4
const TURN_MIN_DEG := 14.0
const TURN_MAX_DEG := 55.0
## Heading may never lean more than this away from straight down
const MAX_LEAN_DEG := 75.0
const EDGE_MARGIN := 60.0
const STUN_DURATION := 1.0

var boom_damage: int = 30
var _heading := Vector2.DOWN
## Signed turn (radians) of the previous dodge — the next dodge must
## differ from it by at least MIN_DODGE_DIFF (40%).
var _last_turn: float = 0.0
var _dash: float = 0.0
var _speed_timer: float = 0.0
var _pop_timer: float = POP_INTERVAL
var _orbs: Array = []
var _orbit_angle: float = 0.0
var _arena_w: float = 720.0

func _ready() -> void:
	super()
	apply_enemy_type(SHIP_TYPE)

## Called by the wave manager after setup_descent.
func setup_kamikaze(orb_hp: int, explode_damage: int) -> void:
	boom_damage = explode_damage
	if fortress:
		_arena_w = fortress.global_position.x * 2.0
		_heading = (fortress.global_position - global_position).normalized()
		_clamp_heading()
	for i in ORB_COUNT:
		var orb := StaticBody2D.new()
		orb.set_script(ORB_SCRIPT)
		add_child(orb)
		orb.setup(self, orb_hp)
		_orbs.append(orb)
	_place_orbs()
	_play_sfx(SFX_SPAWN_PATH, false)

func _physics_process(delta):
	if is_dying:
		return

	if stun_timer > 0.0:
		stun_timer -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		_process_burn(delta)
		return

	_fall_time += delta

	# Speed climbs every 0.1s of flight
	_speed_timer += delta
	while _speed_timer >= 0.1:
		_speed_timer -= 0.1
		speed += SPEED_GAIN

	# Automatic orb pop cadence
	if not _orbs.is_empty():
		_pop_timer -= delta
		if _pop_timer <= 0.0:
			_pop_orb(_orbs[0])

	_dash = move_toward(_dash, 0.0, DASH_DECAY * delta)
	velocity = _heading * (speed + _dash) * get_move_speed_scale() + Vector2(0.0, pull_force.y)
	pull_force = Vector2(0.0, lerpf(pull_force.y, 0.0, 8.0 * delta))
	move_and_slide()
	global_position.x = clampf(global_position.x, 40.0, _arena_w - 40.0)

	_orbit_angle += ORB_ORBIT_SPEED * delta
	_place_orbs()
	_update_fall_visual()
	_process_burn(delta)

	if global_position.y >= _leak_line_y():
		_explode_on_base()

## Steady dive — no UFO spin.
func _update_fall_visual() -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var pulse: float = 1.0 + sin(_fall_time * 5.0) * 0.03
	sprite.scale = _base_sprite_scale * pulse
	# Nose leans into the travel direction
	sprite.rotation = _heading.angle() - PI / 2.0
	if sprite.modulate.a >= 0.99:
		sprite.modulate = Color.WHITE

func _place_orbs() -> void:
	var alive := _orbs.size()
	if alive == 0:
		return
	for i in alive:
		var orb = _orbs[i]
		if not is_instance_valid(orb):
			continue
		var a: float = _orbit_angle + TAU * float(i) / float(alive)
		orb.position = Vector2.from_angle(a) * ORB_ORBIT_RADIUS
		orb.set_pulse(_fall_time)

## An orb was shot to zero HP — pop immediately.
func _on_orb_shot(orb: Node2D) -> void:
	if is_dying:
		return
	_pop_orb(orb)

func _pop_orb(orb: Node2D) -> void:
	_orbs.erase(orb)
	_pop_timer = POP_INTERVAL
	if is_instance_valid(orb):
		_spawn_pop_fx(orb.global_position)
		orb.queue_free()
	_dash_turn()

## The signature move: a sharp diagonal course change + a short dash,
## never repeating the previous dodge (>=40% different) and never
## letting the projected landing point leave the arena.
func _dash_turn() -> void:
	var mag := deg_to_rad(TURN_DEGREES + randf_range(-8.0, 8.0))
	var dir := 1.0 if randf() < 0.5 else -1.0

	# Same direction as the last dodge? The angle must differ by >=40%.
	# (Opposite-direction dodges always differ far more than that.)
	if _last_turn != 0.0 and dir == signf(_last_turn):
		var prev := absf(_last_turn)
		if absf(mag - prev) < prev * MIN_DODGE_DIFF:
			var bigger := prev * (1.0 + MIN_DODGE_DIFF)
			var smaller := prev * (1.0 - MIN_DODGE_DIFF)
			# One of the two always fits inside the turn range
			if bigger <= deg_to_rad(TURN_MAX_DEG) and (smaller < deg_to_rad(TURN_MIN_DEG) or randf() < 0.5):
				mag = bigger
			else:
				mag = smaller

	if not _destination_in_bounds(_heading.rotated(mag * dir)):
		dir = -dir
	var new_heading := _heading.rotated(mag * dir)
	if not _destination_in_bounds(new_heading):
		# Both sides would drift out — lock onto the base center instead
		new_heading = (Vector2(_arena_w * 0.5, _leak_line_y()) - global_position).normalized()
		_last_turn = 0.0
	else:
		_last_turn = mag * dir
	_heading = new_heading
	_clamp_heading()
	_dash = DASH_BOOST

func _clamp_heading() -> void:
	# Always downward, never leaning past MAX_LEAN_DEG from vertical
	var down := PI / 2.0
	var ang := clampf(_heading.angle(), down - deg_to_rad(MAX_LEAN_DEG), down + deg_to_rad(MAX_LEAN_DEG))
	_heading = Vector2.from_angle(ang)

func _leak_line_y() -> float:
	if fortress and fortress.has_method("get_leak_y"):
		return float(fortress.get_leak_y())
	return 1180.0

## Would this heading keep the ship inside the map?
## While more pops remain, only the stretch until the next dodge matters
## (the course changes again anyway). Only the final pop checks the full
## path down to the base line.
func _destination_in_bounds(heading: Vector2) -> bool:
	if heading.y <= 0.05:
		return false
	var travel_y: float = _leak_line_y() - global_position.y
	if not _orbs.is_empty():
		var look_ahead: float = (speed + DASH_BOOST) * POP_INTERVAL * 1.5
		travel_y = minf(travel_y, heading.y * look_ahead)
	var x_ahead: float = global_position.x + heading.x / heading.y * travel_y
	return x_ahead >= EDGE_MARGIN and x_ahead <= _arena_w - EDGE_MARGIN

func _spawn_pop_fx(at: Vector2) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var burst := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 10:
		pts.append(Vector2.from_angle(float(i) / 10.0 * TAU) * 10.0)
	burst.polygon = pts
	burst.position = at
	burst.color = Color(1.0, 0.4, 0.3, 0.9)
	burst.z_index = 15
	scene.add_child(burst)
	var tw := burst.create_tween()
	tw.tween_property(burst, "scale", Vector2(2.6, 2.6), 0.2)
	tw.parallel().tween_property(burst, "modulate:a", 0.0, 0.2)
	tw.tween_callback(burst.queue_free)

## Reached the base: big hit on the fortress + 1s player stun.
func _explode_on_base() -> void:
	if is_dying:
		return
	is_dying = true
	for orb in _orbs:
		if is_instance_valid(orb):
			orb.is_dying = true
	if fortress and fortress.has_method("take_damage"):
		var mult: float = 1.0
		if "leak_damage_mult" in fortress:
			mult = float(fortress.leak_damage_mult)
		fortress.take_damage(maxi(1, int(round(float(boom_damage) * mult))))
	if player and is_instance_valid(player) and player.has_method("apply_stun"):
		player.apply_stun(STUN_DURATION)
	_play_sfx(SFX_DEATH_PATH, true)
	_spawn_boom_fx()
	queue_free()

func _spawn_boom_fx() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var core := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 20:
		pts.append(Vector2.from_angle(float(i) / 20.0 * TAU) * 40.0)
	core.polygon = pts
	core.position = global_position
	core.color = Color(1.0, 0.55, 0.25, 0.9)
	core.z_index = 16
	scene.add_child(core)
	var ctw := core.create_tween()
	ctw.tween_property(core, "scale", Vector2(4.5, 4.5), 0.3)
	ctw.parallel().tween_property(core, "modulate:a", 0.0, 0.3)
	ctw.tween_callback(core.queue_free)

	var ring := Line2D.new()
	var rpts := PackedVector2Array()
	for j in 29:
		rpts.append(Vector2.from_angle(float(j) / 28.0 * TAU) * 40.0)
	ring.points = rpts
	ring.width = 5.0
	ring.default_color = Color(1.0, 0.35, 0.2, 0.85)
	ring.closed = true
	ring.position = global_position
	ring.z_index = 16
	scene.add_child(ring)
	var rtw := ring.create_tween()
	rtw.tween_property(ring, "scale", Vector2(5.0, 5.0), 0.35)
	rtw.parallel().tween_property(ring, "modulate:a", 0.0, 0.35)
	rtw.tween_callback(ring.queue_free)

## Killed before reaching the base — orbs die with the ship, no explosion.
func die():
	if is_dying:
		return
	for orb in _orbs:
		if is_instance_valid(orb):
			orb.is_dying = true
	_play_sfx(SFX_DEATH_PATH, true)
	super()

func _play_sfx(path: String, detach: bool) -> void:
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "Enemy"
	player.volume_db = -4.0
	var host: Node = self
	if detach:
		var scene := get_tree().current_scene if is_inside_tree() else null
		if scene == null:
			return
		host = scene
	host.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
