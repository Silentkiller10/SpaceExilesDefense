extends Node

## Persistent loadout + inventory for hub Character screen.
## Autoload name: PlayerData

signal inventory_changed
signal equipment_changed
signal coins_changed(total: int)

const SAVE_PATH := "user://fortress_player_data.json"
const SLOT_NAMES := ["Helmet", "Armor", "Gloves", "Boots", "Weapon", "Ring1", "Ring2"]

## Display rows for Character / Shop inventory (grouped by gear type).
const GEAR_ROWS := [
	{"title": "WEAPONS", "slots": ["Weapon"]},
	{"title": "HELMETS", "slots": ["Helmet"]},
	{"title": "ARMOR", "slots": ["Armor"]},
	{"title": "GLOVES", "slots": ["Gloves"]},
	{"title": "BOOTS", "slots": ["Boots"]},
	{"title": "RINGS", "slots": ["Ring1", "Ring2"]},
]

## Character screen soldier art (738×1024, gear slots drawn in UI).
const CHARACTER_PANEL_PATH := "res://assets/png/player_character.png"

## Slot -> gear icon art (standalone item PNGs in assets/png/).
const SLOT_ICONS := {
	"Helmet": "res://assets/png/helmet.png",
	"Armor": "res://assets/png/body armour.png",
	"Gloves": "res://assets/png/Gloves.png",
	"Boots": "res://assets/png/Boots.png",
	"Weapon": "res://assets/png/Weapon.png",
	"Ring1": "res://assets/png/Ring 1.png",
	"Ring2": "res://assets/png/Ring 2.png",
}

## inventory entries: { uid, template_id, name, slot, mods[{bonus,amount}], bonus, amount, color_r/g/b, rarity }
## bonus/amount mirror the first mod for older UI; mods[] is the source of truth.
const INT_BONUSES := ["fortress_hp", "fork", "pierce", "projectiles", "burn"]
var inventory: Array = []
## equipped: slot_name -> uid (or "" if empty)
var equipped: Dictionary = {}
var highest_wave: int = 0
var levels_cleared: int = 0
var current_stage: int = 1
var selected_stage: int = 1
var coins: int = 0
var _uid_counter: int = 1
var _tex_cache: Dictionary = {}

## Persistent character progression / skill tree
var char_level: int = 1
var char_xp: int = 0
var skill_points: int = 0
var unlocked_skills: Array = ["core"]
const SKILL_POINTS_PER_LEVEL := 1

var _skill_nodes_cache: Array = []
var _skill_node_map: Dictionary = {}

signal skill_tree_changed
signal character_leveled(new_level: int)

func _ready() -> void:
	for slot_name in SLOT_NAMES:
		equipped[slot_name] = ""
	load_data()
	_purge_amulets()
	_sync_inventory_from_catalog()
	clamp_selected_stage()
	# Guarantee a starter weapon in inventory if empty
	if inventory.is_empty():
		add_item_from_template("weapon_pulse")
		equip_uid(inventory[0]["uid"])
		save_data()

func _sync_inventory_from_catalog() -> void:
	## Keep owned items' stats in line with current catalog templates.
	var changed := false
	for item in inventory:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var t: Dictionary = get_template(String(item.get("template_id", "")))
		if t.is_empty():
			continue
		var new_mods: Array = get_template_mods(t)
		var new_name := String(t["name"])
		var old_mods_s := JSON.stringify(item.get("mods", []))
		var new_mods_s := JSON.stringify(new_mods)
		if old_mods_s != new_mods_s \
				or String(item.get("name", "")) != new_name \
				or not item.has("mods"):
			_apply_template_fields_to_item(item, t)
			changed = true
	if changed:
		save_data()

func _apply_template_fields_to_item(item: Dictionary, t: Dictionary) -> void:
	var mods: Array = get_template_mods(t)
	item["name"] = String(t["name"])
	item["slot"] = String(t["slot"])
	item["rarity"] = String(t.get("rarity", item.get("rarity", "common")))
	item["mods"] = mods.duplicate(true)
	if mods.size() > 0:
		item["bonus"] = String(mods[0].get("bonus", "damage"))
		item["amount"] = float(mods[0].get("amount", 0.0))
	var c: Color = t.get("color", Color.WHITE)
	item["color_r"] = c.r
	item["color_g"] = c.g
	item["color_b"] = c.b

func _purge_amulets() -> void:
	var changed := false
	var kept: Array = []
	for item in inventory:
		if String(item.get("slot", "")) == "Amulet" or String(item.get("template_id", "")).begins_with("amulet_"):
			changed = true
			continue
		kept.append(item)
	inventory = kept
	if equipped.has("Amulet"):
		equipped.erase("Amulet")
		changed = true
	if changed:
		save_data()

func get_catalog() -> Array:
	## Rarity mod counts: common 2 · rare 2–3 · epic 3–4 · legendary 4–5
	## Primary identity mod is first; secondaries are smaller support stats.
	return [
		# --- Common (stage 1+) — 2 mods ---
		{"template_id": "weapon_pulse", "name": "Pulse Rifle", "slot": "Weapon", "rarity": "common", "min_stage": 1,
			"color": Color(0.3, 0.9, 1.0),
			"mods": [{"bonus": "damage", "amount": 0.08}, {"bonus": "fire_rate", "amount": 0.05}]},
		{"template_id": "helmet_neural", "name": "Neural Helm", "slot": "Helmet", "rarity": "common", "min_stage": 1,
			"color": Color(0.5, 0.9, 1.0),
			"mods": [{"bonus": "fire_rate", "amount": 0.14}, {"bonus": "damage", "amount": 0.04}]},
		{"template_id": "armor_plate", "name": "Fortress Plate", "slot": "Armor", "rarity": "common", "min_stage": 1,
			"color": Color(0.4, 0.6, 0.9),
			"mods": [{"bonus": "fortress_hp", "amount": 60.0}, {"bonus": "leak_resist", "amount": 0.05}]},
		{"template_id": "gloves_target", "name": "Target Gloves", "slot": "Gloves", "rarity": "common", "min_stage": 1,
			"color": Color(1.0, 0.5, 0.3),
			"mods": [{"bonus": "fire_rate", "amount": 0.16}, {"bonus": "damage", "amount": 0.05}]},
		{"template_id": "boots_strider", "name": "Strider Boots", "slot": "Boots", "rarity": "common", "min_stage": 1,
			"color": Color(0.3, 1.0, 0.6),
			"mods": [{"bonus": "speed", "amount": 0.12}, {"bonus": "fire_rate", "amount": 0.04}]},
		{"template_id": "ring_teal", "name": "Teal Ring", "slot": "Ring1", "rarity": "common", "min_stage": 1,
			"color": Color(0.2, 0.95, 0.9),
			"mods": [{"bonus": "tower_damage", "amount": 0.14}, {"bonus": "cooldown", "amount": 0.04}]},
		{"template_id": "ring_void", "name": "Void Ring", "slot": "Ring2", "rarity": "common", "min_stage": 1,
			"color": Color(0.6, 0.3, 1.0),
			"mods": [{"bonus": "cooldown", "amount": 0.08}, {"bonus": "tower_damage", "amount": 0.06}]},
		# --- Rare (stage 2+) — 2–3 mods ---
		{"template_id": "weapon_rail", "name": "Rail Cannon", "slot": "Weapon", "rarity": "rare", "min_stage": 2,
			"color": Color(0.5, 0.7, 1.0),
			"mods": [{"bonus": "damage", "amount": 0.16}, {"bonus": "pierce", "amount": 1}, {"bonus": "fire_rate", "amount": 0.05}]},
		{"template_id": "helmet_tactical", "name": "Tactical Visor", "slot": "Helmet", "rarity": "rare", "min_stage": 2,
			"color": Color(0.2, 1.0, 0.8),
			"mods": [{"bonus": "fire_rate", "amount": 0.22}, {"bonus": "damage", "amount": 0.06}, {"bonus": "speed", "amount": 0.04}]},
		{"template_id": "armor_reactor", "name": "Reactor Shell", "slot": "Armor", "rarity": "rare", "min_stage": 2,
			"color": Color(0.55, 0.4, 1.0),
			"mods": [{"bonus": "fortress_hp", "amount": 100.0}, {"bonus": "leak_resist", "amount": 0.08}, {"bonus": "tower_damage", "amount": 0.05}]},
		{"template_id": "gloves_servo", "name": "Servo Gauntlets", "slot": "Gloves", "rarity": "rare", "min_stage": 2,
			"color": Color(1.0, 0.35, 0.2),
			"mods": [{"bonus": "fire_rate", "amount": 0.26}, {"bonus": "damage", "amount": 0.08}, {"bonus": "cooldown", "amount": 0.04}]},
		{"template_id": "gloves_fork", "name": "Fork Gauntlets", "slot": "Gloves", "rarity": "rare", "min_stage": 2,
			"color": Color(1.0, 0.85, 0.35),
			"mods": [{"bonus": "fork", "amount": 4}, {"bonus": "fire_rate", "amount": 0.08}, {"bonus": "damage", "amount": 0.05}]},
		{"template_id": "boots_dash", "name": "Dash Thrusters", "slot": "Boots", "rarity": "rare", "min_stage": 2,
			"color": Color(0.2, 0.95, 0.5),
			"mods": [{"bonus": "speed", "amount": 0.18}, {"bonus": "meteor_slow", "amount": 0.08}, {"bonus": "fire_rate", "amount": 0.04}]},
		{"template_id": "ring_plasma", "name": "Plasma Band", "slot": "Ring1", "rarity": "rare", "min_stage": 2,
			"color": Color(0.7, 0.3, 1.0),
			"mods": [{"bonus": "tower_damage", "amount": 0.24}, {"bonus": "fortress_hp", "amount": 30.0}, {"bonus": "cooldown", "amount": 0.05}]},
		{"template_id": "ring_chrono", "name": "Chrono Loop", "slot": "Ring2", "rarity": "rare", "min_stage": 2,
			"color": Color(0.85, 0.6, 1.0),
			"mods": [{"bonus": "cooldown", "amount": 0.12}, {"bonus": "fire_rate", "amount": 0.06}, {"bonus": "tower_damage", "amount": 0.08}]},
		# --- Epic (stage 4+) — 3–4 mods ---
		{"template_id": "weapon_nova", "name": "Nova Lance", "slot": "Weapon", "rarity": "epic", "min_stage": 4,
			"color": Color(0.85, 0.35, 1.0),
			"mods": [{"bonus": "damage", "amount": 0.26}, {"bonus": "pierce", "amount": 1}, {"bonus": "fire_rate", "amount": 0.08}, {"bonus": "burn", "amount": 1}]},
		{"template_id": "helmet_storm", "name": "Storm Visor", "slot": "Helmet", "rarity": "epic", "min_stage": 4,
			"color": Color(0.7, 0.4, 1.0),
			"mods": [{"bonus": "fire_rate", "amount": 0.32}, {"bonus": "damage", "amount": 0.10}, {"bonus": "projectiles", "amount": 1}, {"bonus": "speed", "amount": 0.05}]},
		{"template_id": "armor_bulwark", "name": "Bulwark Core", "slot": "Armor", "rarity": "epic", "min_stage": 4,
			"color": Color(0.75, 0.45, 1.0),
			"mods": [{"bonus": "fortress_hp", "amount": 180.0}, {"bonus": "leak_resist", "amount": 0.12}, {"bonus": "tower_damage", "amount": 0.10}, {"bonus": "cooldown", "amount": 0.05}]},
		{"template_id": "gloves_predator", "name": "Predator Grips", "slot": "Gloves", "rarity": "epic", "min_stage": 4,
			"color": Color(1.0, 0.25, 0.55),
			"mods": [{"bonus": "fire_rate", "amount": 0.36}, {"bonus": "damage", "amount": 0.12}, {"bonus": "pierce", "amount": 1}, {"bonus": "cooldown", "amount": 0.04}]},
		{"template_id": "gloves_fork_epic", "name": "Prism Forks", "slot": "Gloves", "rarity": "epic", "min_stage": 4,
			"color": Color(1.0, 0.7, 0.2),
			"mods": [{"bonus": "fork", "amount": 4}, {"bonus": "fire_rate", "amount": 0.12}, {"bonus": "damage", "amount": 0.10}, {"bonus": "projectiles", "amount": 1}]},
		{"template_id": "boots_warp", "name": "Warp Skates", "slot": "Boots", "rarity": "epic", "min_stage": 4,
			"color": Color(0.55, 1.0, 0.4),
			"mods": [{"bonus": "speed", "amount": 0.28}, {"bonus": "meteor_slow", "amount": 0.12}, {"bonus": "fire_rate", "amount": 0.06}, {"bonus": "cooldown", "amount": 0.05}]},
		{"template_id": "ring_overcharge", "name": "Overcharge Band", "slot": "Ring1", "rarity": "epic", "min_stage": 4,
			"color": Color(0.95, 0.4, 1.0),
			"mods": [{"bonus": "tower_damage", "amount": 0.38}, {"bonus": "fortress_hp", "amount": 50.0}, {"bonus": "cooldown", "amount": 0.08}, {"bonus": "damage", "amount": 0.05}]},
		{"template_id": "ring_temporal", "name": "Temporal Band", "slot": "Ring2", "rarity": "epic", "min_stage": 4,
			"color": Color(0.9, 0.5, 1.0),
			"mods": [{"bonus": "cooldown", "amount": 0.18}, {"bonus": "fire_rate", "amount": 0.10}, {"bonus": "tower_damage", "amount": 0.10}, {"bonus": "speed", "amount": 0.05}]},
		# --- Legendary (stage 7+) — 4–5 mods ---
		{"template_id": "weapon_oblivion", "name": "Oblivion Rail", "slot": "Weapon", "rarity": "legendary", "min_stage": 7,
			"color": Color(1.0, 0.75, 0.2),
			"mods": [{"bonus": "damage", "amount": 0.38}, {"bonus": "pierce", "amount": 2}, {"bonus": "fire_rate", "amount": 0.10}, {"bonus": "burn", "amount": 1}, {"bonus": "projectiles", "amount": 1}]},
		{"template_id": "helmet_oracle", "name": "Oracle Crown", "slot": "Helmet", "rarity": "legendary", "min_stage": 7,
			"color": Color(1.0, 0.8, 0.25),
			"mods": [{"bonus": "fire_rate", "amount": 0.42}, {"bonus": "damage", "amount": 0.12}, {"bonus": "projectiles", "amount": 1}, {"bonus": "pierce", "amount": 1}, {"bonus": "speed", "amount": 0.06}]},
		{"template_id": "armor_aegis", "name": "Aegis Fortress", "slot": "Armor", "rarity": "legendary", "min_stage": 7,
			"color": Color(1.0, 0.7, 0.15),
			"mods": [{"bonus": "fortress_hp", "amount": 280.0}, {"bonus": "leak_resist", "amount": 0.18}, {"bonus": "tower_damage", "amount": 0.15}, {"bonus": "cooldown", "amount": 0.08}, {"bonus": "meteor_slow", "amount": 0.06}]},
		{"template_id": "gloves_executioner", "name": "Executioner Fists", "slot": "Gloves", "rarity": "legendary", "min_stage": 7,
			"color": Color(1.0, 0.55, 0.1),
			"mods": [{"bonus": "fire_rate", "amount": 0.45}, {"bonus": "damage", "amount": 0.15}, {"bonus": "pierce", "amount": 1}, {"bonus": "projectiles", "amount": 1}, {"bonus": "cooldown", "amount": 0.05}]},
		{"template_id": "gloves_fork_legend", "name": "Rift Splitters", "slot": "Gloves", "rarity": "legendary", "min_stage": 7,
			"color": Color(1.0, 0.9, 0.35),
			"mods": [{"bonus": "fork", "amount": 4}, {"bonus": "fire_rate", "amount": 0.15}, {"bonus": "damage", "amount": 0.12}, {"bonus": "projectiles", "amount": 1}, {"bonus": "pierce", "amount": 1}]},
		{"template_id": "boots_phase", "name": "Phase Striders", "slot": "Boots", "rarity": "legendary", "min_stage": 7,
			"color": Color(1.0, 0.85, 0.3),
			"mods": [{"bonus": "speed", "amount": 0.38}, {"bonus": "meteor_slow", "amount": 0.18}, {"bonus": "fire_rate", "amount": 0.10}, {"bonus": "cooldown", "amount": 0.08}, {"bonus": "tower_damage", "amount": 0.08}]},
		{"template_id": "ring_singularity", "name": "Singularity Core", "slot": "Ring1", "rarity": "legendary", "min_stage": 7,
			"color": Color(1.0, 0.65, 0.15),
			"mods": [{"bonus": "tower_damage", "amount": 0.55}, {"bonus": "fortress_hp", "amount": 80.0}, {"bonus": "cooldown", "amount": 0.10}, {"bonus": "damage", "amount": 0.08}, {"bonus": "fire_rate", "amount": 0.06}]},
		{"template_id": "ring_eternal", "name": "Eternal Loop", "slot": "Ring2", "rarity": "legendary", "min_stage": 7,
			"color": Color(1.0, 0.78, 0.2),
			"mods": [{"bonus": "cooldown", "amount": 0.28}, {"bonus": "fire_rate", "amount": 0.12}, {"bonus": "tower_damage", "amount": 0.15}, {"bonus": "speed", "amount": 0.08}, {"bonus": "fortress_hp", "amount": 40.0}]},
	]

func get_template(template_id: String) -> Dictionary:
	for t in get_catalog():
		if String(t["template_id"]) == template_id:
			return t
	return {}

func get_progress_stage() -> int:
	## Highest stage the player has access to (cleared + 1 track).
	return maxi(1, current_stage)

func is_gear_unlocked(template: Dictionary) -> bool:
	return get_progress_stage() >= int(template.get("min_stage", 1))

func rarity_border_color(rarity: String) -> Color:
	match String(rarity):
		"legendary":
			return Color(1.0, 0.75, 0.15)
		"epic":
			return Color(0.85, 0.4, 1.0)
		"rare":
			return Color(0.35, 0.85, 1.0)
		_:
			return Color(0.25, 0.7, 0.9, 0.85)

func rarity_drop_weight(rarity: String, stage: int) -> float:
	## Higher stages unlock better loot, but high tiers stay scarce.
	var w := 0.0
	match String(rarity):
		"legendary":
			if stage < 7:
				return 0.0
			w = clampf(0.012 + float(stage - 7) * 0.008, 0.012, 0.06)
		"epic":
			if stage < 4:
				return 0.0
			w = clampf(0.04 + float(stage - 4) * 0.015, 0.04, 0.14)
		"rare":
			if stage < 2:
				w = 0.08
			else:
				w = clampf(0.18 + float(stage - 2) * 0.025, 0.18, 0.32)
		_:
			return 1.0
	var luck: float = float(get_skill_bonuses().get("loot_luck", 0.0))
	return w * (1.0 + luck)

func add_item_from_template(template_id: String) -> Dictionary:
	var t: Dictionary = get_template(template_id)
	if t.is_empty():
		return {}
	var c: Color = t.get("color", Color.WHITE)
	var mods: Array = get_template_mods(t)
	var item := {
		"uid": "g%d" % _uid_counter,
		"template_id": template_id,
		"name": String(t["name"]),
		"slot": String(t["slot"]),
		"mods": mods.duplicate(true),
		"bonus": String(mods[0]["bonus"]) if mods.size() > 0 else "damage",
		"amount": float(mods[0]["amount"]) if mods.size() > 0 else 0.0,
		"color_r": c.r,
		"color_g": c.g,
		"color_b": c.b,
		"rarity": String(t.get("rarity", "common"))
	}
	_uid_counter += 1
	inventory.append(item)
	inventory_changed.emit()
	save_data()
	return item

func get_template_mods(template: Dictionary) -> Array:
	if template.is_empty():
		return []
	if template.has("mods") and template["mods"] is Array and not (template["mods"] as Array).is_empty():
		return (template["mods"] as Array).duplicate(true)
	# Legacy single-bonus templates
	if template.has("bonus"):
		return [{"bonus": String(template["bonus"]), "amount": float(template.get("amount", 0.0))}]
	return []

func get_item_mods(item: Dictionary) -> Array:
	if item.is_empty():
		return []
	if item.has("mods") and item["mods"] is Array and not (item["mods"] as Array).is_empty():
		return item["mods"] as Array
	if item.has("bonus"):
		return [{"bonus": String(item["bonus"]), "amount": float(item.get("amount", 0.0))}]
	return get_template_mods(get_template(String(item.get("template_id", ""))))

func roll_level_drop(level_number: int, rng: RandomNumberGenerator) -> Dictionary:
	var stage: int = maxi(1, level_number)
	var catalog: Array = get_catalog()

	# Roll rarity first (legendary/epic stay rare even late)
	var roll := rng.randf()
	var target_rarity := "common"
	var leg_w := rarity_drop_weight("legendary", stage)
	var epi_w := rarity_drop_weight("epic", stage)
	var rar_w := rarity_drop_weight("rare", stage)
	if roll < leg_w:
		target_rarity = "legendary"
	elif roll < leg_w + epi_w:
		target_rarity = "epic"
	elif roll < leg_w + epi_w + rar_w:
		target_rarity = "rare"

	var pool: Array = []
	for t in catalog:
		if String(t["template_id"]) == "weapon_pulse":
			continue # starter only
		if int(t.get("min_stage", 1)) > stage:
			continue
		if String(t.get("rarity", "common")) != target_rarity:
			continue
		pool.append(t)

	# Fallback down the rarity ladder if empty
	if pool.is_empty():
		for fallback in ["epic", "rare", "common"]:
			for t in catalog:
				if String(t["template_id"]) == "weapon_pulse":
					continue
				if int(t.get("min_stage", 1)) > stage:
					continue
				if String(t.get("rarity", "common")) == fallback:
					pool.append(t)
			if not pool.is_empty():
				break

	if pool.is_empty():
		return add_item_from_template("helmet_neural")

	var pick: Dictionary = pool[rng.randi() % pool.size()]
	return add_item_from_template(String(pick["template_id"]))

func find_item(uid: String) -> Dictionary:
	for item in inventory:
		if String(item.get("uid", "")) == uid:
			return item
	return {}

func equip_uid(uid: String) -> bool:
	var item: Dictionary = find_item(uid)
	if item.is_empty():
		return false
	var slot: String = String(item["slot"])
	# Ring1/Ring2: allow either ring slot if template says Ring1 - map necklace etc.
	if slot == "Ring1" or slot == "Ring2":
		# Prefer empty ring slot, else overwrite matching template slot
		if equipped.get("Ring1", "") == "":
			slot = "Ring1"
		elif equipped.get("Ring2", "") == "":
			slot = "Ring2"
		else:
			slot = String(item["slot"])
	equipped[slot] = uid
	equipment_changed.emit()
	save_data()
	return true

func unequip_slot(slot_name: String) -> void:
	if not equipped.has(slot_name):
		return
	equipped[slot_name] = ""
	equipment_changed.emit()
	save_data()

func get_equipped_item(slot_name: String) -> Dictionary:
	var uid: String = String(equipped.get(slot_name, ""))
	if uid == "":
		return {}
	return find_item(uid)

func get_equipped_bonuses() -> Dictionary:
	var out := {
		"damage": 0.0,
		"fire_rate": 0.0,
		"speed": 0.0,
		"tower_damage": 0.0,
		"cooldown": 0.0,
		"fortress_hp": 0,
		"fork": 0,
		"pierce": 0,
		"projectiles": 0,
		"burn": 0,
		"meteor_slow": 0.0,
		"leak_resist": 0.0
	}
	for slot_name in SLOT_NAMES:
		var item: Dictionary = get_equipped_item(slot_name)
		if item.is_empty():
			continue
		_accumulate_mods(out, get_item_mods(item))
	# Soft caps so stacked multi-mod loadouts stay sane
	out["meteor_slow"] = clampf(float(out["meteor_slow"]), 0.0, 0.45)
	out["leak_resist"] = clampf(float(out["leak_resist"]), 0.0, 0.50)
	out["cooldown"] = clampf(float(out["cooldown"]), 0.0, 0.70)
	return out

func _accumulate_mods(out: Dictionary, mods: Array) -> void:
	for mod in mods:
		if typeof(mod) != TYPE_DICTIONARY:
			continue
		var bonus := String(mod.get("bonus", ""))
		if bonus == "" or not out.has(bonus):
			continue
		if bonus in INT_BONUSES:
			out[bonus] = int(out[bonus]) + int(mod.get("amount", 0))
		else:
			out[bonus] = float(out[bonus]) + float(mod.get("amount", 0.0))

func item_color(item: Dictionary) -> Color:
	return Color(float(item.get("color_r", 1.0)), float(item.get("color_g", 1.0)), float(item.get("color_b", 1.0)))

func get_slot_icon_path(slot: String) -> String:
	return String(SLOT_ICONS.get(slot, ""))

func get_item_icon_path(item: Dictionary) -> String:
	if item.is_empty():
		return ""
	return get_slot_icon_path(String(item.get("slot", "")))

## Load image from disk — bypasses broken/missing Godot import cache.
func load_png_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	var fs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(fs_path):
		push_warning("Texture file missing: %s" % fs_path)
		return null
	var cache_key := "%s:%d" % [path, FileAccess.get_modified_time(fs_path)]
	if _tex_cache.has(cache_key):
		return _tex_cache[cache_key]
	var img := _load_image_from_path(fs_path)
	if img == null:
		push_warning("Texture decode failed: %s" % fs_path)
		return null
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[cache_key] = tex
	return tex

func _load_image_from_path(fs_path: String) -> Image:
	var file := FileAccess.open(fs_path, FileAccess.READ)
	if file == null:
		return null
	var data: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	if data.is_empty():
		return null

	var img := Image.new()
	var err := FAILED
	if data.size() >= 8 and data[0] == 0x89 and data[1] == 0x50 and data[2] == 0x4E and data[3] == 0x47:
		err = img.load_png_from_buffer(data)
	elif data.size() >= 2 and data[0] == 0xFF and data[1] == 0xD8:
		err = img.load_jpg_from_buffer(data)
	elif data.size() >= 12 and data.slice(0, 4).get_string_from_ascii() == "RIFF" and data.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(data)
	else:
		err = img.load(fs_path)
	if err != OK:
		return null
	return img

func load_slot_texture(slot: String) -> Texture2D:
	return load_png_texture(get_slot_icon_path(slot))

func make_gear_icon(slot: String, size: Vector2 = Vector2(64, 64), equipped_item: Dictionary = {}) -> Control:
	## Square gear portrait for UI lists / paper-doll overlays.
	var icon_slot := slot
	if not equipped_item.is_empty():
		icon_slot = String(equipped_item.get("slot", slot))
	var panel := PanelContainer.new()
	panel.custom_minimum_size = size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.1, 0.92)
	style.set_corner_radius_all(6)
	style.set_border_width_all(2)
	if not equipped_item.is_empty():
		style.border_color = rarity_border_color(String(equipped_item.get("rarity", "common")))
	else:
		style.border_color = Color(0.25, 0.7, 0.9, 0.85)
	panel.add_theme_stylebox_override("panel", style)

	var tex := TextureRect.new()
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.offset_left = 3
	tex.offset_top = 3
	tex.offset_right = -3
	tex.offset_bottom = -3
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var icon_tex := load_slot_texture(icon_slot)
	if icon_tex != null:
		tex.texture = icon_tex
	panel.add_child(tex)
	return panel

func format_bonus(bonus: String, amount: float) -> String:
	match bonus:
		"damage":
			return "+%d%% Damage" % int(round(amount * 100.0))
		"fire_rate":
			return "+%d%% Fire Rate" % int(round(amount * 100.0))
		"speed":
			return "+%d%% Move Speed" % int(round(amount * 100.0))
		"tower_damage":
			return "+%d%% Tower Damage" % int(round(amount * 100.0))
		"cooldown":
			return "-%d%% Skill Cooldown" % int(round(amount * 100.0))
		"fortress_hp":
			return "+%d Fortress HP" % int(amount)
		"fork":
			return "Fork into %d" % int(amount)
		"pierce":
			return "+%d Pierce" % int(amount)
		"projectiles":
			return "+%d Projectile" % int(amount) if int(amount) == 1 else "+%d Projectiles" % int(amount)
		"burn":
			return "Bullets apply Burn" if amount > 0.0 else ""
		"meteor_slow":
			return "Meteors -%d%% Speed" % int(round(amount * 100.0))
		"leak_resist":
			return "-%d%% Leak Damage" % int(round(amount * 100.0))
		_:
			return "%s +%s" % [bonus, str(amount)]

func format_item_stats(item: Dictionary) -> String:
	if item.is_empty():
		return ""
	return format_mods_list(get_item_mods(item))

func format_template_stats(template: Dictionary) -> String:
	if template.is_empty():
		return ""
	return format_mods_list(get_template_mods(template))

func format_mods_list(mods: Array, separator: String = " · ") -> String:
	var lines: PackedStringArray = []
	for mod in mods:
		if typeof(mod) != TYPE_DICTIONARY:
			continue
		var line := format_bonus(String(mod.get("bonus", "")), float(mod.get("amount", 0.0)))
		if line != "":
			lines.append(line)
	return separator.join(lines)

func get_shop_price(template: Dictionary) -> int:
	match String(template.get("rarity", "common")):
		"legendary":
			return 2200
		"epic":
			return 950
		"rare":
			return 400
		_:
			return 150

func get_item_shop_price(item: Dictionary) -> int:
	var t: Dictionary = get_template(String(item.get("template_id", "")))
	if t.is_empty():
		# Fallback by rarity on the item itself
		t = {"rarity": String(item.get("rarity", "common"))}
	return get_shop_price(t)

func get_sell_price(item: Dictionary) -> int:
	return maxi(1, int(round(float(get_item_shop_price(item)) * 0.1)))

func try_sell_uid(uid: String) -> Dictionary:
	var item: Dictionary = find_item(uid)
	if item.is_empty():
		return {"ok": false, "error": "Item not found"}
	var price: int = get_sell_price(item)
	# Unequip if worn
	for s in SLOT_NAMES:
		if String(equipped.get(s, "")) == uid:
			equipped[s] = ""
			equipment_changed.emit()
			break
	# Remove from inventory
	var kept: Array = []
	for it in inventory:
		if String(it.get("uid", "")) != uid:
			kept.append(it)
	inventory = kept
	inventory_changed.emit()
	coins += price
	coins_changed.emit(coins)
	save_data()
	return {
		"ok": true,
		"price": price,
		"name": String(item.get("name", "Gear")),
		"coins": coins
	}

func try_buy_template(template_id: String) -> Dictionary:
	var t: Dictionary = get_template(template_id)
	if t.is_empty():
		return {"ok": false, "error": "Unknown item"}
	if not is_gear_unlocked(t):
		return {"ok": false, "error": "Reach stage %d to unlock" % int(t.get("min_stage", 1))}
	var price: int = get_shop_price(t)
	if coins < price:
		return {"ok": false, "error": "Not enough coins", "price": price}
	coins -= price
	coins_changed.emit(coins)
	var item: Dictionary = add_item_from_template(template_id)
	save_data()
	return {"ok": true, "item": item, "price": price, "coins": coins}

func get_equipped_stats_summary() -> String:
	var b: Dictionary = get_equipped_bonuses()
	var lines: PackedStringArray = []
	for key in ["damage", "fire_rate", "speed", "tower_damage", "cooldown", "fortress_hp", "fork", "pierce", "projectiles", "burn", "meteor_slow", "leak_resist"]:
		if key in INT_BONUSES:
			if int(b.get(key, 0)) > 0:
				lines.append(format_bonus(key, float(b[key])))
		else:
			if float(b.get(key, 0.0)) > 0.0:
				lines.append(format_bonus(key, float(b[key])))
	if lines.is_empty():
		return "No bonuses equipped"
	return "\n".join(lines)

## Every 5th stage is a hard boss stage with a mega boss and doubled rewards.
const BOSS_STAGE_INTERVAL := 5

## Zone names for normal stages (cycled, boss slots skipped).
const STAGE_ZONE_NAMES := [
	"Ashfall Perimeter", "Shattered Belt", "Ember Fields", "Ion Wastes",
	"Cinder Reach", "Static Verge", "Halo Scrapline", "Dust Corridor",
	"Umbra Flats", "Pale Meridian", "Void Terraces", "Sunken Relay",
	"Glass Steppe", "Aurora Graveyard", "Redshift Basin", "Silent Expanse",
]

## Titles for boss stages (stage 5, 10, 15, ... cycled).
const BOSS_STAGE_NAMES := [
	"The Iron Carrier", "Wrath of the Belt", "The Obsidian Titan",
	"Herald of Ruin", "The Star Devourer", "Avatar of Collapse",
	"The Endless Maw", "Crown of Extinction",
]

func is_boss_stage(stage: int) -> bool:
	return stage >= BOSS_STAGE_INTERVAL and stage % BOSS_STAGE_INTERVAL == 0

func get_stage_name(stage: int) -> String:
	var s: int = maxi(1, stage)
	if is_boss_stage(s):
		var bi: int = (s / BOSS_STAGE_INTERVAL) - 1
		return BOSS_STAGE_NAMES[bi % BOSS_STAGE_NAMES.size()]
	var zi: int = s - 1 - (s / BOSS_STAGE_INTERVAL)
	return STAGE_ZONE_NAMES[zi % STAGE_ZONE_NAMES.size()]

func get_stage_title(stage: int) -> String:
	var s: int = maxi(1, stage)
	if is_boss_stage(s):
		return "Stage %d — %s [BOSS]" % [s, get_stage_name(s)]
	return "Stage %d — %s" % [s, get_stage_name(s)]

func get_clear_coin_reward(stage: int) -> int:
	var s: int = maxi(1, stage)
	var base: int = 100 * s + 50 * s * (s - 1)
	if is_boss_stage(s):
		base *= 2
	var coin_bonus: float = float(get_skill_bonuses().get("coin_bonus", 0.0))
	return int(round(float(base) * (1.0 + coin_bonus)))

func get_max_playable_stage() -> int:
	return maxi(1, current_stage)

func clamp_selected_stage() -> void:
	selected_stage = clampi(selected_stage, 1, get_max_playable_stage())

func set_selected_stage(stage: int) -> void:
	selected_stage = clampi(stage, 1, get_max_playable_stage())

func get_stage_reward_preview(stage: int = -1) -> Dictionary:
	var s: int = selected_stage if stage < 1 else stage
	s = clampi(s, 1, get_max_playable_stage())
	var is_replay: bool = s < current_stage
	var boss: bool = is_boss_stage(s)
	var gear_text := "2 gear pieces" if boss else "1 random gear piece"
	var summary := "%s: %d coins + %s%s" % [
		"BOSS STAGE rewards" if boss else "Stage %d rewards" % s,
		get_clear_coin_reward(s),
		gear_text,
		" (replay)" if is_replay else ""
	]
	return {
		"stage": s,
		"coins": get_clear_coin_reward(s),
		"gear": gear_text,
		"is_boss": boss,
		"is_replay": is_replay,
		"summary": summary
	}

func add_coins(amount: int) -> void:
	if amount == 0:
		return
	coins = maxi(0, coins + amount)
	coins_changed.emit(coins)
	save_data()

func mark_level_cleared(wave: int, stage_played: int = -1) -> void:
	levels_cleared += 1
	if wave > highest_wave:
		highest_wave = wave
	var played: int = current_stage if stage_played < 1 else stage_played
	# Only unlock the next stage when clearing your newest stage
	if played >= current_stage:
		current_stage = played + 1
	selected_stage = clampi(selected_stage, 1, get_max_playable_stage())
	save_data()

# ---------------------------------------------------------------------------
# Character level + skill tree
# ---------------------------------------------------------------------------

func get_skill_nodes() -> Array:
	if not _skill_nodes_cache.is_empty():
		return _skill_nodes_cache
	_skill_nodes_cache = _build_skill_nodes()
	_skill_node_map.clear()
	for n in _skill_nodes_cache:
		_skill_node_map[String(n["id"])] = n
	return _skill_nodes_cache

func _build_skill_nodes() -> Array:
	## Path-of-Exile style: CORE center, three spokes, side clusters.
	var nodes: Array = [
		{"id": "core", "name": "CORE", "branch": "core", "requires": "", "cost": 0,
			"desc": "Starting node. Follow spokes outward or branch into clusters.",
			"x": 0.50, "y": 0.50, "bonuses": {}, "keystone": true},
	]
	# Weapon — north spoke
	var weapon := [
		{"id": "w1", "name": "CALIBER I", "requires": "core", "desc": "+4% Weapon Damage", "bonuses": {"weapon_damage": 0.04}},
		{"id": "w2", "name": "TRIGGER I", "requires": "w1", "desc": "+4% Fire Rate", "bonuses": {"weapon_fire_rate": 0.04}},
		{"id": "w3", "name": "CALIBER II", "requires": "w2", "desc": "+5% Weapon Damage", "bonuses": {"weapon_damage": 0.05}},
		{"id": "w4", "name": "TRIGGER II", "requires": "w3", "desc": "+5% Fire Rate", "bonuses": {"weapon_fire_rate": 0.05}},
		{"id": "w5", "name": "CALIBER III", "requires": "w4", "desc": "+5% Weapon Damage", "bonuses": {"weapon_damage": 0.05}},
		{"id": "w6", "name": "FOCUS", "requires": "w5", "desc": "+5% Fire Rate", "bonuses": {"weapon_fire_rate": 0.05}},
		{"id": "w7", "name": "CALIBER IV", "requires": "w6", "desc": "+6% Weapon Damage", "bonuses": {"weapon_damage": 0.06}},
		{"id": "w8", "name": "PIERCER", "requires": "w7", "desc": "+1 Bullet Pierce", "bonuses": {"pierce": 1}},
		{"id": "w9", "name": "CALIBER V", "requires": "w8", "desc": "+6% Weapon Damage", "bonuses": {"weapon_damage": 0.06}},
		{"id": "w10", "name": "OVERKILL", "requires": "w9", "desc": "+8% Weapon Damage, +1 Projectile", "bonuses": {"weapon_damage": 0.08, "projectiles": 1}},
		{"id": "w11", "name": "CALIBER VI", "requires": "w10", "desc": "+5% Weapon Damage", "bonuses": {"weapon_damage": 0.05}},
		{"id": "w12", "name": "TRIGGER III", "requires": "w11", "desc": "+5% Fire Rate", "bonuses": {"weapon_fire_rate": 0.05}},
		{"id": "w13", "name": "VOLLEY", "requires": "w12", "desc": "+1 Projectile", "bonuses": {"projectiles": 1}},
		{"id": "w14", "name": "CALIBER VII", "requires": "w13", "desc": "+7% Weapon Damage", "bonuses": {"weapon_damage": 0.07}},
		{"id": "w15", "name": "DEVASTATOR", "requires": "w14", "desc": "+10% Weapon Damage, +1 Pierce", "bonuses": {"weapon_damage": 0.10, "pierce": 1}, "keystone": true},
		{"id": "w16", "name": "CALIBER VIII", "requires": "w15", "desc": "+6% Weapon Damage", "bonuses": {"weapon_damage": 0.06}},
		{"id": "w17", "name": "TRIGGER IV", "requires": "w16", "desc": "+6% Fire Rate", "bonuses": {"weapon_fire_rate": 0.06}},
		{"id": "w18", "name": "CALIBER IX", "requires": "w17", "desc": "+7% Weapon Damage", "bonuses": {"weapon_damage": 0.07}},
		{"id": "w19", "name": "BARRAGE", "requires": "w18", "desc": "+1 Projectile", "bonuses": {"projectiles": 1}},
		{"id": "w20", "name": "ANNIHILATOR", "requires": "w19", "desc": "+12% Weapon Damage, +1 Pierce", "bonuses": {"weapon_damage": 0.12, "pierce": 1}, "keystone": true},
	]
	_append_radial_branch(nodes, weapon, "weapon", -90.0, 1)
	_place_cluster(nodes, "w4", "weapon", "Rapid Fire", 1.0, [
		{"id": "wf1", "name": "QUICK I", "requires": "w4", "desc": "+3% Fire Rate", "bonuses": {"weapon_fire_rate": 0.03}},
		{"id": "wf2", "name": "QUICK II", "requires": "wf1", "desc": "+4% Fire Rate", "bonuses": {"weapon_fire_rate": 0.04}},
		{"id": "wf3", "name": "QUICK III", "requires": "wf2", "desc": "+5% Fire Rate", "bonuses": {"weapon_fire_rate": 0.05}},
		{"id": "wf4", "name": "GATLING", "requires": "wf3", "desc": "+6% Fire Rate", "bonuses": {"weapon_fire_rate": 0.06}, "keystone": true},
	], 1)
	_place_cluster(nodes, "w9", "weapon", "Armor Pierce", -1.0, [
		{"id": "wp1", "name": "DRILL I", "requires": "w9", "desc": "+1 Bullet Pierce", "bonuses": {"pierce": 1}},
		{"id": "wp2", "name": "DRILL II", "requires": "wp1", "desc": "+4% Weapon Damage", "bonuses": {"weapon_damage": 0.04}},
		{"id": "wp3", "name": "DRILL III", "requires": "wp2", "desc": "+1 Bullet Pierce", "bonuses": {"pierce": 1}},
		{"id": "wp4", "name": "AP ROUNDS", "requires": "wp3", "desc": "+1 Pierce, +6% Weapon Damage", "bonuses": {"pierce": 1, "weapon_damage": 0.06}, "keystone": true},
	], 1)
	_place_cluster(nodes, "w15", "weapon", "Salvo", 1.0, [
		{"id": "ws1", "name": "SPLIT I", "requires": "w15", "desc": "+1 Projectile", "bonuses": {"projectiles": 1}},
		{"id": "ws2", "name": "SPLIT II", "requires": "ws1", "desc": "+5% Weapon Damage", "bonuses": {"weapon_damage": 0.05}},
		{"id": "ws3", "name": "SPLIT III", "requires": "ws2", "desc": "+1 Projectile", "bonuses": {"projectiles": 1}},
		{"id": "ws4", "name": "STORM", "requires": "ws3", "desc": "+1 Projectile, +8% Weapon Damage", "bonuses": {"projectiles": 1, "weapon_damage": 0.08}, "keystone": true},
	], 1)
	# Tower — southeast spoke
	var tower := [
		{"id": "r1", "name": "LINK I", "requires": "core", "desc": "+5% Tower Damage", "bonuses": {"tower_damage": 0.05}},
		{"id": "r2", "name": "COOLANT I", "requires": "r1", "desc": "+4% Tower Fire Rate", "bonuses": {"tower_fire_rate": 0.04}},
		{"id": "r3", "name": "LINK II", "requires": "r2", "desc": "+5% Tower Damage", "bonuses": {"tower_damage": 0.05}},
		{"id": "r4", "name": "COOLANT II", "requires": "r3", "desc": "+4% Tower Fire Rate", "bonuses": {"tower_fire_rate": 0.04}},
		{"id": "r5", "name": "LINK III", "requires": "r4", "desc": "+6% Tower Damage", "bonuses": {"tower_damage": 0.06}},
		{"id": "r6", "name": "PLATING I", "requires": "r5", "desc": "+40 Fortress HP", "bonuses": {"fortress_hp": 40}},
		{"id": "r7", "name": "LINK IV", "requires": "r6", "desc": "+6% Tower Damage", "bonuses": {"tower_damage": 0.06}},
		{"id": "r8", "name": "PLATING II", "requires": "r7", "desc": "+50 Fortress HP", "bonuses": {"fortress_hp": 50}},
		{"id": "r9", "name": "LINK V", "requires": "r8", "desc": "+7% Tower Damage", "bonuses": {"tower_damage": 0.07}},
		{"id": "r10", "name": "ARTILLERY", "requires": "r9", "desc": "+8% Tower Damage, +5% Tower Fire Rate", "bonuses": {"tower_damage": 0.08, "tower_fire_rate": 0.05}},
		{"id": "r11", "name": "COOLANT III", "requires": "r10", "desc": "+5% Tower Fire Rate", "bonuses": {"tower_fire_rate": 0.05}},
		{"id": "r12", "name": "PLATING III", "requires": "r11", "desc": "+60 Fortress HP", "bonuses": {"fortress_hp": 60}},
		{"id": "r13", "name": "LINK VI", "requires": "r12", "desc": "+7% Tower Damage", "bonuses": {"tower_damage": 0.07}},
		{"id": "r14", "name": "COOLANT IV", "requires": "r13", "desc": "+5% Tower Fire Rate", "bonuses": {"tower_fire_rate": 0.05}},
		{"id": "r15", "name": "CITADEL", "requires": "r14", "desc": "+10% Tower Damage, +80 Fortress HP", "bonuses": {"tower_damage": 0.10, "fortress_hp": 80}, "keystone": true},
		{"id": "r16", "name": "LINK VII", "requires": "r15", "desc": "+6% Tower Damage", "bonuses": {"tower_damage": 0.06}},
		{"id": "r17", "name": "COOLANT V", "requires": "r16", "desc": "+6% Tower Fire Rate", "bonuses": {"tower_fire_rate": 0.06}},
		{"id": "r18", "name": "PLATING IV", "requires": "r17", "desc": "+70 Fortress HP", "bonuses": {"fortress_hp": 70}},
		{"id": "r19", "name": "LINK VIII", "requires": "r18", "desc": "+8% Tower Damage", "bonuses": {"tower_damage": 0.08}},
		{"id": "r20", "name": "FORTRESS", "requires": "r19", "desc": "+12% Tower Damage, +100 Fortress HP", "bonuses": {"tower_damage": 0.12, "fortress_hp": 100}, "keystone": true},
	]
	_append_radial_branch(nodes, tower, "tower", 30.0, 1)
	_place_cluster(nodes, "r5", "tower", "Overcharge", -1.0, [
		{"id": "rt1", "name": "SPIN I", "requires": "r5", "desc": "+3% Tower Fire Rate", "bonuses": {"tower_fire_rate": 0.03}},
		{"id": "rt2", "name": "SPIN II", "requires": "rt1", "desc": "+4% Tower Fire Rate", "bonuses": {"tower_fire_rate": 0.04}},
		{"id": "rt3", "name": "SPIN III", "requires": "rt2", "desc": "+5% Tower Fire Rate", "bonuses": {"tower_fire_rate": 0.05}},
		{"id": "rt4", "name": "TURBO", "requires": "rt3", "desc": "+6% Tower Fire Rate, +4% Tower Damage", "bonuses": {"tower_fire_rate": 0.06, "tower_damage": 0.04}, "keystone": true},
	], 1)
	_place_cluster(nodes, "r10", "tower", "Bulwark", 1.0, [
		{"id": "rh1", "name": "WALL I", "requires": "r10", "desc": "+35 Fortress HP", "bonuses": {"fortress_hp": 35}},
		{"id": "rh2", "name": "WALL II", "requires": "rh1", "desc": "+40 Fortress HP", "bonuses": {"fortress_hp": 40}},
		{"id": "rh3", "name": "WALL III", "requires": "rh2", "desc": "+45 Fortress HP", "bonuses": {"fortress_hp": 45}},
		{"id": "rh4", "name": "RAMPART", "requires": "rh3", "desc": "+60 Fortress HP, +5% Tower Damage", "bonuses": {"fortress_hp": 60, "tower_damage": 0.05}, "keystone": true},
	], 1)
	_place_cluster(nodes, "r16", "tower", "Siege", -1.0, [
		{"id": "rs1", "name": "SIEGE I", "requires": "r16", "desc": "+5% Tower Damage", "bonuses": {"tower_damage": 0.05}},
		{"id": "rs2", "name": "SIEGE II", "requires": "rs1", "desc": "+6% Tower Damage", "bonuses": {"tower_damage": 0.06}},
		{"id": "rs3", "name": "SIEGE III", "requires": "rs2", "desc": "+7% Tower Damage", "bonuses": {"tower_damage": 0.07}},
		{"id": "rs4", "name": "BOMBARD", "requires": "rs3", "desc": "+8% Tower Damage, +4% Tower Fire Rate", "bonuses": {"tower_damage": 0.08, "tower_fire_rate": 0.04}, "keystone": true},
	], 1)
	# Loot — southwest spoke
	var loot := [
		{"id": "l1", "name": "SCAVENGER I", "requires": "core", "desc": "+6% Stage Coins", "bonuses": {"coin_bonus": 0.06}},
		{"id": "l2", "name": "FORTUNE I", "requires": "l1", "desc": "+6% Loot Luck", "bonuses": {"loot_luck": 0.06}},
		{"id": "l3", "name": "SCAVENGER II", "requires": "l2", "desc": "+7% Stage Coins", "bonuses": {"coin_bonus": 0.07}},
		{"id": "l4", "name": "FORTUNE II", "requires": "l3", "desc": "+7% Loot Luck", "bonuses": {"loot_luck": 0.07}},
		{"id": "l5", "name": "SCAVENGER III", "requires": "l4", "desc": "+8% Stage Coins", "bonuses": {"coin_bonus": 0.08}},
		{"id": "l6", "name": "FORTUNE III", "requires": "l5", "desc": "+8% Loot Luck", "bonuses": {"loot_luck": 0.08}},
		{"id": "l7", "name": "HAUL", "requires": "l6", "desc": "+8% Stage Coins", "bonuses": {"coin_bonus": 0.08}},
		{"id": "l8", "name": "LUCKY FIND", "requires": "l7", "desc": "8% chance for bonus gear drop", "bonuses": {"extra_loot_chance": 0.08}},
		{"id": "l9", "name": "FORTUNE IV", "requires": "l8", "desc": "+10% Loot Luck", "bonuses": {"loot_luck": 0.10}},
		{"id": "l10", "name": "TYCOON", "requires": "l9", "desc": "+10% Coins, +8% Extra Loot Chance", "bonuses": {"coin_bonus": 0.10, "extra_loot_chance": 0.08}},
		{"id": "l11", "name": "SCAVENGER IV", "requires": "l10", "desc": "+9% Stage Coins", "bonuses": {"coin_bonus": 0.09}},
		{"id": "l12", "name": "FORTUNE V", "requires": "l11", "desc": "+9% Loot Luck", "bonuses": {"loot_luck": 0.09}},
		{"id": "l13", "name": "GOLD RUSH", "requires": "l12", "desc": "+10% Stage Coins", "bonuses": {"coin_bonus": 0.10}},
		{"id": "l14", "name": "TREASURE HUNT", "requires": "l13", "desc": "+10% Extra Loot Chance", "bonuses": {"extra_loot_chance": 0.10}},
		{"id": "l15", "name": "MOGUL", "requires": "l14", "desc": "+12% Coins, +12% Loot Luck", "bonuses": {"coin_bonus": 0.12, "loot_luck": 0.12}, "keystone": true},
		{"id": "l16", "name": "SCAVENGER V", "requires": "l15", "desc": "+8% Stage Coins", "bonuses": {"coin_bonus": 0.08}},
		{"id": "l17", "name": "FORTUNE VI", "requires": "l16", "desc": "+8% Loot Luck", "bonuses": {"loot_luck": 0.08}},
		{"id": "l18", "name": "GILDED", "requires": "l17", "desc": "+10% Extra Loot Chance", "bonuses": {"extra_loot_chance": 0.10}},
		{"id": "l19", "name": "SCAVENGER VI", "requires": "l18", "desc": "+10% Stage Coins", "bonuses": {"coin_bonus": 0.10}},
		{"id": "l20", "name": "EMPEROR", "requires": "l19", "desc": "+15% Coins, +15% Loot Luck", "bonuses": {"coin_bonus": 0.15, "loot_luck": 0.15}, "keystone": true},
	]
	_append_radial_branch(nodes, loot, "loot", 150.0, 1)
	_place_cluster(nodes, "l5", "loot", "Hoarder", 1.0, [
		{"id": "lh1", "name": "COIN I", "requires": "l5", "desc": "+5% Stage Coins", "bonuses": {"coin_bonus": 0.05}},
		{"id": "lh2", "name": "COIN II", "requires": "lh1", "desc": "+6% Stage Coins", "bonuses": {"coin_bonus": 0.06}},
		{"id": "lh3", "name": "COIN III", "requires": "lh2", "desc": "+7% Stage Coins", "bonuses": {"coin_bonus": 0.07}},
		{"id": "lh4", "name": "VAULT", "requires": "lh3", "desc": "+8% Coins, +5% Loot Luck", "bonuses": {"coin_bonus": 0.08, "loot_luck": 0.05}, "keystone": true},
	], 1)
	_place_cluster(nodes, "l10", "loot", "Gilded", -1.0, [
		{"id": "lg1", "name": "LUCK I", "requires": "l10", "desc": "+5% Loot Luck", "bonuses": {"loot_luck": 0.05}},
		{"id": "lg2", "name": "LUCK II", "requires": "lg1", "desc": "+6% Extra Loot Chance", "bonuses": {"extra_loot_chance": 0.06}},
		{"id": "lg3", "name": "LUCK III", "requires": "lg2", "desc": "+7% Loot Luck", "bonuses": {"loot_luck": 0.07}},
		{"id": "lg4", "name": "JACKPOT", "requires": "lg3", "desc": "+10% Loot Luck, +8% Extra Loot", "bonuses": {"loot_luck": 0.10, "extra_loot_chance": 0.08}, "keystone": true},
	], 1)
	_place_cluster(nodes, "l16", "loot", "Magnate", 1.0, [
		{"id": "lm1", "name": "DEAL I", "requires": "l16", "desc": "+6% Coins, +4% Loot Luck", "bonuses": {"coin_bonus": 0.06, "loot_luck": 0.04}},
		{"id": "lm2", "name": "DEAL II", "requires": "lm1", "desc": "+7% Coins, +5% Loot Luck", "bonuses": {"coin_bonus": 0.07, "loot_luck": 0.05}},
		{"id": "lm3", "name": "DEAL III", "requires": "lm2", "desc": "+8% Coins, +6% Extra Loot", "bonuses": {"coin_bonus": 0.08, "extra_loot_chance": 0.06}},
		{"id": "lm4", "name": "BARON", "requires": "lm3", "desc": "+10% Coins, +10% Loot Luck", "bonuses": {"coin_bonus": 0.10, "loot_luck": 0.10}, "keystone": true},
	], 1)
	_resolve_skill_layout(nodes)
	return nodes

func _append_radial_branch(out: Array, branch_nodes: Array, branch: String, base_angle_deg: float, cost: int) -> void:
	## Place nodes on a spoke with a slight PoE-style weave.
	const RING_STEP := 0.048
	for i in branch_nodes.size():
		var src: Dictionary = branch_nodes[i]
		var ring: float = 0.11 + float(i) * RING_STEP
		var weave: float = 0.0
		if i % 2 == 1:
			weave = 7.0
		elif i % 4 == 2:
			weave = -7.0
		var ang: float = deg_to_rad(base_angle_deg + weave)
		var node := {
			"id": String(src["id"]),
			"name": String(src["name"]),
			"branch": branch,
			"requires": String(src["requires"]),
			"cost": cost,
			"desc": String(src["desc"]),
			"x": 0.5 + cos(ang) * ring,
			"y": 0.5 + sin(ang) * ring,
			"bonuses": src.get("bonuses", {}),
			"keystone": bool(src.get("keystone", false))
		}
		out.append(node)

func _place_cluster(out: Array, anchor_id: String, branch: String, cluster_name: String, side_sign: float, cluster_nodes: Array, cost: int) -> void:
	## PoE-style cluster: hub offset sideways, satellites on outer arc away from the spoke.
	var anchor_pos := Vector2(-1, -1)
	for n in out:
		if String(n["id"]) == anchor_id:
			anchor_pos = Vector2(float(n["x"]), float(n["y"]))
			break
	if anchor_pos.x < 0.0:
		return
	var core := Vector2(0.5, 0.5)
	var outward := (anchor_pos - core).normalized()
	var tangent := Vector2(-outward.y, outward.x) * side_sign
	var cluster_id := cluster_name.to_lower().replace(" ", "_")
	const CLUSTER_OFFSET := 0.115
	const SATELLITE_RADIUS := 0.052
	var hub := anchor_pos + tangent * CLUSTER_OFFSET
	var count := cluster_nodes.size()
	var arc_center := tangent.normalized()
	var arc_half := deg_to_rad(24.0 if count <= 3 else 30.0)
	for i in count:
		var src: Dictionary = cluster_nodes[i]
		var t := 0.0 if count <= 1 else float(i) / float(count - 1)
		var ang := lerpf(-arc_half, arc_half, t)
		var dir := arc_center.rotated(ang)
		var pos := hub + dir * SATELLITE_RADIUS
		var is_notable := bool(src.get("keystone", false)) or i == count - 1
		out.append({
			"id": String(src["id"]),
			"name": String(src["name"]),
			"branch": branch,
			"requires": String(src["requires"]),
			"cost": cost,
			"desc": String(src["desc"]),
			"x": pos.x,
			"y": pos.y,
			"bonuses": src.get("bonuses", {}),
			"keystone": bool(src.get("keystone", false)),
			"cluster": cluster_id,
			"cluster_name": cluster_name if i == 0 else "",
			"cluster_hub_x": hub.x,
			"cluster_hub_y": hub.y,
			"cluster_notable": is_notable,
			"cluster_entry": i == 0,
		})

func _node_layout_radius(node: Dictionary) -> float:
	if String(node.get("id", "")) == "core" or bool(node.get("keystone", false)):
		return 0.022
	if bool(node.get("cluster_notable", false)):
		return 0.018
	if String(node.get("cluster", "")) != "":
		return 0.014
	return 0.016

func _resolve_skill_layout(nodes: Array) -> void:
	## Push overlapping nodes apart while keeping the core fixed.
	const PADDING := 0.006
	const MAX_ITERS := 24
	for _iter in MAX_ITERS:
		var moved := false
		for i in nodes.size():
			for j in range(i + 1, nodes.size()):
				var ni: Dictionary = nodes[i]
				var nj: Dictionary = nodes[j]
				var a := Vector2(float(ni["x"]), float(ni["y"]))
				var b := Vector2(float(nj["x"]), float(nj["y"]))
				var delta := b - a
				var dist := delta.length()
				var min_dist := _node_layout_radius(ni) + _node_layout_radius(nj) + PADDING
				if dist >= min_dist:
					continue
				var push := Vector2(0.02, 0.0) if dist < 0.0001 else delta.normalized() * (min_dist - dist)
				var ai := 1.0
				var aj := 1.0
				if String(ni.get("id", "")) == "core":
					ai = 0.0
					aj = 2.0
				elif String(nj.get("id", "")) == "core":
					ai = 2.0
					aj = 0.0
				elif ni.has("cluster") and not nj.has("cluster"):
					ai = 1.6
					aj = 0.4
				elif nj.has("cluster") and not ni.has("cluster"):
					ai = 0.4
					aj = 1.6
				var total := ai + aj
				if ai > 0.0:
					ni["x"] = float(ni["x"]) - push.x * (ai / total)
					ni["y"] = float(ni["y"]) - push.y * (ai / total)
				if aj > 0.0:
					nj["x"] = float(nj["x"]) + push.x * (aj / total)
					nj["y"] = float(nj["y"]) + push.y * (aj / total)
				moved = true
		if not moved:
			break
	_sync_cluster_hubs(nodes)

func _sync_cluster_hubs(nodes: Array) -> void:
	var hubs: Dictionary = {}
	for n in nodes:
		var cid := String(n.get("cluster", ""))
		if cid == "":
			continue
		if not hubs.has(cid):
			hubs[cid] = {"sum": Vector2.ZERO, "count": 0, "branch": String(n.get("branch", ""))}
		hubs[cid]["sum"] += Vector2(float(n["x"]), float(n["y"]))
		hubs[cid]["count"] += 1
	for n in nodes:
		var cid := String(n.get("cluster", ""))
		if cid == "" or not hubs.has(cid):
			continue
		var info: Dictionary = hubs[cid]
		if int(info["count"]) <= 0:
			continue
		var hub: Vector2 = info["sum"] / float(info["count"])
		n["cluster_hub_x"] = hub.x
		n["cluster_hub_y"] = hub.y

func get_skill_icon_path(node: Dictionary) -> String:
	## Map skill bonuses to uploaded skill_icons by filename.
	const ICON_DIR := "res://assets/png/skill_icons/"
	if node.is_empty():
		return ""
	if String(node.get("id", "")) == "core":
		return ICON_DIR + "Weapon_Damage.png"
	var b: Dictionary = node.get("bonuses", {})
	if b.has("pierce"):
		return ICON_DIR + "Pierce.png"
	if b.has("weapon_fire_rate") and not b.has("weapon_damage"):
		return ICON_DIR + "Fire_Rate.png"
	if b.has("weapon_damage") or b.has("projectiles"):
		return ICON_DIR + "Weapon_Damage.png"
	if b.has("tower_fire_rate") and not b.has("tower_damage"):
		return ICON_DIR + "Tower_Fire_Rate.png"
	if b.has("tower_damage"):
		return ICON_DIR + "Tower_Damage.png"
	if b.has("fortress_hp"):
		return ICON_DIR + "tower_fire_range.png"
	if b.has("coin_bonus") and not b.has("loot_luck"):
		return ICON_DIR + "Coins.png"
	if b.has("loot_luck") or b.has("extra_loot_chance"):
		return ICON_DIR + "Loot_Luck.png"
	if b.has("coin_bonus"):
		return ICON_DIR + "Coins.png"
	return ""

func get_skill_node(skill_id: String) -> Dictionary:
	if _skill_node_map.is_empty():
		get_skill_nodes()
	return _skill_node_map.get(skill_id, {})

func is_skill_unlocked(skill_id: String) -> bool:
	return skill_id in unlocked_skills

func can_unlock_skill(skill_id: String) -> bool:
	var n: Dictionary = get_skill_node(skill_id)
	if n.is_empty() or is_skill_unlocked(skill_id):
		return false
	var req: String = String(n.get("requires", ""))
	if req != "" and not is_skill_unlocked(req):
		return false
	var cost: int = int(n.get("cost", 1))
	return skill_points >= cost

func try_unlock_skill(skill_id: String) -> Dictionary:
	if skill_id == "core":
		if not is_skill_unlocked("core"):
			unlocked_skills.append("core")
			skill_tree_changed.emit()
			save_data()
		return {"ok": true}
	if not can_unlock_skill(skill_id):
		return {"ok": false, "error": "Locked or not enough skill points"}
	var n: Dictionary = get_skill_node(skill_id)
	var cost: int = int(n.get("cost", 1))
	skill_points -= cost
	unlocked_skills.append(skill_id)
	skill_tree_changed.emit()
	save_data()
	return {"ok": true, "id": skill_id}

func get_skill_bonuses() -> Dictionary:
	var out := {
		"weapon_damage": 0.0,
		"weapon_fire_rate": 0.0,
		"pierce": 0,
		"projectiles": 0,
		"tower_damage": 0.0,
		"tower_fire_rate": 0.0,
		"fortress_hp": 0,
		"coin_bonus": 0.0,
		"loot_luck": 0.0,
		"extra_loot_chance": 0.0,
	}
	for skill_id in unlocked_skills:
		var n: Dictionary = get_skill_node(String(skill_id))
		if n.is_empty():
			continue
		var b: Dictionary = n.get("bonuses", {})
		for k in b.keys():
			if typeof(out.get(k)) == TYPE_INT:
				out[k] = int(out[k]) + int(b[k])
			else:
				out[k] = float(out.get(k, 0.0)) + float(b[k])
	return out

func xp_for_level(level: int) -> int:
	## XP required to go from `level` to `level + 1` (easier than before, still climbs).
	match maxi(1, level):
		1:
			return 60
		2:
			return 140
		3:
			return 280
		4:
			return 500
		5:
			return 850
		6:
			return 1300
		7:
			return 2000
		8:
			return 3000
		_:
			return int(round(3000.0 * pow(1.7, float(level - 8))))

func get_kill_xp(is_boss: bool = false) -> int:
	## Slightly more XP at higher levels — gentle climb.
	var base: float = 55.0 if is_boss else 4.0
	var scale: float = 1.0 + float(maxi(0, char_level - 1)) * 0.1
	return maxi(1, int(round(base * scale)))

func add_char_xp(amount: int) -> void:
	if amount <= 0:
		return
	char_xp += amount
	var leveled := false
	while char_xp >= xp_for_level(char_level):
		char_xp -= xp_for_level(char_level)
		char_level += 1
		skill_points += SKILL_POINTS_PER_LEVEL
		leveled = true
		character_leveled.emit(char_level)
	if leveled:
		save_data()
		skill_tree_changed.emit()

func get_skill_summary() -> String:
	var b: Dictionary = get_skill_bonuses()
	var lines: PackedStringArray = []
	if float(b.weapon_damage) > 0.0:
		lines.append("+%d%% Weapon Damage" % int(round(float(b.weapon_damage) * 100.0)))
	if float(b.weapon_fire_rate) > 0.0:
		lines.append("+%d%% Fire Rate" % int(round(float(b.weapon_fire_rate) * 100.0)))
	if int(b.pierce) > 0:
		lines.append("+%d Pierce" % int(b.pierce))
	if int(b.projectiles) > 0:
		lines.append("+%d Projectiles" % int(b.projectiles))
	if float(b.tower_damage) > 0.0:
		lines.append("+%d%% Tower Damage" % int(round(float(b.tower_damage) * 100.0)))
	if float(b.tower_fire_rate) > 0.0:
		lines.append("+%d%% Tower Fire Rate" % int(round(float(b.tower_fire_rate) * 100.0)))
	if int(b.fortress_hp) > 0:
		lines.append("+%d Fortress HP" % int(b.fortress_hp))
	if float(b.coin_bonus) > 0.0:
		lines.append("+%d%% Coins" % int(round(float(b.coin_bonus) * 100.0)))
	if float(b.loot_luck) > 0.0:
		lines.append("+%d%% Loot Luck" % int(round(float(b.loot_luck) * 100.0)))
	if float(b.extra_loot_chance) > 0.0:
		lines.append("+%d%% Extra Loot Chance" % int(round(float(b.extra_loot_chance) * 100.0)))
	if lines.is_empty():
		return "No skills unlocked yet"
	return "\n".join(lines)

func save_data() -> void:
	var data := {
		"inventory": inventory,
		"equipped": equipped,
		"highest_wave": highest_wave,
		"levels_cleared": levels_cleared,
		"current_stage": current_stage,
		"selected_stage": selected_stage,
		"coins": coins,
		"uid_counter": _uid_counter,
		"char_level": char_level,
		"char_xp": char_xp,
		"skill_points": skill_points,
		"unlocked_skills": unlocked_skills,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var data: Dictionary = parsed
	inventory = data.get("inventory", [])
	var eq = data.get("equipped", {})
	if typeof(eq) == TYPE_DICTIONARY:
		for slot_name in SLOT_NAMES:
			equipped[slot_name] = String(eq.get(slot_name, ""))
	highest_wave = int(data.get("highest_wave", 0))
	levels_cleared = int(data.get("levels_cleared", 0))
	current_stage = maxi(1, int(data.get("current_stage", 1)))
	selected_stage = int(data.get("selected_stage", current_stage))
	clamp_selected_stage()
	coins = maxi(0, int(data.get("coins", 0)))
	_uid_counter = int(data.get("uid_counter", inventory.size() + 1))
	char_level = maxi(1, int(data.get("char_level", 1)))
	char_xp = maxi(0, int(data.get("char_xp", 0)))
	skill_points = maxi(0, int(data.get("skill_points", 0)))
	var skills = data.get("unlocked_skills", ["core"])
	if typeof(skills) == TYPE_ARRAY:
		unlocked_skills = skills.duplicate()
	if not ("core" in unlocked_skills):
		unlocked_skills.append("core")
