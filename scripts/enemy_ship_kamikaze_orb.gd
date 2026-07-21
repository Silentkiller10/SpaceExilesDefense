extends StaticBody2D

## Red guard orb orbiting the Kamikaze ship. Individually shootable —
## destroying one forces the ship to pop/dash early. Orbs also auto-pop
## on the ship's own 0.5s cadence, so their HP is a way for the player
## to burn the ship's evasive charges before it gets close.

const RADIUS := 9.0
const CORE_COLOR := Color(1.0, 0.25, 0.2, 0.95)
const GLOW_COLOR := Color(1.0, 0.35, 0.25, 0.3)

var hp: int = 40
var max_hp: int = 40
var is_dying: bool = false
var ship: Node2D

var _core: Polygon2D
var _glow: Polygon2D

func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	add_to_group("enemy")

	_glow = _make_circle(RADIUS * 2.0, GLOW_COLOR, 4)
	add_child(_glow)
	_core = _make_circle(RADIUS, CORE_COLOR, 5)
	add_child(_core)

	var shape_node := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS + 3.0
	shape_node.shape = circle
	add_child(shape_node)

func _make_circle(r: float, color: Color, z: int) -> Polygon2D:
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 14:
		pts.append(Vector2.from_angle(float(i) / 14.0 * TAU) * r)
	poly.polygon = pts
	poly.color = color
	poly.z_index = z
	return poly

func setup(_ship: Node2D, orb_hp: int) -> void:
	ship = _ship
	hp = maxi(1, orb_hp)
	max_hp = hp

## Pulse driven by the ship so all orbs breathe together.
func set_pulse(t: float) -> void:
	if _glow:
		_glow.scale = Vector2.ONE * (1.0 + sin(t * 6.0) * 0.15)

func get_hit(damage: int, _bullet_trans: Transform2D, _knockback: float = 0.0, _apply_ignition: bool = false):
	_damage(damage)

func take_damage(amount: int, _knockback: float = 0.0, _apply_ignition: bool = false) -> void:
	_damage(amount)

func _damage(amount: int) -> void:
	if is_dying:
		return
	hp -= amount
	if _core:
		_core.color = Color(1.8, 1.5, 1.4)
		var tw := _core.create_tween()
		tw.tween_property(_core, "color", CORE_COLOR, 0.12)
	if hp <= 0:
		is_dying = true
		if ship and is_instance_valid(ship) and ship.has_method("_on_orb_shot"):
			ship._on_orb_shot(self)
