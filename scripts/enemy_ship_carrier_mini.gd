extends "res://scripts/enemy.gd"

## Mini Carrier — small copy of the Carrier mother ship, deployed by it
## every few seconds (and 3 at once when the mother dies). Descends with
## the rest of the wave to crash into the base, firing a bullet every
## 1-2 seconds (randomized between shots) on the way down.

const BULLET_SCRIPT := preload("res://scripts/enemy_carrier_bullet.gd")

const SHIP_TYPE := {
	"id": "carrier_mini",
	"category": "ship",
	"texture": "res://assets/sprites/enemy_ship_3.png",
	"sprite_scale": 0.022,
	"collision": Vector2(38, 46),
	"xp": 6
}

var bullet_damage: int = 4
var _fire_timer: float = 1.5

func _ready() -> void:
	super()
	apply_enemy_type(SHIP_TYPE)
	_fire_timer = randf_range(1.0, 2.0)

## Called by the Carrier (or wave manager) after setup_descent.
func setup_mini(bullet_dmg: int) -> void:
	bullet_damage = bullet_dmg

func _physics_process(delta):
	super(delta)
	if is_dying or stun_timer > 0.0:
		return
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = randf_range(1.0, 2.0)
		_fire_bullet()

func _fire_bullet() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var bullet := Node2D.new()
	bullet.set_script(BULLET_SCRIPT)
	scene.add_child(bullet)
	bullet.launch(global_position + Vector2(0, 26), fortress, bullet_damage)

## Steady descent — no UFO spin, the ship art already points down.
func _update_fall_visual() -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var pulse: float = 1.0 + sin(_fall_time * 4.5) * 0.03
	sprite.scale = _base_sprite_scale * pulse
	sprite.rotation = 0.0
	if sprite.modulate.a >= 0.99:
		sprite.modulate = Color.WHITE
