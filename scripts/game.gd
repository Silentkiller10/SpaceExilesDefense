extends Node2D

var arena_size: Vector2
var enemy_list: Array = []
var kill_count: int = 0
var level: int = 1
var kills_to_next_level: int = 6
var run_time: float = 0.0
var game_over: bool = false
## Tower test range: all towers unlocked, endless waves, no progression/rewards
var test_mode: bool = false

var unlocked_towers: Dictionary = {
	"laser": false,
	"cannon": false,
	"machinegun": false,
	"railgun": false,
	"flamethrower": false,
	"rocket": false
}

var towers: Dictionary = {}
var upgrade_ui_container: Control
var ui_layer: CanvasLayer
var gear
var wave_manager

var level_label: Label
var char_level_label: Label
var xp_bar: ProgressBar
var xp_label: Label
var time_label: Label
var fort_hp_bar: ProgressBar
var fort_hp_label: Label
var wave_label: Label
var boss_banner: Label
var gear_panel: PanelContainer
var gear_slot_labels: Dictionary = {}
var game_over_panel: PanelContainer
var run_loot: Array = []
var run_coins_earned: int = 0
var cleared_stage_num: int = 1
var loot_toast: Label
var coins_label: Label
var pause_panel: PanelContainer
var is_paused_menu: bool = false
var run_upgrades: Array = [] # {name, id, desc} taken this run
## Sandbox: how many enemies each spawn button press creates (1 / 10 / 25)
var sandbox_spawn_amount: int = 1

@onready var camera: Camera2D = $Camera2D
@onready var background: ColorRect = $Background
@onready var sky_glow: Polygon2D = $SkyGlow
@onready var fortress = $Fortress
@onready var player: CharacterBody2D = $Player
@onready var towers_root: Node2D = $Towers
@onready var rand = RandomNumberGenerator.new()

var enemy_scene = preload("res://scenes/enemy.tscn")
var boss_scene = preload("res://scenes/boss_carrier.tscn")
const GearSystemScript = preload("res://scripts/gear.gd")
const UpgradeCardsScript = preload("res://scripts/upgrade_cards.gd")
const WaveManagerScript = preload("res://scripts/wave_manager.gd")
var tower_scenes := {
	"laser": preload("res://scenes/towers/tower_laser.tscn"),
	"cannon": preload("res://scenes/towers/tower_cannon.tscn"),
	"machinegun": preload("res://scenes/towers/tower_machinegun.tscn"),
	"railgun": preload("res://scenes/towers/tower_railgun.tscn"),
	"flamethrower": preload("res://scenes/towers/tower_flamethrower.tscn"),
	"rocket": preload("res://scenes/towers/tower_rocket.tscn")
}

func _ready():
	# Keep gameplay pausable — only the UI layer stays active while paused
	process_mode = Node.PROCESS_MODE_PAUSABLE
	arena_size = get_viewport_rect().size
	rand.randomize()
	if camera:
		camera.offset = Vector2.ZERO

	_setup_arena_visuals()
	fortress.setup(arena_size.x, arena_size.y)
	fortress.health_changed.connect(_on_fortress_health_changed)
	fortress.fortress_destroyed.connect(_on_fortress_destroyed)

	# Player fights from an elevated ramp walkway above the tower row
	var rampart_y := arena_size.y - 300.0
	_setup_ramp_walkway(rampart_y + 20.0)
	player.set_arena(arena_size.x, rampart_y)
	player.setup(Vector2(arena_size.x * 0.5, rampart_y))

	camera.position = arena_size * 0.5
	camera.make_current()

	test_mode = PlayerData.tower_test_mode
	if test_mode:
		# Sandbox: the character only fires while the mouse is clicked/held
		player.manual_fire_only = true

	_spawn_tower_slots()
	if test_mode:
		# Test range: every tower available from the start
		for id in towers.keys():
			_unlock_tower(id)
	else:
		# Start with Laser + Machine Gun so towers carry early DPS
		_unlock_tower("laser")
		_unlock_tower("machinegun")

	gear = GearSystemScript.new()
	add_child(gear)
	gear.bind(player, fortress)

	wave_manager = WaveManagerScript.new()
	add_child(wave_manager)
	wave_manager.setup(arena_size.x, fortress.get_leak_y(), enemy_scene, boss_scene, player, fortress, PlayerData.selected_stage)
	if test_mode:
		wave_manager.set_test_mode(true)
		# Beefier fortress so tower testing lasts longer
		fortress.increase_max_health(1500)
	wave_manager.creep_spawned.connect(_on_creep_spawned)
	wave_manager.boss_incoming.connect(_on_boss_incoming)
	wave_manager.wave_started.connect(_on_wave_started)
	wave_manager.level_complete.connect(_on_level_complete)

	setup_ui()
	_on_fortress_health_changed(fortress.health, fortress.max_health)

func _setup_arena_visuals() -> void:
	if background:
		background.color = Color(0.04, 0.05, 0.09, 1.0)
		background.size = arena_size
		background.position = Vector2.ZERO
	if sky_glow:
		sky_glow.polygon = PackedVector2Array([
			Vector2(arena_size.x * 0.5 - 80, 0),
			Vector2(arena_size.x * 0.5 + 80, 0),
			Vector2(arena_size.x * 0.5 + 180, arena_size.y),
			Vector2(arena_size.x * 0.5 - 180, arena_size.y)
		])
		sky_glow.color = Color(0.15, 0.55, 0.85, 0.12)
	var city := get_node_or_null("CitySilhouette") as Polygon2D
	if city:
		var w := arena_size.x
		var h := arena_size.y
		city.polygon = PackedVector2Array([
			Vector2(0, h * 0.65), Vector2(w * 0.05, h * 0.58), Vector2(w * 0.1, h * 0.62),
			Vector2(w * 0.18, h * 0.5), Vector2(w * 0.25, h * 0.57), Vector2(w * 0.35, h * 0.45),
			Vector2(w * 0.45, h * 0.55), Vector2(w * 0.55, h * 0.4), Vector2(w * 0.65, h * 0.52),
			Vector2(w * 0.75, h * 0.42), Vector2(w * 0.85, h * 0.55), Vector2(w, h * 0.48),
			Vector2(w, h), Vector2(0, h)
		])
		city.color = Color(0.02, 0.03, 0.05, 0.85)

func _setup_ramp_walkway(surface_y: float) -> void:
	var ramp := Node2D.new()
	ramp.name = "RampWalkway"
	ramp.z_index = -10
	add_child(ramp)

	var w := arena_size.x
	var deck_h := 24.0
	var margin := 16.0
	var ground_y := arena_size.y - 80.0

	var deck := Polygon2D.new()
	deck.polygon = PackedVector2Array([
		Vector2(margin, surface_y),
		Vector2(w - margin, surface_y),
		Vector2(w - margin, surface_y + deck_h),
		Vector2(margin, surface_y + deck_h)
	])
	deck.color = Color(0.12, 0.18, 0.28, 1.0)
	ramp.add_child(deck)

	# Glowing walk-surface edge
	var edge := Polygon2D.new()
	edge.polygon = PackedVector2Array([
		Vector2(margin, surface_y),
		Vector2(w - margin, surface_y),
		Vector2(w - margin, surface_y + 4.0),
		Vector2(margin, surface_y + 4.0)
	])
	edge.color = Color(0.25, 0.75, 0.95, 0.9)
	ramp.add_child(edge)

	# Angled ramp ends connecting the walkway down to the fortress roof
	for side: float in [-1.0, 1.0]:
		var edge_x := margin if side < 0.0 else w - margin
		var foot_x := edge_x + side * 90.0
		var side_ramp := Polygon2D.new()
		side_ramp.polygon = PackedVector2Array([
			Vector2(edge_x, surface_y),
			Vector2(edge_x, surface_y + deck_h),
			Vector2(clampf(foot_x, 0.0, w), ground_y)
		])
		side_ramp.color = Color(0.1, 0.15, 0.24, 1.0)
		ramp.add_child(side_ramp)

	# Support pillars down to the fortress roofline
	var pillar_count := 5
	for i in pillar_count:
		var x := lerpf(margin + 50.0, w - margin - 50.0, float(i) / float(pillar_count - 1))
		var pillar := Polygon2D.new()
		pillar.polygon = PackedVector2Array([
			Vector2(x - 7.0, surface_y + deck_h),
			Vector2(x + 7.0, surface_y + deck_h),
			Vector2(x + 7.0, ground_y),
			Vector2(x - 7.0, ground_y)
		])
		pillar.color = Color(0.08, 0.12, 0.2, 1.0)
		ramp.add_child(pillar)

func _spawn_tower_slots() -> void:
	var ids := ["laser", "cannon", "machinegun", "railgun", "flamethrower", "rocket"]
	var spacing := arena_size.x / float(ids.size() + 1)
	var y := arena_size.y - 55.0
	for i in ids.size():
		var id: String = ids[i]
		var tower = tower_scenes[id].instantiate()
		tower.position = Vector2(spacing * float(i + 1), y)
		tower.bind_fortress(fortress)
		towers_root.add_child(tower)
		towers[id] = tower

func _unlock_tower(id: String) -> void:
	unlocked_towers[id] = true
	if towers.has(id) and towers[id].has_method("unlock"):
		towers[id].unlock()

## Sandbox: click a tower to switch it on/off
func _unhandled_input(event) -> void:
	if not test_mode or game_over:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var pos: Vector2 = get_global_mouse_position()
		for tower in towers.values():
			if tower.global_position.distance_to(pos) <= 55.0:
				tower.toggle_sandbox_disabled()
				break

func setup_ui():
	ui_layer = CanvasLayer.new()
	ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui_layer)

	var pause_hotkey := Node.new()
	pause_hotkey.set_script(preload("res://scripts/pause_hotkey.gd"))
	pause_hotkey.game = self
	ui_layer.add_child(pause_hotkey)

	# Compact top HUD for portrait phone
	var top := VBoxContainer.new()
	top.position = Vector2(12, 10)
	top.add_theme_constant_override("separation", 4)
	ui_layer.add_child(top)

	# Character level + XP bar
	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 8)
	top.add_child(xp_row)

	char_level_label = Label.new()
	char_level_label.add_theme_font_size_override("font_size", 16)
	char_level_label.modulate = Color(0.45, 1.0, 0.85)
	char_level_label.custom_minimum_size = Vector2(70, 0)
	xp_row.add_child(char_level_label)

	xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(mini(360.0, arena_size.x - 200.0), 18)
	xp_bar.show_percentage = false
	xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var xp_fill := StyleBoxFlat.new()
	xp_fill.bg_color = Color(0.25, 0.9, 0.75)
	xp_fill.set_corner_radius_all(4)
	xp_bar.add_theme_stylebox_override("fill", xp_fill)
	var xp_bg := StyleBoxFlat.new()
	xp_bg.bg_color = Color(0.12, 0.16, 0.2)
	xp_bg.set_corner_radius_all(4)
	xp_bar.add_theme_stylebox_override("background", xp_bg)
	xp_row.add_child(xp_bar)

	xp_label = Label.new()
	xp_label.add_theme_font_size_override("font_size", 13)
	xp_label.modulate = Color(0.75, 0.95, 0.9)
	xp_row.add_child(xp_label)
	_refresh_xp_hud()

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 14)
	top.add_child(row1)

	level_label = Label.new()
	if test_mode:
		level_label.text = "SANDBOX"
		level_label.modulate = Color(0.45, 1.0, 0.9)
	else:
		level_label.text = PlayerData.get_stage_title(PlayerData.selected_stage)
		if PlayerData.is_boss_stage(PlayerData.selected_stage):
			level_label.modulate = Color(1.0, 0.45, 0.35)
	level_label.add_theme_font_size_override("font_size", 18)
	row1.add_child(level_label)

	time_label = Label.new()
	time_label.text = "Time: 00:00"
	time_label.add_theme_font_size_override("font_size", 18)
	row1.add_child(time_label)

	wave_label = Label.new()
	wave_label.text = "Wave: 0" if test_mode else "Wave: 0/15"
	wave_label.add_theme_font_size_override("font_size", 18)
	row1.add_child(wave_label)

	coins_label = Label.new()
	coins_label.text = "Coins: %d" % PlayerData.coins
	coins_label.add_theme_font_size_override("font_size", 18)
	coins_label.modulate = Color(1.0, 0.9, 0.35)
	row1.add_child(coins_label)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	top.add_child(row2)

	fort_hp_label = Label.new()
	fort_hp_label.text = "Fortress"
	fort_hp_label.add_theme_font_size_override("font_size", 14)
	row2.add_child(fort_hp_label)

	fort_hp_bar = ProgressBar.new()
	fort_hp_bar.custom_minimum_size = Vector2(mini(320.0, arena_size.x - 120.0), 18)
	fort_hp_bar.show_percentage = false
	fort_hp_bar.max_value = fortress.max_health
	fort_hp_bar.value = fortress.health
	row2.add_child(fort_hp_bar)

	boss_banner = Label.new()
	boss_banner.text = "FINAL BOSS INCOMING"
	boss_banner.visible = false
	boss_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_banner.add_theme_font_size_override("font_size", 26)
	boss_banner.modulate = Color(1.0, 0.35, 0.55)
	boss_banner.position = Vector2(20, 90)
	boss_banner.size = Vector2(arena_size.x - 40, 40)
	ui_layer.add_child(boss_banner)

	loot_toast = Label.new()
	loot_toast.visible = false
	loot_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loot_toast.add_theme_font_size_override("font_size", 18)
	loot_toast.modulate = Color(1.0, 0.85, 0.3)
	loot_toast.position = Vector2(20, 130)
	loot_toast.size = Vector2(arena_size.x - 40, 40)
	ui_layer.add_child(loot_toast)

	var pause_btn := Button.new()
	pause_btn.text = "II"
	pause_btn.custom_minimum_size = Vector2(44, 36)
	pause_btn.position = Vector2(arena_size.x - 56, 10)
	pause_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_btn.pressed.connect(_toggle_pause_menu)
	ui_layer.add_child(pause_btn)

	if test_mode:
		_build_sandbox_panel()

func _build_sandbox_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(8, 180)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.12, 0.9)
	style.border_color = Color(0.35, 0.9, 1.0, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	ui_layer.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	var title := Label.new()
	title.text = "SPAWN ENEMIES"
	title.add_theme_font_size_override("font_size", 14)
	title.modulate = Color(0.45, 1.0, 0.9)
	box.add_child(title)

	# Amount selector: 1 / 10 / 25 per press
	var amount_row := HBoxContainer.new()
	amount_row.add_theme_constant_override("separation", 4)
	box.add_child(amount_row)
	var group := ButtonGroup.new()
	for amt in [1, 10, 25]:
		var toggle := Button.new()
		toggle.text = str(amt)
		toggle.toggle_mode = true
		toggle.button_group = group
		toggle.custom_minimum_size = Vector2(40, 28)
		toggle.add_theme_font_size_override("font_size", 13)
		toggle.button_pressed = (amt == 1)
		toggle.toggled.connect(_on_sandbox_amount_toggled.bind(amt))
		amount_row.add_child(toggle)

	var entries := [
		{"id": "small", "label": "Small Meteor"},
		{"id": "normal", "label": "Meteor"},
		{"id": "heavy", "label": "Heavy Meteor"},
		{"id": "ufo", "label": "UFO Ship"},
		{"id": "rocketeer", "label": "Rocketeer Ship"},
		{"id": "boss", "label": "Boss"}
	]
	for entry in entries:
		var btn := Button.new()
		btn.text = String(entry["label"])
		btn.add_theme_font_size_override("font_size", 13)
		btn.custom_minimum_size = Vector2(128, 30)
		btn.pressed.connect(_on_sandbox_spawn_pressed.bind(String(entry["id"])))
		box.add_child(btn)

	var hint := Label.new()
	hint.text = "Click a tower to\ntoggle it on/off"
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(0.7, 0.8, 0.85)
	box.add_child(hint)

func _on_sandbox_amount_toggled(pressed: bool, amount: int) -> void:
	if pressed:
		sandbox_spawn_amount = amount

func _on_sandbox_spawn_pressed(id: String) -> void:
	if wave_manager:
		wave_manager.spawn_sandbox_enemy(id, sandbox_spawn_amount)

func _can_toggle_pause() -> bool:
	if game_over:
		return false
	if upgrade_ui_container != null and is_instance_valid(upgrade_ui_container):
		return false
	return true

func _toggle_pause_menu() -> void:
	if not _can_toggle_pause():
		return
	if is_paused_menu:
		_close_pause_menu()
	else:
		_open_pause_menu()

func _open_pause_menu() -> void:
	is_paused_menu = true
	get_tree().paused = true
	if is_instance_valid(pause_panel):
		pause_panel.queue_free()

	pause_panel = PanelContainer.new()
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_panel.position = Vector2(arena_size.x * 0.5 - 170, arena_size.y * 0.5 - 260)
	pause_panel.custom_minimum_size = Vector2(340, 500)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.07, 0.12, 0.96)
	style.border_color = Color(0.35, 0.9, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	pause_panel.add_theme_stylebox_override("panel", style)
	ui_layer.add_child(pause_panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	pause_panel.add_child(root)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.modulate = Color(0.45, 1.0, 0.9)
	root.add_child(title)

	var upgrades_title := Label.new()
	upgrades_title.text = "RUN UPGRADES"
	upgrades_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	upgrades_title.add_theme_font_size_override("font_size", 16)
	upgrades_title.modulate = Color(1.0, 0.85, 0.35)
	root.add_child(upgrades_title)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 280)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)

	if run_upgrades.is_empty():
		var empty := Label.new()
		empty.text = "No upgrades yet.\nLevel up by defeating enemies."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 13)
		empty.modulate = Color(0.65, 0.7, 0.8)
		list.add_child(empty)
	else:
		# Aggregate duplicates: name -> count
		var counts: Dictionary = {}
		var order: Array = []
		for u in run_upgrades:
			var key: String = String(u.get("name", "?"))
			if not counts.has(key):
				counts[key] = {"count": 0, "desc": String(u.get("desc", ""))}
				order.append(key)
			counts[key]["count"] = int(counts[key]["count"]) + 1
		for key in order:
			var info: Dictionary = counts[key]
			var row := Label.new()
			var count: int = int(info["count"])
			var suffix := " x%d" % count if count > 1 else ""
			row.text = "%s%s\n  %s" % [key, suffix, String(info["desc"])]
			row.add_theme_font_size_override("font_size", 12)
			row.modulate = Color(0.8, 0.95, 1.0)
			list.add_child(row)

	var resume := Button.new()
	resume.text = "Resume"
	resume.custom_minimum_size = Vector2(0, 44)
	resume.pressed.connect(_close_pause_menu)
	root.add_child(resume)

	var hub := Button.new()
	hub.text = "Quit to Hub"
	hub.custom_minimum_size = Vector2(0, 44)
	hub.pressed.connect(_pause_quit_to_hub)
	root.add_child(hub)

func _close_pause_menu() -> void:
	is_paused_menu = false
	if is_instance_valid(pause_panel):
		pause_panel.queue_free()
		pause_panel = null
	if not game_over and (upgrade_ui_container == null or not is_instance_valid(upgrade_ui_container)):
		get_tree().paused = false

func _pause_quit_to_hub() -> void:
	is_paused_menu = false
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/mainmenu.tscn")

func _refresh_xp_hud() -> void:
	if char_level_label == null or xp_bar == null:
		return
	var need: int = PlayerData.xp_for_level(PlayerData.char_level)
	char_level_label.text = "Lv %d" % PlayerData.char_level
	xp_bar.max_value = need
	xp_bar.value = PlayerData.char_xp
	if xp_label:
		xp_label.text = "%d/%d" % [PlayerData.char_xp, need]

func _show_loot_toast(text: String) -> void:
	if loot_toast == null:
		return
	loot_toast.text = text
	loot_toast.visible = true
	var t := get_tree().create_timer(2.8)
	await t.timeout
	if is_instance_valid(loot_toast):
		loot_toast.visible = false

func _process(delta: float):
	if game_over:
		return
	if not get_tree().paused:
		run_time += delta
		var mins := int(run_time) / 60
		var secs := int(run_time) % 60
		time_label.text = "Time: %02d:%02d" % [mins, secs]

func _on_creep_spawned(enemy) -> void:
	enemy_list.append(enemy)
	enemy.connect("enemy_destroyed", on_enemy_destroyed)

func _on_wave_started(wave: int) -> void:
	if test_mode:
		wave_label.text = "Wave: %d" % wave
	else:
		wave_label.text = "Wave: %d/15" % wave

func _on_boss_incoming(_wave: int) -> void:
	boss_banner.visible = true
	if test_mode:
		boss_banner.text = "TEST BOSS INCOMING"
	elif PlayerData.is_boss_stage(PlayerData.selected_stage):
		boss_banner.text = "MEGA BOSS — %s" % PlayerData.get_stage_name(PlayerData.selected_stage).to_upper()
	else:
		boss_banner.text = "FINAL BOSS INCOMING"
	var t := get_tree().create_timer(2.5)
	await t.timeout
	if is_instance_valid(boss_banner):
		boss_banner.visible = false

func on_enemy_destroyed(enemy):
	enemy_list.erase(enemy)
	kill_count += 1
	var is_boss_kill := false
	if enemy != null and (enemy.get("is_boss") == true or String(enemy.name).to_lower().contains("boss")):
		is_boss_kill = true
	# Test range grants no persistent XP
	if not test_mode:
		PlayerData.add_char_xp(PlayerData.get_kill_xp(is_boss_kill))
		_refresh_xp_hud()
	if kill_count >= kills_to_next_level:
		trigger_level_up()

func _on_level_complete(_wave: int) -> void:
	if game_over or test_mode:
		return
	game_over = true
	wave_manager.stop()
	_reward_level_clear()
	get_tree().paused = true
	_show_victory()

func _reward_level_clear() -> void:
	cleared_stage_num = PlayerData.selected_stage
	run_coins_earned = PlayerData.get_clear_coin_reward(cleared_stage_num)
	PlayerData.add_coins(run_coins_earned)
	var drop: Dictionary = PlayerData.roll_level_drop(cleared_stage_num, rand)
	if not drop.is_empty():
		run_loot.append(drop)
	# Boss stages always drop a second gear piece
	if PlayerData.is_boss_stage(cleared_stage_num):
		var boss_drop: Dictionary = PlayerData.roll_level_drop(cleared_stage_num, rand)
		if not boss_drop.is_empty():
			run_loot.append(boss_drop)
	# Farming skill: chance for a second gear drop
	var extra_chance: float = float(PlayerData.get_skill_bonuses().get("extra_loot_chance", 0.0))
	if extra_chance > 0.0 and rand.randf() < extra_chance:
		var drop2: Dictionary = PlayerData.roll_level_drop(cleared_stage_num, rand)
		if not drop2.is_empty():
			run_loot.append(drop2)
	PlayerData.add_char_xp(60 + cleared_stage_num * 25)
	_refresh_xp_hud()
	PlayerData.mark_level_cleared(15, cleared_stage_num)
	PlayerData.selected_stage = mini(PlayerData.selected_stage + 1, PlayerData.get_max_playable_stage())
	PlayerData.save_data() # persists XP earned during the run too
	var gear_name: String = "none"
	if not run_loot.is_empty():
		var names: PackedStringArray = []
		for item in run_loot:
			names.append(String(item.get("name", "Gear")))
		gear_name = ", ".join(names)
	_show_loot_toast("STAGE %d CLEAR! +%d coins | Gear: %s" % [cleared_stage_num, run_coins_earned, gear_name])

func _show_victory() -> void:
	game_over_panel = PanelContainer.new()
	game_over_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	game_over_panel.position = Vector2(arena_size.x * 0.5 - 160, arena_size.y * 0.5 - 180)
	game_over_panel.custom_minimum_size = Vector2(320, 320)
	ui_layer.add_child(game_over_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	game_over_panel.add_child(vbox)

	var title := Label.new()
	title.text = "STAGE %d CLEARED" % cleared_stage_num
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.modulate = Color(0.35, 0.95, 0.7)
	vbox.add_child(title)

	var rewards_title := Label.new()
	rewards_title.text = "REWARDS"
	rewards_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rewards_title.add_theme_font_size_override("font_size", 16)
	rewards_title.modulate = Color(1.0, 0.85, 0.3)
	vbox.add_child(rewards_title)

	var coins_reward := Label.new()
	coins_reward.text = "+%d Coins\n(Total: %d)" % [run_coins_earned, PlayerData.coins]
	coins_reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coins_reward.add_theme_font_size_override("font_size", 15)
	coins_reward.modulate = Color(1.0, 0.9, 0.35)
	vbox.add_child(coins_reward)

	var loot_title := Label.new()
	if run_loot.is_empty():
		loot_title.text = "Gear: none this run"
	else:
		var names: PackedStringArray = []
		for item in run_loot:
			names.append(String(item.get("name", "Gear")))
		loot_title.text = "Gear:\n" + "\n".join(names)
	loot_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loot_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	loot_title.add_theme_font_size_override("font_size", 13)
	vbox.add_child(loot_title)

	var info := Label.new()
	info.text = "Next: %s  (reward: %d coins)" % [
		PlayerData.get_stage_title(PlayerData.selected_stage),
		PlayerData.get_clear_coin_reward(PlayerData.selected_stage)
	]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 12)
	vbox.add_child(info)

	var next_btn := Button.new()
	next_btn.text = "Deploy Stage %d" % PlayerData.selected_stage
	next_btn.pressed.connect(func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/game.tscn")
	)
	vbox.add_child(next_btn)

	var hub_btn := Button.new()
	hub_btn.text = "Return to Hub"
	hub_btn.pressed.connect(func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/mainmenu.tscn")
	)
	vbox.add_child(hub_btn)

	var char_btn := Button.new()
	char_btn.text = "Open Character"
	char_btn.pressed.connect(func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/character.tscn")
	)
	vbox.add_child(char_btn)

func trigger_level_up():
	if is_paused_menu:
		_close_pause_menu()
	level += 1
	kill_count = 0
	kills_to_next_level = 5 + level * 2
	get_tree().paused = true
	show_upgrade_cards()

func show_upgrade_cards():
	upgrade_ui_container = Control.new()
	upgrade_ui_container.process_mode = Node.PROCESS_MODE_ALWAYS
	upgrade_ui_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(upgrade_ui_container)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	upgrade_ui_container.add_child(dim)

	var title := Label.new()
	title.text = "CHOOSE AN UPGRADE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.position = Vector2(20, 88)
	title.size = Vector2(arena_size.x - 40, 36)
	upgrade_ui_container.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Character  ·  Tower  ·  Specialist  ·  Wild"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.modulate = Color(0.75, 0.9, 1.0)
	subtitle.position = Vector2(20, 118)
	subtitle.size = Vector2(arena_size.x - 40, 22)
	upgrade_ui_container.add_child(subtitle)

	var cards := UpgradeCardsScript.pick_level_up(unlocked_towers, gear, rand)
	# Portrait: stack 4 compact cards
	var card_w: float = mini(300.0, arena_size.x - 48.0)
	var card_h: float = 132.0
	var gap: float = 8.0
	var start_y: float = 146.0
	var start_x: float = (arena_size.x - card_w) * 0.5

	for i in cards.size():
		var card: Dictionary = cards[i]
		var offer_slot := String(card.get("offer_slot", card.get("category", "random")))
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(card_w, card_h)
		panel.position = Vector2(start_x, start_y + i * (card_h + gap))

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.07, 0.09, 0.14, 0.95)
		style.border_color = card.get("color", Color(0.3, 0.9, 1.0))
		style.set_border_width_all(3)
		style.set_corner_radius_all(8)
		panel.add_theme_stylebox_override("panel", style)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		panel.add_child(vbox)

		var accent := ColorRect.new()
		accent.custom_minimum_size = Vector2(card_w - 20, 5)
		accent.color = card.get("color", Color(0.3, 0.9, 1.0))
		vbox.add_child(accent)

		var slot_l := Label.new()
		slot_l.text = UpgradeCardsScript.category_label(offer_slot)
		slot_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_l.add_theme_font_size_override("font_size", 10)
		match offer_slot:
			"character":
				slot_l.modulate = Color(1.0, 0.85, 0.35)
			"tower":
				slot_l.modulate = Color(0.45, 0.95, 1.0)
			"specialist":
				slot_l.modulate = Color(1.0, 0.55, 0.35)
			_:
				slot_l.modulate = Color(0.85, 0.7, 1.0)
		vbox.add_child(slot_l)

		var name_l := Label.new()
		name_l.text = String(card.get("name", "UPGRADE"))
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.add_theme_font_size_override("font_size", 14)
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(name_l)

		var desc := Label.new()
		desc.text = String(card.get("description", ""))
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc.add_theme_font_size_override("font_size", 11)
		vbox.add_child(desc)

		var btn := Button.new()
		btn.text = "SELECT"
		btn.custom_minimum_size = Vector2(card_w - 30, 28)
		btn.pressed.connect(_on_card_selected.bind(card))
		vbox.add_child(btn)

		upgrade_ui_container.add_child(panel)

func _on_card_selected(card: Dictionary) -> void:
	apply_card(card)
	if is_instance_valid(upgrade_ui_container):
		upgrade_ui_container.queue_free()
	get_tree().paused = false

func apply_card(card: Dictionary) -> void:
	var id := String(card.get("id", ""))
	run_upgrades.append({
		"id": id,
		"name": String(card.get("name", id)),
		"desc": String(card.get("description", ""))
	})
	# Per-tower specialist upgrades
	if String(card.get("category", "")) == "specialist" or String(card.get("type", "")) == "specialist":
		_apply_tower_specialist(card)
		return
	match id:
		"ignition":
			player.has_ignition = true
		"contact_pulse":
			player.has_contact_pulse = true
		"piercing":
			player.pierce_count += 1
		"fork":
			player.bonus_fork += 1
		"damage":
			player.damage_multiplier += 0.12
		"fire_rate":
			player.apply_fire_rate_card(0.70)
		"tower_power":
			if fortress:
				fortress.tower_damage_multiplier += 0.25
		"tower_rapid":
			if fortress:
				fortress.cooldown_reduction = mini(0.7, fortress.cooldown_reduction + 0.20)
		"tower_range":
			_buff_all_tower_range(0.20)
		"tower_fortify":
			if fortress and fortress.has_method("increase_max_health"):
				fortress.increase_max_health(80)
			elif fortress:
				fortress.max_health += 80
				fortress.health += 80
				fortress.health_changed.emit(fortress.health, fortress.max_health)
		"projectile":
			player.bonus_projectiles += 1
		"tower_laser":
			_unlock_tower("laser")
		"tower_cannon":
			_unlock_tower("cannon")
		"tower_machinegun":
			_unlock_tower("machinegun")
		"tower_railgun":
			_unlock_tower("railgun")
		"tower_flamethrower":
			_unlock_tower("flamethrower")
		"tower_rocket":
			_unlock_tower("rocket")

func _apply_tower_specialist(card: Dictionary) -> void:
	var target_id := String(card.get("target", ""))
	if target_id == "" or not towers.has(target_id):
		return
	var tower = towers[target_id]
	if tower == null or not is_instance_valid(tower):
		return
	# Auto-unlock if somehow offered while locked
	if tower.has_method("is_unlocked") and not tower.is_unlocked():
		_unlock_tower(target_id)
	var effect := String(card.get("effect", ""))
	var amount: float = float(card.get("amount", 0.0))
	match effect:
		"damage_mult":
			if tower.has_method("apply_local_damage_mult"):
				tower.apply_local_damage_mult(amount)
		"shots":
			if tower.has_method("add_bonus_shots"):
				tower.add_bonus_shots(int(amount))
			var penalty: float = float(card.get("damage_penalty", 0.0))
			if penalty > 0.0 and tower.has_method("apply_damage_penalty"):
				tower.apply_damage_penalty(penalty)
		"range_mult":
			if tower.has_method("apply_range_mult"):
				tower.apply_range_mult(amount)
		"fire_rate":
			if tower.has_method("apply_fire_rate_mult"):
				tower.apply_fire_rate_mult(amount)
		"aoe_mult":
			if tower.has_method("apply_aoe_mult"):
				tower.apply_aoe_mult(amount)

func _buff_all_tower_range(mult_add: float) -> void:
	for id in towers.keys():
		var tower = towers[id]
		if tower == null or not is_instance_valid(tower):
			continue
		if tower.has_method("apply_range_mult"):
			tower.apply_range_mult(mult_add)
		elif "range_px" in tower:
			tower.range_px *= (1.0 + mult_add)

func _on_fortress_health_changed(current: int, maximum: int) -> void:
	if fort_hp_bar:
		fort_hp_bar.max_value = maximum
		fort_hp_bar.value = current
	if fort_hp_label:
		fort_hp_label.text = "Fortress %d/%d" % [current, maximum]

func _on_fortress_destroyed() -> void:
	game_over = true
	wave_manager.stop()
	get_tree().paused = true
	_show_game_over()

func _show_game_over() -> void:
	game_over_panel = PanelContainer.new()
	game_over_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	game_over_panel.position = Vector2(arena_size.x * 0.5 - 150, arena_size.y * 0.5 - 140)
	game_over_panel.custom_minimum_size = Vector2(300, 260)
	ui_layer.add_child(game_over_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	game_over_panel.add_child(vbox)

	var title := Label.new()
	title.text = "TEST OVER — FORTRESS DOWN" if test_mode else "FORTRESS DESTROYED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	if test_mode:
		var restart_btn := Button.new()
		restart_btn.text = "Restart Test"
		restart_btn.pressed.connect(func():
			get_tree().paused = false
			get_tree().change_scene_to_file("res://scenes/game.tscn")
		)
		vbox.add_child(restart_btn)

	var loot_title := Label.new()
	if test_mode:
		loot_title.text = "Test run — no XP, coins, or gear."
	elif run_loot.is_empty():
		loot_title.text = "No gear this run.\nBeat a boss (every 5 waves) to farm loot."
	else:
		var names: PackedStringArray = []
		for item in run_loot:
			names.append(String(item.get("name", "Gear")))
		loot_title.text = "Loot banked:\n" + "\n".join(names)
	loot_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loot_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	loot_title.add_theme_font_size_override("font_size", 13)
	vbox.add_child(loot_title)

	var hub_btn := Button.new()
	hub_btn.text = "Return to Hub"
	hub_btn.pressed.connect(func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/mainmenu.tscn")
	)
	vbox.add_child(hub_btn)

	var char_btn := Button.new()
	char_btn.text = "Open Character"
	char_btn.pressed.connect(func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/character.tscn")
	)
	vbox.add_child(char_btn)
