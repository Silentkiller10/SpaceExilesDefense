extends Control

var _stage_label: Label
var _reward_preview: Label
var _play_btn: Button

func _ready():
	PlayerData.clamp_selected_stage()
	_build_ui()

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	var bg = ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var glow = ColorRect.new()
	glow.color = Color(0.1, 0.45, 0.7, 0.15)
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(glow)

	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 420)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.08, 0.12, 0.95)
	style.border_color = Color(0.25, 0.85, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var brand = Label.new()
	brand.text = "FORTRESS TD"
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.add_theme_font_size_override("font_size", 32)
	brand.modulate = Color(0.35, 0.9, 1.0)
	vbox.add_child(brand)

	var subtitle = Label.new()
	subtitle.text = "Hub — pick a stage, gear up, deploy"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	vbox.add_child(subtitle)

	var stats = Label.new()
	stats.text = "Coins: %d  |  Newest: Stage %d  |  Cleared: %d" % [
		PlayerData.coins, PlayerData.current_stage, PlayerData.levels_cleared
	]
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 12)
	vbox.add_child(stats)

	# Stage picker
	var picker := HBoxContainer.new()
	picker.alignment = BoxContainer.ALIGNMENT_CENTER
	picker.add_theme_constant_override("separation", 12)
	vbox.add_child(picker)

	var prev_btn := Button.new()
	prev_btn.text = "<"
	prev_btn.custom_minimum_size = Vector2(48, 40)
	prev_btn.pressed.connect(_change_stage.bind(-1))
	picker.add_child(prev_btn)

	_stage_label = Label.new()
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_label.custom_minimum_size = Vector2(160, 0)
	_stage_label.add_theme_font_size_override("font_size", 18)
	picker.add_child(_stage_label)

	var next_btn := Button.new()
	next_btn.text = ">"
	next_btn.custom_minimum_size = Vector2(48, 40)
	next_btn.pressed.connect(_change_stage.bind(1))
	picker.add_child(next_btn)

	_reward_preview = Label.new()
	_reward_preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reward_preview.add_theme_font_size_override("font_size", 12)
	_reward_preview.modulate = Color(1.0, 0.85, 0.35)
	vbox.add_child(_reward_preview)

	_play_btn = Button.new()
	_play_btn.custom_minimum_size = Vector2(240, 44)
	_play_btn.pressed.connect(_on_play_pressed)
	vbox.add_child(_play_btn)

	var test_btn = Button.new()
	test_btn.text = "Sandbox"
	test_btn.custom_minimum_size = Vector2(240, 44)
	test_btn.modulate = Color(0.55, 1.0, 0.85)
	test_btn.tooltip_text = "All towers unlocked. Pick which enemies spawn, click towers to toggle them, manual fire only"
	test_btn.pressed.connect(_on_test_range_pressed)
	vbox.add_child(test_btn)

	var char_btn = Button.new()
	char_btn.text = "Character"
	char_btn.custom_minimum_size = Vector2(240, 44)
	char_btn.pressed.connect(_on_character_pressed)
	vbox.add_child(char_btn)

	var skills_btn = Button.new()
	skills_btn.text = "Skill Tree"
	skills_btn.custom_minimum_size = Vector2(240, 44)
	skills_btn.pressed.connect(_on_skills_pressed)
	vbox.add_child(skills_btn)

	var shop_btn = Button.new()
	shop_btn.text = "Shop"
	shop_btn.custom_minimum_size = Vector2(240, 44)
	shop_btn.pressed.connect(_on_shop_pressed)
	vbox.add_child(shop_btn)

	var quit_btn = Button.new()
	quit_btn.text = "Quit"
	quit_btn.custom_minimum_size = Vector2(240, 40)
	quit_btn.pressed.connect(_on_quit_pressed)
	vbox.add_child(quit_btn)

	_refresh_stage_ui()

func _change_stage(delta: int) -> void:
	PlayerData.set_selected_stage(PlayerData.selected_stage + delta)
	PlayerData.save_data()
	_refresh_stage_ui()

func _refresh_stage_ui() -> void:
	PlayerData.clamp_selected_stage()
	var s: int = PlayerData.selected_stage
	var newest: int = PlayerData.current_stage
	var tag: String = "NEW" if s == newest else "REPLAY"
	if PlayerData.is_boss_stage(s):
		tag += " · BOSS STAGE"
	_stage_label.text = "Stage %d — %s\n(%s)" % [s, PlayerData.get_stage_name(s), tag]
	_stage_label.modulate = Color(1.0, 0.45, 0.35) if PlayerData.is_boss_stage(s) else Color(1, 1, 1)
	var preview: Dictionary = PlayerData.get_stage_reward_preview(s)
	_reward_preview.text = String(preview.get("summary", ""))
	_play_btn.text = "Deploy Stage %d" % s

func _on_play_pressed():
	PlayerData.tower_test_mode = false
	PlayerData.clamp_selected_stage()
	PlayerData.save_data()
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_test_range_pressed():
	PlayerData.tower_test_mode = true
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_character_pressed():
	get_tree().change_scene_to_file("res://scenes/character.tscn")

func _on_skills_pressed():
	get_tree().change_scene_to_file("res://scenes/skill_tree.tscn")

func _on_shop_pressed():
	get_tree().change_scene_to_file("res://scenes/shop.tscn")

func _on_quit_pressed():
	get_tree().quit()
