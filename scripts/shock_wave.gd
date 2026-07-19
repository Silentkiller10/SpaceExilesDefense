extends Node2D

@export var max_radius: float = 280.0
@export var expand_speed: float = 700.0
@export var damage: int = 90

var current_radius: float = 20.0
var hit_enemies: Array = []
var start_pos: Vector2 = Vector2.ZERO

@onready var ring: Polygon2D = $Ring

func setup(pos: Vector2) -> void:
	start_pos = pos

func _ready() -> void:
	global_position = start_pos
	_update_ring()

func _physics_process(delta: float) -> void:
	current_radius += expand_speed * delta
	_update_ring()
	_damage_enemies_in_range()
	if current_radius >= max_radius:
		queue_free()

func _damage_enemies_in_range() -> void:
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(enemy) or enemy in hit_enemies:
			continue
		if enemy.is_dying:
			continue
		if global_position.distance_to(enemy.global_position) <= current_radius:
			hit_enemies.append(enemy)
			if enemy.has_method("get_hit"):
				enemy.get_hit(damage, global_transform, 80.0)

func _update_ring() -> void:
	if ring == null:
		return
	var points: PackedVector2Array = []
	var segments := 36
	for i in range(segments):
		var angle := TAU * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * current_radius)
	ring.polygon = points
	var alpha := 1.0 - (current_radius / max_radius)
	ring.color = Color(0.35, 0.9, 1.0, alpha * 0.5)
