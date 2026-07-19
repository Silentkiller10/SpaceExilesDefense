extends Node2D
class_name Fortress

signal fortress_destroyed
signal health_changed(current: int, maximum: int)

@export var max_health: int = 500
@export var base_damage_on_leak: int = 10

var health: int = 500
var tower_damage_multiplier: float = 1.0
var cooldown_reduction: float = 0.0
## 1.0 = full leak damage; lowered by armor leak_resist gear mods
var leak_damage_mult: float = 1.0

@onready var body: Polygon2D = $Body
@onready var rampart: Polygon2D = $Rampart
@onready var hit_line_y: float = 0.0

func _ready() -> void:
	health = max_health
	hit_line_y = global_position.y - 40.0
	health_changed.emit(health, max_health)

func setup(arena_width: float, arena_height: float) -> void:
	position = Vector2(arena_width * 0.5, arena_height - 60.0)
	hit_line_y = position.y - 40.0
	if body:
		body.polygon = PackedVector2Array([
			Vector2(-arena_width * 0.48, 20),
			Vector2(arena_width * 0.48, 20),
			Vector2(arena_width * 0.48, 80),
			Vector2(-arena_width * 0.48, 80)
		])
		body.color = Color(0.08, 0.1, 0.16, 1.0)
	if rampart:
		rampart.polygon = PackedVector2Array([
			Vector2(-arena_width * 0.46, -20),
			Vector2(arena_width * 0.46, -20),
			Vector2(arena_width * 0.46, 20),
			Vector2(-arena_width * 0.46, 20)
		])
		rampart.color = Color(0.12, 0.18, 0.28, 1.0)

func take_damage(amount: int) -> void:
	health = max(0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0:
		fortress_destroyed.emit()

func heal(amount: int) -> void:
	health = mini(max_health, health + amount)
	health_changed.emit(health, max_health)

func increase_max_health(amount: int) -> void:
	max_health += amount
	health += amount
	health_changed.emit(health, max_health)

func get_leak_y() -> float:
	return hit_line_y
