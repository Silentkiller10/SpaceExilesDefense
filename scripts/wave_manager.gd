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
const KAMIKAZE_SCENE := preload("res://scenes/enemy_ship_kamikaze.tscn")
const CARRIER_SCENE := preload("res://scenes/enemy_ship_carrier.tscn")
const CYBORG_SCENE := preload("res://scenes/boss_cyborg.tscn")
const GIANT_STAR_SCENE := preload("res://scenes/boss_star.tscn")
const EnemyScript := preload("res://scripts/enemy.gd")

## --- Threat-budget wave composition ---
## Each wave gets a threat budget (grows with wave + stage) and "buys"
## enemies from this table until the budget runs out. Weights shift with
## stage: cheap normals fade out, expensive specials take over — later
## stages produce fewer but much scarier waves.
##   cost         — budget points this enemy consumes
##   base_w       — spawn weight at stage 1
##   w_per_stage  — weight change per stage past the first (can be negative)
##   min_w        — weight floor so cheap types never fully vanish
##   min_wave     — earliest wave this type may appear
##   max_per_wave — hard cap per wave (0 = unlimited)
const SPAWN_TABLE := [
	{"id": "small", "kind": "creep", "cost": 1, "base_w": 1.30, "w_per_stage": -0.12, "min_w": 0.15, "min_wave": 1, "max_per_wave": 0},
	{"id": "normal", "kind": "creep", "cost": 2, "base_w": 1.10, "w_per_stage": -0.08, "min_w": 0.15, "min_wave": 1, "max_per_wave": 0},
	{"id": "ufo", "kind": "creep", "cost": 3, "base_w": 0.70, "w_per_stage": 0.08, "min_w": 0.0, "min_wave": 1, "max_per_wave": 0},
	{"id": "heavy", "kind": "creep", "cost": 4, "base_w": 0.60, "w_per_stage": 0.10, "min_w": 0.0, "min_wave": 2, "max_per_wave": 0},
	{"id": "rocketeer", "kind": "rocketeer", "cost": 8, "base_w": 0.15, "w_per_stage": 0.12, "min_w": 0.0, "min_wave": 3, "max_per_wave": 3},
	{"id": "kamikaze", "kind": "kamikaze", "cost": 6, "base_w": 0.10, "w_per_stage": 0.10, "min_w": 0.0, "min_wave": 4, "max_per_wave": 2},
]

## --- Chunked spawn pipeline ---
## Waves no longer spawn all enemies in one frame. Spawn jobs go into a
## queue; every CHUNK_INTERVAL a chunk of CHUNK_SIZE jobs is released.
## Each chunk's PackedScene.instantiate() calls run on a worker thread
## (safe: the nodes are not in the tree yet); the main thread only does
## the cheap part — add_child + setup — once the task completes. The
## SceneTree itself is not thread-safe, so adding must stay on main.
const CHUNK_SIZE := 4
const CHUNK_INTERVAL := 0.7

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
## Endless mode: waves never stop, difficulty ramps every wave
var infinity_mode: bool = false
var rng := RandomNumberGenerator.new()

## Pending spawn jobs: {"kind": "creep"|"rocketeer"|"boss", ...}
var _spawn_queue: Array = []
var _chunk_timer: float = 0.0
## In-flight worker-thread chunks: {"id": task_id, "jobs": Array, "nodes": Array}
var _pending_tasks: Array = []

func set_test_mode(enabled: bool) -> void:
	test_mode = enabled

func set_infinity_mode(enabled: bool) -> void:
	infinity_mode = enabled
	if enabled:
		test_mode = false

## Sandbox on-demand spawning. id is one of the basic enemy ids
## ("small", "normal", "heavy", "ufo") or "rocketeer" / "boss" / "cyborg" / "giant_star".
func spawn_sandbox_enemy(id: String, count: int) -> void:
	for i in count:
		match id:
			"rocketeer":
				_spawn_queue.append({"kind": "rocketeer"})
			"kamikaze":
				_spawn_queue.append({"kind": "kamikaze"})
			"carrier":
				_spawn_queue.append({"kind": "carrier"})
			"cyborg":
				_spawn_queue.append({"kind": "cyborg"})
			"giant_star":
				_spawn_queue.append({"kind": "giant_star"})
			"boss":
				_spawn_queue.append({"kind": "boss", "x": rng.randf_range(90.0, arena_width - 90.0)})
			_:
				_spawn_queue.append({"kind": "creep", "etype": EnemyScript.get_enemy_type(id)})
	# Sandbox button presses should feel instant — release the first chunk now
	_chunk_timer = 0.0

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

	# Drain the spawn pipeline in every mode (waves and sandbox buttons)
	_finalize_completed_chunks()
	_chunk_timer -= delta
	if _chunk_timer <= 0.0 and not _spawn_queue.is_empty():
		_chunk_timer = CHUNK_INTERVAL
		_release_chunk()

	# After final wave is queued, wait until everything spawned AND died
	if waiting_for_clear:
		if active_enemies.is_empty() and _spawn_queue.is_empty() and _pending_tasks.is_empty():
			waiting_for_clear = false
			running = false
			level_complete.emit(wave)
		return

	# Sandbox: never runs timed waves — spawning is button-driven
	if test_mode:
		return

	if not infinity_mode and wave >= max_waves:
		return

	timer -= delta
	if timer <= 0.0:
		_start_next_wave()
		if infinity_mode:
			timer = max(3.0, wave_interval - wave * 0.12)
		elif wave < max_waves:
			timer = max(4.0, wave_interval - wave * 0.15)
		else:
			waiting_for_clear = true

func _start_next_wave() -> void:
	wave += 1
	wave_started.emit(wave)

	var is_final_boss := not infinity_mode and wave == max_waves
	var is_infinity_boss := infinity_mode and wave > 0 and wave % 5 == 0

	if is_final_boss or is_infinity_boss:
		boss_incoming.emit(wave)
		if _should_spawn_giant_star():
			_spawn_queue.append({"kind": "giant_star"})
		else:
			_spawn_queue.append({"kind": "boss", "x": -1.0})
		var escort_budget := int(_wave_budget() * (0.5 if is_final_boss else 0.65))
		for job in _buy_wave_jobs(escort_budget):
			_spawn_queue.append(job)
	else:
		for job in _buy_wave_jobs(_wave_budget()):
			_spawn_queue.append(job)
	# First chunk of the new wave lands on the next frame
	_chunk_timer = 0.0

func _should_spawn_giant_star() -> bool:
	## Giant Star replaces the end boss once the campaign is past stage 10.
	return _effective_stage() > 10

## Total threat points this wave may spend.
func _wave_budget() -> int:
	var eff_stage := _effective_stage()
	var budget := 10 + wave * 5 + eff_stage * 3
	if infinity_mode:
		budget += wave * 3 + int(wave * wave * 0.12)
	if _is_boss_stage():
		budget += 6
	return budget

func _effective_stage() -> int:
	if infinity_mode:
		return maxi(1, 1 + wave / 8)
	return stage

func _entry_weight(entry: Dictionary) -> float:
	var eff := _effective_stage()
	var w := float(entry["base_w"]) + float(entry["w_per_stage"]) * float(eff - 1)
	return maxf(float(entry["min_w"]), w)

## Spends the budget on a weighted-random shopping list of spawn jobs.
func _buy_wave_jobs(budget: int) -> Array:
	var jobs: Array = []
	var counts: Dictionary = {}
	var guard := 400
	while budget > 0 and guard > 0:
		guard -= 1
		var candidates: Array = []
		var total := 0.0
		for entry in SPAWN_TABLE:
			if int(entry["cost"]) > budget:
				continue
			if wave < int(entry["min_wave"]):
				continue
			var cap := int(entry["max_per_wave"])
			if cap > 0 and int(counts.get(entry["id"], 0)) >= cap:
				continue
			var w := _entry_weight(entry)
			if w <= 0.0:
				continue
			candidates.append(entry)
			total += w
		if candidates.is_empty():
			break
		var roll := rng.randf() * total
		var acc := 0.0
		var picked: Dictionary = candidates[0]
		for entry in candidates:
			acc += _entry_weight(entry)
			if roll <= acc:
				picked = entry
				break
		var id := String(picked["id"])
		counts[id] = int(counts.get(id, 0)) + 1
		budget -= int(picked["cost"])
		var kind := String(picked["kind"])
		if kind == "creep":
			jobs.append({"kind": "creep", "etype": EnemyScript.get_enemy_type(id)})
		else:
			jobs.append({"kind": kind})
	return jobs

## --- Spawn pipeline: threaded instantiate, main-thread add ---

func _scene_for_kind(kind: String) -> PackedScene:
	match kind:
		"rocketeer":
			return ROCKETEER_SCENE
		"kamikaze":
			return KAMIKAZE_SCENE
		"carrier":
			return CARRIER_SCENE
		"cyborg":
			return CYBORG_SCENE
		"giant_star":
			return GIANT_STAR_SCENE
		"boss":
			return boss_scene if boss_scene else enemy_scene
		_:
			return enemy_scene

func _release_chunk() -> void:
	var jobs: Array = []
	for i in mini(CHUNK_SIZE, _spawn_queue.size()):
		jobs.append(_spawn_queue.pop_front())
	var scenes: Array = []
	for job in jobs:
		scenes.append(_scene_for_kind(String(job["kind"])))
	var nodes: Array = []
	nodes.resize(jobs.size())
	var task_id := WorkerThreadPool.add_task(
		_instantiate_chunk.bind(scenes, nodes), false, "wave spawn chunk"
	)
	_pending_tasks.append({"id": task_id, "jobs": jobs, "nodes": nodes})

## Runs on a worker thread. Only instantiates — the nodes are not in the
## tree yet, so this is safe off the main thread.
func _instantiate_chunk(scenes: Array, nodes: Array) -> void:
	for i in scenes.size():
		var scene: PackedScene = scenes[i]
		nodes[i] = scene.instantiate() if scene else null

func _finalize_completed_chunks() -> void:
	if _pending_tasks.is_empty():
		return
	var still_pending: Array = []
	for task in _pending_tasks:
		if not WorkerThreadPool.is_task_completed(int(task["id"])):
			still_pending.append(task)
			continue
		WorkerThreadPool.wait_for_task_completion(int(task["id"]))
		var jobs: Array = task["jobs"]
		var nodes: Array = task["nodes"]
		for i in jobs.size():
			var node = nodes[i]
			if node == null:
				continue
			var job: Dictionary = jobs[i]
			match String(job["kind"]):
				"rocketeer":
					_finalize_rocketeer(node)
				"kamikaze":
					_finalize_kamikaze(node)
				"carrier":
					_finalize_carrier(node)
				"cyborg":
					_finalize_cyborg(node)
				"giant_star":
					_finalize_giant_star(node)
				"boss":
					_finalize_boss(node, float(job.get("x", -1.0)))
				_:
					_finalize_creep(node, job.get("etype", {}))
	_pending_tasks = still_pending

func _is_boss_stage() -> bool:
	if infinity_mode:
		return wave > 0 and wave % 5 == 0
	return PlayerData.is_boss_stage(stage)

func _stage_hp_mult() -> float:
	var eff := _effective_stage()
	var m := 1.0 + (eff - 1) * 0.25
	if infinity_mode:
		m += float(wave) * 0.06
	if _is_boss_stage():
		m *= 1.35
	return m

func _stage_speed_mult() -> float:
	var eff := _effective_stage()
	var m := 1.0 + (eff - 1) * 0.08
	if infinity_mode:
		m += float(wave) * 0.025
	if _is_boss_stage():
		m *= 1.10
	return m

func _meteor_slow_mult() -> float:
	var slow: float = float(PlayerData.get_equipped_bonuses().get("meteor_slow", 0.0))
	return 1.0 - clampf(slow, 0.0, 0.45)

func _finalize_creep(enemy: Node, etype_in) -> void:
	var etype: Dictionary = etype_in if etype_in is Dictionary else {}
	if etype.is_empty():
		etype = EnemyScript.pick_enemy_type(rng)
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

func _finalize_rocketeer(ship: Node) -> void:
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

func _finalize_kamikaze(ship: Node) -> void:
	var x := rng.randf_range(90.0, arena_width - 90.0)
	var hp := int((170.0 + float(wave) * 28.0) * _stage_hp_mult())
	# Starts fast — the accelerating dive is its whole identity
	var spd := (110.0 + float(wave) * 3.0) * _stage_speed_mult() * _meteor_slow_mult()
	get_tree().current_scene.add_child(ship)
	ship.setup_descent(Vector2(x, spawn_y - 10.0), player, fortress, hp, spd)
	var orb_hp := int((35.0 + float(wave) * 8.0) * _stage_hp_mult())
	var boom := 25 + wave + (stage - 1) * 3
	ship.setup_kamikaze(orb_hp, boom)
	ship.connect("enemy_destroyed", _on_enemy_destroyed)
	active_enemies.append(ship)
	creep_spawned.emit(ship)

func _finalize_carrier(ship: Node) -> void:
	# Hard cap: never more than 2 motherships alive at once
	if _live_carrier_count() >= 2:
		ship.free()
		return
	var x := rng.randf_range(140.0, arena_width - 140.0)
	var hp := int((190.0 + float(wave) * 27.5) * _stage_hp_mult())
	# For the carrier "speed" is the horizontal patrol speed
	var spd := (60.0 + float(wave) * 1.5) * _stage_speed_mult()
	get_tree().current_scene.add_child(ship)
	ship.setup_descent(Vector2(x, spawn_y + 50.0), player, fortress, hp, spd)
	var mini_hp := int((70.0 + float(wave) * 14.0) * _stage_hp_mult())
	var mini_spd := (48.0 + float(wave) * 1.2) * _stage_speed_mult() * _meteor_slow_mult()
	var mini_bullet_dmg := 3 + int(wave / 3.0) + (stage - 1)
	ship.setup_carrier(mini_hp, mini_spd, mini_bullet_dmg)
	ship.mini_registrar = _register_deployed_mini
	ship.connect("enemy_destroyed", _on_enemy_destroyed)
	active_enemies.append(ship)
	creep_spawned.emit(ship)

func _live_carrier_count() -> int:
	var count := 0
	for e in active_enemies:
		if is_instance_valid(e) and e.get("type_id") == "carrier" and e.get("is_dying") != true:
			count += 1
	return count

## Minis the carrier deploys mid-flight (or on death) enter the same
## bookkeeping as wave spawns: XP hookup + wave-clear tracking.
func _register_deployed_mini(mini: Node) -> void:
	mini.connect("enemy_destroyed", _on_enemy_destroyed)
	active_enemies.append(mini)
	creep_spawned.emit(mini)

## Cyborg boss (phase 1): jet-hovers at the top, sniping the player,
## EMP-ing towers, and keeping 2 carrier motherships deployed.
func _finalize_cyborg(boss: Node) -> void:
	var hp := int((2400.0 + float(wave) * 260.0) * _stage_hp_mult())
	# For the cyborg "speed" is the jet strafe speed between hover points
	var spd := 170.0 * _stage_speed_mult()
	get_tree().current_scene.add_child(boss)
	boss.setup_descent(Vector2(arena_width * 0.5, spawn_y + 90.0), player, fortress, hp, spd)
	# Its carrier fleet mirrors wave-spawned carrier stats
	var c_hp := int((190.0 + float(wave) * 27.5) * _stage_hp_mult())
	var c_spd := (60.0 + float(wave) * 1.5) * _stage_speed_mult()
	var mini_hp := int((70.0 + float(wave) * 14.0) * _stage_hp_mult())
	var mini_spd := (48.0 + float(wave) * 1.2) * _stage_speed_mult() * _meteor_slow_mult()
	var mini_bullet_dmg := 3 + int(wave / 3.0) + (stage - 1)
	var gun_dmg := 12 + wave + (stage - 1) * 2
	boss.setup_cyborg(gun_dmg, c_hp, c_spd, mini_hp, mini_spd, mini_bullet_dmg)
	boss.deploy_registrar = _register_deployed_mini
	boss.connect("enemy_destroyed", _on_enemy_destroyed)
	active_enemies.append(boss)
	creep_spawned.emit(boss)

## Giant Star — post-stage-10 end boss. Huge HP, slow drift, rains falling stars.
func _finalize_giant_star(boss: Node) -> void:
	var hp := int((90000.0 + float(wave) * 5200.0 + float(maxi(0, stage - 10)) * 8000.0) * _stage_hp_mult())
	# Enter from above the arena so it drifts in instead of popping on-screen
	var spd := 28.0 * _stage_speed_mult()
	get_tree().current_scene.add_child(boss)
	boss.setup_descent(Vector2(arena_width * 0.5, -220.0), player, fortress, hp, spd)
	var dmg_scale := 1.0 + float(maxi(0, stage - 10)) * 0.08 + float(wave) * 0.02
	if boss.has_method("setup_star"):
		boss.setup_star(dmg_scale)
	boss.connect("enemy_destroyed", _on_enemy_destroyed)
	active_enemies.append(boss)
	creep_spawned.emit(boss)

func _finalize_boss(boss: Node, x_override: float = -1.0) -> void:
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
	_spawn_queue.clear()

## Never leave worker tasks running or orphan nodes behind on scene change
func _exit_tree() -> void:
	for task in _pending_tasks:
		WorkerThreadPool.wait_for_task_completion(int(task["id"]))
		for node in task["nodes"]:
			if node is Node:
				node.free()
	_pending_tasks.clear()
