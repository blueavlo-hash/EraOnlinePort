class_name ServerQuests
## Era Online - Quest Definitions and Server-Side Progress Checking
##
## All quest definitions are hardcoded here as constants.
## Quest progress is stored in char_dict["quests"] as:
##   { quest_id: { "accepted": bool, "progress": {}, "completed": bool } }
##
## Quest objective types:
##   "kill":         progress["kills"] >= required count
##   "gather":       player holds >= required amount of item with matching obj_type
##   "cook":         progress["cooks"] >= required count
##   "kill_specific": progress["kills_" + npc_name_contains] >= required count
##   "explore":      char_dict["visited_maps"].has(map_id)
##   "craft":        progress["crafts_" + action] >= required count
##   "deliver":      always true once accepted (turn-in = reaching the NPC)


# ---------------------------------------------------------------------------
# Quest IDs
# ---------------------------------------------------------------------------

const QUEST_WARRIORS_BEGINNING : int = 1
const QUEST_GATHER_RESOURCES   : int = 2
const QUEST_HUNGRY_TRAVELER    : int = 3


# ---------------------------------------------------------------------------
# Quest definitions
# ---------------------------------------------------------------------------
## Each quest dict contains:
##   id              : int        — unique quest ID
##   name            : String
##   desc            : String     — dialogue text shown in quest offer
##   giver_npc_name  : String     — NPC name prefix match (case-insensitive) or ""
##   giver_npc_type  : int        — NPC type fallback (-1 = match by name only)
##   turnin_npc_name : String     — NPC name for turn-in (may differ from giver)
##   turnin_npc_type : int        — NPC type for turn-in (-1 = name only)
##   level_req       : int        — minimum character level to accept
##   prereqs         : Array      — quest IDs that must be completed first
##   objectives      : Array      — Array of objective dicts
##   rewards         : Dictionary — { gold, xp, items: [{obj_index, amount}] }
##   completion_msg  : String     — shown in chat on complete

const QUESTS: Array = [
	# -----------------------------------------------------------------------
	# Chain 1 — The Elder (Tutorial)
	# -----------------------------------------------------------------------
	{
		"id":              QUEST_WARRIORS_BEGINNING,
		"name":            "A Warrior's Beginning",
		"desc":            "You look capable, adventurer. Prove yourself by defeating some of the creatures plaguing our lands.",
		"giver_npc_name":  "mayor",
		"giver_npc_type":  0,
		"turnin_npc_name": "mayor",
		"turnin_npc_type": 0,
		"level_req":       1,
		"prereqs":         [],
		"objectives": [
			{"type": "kill", "count": 5, "label": "Kill hostile NPCs"}
		],
		"rewards": {"gold": 100, "xp": 200, "items": []},
		"rep_faction": "haven", "rep_amount": 75,
		"completion_msg":  "Well done, warrior. You are ready for greater challenges.",
	},
	{
		"id":              QUEST_GATHER_RESOURCES,
		"name":            "Gather Resources",
		"desc":            "Good work. Now learn to gather resources. Bring me materials.",
		"giver_npc_name":  "mayor",
		"giver_npc_type":  0,
		"turnin_npc_name": "mayor",
		"turnin_npc_type": 0,
		"level_req":       1,
		"prereqs":         [QUEST_WARRIORS_BEGINNING],
		"objectives": [
			{"type": "gather", "count": 5, "obj_types": [32, 20], "label": "Gather ore or logs"}
		],
		"rewards": {"gold": 50, "xp": 100, "items": [{"obj_index": 3, "amount": 1}]},
		"rep_faction": "haven", "rep_amount": 75,
		"completion_msg":  "Excellent! These materials will serve you well.",
	},
	{
		"id":              4,
		"name":            "The Elder's Errand",
		"desc":            "I need you to deliver this letter to the Blacksmith. He must know of the danger approaching.",
		"giver_npc_name":  "mayor",
		"giver_npc_type":  0,
		"turnin_npc_name": "master blacksmith",
		"turnin_npc_type": -1,
		"level_req":       2,
		"prereqs":         [QUEST_GATHER_RESOURCES],
		"objectives": [
			{"type": "deliver", "label": "Deliver the letter to the Blacksmith"}
		],
		"rewards": {"gold": 75, "xp": 150, "items": []},
		"rep_faction": "haven", "rep_amount": 50,
		"completion_msg":  "Thank you for the message. The Elder was right to send you.",
	},
	{
		"id":              5,
		"name":            "Clearing the Road",
		"desc":            "The roads are not safe. I need you to clear more creatures before the merchants can travel safely.",
		"giver_npc_name":  "mayor",
		"giver_npc_type":  0,
		"turnin_npc_name": "mayor",
		"turnin_npc_type": 0,
		"level_req":       3,
		"prereqs":         [4],
		"objectives": [
			{"type": "kill", "count": 20, "label": "Kill hostile creatures"}
		],
		"rewards": {"gold": 200, "xp": 400, "items": []},
		"rep_faction": "haven", "rep_amount": 100,
		"completion_msg":  "The roads are safer now. Thank you, adventurer.",
	},
	{
		"id":              6,
		"name":            "The Ancient Threat",
		"desc":            "Ancient serpents have returned to the land. Slay five of them to protect the village.",
		"giver_npc_name":  "mayor",
		"giver_npc_type":  0,
		"turnin_npc_name": "mayor",
		"turnin_npc_type": 0,
		"level_req":       5,
		"prereqs":         [5],
		"objectives": [
			{"type": "kill_specific", "count": 5, "npc_name_contains": "serpent", "label": "Kill Serpents"}
		],
		"rewards": {"gold": 300, "xp": 600, "items": []},
		"rep_faction": "haven", "rep_amount": 150,
		"completion_msg":  "The ancient threat is no more. The village owes you a great debt.",
	},

	# -----------------------------------------------------------------------
	# Chain 2 — The Blacksmith
	# -----------------------------------------------------------------------
	{
		"id":              7,
		"name":            "Raw Materials",
		"desc":            "Ah, a fresh face. I am Master Blacksmith Aldric. Gather ten pieces of ore and prove you are worth teaching.",
		"giver_npc_name":  "master blacksmith",
		"giver_npc_type":  -1,
		"turnin_npc_name": "master blacksmith",
		"turnin_npc_type": -1,
		"level_req":       1,
		"prereqs":         [],
		"objectives": [
			{"type": "gather", "count": 10, "obj_types": [32], "label": "Gather ore"}
		],
		"rewards": {"gold": 80, "xp": 160, "items": []},
		"rep_faction": "ironhaven", "rep_amount": 100,
		"completion_msg":  "Good haul! Now let me show you what to do with all this ore.",
	},
	{
		"id":              8,
		"name":            "Learning to Smelt",
		"desc":            "Every blacksmith must learn to smelt ore into steel. Smelt three batches for me.",
		"giver_npc_name":  "master blacksmith",
		"giver_npc_type":  -1,
		"turnin_npc_name": "master blacksmith",
		"turnin_npc_type": -1,
		"level_req":       2,
		"prereqs":         [7],
		"objectives": [
			{"type": "craft", "count": 3, "action": "smelt", "label": "Smelt ore into steel"}
		],
		"rewards": {"gold": 120, "xp": 240, "items": []},
		"rep_faction": "ironhaven", "rep_amount": 150,
		"completion_msg":  "Fine steel! Now you are ready to forge real weapons.",
	},
	{
		"id":              9,
		"name":            "First Weapon",
		"desc":            "Use a blacksmithing blueprint to forge your first weapon. Show me what you can do!",
		"giver_npc_name":  "master blacksmith",
		"giver_npc_type":  -1,
		"turnin_npc_name": "master blacksmith",
		"turnin_npc_type": -1,
		"level_req":       3,
		"prereqs":         [8],
		"objectives": [
			{"type": "craft", "count": 1, "action": "forge", "label": "Forge a weapon or armour"}
		],
		"rewards": {"gold": 200, "xp": 300, "items": [{"obj_index": 5, "amount": 1}]},
		"rep_faction": "ironhaven", "rep_amount": 175,
		"completion_msg":  "An excellent piece of work! You have the makings of a true smith.",
	},
	{
		"id":              10,
		"name":            "Arming the Militia",
		"desc":            "The militia needs weapons. Forge five items from blueprints to equip them.",
		"giver_npc_name":  "master blacksmith",
		"giver_npc_type":  -1,
		"turnin_npc_name": "master blacksmith",
		"turnin_npc_type": -1,
		"level_req":       5,
		"prereqs":         [9],
		"objectives": [
			{"type": "craft", "count": 5, "action": "forge", "label": "Forge weapons or armour"}
		],
		"rewards": {"gold": 500, "xp": 800, "items": []},
		"rep_faction": "ironhaven", "rep_amount": 200,
		"completion_msg":  "The militia is armed and ready. You have done great service for this town.",
	},

	# -----------------------------------------------------------------------
	# Chain 3 — The Cook
	# -----------------------------------------------------------------------
	{
		"id":              QUEST_HUNGRY_TRAVELER,
		"name":            "The Hungry Traveler",
		"desc":            "I could use some help in the kitchen. Show me you can cook.",
		"giver_npc_name":  "cook",
		"giver_npc_type":  -1,
		"turnin_npc_name": "cook",
		"turnin_npc_type": -1,
		"level_req":       1,
		"prereqs":         [],
		"objectives": [
			{"type": "cook", "count": 3, "label": "Cook food items"}
		],
		"rewards": {"gold": 75, "xp": 150, "items": []},
		"rep_faction": "thornwall", "rep_amount": 100,
		"completion_msg":  "Delicious! You have real talent in the kitchen.",
	},
	{
		"id":              11,
		"name":            "Feed the Village",
		"desc":            "Winter is coming and the village needs food. Cook ten meals for the storeroom.",
		"giver_npc_name":  "cook",
		"giver_npc_type":  -1,
		"turnin_npc_name": "cook",
		"turnin_npc_type": -1,
		"level_req":       2,
		"prereqs":         [QUEST_HUNGRY_TRAVELER],
		"objectives": [
			{"type": "cook", "count": 10, "label": "Cook food for the village"}
		],
		"rewards": {"gold": 150, "xp": 250, "items": []},
		"rep_faction": "thornwall", "rep_amount": 150,
		"completion_msg":  "The village will eat well this winter, thanks to you!",
	},
	{
		"id":              12,
		"name":            "Rare Catch",
		"desc":            "I need fresh fish for a special feast. Bring me five fish from the nearby waters.",
		"giver_npc_name":  "cook",
		"giver_npc_type":  -1,
		"turnin_npc_name": "cook",
		"turnin_npc_type": -1,
		"level_req":       3,
		"prereqs":         [11],
		"objectives": [
			{"type": "gather", "count": 5, "obj_types": [39], "label": "Gather fresh fish"}
		],
		"rewards": {"gold": 100, "xp": 200, "items": []},
		"rep_faction": "thornwall", "rep_amount": 125,
		"completion_msg":  "What a wonderful catch! The feast will be remembered for years.",
	},

	# -----------------------------------------------------------------------
	# Chain 4 — The Guard (Hunter chain)
	# -----------------------------------------------------------------------
	{
		"id":              13,
		"name":            "Pest Control",
		"desc":            "Giant spiders have been terrorizing travellers on the road. Kill ten of them.",
		"giver_npc_name":  "guard",
		"giver_npc_type":  -1,
		"turnin_npc_name": "guard",
		"turnin_npc_type": -1,
		"level_req":       2,
		"prereqs":         [],
		"objectives": [
			{"type": "kill_specific", "count": 10, "npc_name_contains": "spider", "label": "Kill Spiders"}
		],
		"rewards": {"gold": 120, "xp": 250, "items": []},
		"rep_faction": "thornwall", "rep_amount": 100,
		"completion_msg":  "Well done! The roads are safe again for now.",
	},
	{
		"id":              14,
		"name":            "Into the Wilderness",
		"desc":            "We need scouts in the eastern forest. Explore the area and report back.",
		"giver_npc_name":  "guard",
		"giver_npc_type":  -1,
		"turnin_npc_name": "guard",
		"turnin_npc_type": -1,
		"level_req":       1,
		"prereqs":         [],
		"objectives": [
			{"type": "explore", "map_id": 4, "label": "Explore the Eastern Forest"}
		],
		"rewards": {"gold": 50, "xp": 100, "items": []},
		"rep_faction": "thornwall", "rep_amount": 75,
		"completion_msg":  "Good scouting! Now we know what lurks out there.",
	},
	{
		"id":              15,
		"name":            "Big Game",
		"desc":            "Trolls have moved into the region. Take down five of them before they destroy the farmsteads.",
		"giver_npc_name":  "guard",
		"giver_npc_type":  -1,
		"turnin_npc_name": "guard",
		"turnin_npc_type": -1,
		"level_req":       5,
		"prereqs":         [13, 14],
		"objectives": [
			{"type": "kill_specific", "count": 5, "npc_name_contains": "troll", "label": "Kill Trolls"}
		],
		"rewards": {"gold": 250, "xp": 500, "items": []},
		"rep_faction": "thornwall", "rep_amount": 175,
		"completion_msg":  "Those trolls won't be bothering anyone anymore. Exceptional work!",
	},
	{
		"id":              16,
		"name":            "Ancient Ruins",
		"desc":            "Strange lights have been seen in the ancient ruins to the south-east. Scout the area.",
		"giver_npc_name":  "guard",
		"giver_npc_type":  -1,
		"turnin_npc_name": "guard",
		"turnin_npc_type": -1,
		"level_req":       3,
		"prereqs":         [14],
		"objectives": [
			{"type": "explore", "map_id": 6, "label": "Explore the Ancient Ruins"}
		],
		"rewards": {"gold": 100, "xp": 200, "items": []},
		"rep_faction": "thornwall", "rep_amount": 100,
		"completion_msg":  "Those ruins are indeed dangerous. Good to have a full report.",
	},

	# -----------------------------------------------------------------------
	# Chain 5 — Merchant Tim
	# -----------------------------------------------------------------------
	{
		"id":              17,
		"name":            "Supply Run",
		"desc":            "My lumber supply is depleted. Bring me five logs and I will make it worth your while.",
		"giver_npc_name":  "tim",
		"giver_npc_type":  -1,
		"turnin_npc_name": "tim",
		"turnin_npc_type": -1,
		"level_req":       1,
		"prereqs":         [],
		"objectives": [
			{"type": "gather", "count": 5, "obj_types": [20], "label": "Gather logs"}
		],
		"rewards": {"gold": 60, "xp": 120, "items": []},
		"rep_faction": "haven", "rep_amount": 75,
		"completion_msg":  "Perfect! That's exactly what I needed. Come back if you want more work.",
	},
	{
		"id":              18,
		"name":            "Timber!",
		"desc":            "I need planks cut from logs for my workshop. Use the carpentry station to cut three batches.",
		"giver_npc_name":  "tim",
		"giver_npc_type":  -1,
		"turnin_npc_name": "tim",
		"turnin_npc_type": -1,
		"level_req":       2,
		"prereqs":         [17],
		"objectives": [
			{"type": "craft", "count": 3, "action": "planks", "label": "Cut logs into planks"}
		],
		"rewards": {"gold": 100, "xp": 200, "items": []},
		"rep_faction": "haven", "rep_amount": 100,
		"completion_msg":  "Good clean cuts! Those planks will build something fine.",
	},
	{
		"id":              19,
		"name":            "Well Equipped",
		"desc":            "I need a reliable supply of ore for trade. Gather ten pieces and bring them here.",
		"giver_npc_name":  "tim",
		"giver_npc_type":  -1,
		"turnin_npc_name": "tim",
		"turnin_npc_type": -1,
		"level_req":       2,
		"prereqs":         [17],
		"objectives": [
			{"type": "gather", "count": 10, "obj_types": [32], "label": "Gather ore"}
		],
		"rewards": {"gold": 150, "xp": 250, "items": []},
		"rep_faction": "haven", "rep_amount": 125,
		"completion_msg":  "Excellent stock! The trade caravans will be pleased.",
	},

	# -----------------------------------------------------------------------
	# Chain 6 — Sylvara the Spell Merchant
	# -----------------------------------------------------------------------
	{
		"id":              20,
		"name":            "Magical Aptitude",
		"desc":            "You found me all the way out here — good. The air elementals in the ancient ruins are a danger to all. Slay three and I will teach you something priceless.",
		"giver_npc_name":  "sylvara",
		"giver_npc_type":  -1,
		"turnin_npc_name": "sylvara",
		"turnin_npc_type": -1,
		"level_req":       4,
		"prereqs":         [],
		"objectives": [
			{"type": "kill_specific", "count": 3, "npc_name_contains": "elemental", "label": "Kill Elementals"}
		],
		"rewards": {"gold": 200, "xp": 400, "items": []},
		"rep_faction": "sealport", "rep_amount": 150,
		"completion_msg":  "Impressive! You have proven yourself worthy of learning the higher arts.",
	},
]


# ---------------------------------------------------------------------------
# Static helpers
# ---------------------------------------------------------------------------

## Returns the quest dict for quest_id, or {} if not found.
static func get_quest(quest_id: int) -> Dictionary:
	for q in QUESTS:
		if (q as Dictionary).get("id", 0) == quest_id:
			return q as Dictionary
	return {}


## Returns true if the character meets all prerequisites to accept quest_id.
static func can_accept(char_dict: Dictionary, quest_id: int) -> bool:
	var q: Dictionary = get_quest(quest_id)
	if q.is_empty():
		return false
	var quests: Dictionary = char_dict.get("quests", {})
	# Already accepted or completed?
	var qstr: String = str(quest_id)
	if quests.has(qstr):
		var entry: Dictionary = quests[qstr] as Dictionary
		if entry.get("accepted", false) or entry.get("completed", false):
			return false
	# Level requirement
	var level_req: int = int(q.get("level_req", 1))
	if int(char_dict.get("level", 1)) < level_req:
		return false
	# Check max active quests (10 cap)
	var active_count: int = 0
	for qid_str in quests:
		var e: Dictionary = quests[qid_str] as Dictionary
		if e.get("accepted", false) and not e.get("completed", false):
			active_count += 1
	if active_count >= 10:
		return false
	# Check prerequisites (array of quest IDs)
	var prereqs: Array = q.get("prereqs", [])
	for pre_id in prereqs:
		var pre_str: String = str(int(pre_id))
		if not quests.has(pre_str):
			return false
		var pre_entry: Dictionary = quests[pre_str] as Dictionary
		if not pre_entry.get("completed", false):
			return false
	return true


## Returns true if all objectives for quest_id are satisfied.
## Checks the character's current progress dict and inventory/visited_maps.
static func check_progress(char_dict: Dictionary, quest_id: int) -> bool:
	var q: Dictionary = get_quest(quest_id)
	if q.is_empty():
		return false
	var quests: Dictionary = char_dict.get("quests", {})
	var qstr: String = str(quest_id)
	if not quests.has(qstr):
		return false
	var entry: Dictionary = quests[qstr] as Dictionary
	if not entry.get("accepted", false):
		return false
	if entry.get("completed", false):
		return false
	var progress: Dictionary = entry.get("progress", {})
	var objectives: Array = q.get("objectives", [])
	for obj in objectives:
		var od: Dictionary = obj as Dictionary
		match od.get("type", ""):
			"kill":
				var kills: int = int(progress.get("kills", 0))
				if kills < int(od.get("count", 1)):
					return false
			"cook":
				var cooks: int = int(progress.get("cooks", 0))
				if cooks < int(od.get("count", 1)):
					return false
			"gather":
				# Check live inventory for matching obj_types
				var required: int = int(od.get("count", 1))
				var obj_types: Array = od.get("obj_types", [])
				var total: int = 0
				var inv: Array = char_dict.get("inventory", [])
				for item in inv:
					var d: Dictionary = item as Dictionary
					if d.is_empty():
						continue
					var oi: int = d.get("obj_index", 0)
					var obj_data: Dictionary = GameData.get_object(oi)
					if obj_data.is_empty():
						continue
					if int(obj_data.get("obj_type", -1)) in obj_types:
						total += int(d.get("amount", 0))
				if total < required:
					return false
			"kill_specific":
				var contains: String = od.get("npc_name_contains", "").to_lower()
				var key: String = "kills_" + contains
				var kills_sp: int = int(progress.get(key, 0))
				if kills_sp < int(od.get("count", 1)):
					return false
			"explore":
				var map_id: int = int(od.get("map_id", -1))
				var visited: Array = char_dict.get("visited_maps", [])
				if not visited.has(map_id):
					return false
			"craft":
				var action: String = od.get("action", "")
				var key: String = "crafts_" + action
				var crafts: int = int(progress.get(key, 0))
				if crafts < int(od.get("count", 1)):
					return false
			"deliver":
				# Delivery is always ready once accepted — completion is reaching turnin NPC
				pass
	return true


## Returns quests for which the given NPC can serve as quest giver or turn-in target.
## Returns Array of { quest_id, mode } where mode = "offer" or "turnin".
static func quests_for_npc(char_dict: Dictionary, npc_name: String, npc_type: int) -> Array:
	var result: Array = []
	var name_lower: String = npc_name.to_lower()
	for entry in QUESTS:
		var q: Dictionary = entry as Dictionary
		var qid: int = q.get("id", 0)

		# --- Check for turn-in match ---
		var ti_name: String = q.get("turnin_npc_name", "").to_lower()
		var ti_type: int = int(q.get("turnin_npc_type", -1))
		var matches_turnin: bool = false
		if ti_name != "" and name_lower.contains(ti_name):
			matches_turnin = true
		elif ti_type >= 0 and ti_type == npc_type:
			matches_turnin = true

		if matches_turnin and check_progress(char_dict, qid):
			result.append({"quest_id": qid, "mode": "turnin"})
			continue

		# --- Check for offer match ---
		var giver_name: String = q.get("giver_npc_name", "").to_lower()
		var giver_type: int = int(q.get("giver_npc_type", -1))
		var matches_giver: bool = false
		if giver_name != "" and name_lower.contains(giver_name):
			matches_giver = true
		elif giver_type >= 0 and giver_type == npc_type:
			matches_giver = true

		if matches_giver and can_accept(char_dict, qid):
			result.append({"quest_id": qid, "mode": "offer"})

	return result


## Returns a human-readable progress string for all objectives of a quest.
static func objective_progress_str(char_dict: Dictionary, quest_id: int) -> String:
	var q: Dictionary = get_quest(quest_id)
	if q.is_empty():
		return ""
	var quests: Dictionary = char_dict.get("quests", {})
	var qstr: String = str(quest_id)
	if not quests.has(qstr):
		return ""
	var entry: Dictionary = quests[qstr] as Dictionary
	var progress: Dictionary = entry.get("progress", {})
	var parts: Array = []
	for obj in q.get("objectives", []):
		var od: Dictionary = obj as Dictionary
		var label: String = od.get("label", "")
		var required: int = int(od.get("count", 1))
		match od.get("type", ""):
			"kill":
				var cur: int = int(progress.get("kills", 0))
				parts.append("%s: %d/%d" % [label, mini(cur, required), required])
			"cook":
				var cur: int = int(progress.get("cooks", 0))
				parts.append("%s: %d/%d" % [label, mini(cur, required), required])
			"gather":
				var obj_types: Array = od.get("obj_types", [])
				var total: int = 0
				var inv: Array = char_dict.get("inventory", [])
				for item in inv:
					var d: Dictionary = item as Dictionary
					if d.is_empty():
						continue
					var oi: int = d.get("obj_index", 0)
					var obj_data: Dictionary = GameData.get_object(oi)
					if not obj_data.is_empty() and \
							int(obj_data.get("obj_type", -1)) in obj_types:
						total += int(d.get("amount", 0))
				parts.append("%s: %d/%d" % [label, mini(total, required), required])
			"kill_specific":
				var contains: String = od.get("npc_name_contains", "").to_lower()
				var key: String = "kills_" + contains
				var cur: int = int(progress.get(key, 0))
				parts.append("%s: %d/%d" % [label, mini(cur, required), required])
			"explore":
				var map_id: int = int(od.get("map_id", -1))
				var visited: Array = char_dict.get("visited_maps", [])
				var map_name: String = "Map %d" % map_id
				if visited.has(map_id):
					parts.append("Explore %s: Done" % map_name)
				else:
					parts.append("Explore %s: Not yet visited" % map_name)
			"craft":
				var action: String = od.get("action", "")
				var key: String = "crafts_" + action
				var cur: int = int(progress.get(key, 0))
				parts.append("%s: %d/%d" % [label, mini(cur, required), required])
			"deliver":
				var turnin: String = q.get("turnin_npc_name", "NPC")
				parts.append("Deliver to %s: Ready" % turnin.capitalize())
	return ", ".join(parts)


## Returns "!" if any quest can be offered at this NPC,
## "?" if any quest is ready to turn in at this NPC,
## "" otherwise. "?" takes priority over "!".
static func get_npc_indicator(char_dict: Dictionary, npc_name: String, npc_type: int) -> String:
	var name_lower: String = npc_name.to_lower()
	var has_offer: bool = false
	for entry in QUESTS:
		var q: Dictionary = entry as Dictionary
		var qid: int = q.get("id", 0)

		# Check turn-in
		var ti_name: String = q.get("turnin_npc_name", "").to_lower()
		var ti_type: int = int(q.get("turnin_npc_type", -1))
		var matches_turnin: bool = false
		if ti_name != "" and name_lower.contains(ti_name):
			matches_turnin = true
		elif ti_type >= 0 and ti_type == npc_type:
			matches_turnin = true
		if matches_turnin and check_progress(char_dict, qid):
			return "?"

		# Check offer
		var giver_name: String = q.get("giver_npc_name", "").to_lower()
		var giver_type: int = int(q.get("giver_npc_type", -1))
		var matches_giver: bool = false
		if giver_name != "" and name_lower.contains(giver_name):
			matches_giver = true
		elif giver_type >= 0 and giver_type == npc_type:
			matches_giver = true
		if matches_giver and can_accept(char_dict, qid):
			has_offer = true

	return "!" if has_offer else ""
