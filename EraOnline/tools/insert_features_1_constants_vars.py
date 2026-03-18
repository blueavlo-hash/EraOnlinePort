"""
Insert Step 1: Add protocol constants and new state variables to game_server.gd
"""
import re

FILE = r"C:\eo3\EraOnline\scripts\server\game_server.gd"

with open(FILE, "r", encoding="utf-8") as f:
    content = f.read()

# ---- 1. Add protocol constants after existing quest consts ----
QUEST_CONST_BLOCK = """## Quest protocol constants
const C_QUEST_TALK    : int = 0x0070
const S_QUEST_OFFER   : int = 0x0071
const C_QUEST_ACCEPT  : int = 0x0072
const C_QUEST_TURNIN  : int = 0x0073
const S_QUEST_UPDATE  : int = 0x0074
const S_QUEST_COMPLETE: int = 0x0075"""

NEW_PROTOCOL_CONSTS = """## Quest protocol constants
const C_QUEST_TALK    : int = 0x0070
const S_QUEST_OFFER   : int = 0x0071
const C_QUEST_ACCEPT  : int = 0x0072
const C_QUEST_TURNIN  : int = 0x0073
const S_QUEST_UPDATE  : int = 0x0074
const S_QUEST_COMPLETE: int = 0x0075

## Addiction loop system protocol constants
const S_RARE_DROP_NOTIFY    : int = 0x0080
const S_ACHIEVEMENT_UNLOCK  : int = 0x0081
const S_BOUNTY_UPDATE       : int = 0x0090
const C_ENCHANT             : int = 0x00A0
const S_ENCHANT_RESULT      : int = 0x00A1
const C_LEADERBOARD_REQUEST : int = 0x00B0
const S_LEADERBOARD_DATA    : int = 0x00B1
const S_WORLD_EVENT_START   : int = 0x00C0
const S_WORLD_EVENT_END     : int = 0x00C1
const S_TITLE_UPDATE        : int = 0x00D0
const S_TOURNEY_START       : int = 0x00E0
const S_TOURNEY_END         : int = 0x00E1
const S_TOURNEY_SCORES      : int = 0x00E2
const S_LOGIN_REWARD        : int = 0x00F0"""

if "S_RARE_DROP_NOTIFY" not in content:
    content = content.replace(QUEST_CONST_BLOCK, NEW_PROTOCOL_CONSTS, 1)
    print("Added protocol constants.")
else:
    print("Protocol constants already present, skipping.")

# ---- 2. Add BOSS_DEFS and ACHIEVEMENTS and TITLE_DEFS constants ----
# Insert after TOWN_MAPS const (which is right before the var declarations)
TOWN_MAPS_LINE = "const TOWN_MAPS: Array = [1, 2, 3, 18, 79, 80, 81, 82, 83, 84, 85, 86, 115, 140, 142, 143, 144, 145, 146]"

BOSS_AND_ACHIEVE_CONSTS = """const TOWN_MAPS: Array = [1, 2, 3, 18, 79, 80, 81, 82, 83, 84, 85, 86, 115, 140, 142, 143, 144, 145, 146]

## Boss monster definitions
const BOSS_DEFS: Array = [
\t{"map_id": 3,   "npc_index": 47, "name": "The Dark Stalker",    "spawn_interval": 3600.0, "loot_bonus": 3},
\t{"map_id": 18,  "npc_index": 53, "name": "The Alpha Wolf",       "spawn_interval": 4500.0, "loot_bonus": 4},
\t{"map_id": 80,  "npc_index": 55, "name": "The Iron Golem",       "spawn_interval": 5400.0, "loot_bonus": 5},
\t{"map_id": 115, "npc_index": 45, "name": "The Serpent Queen",    "spawn_interval": 6300.0, "loot_bonus": 6},
\t{"map_id": 140, "npc_index": 51, "name": "The Gremlin Warlord",  "spawn_interval": 7200.0, "loot_bonus": 7},
]

## Achievement definitions
const ACHIEVEMENTS: Array = [
\t{"id": 1,  "name": "First Blood",      "desc": "Kill your first monster",          "event": "kills",    "threshold": 1,    "gold": 50,   "xp": 100},
\t{"id": 2,  "name": "Monster Slayer",   "desc": "Kill 100 monsters",                "event": "kills",    "threshold": 100,  "gold": 200,  "xp": 500},
\t{"id": 3,  "name": "Legendary Hunter", "desc": "Kill 1000 monsters",               "event": "kills",    "threshold": 1000, "gold": 1000, "xp": 2000},
\t{"id": 4,  "name": "Apprentice Smith", "desc": "Craft your first item",            "event": "crafts",   "threshold": 1,    "gold": 50,   "xp": 100},
\t{"id": 5,  "name": "Master Craftsman", "desc": "Craft 100 items",                  "event": "crafts",   "threshold": 100,  "gold": 500,  "xp": 1000},
\t{"id": 6,  "name": "Fisherman",        "desc": "Catch your first fish",            "event": "fish",     "threshold": 1,    "gold": 25,   "xp": 50},
\t{"id": 7,  "name": "Angler",           "desc": "Catch 50 fish",                    "event": "fish",     "threshold": 50,   "gold": 200,  "xp": 400},
\t{"id": 8,  "name": "Wealthy",          "desc": "Accumulate 10,000 gold",           "event": "gold",     "threshold": 10000,"gold": 500,  "xp": 0},
\t{"id": 9,  "name": "Explorer",         "desc": "Visit 10 different maps",          "event": "maps",     "threshold": 10,   "gold": 200,  "xp": 500},
\t{"id": 10, "name": "Veteran",          "desc": "Reach level 20",                   "event": "level",    "threshold": 20,   "gold": 1000, "xp": 0},
\t{"id": 11, "name": "Champion",         "desc": "Reach level 50",                   "event": "level",    "threshold": 50,   "gold": 5000, "xp": 0},
\t{"id": 12, "name": "Socialite",        "desc": "Complete 5 quests",                "event": "quests",   "threshold": 5,    "gold": 300,  "xp": 600},
\t{"id": 13, "name": "Bounty Hunter",    "desc": "Collect your first bounty",        "event": "bounties", "threshold": 1,    "gold": 100,  "xp": 200},
\t{"id": 14, "name": "PK Warning",       "desc": "Kill another player",              "event": "pks",      "threshold": 1,    "gold": 0,    "xp": 0},
\t{"id": 15, "name": "Enchanter",        "desc": "Enchant an item to +3",            "event": "enchant3", "threshold": 1,    "gold": 500,  "xp": 1000},
]

## Title definitions (use achievement_progress counters)
const TITLE_DEFS: Array = [
\t{"title": "Warrior",       "event": "kills",    "threshold": 50},
\t{"title": "Slayer",        "event": "kills",    "threshold": 500},
\t{"title": "Legend",        "event": "kills",    "threshold": 2000},
\t{"title": "Apprentice",    "event": "crafts",   "threshold": 10},
\t{"title": "Craftsman",     "event": "crafts",   "threshold": 100},
\t{"title": "Master Smith",  "event": "crafts",   "threshold": 500},
\t{"title": "Angler",        "event": "fish",     "threshold": 20},
\t{"title": "Explorer",      "event": "maps",     "threshold": 15},
\t{"title": "Champion",      "event": "level",    "threshold": 30},
\t{"title": "Hero",          "event": "level",    "threshold": 50},
\t{"title": "Merchant",      "event": "gold",     "threshold": 50000},
\t{"title": "Bounty Hunter", "event": "bounties", "threshold": 5},
\t{"title": "Enchanter",     "event": "enchant3", "threshold": 3},
]

## Enchanting constants
const ENCHANT_MATERIAL_OBJ_TYPES: Array = [32, 20, 27]  # ore, logs, steel
const ENCHANT_MATERIAL_REQUIRED: Array = [2, 5, 10, 20]  # materials for +1,+2,+3,+4
const ENCHANT_SUCCESS_RATES: Array = [0.90, 0.70, 0.45, 0.20]
const ENCHANT_BREAK_CHANCE: Array  = [0.00, 0.05, 0.15, 0.35]

## World event constants
const WORLD_EVENT_INTERVAL: float = 3600.0
const WORLD_EVENT_TOWNS: Array = [3, 18, 80]
const WORLD_EVENT_NPC_WAVES: Dictionary = {
\t3:   [47, 47, 48, 48],
\t18:  [53, 53, 47, 48],
\t80:  [51, 51, 55, 47],
}

## Tournament constants
const TOURNEY_INTERVAL:  float = 7200.0
const TOURNEY_DURATION:  float = 600.0
const TOURNEY_PRIZES:    Array = [1000, 500, 250]"""

if "BOSS_DEFS" not in content:
    content = content.replace(TOWN_MAPS_LINE, BOSS_AND_ACHIEVE_CONSTS, 1)
    print("Added BOSS_DEFS, ACHIEVEMENTS, TITLE_DEFS and other constants.")
else:
    print("BOSS_DEFS already present, skipping.")

# ---- 3. Add new state variables after existing var _admin_names line ----
ADMIN_NAMES_LINE = "var _admin_names: Array      = []   # usernames from admins.txt, loaded at startup"

NEW_STATE_VARS = """var _admin_names: Array      = []   # usernames from admins.txt, loaded at startup

## Addiction loop systems state
var _boss_timers:      Dictionary = {}   # map_id -> time_until_spawn (seconds)
var _boss_instances:   Dictionary = {}   # map_id -> npc instance_id (0 = not spawned)
var _world_event_acc:  float = 0.0
var _world_event_active: bool = false
var _world_event_map:  int = 0
var _world_event_npcs: Array = []        # instance_ids of event-spawned NPCs
var _world_event_end_at: float = 0.0
var _tourney_acc:      float = 0.0
var _tourney_active:   bool = false
var _tourney_scores:   Dictionary = {}   # peer_id -> {name, best_catch}
var _tourney_end_at:   float = 0.0
var _leaderboards:     Dictionary = {
\t"kills":  [],
\t"crafts": [],
\t"level":  [],
\t"fishing":[],
}"""

if "_boss_timers" not in content:
    content = content.replace(ADMIN_NAMES_LINE, NEW_STATE_VARS, 1)
    print("Added new state variables.")
else:
    print("State variables already present, skipping.")

with open(FILE, "w", encoding="utf-8") as f:
    f.write(content)

print("Step 1 complete.")
