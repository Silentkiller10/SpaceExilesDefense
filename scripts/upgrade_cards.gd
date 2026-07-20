extends RefCounted
class_name UpgradeCards

## category:
##   character  — player weapon / skills
##   tower      — global tower buffs + unlocks
##   specialist — upgrades for one specific unlocked tower
## Wild slot can roll any available card.

static func all_cards() -> Array:
	return [
		# --- Character ---
		{"id": "ignition", "name": "IGNITION", "description": "Bullets apply burn DoT",
			"color": Color(1.0, 0.45, 0.15), "type": "skill", "category": "character"},
		{"id": "contact_pulse", "name": "CONTACT PULSE", "description": "Press E for AoE blast (5s CD)",
			"color": Color(0.35, 0.85, 1.0), "type": "skill", "category": "character"},
		{"id": "piercing", "name": "PIERCING BULLET", "description": "+1 Penetration",
			"color": Color(0.7, 0.4, 1.0), "type": "skill", "category": "character"},
		{"id": "fork", "name": "SPLIT SHOT", "description": "+1 Fork",
			"color": Color(1.0, 0.85, 0.35), "type": "skill", "category": "character"},
		{"id": "damage", "name": "HOLLOW POINT", "description": "+12% Damage",
			"color": Color(1.0, 0.3, 0.35), "type": "stat", "category": "character"},
		{"id": "fire_rate", "name": "HAIR TRIGGER", "description": "+30% Fire Rate",
			"color": Color(1.0, 0.85, 0.2), "type": "stat", "category": "character"},
		{"id": "projectile", "name": "TWIN LINK", "description": "+1 Projectile",
			"color": Color(0.3, 1.0, 0.7), "type": "stat", "category": "character"},
		# --- Tower (global / unlock) ---
		{"id": "tower_power", "name": "OVERCHARGE", "description": "+25% Tower Damage",
			"color": Color(0.4, 1.0, 0.85), "type": "stat", "category": "tower"},
		{"id": "tower_rapid", "name": "COOLANT LOOP", "description": "+20% Tower Fire Rate",
			"color": Color(0.55, 0.95, 1.0), "type": "stat", "category": "tower"},
		{"id": "tower_range", "name": "LONG SIGHT", "description": "+20% Tower Range",
			"color": Color(0.65, 0.8, 1.0), "type": "stat", "category": "tower"},
		{"id": "tower_fortify", "name": "REINFORCE", "description": "+80 Fortress HP",
			"color": Color(0.5, 0.7, 1.0), "type": "stat", "category": "tower"},
		{"id": "tower_laser", "name": "LASER", "description": "Unlock Laser tower",
			"color": Color(1.0, 0.2, 0.5), "type": "tower", "category": "tower"},
		{"id": "tower_cannon", "name": "CANNON", "description": "Slow fire, big AoE damage",
			"color": Color(1.0, 0.55, 0.2), "type": "tower", "category": "tower"},
		{"id": "tower_machinegun", "name": "MACHINE GUN", "description": "Fast sustained DPS",
			"color": Color(0.85, 0.9, 1.0), "type": "tower", "category": "tower"},
		{"id": "tower_railgun", "name": "RAILGUN", "description": "Slow fire, huge single-target damage, map range",
			"color": Color(0.45, 0.85, 1.0), "type": "tower", "category": "tower"},
		{"id": "tower_flamethrower", "name": "FLAME THROWER", "description": "Short range burn spray",
			"color": Color(1.0, 0.4, 0.1), "type": "tower", "category": "tower"},
		{"id": "tower_rocket", "name": "ROCKET LAUNCHER", "description": "4 rockets/sec, explosive AoE",
			"color": Color(0.4, 0.75, 1.0), "type": "tower", "category": "tower"},
		# --- Specialist (single tower) ---
		{"id": "spec_laser_dmg", "name": "LASER FOCUS", "description": "Laser damage +50%",
			"color": Color(1.0, 0.35, 0.6), "type": "specialist", "category": "specialist",
			"target": "laser", "effect": "damage_mult", "amount": 0.5},
		{"id": "spec_laser_rate", "name": "LASER CYCLE", "description": "Laser fire rate +35%",
			"color": Color(1.0, 0.45, 0.7), "type": "specialist", "category": "specialist",
			"target": "laser", "effect": "fire_rate", "amount": 0.35},
		{"id": "spec_laser_range", "name": "LASER REACH", "description": "Laser range +30%",
			"color": Color(1.0, 0.55, 0.75), "type": "specialist", "category": "specialist",
			"target": "laser", "effect": "range_mult", "amount": 0.3},
		{"id": "spec_mg_dmg", "name": "MG HOLLOW", "description": "Machine Gun damage +50%",
			"color": Color(0.85, 0.9, 1.0), "type": "specialist", "category": "specialist",
			"target": "machinegun", "effect": "damage_mult", "amount": 0.5},
		{"id": "spec_mg_shots", "name": "MG BURST", "description": "Machine Gun shots +1, -10% damage",
			"color": Color(0.75, 0.85, 1.0), "type": "specialist", "category": "specialist",
			"target": "machinegun", "effect": "shots", "amount": 1, "damage_penalty": 0.1},
		{"id": "spec_mg_rate", "name": "MG OVERSPIN", "description": "Machine Gun fire rate +25%",
			"color": Color(0.7, 0.8, 0.95), "type": "specialist", "category": "specialist",
			"target": "machinegun", "effect": "fire_rate", "amount": 0.25},
		{"id": "spec_cannon_dmg", "name": "HE SHELLS", "description": "Cannon damage +50%",
			"color": Color(1.0, 0.55, 0.2), "type": "specialist", "category": "specialist",
			"target": "cannon", "effect": "damage_mult", "amount": 0.5},
		{"id": "spec_cannon_shots", "name": "DOUBLE BARREL", "description": "Cannon shots +1, -10% damage",
			"color": Color(1.0, 0.65, 0.3), "type": "specialist", "category": "specialist",
			"target": "cannon", "effect": "shots", "amount": 1, "damage_penalty": 0.1},
		{"id": "spec_cannon_range", "name": "CANNON REACH", "description": "Cannon range +30%",
			"color": Color(1.0, 0.7, 0.35), "type": "specialist", "category": "specialist",
			"target": "cannon", "effect": "range_mult", "amount": 0.3},
		{"id": "spec_rail_dmg", "name": "RAIL CHARGE", "description": "Railgun damage +50%",
			"color": Color(0.45, 0.85, 1.0), "type": "specialist", "category": "specialist",
			"target": "railgun", "effect": "damage_mult", "amount": 0.5},
		{"id": "spec_rail_shots", "name": "RAIL VOLLEY", "description": "Railgun shots +1, -10% damage",
			"color": Color(0.55, 0.9, 1.0), "type": "specialist", "category": "specialist",
			"target": "railgun", "effect": "shots", "amount": 1, "damage_penalty": 0.1},
		{"id": "spec_rail_rate", "name": "RAIL CAPACITOR", "description": "Railgun fire rate +30%",
			"color": Color(0.4, 0.8, 1.0), "type": "specialist", "category": "specialist",
			"target": "railgun", "effect": "fire_rate", "amount": 0.3},
		{"id": "spec_flame_dmg", "name": "NAPALM", "description": "Flame Thrower damage +50%",
			"color": Color(1.0, 0.4, 0.1), "type": "specialist", "category": "specialist",
			"target": "flamethrower", "effect": "damage_mult", "amount": 0.5},
		{"id": "spec_flame_range", "name": "WIDE BURN", "description": "Flame Thrower range +40%",
			"color": Color(1.0, 0.5, 0.15), "type": "specialist", "category": "specialist",
			"target": "flamethrower", "effect": "range_mult", "amount": 0.4},
		{"id": "spec_flame_rate", "name": "FUEL PUMP", "description": "Flame Thrower fire rate +30%",
			"color": Color(1.0, 0.45, 0.2), "type": "specialist", "category": "specialist",
			"target": "flamethrower", "effect": "fire_rate", "amount": 0.3},
		{"id": "spec_rocket_salvo", "name": "FULL SALVO", "description": "Rocket Launcher +1 rocket, -10% damage",
			"color": Color(0.45, 0.8, 1.0), "type": "specialist", "category": "specialist",
			"target": "rocket", "effect": "shots", "amount": 1, "damage_penalty": 0.1},
		{"id": "spec_rocket_dmg", "name": "HEAVY WARHEADS", "description": "Rocket Launcher damage +50%",
			"color": Color(0.4, 0.75, 1.0), "type": "specialist", "category": "specialist",
			"target": "rocket", "effect": "damage_mult", "amount": 0.5},
		{"id": "spec_rocket_range", "name": "LONG BURN", "description": "Rocket Launcher fire range +30%",
			"color": Color(0.5, 0.82, 1.0), "type": "specialist", "category": "specialist",
			"target": "rocket", "effect": "range_mult", "amount": 0.3},
		{"id": "spec_rocket_aoe", "name": "BIG BLAST", "description": "Rocket explosion AoE +40%",
			"color": Color(0.55, 0.85, 1.0), "type": "specialist", "category": "specialist",
			"target": "rocket", "effect": "aoe_mult", "amount": 0.4},
		{"id": "spec_rocket_rate", "name": "RAPID RELOAD", "description": "Rocket Launcher fire rate +30%",
			"color": Color(0.6, 0.87, 1.0), "type": "specialist", "category": "specialist",
			"target": "rocket", "effect": "fire_rate", "amount": 0.3},
	]

static func category_label(category: String) -> String:
	match category:
		"character":
			return "CHARACTER"
		"tower":
			return "TOWER"
		"specialist":
			return "SPECIALIST"
		"random":
			return "WILD"
		_:
			return category.to_upper()

static func _is_available(card: Dictionary, unlocked_towers: Dictionary) -> bool:
	var ctype := String(card.get("type", ""))
	if ctype == "tower":
		var key := String(card["id"]).replace("tower_", "")
		return not unlocked_towers.get(key, false)
	if ctype == "specialist" or String(card.get("category", "")) == "specialist":
		var target := String(card.get("target", ""))
		return unlocked_towers.get(target, false)
	return true

static func _pool_for_category(category: String, unlocked_towers: Dictionary) -> Array:
	var pool: Array = []
	for card in all_cards():
		if not _is_available(card, unlocked_towers):
			continue
		if category == "any" or String(card.get("category", "")) == category:
			pool.append(card)
	return pool

static func _pick_one(pool: Array, rng: RandomNumberGenerator, exclude_ids: Array) -> Dictionary:
	var filtered: Array = []
	for card in pool:
		if String(card.get("id", "")) in exclude_ids:
			continue
		filtered.append(card)
	if filtered.is_empty():
		filtered = pool
	if filtered.is_empty():
		return {}
	return filtered[rng.randi() % filtered.size()]

static func _append_pick(picks: Array, used_ids: Array, card: Dictionary, offer_slot: String) -> void:
	if card.is_empty():
		return
	var copy: Dictionary = card.duplicate(true)
	copy["offer_slot"] = offer_slot
	picks.append(copy)
	used_ids.append(String(copy["id"]))

## Level-up offers: [character, tower, specialist, wild]
static func pick_three(unlocked_towers: Dictionary, _gear, rng: RandomNumberGenerator) -> Array:
	return pick_level_up(unlocked_towers, _gear, rng)

static func pick_level_up(unlocked_towers: Dictionary, _gear, rng: RandomNumberGenerator) -> Array:
	var char_pool := _pool_for_category("character", unlocked_towers)
	var tower_pool := _pool_for_category("tower", unlocked_towers)
	var spec_pool := _pool_for_category("specialist", unlocked_towers)
	var any_pool := _pool_for_category("any", unlocked_towers)

	var picks: Array = []
	var used_ids: Array = []

	var character_card := _pick_one(char_pool, rng, used_ids)
	if character_card.is_empty():
		character_card = _pick_one(any_pool, rng, used_ids)
	_append_pick(picks, used_ids, character_card, "character")

	var tower_card := _pick_one(tower_pool, rng, used_ids)
	if tower_card.is_empty():
		tower_card = _pick_one(any_pool, rng, used_ids)
	_append_pick(picks, used_ids, tower_card, "tower")

	var spec_card := _pick_one(spec_pool, rng, used_ids)
	if spec_card.is_empty():
		# No specialist available yet (few towers unlocked) — fall back to tower/any
		spec_card = _pick_one(tower_pool, rng, used_ids)
		if spec_card.is_empty():
			spec_card = _pick_one(any_pool, rng, used_ids)
	_append_pick(picks, used_ids, spec_card, "specialist")

	var wild_card := _pick_one(any_pool, rng, used_ids)
	if wild_card.is_empty() and any_pool.size() > 0:
		wild_card = any_pool[rng.randi() % any_pool.size()]
	_append_pick(picks, used_ids, wild_card, "random")

	var fallback := all_cards()
	while picks.size() < 4 and fallback.size() > 0:
		var card: Dictionary = fallback[rng.randi() % fallback.size()].duplicate(true)
		card["offer_slot"] = "random"
		picks.append(card)
	return picks
