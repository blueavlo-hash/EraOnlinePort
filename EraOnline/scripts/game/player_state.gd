extends Node
## Era Online - PlayerState Autoload
## Authoritative local view of the player's inventory, equipment and stats.
## Online: mirrors server state via Network signals.
## Offline/debug: standalone with seeded test items.

signal inventory_changed()
signal equipment_changed()
signal stats_changed()
signal skills_changed(slot: int, value: int)
signal vitals_changed()
signal spellbook_changed()
signal spell_cast_started(spell_id: int)
signal hotbar_changed()
signal unified_hotbar_changed()

const MAX_SLOTS := 20
const SKILL_COUNT := 28

var hunger: int = 80
var thirst: int = 80

## Inventory slots 0..19. Each slot is {} (empty) or:
##   {obj_index:int, amount:int, equipped:bool}
var inventory: Array = []

## Skills: 28 values (0-indexed), but exposed 1-indexed via get_skill/set_skill.
var skills:          Array[int] = []
var skill_xp:        Array[int] = []   # XP within current level, 0-indexed
var skill_xp_needed: Array[int] = []   # XP needed for next level, 0-indexed

## Spells the player has learned (array of spell IDs, 1-based)
var learned_spells: Array[int] = []
## Combat abilities the player has learned (array of ability IDs, 0-based). Starts with Basic Attack.
var learned_abilities: Array[int] = [0]
## Hotbar spell assignments: 5 slots, each is a spell_id or 0 (empty)
var hotbar_spells: Array[int] = [0, 0, 0, 0, 0]
## Unified action hotbar: 10 slots. Each is null (empty) or
## {type: "ability"|"spell", id: int}
var unified_hotbar: Array = []
## Active status effects: status_id → expiry time (Time.get_ticks_msec() ms)
var active_statuses: Dictionary = {}
## Spell cooldowns: spell_id → expiry time (Time.get_ticks_msec() ms)
var spell_cooldowns: Dictionary = {}

## Named equipment slots → obj_index (0 = nothing equipped)
var equipment: Dictionary = {
	"weapon": 0,
	"shield": 0,
	"helmet": 0,
	"armor":  0,
	"boots":  0,
}

## Live stats. min_hit/max_hit/def are recomputed from equipment.
var stats: Dictionary = {
	"level":    1,
	"hp":       100, "max_hp":   100,
	"mp":       50,  "max_mp":   50,
	"sta":      100, "max_sta":  100,
	"exp":      0,   "next_exp": 300,
	"gold":     500,
	"str":      10,  "agi": 10, "int_": 10, "cha": 10,
	"min_hit":  1,   "max_hit":  5,
	"def":      0,
	"night_sight": 0,
}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	inventory.resize(MAX_SLOTS)
	for i in MAX_SLOTS:
		inventory[i] = {}

	skills.resize(SKILL_COUNT)
	skills.fill(0)
	skill_xp.resize(SKILL_COUNT)
	skill_xp.fill(0)
	skill_xp_needed.resize(SKILL_COUNT)
	skill_xp_needed.fill(100)

	unified_hotbar.resize(10)
	for i in 10:
		unified_hotbar[i] = null

	# Hook Network signals for online mode (safe even if server is down)
	Network.on_inventory.connect(_on_net_inventory)
	Network.on_equip_change.connect(_on_net_equip_change)
	Network.on_stats.connect(_on_net_stats)
	Network.on_health.connect(_on_net_health)
	Network.on_skills_received.connect(_on_net_skills)
	Network.on_skill_raise.connect(_on_net_skill_raise)
	Network.on_skill_xp.connect(_on_net_skill_xp)
	Network.on_vitals.connect(_on_net_vitals)
	Network.on_spellbook.connect(_on_net_spellbook)
	Network.on_spell_unlock.connect(_on_net_spell_unlock)
	Network.on_status_applied.connect(_on_net_status_applied)
	Network.on_status_removed.connect(_on_net_status_removed)
	Network.on_ability_list.connect(_on_net_ability_list)
	Network.on_ability_learned.connect(_on_net_ability_learned)
	Network.on_hotbar.connect(_on_net_hotbar)

	# Online: inventory/skills come from server via signals.
	# Offline: world_map calls seed_offline_debug() after the map loads.


# ---------------------------------------------------------------------------
# Unified Hotbar
# ---------------------------------------------------------------------------

func get_unified_hotbar_slot(idx: int) -> Variant:
	if idx < 0 or idx >= unified_hotbar.size():
		return null
	return unified_hotbar[idx]


func set_unified_hotbar_slot(idx: int, slot_type: String, slot_id: int) -> void:
	if idx < 0 or idx >= unified_hotbar.size():
		return
	unified_hotbar[idx] = {"type": slot_type, "id": slot_id}
	unified_hotbar_changed.emit()
	if Network.state == Network.State.CONNECTED:
		Network.send_hotbar(unified_hotbar)


func clear_unified_hotbar_slot(idx: int) -> void:
	if idx < 0 or idx >= unified_hotbar.size():
		return
	unified_hotbar[idx] = null
	unified_hotbar_changed.emit()
	if Network.state == Network.State.CONNECTED:
		Network.send_hotbar(unified_hotbar)


func _on_net_hotbar(slots: Array) -> void:
	## Restore hotbar received from server on world entry.
	for i in 10:
		unified_hotbar[i] = null
	for entry in slots:
		var idx: int = entry.get("slot", -1)
		if idx >= 0 and idx < 10:
			unified_hotbar[idx] = {"type": entry.get("type", "ability"), "id": entry.get("id", 0)}
	unified_hotbar_changed.emit()


# ---------------------------------------------------------------------------
# Skills
# ---------------------------------------------------------------------------

## Return skill value for a 1-based slot (1-28). Returns 0 for invalid slots.
func get_skill(slot_1based: int) -> int:
	if slot_1based < 1 or slot_1based > SKILL_COUNT:
		return 0
	return skills[slot_1based - 1]


## Set skill value for a 1-based slot and emit skills_changed.
func set_skill(slot_1based: int, value: int) -> void:
	if slot_1based < 1 or slot_1based > SKILL_COUNT:
		return
	skills[slot_1based - 1] = value
	skills_changed.emit(slot_1based, value)


## XP needed to go from `lv` to `lv+1`. Must match the server formula.
static func skill_xp_to_next(lv: int) -> int:
	if lv <= 0:   return 100
	if lv >= 100: return 0
	return roundi(100.0 * pow(1.09, lv - 1))


func _on_net_skills(skill_array: Array) -> void:
	## Received full skills list from server (Array[{level,xp,xp_needed}]).
	for i in mini(skill_array.size(), SKILL_COUNT):
		var entry = skill_array[i]
		if entry is Dictionary:
			skills[i]          = entry.get("level",    0)
			skill_xp[i]        = entry.get("xp",       0)
			skill_xp_needed[i] = entry.get("xp_needed", 100)
		else:
			skills[i] = int(entry)
	skills_changed.emit(-1, 0)


func _on_net_skill_raise(slot: int, value: int) -> void:
	## Server confirmed a skill level-up. XP resets to 0 for the new level.
	set_skill(slot, value)
	if slot >= 1 and slot <= SKILL_COUNT:
		skill_xp[slot - 1]        = 0
		skill_xp_needed[slot - 1] = skill_xp_to_next(value)


func _on_net_skill_xp(slot: int, current_xp: int, xp_needed: int) -> void:
	if slot >= 1 and slot <= SKILL_COUNT:
		skill_xp[slot - 1]        = current_xp
		skill_xp_needed[slot - 1] = xp_needed
		skills_changed.emit(slot, skills[slot - 1])


# ---------------------------------------------------------------------------
# Inventory mutations
# ---------------------------------------------------------------------------

## Seed debug items for offline/training mode — called by world_map, not on startup.
func seed_offline_debug() -> void:
	give_item(64,  1)   # Silver Sword       (weapon, 6-8 dmg)
	give_item(3,   1)   # Sword              (weapon, 1-5 dmg)
	give_item(57,  1)   # Rusty Wooden Shield (shield, shield_anim=3)
	give_item(145, 1)   # brown pants & green shirt (clothing, clothing_type=1)
	give_item(146, 1)   # Full Paladin Armor  (armor, clothing_type=14, DEF=18)
	give_item(40,  1)   # Plate Helmet        (helmet, obj_type=14, DEF=5)
	give_item(306, 1)   # Pickaxe            (tool for Mining)
	give_item(7,   1)   # Lumberjack's Axe   (tool for Lumberjacking)
	give_item(80,  1)   # Fishing Rod        (tool for Fishing)
	give_item(38,  1)   # Hammer             (tool for Smelting/Blacksmithing)
	give_item(154, 10)  # Ore x10            (Smelting material)
	give_item(308, 3)   # 2kg fish x3        (Cooking test)
	give_item(153, 20)  # Steel Clumps x20   (Blacksmithing material)
	give_item(185, 1)   # Knife Drawing      (Blacksmithing blueprint, 5 steel, skill 1)
	# Starter spells for offline testing (IDs 1-16 = original, 17+ = purchasable)
	for sid: int in [1, 2, 3, 4, 5, 17, 18, 19, 21, 22]:
		if not has_spell(sid):
			learned_spells.append(sid)
	spellbook_changed.emit()
	# Populate hotbar slots 0-4 with a mix of spell types (legacy hotbar)
	assign_hotbar(0, 1)    # slot 4-key: original spell 1
	assign_hotbar(1, 17)   # Arcane Bolt  (SINGLE_ENEMY, projectile)
	assign_hotbar(2, 18)   # Fireburst    (GROUND_AOE)
	assign_hotbar(3, 21)   # Lightning Chain (chain)
	assign_hotbar(4, 22)   # Frost Nova   (SELF_AOE)
	# Starter combat abilities for offline testing
	learned_abilities = [0, 1, 3, 5]
	# Pre-populate unified hotbar: slots 1-5 = abilities, 6-10 = spells
	set_unified_hotbar_slot(0, "ability", 0)  # 1: Basic Attack
	set_unified_hotbar_slot(1, "ability", 1)  # 2: Lunge
	set_unified_hotbar_slot(2, "ability", 3)  # 3: Feint
	set_unified_hotbar_slot(3, "ability", 5)  # 4: Cleave
	set_unified_hotbar_slot(4, "spell",   1)  # 5: Spell 1
	set_unified_hotbar_slot(5, "spell",  17)  # 6: Arcane Bolt
	set_unified_hotbar_slot(6, "spell",  18)  # 7: Fireburst
	set_unified_hotbar_slot(7, "spell",  21)  # 8: Lightning Chain
	# Infinite mana for testing
	stats["mp"]     = 9999
	stats["max_mp"] = 9999


## Add items. Stacks if same obj_index exists, else uses first free slot.
## Returns true on success, false if inventory full.
func give_item(obj_index: int, amount: int) -> bool:
	for i in MAX_SLOTS:
		var s = inventory[i]
		if not s.is_empty() and s["obj_index"] == obj_index and not s.get("equipped", false):
			s["amount"] += amount
			inventory_changed.emit()
			return true
	for i in MAX_SLOTS:
		if inventory[i].is_empty():
			inventory[i] = {"obj_index": obj_index, "amount": amount, "equipped": false}
			inventory_changed.emit()
			return true
	return false


## Remove `amount` of the item in `slot`. Clears slot if count reaches 0.
func remove_item(slot: int, amount: int = 1) -> bool:
	if slot < 0 or slot >= MAX_SLOTS or inventory[slot].is_empty():
		return false
	var s = inventory[slot]
	s["amount"] -= amount
	if s["amount"] <= 0:
		if s.get("equipped", false):
			unequip_slot(_get_equip_slot_for_obj(s["obj_index"]))
		inventory[slot] = {}
	inventory_changed.emit()
	return true


# ---------------------------------------------------------------------------
# Equipment
# ---------------------------------------------------------------------------

## Equip the item in inventory `slot`. Swaps out current item in that slot.
func equip_item(slot: int) -> void:
	if slot < 0 or slot >= MAX_SLOTS or inventory[slot].is_empty():
		return
	var obj_idx: int = inventory[slot]["obj_index"]
	var obj_data     := GameData.get_object(obj_idx)
	if obj_data.is_empty():
		return
	var eq_slot := _get_equip_slot(obj_data)
	if eq_slot.is_empty():
		return

	# Unequip whatever is currently in that slot
	if equipment[eq_slot] > 0:
		_clear_equip_flag(equipment[eq_slot])
	equipment[eq_slot] = obj_idx
	inventory[slot]["equipped"] = true

	_recalculate_combat_stats()
	inventory_changed.emit()
	equipment_changed.emit()

	if Network.state == Network.State.CONNECTED:
		Network.send_equip(slot)


## Unequip whatever is in the named equipment slot (e.g. "weapon").
func unequip_slot(eq_slot: String) -> void:
	if eq_slot.is_empty() or equipment.get(eq_slot, 0) == 0:
		return
	var obj_idx: int = equipment[eq_slot]
	# Find the inventory slot of this equipped item before clearing it
	var inv_slot: int = -1
	for i in MAX_SLOTS:
		var s = inventory[i]
		if not s.is_empty() and s["obj_index"] == obj_idx and s.get("equipped", false):
			inv_slot = i
			break
	_clear_equip_flag(obj_idx)
	equipment[eq_slot] = 0
	_recalculate_combat_stats()
	inventory_changed.emit()
	equipment_changed.emit()

	if Network.state == Network.State.CONNECTED:
		Network.send_unequip(inv_slot if inv_slot >= 0 else 0)


## Return the equipped obj_index for a given slot name, 0 if empty.
func get_equipped(eq_slot: String) -> int:
	return equipment.get(eq_slot, 0)


# ---------------------------------------------------------------------------
# Damage / healing (local, also applied via Network signals online)
# ---------------------------------------------------------------------------

func apply_damage(amount: int) -> void:
	stats["hp"] = maxi(0, stats["hp"] - amount)
	stats_changed.emit()


func heal(amount: int) -> void:
	stats["hp"] = mini(stats["max_hp"], stats["hp"] + amount)
	stats_changed.emit()


# ---------------------------------------------------------------------------
# Network signal handlers
# ---------------------------------------------------------------------------

func _on_net_inventory(items: Array) -> void:
	for i in MAX_SLOTS:
		inventory[i] = {}
	for item in items:
		var slot: int = item.get("slot", 1) - 1  # Server is 1-based
		if slot >= 0 and slot < MAX_SLOTS:
			inventory[slot] = {
				"obj_index": item.get("obj_index", 0),
				"amount":    item.get("amount",    1),
				"equipped":  item.get("equipped",  0) != 0,
			}
	_rebuild_equipment_from_inventory()
	inventory_changed.emit()
	equipment_changed.emit()


func _on_net_equip_change(_slot: int, _obj_index: int, _amount: int) -> void:
	_rebuild_equipment_from_inventory()
	_recalculate_combat_stats()
	equipment_changed.emit()


func _on_net_stats(s: Dictionary) -> void:
	for k in s:
		stats[k] = s[k]
	stats_changed.emit()


func _on_net_health(hp: int, mp: int, sta: int) -> void:
	stats["hp"]  = hp
	stats["mp"]  = mp
	stats["sta"] = sta
	stats_changed.emit()


func _on_net_vitals(h: int, t: int) -> void:
	hunger = h
	thirst = t
	vitals_changed.emit()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _recalculate_combat_stats() -> void:
	stats["min_hit"] = 1
	stats["max_hit"] = 5
	stats["def"]     = 0
	if equipment["weapon"] > 0:
		var obj := GameData.get_object(equipment["weapon"])
		stats["min_hit"] = obj.get("min_hit", 1)
		stats["max_hit"] = obj.get("max_hit", 5)
	if equipment["armor"] > 0:
		var obj := GameData.get_object(equipment["armor"])
		stats["def"] += obj.get("def", 0)
	if equipment["helmet"] > 0:
		var obj := GameData.get_object(equipment["helmet"])
		stats["def"] += obj.get("def", 0)
	if equipment["shield"] > 0:
		var obj := GameData.get_object(equipment["shield"])
		stats["def"] += obj.get("def", 0)
	# Night Sight: sum from all equipped items that carry the property
	var ns: int = 0
	for eq_slot in equipment:
		var idx: int = equipment[eq_slot]
		if idx > 0:
			ns += GameData.get_object(idx).get("night_sight", 0)
	stats["night_sight"] = ns
	stats_changed.emit()


func _rebuild_equipment_from_inventory() -> void:
	for k in equipment:
		equipment[k] = 0
	for i in MAX_SLOTS:
		var s = inventory[i]
		if s.is_empty() or not s.get("equipped", false):
			continue
		var obj := GameData.get_object(s["obj_index"])
		var slot := _get_equip_slot(obj)
		if not slot.is_empty():
			equipment[slot] = s["obj_index"]


func _get_equip_slot(obj_data: Dictionary) -> String:
	# ObjType 24 = OBJTYPE_SHIELD in VB6 (category stored as "Armor" in OBJ.dat)
	if obj_data.get("obj_type", 0) == 24:
		return "shield"
	# ObjType 14 = OBJTYPE_HELMET; equipping changes body animation via clothing_type
	if obj_data.get("obj_type", 0) == 14:
		return "helmet"
	match obj_data.get("category", ""):
		"Weapon", "Archery": return "weapon"
	# Clothing (obj_type 15) and Armor (obj_type 3): any non-zero clothing_type
	# means equipping changes the body sprite via that clothing_type index.
	# OBJ2 "Armour" has clothing_type=0 but category="Armor" and obj_type=3.
	var obj_type: int = obj_data.get("obj_type", 0)
	if obj_type == 15 or obj_type == 3:
		return "armor"
	if obj_data.get("clothing_type", 0) > 0:
		return "armor"
	return ""


func _get_equip_slot_for_obj(obj_index: int) -> String:
	return _get_equip_slot(GameData.get_object(obj_index))


func _clear_equip_flag(obj_index: int) -> void:
	for i in MAX_SLOTS:
		var s = inventory[i]
		if not s.is_empty() and s["obj_index"] == obj_index and s.get("equipped", false):
			s["equipped"] = false
			return


# ---------------------------------------------------------------------------
# Spells
# ---------------------------------------------------------------------------

func has_spell(spell_id: int) -> bool:
	return spell_id in learned_spells

func has_ability(ability_id: int) -> bool:
	return learned_abilities.has(ability_id)

func assign_hotbar(slot: int, spell_id: int) -> void:
	## Assign spell_id (or 0 to clear) to hotbar slot 0-4.
	if slot < 0 or slot >= hotbar_spells.size():
		return
	hotbar_spells[slot] = spell_id
	hotbar_changed.emit()

func get_hotbar_spell(slot: int) -> int:
	if slot < 0 or slot >= hotbar_spells.size():
		return 0
	return hotbar_spells[slot]

func is_spell_ready(spell_id: int) -> bool:
	var now := Time.get_ticks_msec()
	return not spell_cooldowns.has(spell_id) or spell_cooldowns[spell_id] <= now

func set_spell_cooldown(spell_id: int, cooldown_sec: float) -> void:
	spell_cooldowns[spell_id] = Time.get_ticks_msec() + int(cooldown_sec * 1000.0)
	# Remove when expired (cleaned lazily via is_spell_ready)

func get_cooldown_remaining(spell_id: int) -> float:
	if not spell_cooldowns.has(spell_id):
		return 0.0
	var rem: int = spell_cooldowns[spell_id] - Time.get_ticks_msec()
	return maxf(0.0, float(rem) / 1000.0)

func has_status(status_id: int) -> bool:
	if not active_statuses.has(status_id):
		return false
	return active_statuses[status_id] > Time.get_ticks_msec()

func _on_net_spellbook(spell_ids: Array) -> void:
	learned_spells.clear()
	var seen: Dictionary = {}
	for sid in spell_ids:
		var id := int(sid)
		if id > 0 and not seen.has(id):
			seen[id] = true
			learned_spells.append(id)
	spellbook_changed.emit()
	# Auto-populate empty hotbar slots with newly received spells so that
	# online players can cast immediately without opening the spellbook UI.
	_auto_fill_hotbar()

func _on_net_spell_unlock(spell_id: int) -> void:
	if not has_spell(spell_id):
		learned_spells.append(spell_id)
		spellbook_changed.emit()
		# Try to slot the newly unlocked spell into the first free hotbar slot.
		_auto_fill_hotbar()

func _auto_fill_hotbar() -> void:
	## Fill any empty hotbar slots (value == 0) with the first learned spells
	## that are not already assigned. Called after S_SPELLBOOK / S_SPELL_UNLOCK
	## so online players can cast immediately without manually assigning spells.
	var already_assigned: Dictionary = {}
	for i in hotbar_spells.size():
		if hotbar_spells[i] != 0:
			already_assigned[hotbar_spells[i]] = true
	for spell_id in learned_spells:
		if already_assigned.has(spell_id):
			continue
		# Find the first empty hotbar slot
		for i in hotbar_spells.size():
			if hotbar_spells[i] == 0:
				hotbar_spells[i] = spell_id
				already_assigned[spell_id] = true
				break
	hotbar_changed.emit()


func _on_net_status_applied(char_id: int, status_id: int, duration_ms: int) -> void:
	## Only track statuses on the local player (char_id == 0 means "self" from server perspective)
	## The server sends char_id matching the player's peer_id; we simplify by tracking all.
	active_statuses[status_id] = Time.get_ticks_msec() + duration_ms
	stats_changed.emit()

func _on_net_status_removed(char_id: int, status_id: int) -> void:
	active_statuses.erase(status_id)
	stats_changed.emit()


func _on_net_ability_list(ids: Array) -> void:
	learned_abilities.clear()
	for id in ids:
		learned_abilities.append(int(id))
	if not learned_abilities.has(0):
		learned_abilities.insert(0, 0)  # always have basic attack


func _on_net_ability_learned(ability_id: int) -> void:
	if not learned_abilities.has(ability_id):
		learned_abilities.append(ability_id)
