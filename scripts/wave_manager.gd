extends Node
class_name WaveManager

signal wave_started(wave: int)
signal boss_incoming(wave: int)
signal creep_spawned(enemy)
signal wave_cleared(wave: int)
signal level_complete(wave: int)

@export var wave_interval: float = 8.0
@export var spawn_y: float = 40.0
@export var max_waves: int = 15

const ROCKETEER_SCENE := preload("res://scenes/enemy_ship_rocketeer.tscn")
const EnemyScript := preload("res://scripts/enemy.gd")
## First wave where the shielded Rocketeer gunship can appear.
const ROCKETEER_MIN_WAVE := 3
const ROCKETEER_CHANCE := 0.5

var wave: int = 0
var stage: int = 1
var arena_width: float = 1152.0
var fortress_y: float = 600.0
var enemy_scene: PackedScene
var boss_scene: PackedScene
var player: CharacterBody2D
var fortress: Node2D
var active_enemies: Array = []
var timer: float = 0.0
var running: bool = false
var waiting_for_clear: bool = false
## Sandbox: no automatic waves — enemies spawn only via spawn_sandbox_enemy()
var test_mode: bool = false
var rng := RandomNumberGenerator.new()

func set_test_mode(enabled: bool) -> void:
	test_mode = enabled

## Sandbox on-demand spawning. id is one of the basic enemy ids
## ("small", "normal", "heavy", "ufo") or "rocketeer" / "boss".
func spawn_sandbox_enemy(id: String, count: int) -> void:
	for i in count:
		match id:
			"rocketeer":
				_spawn_rocketeer()
			"boss":
				_spawn_boss(rng.randf_range(90.0, arena_width - 90.0))
			_:
				_spawn_creep(EnemyScript.get_enemy_type(id))

func setup(width: float, fort_y: float, enemy: PackedScene, boss: PackedScene, p: CharacterBody2D, f: Node2D, stage_num: int = 1) -> void:
	arena_width = width
	fortress_y = fort_y
	enemy_scene = enemy
	boss_scene = boss
	player = p
	fortress = f
	stage = maxi(1, stage_num)
	rng.randomize()
	running = true
	waiting_for_clear = false
	wave = 0
	timer = 1.5

func _process(delta: float) -> void:
	if not running or get_tree().paused:
		return
	active_enemies = active_enemies.filter(func(e): return is_instance_valid(e))

	# After final wave is spawned, wait until field is clear then complete
	if waiting_for_clear:
		if active_enemies.is_empty():
			waiting_for_clear = false
			running = false
			level_complete.emit(wave)
		return

	# Sandbox: never runs timed waves — spawning is button-driven
	if test_mode:
		return

	if wave >= max_waves:
		return

	timer -= delta
	if timer <= 0.0:
		_start_next_wave()
		if wave < max_waves:
			timer = max(4.0, wave_interval - wave * 0.15)
		else:
			waiting_for_clear = true

func _start_next_wave() -> void:
	wave += 1
	wave_started.emit(wave)

	if wave == max_waves:
		boss_incoming.emit(wave)
		_spawn_boss()
		# Escort creeps with the boss (heavier guard on boss stages)
		var escorts := 2 + stage
		if _is_boss_stage():
			escorts += 4
		for i in range(escorts):
			_spawn_creep()
	else:
		var count := 4 + wave * 2 + stage
		if _is_boss_stage():
			count += 3
		for i in range(count):
			_spawn_creep()
		if wave >= ROCKETEER_MIN_WAVE and rng.randf() < ROCKETEER_CHANCE:
			_spawn_rocketeer()

	if active_enemies.is_empty():
		wave_cleared.emit(wave)

func _is_boss_stage() -> bool:
	return PlayerData.is_boss_stage(stage)

func _stage_hp_mult() -> float:
	var m := 1.0 + (stage - 1) * 0.25
	if _is_boss_stage():
		m *= 1.35
	return m

func _stage_speed_mult() -> float:
	var m := 1.0 + (stage - 1) * 0.08
	if _is_boss_stage():
		m *= 1.10
	return m

func _meteor_slow_mult() -> float:
	var slow: float = float(PlayerData.get_equipped_bonuses().get("meteor_slow", 0.0))
	return 1.0 - clampf(slow, 0.0, 0.45)

func _spawn_creep(etype_override: Dictionary = {}) -> void:
	if enemy_scene == null:
		return
	var etype: Dictionary = etype_override
	if etype.is_empty():
		etype = EnemyScript.pick_enemy_type(rng)
	var enemy = enemy_scene.instantiate()
	var x := rng.randf_range(60.0, arena_width - 60.0)
	var y := spawn_y + rng.randf_range(-20.0, 40.0)
	var hp: int
	var spd: float
	if not etype.is_empty():
		hp = int((float(etype["base_hp"]) + float(wave) * float(etype["hp_per_wave"])) * _stage_hp_mult())
		spd = (float(etype["base_speed"]) + float(wave) * float(etype["speed_per_wave"])) * _stage_speed_mult() * _meteor_slow_mult()
	else:
		hp = int((180 + wave * 35) * _stage_hp_mult())
		spd = (32.0 + wave * 1.5) * _stage_speed_mult() * _meteor_slow_mult()

	get_tree().current_scene.add_child(enemy)
	if enemy.has_method("apply_enemy_type") and not etype.is_empty():
		enemy.apply_enemy_type(etype)
	enemy.setup_descent(Vector2(x, y), player, fortress, hp, spd)
	enemy.connect("enemy_destroyed", _on_enemy_destroyed)
	active_enemies.append(enemy)
	creep_spawned.emit(enemy)

func _spawn_rocketeer() -> void:
	var ship = ROCKETEER_SCENE.instantiate()
	var x := rng.randf_range(90.0, arena_width - 90.0)
	var hp := int((260.0 + float(wave) * 45.0) * _stage_hp_mult())
	var spd := (16.0 + float(wave) * 0.4) * _stage_speed_mult() * _meteor_slow_mult()
	get_tree().current_scene.add_child(ship)
	ship.setup_descent(Vector2(x, spawn_y - 10.0), player, fortress, hp, spd)
	# Shield and payload scale with wave and stage
	var shield := int((140.0 + float(wave) * 35.0) * _stage_hp_mult())
	var fort_dmg := 12 + wave + (stage - 1) * 2
	var aoe_dmg := int((80.0 + float(wave) * 12.0) * _stage_hp_mult())
	ship.setup_combat(shield, fort_dmg, aoe_dmg)
	ship.connect("enemy_destroyed", _on_enemy_destroyed)
	active_enemies.append(ship)
	creep_spawned.emit(ship)

func _spawn_boss(x_override: float = -1.0) -> void:
	var scene = boss_scene if boss_scene else enemy_scene
	if scene == null:
		return
	var boss = scene.instantiate()
	var x := x_override if x_override >= 0.0 else arena_width * 0.5
	var heavy: Dictionary = {}
	if boss.has_method("get_enemy_type"):
		heavy = boss.get_enemy_type("heavy")
	# Mega boss on boss stages: much tougher, slightly slower descent
	var hp_mult := 25.0 if _is_boss_stage() else 10.0
	var spd_mult := 0.45 if _is_boss_stage() else 0.55
	var hp: int
	var spd: float
	if not heavy.is_empty():
		hp = int((float(heavy["base_hp"]) + float(wave) * float(heavy["hp_per_wave"])) * hp_mult * _stage_hp_mult())
		spd = float(heavy["base_speed"]) * spd_mult * _stage_speed_mult() * _meteor_slow_mult()
	else:
		hp = int((180 + wave * 35) * hp_mult * _stage_hp_mult())
		spd = 18.0 * (spd_mult / 0.55) * _stage_speed_mult() * _meteor_slow_mult()
	get_tree().current_scene.add_child(boss)
	if boss.has_method("setup_descent"):
		boss.setup_descent(Vector2(x, spawn_y - 20.0), player, fortress, hp, spd)
	if boss.has_method("set_as_boss"):
		boss.set_as_boss(true)
	if _is_boss_stage():
		boss.scale *= 1.35
	boss.connect("enemy_destroyed", _on_enemy_destroyed)
	active_enemies.append(boss)
	creep_spawned.emit(boss)

func _on_enemy_destroyed(enemy) -> void:
	active_enemies.erase(enemy)
	if active_enemies.is_empty():
		wave_cleared.emit(wave)

func stop() -> void:
	running = false
	waiting_for_clear = false
