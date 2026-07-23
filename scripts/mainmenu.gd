extends Control

## Mobile-style command hub: browse unlocked stages, Battle to deploy.

const TEAL := Color(0.33, 0.78, 0.72)
const TEAL_DIM := Color(0.18, 0.42, 0.40)
const TEAL_BG := Color(0.08, 0.18, 0.18, 0.92)
const DARK := Color(0.04, 0.05, 0.07)
const PANEL := Color(0.08, 0.10, 0.12, 0.95)
const GOLD := Color(1.0, 0.85, 0.35)
const MUTED := Color(0.62, 0.70, 0.74)

var _stage_title: Label
var _stage_sub: Label
var _status_lbl: Label
var _reward_lbl: Label
var _coins_lbl: Label
var _name_lbl: Label
var _level_lbl: Label
var _battle_btn: Button
var _prev_btn: Button
var _next_btn: Button
var _normal_tab: Button
var _infinity_tab: Button
var _planet_panel: Panel
var _stage_center: VBoxContainer
var _stage_center_num: Label
var _stage_center_name: Label
var _infinity_stats: VBoxContainer
var _inf_wave_lbl: Label
var _inf_time_lbl: Label
var _lock_lbl: Label
var _boss_badge: Label
var _leaderboard_box: VBoxContainer
var _leaderboard_panel: PanelContainer
var _view_stage: int = 1
## "normal" = stage campaign, "infinity" = endless
var _play_mode: String = "normal"

func _ready() -> void:
	MusicManager.play_menu_music()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	PlayerData.clamp_selected_stage()
	_view_stage = PlayerData.selected_stage

	_build_background()
	_build_top_bar()
	_build_side_rails()
	_build_stage_area()
	_build_battle_row()
	_build_bottom_nav()
	_build_leaderboard_overlay()
	_refresh_stage_view()

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = DARK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Soft teal vignette at top
	var glow := ColorRect.new()
	glow.color = Color(0.05, 0.16, 0.16, 0.55)
	glow.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	glow.offset_bottom = 280
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	if ResourceLoader.exists("res://assets/sprites/space2.png"):
		var space := TextureRect.new()
		space.texture = load("res://assets/sprites/space2.png")
		space.set_anchors_preset(Control.PRESET_FULL_RECT)
		space.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		space.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		space.modulate = Color(1, 1, 1, 0.22)
		space.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(space)

func _build_top_bar() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 16
	bar.offset_right = -16
	bar.offset_top = 18
	bar.offset_bottom = 88
	bar.add_theme_constant_override("separation", 12)
	add_child(bar)

	# Profile pill
	var profile := PanelContainer.new()
	profile.custom_minimum_size = Vector2(120, 64)
	profile.add_theme_stylebox_override("panel", _round_style(PANEL, TEAL_DIM, 8, 1))
	bar.add_child(profile)

	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 2)
	profile.add_child(pv)

	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 6)
	pv.add_child(ph)

	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(36, 36)
	avatar.add_theme_stylebox_override("panel", _round_style(Color(0.12, 0.16, 0.18), TEAL, 18, 2))
	ph.add_child(avatar)
	_level_lbl = Label.new()
	_level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_lbl.add_theme_font_size_override("font_size", 14)
	_level_lbl.modulate = TEAL
	avatar.add_child(_level_lbl)

	_name_lbl = Label.new()
	_name_lbl.add_theme_font_size_override("font_size", 13)
	_name_lbl.modulate = Color(0.9, 0.95, 0.95)
	_name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_lbl.custom_minimum_size = Vector2(70, 0)
	ph.add_child(_name_lbl)

	# Coins
	var coins_panel := PanelContainer.new()
	coins_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	coins_panel.add_theme_stylebox_override("panel", _round_style(Color(0.10, 0.10, 0.08, 0.9), Color(0.45, 0.35, 0.1), 10, 1))
	bar.add_child(coins_panel)
	var ch := HBoxContainer.new()
	ch.alignment = BoxContainer.ALIGNMENT_CENTER
	ch.add_theme_constant_override("separation", 8)
	coins_panel.add_child(ch)
	var coin_ico := Label.new()
	coin_ico.text = "◆"
	coin_ico.modulate = GOLD
	coin_ico.add_theme_font_size_override("font_size", 18)
	ch.add_child(coin_ico)
	_coins_lbl = Label.new()
	_coins_lbl.add_theme_font_size_override("font_size", 18)
	_coins_lbl.modulate = GOLD
	ch.add_child(_coins_lbl)

	var settings := _icon_btn("☰", Vector2(52, 52))
	settings.pressed.connect(_on_settings_pressed)
	bar.add_child(settings)

func _build_stage_area() -> void:
	var area := VBoxContainer.new()
	area.set_anchors_preset(Control.PRESET_FULL_RECT)
	area.offset_left = 24
	area.offset_right = -24
	area.offset_top = 110
	area.offset_bottom = -210
	area.add_theme_constant_override("separation", 10)
	add_child(area)

	# Stage title chip
	var title_wrap := CenterContainer.new()
	area.add_child(title_wrap)
	var title_panel := PanelContainer.new()
	title_panel.custom_minimum_size = Vector2(320, 44)
	title_panel.add_theme_stylebox_override("panel", _round_style(TEAL_BG, TEAL, 14, 2))
	title_wrap.add_child(title_panel)
	_stage_title = Label.new()
	_stage_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_title.add_theme_font_size_override("font_size", 20)
	_stage_title.modulate = Color(0.85, 1.0, 0.95)
	title_panel.add_child(_stage_title)

	_stage_sub = Label.new()
	_stage_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_sub.add_theme_font_size_override("font_size", 13)
	_stage_sub.modulate = MUTED
	area.add_child(_stage_sub)

	# Normal / Infinity tabs
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 10)
	area.add_child(tabs)
	_normal_tab = _tab_btn("Normal", true)
	_normal_tab.pressed.connect(func(): _set_play_mode("normal"))
	tabs.add_child(_normal_tab)
	_infinity_tab = _tab_btn("Infinity", false)
	_infinity_tab.pressed.connect(func(): _set_play_mode("infinity"))
	tabs.add_child(_infinity_tab)

	# Planet + arrows
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 8)
	area.add_child(mid)

	_prev_btn = _chevron_btn("<")
	_prev_btn.z_index = 20
	_prev_btn.pressed.connect(_on_prev_stage)
	mid.add_child(_prev_btn)

	var planet_host := Control.new()
	planet_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	planet_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	planet_host.custom_minimum_size = Vector2(280, 280)
	mid.add_child(planet_host)

	var planet_panel := Panel.new()
	_planet_panel = planet_panel
	planet_panel.set_anchors_preset(Control.PRESET_CENTER)
	planet_panel.custom_minimum_size = Vector2(260, 260)
	planet_panel.offset_left = -130
	planet_panel.offset_top = -130
	planet_panel.offset_right = 130
	planet_panel.offset_bottom = 130
	var disc := StyleBoxFlat.new()
	disc.bg_color = Color(0.06, 0.09, 0.11, 0.95)
	disc.border_color = TEAL_DIM
	disc.set_border_width_all(3)
	disc.set_corner_radius_all(130)
	disc.shadow_color = Color(0.2, 0.7, 0.65, 0.25)
	disc.shadow_size = 18
	planet_panel.add_theme_stylebox_override("panel", disc)
	planet_host.add_child(planet_panel)

	# Infinity personal-best readout (center of the disc).
	_infinity_stats = VBoxContainer.new()
	_infinity_stats.set_anchors_preset(Control.PRESET_FULL_RECT)
	_infinity_stats.offset_left = 28
	_infinity_stats.offset_top = 56
	_infinity_stats.offset_right = -28
	_infinity_stats.offset_bottom = -40
	_infinity_stats.alignment = BoxContainer.ALIGNMENT_CENTER
	_infinity_stats.add_theme_constant_override("separation", 10)
	_infinity_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_infinity_stats.visible = false
	planet_panel.add_child(_infinity_stats)

	var best_hdr := Label.new()
	best_hdr.text = "YOUR BEST"
	best_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	best_hdr.add_theme_font_size_override("font_size", 14)
	best_hdr.modulate = Color(1.0, 0.55, 0.95)
	_infinity_stats.add_child(best_hdr)

	_inf_wave_lbl = Label.new()
	_inf_wave_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inf_wave_lbl.add_theme_font_size_override("font_size", 28)
	_inf_wave_lbl.modulate = Color(0.95, 0.95, 1.0)
	_infinity_stats.add_child(_inf_wave_lbl)

	_inf_time_lbl = Label.new()
	_inf_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inf_time_lbl.add_theme_font_size_override("font_size", 22)
	_inf_time_lbl.modulate = TEAL
	_infinity_stats.add_child(_inf_time_lbl)

	# Normal-mode stage readout (replaces the old nebula PNG).
	_stage_center = VBoxContainer.new()
	_stage_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage_center.offset_left = 28
	_stage_center.offset_top = 56
	_stage_center.offset_right = -28
	_stage_center.offset_bottom = -40
	_stage_center.alignment = BoxContainer.ALIGNMENT_CENTER
	_stage_center.add_theme_constant_override("separation", 8)
	_stage_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	planet_panel.add_child(_stage_center)

	_stage_center_num = Label.new()
	_stage_center_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_center_num.add_theme_font_size_override("font_size", 42)
	_stage_center_num.modulate = TEAL
	_stage_center.add_child(_stage_center_num)

	_stage_center_name = Label.new()
	_stage_center_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_center_name.add_theme_font_size_override("font_size", 14)
	_stage_center_name.modulate = MUTED
	_stage_center_name.autowrap_mode = TextServer.AUTOWRAP_WORD
	_stage_center.add_child(_stage_center_name)

	_boss_badge = Label.new()
	_boss_badge.text = "BOSS"
	_boss_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_badge.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_boss_badge.offset_top = 28
	_boss_badge.offset_bottom = 56
	_boss_badge.add_theme_font_size_override("font_size", 18)
	_boss_badge.modulate = Color(1.0, 0.45, 0.35)
	_boss_badge.visible = false
	planet_panel.add_child(_boss_badge)

	_lock_lbl = Label.new()
	_lock_lbl.text = "LOCKED"
	_lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lock_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lock_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lock_lbl.add_theme_font_size_override("font_size", 28)
	_lock_lbl.modulate = Color(1, 1, 1, 0.9)
	_lock_lbl.visible = false
	planet_panel.add_child(_lock_lbl)

	_next_btn = _chevron_btn(">")
	_next_btn.z_index = 20
	_next_btn.pressed.connect(_on_next_stage)
	mid.add_child(_next_btn)

	_status_lbl = Label.new()
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.add_theme_font_size_override("font_size", 15)
	_status_lbl.modulate = TEAL
	area.add_child(_status_lbl)

	_reward_lbl = Label.new()
	_reward_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reward_lbl.add_theme_font_size_override("font_size", 12)
	_reward_lbl.modulate = MUTED
	_reward_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	area.add_child(_reward_lbl)

func _build_side_rails() -> void:
	# Compact side shortcuts near the top — keep clear of the stage arrows.
	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	left.offset_left = 10
	left.offset_top = 100
	left.offset_right = 96
	left.offset_bottom = 170
	left.add_theme_constant_override("separation", 10)
	add_child(left)
	left.add_child(_side_btn("Sandbox", Color(0.45, 0.9, 0.85), _on_sandbox_pressed))

	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.offset_left = -96
	right.offset_top = 100
	right.offset_right = -10
	right.offset_bottom = 170
	right.add_theme_constant_override("separation", 10)
	add_child(right)
	right.add_child(_side_btn("Rank", Color(1.0, 0.75, 0.4), _on_leaderboard_pressed))

func _build_battle_row() -> void:
	var row := VBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	row.offset_left = 48
	row.offset_right = -48
	row.offset_top = -200
	row.offset_bottom = -110
	row.add_theme_constant_override("separation", 6)
	add_child(row)

	_battle_btn = Button.new()
	_battle_btn.text = "Battle"
	_battle_btn.custom_minimum_size = Vector2(0, 64)
	_battle_btn.add_theme_font_size_override("font_size", 26)
	_style_primary_btn(_battle_btn)
	_battle_btn.pressed.connect(_on_battle_pressed)
	row.add_child(_battle_btn)

func _build_bottom_nav() -> void:
	var nav := PanelContainer.new()
	nav.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	nav.offset_top = -96
	nav.add_theme_stylebox_override("panel", _round_style(Color(0.05, 0.12, 0.12, 0.98), TEAL_DIM, 0, 2))
	add_child(nav)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	nav.add_child(row)

	row.add_child(_nav_item("Shop", false, _on_shop_pressed))
	row.add_child(_nav_item("Gear", false, _on_character_pressed))
	row.add_child(_nav_item("Battle", true, func(): pass))
	row.add_child(_nav_item("Skills", false, _on_skill_tree_pressed))
	row.add_child(_nav_item("Settings", false, _on_settings_pressed))

# --- Helpers ---

func _round_style(bg: Color, border: Color, radius: int, border_w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(10)
	return s

func _style_primary_btn(btn: Button) -> void:
	var n := _round_style(TEAL, Color(0.55, 0.95, 0.9), 18, 0)
	var h := _round_style(Color(0.4, 0.9, 0.85), Color(0.7, 1.0, 0.95), 18, 0)
	var p := _round_style(TEAL_DIM, TEAL, 18, 0)
	var d := _round_style(Color(0.18, 0.22, 0.22), Color(0.3, 0.35, 0.35), 18, 0)
	btn.add_theme_stylebox_override("normal", n)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_stylebox_override("pressed", p)
	btn.add_theme_stylebox_override("disabled", d)
	btn.add_theme_color_override("font_color", Color(0.05, 0.12, 0.12))
	btn.add_theme_color_override("font_hover_color", Color(0.05, 0.12, 0.12))
	btn.add_theme_color_override("font_pressed_color", Color(0.7, 0.9, 0.88))
	btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.5, 0.5))

func _tab_btn(text: String, active: bool) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(110, 34)
	btn.toggle_mode = true
	btn.button_pressed = active
	_style_tab(btn, active)
	return btn

func _style_tab(btn: Button, active: bool) -> void:
	var bg := TEAL if active else Color(0.12, 0.14, 0.15)
	var bd := TEAL if active else Color(0.25, 0.3, 0.32)
	btn.add_theme_stylebox_override("normal", _round_style(bg, bd, 12, 1))
	btn.add_theme_stylebox_override("hover", _round_style(TEAL_DIM if not active else TEAL, TEAL, 12, 1))
	btn.add_theme_stylebox_override("pressed", _round_style(TEAL, TEAL, 12, 1))
	btn.add_theme_color_override("font_color", Color(0.05, 0.1, 0.1) if active else MUTED)

func _chevron_btn(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(56, 88)
	btn.add_theme_font_size_override("font_size", 36)
	var s := _round_style(Color(0.08, 0.16, 0.16, 0.7), TEAL_DIM, 12, 1)
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", _round_style(TEAL_DIM, TEAL, 12, 1))
	btn.add_theme_stylebox_override("pressed", _round_style(TEAL, TEAL, 12, 1))
	btn.add_theme_stylebox_override("disabled", _round_style(Color(0.08, 0.08, 0.08, 0.4), Color(0.2, 0.2, 0.2), 12, 1))
	btn.add_theme_color_override("font_color", TEAL)
	btn.add_theme_color_override("font_disabled_color", Color(0.3, 0.35, 0.35))
	return btn

func _icon_btn(text: String, size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = size
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_stylebox_override("normal", _round_style(PANEL, TEAL_DIM, 12, 1))
	btn.add_theme_stylebox_override("hover", _round_style(TEAL_DIM, TEAL, 12, 1))
	btn.add_theme_color_override("font_color", TEAL)
	return btn

func _side_btn(text: String, color: Color, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(78, 54)
	btn.add_theme_font_size_override("font_size", 12)
	btn.add_theme_stylebox_override("normal", _round_style(PANEL, color.darkened(0.35), 12, 1))
	btn.add_theme_stylebox_override("hover", _round_style(color.darkened(0.55), color, 12, 1))
	btn.add_theme_color_override("font_color", color)
	btn.pressed.connect(cb)
	return btn

func _nav_item(text: String, active: bool, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 72)
	btn.add_theme_font_size_override("font_size", 12)
	if active:
		btn.add_theme_stylebox_override("normal", _round_style(TEAL, TEAL, 14, 0))
		btn.add_theme_color_override("font_color", Color(0.05, 0.12, 0.12))
	else:
		btn.add_theme_stylebox_override("normal", _round_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 14, 0))
		btn.add_theme_stylebox_override("hover", _round_style(TEAL_DIM, TEAL_DIM, 14, 0))
		btn.add_theme_color_override("font_color", MUTED)
		btn.add_theme_color_override("font_hover_color", TEAL)
	btn.pressed.connect(cb)
	return btn

func _max_browse_stage() -> int:
	# Allow peeking one locked stage past the frontier.
	return PlayerData.get_max_playable_stage() + 1

func _is_locked(stage: int) -> bool:
	return stage > PlayerData.get_max_playable_stage()

func _refresh_stage_view() -> void:
	_view_stage = clampi(_view_stage, 1, _max_browse_stage())
	var infinity := _play_mode == "infinity"
	var locked := (not infinity) and _is_locked(_view_stage)
	var boss := PlayerData.is_boss_stage(_view_stage)

	_level_lbl.text = str(PlayerData.char_level)
	_name_lbl.text = PlayerData.player_name
	_coins_lbl.text = str(PlayerData.coins)

	_prev_btn.visible = not infinity
	_next_btn.visible = not infinity
	_prev_btn.disabled = infinity or _view_stage <= 1
	_next_btn.disabled = infinity or _view_stage >= _max_browse_stage()

	if infinity:
		_stage_title.text = "INFINITY MODE"
		_stage_sub.text = "Endless escalating waves"
		_boss_badge.visible = false
		_lock_lbl.visible = false
		_stage_center.visible = false
		_infinity_stats.visible = true
		var best := _get_infinity_best()
		var waves: int = int(best.get("waves", 0))
		var time_sec: float = float(best.get("time_sec", 0.0))
		if waves <= 0:
			_inf_wave_lbl.text = "Wave —"
			_inf_time_lbl.text = "Time —"
			_status_lbl.text = "No runs yet — set your first record"
		else:
			_inf_wave_lbl.text = "Wave %d" % waves
			_inf_time_lbl.text = "Time  %s" % _format_time(time_sec)
			_status_lbl.text = "Beat your best to climb the ranks"
		_reward_lbl.text = "Ranks by wave reached, then time"
		_battle_btn.disabled = false
		_battle_btn.text = "Battle"
	else:
		_stage_title.text = "NORMAL STAGE %d" % _view_stage
		_stage_sub.text = PlayerData.get_stage_name(_view_stage)
		_boss_badge.visible = boss and not locked
		_lock_lbl.visible = locked
		_stage_center.visible = not locked
		_infinity_stats.visible = false
		_stage_center_num.text = str(_view_stage)
		_stage_center_name.text = PlayerData.get_stage_name(_view_stage)
		if locked:
			_status_lbl.text = "Locked — clear Stage %d first" % PlayerData.get_max_playable_stage()
			_reward_lbl.text = "Reach this stage to unlock Battle"
			_battle_btn.disabled = true
			_battle_btn.text = "Locked"
		else:
			var preview: Dictionary = PlayerData.get_stage_reward_preview(_view_stage)
			if bool(preview.get("is_replay", false)):
				_status_lbl.text = "Replay — Stage %d cleared" % _view_stage
			elif boss:
				_status_lbl.text = "Boss stage — high rewards"
			else:
				_status_lbl.text = "Frontier stage — clear to advance"
			_reward_lbl.text = String(preview.get("summary", ""))
			_battle_btn.disabled = false
			_battle_btn.text = "Battle"

	_style_tab(_normal_tab, not infinity)
	_style_tab(_infinity_tab, infinity)
	_normal_tab.button_pressed = not infinity
	_infinity_tab.button_pressed = infinity

func _set_play_mode(mode: String) -> void:
	_play_mode = mode
	_refresh_stage_view()

func _format_time(sec: float) -> String:
	var total := maxi(0, int(sec))
	var m := total / 60
	var s := total % 60
	return "%02d:%02d" % [m, s]

func _get_infinity_best() -> Dictionary:
	var best_waves := 0
	var best_time := 0.0
	var found := false
	for e in PlayerData.get_infinity_leaderboard():
		if not (e is Dictionary):
			continue
		if String(e.get("name", "")) != PlayerData.player_name:
			continue
		var w: int = int(e.get("waves", 0))
		var t: float = float(e.get("time_sec", 0.0))
		if not found or w > best_waves or (w == best_waves and t < best_time):
			best_waves = w
			best_time = t
			found = true
	if not found:
		return {"waves": 0, "time_sec": 0.0}
	return {"waves": best_waves, "time_sec": best_time}

func _on_prev_stage() -> void:
	if _play_mode != "normal":
		return
	_view_stage = maxi(1, _view_stage - 1)
	_refresh_stage_view()

func _on_next_stage() -> void:
	if _play_mode != "normal":
		return
	_view_stage = mini(_max_browse_stage(), _view_stage + 1)
	_refresh_stage_view()

func _unhandled_input(event: InputEvent) -> void:
	if _play_mode != "normal":
		return
	if event.is_action_pressed("ui_left") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_LEFT):
		_on_prev_stage()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right") or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_RIGHT):
		_on_next_stage()
		get_viewport().set_input_as_handled()

func _on_battle_pressed() -> void:
	if _play_mode == "infinity":
		_on_infinity_pressed()
		return
	if _is_locked(_view_stage):
		return
	PlayerData.tower_test_mode = false
	PlayerData.session_mode = "normal"
	PlayerData.set_selected_stage(_view_stage)
	PlayerData.save_data()
	get_tree().change_scene_to_file("res://scenes/game.tscn")

func _build_leaderboard_overlay() -> void:
	_leaderboard_panel = PanelContainer.new()
	_leaderboard_panel.visible = false
	_leaderboard_panel.set_anchors_preset(Control.PRESET_CENTER)
	_leaderboard_panel.custom_minimum_size = Vector2(360, 460)
	_leaderboard_panel.offset_left = -180
	_leaderboard_panel.offset_top = -230
	_leaderboard_panel.offset_right = 180
	_leaderboard_panel.offset_bottom = 230
	_leaderboard_panel.add_theme_stylebox_override("panel", _round_style(Color(0.06, 0.08, 0.12, 0.98), Color(1.0, 0.55, 0.95, 0.55), 14, 2))
	add_child(_leaderboard_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_leaderboard_panel.add_child(vbox)

	var lb_title := Label.new()
	lb_title.text = "INFINITY LEADERBOARD"
	lb_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb_title.add_theme_font_size_override("font_size", 18)
	lb_title.modulate = Color(1.0, 0.55, 0.95)
	vbox.add_child(lb_title)

	_leaderboard_box = VBoxContainer.new()
	_leaderboard_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_leaderboard_box)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(120, 40)
	close_btn.pressed.connect(func(): _leaderboard_panel.visible = false)
	vbox.add_child(close_btn)

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
		empty.modulate = MUTED
		_leaderboard_box.add_child(empty)
		return
	for i in board.size():
		var e: Dictionary = board[i]
		var tm := int(float(e.get("time_sec", 0.0))) / 60
		var ts := int(float(e.get("time_sec", 0.0))) % 60
		var row := Label.new()
		row.text = "%d. %s\n   Wave %d  •  %02d:%02d" % [
			i + 1, String(e.get("name", "?")), int(e.get("waves", 0)), tm, ts
		]
		row.add_theme_font_size_override("font_size", 12)
		if String(e.get("name", "")) == PlayerData.player_name:
			row.modulate = TEAL
		_leaderboard_box.add_child(row)

func _on_leaderboard_pressed() -> void:
	_refresh_leaderboard()
	_leaderboard_panel.visible = true
	_leaderboard_panel.move_to_front()

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
