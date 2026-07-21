extends Node

## Persistent game settings (audio, graphics, player controls).

const SAVE_PATH := "user://game_settings.json"
const BUS_PLAYER := "Player"
const BUS_ENEMY := "Enemy"
const BUS_TOWERS := "Towers"
const BUS_MUSIC := "Music"

signal settings_changed

var master_volume: float = 1.0
var player_volume: float = 1.0
var enemy_volume: float = 1.0
var towers_volume: float = 1.0
var music_volume: float = 1.0
var sfx_enabled: bool = true
var fullscreen: bool = false
var vsync_enabled: bool = true
var auto_aim_when_idle: bool = true
var auto_shoot_when_idle: bool = true

func _ready() -> void:
	_ensure_buses()
	load_settings()
	apply_all()

func apply_all() -> void:
	apply_audio()
	apply_graphics()

func _ensure_buses() -> void:
	for bus_name in [BUS_PLAYER, BUS_ENEMY, BUS_TOWERS, BUS_MUSIC]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")

func _apply_bus_volume(bus_name: String, linear: float, force_mute: bool = false) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus < 0:
		return
	var vol := clampf(linear, 0.0, 1.0)
	if force_mute or vol <= 0.001:
		AudioServer.set_bus_mute(bus, true)
	else:
		AudioServer.set_bus_mute(bus, false)
		AudioServer.set_bus_volume_db(bus, linear_to_db(vol))

func apply_audio() -> void:
	_ensure_buses()
	var master := AudioServer.get_bus_index("Master")
	if master >= 0:
		if master_volume <= 0.001:
			AudioServer.set_bus_mute(master, true)
		else:
			AudioServer.set_bus_mute(master, false)
			AudioServer.set_bus_volume_db(master, linear_to_db(clampf(master_volume, 0.0, 1.0)))
	_apply_bus_volume(BUS_MUSIC, music_volume)
	_apply_bus_volume(BUS_PLAYER, player_volume, not sfx_enabled)
	_apply_bus_volume(BUS_ENEMY, enemy_volume, not sfx_enabled)
	_apply_bus_volume(BUS_TOWERS, towers_volume, not sfx_enabled)

func apply_graphics() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)
	if vsync_enabled:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	apply_audio()
	save_settings()
	settings_changed.emit()

func set_player_volume(value: float) -> void:
	player_volume = clampf(value, 0.0, 1.0)
	apply_audio()
	save_settings()
	settings_changed.emit()

func set_enemy_volume(value: float) -> void:
	enemy_volume = clampf(value, 0.0, 1.0)
	apply_audio()
	save_settings()
	settings_changed.emit()

func set_towers_volume(value: float) -> void:
	towers_volume = clampf(value, 0.0, 1.0)
	apply_audio()
	save_settings()
	settings_changed.emit()

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	apply_audio()
	save_settings()
	settings_changed.emit()

func set_sfx_enabled(enabled: bool) -> void:
	sfx_enabled = enabled
	apply_audio()
	save_settings()
	settings_changed.emit()

func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	apply_graphics()
	save_settings()
	settings_changed.emit()

func set_vsync_enabled(enabled: bool) -> void:
	vsync_enabled = enabled
	apply_graphics()
	save_settings()
	settings_changed.emit()

func set_auto_aim_when_idle(enabled: bool) -> void:
	auto_aim_when_idle = enabled
	save_settings()
	settings_changed.emit()

func set_auto_shoot_when_idle(enabled: bool) -> void:
	auto_shoot_when_idle = enabled
	save_settings()
	settings_changed.emit()

func save_settings() -> void:
	var data := {
		"master_volume": master_volume,
		"player_volume": player_volume,
		"enemy_volume": enemy_volume,
		"towers_volume": towers_volume,
		"music_volume": music_volume,
		"sfx_enabled": sfx_enabled,
		"fullscreen": fullscreen,
		"vsync_enabled": vsync_enabled,
		"auto_aim_when_idle": auto_aim_when_idle,
		"auto_shoot_when_idle": auto_shoot_when_idle,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

func load_settings() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	master_volume = clampf(float(data.get("master_volume", master_volume)), 0.0, 1.0)
	player_volume = clampf(float(data.get("player_volume", player_volume)), 0.0, 1.0)
	enemy_volume = clampf(float(data.get("enemy_volume", enemy_volume)), 0.0, 1.0)
	towers_volume = clampf(float(data.get("towers_volume", towers_volume)), 0.0, 1.0)
	music_volume = clampf(float(data.get("music_volume", music_volume)), 0.0, 1.0)
	sfx_enabled = bool(data.get("sfx_enabled", sfx_enabled))
	fullscreen = bool(data.get("fullscreen", fullscreen))
	vsync_enabled = bool(data.get("vsync_enabled", vsync_enabled))
	auto_aim_when_idle = bool(data.get("auto_aim_when_idle", auto_aim_when_idle))
	auto_shoot_when_idle = bool(data.get("auto_shoot_when_idle", auto_shoot_when_idle))
