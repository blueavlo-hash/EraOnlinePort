## Era Online - Server-side combat math (all static, no state).
## Called by GameServer; never runs on clients.


## Base stats by class_id (0=Warrior 1=Mage 2=Rogue 3=Archer).
static func base_stats(class_id: int) -> Dictionary:
	match class_id:
		0: return {  # Warrior — low mana, relies on stamina
			"class_name": "Warrior",
			"body": 1, "head": 1,
			"hp": 150, "max_hp": 150, "mp": 0, "max_mp": 30,
			"sta": 150, "max_sta": 150,
			"str": 18, "agi": 10, "int_": 5, "cha": 5,
			"def": 0, "min_hit": 5, "max_hit": 12,
		}
		1: return {  # Mage — high mana pool
			"class_name": "Mage",
			"body": 2, "head": 1,
			"hp": 80,  "max_hp": 80,  "mp": 0, "max_mp": 120,
			"sta": 100, "max_sta": 100,
			"str": 8,  "agi": 10, "int_": 18, "cha": 8,
			"def": 0, "min_hit": 3, "max_hit": 8,
		}
		2: return {  # Rogue — moderate mana
			"class_name": "Rogue",
			"body": 3, "head": 1,
			"hp": 100, "max_hp": 100, "mp": 0, "max_mp": 60,
			"sta": 120, "max_sta": 120,
			"str": 14, "agi": 18, "int_": 8, "cha": 10,
			"def": 0, "min_hit": 4, "max_hit": 10,
		}
		_: return {   # Archer (class_id 3, also default) — moderate mana
			"class_name": "Archer",
			"body": 4, "head": 1,
			"hp": 100, "max_hp": 100, "mp": 0, "max_mp": 80,
			"sta": 110, "max_sta": 110,
			"str": 12, "agi": 16, "int_": 12, "cha": 8,
			"def": 0, "min_hit": 4, "max_hit": 9,
		}


## Class display name.
static func class_name_str(class_id: int) -> String:
	return base_stats(class_id).get("class_name", "Unknown")


## XP required to reach the NEXT level (level 1→2 = 1500, each level ×1.35).
## Steep grind curve — early levels require dozens of kills, mid-game requires hundreds.
static func xp_to_next(level: int) -> int:
	return int(1500.0 * pow(1.35, level - 1))


## XP rewarded for killing a character/NPC of the given level.
static func xp_for_kill(target_level: int) -> int:
	return target_level * 15


## Resolve one attack.  Returns {dmg:int, evaded:bool}.
## attacker/target are character dicts with min_hit, max_hit, def, agi fields.
## Evade chance scales with target AGI: 3% base + 0.3% per AGI point, capped at 25%.
## DEF absorbs at 60% efficiency (raw - def*0.6) so high-DEF targets stay hittable.
static func resolve_attack(attacker: Dictionary, target: Dictionary,
		multiplier: float = 1.0) -> Dictionary:
	var agi: int = target.get("agi", 10)
	if randf() < minf(0.25, 0.03 + agi * 0.003):
		return {"dmg": 0, "evaded": true}
	var raw := randi_range(
		attacker.get("min_hit", 1),
		attacker.get("max_hit", 5)
	)
	var eff_def := int(target.get("def", 0) * 0.6)
	var dmg := maxi(1, int(raw * multiplier) - eff_def)
	return {"dmg": dmg, "evaded": false}


## Apply a level-up to a character dict in-place.  Returns true if levelled.
static func try_level_up(char: Dictionary) -> bool:
	var lvl: int = char.get("level", 1)
	var xp:  int = char.get("xp",    0)
	var need: int = xp_to_next(lvl)
	if xp < need or lvl >= 50:
		return false

	char["level"]    = lvl + 1
	char["next_exp"] = xp_to_next(lvl + 1)

	# Per-class stat growth
	match char.get("class_id", 0):
		0:  # Warrior — tank: good HP, steadily rising DEF, strong STR
			char["max_hp"]  = char.get("max_hp",  150) + 12
			char["max_mp"]  = char.get("max_mp",   30) + 2
			char["max_sta"] = char.get("max_sta", 150) + 10
			char["str"]     = char.get("str",  18) + 2
			char["def"]     = char.get("def",   0) + 1   # passive DR from conditioning
		1:  # Mage — glass cannon: better HP growth than before, but still softest
			char["max_hp"]  = char.get("max_hp",   80) + 9
			char["max_mp"]  = char.get("max_mp",  120) + 14
			char["max_sta"] = char.get("max_sta", 100) + 6
			char["int_"]    = char.get("int_", 18) + 2
		2:  # Rogue — skirmisher: decent HP, rising AGI and STR
			char["max_hp"]  = char.get("max_hp",  100) + 10
			char["max_mp"]  = char.get("max_mp",   60) + 5
			char["max_sta"] = char.get("max_sta", 120) + 8
			char["agi"]     = char.get("agi",  18) + 2
			char["str"]     = char.get("str",  14) + 1
		_:  # Archer — versatile: balanced HP, AGI+INT for hybrid dodge/magic
			char["max_hp"]  = char.get("max_hp",  100) + 10
			char["max_mp"]  = char.get("max_mp",   80) + 7
			char["max_sta"] = char.get("max_sta", 110) + 7
			char["agi"]     = char.get("agi",  16) + 1
			char["int_"]    = char.get("int_", 12) + 1

	# Full restore on level up
	char["hp"]  = char["max_hp"]
	char["mp"]  = char["max_mp"]
	char["sta"] = char["max_sta"]
	return true


## Recalculate min_hit / max_hit / def from equipped items.
## equipment dict: slot_name → obj_index.  Uses GameData (available server-side).
static func recalculate_combat_stats(char: Dictionary) -> void:
	var min_h: int = char.get("base_min_hit", char.get("min_hit", 1))
	var max_h: int = char.get("base_max_hit", char.get("max_hit", 5))
	var def_v := 0

	var equip: Dictionary = char.get("equipment", {})
	if equip.get("weapon", 0) > 0:
		var obj := GameData.get_object(equip["weapon"])
		# Only override with weapon stats when they are non-zero.
		# Bows have min_hit=0/max_hit=0 in VB6 data (damage is skill-based).
		if obj.get("min_hit", 0) > 0:
			min_h = obj.get("min_hit", min_h)
		if obj.get("max_hit", 0) > 0:
			max_h = obj.get("max_hit", max_h)
		# Archery weapons: scale damage with Archery skill (index 27).
		# Creates a meaningful hit range that grows as the player trains.
		if obj.get("category", "") == "Archery":
			var sk: Array = char.get("skills", [])
			var archery_lv: int = sk[27] if sk.size() > 27 else 0
			min_h = min_h + archery_lv / 5          # +1 per 5 skill pts
			max_h = max_h + archery_lv / 2          # +1 per 2 skill pts
	for slot in ["armor", "helmet", "shield"]:
		if equip.get(slot, 0) > 0:
			var obj := GameData.get_object(equip[slot])
			def_v += obj.get("def", 0)

	char["min_hit"] = min_h
	char["max_hit"] = max_h
	char["def"]     = def_v
