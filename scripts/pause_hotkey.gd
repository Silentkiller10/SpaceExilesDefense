extends Node

## Lives on the always-processing UI layer so Esc works while paused.

var game: Node

func _unhandled_input(event: InputEvent) -> void:
	if game == null:
		return
	if event.is_action_pressed("ui_cancel"):
		if game.has_method("_toggle_pause_menu"):
			game._toggle_pause_menu()
		get_viewport().set_input_as_handled()
