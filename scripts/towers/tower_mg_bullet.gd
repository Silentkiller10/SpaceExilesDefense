extends Area2D

## Machine gun tower projectile — fast sprite bullet.

const TEX_PATH: String = "res://assets/sprites/machine_gun_bullet.png"
const BULLET_SCALE := Vector2(0.32, 0.32)

@export var speed: float = 2600.0

var damage: int = 16
var knockback: float = 10.0
var _range_left: float = 520.0
var _sprite: Sprite2D

func _ready() -> void:
	z_index = 15
	monitoring = true
	collision_layer = 4
	collision_mask = 2

	var tex: Texture2D = load(TEX_PATH) as Texture2D
	_sprite = Sprite2D.new()
	if tex:
		_sprite.texture = tex
	else:
		# Fallback if import cache is missing — keeps bullets visible in-editor.
		_sprite.texture = _make_fallback_texture()
	_sprite.scale = BULLET_SCALE
	add_child(_sprite)

	var shape_node := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(40, 14)
	shape_node.shape = rect
	add_child(shape_node)

	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _make_fallback_texture() -> Texture2D:
	var img := Image.create(64, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for x in img.get_width():
		for y in img.get_height():
			var t: float = float(x) / float(img.get_width() - 1)
			var c: Color = Color(1.0, 0.95, 0.7).lerp(Color(1.0, 0.45, 0.1), t)
			if y >= 4 and y <= 11:
				img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func launch(origin: Vector2, direction: Vector2, dmg: int, kb: float, max_range: float) -> void:
	global_position = origin
	if direction.length_squared() < 0.0001:
		direction = Vector2.UP
	else:
		direction = direction.normalized()
	rotation = direction.angle()
	damage = dmg
	knockback = kb
	_range_left = max_range

func _physics_process(delta: float) -> void:
	var step: float = speed * delta
	position += transform.x * step
	_range_left -= step
	if _range_left <= 0.0:
		queue_free()
		return
	var gp := global_position
	if gp.y < -400.0 or gp.y > 2400.0 or gp.x < -400.0 or gp.x > 2400.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body == null or not is_instance_valid(body):
		return
	if not body.is_in_group("enemy"):
		return
	if body.get("is_dying") == true:
		return
	if body.has_method("take_damage"):
		body.take_damage(damage, knockback)
	elif body.has_method("get_hit"):
		body.get_hit(damage, global_transform, knockback)
	queue_free()
