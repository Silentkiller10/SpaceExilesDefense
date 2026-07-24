extends "res://scripts/towers/tower_base.gd"

## Tesla coil — static sprite, chain lightning arcs across nearby enemies.

const V := preload("res://scripts/towers/tower_visuals.gd")
const TEX_PATH := "res://assets/Tesla Tower.png"
const SFX_PATH := "res://assets/sound_effects/tower_laser.wav"

const CORE := Color(0.35, 0.95, 1.0)
const HOT := Color(0.75, 1.0, 1.0)

const TOWER_SCALE := 0.792
const SPRITE_SCALE := 0.072 * TOWER_SCALE * 2.5 * 1.1
const FOOT_MARGIN := 14.0
const SHADOW_RADIUS := 22.0 * TOWER_SCALE
const LABEL_Y := 30.0 * TOWER_SCALE

## Extra enemies after the primary (3 jumps = 4 total hits).
const CHAIN_JUMPS_BASE := 3
const CHAIN_RANGE_BASE := 170.0
const CHAIN_FALLOFF_BASE := 0.72
const ARC_SEGMENTS := 6

var _sprite: Sprite2D
var _muzzle: Node2D
var _idle_t: float = 0.0
var _charge: float = 0.0
var _chain_jumps: int = CHAIN_JUMPS_BASE
var _chain_range: float = CHAIN_RANGE_BASE
var _chain_falloff: float = CHAIN_FALLOFF_BASE
var _sfx_player: AudioStreamPlayer

func _ready() -> void:
	## Mid-range zap; chains through a few enemies each discharge.
	configure("tesla", "Tesla", CORE, 1040.0, 0.55, 45)
	super._ready()

func unlock() -> void:
	super.unlock()
	V.play_unlock(self)

func apply_aoe_mult(mult_add: float) -> void:
	_chain_range *= (1.0 + mult_add)

func apply_chain_bonus(count: int = 1) -> void:
	_chain_jumps += count

func apply_chain_falloff_bonus(amount: float = 0.1) -> void:
	## Raise retained damage per jump (closer to 1.0 = less falloff).
	_chain_falloff = minf(0.95, _chain_falloff + amount)

func _build_visual() -> void:
	V.add_shadow(self, SHADOW_RADIUS)

	body = Polygon2D.new()
	body.visible = false
	add_child(body)

	var tex: Texture2D = load(TEX_PATH) as Texture2D
	_sprite = Sprite2D.new()
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_sprite.centered = false
	_sprite.position = Vector2(0.0, FOOT_MARGIN)
	_sprite.z_index = 1
	add_child(_sprite)

	_muzzle = Node2D.new()
	_sprite.add_child(_muzzle)
	_apply_tower_tex(tex)

	label = V.add_label(self, "TESLA", CORE, LABEL_Y)

func _apply_tower_tex(tex: Texture2D) -> void:
	if _sprite == null or tex == null:
		return
	_sprite.texture = tex
	var tex_size: Vector2 = tex.get_size()
	_sprite.offset = Vector2(-tex_size.x * 0.5, -tex_size.y)
	# Sphere tip is the discharge point.
	if _muzzle:
		_muzzle.position = Vector2(0.0, -tex_size.y * 0.94)

func _process(delta: float) -> void:
	if not unlocked or sandbox_disabled:
		return
	_idle_t += delta
	_charge = move_toward(_charge, 0.0, delta * 2.8)
	if _sprite:
		var pulse: float = 0.5 + 0.5 * sin(_idle_t * 6.0)
		var glow: float = 1.0 + pulse * 0.04 + _charge * 0.18
		_sprite.modulate = Color(glow, glow + 0.04, glow + 0.12, 1.0)
	super._process(delta)

func _fire(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	_charge = 1.0
	var hit: Array = [target]
	var cursor: Node2D = target
	for _i in _chain_jumps:
		var nxt := _find_chain_next(cursor, hit)
		if nxt == null:
			break
		hit.append(nxt)
		cursor = nxt

	var dmg: float = float(_scaled_damage())
	var from_g: Vector2 = _muzzle.global_position if _muzzle else global_position
	var prev_local: Vector2 = from_g - global_position
	for i in hit.size():
		var enemy: Node2D = hit[i]
		if enemy == null or not is_instance_valid(enemy):
			continue
		_hit_enemy(enemy, maxi(1, int(round(dmg))))
		var to_local: Vector2 = enemy.global_position - global_position
		_spawn_arc(prev_local, to_local, i == 0)
		V.impact_burst(self, to_local, CORE, HOT)
		prev_local = to_local
		dmg *= _chain_falloff

	V.muzzle_sparks(_muzzle, CORE, HOT, 8)
	_play_zap_sfx()

func _find_chain_next(from: Node2D, already: Array) -> Node2D:
	if from == null or not is_instance_valid(from):
		return null
	var best: Node2D = null
	var best_d: float = _chain_range
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		if enemy.get("is_dying") == true:
			continue
		if enemy in already:
			continue
		var d: float = from.global_position.distance_to(enemy.global_position)
		if d <= best_d:
			best_d = d
			best = enemy
	return best

func _spawn_arc(from_local: Vector2, to_local: Vector2, primary: bool) -> void:
	var pts := _jagged_points(from_local, to_local, ARC_SEGMENTS)
	var widths: Array = [28.0, 14.0, 6.4] if primary else [20.0, 9.6, 4.8]
	var alphas: Array = [0.22, 0.55, 0.95] if primary else [0.16, 0.45, 0.9]
	var lines: Array = []
	for i in widths.size():
		var line := Line2D.new()
		line.width = widths[i] * TOWER_SCALE
		line.default_color = Color(CORE.r, CORE.g, CORE.b, alphas[i]) if i < 2 else Color(HOT.r, HOT.g, HOT.b, alphas[i])
		line.points = pts
		line.z_index = 4 + i
		line.modulate.a = alphas[i]
		add_child(line)
		lines.append(line)
	var tw := create_tween()
	tw.set_parallel(true)
	for i in lines.size():
		var fade: float = 0.1 + float(i) * 0.03
		tw.tween_property(lines[i], "modulate:a", 0.0, fade)
	tw.chain().tween_callback(func():
		for line in lines:
			if is_instance_valid(line):
				line.queue_free()
	)

func _jagged_points(from_p: Vector2, to_p: Vector2, segments: int) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	var delta := to_p - from_p
	var normal := Vector2(-delta.y, delta.x)
	if normal.length_squared() > 0.0001:
		normal = normal.normalized()
	else:
		normal = Vector2.RIGHT
	pts.append(from_p)
	for i in range(1, segments):
		var t: float = float(i) / float(segments)
		var mid: Vector2 = from_p.lerp(to_p, t)
		var amp: float = 10.0 * (1.0 - absf(t - 0.5) * 1.4)
		mid += normal * randf_range(-amp, amp)
		pts.append(mid)
	pts.append(to_p)
	return pts

func _play_zap_sfx() -> void:
	if _sfx_player == null:
		var stream: AudioStream = load(SFX_PATH) as AudioStream
		if stream == null:
			return
		_sfx_player = AudioStreamPlayer.new()
		_sfx_player.stream = stream
		_sfx_player.bus = "Towers"
		_sfx_player.volume_db = -8.0
		add_child(_sfx_player)
	_sfx_player.pitch_scale = randf_range(1.15, 1.35)
	_sfx_player.play()
