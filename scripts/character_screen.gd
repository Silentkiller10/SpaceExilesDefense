extends Control

## Hub Character screen: equipment panel art + gear rows.

const CharacterVisualScript = preload("res://scripts/character_visual.gd")

var _focus_slots: Array = []
var _selected_row: int = 0

func _ready() -> void:
	_build_ui()

func _selected_row_def() -> Dictionary:
	if _selected_row < 0 or _selected_row >= PlayerData.GEAR_ROWS.size():
		_selected_row = 0
	return PlayerData.GEAR_ROWS[_selected_row]

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.06)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 12
	root.offset_top = 12
	root.offset_right = -12
	root.offset_bottom = -12
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	var title := Label.new()
	title.text = "CHARACTER"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 26)
	title.modulate = Color(0.35, 0.9, 1.0)
	header.add_child(title)

	var shop_btn := Button.new()
	shop_btn.text = "Shop"
	shop_btn.custom_minimum_size = Vector2(90, 36)
	shop_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/shop.tscn"))
	header.add_child(shop_btn)

	var skills_btn := Button.new()
	skills_btn.text = "Skills"
	skills_btn.custom_minimum_size = Vector2(90, 36)
	skills_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/skill_tree.tscn"))
	header.add_child(skills_btn)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(90, 36)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/mainmenu.tscn"))
	header.add_child(back)

	var stats := Label.new()
	stats.text = "Lv %d (%d/%d XP)  |  SP: %d  |  Coins: %d" % [
		PlayerData.char_level,
		PlayerData.char_xp,
		PlayerData.xp_for_level(PlayerData.char_level),
		PlayerData.skill_points,
		PlayerData.coins
	]
	stats.add_theme_font_size_override("font_size", 13)
	root.add_child(stats)

	var total_panel := PanelContainer.new()
	root.add_child(total_panel)
	var total_box := VBoxContainer.new()
	total_panel.add_child(total_box)
	var total_title := Label.new()
	total_title.text = "TOTAL EQUIPPED STATS"
	total_title.add_theme_font_size_override("font_size", 14)
	total_title.modulate = Color(1.0, 0.85, 0.35)
	total_box.add_child(total_title)
	var total_stats := Label.new()
	total_stats.text = PlayerData.get_equipped_stats_summary()
	total_stats.add_theme_font_size_override("font_size", 13)
	total_box.add_child(total_stats)

	# Equipment paper-doll
	var art_wrap := CenterContainer.new()
	art_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.add_child(art_wrap)

	var panel_w := 260.0
	var art_panel := PanelContainer.new()
	art_panel.custom_minimum_size = Vector2(
		panel_w,
		panel_w * CharacterVisualScript.EQUIPMENT_PANEL_H_OVER_W
	)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.05, 0.09, 0.95)
	panel_style.border_color = Color(0.35, 0.9, 1.0, 0.45)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.content_margin_left = 0
	panel_style.content_margin_top = 0
	panel_style.content_margin_right = 0
	panel_style.content_margin_bottom = 0
	art_panel.add_theme_stylebox_override("panel", panel_style)
	art_wrap.add_child(art_panel)

	var art_host := Control.new()
	art_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art_panel.add_child(art_host)

	var overlay := CharacterVisualScript.build_equipment_panel(art_host)

	for entry in CharacterVisualScript.get_equipment_slot_layout():
		var slot_name: String = String(entry["slot"])
		var group: Array = entry.get("group", [slot_name])
		var display_slot := String(group[0])
		var equipped_item: Dictionary = PlayerData.get_equipped_item(display_slot)
		if equipped_item.is_empty() and group.size() > 1:
			for s in group:
				var it: Dictionary = PlayerData.get_equipped_item(String(s))
				if not it.is_empty():
					equipped_item = it
					display_slot = String(s)
					break

		var focused := false
		for s in group:
			if String(s) in _focus_slots:
				focused = true
				break

		var highlight := Panel.new()
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		highlight.z_index = 1
		CharacterVisualScript.apply_equipment_slot_rect(highlight, entry, 0.0)
		var hl_style := StyleBoxFlat.new()
		if focused:
			hl_style.bg_color = Color(0.25, 0.95, 1.0, 0.14)
			hl_style.border_color = Color(0.45, 1.0, 1.0, 0.95)
			hl_style.set_border_width_all(3)
		elif not equipped_item.is_empty():
			hl_style.bg_color = Color(1.0, 0.85, 0.25, 0.08)
			hl_style.border_color = PlayerData.rarity_border_color(String(equipped_item.get("rarity", "common")))
			hl_style.set_border_width_all(2)
		else:
			hl_style.bg_color = Color(0.03, 0.04, 0.07, 0.88)
			hl_style.border_color = Color(0.25, 0.7, 0.9, 0.55)
			hl_style.set_border_width_all(2)
		hl_style.set_corner_radius_all(8)
		highlight.add_theme_stylebox_override("panel", hl_style)
		overlay.add_child(highlight)

		var slot_icon := TextureRect.new()
		var slot_tex: Texture2D = PlayerData.load_slot_texture(display_slot)
		if slot_tex != null:
			slot_icon.texture = slot_tex
			slot_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			slot_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			CharacterVisualScript.apply_equipment_slot_rect(slot_icon, entry, 0.0)
			slot_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot_icon.z_index = 2
			slot_icon.modulate = Color(1, 1, 1, 1) if not equipped_item.is_empty() else Color(0.65, 0.65, 0.7, 0.85)
			overlay.add_child(slot_icon)

		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.flat = true
		btn.z_index = 3
		CharacterVisualScript.apply_equipment_slot_rect(btn, entry, 0.0)
		btn.tooltip_text = _slot_tooltip(group)
		btn.modulate = Color(1.0, 1.0, 1.0, 0.02)
		btn.pressed.connect(_focus_row.bind(group))
		overlay.add_child(btn)

	# Equipped ring chips
	var ring_row := HBoxContainer.new()
	ring_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ring_row.add_theme_constant_override("separation", 8)
	root.add_child(ring_row)
	for ring_slot in ["Ring1", "Ring2"]:
		var chip := Button.new()
		var item: Dictionary = PlayerData.get_equipped_item(ring_slot)
		chip.icon = PlayerData.load_slot_texture(ring_slot)
		chip.expand_icon = true
		chip.add_theme_constant_override("icon_max_width", 36)
		chip.text = " %s: %s" % [ring_slot, "—" if item.is_empty() else String(item.get("name", "?"))]
		chip.custom_minimum_size = Vector2(0, 44)
		chip.pressed.connect(_select_rings)
		ring_row.add_child(chip)

	var inv_title := Label.new()
	inv_title.text = "GEAR — pick a type, then tap to equip"
	inv_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inv_title.add_theme_font_size_override("font_size", 14)
	inv_title.modulate = Color(0.7, 0.9, 1.0)
	root.add_child(inv_title)

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
	scroll.custom_minimum_size = Vector2(0, 200)
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	var row_slots: Array = _selected_row_def()["slots"]
	var items: Array = _items_for_slots(row_slots)
	if items.is_empty():
		var empty := Label.new()
		empty.text = "No %s yet.\nFarm stages or buy from Shop." % String(_selected_row_def()["title"]).to_lower()
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		list.add_child(empty)
	else:
		for item in items:
			list.add_child(_make_item_row(item))

func _items_for_slots(slots: Array) -> Array:
	var out: Array = []
	for item in PlayerData.inventory:
		var item_slot := String(item.get("slot", ""))
		if item_slot in slots:
			out.append(item)
			continue
		# Ring templates can show in Rings row regardless of Ring1/Ring2 template tag
		if ("Ring1" in slots or "Ring2" in slots) and (item_slot == "Ring1" or item_slot == "Ring2"):
			if item not in out:
				out.append(item)
	return out

func _make_item_row(item: Dictionary) -> Control:
	var item_slot: String = String(item.get("slot", ""))
	var uid: String = String(item.get("uid", ""))
	var is_on := false
	for s in PlayerData.SLOT_NAMES:
		if String(PlayerData.equipped.get(s, "")) == uid:
			is_on = true
			break

	var row := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.09, 0.14, 0.95)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.set_corner_radius_all(6)
	style.set_border_width_all(2)
	style.border_color = PlayerData.rarity_border_color(String(item.get("rarity", "common")))
	row.add_theme_stylebox_override("panel", style)

	var row_h := HBoxContainer.new()
	row_h.add_theme_constant_override("separation", 10)
	row.add_child(row_h)

	# Content lays out normally (not clipped inside a fixed-height button)
	var content := HBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	content.mouse_filter = Control.MOUSE_FILTER_STOP
	content.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_equip(uid)
	)
	row_h.add_child(content)

	var gicon := PlayerData.make_gear_icon(item_slot, Vector2(56, 56), item)
	gicon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gicon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	content.add_child(gicon)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(info)

	var name_l := Label.new()
	name_l.text = "%s%s" % [String(item.get("name", "?")), "  · EQUIPPED" if is_on else ""]
	name_l.add_theme_font_size_override("font_size", 15)
	name_l.modulate = Color(1.0, 0.92, 0.55) if is_on else Color(0.95, 0.97, 1.0)
	info.add_child(name_l)

	var rarity_l := Label.new()
	rarity_l.text = String(item.get("rarity", "common")).to_upper()
	rarity_l.add_theme_font_size_override("font_size", 11)
	rarity_l.modulate = PlayerData.rarity_border_color(String(item.get("rarity", "common")))
	info.add_child(rarity_l)

	# One modifier per line — full horizontal text, easy to read
	for mod in PlayerData.get_item_mods(item):
		if typeof(mod) != TYPE_DICTIONARY:
			continue
		var line := PlayerData.format_bonus(String(mod.get("bonus", "")), float(mod.get("amount", 0.0)))
		if line == "":
			continue
		var mod_l := Label.new()
		mod_l.text = line
		mod_l.add_theme_font_size_override("font_size", 13)
		mod_l.modulate = Color(0.78, 0.92, 1.0)
		info.add_child(mod_l)

	var sell_price: int = PlayerData.get_sell_price(item)
	var sell_btn := Button.new()
	sell_btn.text = "Sell\n%d" % sell_price
	sell_btn.custom_minimum_size = Vector2(72, 64)
	sell_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sell_btn.add_theme_font_size_override("font_size", 12)
	sell_btn.modulate = Color(1.0, 0.7, 0.45)
	sell_btn.pressed.connect(_sell.bind(uid))
	row_h.add_child(sell_btn)
	return row

func _sell(uid: String) -> void:
	var result: Dictionary = PlayerData.try_sell_uid(uid)
	if bool(result.get("ok", false)):
		_build_ui()

func _slot_tooltip(group: Array) -> String:
	var parts: PackedStringArray = []
	for s in group:
		var item: Dictionary = PlayerData.get_equipped_item(String(s))
		if item.is_empty():
			parts.append("%s: empty" % s)
		else:
			parts.append("%s: %s\n%s" % [
				s,
				String(item.get("name", "?")),
				PlayerData.format_item_stats(item)
			])
	return "\n".join(parts)

func _slot_status_text(group: Array) -> String:
	if group.size() == 1:
		var item: Dictionary = PlayerData.get_equipped_item(String(group[0]))
		return "" if item.is_empty() else String(item.get("name", ""))
	var lines: PackedStringArray = []
	for s in group:
		var item: Dictionary = PlayerData.get_equipped_item(String(s))
		lines.append("—" if item.is_empty() else String(item.get("name", "?")))
	return "\n".join(lines)

func _focus_row(group: Array) -> void:
	_focus_slots = []
	for s in group:
		_focus_slots.append(String(s))
	# Select matching category tab
	for i in PlayerData.GEAR_ROWS.size():
		var slots: Array = PlayerData.GEAR_ROWS[i]["slots"]
		for s in group:
			if String(s) in slots:
				_selected_row = i
				_build_ui()
				return
	_build_ui()

func _select_row(index: int) -> void:
	_selected_row = index
	_focus_slots = []
	for s in PlayerData.GEAR_ROWS[index]["slots"]:
		_focus_slots.append(String(s))
	_build_ui()

func _select_rings() -> void:
	for i in PlayerData.GEAR_ROWS.size():
		if String(PlayerData.GEAR_ROWS[i]["title"]) == "RINGS":
			_select_row(i)
			return
	_select_row(PlayerData.GEAR_ROWS.size() - 1)

func _equip(uid: String) -> void:
	for s in PlayerData.SLOT_NAMES:
		if String(PlayerData.equipped.get(s, "")) == uid:
			PlayerData.unequip_slot(s)
			_build_ui()
			return
	PlayerData.equip_uid(uid)
	_build_ui()
