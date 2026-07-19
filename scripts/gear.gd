extends Node
class_name GearSystem

signal gear_changed

const SLOT_NAMES := ["Helmet", "Armor", "Gloves", "Boots", "Weapon", "Ring1", "Ring2"]

var slots: Dictionary = {}
var player: CharacterBody2D
var fortress: Node2D
var meteor_slow: float = 0.0

func _ready() -> void:
	_sync_from_player_data()

func bind(p: CharacterBody2D, f: Node2D) -> void:
	player = p
	fortress = f
	_sync_from_player_data()
	_reapply_all()

func _sync_from_player_data() -> void:
	for slot_name in SLOT_NAMES:
		var item: Dictionary = PlayerData.get_equipped_item(slot_name)
		if item.is_empty():
			slots[slot_name] = null
		else:
			slots[slot_name] = {
				"name": String(item.get("name", "?")),
				"mods": PlayerData.get_item_mods(item),
				"color": PlayerData.item_color(item)
			}

func _reapply_all() -> void:
	if player == null:
		return

	var bonuses: Dictionary = PlayerData.get_equipped_bonuses()
	var skills: Dictionary = PlayerData.get_skill_bonuses()

	player.gear_damage_bonus = float(bonuses.get("damage", 0.0))
	player.gear_fire_rate_bonus = float(bonuses.get("fire_rate", 0.0))
	player.gear_move_bonus = float(bonuses.get("speed", 0.0))
	player.gear_cooldown_reduction = float(bonuses.get("cooldown", 0.0))
	player.gear_fork_count = int(bonuses.get("fork", 0))
	player.gear_pierce = int(bonuses.get("pierce", 0))
	player.gear_projectiles = int(bonuses.get("projectiles", 0))
	player.gear_ignition = int(bonuses.get("burn", 0)) > 0
	meteor_slow = float(bonuses.get("meteor_slow", 0.0))

	player.skill_damage_bonus = float(skills.get("weapon_damage", 0.0))
	player.skill_fire_rate_bonus = float(skills.get("weapon_fire_rate", 0.0))
	player.skill_pierce = int(skills.get("pierce", 0))
	player.skill_projectiles = int(skills.get("projectiles", 0))

	if fortress:
		fortress.tower_damage_multiplier = 1.0 + float(bonuses.get("tower_damage", 0.0)) + float(skills.get("tower_damage", 0.0))
		fortress.cooldown_reduction = float(bonuses.get("cooldown", 0.0)) + float(skills.get("tower_fire_rate", 0.0))
		fortress.leak_damage_mult = 1.0 - float(bonuses.get("leak_resist", 0.0))
		var bonus_hp: int = int(bonuses.get("fortress_hp", 0)) + int(skills.get("fortress_hp", 0))
		fortress.max_health = 500 + bonus_hp
		fortress.health = fortress.max_health
		fortress.health_changed.emit(fortress.health, fortress.max_health)

	gear_changed.emit()
