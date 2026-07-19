extends Control

const LOADING_IMAGE := "res://assets/png/loading_screen.png"
const MAIN_MENU := "res://scenes/mainmenu.tscn"
const MIN_DISPLAY_SEC := 2.5

func _ready() -> void:
	_build_ui()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(MIN_DISPLAY_SEC).timeout
	get_tree().change_scene_to_file(MAIN_MENU)

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var art := TextureRect.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture = PlayerData.load_png_texture(LOADING_IMAGE)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)

	var status := Label.new()
	status.text = "Loading..."
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	status.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	status.offset_bottom = -36
	status.add_theme_font_size_override("font_size", 18)
	status.modulate = Color(0.85, 0.95, 1.0, 0.9)
	add_child(status)
