extends Node2D

@onready var bleeding_effect: GPUParticles2D = $BleedingEffect

func setup(trans: Transform2D):
	global_transform = trans
	if not is_node_ready():
		await ready
	if bleeding_effect:
		bleeding_effect.emitting = true

func _on_bleeding_effect_finished():
	queue_free()
