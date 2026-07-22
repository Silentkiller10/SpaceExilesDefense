extends Control

var _play_btn: Button
var _normal_btn: Button
var _infinity_btn: Button
var _sandbox_btn: Button
var _char_btn: Button
var _skill_btn: Button
var _leaderboard_box: VBoxContainer
var _mode_panel: VBoxContainer
var _hub_panel: VBoxContainer
var _leaderboard_panel: PanelContainer
var _leaderboard_btn: Button

func _ready() -> void:
	MusicManager.play_menu_music()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.09, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 24)
	root.set("theme_override_constants/margin_left", 32)
	root.set("theme_override_constants/margin_right", 32)
	root.set("theme_override_constants/margin_top", 28)
	root.set("theme_override_constants/margin_bottom", 28)
	add_child(root)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	root.add_child(left)

	var title := Label.new()
	title.text = "SPACE EXILES DEFENSE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.modulate = Color(0.35, 0.95, 0.85)
	left.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Fortress Command Hub"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.modulate = Color(0.65, 0.75, 0.85)
	left.add_child(subtitle)

	left.add_child(_spacer(12))

	_play_btn = _make_btn("PLAY", Color(0.35, 0.95, 0.7))
	_play_btn.custom_minimum_size = Vector2(280, 52)
	_play_btn.add_theme_font_size_override("font_size", 22)
	_play_btn.pressed.connect(_on_play_pressed)
	left.add_child(_play_btn)

	_mode_panel = VBoxContainer.new()
	_mode_panel.visible = false
	_mode_panel.add_theme_constant_override("separation", 8)
	left.add_child(_mode_panel)

	var mode_hint := Label.new()
	mode_hint.text = "Choose game mode"
	mode_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_hint.add_theme_font_size_override("font_size", 13)
	mode_hint.modulate = Color(0.7, 0.8, 0.9)
	_mode_panel.add_child(mode_hint)

	_normal_btn = _make_btn("Normal Mode — Stage Campaign", Color(0.4, 0.85, 1.0))
	_normal_btn.pressed.connect(_on_normal_pressed)
	_mode_panel.add_child(_normal_btn)

	_infinity_btn = _make_btn("Infinity Mode — Endless Waves", Color(1.0, 0.55, 0.95))
	_infinity_btn.pressed.connect(_on_infinity_pressed)
	_mode_panel.add_child(_infinity_btn)

	var back_btn := _make_btn("Back", Color(0.65, 0.75, 0.85))
	back_btn.pressed.connect(_on_play_back)
	_mode_panel.add_child(back_btn)

	_hub_panel = VBoxContainer.new()
	_hub_panel.add_theme_constant_override("separation", 10)
	left.add_child(_hub_panel)

	_sandbox_btn = _make_btn("Sandbox (Tower Test Range)", Color(0.45, 1.0, 0.9))
	_sandbox_btn.pressed.connect(_on_sandbox_pressed)
	_hub_panel.add_child(_sandbox_btn)

	_char_btn = _make_btn("Character & Gear", Color(0.75, 0.85, 1.0))
	_char_btn.pressed.connect(_on_character_pressed)
	_hub_panel.add_child(_char_btn)

	var shop_btn := _make_btn("Gear Shop", Color(1.0, 0.85, 0.3))
	shop_btn.pressed.connect(_on_shop_pressed)
	_hub_panel.add_child(shop_btn)

	_skill_btn = _make_btn("Skill Tree", Color(0.85, 0.65, 1.0))
	_skill_btn.pressed.connect(_on_skill_tree_pressed)
	_hub_panel.add_child(_skill_btn)

	_leaderboard_btn = _make_btn("Infinity Leaderboard", Color(1.0, 0.55, 0.95))
	_leaderboard_btn.pressed.connect(_on_leaderboard_pressed)
	_hub_panel.add_child(_leaderboard_btn)

	var settings_btn := _make_btn("Settings", Color(0.7, 0.85, 1.0))
	settings_btn.pressed.connect(_on_settings_pressed)
	_hub_panel.add_child(settings_btn)

	_build_leaderboard_overlay()

func _build_leaderboard_overlay() -> void:
	_leaderboard_panel = PanelContainer.new()
	_leaderboard_panel.visible = false
	_leaderboard_panel.set_anchors_preset(Control.PRESET_CENTER)
	_leaderboard_panel.custom_minimum_size = Vector2(340, 420)
	_leaderboard_panel.offset_left = -170
	_leaderboard_panel.offset_top = -210
	_leaderboard_panel.offset_right = 170
	_leaderboard_panel.offset_bottom = 210

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.08, 0.14, 0.98)
	panel_style.border_color = Color(1.0, 0.55, 0.95, 0.6)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(16)
	_leaderboard_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_leaderboard_panel)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 8)
	_leaderboard_panel.add_child(right_vbox)

	var lb_title := Label.new()
	lb_title.text = "INFINITY LEADERBOARD"
	lb_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb_title.add_theme_font_size_override("font_size", 18)
	lb_title.modulate = Color(1.0, 0.55, 0.95)
	right_vbox.add_child(lb_title)

	var lb_sub := Label.new()
	lb_sub.text = "Top survivors by wave, then time"
	lb_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb_sub.add_theme_font_size_override("font_size", 11)
	lb_sub.modulate = Color(0.65, 0.75, 0.85)
	right_vbox.add_child(lb_sub)

	right_vbox.add_child(_spacer(4))

	_leaderboard_box = VBoxContainer.new()
	_leaderboard_box.add_theme_constant_override("separation", 6)
	right_vbox.add_child(_leaderboard_box)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(120, 36)
	close_btn.pressed.connect(_on_leaderboard_close)
	right_vbox.add_child(close_btn)

func _spacer(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s

func _make_btn(text: String, color: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280, 40)
	btn.modulate = color
	return btn

func _refresh_leaderboard() -> void:
	for child in _leaderboard_box.get_children():
		child.queue_free()
	var board := PlayerData.get_infinity_leaderboard()
	if board.is_empty():
		var empty := Label.new()
		empty.text = "No runs recorded yet.\nStart Infinity Mode to claim #1!"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = Color(0.65, 0.75, 0.85)
		_leaderboard_box.add_child(empty)
		return
	for i in board.size():
		var e: Dictionary = board[i]
		var tm := int(float(e.get("time_sec", 0.0))) / 60
		var ts := int(float(e.get("time_sec", 0.0))) % 60
		var row := Label.new()
		row.text = "%d. %s\n   Wave %d  •  %02d:%02d" % [
			i + 1,
			String(e.get("name", "?")),
			int(e.get("waves", 0)),
			tm, ts
		]
		row.add_theme_font_size_override("font_size", 12)
		if String(e.get("name", "")) == PlayerData.player_name:
			row.modulate = Color(0.35, 0.95, 0.7)
		_leaderboard_box.add_child(row)

func _on_play_pressed() -> void:
	_hub_panel.visible = false
	_play_btn.visible = false
	_mode_panel.visible = true

func _on_play_back() -> void:
	_hub_panel.visible = true
	_play_btn.visible = true
	_mode_panel.visible = false

func _on_leaderboard_pressed() -> void:
	_refresh_leaderboard()
	_leaderboard_panel.visible = true
	_leaderboard_panel.move_to_front()

func _on_leaderboard_close() -> void:
	_leaderboard_panel.visible = false

func _on_normal_pressed() -> void:
	PlayerData.tower_test_mode = false
	PlayerData.session_mode = "normal"
	PlayerData.selected_stage = PlayerData.current_stage
	PlayerData.clamp_selected_stage()
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_infinity_pressed() -> void:
	PlayerData.tower_test_mode = false
	PlayerData.session_mode = "infinity"
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_sandbox_pressed() -> void:
	PlayerData.tower_test_mode = true
	PlayerData.session_mode = "sandbox"
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_character_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/character.tscn")

func _on_shop_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/shop.tscn")

func _on_skill_tree_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/skill_tree.tscn")

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/settings.tscn")
