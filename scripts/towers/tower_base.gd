extends Node2D
class_name TowerBase

@export var tower_id: String = "gatling"
@export var display_name: String = "Tower"
@export var range_px: float = 420.0
@export var cooldown: float = 0.4
@export var damage: int = 12
@export var neon_color: Color = Color(0.3, 0.9, 1.0)

var fortress: Node2D
var cd_left: float = 0.0
var unlocked: bool = false
var body: Polygon2D
var label: Label
var range_hint: Polygon2D

## Run upgrades for this tower only
var local_damage_mult: float = 1.0
var bonus_shots: int = 0

## Floor must sit below the fastest tower base CD (laser 0.04) or rate upgrades do nothing.
const MIN_COOLDOWN: float = 0.01

func _ready() -> void:
	_build_visual()
	visible = unlocked
	set_process(unlocked)

func configure(id: String, fname: String, color: Color, rng: float, cd: float, dmg: int) -> void:
	tower_id = id
	display_name = fname
	neon_color = color
	range_px = rng
	cooldown = cd
	damage = dmg
	if label:
		label.text = fname
	if body:
		body.color = neon_color

func bind_fortress(f: Node2D) -> void:
	fortress = f

func unlock() -> void:
	unlocked = true
	visible = true
	set_process(true)

func is_unlocked() -> bool:
	return unlocked

func apply_local_damage_mult(mult_add: float) -> void:
	local_damage_mult *= (1.0 + mult_add)

func apply_damage_penalty(penalty: float) -> void:
	local_damage_mult *= maxf(0.2, 1.0 - penalty)

func add_bonus_shots(count: int = 1) -> void:
	bonus_shots += count

func apply_range_mult(mult_add: float) -> void:
	range_px *= (1.0 + mult_add)

func apply_fire_rate_mult(mult_add: float) -> void:
	## Faster fire = lower cooldown
	cooldown = maxf(MIN_COOLDOWN, cooldown / (1.0 + mult_add))

func _build_visual() -> void:
	body = Polygon2D.new()
	body.polygon = PackedVector2Array([
		Vector2(-14, 10), Vector2(14, 10), Vector2(10, -16), Vector2(-10, -16)
	])
	body.color = neon_color
	add_child(body)

	var core := Polygon2D.new()
	core.polygon = PackedVector2Array([
		Vector2(-5, -4), Vector2(5, -4), Vector2(5, 4), Vector2(-5, 4)
	])
	core.color = Color(1, 1, 1, 0.85)
	add_child(core)

	label = Label.new()
	label.text = display_name
	label.position = Vector2(-28, 14)
	label.add_theme_font_size_override("font_size", 10)
	add_child(label)

func _process(delta: float) -> void:
	if not unlocked:
		return
	cd_left -= delta
	if cd_left > 0.0:
		return
	var shot_count: int = 1 + bonus_shots
	var targets: Array = _find_targets(shot_count)
	if targets.is_empty():
		return
	for target in targets:
		_fire(target)
	var cdr := 0.0
	if fortress:
		cdr = fortress.cooldown_reduction
	cd_left = maxf(MIN_COOLDOWN, cooldown * (1.0 - cdr))

func _find_target() -> Node2D:
	var targets := _find_targets(1)
	if targets.is_empty():
		return null
	return targets[0]

func _find_targets(count: int) -> Array:
	var candidates: Array = []
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy):
			continue
		if enemy.get("is_dying") == true:
			continue
		var d := global_position.distance_to(enemy.global_position)
		if d <= range_px:
			candidates.append(enemy)
	candidates.sort_custom(func(a, b): return a.global_position.y > b.global_position.y)
	var out: Array = []
	for i in mini(count, candidates.size()):
		out.append(candidates[i])
	# If we need more shots than targets, repeat the best target
	while out.size() < count and not candidates.is_empty():
		out.append(candidates[0])
	return out

func _scaled_damage() -> int:
	var mult := local_damage_mult
	if fortress:
		mult *= fortress.tower_damage_multiplier
	return maxi(1, int(round(float(damage) * mult)))

func _fire(_target: Node2D) -> void:
	pass

func _hit_enemy(enemy: Node2D, dmg: int, knockback: float = 0.0) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	# Prefer sync take_damage so rapid towers (laser) never stall on bullet VFX.
	if enemy.has_method("take_damage"):
		enemy.take_damage(dmg, knockback)
	elif enemy.has_method("get_hit"):
		enemy.get_hit(dmg, global_transform, knockback)
