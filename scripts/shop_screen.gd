extends Control

## Gear shop — buy catalog items with coins, selectable category tabs.

var _status: Label
var _selected_row: int = 0

func _ready() -> void:
	MusicManager.play_menu_music()
	_build_ui()

func _selected_row_def() -> Dictionary:
	if _selected_row < 0 or _selected_row >= PlayerData.GEAR_ROWS.size():
		_selected_row = 0
	return PlayerData.GEAR_ROWS[_selected_row]

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_top = 16
	root.offset_right = -16
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	var title := Label.new()
	title.text = "GEAR SHOP"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 26)
	title.modulate = Color(1.0, 0.85, 0.3)
	header.add_child(title)

	var char_btn := Button.new()
	char_btn.text = "Character"
	char_btn.custom_minimum_size = Vector2(110, 36)
	char_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/character.tscn"))
	header.add_child(char_btn)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(100, 36)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/mainmenu.tscn"))
	header.add_child(back)

	var coins := Label.new()
	coins.text = "Your coins: %d" % PlayerData.coins
	coins.add_theme_font_size_override("font_size", 16)
	coins.modulate = Color(1.0, 0.9, 0.35)
	root.add_child(coins)

	var hint := Label.new()
	hint.text = "Higher stages unlock Epic / Legendary gear. Prices scale with rarity."
	hint.add_theme_font_size_override("font_size", 12)
	root.add_child(hint)

	_status = Label.new()
	_status.text = ""
	_status.add_theme_font_size_override("font_size", 13)
	_status.modulate = Color(0.5, 1.0, 0.7)
	root.add_child(_status)

	# Horizontal selectable category tabs
	var tabs_scroll := ScrollContainer.new()
	tabs_scroll.custom_minimum_size = Vector2(0, 48)
	tabs_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tabs_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(tabs_scroll)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	tabs_scroll.add_child(tabs)

	for i in PlayerData.GEAR_ROWS.size():
		var row_def: Dictionary = PlayerData.GEAR_ROWS[i]
		var tab := Button.new()
		tab.toggle_mode = true
		tab.button_pressed = (i == _selected_row)
		tab.custom_minimum_size = Vector2(88, 40)
		tab.text = String(row_def["title"])
		tab.add_theme_font_size_override("font_size", 11)
		if i == _selected_row:
			tab.modulate = Color(0.45, 1.0, 1.0)
		tab.pressed.connect(_select_row.bind(i))
		tabs.add_child(tab)

	var selected_lab := Label.new()
	selected_lab.text = String(_selected_row_def()["title"])
	selected_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selected_lab.add_theme_font_size_override("font_size", 15)
	selected_lab.modulate = Color(1.0, 0.85, 0.35)
	root.add_child(selected_lab)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	var row_slots: Array = _selected_row_def()["slots"]
	for t in PlayerData.get_catalog():
		if String(t["slot"]) not in row_slots:
			continue
		list.add_child(_make_shop_row(t))

func _select_row(index: int) -> void:
	_selected_row = index
	_build_ui()

func _make_shop_row(t: Dictionary) -> Control:
	var template_id: String = String(t["template_id"])
	var price: int = PlayerData.get_shop_price(t)
	var unlocked: bool = PlayerData.is_gear_unlocked(t)
	var can_afford: bool = unlocked and PlayerData.coins >= price
	var rarity: String = String(t.get("rarity", "common"))
	var min_stage: int = int(t.get("min_stage", 1))

	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.14, 0.95)
	style.border_color = PlayerData.rarity_border_color(rarity)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	row.add_theme_stylebox_override("panel", style)
	if not unlocked:
		row.modulate = Color(0.55, 0.55, 0.6, 0.9)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)

	var icon := PlayerData.make_gear_icon(String(t["slot"]), Vector2(72, 72), t)
	h.add_child(icon)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)

	var name_l := Label.new()
	name_l.text = "%s  [%s]" % [String(t["name"]), rarity.to_upper()]
	name_l.add_theme_font_size_override("font_size", 14)
	name_l.modulate = PlayerData.rarity_border_color(rarity)
	info.add_child(name_l)

	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 1)
	info.add_child(stats_box)
	if unlocked:
		for mod in PlayerData.get_template_mods(t):
			if typeof(mod) != TYPE_DICTIONARY:
				continue
			var line := PlayerData.format_bonus(String(mod.get("bonus", "")), float(mod.get("amount", 0.0)))
			if line == "":
				continue
			var stats_l := Label.new()
			stats_l.text = line
			stats_l.add_theme_font_size_override("font_size", 12)
			stats_l.modulate = Color(0.75, 0.9, 1.0)
			stats_box.add_child(stats_l)
	else:
		var stats_l := Label.new()
		stats_l.text = "Locked — reach stage %d" % min_stage
		stats_l.add_theme_font_size_override("font_size", 12)
		stats_l.modulate = Color(1.0, 0.55, 0.45)
		stats_box.add_child(stats_l)

	var buy := Button.new()
	if unlocked:
		buy.text = "%d coins" % price
	else:
		buy.text = "Stage %d" % min_stage
	buy.custom_minimum_size = Vector2(110, 44)
	buy.disabled = not can_afford
	buy.pressed.connect(_buy.bind(template_id))
	h.add_child(buy)
	return row

func _buy(template_id: String) -> void:
	var result: Dictionary = PlayerData.try_buy_template(template_id)
	if bool(result.get("ok", false)):
		var item: Dictionary = result.get("item", {})
		_status.text = "Bought %s for %d coins!" % [
			String(item.get("name", "gear")),
			int(result.get("price", 0))
		]
		_status.modulate = Color(0.5, 1.0, 0.7)
	else:
		_status.text = String(result.get("error", "Purchase failed"))
		_status.modulate = Color(1.0, 0.45, 0.45)
	_build_ui()
