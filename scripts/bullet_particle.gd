extends Node2D

@onready var bullet_effect: GPUParticles2D = $BulletEffect

func setup(trans: Transform2D):
	transform = trans
	scale.x = -1
	if not is_node_ready():
		await ready
	bullet_effect.emitting = true

func _on_bullet_effect_finished():
	queue_free()
