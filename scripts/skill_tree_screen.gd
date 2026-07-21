extends Control

## Column-style skill tree: three vertical branches under a CORE node,
## hex skill icons linked by right-angle connectors. Pan + zoom.

var _detail: Label
var _selected_id: String = "core"
var _board_scroll: ScrollContainer
var _board: Control
var _board_holder: Control
var _zoom_label: Label
var _zoom: float = 0.55
var _scroll_pos: Vector2 = Vector2(-1, -1)
var _centered_once: bool = false

var _panning: bool = false
var _pan_moved: bool = false
var _pan_press_pos: Vector2 = Vector2.ZERO
var _pan_press_skill: String = ""
var _touch_index: int = -1

var _ui_built: bool = false
var _node_controls: Dictionary = {}
var _line_controls: Dictionary = {}
var _lvl_label: Label
var _summary_label: Label
var _node_lookup: Dictionary = {}
var _icon_cache: Dictionary = {}

const BOARD_W := 2400.0
const BOARD_H := 3400.0
const ZOOM_MIN := 0.28
const ZOOM_MAX := 2.8
const ZOOM_STEP := 1.12
const PAN_THRESHOLD := 10.0

const BRANCH_HEADERS := {
	"loot": {"x": 0.14, "label": "LOOT", "icon": "res://assets/png/skill_icons/Main_Loot.png"},
	"weapon": {"x": 0.38, "label": "WEAPON", "icon": "res://assets/png/skill_icons/Main_Weapon.png"},
	"tower": {"x": 0.62, "label": "TOWER", "icon": "res://assets/png/skill_icons/Main_Tower.png"},
	"active": {"x": 0.86, "label": "ACTIVE SKILLS", "icon": ""},
}

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	if _ui_built:
		_refresh_tree_state()
		return
	if _board_scroll != null and is_instance_valid(_board_scroll):
		_scroll_pos = Vector2(_board_scroll.scroll_horizontal, _board_scroll.scroll_vertical)

	for c in get_children():
		c.queue_free()

	var bg := ColorRect.new()
	bg.color = Color(0.015, 0.02, 0.05)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 10
	root.offset_top = 10
	root.offset_right = -10
	root.offset_bottom = -10
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	var title := Label.new()
	title.text = "SKILL TREE"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = Color(0.85, 0.75, 0.35)
	header.add_child(title)

	var zoom_out := Button.new()
	zoom_out.text = "−"
	zoom_out.custom_minimum_size = Vector2(40, 36)
	zoom_out.pressed.connect(func(): _zoom_by(1.0 / ZOOM_STEP))
	header.add_child(zoom_out)

	_zoom_label = Label.new()
	_zoom_label.custom_minimum_size = Vector2(58, 0)
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_label.add_theme_font_size_override("font_size", 13)
	_zoom_label.modulate = Color(0.85, 0.9, 1.0)
	header.add_child(_zoom_label)

	var zoom_in := Button.new()
	zoom_in.text = "+"
	zoom_in.custom_minimum_size = Vector2(40, 36)
	zoom_in.pressed.connect(func(): _zoom_by(ZOOM_STEP))
	header.add_child(zoom_in)

	var zoom_reset := Button.new()
	zoom_reset.text = "Fit"
	zoom_reset.custom_minimum_size = Vector2(56, 36)
	zoom_reset.pressed.connect(_reset_zoom)
	header.add_child(zoom_reset)

	var char_btn := Button.new()
	char_btn.text = "Gear"
	char_btn.custom_minimum_size = Vector2(90, 36)
	char_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/character.tscn"))
	header.add_child(char_btn)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(90, 36)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/mainmenu.tscn"))
	header.add_child(back)

	var lvl := Label.new()
	_lvl_label = lvl
	lvl.text = "Level %d   XP %d/%d   SP: %d" % [
		PlayerData.char_level,
		PlayerData.char_xp,
		PlayerData.xp_for_level(PlayerData.char_level),
		PlayerData.skill_points
	]
	lvl.add_theme_font_size_override("font_size", 13)
	lvl.modulate = Color(1.0, 0.9, 0.4)
	root.add_child(lvl)

	var legend := Label.new()
	legend.text = "Drag / touch to pan    ·    Scroll wheel to zoom"
	legend.add_theme_font_size_override("font_size", 11)
	legend.modulate = Color(0.65, 0.75, 0.9)
	root.add_child(legend)

	_board_scroll = ScrollContainer.new()
	_board_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_board_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_board_scroll.gui_input.connect(_on_board_gui_input)
	root.add_child(_board_scroll)

	_board_holder = Control.new()
	_board_scroll.add_child(_board_holder)

	_board = Control.new()
	_board.custom_minimum_size = Vector2(BOARD_W, BOARD_H)
	_board.size = Vector2(BOARD_W, BOARD_H)
	_board.mouse_filter = Control.MOUSE_FILTER_STOP
	_board.gui_input.connect(_on_board_gui_input)
	_board_holder.add_child(_board)

	var board_bg := ColorRect.new()
	board_bg.color = Color(0.03, 0.035, 0.06)
	board_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	board_bg.gui_input.connect(_on_board_gui_input)
	_board.add_child(board_bg)

	# Column background panels — one tinted slab per branch, like the reference.
	for branch in BRANCH_HEADERS.keys():
		var info: Dictionary = BRANCH_HEADERS[branch]
		var col := _branch_color(String(branch))
		var panel := Panel.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(col.r * 0.08, col.g * 0.08, col.b * 0.08, 0.55)
		style.border_color = Color(col.r, col.g, col.b, 0.22)
		style.set_border_width_all(2)
		style.set_corner_radius_all(18)
		panel.add_theme_stylebox_override("panel", style)
		panel.position = Vector2(float(info["x"]) * BOARD_W - BOARD_W * 0.112, BOARD_H * 0.075)
		panel.size = Vector2(BOARD_W * 0.224, BOARD_H * 0.88)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_board.add_child(panel)

	var nodes: Array = PlayerData.get_skill_nodes()
	_node_lookup.clear()
	for n in nodes:
		_node_lookup[String(n["id"])] = n
	var pos_map: Dictionary = {}
	for n in nodes:
		pos_map[String(n["id"])] = Vector2(float(n["x"]) * BOARD_W, float(n["y"]) * BOARD_H)

	# Header centers used so connectors pass under the main branch icons.
	var header_pos: Dictionary = {}
	for branch in BRANCH_HEADERS.keys():
		var info: Dictionary = BRANCH_HEADERS[branch]
		header_pos[String(branch)] = Vector2(float(info["x"]) * BOARD_W, BOARD_H * 0.115)

	# Connectors first (under icons).
	for n in nodes:
		var req: String = String(n.get("requires", ""))
		if req == "" or not pos_map.has(req):
			continue
		var from: Vector2 = pos_map[req]
		var to: Vector2 = pos_map[String(n["id"])]
		var nid: String = String(n["id"])
		var line := Line2D.new()
		line.width = 3.0
		line.z_index = 0
		line.default_color = Color(0.22, 0.24, 0.3, 0.4)
		# Core → first branch node: route through that branch's main icon.
		if req == "core" and header_pos.has(String(n.get("branch", ""))):
			var hub: Vector2 = header_pos[String(n["branch"])]
			line.points = PackedVector2Array([
				from,
				Vector2(from.x, (from.y + hub.y) * 0.5),
				Vector2(hub.x, (from.y + hub.y) * 0.5),
				hub,
				to
			])
		elif absf(from.x - to.x) < 2.0 or absf(from.y - to.y) < 2.0:
			line.points = PackedVector2Array([from, to])
		else:
			var mid_y := (from.y + to.y) * 0.5
			line.points = PackedVector2Array([
				from, Vector2(from.x, mid_y), Vector2(to.x, mid_y), to
			])
		_board.add_child(line)
		_line_controls[nid] = line

	# Branch header icons (drawn above lines).
	for branch in BRANCH_HEADERS.keys():
		var info: Dictionary = BRANCH_HEADERS[branch]
		_draw_branch_header(
			header_pos[String(branch)],
			String(info["label"]),
			_branch_color(String(branch)),
			String(info.get("icon", ""))
		)

	# Cluster name tags beside entry nodes.
	for n in nodes:
		if not bool(n.get("cluster_entry", false)):
			continue
		var cname := String(n.get("cluster_name", ""))
		if cname == "":
			continue
		var col := _branch_color(String(n.get("branch", "core")))
		var tag := Label.new()
		tag.text = cname.to_upper()
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", 13)
		tag.modulate = Color(col.r, col.g, col.b, 0.75)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.z_index = 2
		var p_tag: Vector2 = pos_map[String(n["id"])]
		tag.custom_minimum_size = Vector2(160.0, 16.0)
		tag.position = p_tag + Vector2(-80.0, -64.0)
		_board.add_child(tag)

	# Nodes — hex skill icons / circular core (above lines).
	for n in nodes:
		var id: String = String(n["id"])
		var p: Vector2 = pos_map[id]
		var is_core := id == "core"
		var is_key := bool(n.get("keystone", false)) or is_core
		var is_notable := bool(n.get("cluster_notable", false)) and not is_key
		var icon_size := Vector2(128, 128) if is_core else (Vector2(96, 96) if is_key else (Vector2(80, 80) if is_notable else Vector2(68, 68)))

		var node := Control.new()
		node.custom_minimum_size = icon_size
		node.size = icon_size
		node.position = p - icon_size * 0.5
		node.mouse_filter = Control.MOUSE_FILTER_STOP
		node.z_index = 3
		node.gui_input.connect(_on_node_gui_input.bind(id))
		_board.add_child(node)
		_node_controls[id] = node

		var icon_tex := _get_icon_texture(PlayerData.get_skill_icon_path(n))
		if icon_tex != null:
			var tex := TextureRect.new()
			tex.texture = icon_tex
			tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			node.add_child(tex)
		else:
			# Fallback hex + name if an icon is missing.
			var col := _branch_color(String(n.get("branch", "core")))
			var hex_r := icon_size.x * 0.42
			var hex_fill := Polygon2D.new()
			hex_fill.polygon = _hex_points(hex_r)
			hex_fill.position = icon_size * 0.5
			hex_fill.color = Color(col.r * 0.16, col.g * 0.16, col.b * 0.16, 0.95)
			node.add_child(hex_fill)
			var hex_border := Line2D.new()
			var border_pts := _hex_points(hex_r)
			border_pts.append(border_pts[0])
			hex_border.points = border_pts
			hex_border.position = icon_size * 0.5
			hex_border.width = 4.0
			hex_border.default_color = col
			node.add_child(hex_border)
			var name_label := Label.new()
			name_label.text = String(n["name"])
			name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			name_label.add_theme_font_size_override("font_size", 11)
			name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			name_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			node.add_child(name_label)

	_detail = Label.new()
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD
	_detail.custom_minimum_size = Vector2(0, 72)
	_detail.add_theme_font_size_override("font_size", 13)
	root.add_child(_detail)

	var unlock_btn := Button.new()
	unlock_btn.text = "Unlock Selected"
	unlock_btn.custom_minimum_size = Vector2(0, 40)
	unlock_btn.pressed.connect(_unlock_selected)
	root.add_child(unlock_btn)

	var summary := Label.new()
	_summary_label = summary
	summary.text = "Active: " + PlayerData.get_skill_summary().replace("\n", "  ·  ")
	summary.add_theme_font_size_override("font_size", 11)
	summary.modulate = Color(0.7, 0.95, 0.8)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(summary)

	_apply_zoom_visual()
	_ui_built = true
	if not _centered_once:
		_centered_once = true
		call_deferred("_center_on_core")
	else:
		call_deferred("_restore_scroll")
	_refresh_tree_state()

func _get_icon_texture(path: String) -> Texture2D:
	if path == "":
		return null
	if _icon_cache.has(path):
		return _icon_cache[path]
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	_icon_cache[path] = tex
	return tex

func _hex_points(r: float) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	for i in 6:
		var a: float = TAU * float(i) / 6.0 - PI / 2.0
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts

func _draw_branch_header(center: Vector2, text: String, col: Color, icon_path: String = "") -> void:
	const ICON_SIZE := 148.0
	var icon_tex := _get_icon_texture(icon_path)
	if icon_tex != null:
		var tex := TextureRect.new()
		tex.texture = icon_tex
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tex.z_index = 2
		tex.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		tex.size = Vector2(ICON_SIZE, ICON_SIZE)
		tex.position = center - Vector2(ICON_SIZE * 0.5, ICON_SIZE * 0.5)
		_board.add_child(tex)
	else:
		# Fallback circle if the main icon is missing.
		var outer := Line2D.new()
		outer.width = 6.0
		outer.default_color = col
		var pts: PackedVector2Array = []
		for s in 32:
			var a: float = TAU * float(s) / 32.0
			pts.append(center + Vector2(cos(a), sin(a)) * 74.0)
		pts.append(pts[0])
		outer.points = pts
		_board.add_child(outer)
		var fill := Polygon2D.new()
		var fpts: PackedVector2Array = []
		for s in 32:
			var a: float = TAU * float(s) / 32.0
			fpts.append(Vector2(cos(a), sin(a)) * 70.0)
		fill.polygon = fpts
		fill.position = center
		fill.color = Color(col.r * 0.2, col.g * 0.2, col.b * 0.2, 0.95)
		_board.add_child(fill)

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.modulate = col.lightened(0.35)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = 2
	label.custom_minimum_size = Vector2(160, 28)
	label.position = center + Vector2(-80, ICON_SIZE * 0.5 + 4.0)
	_board.add_child(label)

func _refresh_tree_state() -> void:
	if _lvl_label:
		_lvl_label.text = "Level %d   XP %d/%d   SP: %d" % [
			PlayerData.char_level,
			PlayerData.char_xp,
			PlayerData.xp_for_level(PlayerData.char_level),
			PlayerData.skill_points
		]
	if _summary_label:
		_summary_label.text = "Active: " + PlayerData.get_skill_summary().replace("\n", "  ·  ")
	for id in _line_controls.keys():
		var line: Line2D = _line_controls[id]
		var n: Dictionary = PlayerData.get_skill_node(String(id))
		if n.is_empty():
			continue
		var req: String = String(n.get("requires", ""))
		var unlocked := PlayerData.is_skill_unlocked(String(id))
		var req_on := req != "" and PlayerData.is_skill_unlocked(req)
		line.width = 4.5 if unlocked else 3.0
		if unlocked:
			line.default_color = _branch_color(String(n.get("branch", "core"))).lightened(0.15)
			line.default_color.a = 0.95
		elif req_on:
			line.default_color = Color(0.55, 0.5, 0.35, 0.75)
		else:
			line.default_color = Color(0.22, 0.24, 0.3, 0.4)
	for id in _node_controls.keys():
		var node_ctrl: Control = _node_controls[id]
		var unlocked := PlayerData.is_skill_unlocked(String(id))
		var available := PlayerData.can_unlock_skill(String(id)) or (String(id) == "core" and unlocked)
		if unlocked:
			node_ctrl.modulate = Color(1, 1, 1, 1)
		elif available:
			node_ctrl.modulate = Color(0.95, 0.95, 0.9, 1)
		else:
			node_ctrl.modulate = Color(0.45, 0.45, 0.5, 0.75)
		if String(id) == _selected_id:
			node_ctrl.modulate = node_ctrl.modulate.lightened(0.25)
	_update_detail(_selected_id)

func _apply_zoom_visual() -> void:
	if _board == null or _board_holder == null:
		return
	_zoom = clampf(_zoom, ZOOM_MIN, ZOOM_MAX)
	_board.scale = Vector2(_zoom, _zoom)
	_board.position = Vector2.ZERO
	_board_holder.custom_minimum_size = Vector2(BOARD_W * _zoom, BOARD_H * _zoom)
	_board_holder.size = Vector2(BOARD_W * _zoom, BOARD_H * _zoom)
	if _zoom_label:
		_zoom_label.text = "%d%%" % int(round(_zoom * 100.0))

func _zoom_by(factor: float, pivot_in_view: Vector2 = Vector2(-1, -1)) -> void:
	if _board_scroll == null:
		return
	var old_zoom := _zoom
	var new_zoom := clampf(old_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(old_zoom, new_zoom):
		return

	var pivot := pivot_in_view
	if pivot.x < 0.0:
		pivot = _board_scroll.size * 0.5

	var board_pt := Vector2(
		(float(_board_scroll.scroll_horizontal) + pivot.x) / old_zoom,
		(float(_board_scroll.scroll_vertical) + pivot.y) / old_zoom
	)

	_zoom = new_zoom
	_apply_zoom_visual()

	_board_scroll.scroll_horizontal = int(round(board_pt.x * _zoom - pivot.x))
	_board_scroll.scroll_vertical = int(round(board_pt.y * _zoom - pivot.y))
	_scroll_pos = Vector2(_board_scroll.scroll_horizontal, _board_scroll.scroll_vertical)

func _reset_zoom() -> void:
	_zoom = 0.55
	_apply_zoom_visual()
	_center_on_core()

func _pan_by(delta: Vector2) -> void:
	if _board_scroll == null:
		return
	_board_scroll.scroll_horizontal = int(_board_scroll.scroll_horizontal - delta.x)
	_board_scroll.scroll_vertical = int(_board_scroll.scroll_vertical - delta.y)
	_scroll_pos = Vector2(_board_scroll.scroll_horizontal, _board_scroll.scroll_vertical)

func _begin_pan(pos: Vector2, skill_id: String = "") -> void:
	_panning = true
	_pan_moved = false
	_pan_press_pos = pos
	_pan_press_skill = skill_id

func _end_pan() -> void:
	if _panning and not _pan_moved and _pan_press_skill != "":
		_on_node_pressed(_pan_press_skill)
	_panning = false
	_pan_moved = false
	_pan_press_skill = ""
	_touch_index = -1

func _on_board_gui_input(event: InputEvent) -> void:
	_handle_pan_zoom_input(event, "")

func _on_node_gui_input(event: InputEvent, skill_id: String) -> void:
	_handle_pan_zoom_input(event, skill_id)

func _handle_pan_zoom_input(event: InputEvent, skill_id: String) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_by(ZOOM_STEP, mb.position)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_by(1.0 / ZOOM_STEP, mb.position)
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin_pan(mb.global_position, skill_id)
			else:
				_end_pan()
			accept_event()
			return

	if event is InputEventMouseMotion and _panning:
		var mm := event as InputEventMouseMotion
		if not _pan_moved and mm.global_position.distance_to(_pan_press_pos) >= PAN_THRESHOLD:
			_pan_moved = true
		if _pan_moved:
			_pan_by(mm.relative)
			accept_event()
		return

	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touch_index = st.index
			_begin_pan(st.position, skill_id)
		elif st.index == _touch_index:
			_end_pan()
		accept_event()
		return

	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index != _touch_index and _touch_index != -1:
			return
		if not _pan_moved and sd.position.distance_to(_pan_press_pos) >= PAN_THRESHOLD:
			_pan_moved = true
		if _pan_moved:
			_pan_by(sd.relative)
			accept_event()
		return

	if event is InputEventMagnifyGesture:
		var mag := event as InputEventMagnifyGesture
		_zoom_by(mag.factor, mag.position)
		accept_event()

func _center_on_core() -> void:
	if _board_scroll == null or not is_instance_valid(_board_scroll):
		return
	var view_w: float = maxf(1.0, _board_scroll.size.x)
	var view_h: float = maxf(1.0, _board_scroll.size.y)
	_board_scroll.scroll_horizontal = int(maxi(0, int(BOARD_W * 0.5 * _zoom - view_w * 0.5)))
	_board_scroll.scroll_vertical = 0
	_scroll_pos = Vector2(_board_scroll.scroll_horizontal, _board_scroll.scroll_vertical)

func _restore_scroll() -> void:
	if _board_scroll == null or not is_instance_valid(_board_scroll):
		return
	if _scroll_pos.x < 0.0:
		_center_on_core()
		return
	_board_scroll.scroll_horizontal = int(_scroll_pos.x)
	_board_scroll.scroll_vertical = int(_scroll_pos.y)

func _branch_color(branch: String) -> Color:
	match branch:
		"weapon":
			return Color(1.0, 0.45, 0.35)
		"tower":
			return Color(0.35, 0.75, 1.0)
		"loot":
			return Color(0.45, 1.0, 0.55)
		"active":
			return Color(0.8, 0.5, 1.0)
		_:
			return Color(0.85, 0.9, 1.0)

func _on_node_pressed(skill_id: String) -> void:
	_selected_id = skill_id
	if PlayerData.can_unlock_skill(skill_id):
		PlayerData.try_unlock_skill(skill_id)
	_refresh_tree_state()

func _update_detail(skill_id: String) -> void:
	var n: Dictionary = PlayerData.get_skill_node(skill_id)
	if n.is_empty() or _detail == null:
		return
	var state := "LOCKED"
	if PlayerData.is_skill_unlocked(skill_id):
		state = "ALLOCATED"
	elif PlayerData.can_unlock_skill(skill_id):
		state = "AVAILABLE (%d SP)" % int(n.get("cost", 1))
	var key_tag := "  [KEYSTONE]" if bool(n.get("keystone", false)) else ""
	var cluster_tag := ""
	if String(n.get("cluster_name", "")) != "":
		cluster_tag = "  ·  Cluster: %s" % String(n.get("cluster_name", ""))
	elif String(n.get("cluster", "")) != "":
		cluster_tag = "  ·  Cluster"
	_detail.text = "%s%s%s  —  %s\n%s" % [
		String(n.get("name", "?")),
		key_tag,
		cluster_tag,
		state,
		String(n.get("desc", ""))
	]
	_detail.modulate = _branch_color(String(n.get("branch", "core")))

func _unlock_selected() -> void:
	var result: Dictionary = PlayerData.try_unlock_skill(_selected_id)
	if bool(result.get("ok", false)):
		_refresh_tree_state()
	else:
		_update_detail(_selected_id)
		if _detail:
			_detail.text += "\n" + String(result.get("error", "Cannot unlock"))
