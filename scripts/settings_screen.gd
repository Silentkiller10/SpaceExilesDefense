extends Control

var _section_title: Label
var _content_box: VBoxContainer
var _sfx_toggle: CheckButton
var _fullscreen_toggle: CheckButton
var _vsync_toggle: CheckButton
var _auto_aim_toggle: CheckButton
var _auto_shoot_toggle: CheckButton

enum Section { SOUNDS, GRAPHICS, PLAYER }
var _section: Section = Section.SOUNDS

func _ready() -> void:
	_build_ui()
	_show_section(Section.SOUNDS)

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.09, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 20
	root.offset_top = 16
	root.offset_right = -20
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 12)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	var title := Label.new()
	title.text = "SETTINGS"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 26)
	title.modulate = Color(0.75, 0.9, 1.0)
	header.add_child(title)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(90, 36)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/mainmenu.tscn"))
	header.add_child(back_btn)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	root.add_child(nav)

	for item in [
		["Sounds", Section.SOUNDS],
		["Graphics", Section.GRAPHICS],
		["Player Settings", Section.PLAYER],
	]:
		var btn := Button.new()
		btn.text = String(item[0])
		btn.custom_minimum_size = Vector2(140, 36)
		btn.pressed.connect(_show_section.bind(int(item[1])))
		nav.add_child(btn)

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.14, 0.95)
	style.border_color = Color(0.35, 0.75, 1.0, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var panel_vbox := VBoxContainer.new()
	panel_vbox.add_theme_constant_override("separation", 14)
	panel.add_child(panel_vbox)

	_section_title = Label.new()
	_section_title.add_theme_font_size_override("font_size", 18)
	_section_title.modulate = Color(0.35, 0.95, 0.85)
	panel_vbox.add_child(_section_title)

	_content_box = VBoxContainer.new()
	_content_box.add_theme_constant_override("separation", 12)
	panel_vbox.add_child(_content_box)

func _clear_content() -> void:
	for child in _content_box.get_children():
		child.queue_free()

func _show_section(section: int) -> void:
	_section = section as Section
	_clear_content()
	match _section:
		Section.SOUNDS:
			_section_title.text = "Sounds"
			_build_sounds_section()
		Section.GRAPHICS:
			_section_title.text = "Graphics"
			_build_graphics_section()
		Section.PLAYER:
			_section_title.text = "Player Settings"
			_build_player_section()

func _build_sounds_section() -> void:
	_make_volume_row("Master", GameSettings.master_volume, func(v: float): GameSettings.set_master_volume(v))
	_make_volume_row("Music", GameSettings.music_volume, func(v: float): GameSettings.set_music_volume(v))
	_make_volume_row("Player", GameSettings.player_volume, func(v: float): GameSettings.set_player_volume(v))
	_make_volume_row("Enemy", GameSettings.enemy_volume, func(v: float): GameSettings.set_enemy_volume(v))
	_make_volume_row("Towers", GameSettings.towers_volume, func(v: float): GameSettings.set_towers_volume(v))

	_sfx_toggle = _make_toggle_row(
		"Sound effects",
		GameSettings.sfx_enabled,
		func(on: bool): GameSettings.set_sfx_enabled(on)
	)

func _make_volume_row(label_text: String, initial: float, callback: Callable) -> void:
	_content_box.add_child(_make_row_label(label_text))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_content_box.add_child(row)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value = initial * 100.0
	row.add_child(slider)

	var value_lbl := Label.new()
	value_lbl.custom_minimum_size = Vector2(48, 0)
	value_lbl.text = "%d%%" % int(slider.value)
	row.add_child(value_lbl)

	slider.value_changed.connect(func(value: float):
		value_lbl.text = "%d%%" % int(value)
		callback.call(value / 100.0)
	)

func _build_graphics_section() -> void:
	_fullscreen_toggle = _make_toggle_row(
		"Fullscreen",
		GameSettings.fullscreen,
		func(on: bool): GameSettings.set_fullscreen(on)
	)
	_vsync_toggle = _make_toggle_row(
		"VSync",
		GameSettings.vsync_enabled,
		func(on: bool): GameSettings.set_vsync_enabled(on)
	)

func _build_player_section() -> void:
	var hint := Label.new()
	hint.text = "These options apply while your character is standing still."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(0.65, 0.75, 0.85)
	_content_box.add_child(hint)

	_auto_aim_toggle = _make_toggle_row(
		"Auto aim when not moving",
		GameSettings.auto_aim_when_idle,
		func(on: bool): GameSettings.set_auto_aim_when_idle(on)
	)
	_auto_shoot_toggle = _make_toggle_row(
		"Auto shoot when not moving",
		GameSettings.auto_shoot_when_idle,
		func(on: bool): GameSettings.set_auto_shoot_when_idle(on)
	)

func _make_row_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 14)
	return lbl

func _make_toggle_row(label_text: String, initial_on: bool, callback: Callable) -> CheckButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_content_box.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 14)
	row.add_child(lbl)

	var toggle := CheckButton.new()
	toggle.text = "On" if initial_on else "Off"
	toggle.button_pressed = initial_on
	toggle.custom_minimum_size = Vector2(80, 32)
	toggle.toggled.connect(func(on: bool):
		toggle.text = "On" if on else "Off"
		callback.call(on)
	)
	row.add_child(toggle)
	return toggle
