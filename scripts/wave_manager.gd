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
## Endless sandbox: waves never stop, boss every 5th wave, no level_complete
var test_mode: bool = false
var rng := RandomNumberGenerator.new()

func set_test_mode(enabled: bool) -> void:
	test_mode = enabled

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

	if not test_mode and wave >= max_waves:
		return

	timer -= delta
	if timer <= 0.0:
		_start_next_wave()
		if test_mode or wave < max_waves:
			timer = max(4.0, wave_interval - wave * 0.15)
		else:
			waiting_for_clear = true

func _start_next_wave() -> void:
	wave += 1
	wave_started.emit(wave)

	var is_boss_wave: bool
	if test_mode:
		is_boss_wave = wave > 0 and wave % 5 == 0
	else:
		is_boss_wave = wave == max_waves
	if is_boss_wave:
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
		if test_mode:
			count = mini(count, 26)
		for i in range(count):
			_spawn_creep()

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

func _spawn_creep() -> void:
	if enemy_scene == null:
		return
	var enemy = enemy_scene.instantiate()
	var x := rng.randf_range(60.0, arena_width - 60.0)
	var y := spawn_y + rng.randf_range(-20.0, 40.0)

	var etype: Dictionary = enemy.pick_enemy_type(rng) if enemy.has_method("pick_enemy_type") else {}
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

func _spawn_boss() -> void:
	var scene = boss_scene if boss_scene else enemy_scene
	if scene == null:
		return
	var boss = scene.instantiate()
	var x := arena_width * 0.5
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
