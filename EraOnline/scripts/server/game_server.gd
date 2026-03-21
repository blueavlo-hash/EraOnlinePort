extends Node
## Era Online - Authoritative Game Server
## Launch with:  godot --headless -- --server
##
## Security model:
##   Clients send intents (move direction, attack target, equip slot).
##   Server validates every action, calculates all outcomes, broadcasts results.
##   No damage, gold, XP, or position change is ever trusted from the client.

# Force-compile dependencies so their class_names are registered before type-checking.
const _ServerClientSCR  = preload("res://scripts/server/server_client.gd")
const _ServerDBSCR      = preload("res://scripts/server/server_db.gd")
const _ServerCombatSCR  = preload("res://scripts/server/server_combat.gd")
const _NetProtocolSCR   = preload("res://scripts/shared/net_protocol.gd")
const _ServerQuestsSCR  = preload("res://scripts/server/server_quests.gd")

const PORT          : int   = 6969
const TICK_RATE     : float = 1.0 / 30.0   # 30 Hz game tick
const REGEN_INTERVAL: float = 5.0           # HP/MP/STA regen every 5 s
const SAVE_INTERVAL : float = 60.0          # Autosave every 60 s
const NEARBY_RANGE  : int   = 15            # Tiles considered "visible"
const SERVER_SECRET : String = "EraOnlineSecret2025ChangeInProd!"

## Quest protocol constants
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
const S_LOGIN_REWARD        : int = 0x00F0
const S_TIME_OF_DAY         : int = 0x0100

## Shop protocol constants
const C_SHOP_OPEN     : int = 0x0030
const S_SHOP_LIST     : int = 0x0031
const C_BUY           : int = 0x0032
const S_BUY_RESULT    : int = 0x0033
const S_SPELL_CAST    : int = 0x0300
const S_SPELL_HIT     : int = 0x0301
const S_SPELL_CHAIN   : int = 0x0302
const S_STATUS_APPLIED: int = 0x0303
const S_STATUS_REMOVED: int = 0x0304
const S_SPELLBOOK     : int = 0x0305
const S_SPELL_UNLOCK  : int = 0x0306
const S_SPELL_SHOP    : int = 0x0307
const C_BUY_SPELL     : int = 0x010A

## NPC system constants
const NPC_ID_BASE     : int   = 10001   # NPC instance IDs start here (above player peer_ids)
const NPC_AI_INTERVAL : float = 0.5
const NPC_DETECT_RANGE: int   = 8       # tiles NPC can see players
const NPC_ATTACK_RANGE: int      = 2    # tiles NPC melee can reach
const PLAYER_MELEE_RANGE: int    = 1    # tiles player basic melee can reach
const RANGED_ATTACK_RANGE: int   = 10   # tiles for bow/ranged attacks
const ARROW_OBJ_TYPE: int      = 18     # obj_type value for arrow stacks
const NPC_RESPAWN_SECS: float = 30.0
const NPC_IDLE_ACTION_MIN: float = 1.2
const NPC_IDLE_ACTION_MAX: float = 2.4
const NPC_CHASE_ACTION_MIN: float = 0.7
const NPC_CHASE_ACTION_MAX: float = 1.3
const NPC_ATTACK_COOLDOWN_MIN: float = 1.1
const NPC_ATTACK_COOLDOWN_MAX: float = 1.8
const SHOP_BUY_PRICE_MULT:  float = 1.0   # Players buy at full item value
const SHOP_SELL_PRICE_MULT: float = 0.3   # Players sell back at 30% of value

## ---------------------------------------------------------------------------
## Sound number constants — match VB6 Declarations.bas SOUND_* values exactly.
## Each number corresponds to snd{N}.wav in assets/sounds/.
## ---------------------------------------------------------------------------
const SND_BUMP          : int =  1   # Wall bump / blocked movement
const SND_SWING         : int =  2   # Melee weapon swing (miss/attack start)
const SND_WARP          : int =  3   # Tile warp / teleport
const SND_PAPER         : int =  4   # Paper / parchment (crafting blueprints)
const SND_DRAGFISH      : int =  5   # Fishing drag
const SND_FISHINGPOLE   : int =  6   # Fishing cast
const SND_BURN          : int =  7   # Fire / burning
const SND_COINS         : int =  8   # Gold / coins (pickup, buy, sell)
const SND_NIGHTLOOP     : int =  9   # Night ambient (loop)
const SND_FIREBALL      : int = 10   # Fireball spell
const SND_FIREBALL2     : int = 11   # Fireball variant
const SND_FOLDCLOTHING  : int = 12   # Tailoring / folding cloth
const SND_FORRESTLOOP   : int = 13   # Forest ambient loop
const SND_FORRESTLOOP2  : int = 14   # Forest ambient loop 2
const SND_FEMALESCREAM  : int = 15   # Female player hit
const SND_SPELLEFFECT1  : int = 16   # Generic spell effect 1
const SND_HAMMERING     : int = 17   # Hammering (blacksmithing)
const SND_LIGHTNING     : int = 18   # Lightning spell
const SND_LOCKPICKING   : int = 19   # Lockpicking skill
const SND_MALEHURT      : int = 20   # Male player hit
const SND_MALEHURT2     : int = 21   # Male player hit 2
const SND_MEDOWLOOP     : int = 22   # Meadow ambient loop
const SND_METALHIT      : int = 23   # Metal-on-metal hit (armored melee)
const SND_SPELLEFFECT2  : int = 24   # Generic spell effect 2
const SND_SAILING       : int = 25   # Sailing / water
const SND_SAW           : int = 26   # Carpentry saw
const SND_SHORE         : int = 27   # Shoreline ambient
const SND_SMITHING      : int = 28   # Blacksmith anvil strike
const SND_SPELLEFFECT3  : int = 29   # Generic spell effect 3
const SND_SPELLEFFECT4  : int = 30   # Generic spell effect 4
const SND_SPELLEFFECT5  : int = 31   # Generic spell effect 5
const SND_STREAM        : int = 32   # Stream / water ambient
const SND_SWAMPLOOP     : int = 33   # Swamp ambient loop
const SND_SWORDSWING    : int = 34   # Sword swing (crafting, skill use)
const SND_SWORDHIT      : int = 35   # Sword hit variant 1
const SND_SWORDHIT2     : int = 36   # Sword hit variant 2 (melee hit on target)
const SND_WINDLOOP      : int = 37   # Wind ambient loop
const SND_STORMLOOP     : int = 38   # Storm ambient loop
const SND_SPELLEFFECT6  : int = 39   # Generic spell effect 6
const SND_CHOPPING      : int = 40   # Lumberjacking chop
const SND_MEDIVAL       : int = 41   # Medieval ambience
const SND_CHORUS        : int = 42   # Level-up / triumph chime
const SND_THUNDER       : int = 43   # Thunder (weather)
const SND_BIRDS         : int = 44   # Birdsong 1
const SND_SNAKE         : int = 45   # Snake NPC sound
const SND_SHEEP         : int = 46   # Sheep NPC sound
const SND_MONSTER1      : int = 47   # Generic monster sound 1
const SND_MONSTER2      : int = 48   # Generic monster sound 2
const SND_COW           : int = 49   # Cow NPC sound
const SND_COW2          : int = 50   # Cow NPC sound 2
const SND_GREMLIN       : int = 51   # Gremlin NPC sound
const SND_HORSE         : int = 52   # Horse NPC sound
const SND_WOLF          : int = 53   # Wolf NPC sound
const SND_CHICKEN       : int = 54   # Chicken NPC sound
const SND_ROAR          : int = 55   # Roar (large monster)
const SND_LAUGHEVIL     : int = 56   # Evil laugh
const SND_HEART         : int = 57   # Heartbeat (low HP warning, heal spells)
const SND_CLICK         : int = 58   # UI click / button
const SND_BIRDS2        : int = 59   # Birdsong 2
const SND_BEE           : int = 60   # Bee / insect ambient

## Semantic aliases for the most common gameplay events.
const SOUND_MELEE_HIT   : int = SND_SWORDHIT2   # 36 — hit connects on any target
const SOUND_NPC_DEATH   : int = SND_MALEHURT2    # 21 — NPC death grunt
const SOUND_PLAYER_HIT  : int = SND_MALEHURT     # 20 — player struck by NPC
const SOUND_LEVEL_UP    : int = SND_CHORUS       # 42 — level-up chime
const SOUND_SPELL_CAST  : int = SND_SPELLEFFECT1 # 16 — generic spell cast
const SOUND_ITEM_PICKUP : int = SND_COINS        #  8 — item/gold pickup
const SOUND_ITEM_DROP   : int = SND_PAPER        #  4 — item dropped to ground

## GRH index for the lying human corpse sprite (file grh403.png, OBJ 199)
const CORPSE_GRH        : int = 503

## Caster / ranged AI
const NPC_CASTER_RANGE        : int   = 6
const NPC_SPELL_COOLDOWN_MIN  : float = 2.5
const NPC_SPELL_COOLDOWN_MAX  : float = 4.0

## Flee / skittish AI
const NPC_FLEE_SPEED_MIN : float = 0.35
const NPC_FLEE_SPEED_MAX : float = 0.65

## Random encounter system
const ENCOUNTER_CHECK_INTERVAL : float = 15.0   # seconds between encounter rolls
const ENCOUNTER_CHANCE          : float = 0.12   # 12 % chance per check
const ENCOUNTER_COOLDOWN_MIN    : float = 90.0   # seconds before same player can be ambushed again
const ENCOUNTER_COOLDOWN_MAX    : float = 180.0
const ENCOUNTER_DESPAWN_SECS    : float = 120.0  # encounter NPCs despawn if nobody is engaged

## Town map IDs — no random encounters in these
const TOWN_MAPS: Array = [1, 2, 3, 18, 79, 80, 81, 82, 83, 84, 85, 86, 115, 140, 142, 143, 144, 145, 146]

## Boss monster definitions
const BOSS_DEFS: Array = [
	{"map_id": 3,   "npc_index": 47, "name": "The Dark Stalker",    "spawn_interval": 3600.0, "loot_bonus": 3},
	{"map_id": 18,  "npc_index": 53, "name": "The Alpha Wolf",       "spawn_interval": 4500.0, "loot_bonus": 4},
	{"map_id": 80,  "npc_index": 55, "name": "The Iron Golem",       "spawn_interval": 5400.0, "loot_bonus": 5},
	{"map_id": 115, "npc_index": 45, "name": "The Serpent Queen",    "spawn_interval": 6300.0, "loot_bonus": 6},
	{"map_id": 140, "npc_index": 51, "name": "The Gremlin Warlord",  "spawn_interval": 7200.0, "loot_bonus": 7},
]

## Achievement definitions
const ACHIEVEMENTS: Array = [
	{"id": 1,  "name": "First Blood",      "desc": "Kill your first monster",          "event": "kills",    "threshold": 1,    "gold": 50,   "xp": 100},
	{"id": 2,  "name": "Monster Slayer",   "desc": "Kill 100 monsters",                "event": "kills",    "threshold": 100,  "gold": 200,  "xp": 500},
	{"id": 3,  "name": "Legendary Hunter", "desc": "Kill 1000 monsters",               "event": "kills",    "threshold": 1000, "gold": 1000, "xp": 2000},
	{"id": 4,  "name": "Apprentice Smith", "desc": "Craft your first item",            "event": "crafts",   "threshold": 1,    "gold": 50,   "xp": 100},
	{"id": 5,  "name": "Master Craftsman", "desc": "Craft 100 items",                  "event": "crafts",   "threshold": 100,  "gold": 500,  "xp": 1000},
	{"id": 6,  "name": "Fisherman",        "desc": "Catch your first fish",            "event": "fish",     "threshold": 1,    "gold": 25,   "xp": 50},
	{"id": 7,  "name": "Angler",           "desc": "Catch 50 fish",                    "event": "fish",     "threshold": 50,   "gold": 200,  "xp": 400},
	{"id": 8,  "name": "Wealthy",          "desc": "Accumulate 10,000 gold",           "event": "gold",     "threshold": 10000,"gold": 500,  "xp": 0},
	{"id": 9,  "name": "Explorer",         "desc": "Visit 10 different maps",          "event": "maps",     "threshold": 10,   "gold": 200,  "xp": 500},
	{"id": 10, "name": "Veteran",          "desc": "Reach level 20",                   "event": "level",    "threshold": 20,   "gold": 1000, "xp": 0},
	{"id": 11, "name": "Champion",         "desc": "Reach level 50",                   "event": "level",    "threshold": 50,   "gold": 5000, "xp": 0},
	{"id": 12, "name": "Socialite",        "desc": "Complete 5 quests",                "event": "quests",   "threshold": 5,    "gold": 300,  "xp": 600},
	{"id": 13, "name": "Bounty Hunter",    "desc": "Collect your first bounty",        "event": "bounties", "threshold": 1,    "gold": 100,  "xp": 200},
	{"id": 14, "name": "PK Warning",       "desc": "Kill another player",              "event": "pks",      "threshold": 1,    "gold": 0,    "xp": 0},
	{"id": 15, "name": "Enchanter",        "desc": "Enchant an item to +3",            "event": "enchant3", "threshold": 1,    "gold": 500,  "xp": 1000},
]

## Title definitions (use achievement_progress counters)
const TITLE_DEFS: Array = [
	{"title": "Warrior",       "event": "kills",    "threshold": 50},
	{"title": "Slayer",        "event": "kills",    "threshold": 500},
	{"title": "Legend",        "event": "kills",    "threshold": 2000},
	{"title": "Apprentice",    "event": "crafts",   "threshold": 10},
	{"title": "Craftsman",     "event": "crafts",   "threshold": 100},
	{"title": "Master Smith",  "event": "crafts",   "threshold": 500},
	{"title": "Angler",        "event": "fish",     "threshold": 20},
	{"title": "Explorer",      "event": "maps",     "threshold": 15},
	{"title": "Champion",      "event": "level",    "threshold": 30},
	{"title": "Hero",          "event": "level",    "threshold": 50},
	{"title": "Merchant",      "event": "gold",     "threshold": 50000},
	{"title": "Bounty Hunter", "event": "bounties", "threshold": 5},
	{"title": "Enchanter",     "event": "enchant3", "threshold": 3},
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
	3:   [47, 47, 48, 48],
	18:  [53, 53, 47, 48],
	80:  [51, 51, 55, 47],
}

## Tournament constants
const TOURNEY_INTERVAL:  float = 7200.0
const TOURNEY_DURATION:  float = 600.0
const TOURNEY_PRIZES:    Array = [1000, 500, 250]

var _tcp_server:  TCPServer  = null
var _tls_options: TLSOptions = null
var _db = null

## peer_id → _ServerClientSCR
var _clients: Dictionary = {}
var _next_peer_id: int   = 1

var _tick_acc:   float = 0.0
var _regen_acc:  float = 0.0
var _save_acc:   float = 0.0

## NPC instances: instance_id → npc state dict
var _npcs: Dictionary = {}
var _npc_counter: int = NPC_ID_BASE
## Which maps have already had their NPCs spawned
var _spawned_maps: Dictionary = {}   # map_id → true
var _hardcoded_spawns: Dictionary = {}   # loaded once from npc_spawns.json
var _npc_ai_acc:      float = 0.0
var _housekeep_acc:   float = 0.0   # Drives respawn / status / ground-item cleanup
const HOUSEKEEP_INTERVAL: float = 1.0

## Per-AI-tick caches rebuilt once per _tick_npc_ai call.
## _ai_map_players: map_id → [{pid, x, y, level}]  — for NPC aggro/scan
## _ai_map_clients: map_id → [{pid, client}]        — for _broadcast_nearby
var _ai_map_players: Dictionary = {}
var _ai_map_clients: Dictionary = {}

## Random encounter tracking
var _encounter_acc: float = 0.0
## peer_id → time (absolute seconds) when next encounter is allowed
var _encounter_cooldowns: Dictionary = {}
## instance_id → time when the encounter NPC should auto-despawn if still un-engaged
var _encounter_despawn_at: Dictionary = {}

## Spell cooldowns per client: peer_id → { spell_id: expiry_ms }
var _spell_cooldowns: Dictionary = {}
## Per-character active status effects: char_id → {status_id → expiry_ms}
var _active_statuses: Dictionary = {}

## Weather state — mirrors VB6 Raining global
var _raining:       bool  = false
var _weather_acc:   float = 0.0
const WEATHER_INTERVAL := 300.0  # Check weather every 5 minutes
const RAIN_CHANCE      := 0.15   # 15% chance to start raining each check

## ---------------------------------------------------------------------------
## Gathering / timed skill system
## ---------------------------------------------------------------------------

## Per-player active skill timer: peer_id → {skill_id, time_left, tile, yield_obj}
var _skill_timers: Dictionary = {}

## Ground items: id → {id, obj_index, amount, map_id, x, y, expires_at}
var _ground_items: Dictionary = {}
var _ground_item_counter: int = 1
const GROUND_ITEM_TIMEOUT := 120.0   # 2 minutes before despawn

## Hardcoded tile exits: "map_id,x,y" → {map, x, y}
## Supplements map JSON exit data without requiring map file edits.
const HARDCODED_EXITS: Dictionary = {
	# Map 1 Bridge of Bondage → Map 2 (east end of bridge, y≈13-17, x≈83-87)
	"1,83,13": {"map": 2, "x": 13, "y": 19},
	"1,84,13": {"map": 2, "x": 13, "y": 19},
	"1,85,13": {"map": 2, "x": 13, "y": 19},
	"1,83,14": {"map": 2, "x": 13, "y": 19},
	"1,84,14": {"map": 2, "x": 13, "y": 19},
	"1,85,14": {"map": 2, "x": 13, "y": 19},
	"1,83,15": {"map": 2, "x": 13, "y": 19},
	"1,84,15": {"map": 2, "x": 13, "y": 19},
	"1,85,15": {"map": 2, "x": 13, "y": 19},
	"1,83,16": {"map": 2, "x": 13, "y": 19},
	"1,84,16": {"map": 2, "x": 13, "y": 19},
	"1,85,16": {"map": 2, "x": 13, "y": 19},
	"1,83,17": {"map": 2, "x": 13, "y": 19},
	"1,84,17": {"map": 2, "x": 13, "y": 19},
	"1,85,17": {"map": 2, "x": 13, "y": 19},
}

## Hardcoded resource nodes: "map_id,x,y" → skill_id
## Only needed for maps where resource objects haven't been placed in the map JSON yet.
## Map 3 resources are now in map_3.json directly, so this is empty.
const RESOURCE_NODES: Dictionary = {
	# Key format: "map_id,x,y"  Value: skill_id (5=Lumberjacking, 21=Mining)
	# Map 3 (Haven) - tiny starter cluster
	"3,5,5": 5,  "3,6,5": 5,  "3,5,7": 5,  "3,7,6": 5,
	"3,90,90": 21, "3,92,90": 21, "3,90,92": 21,
	# Map 4 (Eastern Forest near Haven)
	"4,18,20": 5, "4,20,20": 5, "4,22,19": 5,
	"4,25,18": 5, "4,28,22": 5, "4,30,20": 5,
	"4,15,30": 5, "4,18,28": 5, "4,22,32": 5, "4,26,28": 5,
	# Map 5 (Deep Forest)
	"5,15,30": 5, "5,20,28": 5, "5,25,30": 5, "5,18,35": 5,
	"5,22,40": 5, "5,28,38": 5, "5,30,42": 5,
	# Map 6 (Ancient Ruins - early ore)
	"6,40,40": 21, "6,42,38": 21, "6,38,42": 21, "6,45,45": 21,
	# Map 18 (Thornwall) - forest fringe
	"18,8,15": 5,  "18,10,18": 5, "18,12,15": 5,
	"18,15,8": 5,  "18,8,22": 5,  "18,10,25": 5,
	# Maps 21-25 (Forest cluster near Thornwall)
	"21,25,20": 5, "21,28,18": 5, "21,30,22": 5, "21,22,25": 5,
	"21,35,30": 5, "21,38,28": 5, "21,32,35": 5,
	"22,15,15": 5, "22,18,20": 5, "22,20,15": 5, "22,25,18": 5,
	"22,28,22": 5, "22,30,25": 5, "22,12,28": 5,
	"23,20,30": 5, "23,25,25": 5, "23,28,30": 5,
	"23,60,60": 21,"23,63,60": 21,"23,65,62": 21,"23,60,65": 21,
	"24,30,20": 5, "24,35,22": 5, "24,32,18": 5, "24,28,25": 5,
	"25,22,35": 5, "25,25,38": 5, "25,28,32": 5, "25,30,38": 5,
	# Map 79 (Western approach to Ironhaven)
	"79,20,50": 5, "79,22,55": 5, "79,18,58": 5,
	"79,60,40": 21,"79,65,42": 21,"79,62,45": 21,
	# Maps 82-86 (Mountain cluster near Ironhaven) - heavy ore
	"82,30,40": 21,"82,35,42": 21,"82,40,38": 21,
	"82,38,45": 21,"82,32,48": 21,"82,45,40": 21,
	"82,28,35": 21,"82,42,52": 21,"82,50,44": 21,
	"83,20,20": 21,"83,25,22": 21,"83,22,28": 21,
	"83,28,25": 21,"83,30,20": 21,"83,35,30": 21,
	"84,35,35": 21,"84,38,38": 21,"84,40,32": 21,"84,42,38": 21,
	"84,45,42": 21,"84,32,42": 21,
	"85,50,50": 21,"85,52,48": 21,"85,55,52": 21,"85,48,55": 21,
	"85,58,45": 21,"85,45,60": 21,
	"86,25,30": 21,"86,28,28": 21,"86,30,32": 21,
	# Maps 116-119 (Forest near Sealport)
	"116,15,20": 5,"116,18,25": 5,"116,20,18": 5,"116,22,22": 5,
	"117,30,30": 5,"117,32,28": 5,"117,28,35": 5,
	"118,12,40": 5,"118,15,38": 5,"118,18,42": 5,
	"119,25,45": 5,"119,28,42": 5,"119,22,48": 5,
	# Maps 141-146 (Shadowmoor region) - rich mixed
	"141,40,20": 21,"141,42,22": 21,"141,38,25": 21,
	"141,55,55": 5, "141,58,52": 5, "141,52,58": 5,
	"143,30,30": 21,"143,35,28": 21,"143,32,35": 21,"143,38,32": 21,
	"144,20,60": 5, "144,22,58": 5, "144,25,62": 5,
	"145,50,40": 21,"145,52,38": 21,"145,48,42": 21,
	"146,60,25": 5, "146,62,28": 5, "146,58,22": 5,
}


## Base skill duration in seconds (before skill-level speed bonus).
const SKILL_DURATIONS: Dictionary = {
	1:   8.0,   # Cooking
	4:   6.0,   # Carpenting (plank making)
	5:  10.0,   # Lumberjacking
	9:   7.0,   # Smelting (timed; smithing is instant)
	20: 12.0,   # Fishing
	21:  7.0,   # Mining
}

## Skill XP awarded per successful action (feeds individual skill levels, not character XP).
const SKILL_ACTION_XP: Dictionary = {
	1:  12,   # Cooking
	4:  10,   # Carpenting
	5:  10,   # Lumberjacking
	9:  25,   # Blacksmithing / Smelting
	20:  8,   # Fishing
	21: 15,   # Mining
}

## XP required to advance from `lv` to `lv+1`. Mirrors Constants.skill_xp_to_next().
static func _skill_xp_to_next(lv: int) -> int:
	if lv <= 0:   return 100
	if lv >= 100: return 0
	return roundi(100.0 * pow(1.09, lv - 1))

## Hunger/thirst restoration per item (obj_index → {hunger, thirst})
const FOOD_RESTORE: Dictionary = {
	6:   {"hunger": 15, "thirst": 0},   # Apple
	29:  {"hunger": 40, "thirst": 15},  # Bowl of Stew
	95:  {"hunger": 25, "thirst": 0},   # Bread
	99:  {"hunger": 20, "thirst": 0},   # Carrots
	117: {"hunger": 30, "thirst": 0},   # Meat
	135: {"hunger": 15, "thirst": 0},   # 1kg fish (raw — poisons)
	307: {"hunger": 30, "thirst": 5},   # Roasted fish
	308: {"hunger": 15, "thirst": 0},   # 2kg fish (raw)
	309: {"hunger": 15, "thirst": 0},   # 3kg fish (raw)
	310: {"hunger": 15, "thirst": 0},   # 4kg fish (raw)
	311: {"hunger": 15, "thirst": 0},   # 5kg fish (raw)
	312: {"hunger": 15, "thirst": 0},   # 6kg fish (raw)
	313: {"hunger": 15, "thirst": 0},   # 7kg fish (raw)
	314: {"hunger": 15, "thirst": 0},   # 8kg fish (raw)
	315: {"hunger": 15, "thirst": 0},   # 9kg fish (raw)
	316: {"hunger": 15, "thirst": 0},   # 10kg fish (raw)
	317: {"hunger": 15, "thirst": 0},   # 20kg fish (raw)
	156: {"hunger": 30, "thirst": 0},   # Roasted meat
	19:  {"hunger": 0,  "thirst": 25},  # Snake Wine
	20:  {"hunger": 0,  "thirst": 20},  # Cyclop Blood Ale
	21:  {"hunger": 5,  "thirst": 30},  # Grape Juice
	22:  {"hunger": 0,  "thirst": 35},  # Water Flask
	220: {"hunger": 20, "thirst": 10},  # Rations of Shimmer
}

## Poison state: peer_id → {expiry_ms, next_tick_ms}
var _poison_timers: Dictionary = {}

## Admin system runtime state
var _god_mode:    Dictionary = {}   # peer_id → true (invincible)
var _invisible:   Dictionary = {}   # peer_id → true (not broadcast to others)
var _mutes:       Dictionary = {}   # peer_id → expiry_ms (0 = permanent)
var _admin_names: Array      = []   # usernames from admins.txt, loaded at startup

## Addiction loop systems state
var _boss_timers:      Dictionary = {}   # map_id -> time_until_spawn (seconds)
var _boss_instances:   Dictionary = {}   # map_id -> npc instance_id (0 = not spawned)
var _world_event_acc:  float = 0.0
## Day/night cycle
var _time_of_day:      float = 8.0    # in-game hours, starts at 8am
var _time_acc:         float = 0.0    # accumulator for time advance
var _time_sync_acc:    float = 0.0    # timer for broadcasting time to clients
# Full 20-min real cycle = 24 in-game hours. Rate = 24.0 / (20.0 * 60.0) hours/second
const TIME_RATE:       float = 24.0 / 1200.0
const TIME_SYNC_INTERVAL: float = 10.0  # broadcast time every 10 real seconds
var _world_event_active: bool = false
var _world_event_map:  int = 0
var _world_event_npcs: Array = []        # instance_ids of event-spawned NPCs
var _world_event_end_at: float = 0.0
var _tourney_acc:      float = 0.0
var _tourney_active:   bool = false
var _tourney_scores:   Dictionary = {}   # peer_id -> {name, best_catch}
var _tourney_end_at:   float = 0.0
var _leaderboards:     Dictionary = {
	"kills":  [],
	"crafts": [],
	"level":  [],
	"fishing":[],
}
const HUNGER_DECAY_PER_TICK: float = 0.139  # per 5s regen tick (~60 min to empty, 33% faster than before)
const THIRST_DECAY_PER_TICK: float = 0.093  # per 5s regen tick (100/0.093 × 5s ≈ 90 min to empty)
const STARVATION_DMG_INTERVAL: int = 7      # ticks between starvation HP hits (7 × 5s = 35s → ~60 min to die at 100 HP)

## Object type IDs for tool detection (matches OBJ.dat ObjType field)
const PICKAXE_OBJ_TYPE:      int = 48   # Mining pickaxe
const LUMBERJACK_AXE_TYPE:   int = 17   # Lumberjack axe
const FISHING_ROD_TYPE:      int = 16   # Fishing rod
const HAMMER_OBJ_TYPE:       int = 33   # Blacksmith hammer (smelting)
const SAW_OBJ_TYPE:          int = 22   # Carpenter's saw (plank making)

## Object type IDs for resource tile detection
const ORE_OBJ_TYPE:  int = 32   # Ore node object
const LOG_OBJ_TYPE:  int = 20   # Wood/log object

## Object type IDs for crafting station detection (world objects)
const FORGE_OBJ_TYPE:          int = 50   # Smelting forge (OBJ318)
const ANVIL_OBJ_TYPE:          int = 51   # Anvil (OBJ319)
const COOKING_STATION_TYPES:   Array = [21, 34, 52]  # campfire, campfire2, cooking stove

## Hardcoded crafting station positions per map (server authority).
## Format: map_id -> Array of {x, y, obj_type}
## obj_type 21/34/52 = cooking  |  50 = forge  |  51 = anvil
const CRAFTING_STATIONS: Dictionary = {
	3:  [
		{"x": 15, "y": 8,  "obj_type": 21},
	],
	18: [
		{"x": 30, "y": 35, "obj_type": 52},
		{"x": 12, "y": 15, "obj_type": 21},
		{"x": 12, "y": 16, "obj_type": 34},
	],
	80: [
		{"x": 39, "y": 44, "obj_type": 50},
		{"x": 40, "y": 44, "obj_type": 51},
		{"x": 38, "y": 48, "obj_type": 52},
	],
	115: [
		{"x": 38, "y": 65, "obj_type": 52},
		{"x": 42, "y": 62, "obj_type": 21},
	],
	140: [
		{"x": 68, "y": 40, "obj_type": 50},
		{"x": 69, "y": 40, "obj_type": 51},
		{"x": 72, "y": 28, "obj_type": 52},
	],
	142: [
		{"x": 38, "y": 37, "obj_type": 50},
		{"x": 39, "y": 37, "obj_type": 51},
		{"x": 36, "y": 37, "obj_type": 52},
	],
}

const TOWN_FACTIONS: Dictionary = {
	"haven":      3,
	"thornwall":  18,
	"ironhaven":  80,
	"sealport":   115,
	"shadowmoor": 140,
}
const REP_NEUTRAL:   int = 0
const REP_FRIENDLY:  int = 100
const REP_HONORED:   int = 250
const REP_REVERED:   int = 500
const REP_MIN:       int = -500  # "Hated" floor — vendors refuse service below 0
const REP_MAX:       int = 800   # Cap so grinding doesn't make numbers absurd

## Faction rivalries: gaining rep with a faction penalises these rivals.
## Penalty rate = RIVAL_PENALTY × amount gained (rounded down).
const RIVAL_PENALTY: float = 0.6
const FACTION_RIVALS: Dictionary = {
	"haven":      ["shadowmoor"],
	"thornwall":  ["sealport", "shadowmoor"],
	"ironhaven":  ["sealport"],
	"sealport":   ["ironhaven", "thornwall"],
	"shadowmoor": ["haven", "thornwall"],
}

## Penance quest cost tiers (gold required to buy back 75 rep with a faction).
## Repeatable — each use deducts gold from the player and adds 75 rep.
const PENANCE_GOLD_COST: int = 500
const PENANCE_REP_GAIN:  int = 75

## Object type IDs for crafting
const BLACKSMITH_DRAWING_TYPE: int = 26  # Blacksmithing drawing/blueprint
const CARPENTRY_DRAWING_TYPE:  int = 25  # Carpentry drawing/blueprint
const RAW_MEAT_OBJ_TYPE:       int = 39  # Raw fish / uncooked meat

## Yield object indices (from objects.json)
const ORE_OBJ_INDEX:          int = 154  # "ore" — mining yield
const LOG_OBJ_INDEX:          int = 114  # "Log" — lumberjacking yield
const STEEL_OBJ_INDEX:        int = 153  # "a steel clump" — smelting output
const PLANK_OBJ_INDEX:        int = 148  # "Plank" — carpentry stage-1 output
const ROASTED_FISH_OBJ_INDEX: int = 307  # "roasted fish" — cooking output
const ROASTED_MEAT_OBJ_INDEX: int = 156  # "roasted meat" — cooking output
const RAW_FISH_MIN:           int = 308  # Random catch range lo
const RAW_FISH_MAX:           int = 317  # Random catch range hi

## Smelting / carpentry ratios (matches VB6 originals)
const SMELT_ORE_COST:    int = 2   # ore consumed per smelt
const SMELT_STEEL_YIELD: int = 4   # steel produced per smelt
const PLANK_LOG_COST:    int = 2   # logs consumed per plank batch
const PLANK_YIELD:       int = 4   # planks produced per batch

## Poison status
const POISON_STATUS_ID:    int   = 1
const POISON_DURATION_SEC: float = 60.0
const POISON_TICK_SEC:     float = 3.0
const POISON_TICK_DMG:     int   = 1

## Skill names 1-indexed (mirrors SkillProgressUI.SKILL_NAMES on the client)
const SKILL_NAMES: Array = [
	"",              # 0 — unused
	"Cooking",       # 1
	"Musicianship",  # 2
	"Tailoring",     # 3
	"Carpenting",    # 4
	"Lumberjacking", # 5
	"Tactics",       # 6
	"Disguise",      # 7
	"Merchant",      # 8
	"Blacksmithing", # 9
	"Hiding",        # 10
	"Magery",        # 11
	"Lockpicking",   # 12
	"Pickpocketing", # 13
	"Stealth",       # 14
	"Poisoning",     # 15
	"Swordsmanship", # 16
	"Parrying",      # 17
	"Animal Taming", # 18
	"Religion Lore", # 19
	"Fishing",       # 20
	"Mining",        # 21
	"Backstabbing",  # 22
	"Healing",       # 23
	"Surviving",     # 24
	"Etiquette",     # 25
	"Streetwise",    # 26
	"Meditating",    # 27
	"Archery",       # 28
]


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	print("[Server] Initialising Era Online server v0.1...")
	_db = _ServerDBSCR.new()

	_tls_options = _load_or_create_tls()
	if _tls_options == null:
		push_error("[Server] Failed to set up TLS — server cannot start.")
		return

	_tcp_server = TCPServer.new()
	var err := _tcp_server.listen(PORT)
	if err != OK:
		push_error("[Server] Cannot listen on port %d: %s" % [PORT, error_string(err)])
		return

	print("[Server] Listening on port %d (TLS)" % PORT)
	_load_admin_list()
	_start_status_server()

	# Initialise boss timers with staggered initial spawns
	for boss_def in BOSS_DEFS:
		var mid: int = int(boss_def["map_id"])
		_boss_timers[mid] = randf_range(
				float(boss_def["spawn_interval"]) * 0.3,
				float(boss_def["spawn_interval"]) * 0.7)
		_boss_instances[mid] = 0


func _process(delta: float) -> void:
	if _tcp_server == null:
		return

	_tick_status_server()

	# Accept new connections
	while _tcp_server.is_connection_available():
		var tcp_peer := _tcp_server.take_connection()
		var client := _ServerClientSCR.new(
			_next_peer_id, tcp_peer, _tls_options, Time.get_ticks_msec() / 1000.0)
		_clients[_next_peer_id] = client
		print("[Server] New connection peer_id=%d" % _next_peer_id)
		_next_peer_id += 1
		# Queue SERVER_HELLO after TLS handshake completes (done in _tick_clients)

	_tick_acc += delta
	while _tick_acc >= TICK_RATE:
		_tick_acc -= TICK_RATE
		_tick_clients(TICK_RATE)

	_regen_acc += delta
	if _regen_acc >= REGEN_INTERVAL:
		_regen_acc = 0.0
		_tick_regen()

	_save_acc += delta
	if _save_acc >= SAVE_INTERVAL:
		_save_acc = 0.0
		_save_all()

	var now := Time.get_ticks_msec() / 1000.0

	## Weather tick
	_weather_acc += delta
	if _weather_acc >= WEATHER_INTERVAL:
		_weather_acc = 0.0
		_tick_weather()

	## Day/night cycle
	_time_of_day = fmod(_time_of_day + TIME_RATE * delta, 24.0)
	_time_sync_acc += delta
	if _time_sync_acc >= TIME_SYNC_INTERVAL:
		_time_sync_acc = 0.0
		_broadcast_time_of_day()

	## Skill timers (must stay per-frame so durations are accurate)
	for pid in _skill_timers.keys():
		var st: Dictionary = _skill_timers[pid]
		st["time_left"] -= delta
		if st["time_left"] <= 0.0:
			_skill_timers.erase(pid)
			_complete_skill(pid, st["skill_id"], st["tile"],
					st.get("action", ""), st.get("aux", {}))
			break  # erase-safe: restart next frame

	## NPC AI tick (also handles encounter despawn)
	_npc_ai_acc += delta
	if _npc_ai_acc >= NPC_AI_INTERVAL:
		_npc_ai_acc = 0.0
		_tick_npc_ai(now)

	## Random encounter tick
	_encounter_acc += delta
	if _encounter_acc >= ENCOUNTER_CHECK_INTERVAL:
		_encounter_acc = 0.0
		_tick_random_encounters(now)

	## Housekeeping: NPC respawns, status effects, ground items — throttled to 1 Hz
	_housekeep_acc += delta
	if _housekeep_acc >= HOUSEKEEP_INTERVAL:
		_housekeep_acc = 0.0
		_tick_housekeep(now)

	## Boss spawn timers
	for _boss_map_id in _boss_timers.keys():
		_boss_timers[_boss_map_id] -= delta
		if _boss_timers[_boss_map_id] <= 0.0:
			_try_spawn_boss(_boss_map_id)
			break  # erase-safe: restart next frame

	## World event tick
	if not _world_event_active:
		_world_event_acc += delta
		if _world_event_acc >= WORLD_EVENT_INTERVAL:
			_world_event_acc = 0.0
			_start_world_event()
	else:
		if Time.get_ticks_msec() / 1000.0 >= _world_event_end_at:
			_end_world_event("The invasion has been repelled!" if _world_event_npcs.is_empty() else "The monsters retreated into the darkness.")

	## Fishing tournament tick
	if not _tourney_active:
		_tourney_acc += delta
		if _tourney_acc >= TOURNEY_INTERVAL:
			_tourney_acc = 0.0
			_start_fishing_tourney()
	else:
		if Time.get_ticks_msec() / 1000.0 >= _tourney_end_at:
			_end_fishing_tourney()


# ---------------------------------------------------------------------------
# Housekeeping tick (1 Hz) — NPC respawns, status effects, ground items
# ---------------------------------------------------------------------------

func _tick_housekeep(now: float) -> void:
	## NPC respawns
	for nid in _npcs:
		var npc: Dictionary = _npcs[nid]
		if npc["ai_state"] == "dead" and npc["data"].get("summoned_by", 0) == 0:
			if now >= float(npc["respawn_at"]):
				_respawn_npc(npc)

	## Status effect expiry — no .duplicate(); iterate values, collect expired keys
	var now_ms: int = Time.get_ticks_msec()
	for cid in _active_statuses:
		var char_statuses: Dictionary = _active_statuses[cid]
		var expired: Array = []
		for sid in char_statuses:
			if int(char_statuses[sid]) <= now_ms:
				expired.append(sid)
		for sid in expired:
			char_statuses.erase(sid)
			var cmap: int = -1
			if _clients.has(cid):
				cmap = _clients[cid].char.get("map_id", -1)
			if cmap >= 0:
				_broadcast_status_removed(cmap, cid, sid)
	# Clean up empty entries (safe separate pass)
	var empty_cids: Array = []
	for cid in _active_statuses:
		if _active_statuses[cid].is_empty():
			empty_cids.append(cid)
	for cid in empty_cids:
		_active_statuses.erase(cid)

	## Ground item expiry
	var expired_gids: Array = []
	for gid in _ground_items:
		if now >= float(_ground_items[gid]["expires_at"]):
			expired_gids.append(gid)
	for gid in expired_gids:
		_remove_ground_item(gid)

	## Poison ticks
	_tick_poison(now_ms)


# ---------------------------------------------------------------------------
# Client tick
# ---------------------------------------------------------------------------

func _tick_clients(delta: float) -> void:
	var to_remove: Array = []
	var time_now := Time.get_ticks_msec() / 1000.0

	for pid in _clients:
		var client = _clients[pid]

		# Send SERVER_HELLO once TLS handshake completes
		if client.state == _ServerClientSCR.State.HANDSHAKE:
			if client.tls != null and \
					client.tls.get_status() == StreamPeerTLS.STATUS_CONNECTED:
				client.server_nonce = Crypto.new().generate_random_bytes(
						NetProtocol.NONCE_SIZE)
				var w := NetProtocol.PacketWriter.new()
				w.write_u16(NetProtocol.PROTOCOL_VERSION)
				w.write_bytes(client.server_nonce)
				client.send_preauth(NetProtocol.MsgType.SERVER_HELLO, w.get_bytes())
				client.state = _ServerClientSCR.State.PROTO_WAIT
				client.flush()
			else:
				client.tls.poll()
			continue

		var messages: Array = client.tick(delta)
		for msg in messages:
			_dispatch(client, msg["type"], msg["payload"], time_now)

		if client.state == _ServerClientSCR.State.CLOSING:
			to_remove.append(pid)

	for pid in to_remove:
		_disconnect_client(pid)


# ---------------------------------------------------------------------------
# Message dispatch
# ---------------------------------------------------------------------------

func _dispatch(client, msg_type: int,
		payload: PackedByteArray, time_now: float) -> void:
	var r := NetProtocol.PacketReader.new(payload)

	match client.state:
		_ServerClientSCR.State.PROTO_WAIT:
			_handle_proto(client, msg_type, r, time_now)
		_ServerClientSCR.State.AUTHENTICATING:
			_handle_auth(client, msg_type, r, time_now)
		_ServerClientSCR.State.CHAR_SELECT:
			if not client.check_rate(msg_type, time_now):
				return
			_handle_char_select(client, msg_type, r)
		_ServerClientSCR.State.CONNECTED:
			if not client.check_rate(msg_type, time_now):
				return
			_handle_game(client, msg_type, r, time_now)


func _handle_proto(client, msg_type: int,
		r: NetProtocol.PacketReader, _time_now: float) -> void:
	if msg_type != NetProtocol.MsgType.CLIENT_HELLO:
		return
	client.client_nonce = r.read_bytes(NetProtocol.NONCE_SIZE)
	client.state = _ServerClientSCR.State.AUTHENTICATING


func _handle_auth(client, msg_type: int,
		r: NetProtocol.PacketReader, time_now: float) -> void:
	# Auth rate limiting
	if time_now - client.last_auth_time < NetProtocol.AUTH_ATTEMPT_WINDOW:
		client.auth_attempts += 1
	else:
		client.auth_attempts = 1
	client.last_auth_time = time_now
	if time_now < client.locked_until:
		_send_auth_fail(client, "Too many attempts. Try again later.")
		return
	if client.auth_attempts > NetProtocol.AUTH_MAX_ATTEMPTS:
		client.locked_until = time_now + NetProtocol.AUTH_LOCKOUT_SECS
		_send_auth_fail(client, "Account locked for 60 seconds.")
		return

	var username := r.read_str()
	var password := r.read_str()

	match msg_type:
		NetProtocol.MsgType.AUTH_LOGIN:
			if not _db.account_exists(username):
				_send_auth_fail(client, "Account not found.")
				return
			if not _db.verify_password(username, password):
				_send_auth_fail(client, "Incorrect password.")
				return
			# Ban check
			var acc_login: Dictionary = _db.load_account(username)
			if acc_login.get("banned", false):
				var ban_reason: String = acc_login.get("ban_reason", "You are banned from this server.")
				_send_auth_fail(client, "Banned: %s" % ban_reason)
				return
			_complete_auth(client, username)

		NetProtocol.MsgType.AUTH_REGISTER:
			var result: Dictionary = _db.create_account(username, password)
			if not result["ok"]:
				_send_auth_fail(client, result["reason"])
				return
			_complete_auth(client, username)


func _complete_auth(client, username: String) -> void:
	client.username = username

	# Derive session key and enter authenticated mode
	var secret := SERVER_SECRET.to_utf8_buffer()
	var session_id := _generate_session_id()
	client.session_key = NetProtocol.derive_session_key(
		secret, client.client_nonce, client.server_nonce, session_id)
	client.send_seq = 0
	client.recv_seq = 0

	# AUTH_OK: session_id:str, char_id:i32 (peer_id assigned now), char_name:str ("")
	var w := NetProtocol.PacketWriter.new()
	w.write_str(session_id)
	w.write_i32(client.peer_id)
	w.write_str("")
	client.send_preauth(NetProtocol.MsgType.AUTH_OK, w.get_bytes())
	client.state = _ServerClientSCR.State.CHAR_SELECT

	# Flush preauth queue before switching to authenticated sends
	client.flush()

	# Send character list (now using authenticated framing)
	_send_char_list(client)
	print("[Server] Auth OK: %s" % username)


func _handle_char_select(client, msg_type: int,
		r: NetProtocol.PacketReader) -> void:
	match msg_type:
		NetProtocol.MsgType.C_SELECT_CHAR:
			var name_str := r.read_str()
			var c: Dictionary = _db.get_char(client.username, name_str)
			if c.is_empty():
				_send_create_result(client, false, "Character not found.")
				return
			_enter_world(client, c)

		NetProtocol.MsgType.C_CREATE_CHAR:
			var name_str := r.read_str()
			var class_id := r.read_u8()
			var head_idx := r.read_i16()
			var body_idx := r.read_i16()
			var result: Dictionary = _create_character(client.username, name_str, class_id, head_idx, body_idx)
			if not result["ok"]:
				_send_create_result(client, false, result["reason"])
				return
			_send_create_result(client, true, "")
			var c: Dictionary = _db.get_char(client.username, name_str)
			_enter_world(client, c)

		NetProtocol.MsgType.C_DELETE_CHAR:
			_on_delete_char(client, r)


func _on_delete_char(client, r: NetProtocol.PacketReader) -> void:
	if client.state != _ServerClientSCR.State.CHAR_SELECT:
		return
	var char_name: String = r.read_str()
	# Verify the character belongs to this account
	var chars: Array = _db.get_chars(client.username)
	var found := false
	for cd in chars:
		if cd.get("name", "") == char_name:
			found = true
			break
	if not found:
		var w := NetProtocol.PacketWriter.new()
		w.write_u8(0); w.write_str("Character not found.")
		client.send_auth(NetProtocol.MsgType.S_DELETE_RESULT, w.get_bytes())
		return
	_db.delete_char(client.username, char_name)
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(1); w.write_str("")
	client.send_auth(NetProtocol.MsgType.S_DELETE_RESULT, w.get_bytes())
	# Resend updated char list
	_send_char_list(client)


func _handle_game(client, msg_type: int,
		r: NetProtocol.PacketReader, time_now: float) -> void:
	match msg_type:
		NetProtocol.MsgType.C_MOVE:
			_on_move(client, r.read_u8(), time_now)

		NetProtocol.MsgType.C_ATTACK:
			_on_attack(client, r.read_i32(), time_now)

		NetProtocol.MsgType.C_EQUIP:
			_on_equip(client, r.read_u8())

		NetProtocol.MsgType.C_UNEQUIP:
			_on_unequip(client, r.read_u8())

		NetProtocol.MsgType.C_CHAT:
			_on_chat(client, r.read_str())

		NetProtocol.MsgType.C_PING:
			var ts := r.read_i64()
			var pw := NetProtocol.PacketWriter.new()
			pw.write_i64(ts)
			client.send_auth(NetProtocol.MsgType.S_PONG, pw.get_bytes())

		NetProtocol.MsgType.C_DROP:
			_on_drop(client, r.read_u8(), r.read_u16())

		NetProtocol.MsgType.C_PICKUP:
			_on_pickup(client, r.read_i16())

		NetProtocol.MsgType.C_USE_ITEM:
			_on_use_item(client, r.read_u8())

		NetProtocol.MsgType.C_CAST_SPELL:
			var spell_id  := r.read_u8()
			var target_id := r.read_i32()
			var stx       := r.read_i16()
			var sty       := r.read_i16()
			_handle_cast_spell(client, spell_id, target_id, stx, sty)

		NetProtocol.MsgType.C_BUY_SPELL:
			_handle_buy_spell(client, r.read_i32(), r.read_u8())

		NetProtocol.MsgType.C_LEARN_ABILITY:
			_on_learn_ability(client, r)

		NetProtocol.MsgType.C_SAVE_HOTBAR:
			_on_save_hotbar(client, r)

		NetProtocol.MsgType.C_USE_SKILL:
			var skill_id: int  = r.read_u8()
			var tile_x:   int  = r.read_i16()
			var tile_y:   int  = r.read_i16()
			_handle_use_skill(client, skill_id, Vector2i(tile_x, tile_y))

		C_SHOP_OPEN:
			_on_shop_open(client, r.read_i32())

		C_BUY:
			_on_buy(client, r.read_i32(), r.read_i16(), r.read_u16())

		NetProtocol.MsgType.C_SELL:
			_on_sell(client, r.read_i32(), r.read_u8())

		NetProtocol.MsgType.C_BANK_OPEN:
			_on_bank_open(client, r.read_i32())

		NetProtocol.MsgType.C_BANK_DEPOSIT:
			_on_bank_deposit(client, r.read_u8())

		NetProtocol.MsgType.C_BANK_WITHDRAW:
			_on_bank_withdraw(client, r.read_u8(), r.read_i16())

		NetProtocol.MsgType.C_BANK_DEPOSIT_GOLD:
			_on_bank_deposit_gold(client, r.read_i32())

		NetProtocol.MsgType.C_BANK_WITHDRAW_GOLD:
			_on_bank_withdraw_gold(client, r.read_i32())

		NetProtocol.MsgType.C_TRADE_REQUEST:
			_on_trade_request(client, r.read_i32())

		NetProtocol.MsgType.C_TRADE_RESPOND:
			_on_trade_respond(client, r.read_u8() != 0)

		NetProtocol.MsgType.C_TRADE_OFFER:
			_on_trade_offer(client, r.read_u8())

		NetProtocol.MsgType.C_TRADE_RETRACT:
			_on_trade_retract(client, r.read_u8())

		NetProtocol.MsgType.C_TRADE_CONFIRM:
			_on_trade_confirm(client)

		NetProtocol.MsgType.C_TRADE_CANCEL:
			_on_trade_cancel(client)

		C_QUEST_TALK:
			_on_quest_talk(client, r.read_i32())

		C_QUEST_ACCEPT:
			_on_quest_accept(client, r.read_u16())

		C_QUEST_TURNIN:
			_on_quest_turnin(client, r.read_u16())

		C_ENCHANT:
			_on_enchant(client, r.read_u8(), r.read_u8())

		C_LEADERBOARD_REQUEST:
			_on_leaderboard_request(client, r.read_u8())

		NetProtocol.MsgType.C_PENANCE:
			_on_penance(client, r.read_str())


# ---------------------------------------------------------------------------
# Game actions
# ---------------------------------------------------------------------------

func _on_move(client, direction: int, time_now: float) -> void:
	# Movement throttle: max 15 moves/sec already handled by rate limiter.
	# Additional: no more than 1 move per ~67ms to prevent micro-spam.
	if time_now - client.last_move_time < 0.06:
		return
	client.last_move_time = time_now

	var c: Dictionary = client.char
	var cx: int = c.get("x", 1)
	var cy: int = c.get("y", 1)
	var map_id: int = c.get("map_id", 1)

	var dx := 0
	var dy := 0
	var heading := direction
	match direction:
		1: dy = -1  # North
		2: dx =  1  # East
		3: dy =  1  # South
		4: dx = -1  # West
		_: return

	var nx := cx + dx
	var ny := cy + dy

	# Reject moves off the map edge — cardinal exits fire from within buffer zones.
	if nx < 1 or nx > 100 or ny < 1 or ny > 100:
		return

	var tile := GameData.get_map_tile(map_id, nx, ny)
	if tile.get("blocked", 0) != 0:
		return

	c["x"]       = nx
	c["y"]       = ny
	c["heading"] = heading

	# Broadcast movement to all nearby clients (including mover)
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(client.peer_id)
	w.write_i16(nx)
	w.write_i16(ny)
	w.write_u8(heading)
	_broadcast_nearby(map_id, nx, ny, NetProtocol.MsgType.S_MOVE_CHAR, w.get_bytes(), -1)

	# Hardcoded exits take priority (supplements map JSON data).
	var hc_key: String = "%d,%d,%d" % [map_id, nx, ny]
	if HARDCODED_EXITS.has(hc_key):
		var hc: Dictionary = HARDCODED_EXITS[hc_key]
		_teleport(client, hc["map"], hc["x"], hc["y"])
		return

	# Tile exit from map data.
	var exit_d: Dictionary = tile.get("exit", {})
	if not exit_d.is_empty():
		var dest_map: int = exit_d.get("map", 0)
		var dest_x: int   = exit_d.get("x", nx)
		var dest_y: int   = exit_d.get("y", ny)
		if dest_map > 1:
			_teleport(client, dest_map, dest_x, dest_y)
			return

	# Cardinal exits (VB6: y<7=North, y>94=South, x<9=West, x>92=East).
	# Skip map 1 (ocean): it has no return exits yet so players would get stranded.
	var map_data := GameData.get_map(map_id)
	if ny < 7 and map_data.get("north_exit", 0) > 1:
		_teleport(client, map_data["north_exit"], nx, 94)
	elif ny > 94 and map_data.get("south_exit", 0) > 1:
		_teleport(client, map_data["south_exit"], nx, 7)
	elif nx < 9 and map_data.get("west_exit", 0) > 1:
		_teleport(client, map_data["west_exit"], 91, ny)
	elif nx > 92 and map_data.get("east_exit", 0) > 1:
		_teleport(client, map_data["east_exit"], 10, ny)


## Find the nearest walkable tile at or near (x, y) on map_id.
## Prevents teleporting players into blocked/water tiles.
func _find_safe_spawn(map_id: int, x: int, y: int) -> Vector2i:
	var preferred := Vector2i(x, y)
	if _spawn_walkable(map_id, preferred):
		return preferred
	var offsets := [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1),
					Vector2i(1,1), Vector2i(-1,1), Vector2i(1,-1), Vector2i(-1,-1)]
	for off in offsets:
		var t: Vector2i = preferred + off
		if _spawn_walkable(map_id, t):
			return t
	return preferred  # fallback — map data may be corrupt


func _spawn_walkable(map_id: int, t: Vector2i) -> bool:
	return t.x >= 1 and t.x <= 100 and t.y >= 1 and t.y <= 100 \
			and GameData.get_map_tile(map_id, t.x, t.y).get("blocked", 0) == 0


## Map IDs that are blocked from teleport/warp (purely cinematic/inaccessible maps).
## Map 1 is NOT restricted: it is a valid in-game town with vendors that players
## can reach by walking the bridge from map 2.  The _enter_world SPAWN_MAP redirect
## already handles newly-logged-in characters whose saved map_id == 1.
const RESTRICTED_MAPS: Array = []
## Default spawn fallback for new characters and death-respawn.
const SPAWN_MAP: int = 3
const SPAWN_X:   int = 10
const SPAWN_Y:   int = 10

func _teleport(client, map_id: int, x: int, y: int) -> void:
	# Redirect restricted maps to spawn.
	if map_id in RESTRICTED_MAPS:
		map_id = SPAWN_MAP
		x      = SPAWN_X
		y      = SPAWN_Y
	# x=0 or y=0 means "use the map's start_pos" (VB6 convention for dungeon entries).
	if x <= 0 or y <= 0:
		var dest_map_data := GameData.get_map(map_id)
		var sp: Dictionary = dest_map_data.get("start_pos", {})
		x = int(sp.get("x", 10))
		y = int(sp.get("y", 10))
		if x <= 0: x = 10
		if y <= 0: y = 10
	# Validate destination is not blocked/water.
	var safe := _find_safe_spawn(map_id, x, y)
	# Notify old-area clients this character left
	_broadcast_remove(client)
	client.char["map_id"] = map_id
	client.char["x"]      = safe.x
	client.char["y"]      = safe.y
	_enter_world(client, client.char)


func _on_attack(client, target_id: int, _time_now: float) -> void:
	## Handles player attack.
	## target_id: >= NPC_ID_BASE = NPC instance, > 0 = player peer_id,
	##            -1 = auto-target nearest, 0 = invalid.
	var attacker: Dictionary = client.char
	var map_id: int = attacker.get("map_id", 0)
	var ax: int = attacker.get("x", 0)
	var ay: int = attacker.get("y", 0)

	# Determine attack range based on equipped weapon type
	var wpn_idx: int = attacker.get("equipment", {}).get("weapon", 0)
	var wpn_data: Dictionary = GameData.get_object(wpn_idx) if wpn_idx > 0 else {}
	var is_ranged: bool = wpn_data.get("category", "") == "Archery"
	var attack_range: int = RANGED_ATTACK_RANGE if is_ranged else PLAYER_MELEE_RANGE

	# Ranged attack requires arrows in inventory
	if is_ranged and not _has_arrows(attacker):
		return

	## --- Attack a specific NPC by instance ID ---
	if target_id >= NPC_ID_BASE:
		if not _npcs.has(target_id):
			return
		var npc_target: Dictionary = _npcs[target_id]
		if npc_target["ai_state"] == "dead":
			return
		if npc_target["map_id"] != map_id:
			return
		# Block attacking service/vendor NPCs — only npc_type==1 (combat) can be attacked.
		if npc_target["data"].get("npc_type", 0) != 1:
			return
		var dist := maxi(abs(npc_target["x"] - ax), abs(npc_target["y"] - ay))
		if dist > attack_range:
			return
		if is_ranged:
			_consume_arrow(attacker)
			_broadcast_projectile(map_id, client.peer_id, target_id, ax, ay, 0)
		_player_attack_npc(client, npc_target)
		return

	## --- Auto-target nearest (target_id == -1) or specific player (target_id > 0) ---
	## Collect candidates: nearby players and nearby NPCs.
	var best_dist := attack_range + 1
	var best_player_client = null
	var best_npc: Dictionary = {}
	var heading: int = attacker.get("heading", 3)

	# Search players
	for pid in _clients:
		if pid == client.peer_id:
			continue
		if target_id > 0 and pid != target_id:
			continue
		var target_client = _clients[pid]
		if target_client.state != _ServerClientSCR.State.CONNECTED:
			continue
		var tc: Dictionary = target_client.char
		if tc.get("map_id", -1) != map_id:
			continue
		var tdx: int = tc.get("x", 0) - ax
		var tdy: int = tc.get("y", 0) - ay
		var dist := maxi(abs(tdx), abs(tdy))
		if dist > attack_range or dist >= best_dist:
			continue
		if not is_ranged and not _in_melee_arc(heading, tdx, tdy):
			continue
		best_dist = dist
		best_player_client = target_client

	# Search NPCs (only when auto-targeting or when no specific player target found)
	if target_id == -1 or best_player_client == null:
		for nid in _npcs:
			var npc_cand: Dictionary = _npcs[nid]
			if npc_cand["ai_state"] == "dead":
				continue
			if npc_cand["map_id"] != map_id:
				continue
			# Skip non-combat NPCs (vendors, service NPCs)
			if npc_cand["data"].get("npc_type", 0) != 1:
				continue
			var ndx: int = npc_cand["x"] - ax
			var ndy: int = npc_cand["y"] - ay
			var dist := maxi(abs(ndx), abs(ndy))
			if dist > attack_range or dist >= best_dist:
				continue
			if not is_ranged and not _in_melee_arc(heading, ndx, ndy):
				continue
			best_dist = dist
			best_npc = npc_cand
			best_player_client = null  # NPC wins if it's closer

	# Execute attack on best target found
	if best_player_client != null:
		if is_ranged:
			_consume_arrow(attacker)
			_broadcast_projectile(map_id, client.peer_id, best_player_client.peer_id, ax, ay, 0)
		_player_attack_player(client, best_player_client)
	elif not best_npc.is_empty():
		if is_ranged:
			_consume_arrow(attacker)
			_broadcast_projectile(map_id, client.peer_id, best_npc["instance_id"], ax, ay, 0)
		_player_attack_npc(client, best_npc)


func _player_attack_player(attacker_client,
		target_client) -> void:
	## Resolves player-vs-player combat.
	var attacker: Dictionary = attacker_client.char
	var tc: Dictionary = target_client.char
	var map_id: int = attacker.get("map_id", 0)
	var ax: int = attacker.get("x", 0)
	var ay: int = attacker.get("y", 0)

	# God mode: target is invincible
	if _god_mode.has(target_client.peer_id):
		return

	var result := _ServerCombatSCR.resolve_attack(attacker, tc)
	var dmg: int   = result["dmg"]
	var evaded: bool = result["evaded"]

	# Damage broadcast
	var dw := NetProtocol.PacketWriter.new()
	dw.write_i32(target_client.peer_id)
	dw.write_i16(dmg)
	dw.write_u8(1 if evaded else 0)
	_broadcast_nearby(map_id, ax, ay, NetProtocol.MsgType.S_DAMAGE, dw.get_bytes(), -1)

	# Swing on miss/evade; hit sounds when damage lands
	if evaded or dmg == 0:
		_broadcast_sound_near(map_id, Vector2i(ax, ay), SND_SWING)
	else:
		_broadcast_sound_near(map_id, Vector2i(ax, ay), SOUND_MELEE_HIT)
		_broadcast_sound_near(map_id, Vector2i(ax, ay), SOUND_PLAYER_HIT)

	if not evaded and dmg > 0:
		tc["hp"] = maxi(0, tc.get("hp", 0) - dmg)

		# Send updated health to target
		var hw := NetProtocol.PacketWriter.new()
		hw.write_i16(tc.get("hp", 0))
		hw.write_i16(tc.get("mp", 0))
		hw.write_i16(tc.get("sta", 0))
		target_client.send_auth(NetProtocol.MsgType.S_HEALTH, hw.get_bytes())

		# Handle death
		if tc.get("hp", 0) <= 0:
			_handle_player_death(attacker_client, target_client)


func _player_attack_npc(attacker_client,
		npc_target: Dictionary) -> void:
	## Resolves player-vs-NPC combat.
	var attacker: Dictionary = attacker_client.char
	var map_id: int = attacker.get("map_id", 0)
	var ax: int = attacker.get("x", 0)
	var ay: int = attacker.get("y", 0)

	# Level-differential scaling: player gains bonus vs higher-level NPCs and vice versa
	var attacker_level: int = maxi(1, attacker.get("level", 1))
	var target_level:   int = maxi(1, npc_target["data"].get("level", 1))
	var lvl_mult := clampf(1.0 + (attacker_level - target_level) * 0.04, 0.5, 1.6)

	var result := _ServerCombatSCR.resolve_attack(attacker, npc_target, lvl_mult)
	var dmg: int   = result["dmg"]
	var evaded: bool = result["evaded"]

	# Broadcast S_DAMAGE: i32=npc instance_id, i16=dmg, u8=evaded
	var dw := NetProtocol.PacketWriter.new()
	dw.write_i32(npc_target["instance_id"])
	dw.write_i16(dmg)
	dw.write_u8(1 if evaded else 0)
	_broadcast_nearby(map_id, ax, ay, NetProtocol.MsgType.S_DAMAGE, dw.get_bytes(), -1)

	# Play melee hit sound (swing on miss/evade, metal hit on armoured connect)
	if evaded or dmg == 0:
		_broadcast_sound_near(map_id, Vector2i(ax, ay), SND_SWING)
	else:
		_broadcast_sound_near(map_id, Vector2i(ax, ay), SOUND_MELEE_HIT)

	if not evaded and dmg > 0:
		npc_target["hp"] = maxi(0, npc_target["hp"] - dmg)
		if npc_target["hp"] <= 0:
			_npc_death(npc_target, attacker_client)
		else:
			# NPC retaliates — set as hostile toward attacker if idle
			if npc_target["ai_state"] == "idle" and \
					npc_target["data"].get("hostile", 0) != 0:
				npc_target["ai_state"] = "chase"
				npc_target["target_peer"] = attacker_client.peer_id


func _has_arrows(char_data: Dictionary) -> bool:
	## Returns true if the character has at least one arrow stack in inventory.
	var inv: Array = char_data.get("inventory", [])
	for slot in inv:
		if slot is Dictionary and slot.get("obj_idx", 0) > 0:
			var obj: Dictionary = GameData.get_object(slot["obj_idx"])
			if obj.get("obj_type", 0) == ARROW_OBJ_TYPE:
				return true
	return false


func _consume_arrow(char_data: Dictionary) -> void:
	## Removes one arrow from the first arrow stack found in inventory.
	var inv: Array = char_data.get("inventory", [])
	for i in inv.size():
		var slot = inv[i]
		if slot is Dictionary and slot.get("obj_idx", 0) > 0:
			var obj: Dictionary = GameData.get_object(slot["obj_idx"])
			if obj.get("obj_type", 0) == ARROW_OBJ_TYPE:
				var amt: int = slot.get("amount", 1) - 1
				if amt <= 0:
					inv[i] = {"obj_idx": 0, "amount": 0}
				else:
					inv[i]["amount"] = amt
				return


func _broadcast_projectile(map_id: int, caster_id: int, target_id: int,
		cx: int, cy: int, proj_type: int) -> void:
	## Broadcasts S_PROJECTILE to all players near the launch point except the caster.
	var pw := NetProtocol.PacketWriter.new()
	pw.write_i32(caster_id)
	pw.write_i32(target_id)
	pw.write_u8(proj_type)
	var msg_bytes := pw.get_bytes()
	for pid in _clients:
		if pid == caster_id:
			continue
		var c = _clients[pid]
		if c.state != _ServerClientSCR.State.CONNECTED:
			continue
		var cc: Dictionary = c.char
		if cc.get("map_id", -1) != map_id:
			continue
		var dx: int = abs(int(cc.get("x", 0)) - cx)
		var dy: int = abs(int(cc.get("y", 0)) - cy)
		if dx <= 15 and dy <= 10:
			c.send_auth(NetProtocol.MsgType.S_PROJECTILE, msg_bytes)


func _handle_player_death(killer_client, dead_client) -> void:
	var dead_char: Dictionary = dead_client.char
	var level: int = dead_char.get("level", 1)

	# Award XP to killer
	var xp_gain := _ServerCombatSCR.xp_for_kill(level)
	var kc: Dictionary = killer_client.char
	kc["xp"] = kc.get("xp", 0) + xp_gain
	var levelled_up := _ServerCombatSCR.try_level_up(kc)

	_send_stats(killer_client)

	# XP gain notification
	var xw := NetProtocol.PacketWriter.new()
	xw.write_i32(xp_gain)
	killer_client.send_auth(NetProtocol.MsgType.S_XP_GAIN, xw.get_bytes())

	# Level-up notification + sound (killer only)
	if levelled_up:
		var lw := NetProtocol.PacketWriter.new()
		lw.write_u8(kc.get("level", 1))
		killer_client.send_auth(NetProtocol.MsgType.S_LEVEL_UP, lw.get_bytes())
		var sw := NetProtocol.PacketWriter.new()
		sw.write_u8(SOUND_LEVEL_UP)
		killer_client.send_auth(NetProtocol.MsgType.S_PLAY_SOUND, sw.get_bytes())
		_check_achievements(killer_client, "level", 0)
		_update_leaderboard("level", kc.get("name", "?"), kc.get("level", 1))

	# Bounty system: killer gets dead player's bounty, gains new bounty
	var _dead_bounty: int = int(dead_char.get("bounty", 0))
	var _killer_map_id: int = int(kc.get("map_id", 0))
	var _killer_name_pvp: String = kc.get("name", "unknown")
	if _dead_bounty > 0:
		kc["gold"] = int(kc.get("gold", 0)) + _dead_bounty
		dead_char["bounty"] = 0
		_send_server_msg(killer_client, "You collected a bounty of %d gold!" % _dead_bounty)
		_send_stats(killer_client)
		_check_achievements(killer_client, "bounties", 1)
	kc["bounty"] = int(kc.get("bounty", 0)) + 200
	var _new_bounty: int = int(kc.get("bounty", 0))
	var _bw := NetProtocol.PacketWriter.new()
	_bw.write_i32(killer_client.peer_id)
	_bw.write_str(_killer_name_pvp)
	_bw.write_i32(_new_bounty)
	_broadcast_map(_killer_map_id, S_BOUNTY_UPDATE, _bw.get_bytes())
	_send_server_msg_to_map(_killer_map_id, "WARNING: %s is now wanted! Bounty: %d gold." % [_killer_name_pvp, _new_bounty])
	# PK achievement
	_check_achievements(killer_client, "pks", 1)

	# Respawn dead player at map start position
	var map_id: int = dead_char.get("map_id", 1)
	var map_data := GameData.get_map(map_id)
	var sp: Dictionary = map_data.get("start_pos", {"x": 10, "y": 10})
	dead_char["hp"]    = dead_char.get("max_hp", 100)

	# Broadcast corpse visual at dead player's position before respawn
	var dead_x: int = int(dead_char.get("x", 10))
	var dead_y: int = int(dead_char.get("y", 10))
	var dead_map_id: int = int(dead_char.get("map_id", 1))
	var corpse_w := NetProtocol.PacketWriter.new()
	corpse_w.write_i16(dead_x)
	corpse_w.write_i16(dead_y)
	corpse_w.write_i16(CORPSE_GRH)
	_broadcast_nearby(dead_map_id, dead_x, dead_y,
			NetProtocol.MsgType.S_CORPSE, corpse_w.get_bytes(), -1)

	# Death penalty: strip gold and most items; gold goes directly to killer
	var loss_msg: String = _apply_death_penalty(dead_char)
	var looted_gold: int = dead_char.get("_looted_gold", 0)
	dead_char.erase("_looted_gold")
	if looted_gold > 0:
		kc["gold"] = kc.get("gold", 0) + looted_gold
		_send_stats(killer_client)
		_send_server_msg(killer_client, "You looted %d gold from %s!" % [looted_gold, dead_char.get("name", "your victim")])

	dead_char["x"]     = sp.get("x", 10)
	dead_char["y"]     = sp.get("y", 10)
	var dw_pvp := NetProtocol.PacketWriter.new()
	dw_pvp.write_str(kc.get("name", "a player"))
	dead_client.send_auth(NetProtocol.MsgType.S_DEATH, dw_pvp.get_bytes())
	_enter_world(dead_client, dead_char)

	# Notify the dead player of their losses in chat (arrives after world reload packets).
	_send_server_msg(dead_client, "You were slain by %s! %s" % [
			kc.get("name", "a player"), loss_msg])


## Player died from starvation/dehydration — respawn at map start with partial vitals
func _starve_death(client) -> void:
	var c: Dictionary = client.char
	var msg := NetProtocol.PacketWriter.new()
	msg.write_str("You died of %s!" % ("starvation" if c.get("hunger", 1.0) <= c.get("thirst", 1.0) else "dehydration"))
	client.send_auth(NetProtocol.MsgType.S_SERVER_MSG, msg.get_bytes())

	# Restore vitals to 25 so they don't immediately die again
	c["hunger"] = maxf(c.get("hunger", 0.0), 25.0)
	c["thirst"] = maxf(c.get("thirst", 0.0), 25.0)

	# Respawn at map start
	var map_id: int = c.get("map_id", 1)
	var map_data := GameData.get_map(map_id)
	var sp: Dictionary = map_data.get("start_pos", {"x": 10, "y": 10})
	c["hp"] = c.get("max_hp", 100)
	c["x"]  = sp.get("x", 10)
	c["y"]  = sp.get("y", 10)
	var dw_starve := NetProtocol.PacketWriter.new()
	dw_starve.write_str("")
	client.send_auth(NetProtocol.MsgType.S_DEATH, dw_starve.get_bytes())
	_enter_world(client, c)


func _on_equip(client, inv_slot: int) -> void:
	var char: Dictionary = client.char
	var inv: Array = char.get("inventory", [])
	if inv_slot < 0 or inv_slot >= inv.size():
		return
	var item: Dictionary = inv[inv_slot]
	if item.is_empty():
		return
	var obj_idx: int = item.get("obj_index", 0)
	var obj := GameData.get_object(obj_idx)
	if obj.is_empty():
		return

	var eq_slot := _get_equip_slot(obj)
	if eq_slot.is_empty():
		return

	var equip: Dictionary = char.get("equipment", {})
	# Unequip any existing item in this slot first (clear old body/shield visuals)
	var old_obj_idx: int = equip.get(eq_slot, 0)
	if old_obj_idx > 0:
		var old_obj := GameData.get_object(old_obj_idx)
		# Revert body to base if old item was armor/helmet that changed it
		if eq_slot == "armor" or eq_slot == "helmet":
			var old_ct: int = old_obj.get("clothing_type", 0)
			if old_ct > 0 and char.get("body", 1) == old_ct:
				char["body"] = char.get("base_body", 1)
		# Clear equipped flag on old item in inventory
		for inv_item in inv:
			var di: Dictionary = inv_item
			if not di.is_empty() and di.get("obj_index", 0) == old_obj_idx \
					and di.get("equipped", false):
				di["equipped"] = false
				break
	equip[eq_slot] = obj_idx
	char["equipment"] = equip
	item["equipped"] = true

	# VB6 faithful: equipping armor/clothing/helmet changes Char.Body to ClothingType.
	# This body index maps directly to a body.dat entry (different sprite set).
	if eq_slot == "armor" or eq_slot == "helmet":
		var ct: int = obj.get("clothing_type", 0)
		if ct > 0:
			# Save the original base body index on first armor equip
			if not char.has("base_body"):
				char["base_body"] = char.get("body", 1)
			char["body"] = ct

	_ServerCombatSCR.recalculate_combat_stats(char)
	_send_stats(client)
	_send_inventory(client)

	# Notify nearby clients of appearance change
	_broadcast_set_char(client)


func _on_unequip(client, slot: int) -> void:
	var char: Dictionary = client.char
	var inv: Array = char.get("inventory", [])
	var equip: Dictionary = char.get("equipment", {})

	# Find the item to unequip by the inventory slot index sent from the client.
	var item: Dictionary = {}
	var item_slot: int = -1
	if slot >= 0 and slot < inv.size() and not inv[slot].is_empty() and inv[slot].get("equipped", false):
		item = inv[slot]
		item_slot = slot
	else:
		# Fallback: find first equipped item in inventory.
		for i in inv.size():
			if not inv[i].is_empty() and inv[i].get("equipped", false):
				item = inv[i]
				item_slot = i
				break

	if item.is_empty():
		return

	var obj := GameData.get_object(item.get("obj_index", 0))
	var eq_slot := _get_equip_slot(obj)
	if not eq_slot.is_empty():
		equip[eq_slot] = 0
		# VB6 faithful: removing armor/helmet reverts body to the base body index.
		if eq_slot == "armor" or eq_slot == "helmet":
			var ct: int = obj.get("clothing_type", 0)
			if ct > 0 and char.get("body", 1) == ct:
				char["body"] = char.get("base_body", 1)
	item["equipped"] = false
	inv[item_slot] = item
	char["equipment"] = equip
	char["inventory"] = inv

	_ServerCombatSCR.recalculate_combat_stats(char)
	_send_stats(client)
	_send_inventory(client)
	_broadcast_set_char(client)


func _on_chat(client, message: String) -> void:
	if message.length() == 0 or message.length() > 256:
		return

	# Mute check
	var pid_chat: int = client.peer_id
	if _mutes.has(pid_chat):
		var expiry_chat: int = _mutes[pid_chat]
		if expiry_chat == 0 or Time.get_ticks_msec() < expiry_chat:
			_send_server_msg(client, "You are muted and cannot chat.")
			return
		else:
			_mutes.erase(pid_chat)  # expired

	# All slash commands (including /w and /whisper) go through the admin handler
	if message.begins_with("/"):
		_handle_admin_command(client, message)
		return

	var char: Dictionary = client.char
	var map_id: int = char.get("map_id", 0)
	var cx: int = char.get("x", 0)
	var cy: int = char.get("y", 0)
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(client.peer_id)
	w.write_u8(0)  # chat_type 0 = normal
	w.write_str(message)
	_broadcast_nearby(map_id, cx, cy, NetProtocol.MsgType.S_CHAT, w.get_bytes(), -1)


func _send_whisper(sender_client, target_name: String, message: String) -> void:
	var sender_name: String = sender_client.char.get("name", "Unknown")
	# Find target by name
	for pid in _clients:
		var c = _clients[pid]
		if c.state != _ServerClientSCR.State.CONNECTED:
			continue
		if c.char.get("name", "").to_lower() == target_name.to_lower():
			# Send to target: type 3 = whisper
			var tw := NetProtocol.PacketWriter.new()
			tw.write_i32(sender_client.peer_id)
			tw.write_u8(3)
			tw.write_str("[%s whispers]: %s" % [sender_name, message])
			c.send_auth(NetProtocol.MsgType.S_CHAT, tw.get_bytes())
			# Echo back to sender
			_send_server_msg(sender_client, "You whisper to %s: %s" % [target_name, message])
			return
	_send_server_msg(sender_client, "Player '%s' is not online." % target_name)


func _on_drop(client, slot: int, amount: int) -> void:
	var char: Dictionary = client.char
	var inv: Array = char.get("inventory", [])
	if slot < 0 or slot >= inv.size():
		return
	var item: Dictionary = inv[slot]
	if item.is_empty():
		return
	var have: int = item.get("amount", 0)
	amount = mini(amount, have)
	var obj_index: int = item.get("obj_index", 0)
	item["amount"] = have - amount
	if item["amount"] <= 0:
		inv[slot] = {}
	char["inventory"] = inv
	_send_inventory(client)
	# Spawn the dropped item as a ground item
	var cx: int = char.get("x", 0)
	var cy: int = char.get("y", 0)
	var map_id: int = char.get("map_id", 0)
	_spawn_ground_item(map_id, cx, cy, obj_index, amount)
	# Item drop sound — played only to the dropping player
	var dsw := NetProtocol.PacketWriter.new()
	dsw.write_u8(SOUND_ITEM_DROP)
	client.send_auth(NetProtocol.MsgType.S_PLAY_SOUND, dsw.get_bytes())


func _spawn_ground_item(map_id: int, x: int, y: int, obj_index: int, amount: int) -> void:
	var id := _ground_item_counter
	_ground_item_counter += 1
	var gi := {
		"id": id, "obj_index": obj_index, "amount": amount,
		"map_id": map_id, "x": x, "y": y,
		"expires_at": Time.get_ticks_msec() / 1000.0 + GROUND_ITEM_TIMEOUT
	}
	_ground_items[id] = gi
	_broadcast_ground_item_add(gi)


func _remove_ground_item(id: int) -> void:
	if not _ground_items.has(id):
		return
	var gi: Dictionary = _ground_items[id]
	_ground_items.erase(id)
	var w := NetProtocol.PacketWriter.new()
	w.write_i16(id)
	for pid in _clients:
		var cl = _clients[pid]
		if cl.state == _ServerClientSCR.State.CONNECTED and cl.char.get("map_id", -1) == gi["map_id"]:
			cl.send_auth(NetProtocol.MsgType.S_GROUND_ITEM_REMOVE, w.get_bytes())


func _broadcast_ground_item_add(gi: Dictionary) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_i16(gi["id"])
	w.write_i16(gi["obj_index"])
	w.write_u16(gi["amount"])
	w.write_i16(gi["x"])
	w.write_i16(gi["y"])
	for pid in _clients:
		var cl = _clients[pid]
		if cl.state == _ServerClientSCR.State.CONNECTED and cl.char.get("map_id", -1) == gi["map_id"]:
			cl.send_auth(NetProtocol.MsgType.S_GROUND_ITEM_ADD, w.get_bytes())


func _send_ground_items_for_map(client, map_id: int) -> void:
	for id in _ground_items:
		var gi: Dictionary = _ground_items[id]
		if gi["map_id"] == map_id:
			var w := NetProtocol.PacketWriter.new()
			w.write_i16(gi["id"])
			w.write_i16(gi["obj_index"])
			w.write_u16(gi["amount"])
			w.write_i16(gi["x"])
			w.write_i16(gi["y"])
			client.send_auth(NetProtocol.MsgType.S_GROUND_ITEM_ADD, w.get_bytes())


func _on_pickup(client, item_id: int) -> void:
	if not _ground_items.has(item_id):
		_send_server_msg(client, "That item is no longer there.")
		return
	var gi: Dictionary = _ground_items[item_id]
	var char_dict: Dictionary = client.char
	if gi["map_id"] != char_dict.get("map_id", -1):
		return
	var cx: int = char_dict.get("x", 0)
	var cy: int = char_dict.get("y", 0)
	if abs(gi["x"] - cx) > 2 or abs(gi["y"] - cy) > 2:
		_send_server_msg(client, "You are too far away.")
		return
	_give_item(char_dict, gi["obj_index"], gi["amount"])
	_send_inventory(client)
	var obj_name: String = GameData.get_object(gi["obj_index"]).get("name", "item")
	_send_server_msg(client, "You pick up: %s." % obj_name)
	# Quest gather progress check
	_check_gather_quests(client)
	# Item pickup sound — played only to the picking-up player
	var pw := NetProtocol.PacketWriter.new()
	pw.write_u8(SOUND_ITEM_PICKUP)
	client.send_auth(NetProtocol.MsgType.S_PLAY_SOUND, pw.get_bytes())
	_remove_ground_item(item_id)
	_db.save_char(client.username, char_dict)


func _on_use_item(client, slot: int) -> void:
	var char: Dictionary = client.char
	var inv: Array = char.get("inventory", [])
	if slot < 0 or slot >= inv.size():
		return
	var item: Dictionary = inv[slot]
	if item.is_empty():
		return
	var obj: Dictionary = GameData.get_object(item.get("obj_index", 0))
	var obj_type: int = obj.get("obj_type", 0)

	# Blacksmithing blueprint
	if obj_type == BLACKSMITH_DRAWING_TYPE:
		_handle_blacksmithing(client, slot, inv, obj)
		return

	# Food / consumable
	var obj_index_used: int = item.get("obj_index", 0)
	var food: int = obj.get("food", 0)
	var restore: Dictionary = FOOD_RESTORE.get(obj_index_used, {})
	var hunger_gain: float = float(restore.get("hunger", 0))
	var thirst_gain: float = float(restore.get("thirst", 0))

	if food > 0 or hunger_gain > 0 or thirst_gain > 0:
		# HP healing from food field
		if food > 0:
			char["hp"] = mini(char.get("max_hp", 100), char.get("hp", 0) + food)
		# Hunger/thirst restoration
		if hunger_gain > 0:
			char["hunger"] = minf(100.0, char.get("hunger", 80.0) + hunger_gain)
		if thirst_gain > 0:
			char["thirst"] = minf(100.0, char.get("thirst", 80.0) + thirst_gain)

		item["amount"] = item.get("amount", 1) - 1
		if item["amount"] <= 0:
			inv[slot] = {}
		char["inventory"] = inv
		_send_inventory(client)
		_send_vitals(client)

		var hw := NetProtocol.PacketWriter.new()
		hw.write_i16(char.get("hp", 0))
		hw.write_i16(char.get("mp", 0))
		hw.write_i16(char.get("sta", 0))
		client.send_auth(NetProtocol.MsgType.S_HEALTH, hw.get_bytes())

		# Raw fish/meat makes the player sick
		if obj_type == RAW_MEAT_OBJ_TYPE:
			_apply_poison(client.peer_id, client, char)


## Blacksmithing: use a blueprint to forge a weapon/armour from steel clumps.
func _handle_blacksmithing(client, blueprint_slot: int, inv: Array, blueprint: Dictionary) -> void:
	var char_dict: Dictionary = client.char

	var make_item: int   = blueprint.get("make_item", 0)
	var need_steel: int  = blueprint.get("need_steel", 0)
	var req_skill: int   = blueprint.get("skill", 0)

	if make_item <= 0:
		_send_server_msg(client, "This blueprint is incomplete.")
		return

	# Check Blacksmithing skill (slot 9, 0-indexed as 8)
	var skills: Array = char_dict.get("skills", [])
	var smith_skill: int = skills[8] if skills.size() > 8 else 0
	if smith_skill < req_skill:
		_send_server_msg(client,
			"Your Blacksmithing skill is too low. (Need %d, have %d)" % [req_skill, smith_skill])
		return

	# Count steel clumps in inventory
	var steel_have: int = 0
	var steel_slots: Array = []
	for i in inv.size():
		var d: Dictionary = inv[i] as Dictionary
		if d.is_empty() or d.get("equipped", false):
			continue
		if d.get("obj_index", 0) == STEEL_OBJ_INDEX:
			steel_have += d.get("amount", 0)
			steel_slots.append(i)

	if steel_have < need_steel:
		_send_server_msg(client,
			"You need %d steel clumps. You have %d." % [need_steel, steel_have])
		return

	# Deduct steel (may span multiple stacks)
	var to_deduct: int = need_steel
	for i in steel_slots:
		if to_deduct <= 0:
			break
		var d: Dictionary = inv[i] as Dictionary
		var have: int = d.get("amount", 0)
		if have <= to_deduct:
			to_deduct -= have
			inv[i] = {}
		else:
			d["amount"] = have - to_deduct
			to_deduct = 0

	# Consume the blueprint
	inv[blueprint_slot] = {}
	char_dict["inventory"] = inv

	# Give the crafted item
	_give_item(char_dict, make_item, 1)
	_send_inventory(client)

	var out_name: String = GameData.get_object(make_item).get("name", "item")
	_send_server_msg(client, "You forge: %s!" % out_name)

	# Award Blacksmithing skill XP
	_award_skill_xp(client, char_dict, 9)
	_db.save_char(client.username, char_dict)
	# Quest craft progress
	_check_craft_quests(client, "forge")
	# Achievements & leaderboards for crafting
	_check_achievements(client, "crafts", 1)
	_update_leaderboard("crafts", char_dict.get("name", "?"),
			int(char_dict.get("achievement_progress", {}).get("crafts", 0)))


# ---------------------------------------------------------------------------
# Timed skill system
# ---------------------------------------------------------------------------

## Convenience wrapper — sends a S_SERVER_MSG packet to one client.
func _send_server_msg(client, message: String) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_str(message)
	client.send_auth(NetProtocol.MsgType.S_SERVER_MSG, w.get_bytes())


## Entry point for C_USE_SKILL.
func _handle_use_skill(client, skill_id: int, tile: Vector2i) -> void:
	var pid: int = client.peer_id

	# Can't start a new skill while one is in progress
	if _skill_timers.has(pid):
		_send_server_msg(client, "You are already busy.")
		return

	match skill_id:
		1:   # Cooking
			_start_cooking(client, tile)
		4:   # Carpenting — plank making OR carpentry crafting
			_handle_carpenting(client)
		5:   # Lumberjacking
			_start_gathering(client, skill_id, tile,
					LUMBERJACK_AXE_TYPE, LOG_OBJ_INDEX,
					"You begin chopping wood...")
		9:   # Blacksmithing OR Smelting — context-dependent
			_handle_smith_or_smelt(client)
		20:  # Fishing
			_start_gathering(client, skill_id, tile,
					FISHING_ROD_TYPE, 0,
					"You cast your line...")
		21:  # Mining
			_start_gathering(client, skill_id, tile,
					PICKAXE_OBJ_TYPE, ORE_OBJ_INDEX,
					"You begin mining for ore...")
		_:
			_send_server_msg(client, "That skill is not yet implemented.")


## Blacksmithing via skill key — find first blueprint in inventory and forge it.
func _start_blacksmithing_from_skill(client) -> void:
	var inv: Array = client.char.get("inventory", [])
	for i in inv.size():
		var d: Dictionary = inv[i] as Dictionary
		if d.is_empty():
			continue
		var obj: Dictionary = GameData.get_object(d.get("obj_index", 0))
		if obj.get("obj_type", 0) == BLACKSMITH_DRAWING_TYPE:
			_handle_blacksmithing(client, i, inv, obj)
			return
	_send_server_msg(client, "You have no blacksmithing blueprints.")


# ---------------------------------------------------------------------------
# Crafting helpers — smelting, cooking, carpenting, station detection
# ---------------------------------------------------------------------------

## Skill 9 dispatcher: if the player has ore + is near forge+anvil → smelt;
## otherwise look for a blacksmithing blueprint → forge.
func _handle_smith_or_smelt(client) -> void:
	var char_dict: Dictionary = client.char
	var map_id: int = char_dict.get("map_id", 0)
	var tile := Vector2i(char_dict.get("x", 0), char_dict.get("y", 0))

	# Check for ore in inventory
	var has_ore: bool = _has_item_index(char_dict, ORE_OBJ_INDEX)
	# Check for forge AND anvil nearby
	var near_forge: bool = _has_station_near(map_id, tile, [FORGE_OBJ_TYPE])
	var near_anvil: bool = _has_station_near(map_id, tile, [ANVIL_OBJ_TYPE])

	if has_ore and near_forge and near_anvil:
		_start_smelting(client, tile)
	elif _has_tool_type(char_dict, HAMMER_OBJ_TYPE):
		_start_blacksmithing_from_skill(client)
	else:
		_send_server_msg(client, "You need a hammer, ore near a forge and anvil, or a blueprint to use Blacksmithing.")


## Start a smelting action (ore → steel). Requires hammer + ore + forge + anvil nearby.
func _start_smelting(client, tile: Vector2i) -> void:
	var char_dict: Dictionary = client.char
	var pid: int = client.peer_id

	if not _has_tool_type(char_dict, HAMMER_OBJ_TYPE):
		_send_server_msg(client, "You need a hammer to smelt ore.")
		return
	if not _has_item_index(char_dict, ORE_OBJ_INDEX):
		_send_server_msg(client, "You have no ore to smelt.")
		return

	var map_id: int = char_dict.get("map_id", 0)
	var char_tile := Vector2i(char_dict.get("x", 0), char_dict.get("y", 0))
	if not _has_station_near(map_id, char_tile, [FORGE_OBJ_TYPE]):
		_send_server_msg(client, "You must be near a forge to smelt ore.")
		return
	if not _has_station_near(map_id, char_tile, [ANVIL_OBJ_TYPE]):
		_send_server_msg(client, "You must be near an anvil to smelt ore.")
		return

	var skills_arr: Array = char_dict.get("skills", [])
	var skill_lv: int = skills_arr[8] if skills_arr.size() > 8 else 0  # skill 9 = index 8
	var speed_factor: float = maxf(0.50, 1.0 - float(skill_lv) * 0.005)
	var duration: float = SKILL_DURATIONS.get(9, 7.0) * speed_factor

	_skill_timers[pid] = {
		"skill_id": 9,
		"time_left": duration,
		"tile":      tile,
		"action":    "smelt",
		"aux":       {},
	}
	_send_skill_progress(client, 9, int(duration * 1000.0))
	_send_server_msg(client, "You begin smelting ore...")


## Skill 1 (Cooking) dispatcher. Looks for raw food near a campfire or stove.
func _start_cooking(client, _tile: Vector2i) -> void:
	var char_dict: Dictionary = client.char
	var pid: int = client.peer_id
	var map_id: int = char_dict.get("map_id", 0)
	var char_tile := Vector2i(char_dict.get("x", 0), char_dict.get("y", 0))

	if not _has_station_near(map_id, char_tile, COOKING_STATION_TYPES):
		_send_server_msg(client, "You need to be near a campfire or cooking stove.")
		return

	# Find first raw ingredient in inventory
	var inv: Array = char_dict.get("inventory", [])
	var cook_slot: int = -1
	for i in inv.size():
		var d: Dictionary = inv[i] as Dictionary
		if d.is_empty():
			continue
		var obj_type: int = GameData.get_object(d.get("obj_index", 0)).get("obj_type", 0)
		# Raw fish (type 39), raw meat (obj_index 117)
		if obj_type == RAW_MEAT_OBJ_TYPE or d.get("obj_index", 0) == 117:
			cook_slot = i
			break

	if cook_slot < 0:
		_send_server_msg(client, "You have no raw food to cook.")
		return

	var skills_arr: Array = char_dict.get("skills", [])
	var skill_lv: int = skills_arr[0] if skills_arr.size() > 0 else 0  # skill 1 = index 0
	var speed_factor: float = maxf(0.50, 1.0 - float(skill_lv) * 0.005)
	var duration: float = SKILL_DURATIONS.get(1, 6.0) * speed_factor

	_skill_timers[pid] = {
		"skill_id": 1,
		"time_left": duration,
		"tile":      char_tile,
		"action":    "cook",
		"aux":       {"slot": cook_slot},
	}
	_send_skill_progress(client, 1, int(duration * 1000.0))
	_send_server_msg(client, "You begin cooking...")


## Skill 4 (Carpenting) dispatcher: plank-making OR carpentry crafting from blueprint.
func _handle_carpenting(client) -> void:
	var char_dict: Dictionary = client.char

	# If a carpentry drawing is in inventory → craft from blueprint
	var inv: Array = char_dict.get("inventory", [])
	for i in inv.size():
		var d: Dictionary = inv[i] as Dictionary
		if d.is_empty():
			continue
		var obj: Dictionary = GameData.get_object(d.get("obj_index", 0))
		if obj.get("obj_type", 0) == CARPENTRY_DRAWING_TYPE:
			_handle_carpentry_craft(client, i, inv, obj)
			return

	# No blueprint → plank-making (logs → planks)
	_start_plank_making(client)


## Start a plank-making action. Requires a saw and logs in inventory.
func _start_plank_making(client) -> void:
	var char_dict: Dictionary = client.char
	var pid: int = client.peer_id

	if not _has_tool_type(char_dict, SAW_OBJ_TYPE):
		_send_server_msg(client, "You need a saw to cut planks.")
		return
	if not _has_item_index(char_dict, LOG_OBJ_INDEX):
		_send_server_msg(client, "You have no logs to cut into planks.")
		return

	var skills_arr: Array = char_dict.get("skills", [])
	var skill_lv: int = skills_arr[3] if skills_arr.size() > 3 else 0  # skill 4 = index 3
	var speed_factor: float = maxf(0.50, 1.0 - float(skill_lv) * 0.005)
	var duration: float = SKILL_DURATIONS.get(4, 6.0) * speed_factor
	var tile := Vector2i(char_dict.get("x", 0), char_dict.get("y", 0))

	_skill_timers[pid] = {
		"skill_id": 4,
		"time_left": duration,
		"tile":      tile,
		"action":    "planks",
		"aux":       {},
	}
	_send_skill_progress(client, 4, int(duration * 1000.0))
	_send_server_msg(client, "You begin cutting logs into planks...")


## Carpentry blueprint crafting — mirrors _handle_blacksmithing but uses planks.
func _handle_carpentry_craft(client, blueprint_slot: int, inv: Array,
		blueprint: Dictionary) -> void:
	var char_dict: Dictionary = client.char

	# Retrieve the item to make
	var make_item: int = blueprint.get("make_item", 0)
	if make_item <= 0:
		_send_server_msg(client, "That blueprint is not usable.")
		return

	# Require a saw
	if not _has_tool_type(char_dict, SAW_OBJ_TYPE):
		_send_server_msg(client, "You need a saw for carpentry.")
		return

	# Check and consume planks (need_planks field on blueprint object)
	var need_planks: int = blueprint.get("need_planks", 1)
	var available: int = 0
	for item in inv:
		var d: Dictionary = item as Dictionary
		if not d.is_empty() and d.get("obj_index", 0) == PLANK_OBJ_INDEX:
			available += d.get("amount", 0)
	if available < need_planks:
		_send_server_msg(client, "You need %d planks (have %d)." % [need_planks, available])
		return

	# Consume planks
	var to_deduct: int = need_planks
	for i in inv.size():
		if to_deduct <= 0:
			break
		var d: Dictionary = inv[i] as Dictionary
		if d.is_empty() or d.get("obj_index", 0) != PLANK_OBJ_INDEX:
			continue
		var have: int = d.get("amount", 0)
		if have <= to_deduct:
			to_deduct -= have
			inv[i] = {}
		else:
			d["amount"] = have - to_deduct
			to_deduct = 0

	# Consume the blueprint
	inv[blueprint_slot] = {}
	char_dict["inventory"] = inv

	_give_item(char_dict, make_item, 1)
	_send_inventory(client)

	var out_name: String = GameData.get_object(make_item).get("name", "item")
	_send_server_msg(client, "You craft: %s!" % out_name)
	_award_skill_xp(client, char_dict, 4)
	_db.save_char(client.username, char_dict)


## Returns true if any world object within STATION_RANGE tiles of char_tile
## (on the same map) has an obj_type matching one of station_types.
const STATION_RANGE: int = 3
func _has_station_near(map_id: int, char_tile: Vector2i,
		station_types: Array) -> bool:
	var map_data: Dictionary = GameData.get_map(map_id)
	if map_data.is_empty():
		return false
	var tiles: Dictionary = map_data.get("tiles", {})
	for dy in range(-STATION_RANGE, STATION_RANGE + 1):
		for dx in range(-STATION_RANGE, STATION_RANGE + 1):
			var tx: int = char_tile.x + dx
			var ty: int = char_tile.y + dy
			var key: String = "%d,%d" % [ty, tx]
			var td: Dictionary = tiles.get(key, {})
			var obj: Dictionary = td.get("obj", {})
			if obj.is_empty():
				continue
			var obj_idx: int = obj.get("index", 0)
			if obj_idx <= 0:
				continue
			var obj_type: int = GameData.get_object(obj_idx).get("obj_type", 0)
			if station_types.has(obj_type):
				return true
	# Also check hardcoded CRAFTING_STATIONS
	var cs_map: Array = CRAFTING_STATIONS.get(map_id, [])
	for cs in cs_map:
		if not station_types.has(int(cs["obj_type"])):
			continue
		var cdx: int = abs(int(cs["x"]) - char_tile.x)
		var cdy: int = abs(int(cs["y"]) - char_tile.y)
		if maxi(cdx, cdy) <= STATION_RANGE:
			return true
	return false


## Returns true if the character has at least one item with the given obj_index.
func _has_item_index(char_dict: Dictionary, obj_index: int) -> bool:
	var inv: Array = char_dict.get("inventory", [])
	for item in inv:
		var d: Dictionary = item as Dictionary
		if not d.is_empty() and d.get("obj_index", 0) == obj_index:
			return true
	return false


## Remove up to `amount` of `obj_index` from inventory. Returns actual amount removed.
func _remove_item_by_index(char_dict: Dictionary, obj_index: int, amount: int) -> int:
	var inv: Array = char_dict.get("inventory", [])
	var to_remove: int = amount
	for i in inv.size():
		if to_remove <= 0:
			break
		var d: Dictionary = inv[i] as Dictionary
		if d.is_empty() or d.get("obj_index", 0) != obj_index:
			continue
		var have: int = d.get("amount", 0)
		if have <= to_remove:
			to_remove -= have
			inv[i] = {}
		else:
			d["amount"] = have - to_remove
			to_remove = 0
	char_dict["inventory"] = inv
	return amount - to_remove   # how many were actually removed


## Apply the poison status to a player. Overwrites any existing poison timer.
func _apply_poison(pid: int, client, _char_dict: Dictionary) -> void:
	var now_ms: int = Time.get_ticks_msec()
	_poison_timers[pid] = {
		"expiry_ms":    now_ms + int(POISON_DURATION_SEC * 1000.0),
		"next_tick_ms": now_ms + int(POISON_TICK_SEC * 1000.0),
	}
	# Notify client via status packet
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(POISON_STATUS_ID)
	w.write_u16(int(POISON_DURATION_SEC))   # duration hint in seconds
	client.send_auth(S_STATUS_APPLIED, w.get_bytes())
	_send_server_msg(client, "You feel sick from eating raw food!")


## Called every housekeep tick. Deals periodic poison damage and clears expired timers.
func _tick_poison(now_ms: int) -> void:
	for pid in _poison_timers.keys():
		var pt: Dictionary = _poison_timers[pid]

		# Expired?
		if now_ms >= pt["expiry_ms"]:
			_poison_timers.erase(pid)
			if _clients.has(pid):
				var cl = _clients[pid]
				if cl.state == _ServerClientSCR.State.CONNECTED:
					var w := NetProtocol.PacketWriter.new()
					w.write_u8(POISON_STATUS_ID)
					cl.send_auth(S_STATUS_REMOVED, w.get_bytes())
					_send_server_msg(cl, "You no longer feel poisoned.")
			continue

		# Deal tick damage
		if now_ms >= pt["next_tick_ms"]:
			pt["next_tick_ms"] = now_ms + int(POISON_TICK_SEC * 1000.0)
			if not _clients.has(pid):
				continue
			var cl = _clients[pid]
			if cl.state != _ServerClientSCR.State.CONNECTED:
				continue
			var char_dict: Dictionary = cl.char
			var hp: int = char_dict.get("hp", 0)
			hp = maxi(0, hp - POISON_TICK_DMG)
			char_dict["hp"] = hp
			_send_stats(cl)
			# Broadcast poison tick damage to nearby clients
			var dw := NetProtocol.PacketWriter.new()
			dw.write_i32(pid)
			dw.write_i16(POISON_TICK_DMG)
			dw.write_u8(0)   # not evaded
			var map_id_p: int = char_dict.get("map_id", 0)
			_broadcast_nearby(map_id_p, char_dict.get("x", 0),
					char_dict.get("y", 0), NetProtocol.MsgType.S_DAMAGE,
					dw.get_bytes(), -1)
			if hp <= 0:
				_handle_player_death(cl, cl)   # poison killed the player (no killer)
				_poison_timers.erase(pid)


## Validates requirements, then starts the skill timer and notifies the client.
func _start_gathering(client, skill_id: int, tile: Vector2i,
		required_tool_type: int, yield_obj_index: int, start_msg: String) -> void:
	var char_dict: Dictionary = client.char
	var pid: int = client.peer_id

	# Check player has the required tool type in inventory
	if not _has_tool_type(char_dict, required_tool_type):
		match skill_id:
			5:  _send_server_msg(client, "You need a lumberjack axe to chop wood.")
			21: _send_server_msg(client, "You need a pickaxe to mine ore.")
			20: _send_server_msg(client, "You need a fishing rod to fish.")
		return

	# Check there is a valid resource tile within 2 tiles of the player
	var char_tile := Vector2i(char_dict.get("x", 0), char_dict.get("y", 0))
	if not _has_resource_near(char_dict.get("map_id", 0), char_tile, skill_id):
		match skill_id:
			5:  _send_server_msg(client, "There are no trees to chop nearby.")
			21: _send_server_msg(client, "There is no ore to mine nearby.")
			20: _send_server_msg(client, "You need to be near water to fish.")
		return

	# Start the timer — higher skill level shortens duration (max 50% faster at level 100).
	var skills_arr: Array = char_dict.get("skills", [])
	var skill_lv: int = skills_arr[skill_id - 1] if skill_id - 1 < skills_arr.size() else 0
	var speed_factor: float = maxf(0.50, 1.0 - float(skill_lv) * 0.005)
	var duration: float = SKILL_DURATIONS.get(skill_id, 7.0) * speed_factor
	_skill_timers[pid] = {
		"skill_id":   skill_id,
		"time_left":  duration,
		"tile":       tile,
		"yield_obj":  yield_obj_index,
	}

	# Notify client to show progress bar
	_send_skill_progress(client, skill_id, int(duration * 1000.0))
	_send_server_msg(client, start_msg)


## Returns true if the character has at least one item with the given obj_type.
func _has_tool_type(char_dict: Dictionary, tool_obj_type: int) -> bool:
	var inv: Array = char_dict.get("inventory", [])
	for item in inv:
		var d: Dictionary = item as Dictionary
		if d.is_empty():
			continue
		var obj_data: Dictionary = GameData.get_object(d.get("obj_index", 0))
		if obj_data.get("obj_type", 0) == tool_obj_type:
			return true
	return false


## GRH index used by all water tiles (animated water = grh 3500).
const WATER_GRH: int = 3500

## Returns true if there is a suitable resource within 2 tiles.
## Checks both hardcoded RESOURCE_NODES and map tile objects.
func _has_resource_near(map_id: int, char_tile: Vector2i, skill_id: int) -> bool:
	if skill_id == 20:
		# Fishing: check for adjacent water tile (layer[0] == WATER_GRH)
		var map_data: Dictionary = GameData.get_map(map_id)
		var tiles: Dictionary = map_data.get("tiles", {})
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var key: String = "%d,%d" % [char_tile.y + dy, char_tile.x + dx]
				var td: Dictionary = tiles.get(key, {})
				var layers: Array = td.get("layers", [0])
				if layers.size() > 0 and layers[0] == WATER_GRH:
					return true
		return false

	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var tx: int = char_tile.x + dx
			var ty: int = char_tile.y + dy

			# Check hardcoded resource nodes first
			var node_key: String = "%d,%d,%d" % [map_id, tx, ty]
			if RESOURCE_NODES.has(node_key) and RESOURCE_NODES[node_key] == skill_id:
				return true

			# Check map tile object data
			var map_data: Dictionary = GameData.get_map(map_id)
			if map_data.is_empty():
				continue
			var tiles: Dictionary = map_data.get("tiles", {})
			var tile: Dictionary = tiles.get("%d,%d" % [ty, tx], {})
			var obj: Dictionary  = tile.get("obj", {})
			if obj.is_empty():
				continue
			var obj_idx: int = obj.get("index", 0)
			if obj_idx <= 0:
				continue
			var obj_data: Dictionary = GameData.get_object(obj_idx)
			var obj_type: int = obj_data.get("obj_type", 0)
			match skill_id:
				5:  if obj_type == LOG_OBJ_TYPE: return true
				21: if obj_type == ORE_OBJ_TYPE: return true

	return false


## Called when a skill timer expires — resolves success/failure and yields.
## action: sub-action string for skills with multiple modes (smelt, cook, planks).
## aux:    extra data stored in the timer (e.g. inventory slot for cooking).
func _complete_skill(pid: int, skill_id: int, _tile: Vector2i,
		action: String = "", aux: Dictionary = {}) -> void:
	if not _clients.has(pid):
		return
	var client = _clients[pid]
	if client.state != _ServerClientSCR.State.CONNECTED:
		return
	var char_dict: Dictionary = client.char

	# Cancel progress bar on client (duration_ms=0 signals completion)
	_send_skill_progress(client, skill_id, 0)

	# Retrieve skill value (skills array is 0-indexed; skill_id is 1-based)
	var skills: Array = char_dict.get("skills", [])
	var skill_val: int = skills[skill_id - 1] if skill_id - 1 < skills.size() else 0

	# Success roll: 30% base + 0.6% per skill level → 90% at level 100.
	var success_chance: float = clampf(0.30 + float(skill_val) * 0.006, 0.30, 0.90)
	var crafting_action: bool = action in ["smelt", "planks", "cook"]
	if randf() > success_chance:
		# Crafting failures consume the raw material (33% of failures do so — always for crafting).
		if crafting_action:
			match action:
				"smelt":
					_remove_item_by_index(char_dict, ORE_OBJ_INDEX, SMELT_ORE_COST)
					_send_inventory(client)
					_send_server_msg(client, "You botched the smelt — the ore is ruined.")
				"planks":
					_remove_item_by_index(char_dict, LOG_OBJ_INDEX, PLANK_LOG_COST)
					_send_inventory(client)
					_send_server_msg(client, "You cut wrong — the logs are wasted.")
				"cook":
					var cook_slot_f: int = aux.get("slot", -1)
					var inv_f: Array = char_dict.get("inventory", [])
					if cook_slot_f >= 0 and cook_slot_f < inv_f.size():
						var raw_f: Dictionary = inv_f[cook_slot_f]
						raw_f["amount"] = raw_f.get("amount", 1) - 1
						if raw_f["amount"] <= 0:
							inv_f[cook_slot_f] = {}
						char_dict["inventory"] = inv_f
					_send_inventory(client)
					_send_server_msg(client, "You burned the food — it's ruined.")
		else:
			_send_server_msg(client, "You failed.")
		return

	# --- Action-specific resolution ---
	match action:
		"smelt":
			# Consume ore, produce steel
			var removed: int = _remove_item_by_index(char_dict, ORE_OBJ_INDEX, SMELT_ORE_COST)
			if removed < SMELT_ORE_COST:
				_send_server_msg(client, "You ran out of ore.")
				return
			_give_item(char_dict, STEEL_OBJ_INDEX, SMELT_STEEL_YIELD)
			_send_inventory(client)
			_send_server_msg(client, "You smelt the ore into %d steel clumps." % SMELT_STEEL_YIELD)
			# Quest craft progress
			_check_craft_quests(client, "smelt")
			_check_achievements(client, "crafts", 1)
			_update_leaderboard("crafts", char_dict.get("name", "?"),
					int(char_dict.get("achievement_progress", {}).get("crafts", 0)))

		"planks":
			# Consume logs, produce planks
			var log_removed: int = _remove_item_by_index(char_dict, LOG_OBJ_INDEX, PLANK_LOG_COST)
			if log_removed < PLANK_LOG_COST:
				_send_server_msg(client, "You ran out of logs.")
				return
			_give_item(char_dict, PLANK_OBJ_INDEX, PLANK_YIELD)
			_send_inventory(client)
			_send_server_msg(client, "You cut the logs into %d planks." % PLANK_YIELD)
			# Quest craft progress
			_check_craft_quests(client, "planks")

		"cook":
			# Convert raw ingredient in stored slot to cooked version
			var cook_slot: int = aux.get("slot", -1)
			var inv: Array = char_dict.get("inventory", [])
			if cook_slot < 0 or cook_slot >= inv.size() or (inv[cook_slot] as Dictionary).is_empty():
				_send_server_msg(client, "The ingredient is gone.")
				return
			var raw_item: Dictionary = inv[cook_slot]
			var raw_idx: int = raw_item.get("obj_index", 0)
			# obj_index 117 = raw meat → roasted meat; everything else → roasted fish
			var cooked_idx: int = ROASTED_MEAT_OBJ_INDEX if raw_idx == 117 else ROASTED_FISH_OBJ_INDEX
			# Consume one raw item, grant one cooked item
			raw_item["amount"] = raw_item.get("amount", 1) - 1
			if raw_item["amount"] <= 0:
				inv[cook_slot] = {}
			char_dict["inventory"] = inv
			_give_item(char_dict, cooked_idx, 1)
			_send_inventory(client)
			var cooked_name: String = GameData.get_object(cooked_idx).get("name", "food")
			_send_server_msg(client, "You cook the food into %s." % cooked_name)
			# Quest: cooking progress
			_check_cook_quests(client)

		_:
			# Default gathering actions (lumberjacking, mining, fishing)
			var yield_index: int  = 0
			var yield_amount: int = 1
			match skill_id:
				5:  yield_index = LOG_OBJ_INDEX
				21: yield_index = ORE_OBJ_INDEX
				20: yield_index = _fishing_yield()
			if yield_index > 0:
				_give_item(char_dict, yield_index, yield_amount)
				_send_inventory(client)
				var obj_name: String = GameData.get_object(yield_index).get("name", "item")
				_send_server_msg(client, "You obtained: %s." % obj_name)
				# Quest gather progress check
				_check_gather_quests(client)
				# Achievements for fishing
				if skill_id == 20:
					_check_achievements(client, "fish", 1)
					_update_leaderboard("fishing", char_dict.get("name", "?"),
							int(char_dict.get("achievement_progress", {}).get("fish", 0)))
					# Fishing tournament tracking
					if _tourney_active:
						var _fish_obj: Dictionary = GameData.get_object(yield_index)
						var _fish_val: int = int(_fish_obj.get("value", 1))
						var _existing_score: int = 0
						if _tourney_scores.has(client.peer_id):
							_existing_score = int(_tourney_scores[client.peer_id].get("best_catch", 0))
						_tourney_scores[client.peer_id] = {
							"name": char_dict.get("name", "?"),
							"best_catch": maxi(_existing_score, _fish_val)
						}
						# Broadcast updated scores (top 5)
						_broadcast_tourney_scores()

	# Award character XP
	var xp_gain: int = 0
	match skill_id:
		1:  xp_gain = 5    # Cooking
		4:  xp_gain = 5    # Carpenting
		5:  xp_gain = 8    # Lumberjacking
		9:  xp_gain = 12   # Smelting
		20: xp_gain = 6    # Fishing
		21: xp_gain = 10   # Mining
	if xp_gain > 0:
		char_dict["xp"] = char_dict.get("xp", 0) + xp_gain
		var levelled_up := _ServerCombatSCR.try_level_up(char_dict)
		_send_stats(client)
		var xgw := NetProtocol.PacketWriter.new()
		xgw.write_i32(xp_gain)
		client.send_auth(NetProtocol.MsgType.S_XP_GAIN, xgw.get_bytes())
		if levelled_up:
			var lw := NetProtocol.PacketWriter.new()
			lw.write_u8(char_dict.get("level", 1))
			client.send_auth(NetProtocol.MsgType.S_LEVEL_UP, lw.get_bytes())
			# Level-up sound (played only to the levelling player)
			var slw := NetProtocol.PacketWriter.new()
			slw.write_u8(SOUND_LEVEL_UP)
			client.send_auth(NetProtocol.MsgType.S_PLAY_SOUND, slw.get_bytes())
			# Level achievements & leaderboard
			_check_achievements(client, "level", 0)
			_update_leaderboard("level", char_dict.get("name", "?"), char_dict.get("level", 1))

	# Skill action sound — plays to the acting player only.
	var snd_for_skill: int = 0
	match action:
		"smelt":    snd_for_skill = SND_SMITHING      # 28 — anvil strike
		"planks":   snd_for_skill = SND_SAW           # 26 — carpentry saw
		"cook":     snd_for_skill = SND_BURN          #  7 — fire / cooking
		_:
			match skill_id:
				5:  snd_for_skill = SND_CHOPPING      # 40 — lumberjacking
				20: snd_for_skill = SND_FISHINGPOLE   #  6 — fishing
				21: snd_for_skill = SND_HAMMERING     # 17 — mining (using hammering as best proxy)
	if snd_for_skill > 0:
		var sw := NetProtocol.PacketWriter.new()
		sw.write_u8(snd_for_skill)
		client.send_auth(NetProtocol.MsgType.S_PLAY_SOUND, sw.get_bytes())

	# Award skill XP
	_award_skill_xp(client, char_dict, skill_id)

	# Persist character
	_db.save_char(client.username, char_dict)


## Returns a random fish item index from the full catch range (OBJ308–317).
## Occasionally throws back a small 1kg fish (OBJ135) for variety.
func _fishing_yield() -> int:
	if randf() < 0.15:
		return 135   # 1kg fish — small catch
	return randi_range(RAW_FISH_MIN, RAW_FISH_MAX)


## Award skill XP and level up the skill if the XP threshold is crossed.
## Each level requires more XP than the last (exponential curve).
func _award_skill_xp(client, char_dict: Dictionary, skill_id: int) -> void:
	var gain: int = SKILL_ACTION_XP.get(skill_id, 10)
	var skills:   Array = char_dict.get("skills",   [])
	var skill_xp: Array = char_dict.get("skill_xp", [])
	while skills.size()   < 28: skills.append(0)
	while skill_xp.size() < 28: skill_xp.append(0)

	var idx: int = skill_id - 1
	var lv:  int = skills[idx]
	if lv >= 100:
		return   # already maxed

	skill_xp[idx] += gain
	var needed: int = _skill_xp_to_next(lv)

	# Level-up loop (handles gaining multiple levels at low skill levels)
	while skill_xp[idx] >= needed and lv < 100:
		skill_xp[idx] -= needed
		lv += 1
		skills[idx] = lv
		needed = _skill_xp_to_next(lv)
		_send_skill_raise(client, skill_id, lv)
		var skill_name: String = SKILL_NAMES[skill_id] if skill_id < SKILL_NAMES.size() else "skill"
		_send_server_msg(client, "@Your %s skill has improved to level %d!" % [skill_name, lv])

	char_dict["skills"]   = skills
	char_dict["skill_xp"] = skill_xp

	# Always push current XP progress to client even if no level-up occurred
	_send_skill_xp(client, skill_id, skill_xp[idx], _skill_xp_to_next(lv))


## Add yield_amount of obj_index to the character's inventory (stack or find slot).
func _give_item(char_dict: Dictionary, obj_index: int, amount: int) -> void:
	var inv: Array = char_dict.get("inventory", [])
	# Ensure at least 20 slots exist
	while inv.size() < 20:
		inv.append({})
	# Try to stack into an existing non-equipped slot
	for item in inv:
		var d: Dictionary = item as Dictionary
		if not d.is_empty() and d.get("obj_index", 0) == obj_index \
				and not d.get("equipped", false):
			d["amount"] = d.get("amount", 0) + amount
			char_dict["inventory"] = inv
			return
	# Find first empty slot
	for i in inv.size():
		if (inv[i] as Dictionary).is_empty():
			inv[i] = {"obj_index": obj_index, "amount": amount, "equipped": false, "slot": i + 1}
			char_dict["inventory"] = inv
			return
	# Inventory full — silently drop
	print("[Server] Inventory full — cannot give obj_index=%d" % obj_index)


## Send S_SKILL_PROGRESS to client. duration_ms=0 means cancel/done.
func _send_skill_progress(client, skill_id: int, duration_ms: int) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(skill_id)
	w.write_u16(duration_ms)
	client.send_auth(NetProtocol.MsgType.S_SKILL_PROGRESS, w.get_bytes())


## Send S_SKILL_RAISE to client.
func _send_skill_raise(client, skill_id: int, new_value: int) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(skill_id)
	w.write_i16(new_value)
	client.send_auth(NetProtocol.MsgType.S_SKILL_RAISE, w.get_bytes())


## Send S_SKILL_XP — live XP progress within the current skill level.
func _send_skill_xp(client, skill_id: int, current_xp: int, xp_needed: int) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(skill_id)
	w.write_i32(current_xp)
	w.write_i32(xp_needed)
	client.send_auth(NetProtocol.MsgType.S_SKILL_XP, w.get_bytes())


# ---------------------------------------------------------------------------
# Enter world
# ---------------------------------------------------------------------------

func _enter_world(client, char_dict: Dictionary) -> void:
	client.char  = char_dict
	client.state = _ServerClientSCR.State.CONNECTED

	# Apply admin role from admins.txt
	if client.username.to_lower() in _admin_names:
		if int(char_dict.get("role", 0)) < 2:
			char_dict["role"] = 2
			print("[Admin] Auto-promoted %s to admin from admins.txt" % client.username)

	# Migrate old infinite-mana characters: cap max_mp to class-appropriate value.
	if char_dict.get("max_mp", 0) > 500:
		var class_caps := {0: 30, 1: 120, 2: 60, 3: 80}
		var cid: int = char_dict.get("class_id", 0)
		var lvl: int = char_dict.get("level", 1)
		var mp_inc := {0: 2, 1: 14, 2: 5, 3: 7}
		var cap: int = class_caps.get(cid, 60) + mp_inc.get(cid, 5) * (lvl - 1)
		char_dict["max_mp"] = cap
		char_dict["mp"]     = mini(char_dict.get("mp", 0), cap)

	# Redirect characters saved on restricted maps back to spawn (RESTRICTED_MAPS is
	# currently empty — new chars always start at SPAWN_MAP via _create_character).
	if char_dict.get("map_id", 1) in RESTRICTED_MAPS:
		char_dict["map_id"] = SPAWN_MAP
		char_dict["x"]      = SPAWN_X
		char_dict["y"]      = SPAWN_Y

	var map_id: int = char_dict.get("map_id", 1)
	var cx: int     = char_dict.get("x", 10)
	var cy: int     = char_dict.get("y", 10)

	# Track visited maps for explore objectives
	var visited: Array = char_dict.get("visited_maps", [])
	if not visited.has(map_id):
		visited.append(map_id)
		char_dict["visited_maps"] = visited

	# S_WORLD_STATE — triggers WorldMap to load
	var ww := NetProtocol.PacketWriter.new()
	ww.write_i32(map_id)
	ww.write_i16(cx)
	ww.write_i16(cy)
	client.send_auth(NetProtocol.MsgType.S_WORLD_STATE, ww.get_bytes())

	# Normalize spells array to int (avoids string/int duplicates from old saves).
	var raw_spells: Array = char_dict.get("spells", [])
	var seen_int: Dictionary = {}
	for s in raw_spells:
		seen_int[int(s)] = true
	var char_spells: Array = seen_int.keys()
	char_spells.sort()
	char_dict["spells"] = char_spells
	if char_spells.size() != raw_spells.size():
		_db.save_char(client.username, char_dict)

	# Send full stats, inventory, skills, vitals, spellbook and ability list
	_send_stats(client)
	_send_inventory(client)
	_send_skills(client)
	_send_vitals(client)
	_send_spellbook(client)
	_send_abilities(client)
	_send_hotbar(client)

	# Send any ground items on this map
	_send_ground_items_for_map(client, map_id)

	# Send current weather state
	if _raining:
		client.send_auth(NetProtocol.MsgType.S_RAIN_ON, PackedByteArray())

	# Spawn NPCs for this map if not yet spawned
	if not _spawned_maps.has(map_id):
		_spawn_map_npcs(map_id)
		_spawn_hardcoded_npcs(map_id)

	# Announce this player to nearby clients, and send nearby players to this client
	_broadcast_set_char(client)
	for pid in _clients:
		if pid == client.peer_id:
			continue
		var other = _clients[pid]
		if other.state != _ServerClientSCR.State.CONNECTED:
			continue
		var oc: Dictionary = other.char
		if oc.get("map_id", -1) != map_id:
			continue
		var dist := maxi(abs(oc.get("x",0) - cx), abs(oc.get("y",0) - cy))
		if dist <= NEARBY_RANGE:
			# Send other to us (skip if they are invisible)
			if not _invisible.has(other.peer_id):
				_send_set_char(client, other)
			# Send us to other (skip if we are invisible)
			if not _invisible.has(client.peer_id):
				_send_set_char(other, client)

	# Send all alive NPCs on this map to the joining client
	for nid in _npcs:
		var npc: Dictionary = _npcs[nid]
		if npc["map_id"] == map_id and npc["ai_state"] != "dead":
			_send_npc_set_char(client, npc)

	# Check explore quests (client has accepted quests for this map_id)
	_check_explore_quests(client, map_id)
	# Send quest indicators for NPCs on this map
	_send_quest_indicators(client)

	# Daily login reward
	_check_daily_login(client)

	# Sync time of day immediately on world entry
	var _tod_min: int = int(_time_of_day * 60.0) % 1440
	var _tod_w := NetProtocol.PacketWriter.new()
	_tod_w.write_u16(_tod_min)
	client.send_auth(S_TIME_OF_DAY, _tod_w.get_bytes())

	# Map exploration achievement
	_check_achievements(client, "maps", 0)

	print("[Server] %s entered map %d @ (%d,%d)" % [
		char_dict.get("name","?"), map_id, cx, cy])


# ---------------------------------------------------------------------------
# NPC Spawning
# ---------------------------------------------------------------------------

func _spawn_map_npcs(map_id: int) -> void:
	## Spawns all NPCs defined in the map tile data. Called once per map.
	_spawned_maps[map_id] = true
	var map_data := GameData.get_map(map_id)
	if map_data.is_empty():
		return

	var spawned_count := 0
	for key in map_data.get("tiles", {}):
		var tile: Dictionary = map_data["tiles"][key]
		var npc_idx: int = tile.get("npc_index", 0)
		if npc_idx <= 0:
			continue

		# Parse tile key "y,x"
		var parts: PackedStringArray = key.split(",")
		if parts.size() < 2:
			continue
		var ty := int(parts[0])
		var tx := int(parts[1])

		var npc_data := GameData.get_npc(npc_idx)
		if npc_data.is_empty():
			print("[Server] WARNING: Unknown NPC %d on map %d tile %s" % [npc_idx, map_id, key])
			continue

		# Build effective data dict — shallow copy so we can override fields
		var eff_data: Dictionary = npc_data.duplicate(false)

		# Classify role based on VB6 fields
		var is_hostile: bool  = npc_data.get("hostile", 0) != 0
		var attackable: bool  = npc_data.get("attackable", 0) != 0
		var inventory: Array  = npc_data.get("inventory", [])

		# Skip non-hostile, non-attackable NPCs from tile data entirely.
		# Service NPCs (bankers, smiths, tailors, etc.) are controlled exclusively
		# via _spawn_hardcoded_npcs so they only appear in the intended towns.
		if (not is_hostile) and (not attackable):
			continue

		# All tile-data NPCs reaching here are hostile or attackable
		eff_data["npc_type"] = 1
		var drops: Array = []
		for inv_entry in inventory:
			var oi: int = int(inv_entry.get("obj_index", 0))
			if oi > 0:
				drops.append(oi)
		if not drops.is_empty():
			eff_data["drop_items"] = drops

		# Combat stats: use VB6 data directly; fall back to level-based formulas
		var level: int = maxi(1, int(npc_data.get("level", 1)))
		var max_hp: int = int(npc_data.get("max_hp", 0))
		if max_hp <= 0:
			max_hp = level * 15 + 20 if is_hostile else 300
		var min_hit: int = int(npc_data.get("min_hit", 0))
		if min_hit <= 0:
			min_hit = maxi(1, level - 1) if is_hostile else 0
		var max_hit: int = int(npc_data.get("max_hit", 0))
		if max_hit <= 0:
			max_hit = (level * 2 + 2) if is_hostile else 0
		var def_v: int = int(npc_data.get("def", 0))
		var give_exp: int = int(npc_data.get("give_exp", level * 15))
		var heading: int = int(npc_data.get("heading", 3))
		if heading <= 0:
			heading = 3

		var instance_id := _npc_counter
		_npc_counter += 1

		var npc_state: Dictionary = {
			"instance_id": instance_id,
			"npc_index":   npc_idx,
			"map_id":      map_id,
			"x":           tx,
			"y":           ty,
			"spawn_x":     tx,
			"spawn_y":     ty,
			"heading":     heading,
			"hp":          max_hp,
			"max_hp":      max_hp,
			"min_hit":     min_hit,
			"max_hit":     max_hit,
			"def":         def_v,
			"give_exp":    give_exp,
			"ai_state":    "idle",
			"target_peer": 0,
			"next_action_at": 0.0,
			"respawn_at":  0.0,
			"data":        eff_data,
		}
		_npc_init_behavior(npc_state)
		_schedule_npc_next_action(npc_state, Time.get_ticks_msec() / 1000.0, "idle")
		_npcs[instance_id] = npc_state
		_broadcast_npc_set_char(npc_state)
		spawned_count += 1

	print("[Server] Spawned %d NPCs on map %d" % [spawned_count, map_id])


func _load_hardcoded_spawns() -> void:
	## Loads npc_spawns.json once and caches in _hardcoded_spawns.
	var path := ProjectSettings.globalize_path("res://data/npc_spawns.json")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[Server] npc_spawns.json not found at " + path)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_hardcoded_spawns = parsed
	else:
		push_warning("[Server] npc_spawns.json parse failed")


func _spawn_hardcoded_npcs(map_id: int) -> void:
	## Spawns hand-placed NPCs for specific maps. Reads from data/npc_spawns.json.
	## Each entry: {"npc_index": N, "x": X, "y": Y}  — loads from NPC.dat
	##         or: {full inline dict with "name","x","y",...} — custom NPC
	if _hardcoded_spawns.is_empty():
		_load_hardcoded_spawns()
	var pos_defs: Array = _hardcoded_spawns.get(str(map_id), [])

	var count := 0
	for d in pos_defs:
		var eff_data: Dictionary
		var max_hp: int
		var min_hit: int = 0
		var max_hit: int = 0
		var def_v:  int = 0
		var heading: int = 3
		var give_exp: int = 0
		var npc_idx: int = d.get("npc_index", 0)

		if npc_idx > 0:
			var npc_raw := GameData.get_npc(npc_idx)
			if npc_raw.is_empty():
				print("[Server] WARNING: Unknown NPC %d in hardcoded spawn for map %d" % [
						npc_idx, map_id])
				continue
			eff_data = npc_raw.duplicate(false)
			var is_hostile: bool = npc_raw.get("hostile", 0) != 0
			var attackable: bool = npc_raw.get("attackable", 0) != 0
			var inventory: Array = npc_raw.get("inventory", [])
			if (not is_hostile) and (not attackable) and inventory.size() >= 5:
				eff_data["npc_type"] = 2
				var shop_items: Array = []
				for inv_entry in inventory:
					var oi: int = int(inv_entry.get("obj_index", 0))
					if oi > 0:
						shop_items.append(oi)
				eff_data["items"] = shop_items
			elif is_hostile or attackable:
				eff_data["npc_type"] = 1
			else:
				eff_data["npc_type"] = 0
			max_hp  = int(npc_raw.get("max_hp", 0))
			if max_hp <= 0:
				max_hp = 300
			min_hit  = int(npc_raw.get("min_hit", 0))
			max_hit  = int(npc_raw.get("max_hit", 0))
			# Service NPCs with no attack stats are non-combat regardless of VB6 hostile flag.
			if max_hit <= 0 and min_hit <= 0 and eff_data.get("npc_type", 0) == 1:
				eff_data["npc_type"] = 0
				eff_data["hostile"] = 0
				eff_data["attackable"] = 0
			def_v    = int(npc_raw.get("def", 0))
			give_exp = int(npc_raw.get("give_exp", 0))
			heading  = int(npc_raw.get("heading", 3))
			if heading <= 0:
				heading = 3
		else:
			eff_data = d
			max_hp  = int(d.get("max_hp", 500))
			min_hit = int(d.get("min_hit", 0))
			max_hit = int(d.get("max_hit", 0))
			def_v   = int(d.get("def", 0))
			heading = int(d.get("heading", 3))

		var instance_id := _npc_counter
		_npc_counter += 1
		var npc_state: Dictionary = {
			"instance_id": instance_id,
			"npc_index":   npc_idx,
			"map_id":      map_id,
			"x":           d["x"],
			"y":           d["y"],
			"spawn_x":     d["x"],
			"spawn_y":     d["y"],
			"heading":     heading,
			"hp":          max_hp,
			"max_hp":      max_hp,
			"min_hit":     min_hit,
			"max_hit":     max_hit,
			"def":         def_v,
			"give_exp":    give_exp,
			"ai_state":    "idle",
			"target_peer": 0,
			"next_action_at": 0.0,
			"respawn_at":  0.0,
			"data":        eff_data,
		}
		_npc_init_behavior(npc_state)
		_schedule_npc_next_action(npc_state, Time.get_ticks_msec() / 1000.0, "idle")
		_npcs[instance_id] = npc_state
		_broadcast_npc_set_char(npc_state)
		count += 1
	if count > 0:
		print("[Server] Spawned %d hardcoded NPCs on map %d" % [count, map_id])


# ---------------------------------------------------------------------------
# NPC AI — 9 behaviour archetypes
# ---------------------------------------------------------------------------

## Maps NPC index → behaviour archetype string.
## Unlisted NPCs default to "wanderer" (hostile) or "civilian" (non-hostile).
const NPC_BEHAVIOR_TABLE: Dictionary = {
	# ── passive ─────────────────────────────────────────────────────────────
	# Flee when attacked; never initiate. Domestic/farm animals.
	512: "passive", 513: "passive", 514: "passive",
	515: "passive", 516: "passive", 517: "passive", 518: "passive",

	# ── skittish ─────────────────────────────────────────────────────────────
	# Flee from players on sight (cowardly critters).
	508: "skittish", 509: "skittish", 510: "skittish", 528: "skittish",

	# ── wanderer ─────────────────────────────────────────────────────────────
	# Mindless undead / lone creatures: meander aimlessly, attack anything in range.
	502: "wanderer", 503: "wanderer", 511: "wanderer",
	523: "wanderer", 506: "wanderer", 525: "wanderer", 527: "wanderer",

	# ── aggressive ───────────────────────────────────────────────────────────
	# Charge immediately; pursue relentlessly; fight to death.
	501: "aggressive", 531: "aggressive", 507: "aggressive",
	529: "aggressive", 524: "aggressive", 520: "aggressive",
	9:   "aggressive", 76:  "aggressive", 142: "aggressive", 211: "aggressive",

	# ── pack_hunter ──────────────────────────────────────────────────────────
	# Call nearby kin when engaged; surround target.
	521: "pack_hunter", 526: "pack_hunter", 519: "pack_hunter",

	# ── caster ───────────────────────────────────────────────────────────────
	# Prefer ranged distance; kite & cast; melee only as fallback.
	504: "caster", 56: "caster", 123: "caster", 191: "caster",
	259: "caster", 505: "caster",

	# ── berserker ────────────────────────────────────────────────────────────
	# Slow to anger but unstoppable; attack speed ramps up when low HP.
	500: "berserker", 532: "berserker", 533: "berserker",
	522: "berserker", 530: "berserker",

	# ── patrol ───────────────────────────────────────────────────────────────
	# Walk a simple patrol route; engage lawbreakers / aggressive players.
	57: "patrol", 124: "patrol", 192: "patrol", 260: "patrol", 271: "patrol",

	# ── boss ─────────────────────────────────────────────────────────────────
	# Phase changes; calls minions; has enrage threshold.
	534: "boss", 535: "boss",
}


func _npc_behavior_for(npc: Dictionary) -> String:
	var npc_data: Dictionary = npc["data"]
	var idx: int = npc.get("npc_index", 0)
	if NPC_BEHAVIOR_TABLE.has(idx):
		return NPC_BEHAVIOR_TABLE[idx]
	if npc_data.get("hostile", 0) != 0:
		return "wanderer"
	return "civilian"


func _npc_init_behavior(npc: Dictionary) -> void:
	## Called once at spawn time — writes behavior-specific state fields.
	var beh := _npc_behavior_for(npc)
	npc["behavior"] = beh
	npc["enraged"]  = false   # berserker / boss phase flag
	npc["patrol_dir"] = 1     # patrol direction toggle
	match beh:
		"caster":
			npc["spell_ready_at"] = 0.0
		"boss":
			npc["phase"] = 1
			npc["minions_spawned"] = false


func _schedule_npc_next_action(npc: Dictionary, now: float, mode: String) -> void:
	var delay := NPC_IDLE_ACTION_MIN
	var beh: String = npc.get("behavior", "wanderer")
	match mode:
		"chase":
			delay = randf_range(NPC_CHASE_ACTION_MIN, NPC_CHASE_ACTION_MAX)
			# Berserkers speed up when low HP
			if beh == "berserker" and npc.get("enraged", false):
				delay *= 0.55
		"attack":
			delay = randf_range(NPC_ATTACK_COOLDOWN_MIN, NPC_ATTACK_COOLDOWN_MAX)
			if beh == "berserker" and npc.get("enraged", false):
				delay *= 0.55
		_:
			delay = randf_range(NPC_IDLE_ACTION_MIN, NPC_IDLE_ACTION_MAX)
	npc["next_action_at"] = now + delay


func _heading_toward(nx: int, ny: int, tx: int, ty: int) -> int:
	var dx := tx - nx
	var dy := ty - ny
	if abs(dx) >= abs(dy):
		if dx > 0:
			return 2
		if dx < 0:
			return 4
	if dy < 0:
		return 1
	if dy > 0:
		return 3
	return 3


func _npc_turn_in_place(npc: Dictionary, target_heading: int = 0) -> void:
	var new_heading := target_heading
	if new_heading <= 0:
		new_heading = [1, 2, 3, 4].pick_random()
	if npc["heading"] == new_heading:
		return
	npc["heading"] = new_heading
	_broadcast_npc_set_char(npc)


## ── Main AI dispatcher ─────────────────────────────────────────────────────

func _tick_npc_ai(now: float) -> void:
	## Called every NPC_AI_INTERVAL seconds. Drives all NPC behaviour.

	# ── Build per-map player + client caches (one pass, shared by all NPCs + broadcasts) ──
	_ai_map_players.clear()
	_ai_map_clients.clear()
	for pid in _clients:
		var cl = _clients[pid]
		if cl.state != _ServerClientSCR.State.CONNECTED:
			continue
		var tc: Dictionary = cl.char
		var mid: int = tc.get("map_id", -1)
		if mid < 0:
			continue
		if not _ai_map_players.has(mid):
			_ai_map_players[mid] = []
			_ai_map_clients[mid] = []
		_ai_map_players[mid].append({
			"pid":   pid,
			"x":     tc.get("x", 0),
			"y":     tc.get("y", 0),
			"level": tc.get("level", 1),
		})
		_ai_map_clients[mid].append({"pid": pid, "cl": cl, "x": tc.get("x", 0), "y": tc.get("y", 0)})

	# ── Encounter NPC auto-despawn (moved here from _process to reduce frame overhead) ──
	for eid in _encounter_despawn_at.keys().duplicate():
		if now >= _encounter_despawn_at[eid]:
			_encounter_despawn_at.erase(eid)
			if _npcs.has(eid) and _npcs[eid].get("ai_state", "") != "chase":
				_despawn_npc(eid, _npcs[eid]["map_id"])

	# ── NPC AI dispatch ──────────────────────────────────────────────────────
	for nid in _npcs:
		var npc: Dictionary = _npcs[nid]
		if npc["ai_state"] == "dead":
			continue
		var npc_data: Dictionary = npc["data"]

		# Initialise behavior field if spawned before this system was in place
		if not npc.has("behavior"):
			_npc_init_behavior(npc)

		# Summoned familiars use their own hunter AI
		if npc_data.get("summoned_by", 0) > 0:
			_tick_summon_ai(npc, now)
			continue

		var beh: String = npc.get("behavior", "wanderer")

		# Non-hostile archetypes
		match beh:
			"civilian", "passive":
				_tick_civilian_ai(npc, now)
				continue
			"skittish":
				_tick_skittish_ai(npc, now)
				continue
			"patrol":
				_tick_patrol_ai(npc, now)
				continue

		# All hostile archetypes share the same state machine
		_tick_hostile_ai(npc, now, beh)


## ── Civilian / passive ──────────────────────────────────────────────────────

func _tick_civilian_ai(npc: Dictionary, now: float) -> void:
	var npc_data: Dictionary = npc["data"]
	var movement_v: int = npc_data.get("movement", 0)
	if movement_v >= 2 and npc_data.get("npc_type", 0) != 2:
		if now >= float(npc.get("next_action_at", 0.0)):
			if randf() < 0.4:
				_npc_wander(npc)
			elif randf() < 0.5:
				_npc_turn_in_place(npc)
			_schedule_npc_next_action(npc, now, "idle")


## ── Skittish ────────────────────────────────────────────────────────────────

func _tick_skittish_ai(npc: Dictionary, now: float) -> void:
	## Runs from any player that enters detect range.
	if now < float(npc.get("next_action_at", 0.0)):
		return
	var map_id: int = int(npc["map_id"])
	var nx: int     = int(npc["x"])
	var ny: int     = int(npc["y"])
	if _ai_map_players.has(map_id):
		for entry: Dictionary in _ai_map_players[map_id]:
			var dist := maxi(abs(int(entry["x"]) - nx), abs(int(entry["y"]) - ny))
			if dist <= NPC_DETECT_RANGE:
				_npc_flee_step(npc, entry["x"], entry["y"])
				npc["next_action_at"] = now + randf_range(NPC_FLEE_SPEED_MIN, NPC_FLEE_SPEED_MAX)
				return
	# Nobody nearby — wander idly
	if randf() < 0.45:
		_npc_wander(npc)
	_schedule_npc_next_action(npc, now, "idle")


func _npc_flee_step(npc: Dictionary, threat_x: int, threat_y: int) -> void:
	## Takes one step directly away from (threat_x, threat_y).
	var nx: int    = int(npc["x"])
	var ny: int    = int(npc["y"])
	var map_id: int = int(npc["map_id"])
	var dx := nx - threat_x  # reverse direction
	var dy := ny - threat_y
	var candidates: Array = []
	if abs(dx) >= abs(dy):
		if dx != 0:
			candidates.append(Vector2i(nx + sign(dx), ny))
		if dy != 0:
			candidates.append(Vector2i(nx, ny + sign(dy)))
	else:
		if dy != 0:
			candidates.append(Vector2i(nx, ny + sign(dy)))
		if dx != 0:
			candidates.append(Vector2i(nx + sign(dx), ny))
	# Fallback: random orthogonal step
	candidates.append(Vector2i(nx + int(([-1, 1] as Array).pick_random()), ny))
	candidates.append(Vector2i(nx, ny + int(([-1, 1] as Array).pick_random())))
	for step: Vector2i in candidates:
		var sx: int = step.x
		var sy: int = step.y
		if sx < 1 or sx > 100 or sy < 1 or sy > 100:
			continue
		if GameData.get_map_tile(map_id, sx, sy).get("blocked", 0) != 0:
			continue
		var move_dx := sx - nx
		var move_dy := sy - ny
		var new_heading := 3
		if move_dy < 0:   new_heading = 1
		elif move_dx > 0: new_heading = 2
		elif move_dy > 0: new_heading = 3
		elif move_dx < 0: new_heading = 4
		npc["x"] = sx
		npc["y"] = sy
		npc["heading"] = new_heading
		var w := NetProtocol.PacketWriter.new()
		w.write_i32(npc["instance_id"])
		w.write_i16(sx); w.write_i16(sy); w.write_u8(new_heading)
		_broadcast_nearby(map_id, sx, sy, NetProtocol.MsgType.S_MOVE_CHAR, w.get_bytes(), -1)
		break


## ── Patrol ──────────────────────────────────────────────────────────────────

func _tick_patrol_ai(npc: Dictionary, now: float) -> void:
	## Walk a back-and-forth horizontal patrol; engage hostiles nearby.
	if now < float(npc.get("next_action_at", 0.0)):
		return
	var map_id: int = int(npc["map_id"])
	var nx: int     = int(npc["x"])
	var ny: int     = int(npc["y"])

	# Check for criminal players using the per-tick cache
	if _ai_map_players.has(map_id):
		for entry: Dictionary in _ai_map_players[map_id]:
			if not _clients.has(entry["pid"]):
				continue
			if not _clients[entry["pid"]].char.get("criminal", false):
				continue
			var dist := maxi(abs(int(entry["x"]) - nx), abs(int(entry["y"]) - ny))
			if dist <= NPC_DETECT_RANGE:
				npc["ai_state"]    = "chase"
				npc["target_peer"] = entry["pid"]
				npc["next_action_at"] = now + 0.3
				return

	# Patrol: step east/west; reverse at boundary (±8 from spawn)
	var dir: int = npc.get("patrol_dir", 1)
	var tx: int  = nx + dir
	if abs(tx - npc["spawn_x"]) > 8:
		dir = -dir
		npc["patrol_dir"] = dir
		tx = nx + dir
	var tile := GameData.get_map_tile(map_id, tx, ny)
	if tile.get("blocked", 0) != 0:
		dir = -dir
		npc["patrol_dir"] = dir
		tx = nx + dir
	if GameData.get_map_tile(map_id, tx, ny).get("blocked", 0) == 0:
		npc["x"] = tx
		npc["heading"] = 2 if dir > 0 else 4
		var w := NetProtocol.PacketWriter.new()
		w.write_i32(npc["instance_id"])
		w.write_i16(tx); w.write_i16(ny); w.write_u8(npc["heading"])
		_broadcast_nearby(map_id, tx, ny, NetProtocol.MsgType.S_MOVE_CHAR, w.get_bytes(), -1)
	_schedule_npc_next_action(npc, now, "idle")


## ── Hostile unified state machine ───────────────────────────────────────────

func _tick_hostile_ai(npc: Dictionary, now: float, beh: String) -> void:
	var npc_data: Dictionary = npc["data"]
	var movement: int = npc_data.get("movement", 0)
	var map_id: int   = npc["map_id"]

	match npc["ai_state"]:
		"idle":
			# Gate all idle work (wander + player scan) behind a single timer.
			# This means each NPC scans at most once per 1.2–2.4 s instead of
			# every AI tick (0.5 s), cutting scan work by ~3×.
			if now < float(npc.get("next_action_at", 0.0)):
				return

			# Wander / turn before scanning
			if movement >= 1:
				if beh == "wanderer" or beh == "aggressive":
					if randf() < 0.55:
						_npc_wander(npc)
					elif randf() < 0.4:
						_npc_turn_in_place(npc)
				elif randf() < 0.35:
					_npc_wander(npc)

			# Scan for nearby players (cache lookup — O(players on map))
			var nearest := _npc_nearest_player_in_range(npc, NPC_DETECT_RANGE)
			if nearest >= 0:
				npc["ai_state"]    = "chase"
				npc["target_peer"] = nearest
				npc["next_action_at"] = now + randf_range(0.15, 0.45)
				if beh == "pack_hunter":
					_npc_call_for_help(npc)
				return

			_schedule_npc_next_action(npc, now, "idle")

		"chase":
			var tc: Dictionary = _npc_get_valid_target(npc)
			if tc.is_empty():
				_npc_reset_to_idle(npc)
				return

			var tx: int = tc.get("x", 0)
			var ty: int = tc.get("y", 0)
			var dist := maxi(abs(tx - npc["x"]), abs(ty - npc["y"]))

			# Leash — how far will this NPC chase?
			var leash := 15
			if beh == "berserker" or beh == "boss":
				leash = 25  # persistent chasers
			elif beh == "caster":
				leash = 18
			if dist > leash:
				_npc_reset_to_idle(npc)
				return

			if now < float(npc.get("next_action_at", 0.0)):
				return

			# ── Boss phase-change check ────────────────────────────────────
			if beh == "boss":
				_npc_boss_phase_change(npc)

			# ── Berserker enrage check ─────────────────────────────────────
			if beh == "berserker":
				var hp_pct := float(npc.get("hp", 1)) / float(npc.get("max_hp", 1))
				if hp_pct < 0.35 and not npc.get("enraged", false):
					npc["enraged"] = true
					var mw := NetProtocol.PacketWriter.new()
					mw.write_str("%s ENRAGES!" % npc["data"].get("name", "The creature"))
					_broadcast_msg_to_map(map_id, mw)

			# ── Caster kiting logic ────────────────────────────────────────
			if beh == "caster":
				# Ideal distance: 3–6 tiles
				if dist < 3 and movement >= 1:
					# Back away
					_npc_flee_step(npc, tx, ty)
					_schedule_npc_next_action(npc, now, "chase")
					return
				if now >= float(npc.get("spell_ready_at", 0.0)):
					_npc_caster_attack(npc, tc)
					npc["spell_ready_at"] = now + randf_range(NPC_SPELL_COOLDOWN_MIN,
							NPC_SPELL_COOLDOWN_MAX)
					_schedule_npc_next_action(npc, now, "attack")
					return
				if dist > NPC_CASTER_RANGE and movement >= 1:
					_npc_step_toward(npc, tx, ty)
				_schedule_npc_next_action(npc, now, "chase")
				return

			# ── Standard melee ────────────────────────────────────────────
			if dist <= NPC_ATTACK_RANGE:
				_npc_attack(npc)
				_schedule_npc_next_action(npc, now, "attack")
			elif movement >= 1:
				# Pack hunters try to flank (occasional diagonal offset)
				if beh == "pack_hunter" and randf() < 0.3:
					var flank_tx := tx + randi_range(-2, 2)
					var flank_ty := ty + randi_range(-2, 2)
					_npc_step_toward(npc, flank_tx, flank_ty)
				else:
					_npc_step_toward(npc, tx, ty)
				_schedule_npc_next_action(npc, now, "chase")


## ── Helper: nearest player in range ────────────────────────────────────────

## Returns true if offset (dx, dy) from attacker falls within the frontal 180°
## arc for the given VB6 heading (1=N 2=E 3=S 4=W).
## Targets directly to the side (on the perpendicular axis) are included;
## only targets clearly behind the attacker are excluded.
func _in_melee_arc(heading: int, dx: int, dy: int) -> bool:
	match heading:
		1: return dy <= 0   # facing NORTH — target must not be south of player
		2: return dx >= 0   # facing EAST  — target must not be west of player
		3: return dy >= 0   # facing SOUTH — target must not be north of player
		4: return dx <= 0   # facing WEST  — target must not be east of player
	return true


func _npc_nearest_player_in_range(npc: Dictionary, range_tiles: int) -> int:
	## Uses the per-tick _ai_map_players cache — no client dict iteration.
	var map_id: int = int(npc["map_id"])
	var nx: int     = int(npc["x"])
	var ny: int     = int(npc["y"])
	if not _ai_map_players.has(map_id):
		return -1
	var best_pid  := -1
	var best_dist := range_tiles + 1
	for entry: Dictionary in _ai_map_players[map_id]:
		var dist := maxi(abs(int(entry["x"]) - nx), abs(int(entry["y"]) - ny))
		if dist < best_dist:
			best_dist = dist
			best_pid  = entry["pid"]
	return best_pid


func _npc_get_valid_target(npc: Dictionary) -> Dictionary:
	## Returns the target player's char dict, or {} if invalid / left map.
	var target_peer: int = npc.get("target_peer", 0)
	if not _clients.has(target_peer):
		return {}
	var cl = _clients[target_peer]
	if cl.state != _ServerClientSCR.State.CONNECTED:
		return {}
	var tc: Dictionary = cl.char
	if tc.get("map_id", -1) != npc["map_id"]:
		return {}
	return tc


## ── Pack-hunter call for help ────────────────────────────────────────────────

func _npc_call_for_help(npc: Dictionary) -> void:
	## Wake up all idle pack-members within 12 tiles and set them on the same target.
	var map_id: int = npc["map_id"]
	var nx: int     = npc["x"]
	var ny: int     = npc["y"]
	var target_peer: int = npc.get("target_peer", 0)
	for nid in _npcs:
		if nid == npc["instance_id"]:
			continue
		var other: Dictionary = _npcs[nid]
		if other.get("map_id", -1) != map_id:
			continue
		if other.get("ai_state", "dead") == "dead":
			continue
		if other.get("behavior", "") not in ["pack_hunter", "wanderer", "aggressive"]:
			continue
		var dist := maxi(abs(int(other["x"]) - nx), abs(int(other["y"]) - ny))
		if dist <= 12 and other["ai_state"] == "idle":
			other["ai_state"]    = "chase"
			other["target_peer"] = target_peer
			other["next_action_at"] = Time.get_ticks_msec() / 1000.0 + randf_range(0.3, 0.9)


## ── Boss phase transition ────────────────────────────────────────────────────

func _npc_boss_phase_change(npc: Dictionary) -> void:
	var hp_pct := float(npc.get("hp", 1)) / float(npc.get("max_hp", 1))
	var current_phase: int = npc.get("phase", 1)

	# Phase 2: ≤ 60 % HP — speed increase
	if current_phase == 1 and hp_pct <= 0.60:
		npc["phase"]   = 2
		npc["enraged"] = true
		var mw := NetProtocol.PacketWriter.new()
		mw.write_str("%s grows more dangerous!" % npc["data"].get("name", "The boss"))
		_broadcast_msg_to_map(npc["map_id"], mw)

	# Phase 3: ≤ 30 % HP — summon minions once
	if current_phase <= 2 and hp_pct <= 0.30 and not npc.get("minions_spawned", false):
		npc["phase"]           = 3
		npc["minions_spawned"] = true
		# Spawn 2 wanderer minions adjacent to boss
		for _i in range(2):
			var mx: int = int(npc["x"]) + randi_range(-3, 3)
			var my: int = int(npc["y"]) + randi_range(-3, 3)
			mx = clampi(mx, 1, 100)
			my = clampi(my, 1, 100)
			var minion_data := {
				"name": "Minion", "hostile": 1, "attackable": 1,
				"body": 2, "head": 1, "heading": 3, "movement": 2,
				"max_hp": 120, "min_hit": 4, "max_hit": 10, "def": 2,
				"level": npc["data"].get("level", 10),
				"give_exp": 0, "give_gld": 0,
			}
			var mid := _npc_counter
			_npc_counter += 1
			var minion: Dictionary = {
				"instance_id": mid,
				"npc_index":   0,
				"map_id":      npc["map_id"],
				"x": mx, "y": my, "spawn_x": mx, "spawn_y": my,
				"heading": 3, "hp": 120, "max_hp": 120,
				"min_hit": 4, "max_hit": 10, "def": 2,
				"give_exp": 0, "ai_state": "chase",
				"target_peer": npc.get("target_peer", 0),
				"next_action_at": 0.0, "respawn_at": 0.0,
				"data": minion_data,
			}
			_npc_init_behavior(minion)
			_npcs[mid] = minion
			_broadcast_npc_set_char(minion)
		var mw2 := NetProtocol.PacketWriter.new()
		mw2.write_str("%s calls for minions!" % npc["data"].get("name", "The boss"))
		_broadcast_msg_to_map(npc["map_id"], mw2)


## ── Caster ranged attack ─────────────────────────────────────────────────────

func _npc_caster_attack(npc: Dictionary, tc: Dictionary) -> void:
	## Deals magical damage scaled by NPC level; bypasses some DEF.
	var npc_level: int = maxi(1, npc["data"].get("level", 1))
	var raw_dmg := randi_range(npc_level * 2, npc_level * 4)
	# Casters bypass half of DEF
	var eff_def := int(tc.get("def", 0) * 0.3)
	var attacker_level: int = maxi(1, npc["data"].get("level", 1))
	var target_level:   int = maxi(1, tc.get("level", 1))
	var lvl_mult := clampf(1.0 + (attacker_level - target_level) * 0.04, 0.5, 1.6)
	var dmg := maxi(1, int(raw_dmg * lvl_mult) - eff_def)
	var map_id: int = npc["map_id"]

	var dw := NetProtocol.PacketWriter.new()
	dw.write_i32(npc.get("target_peer", 0))
	dw.write_i16(dmg)
	dw.write_u8(0)
	_broadcast_nearby(map_id, npc["x"], npc["y"], NetProtocol.MsgType.S_DAMAGE, dw.get_bytes(), -1)

	tc["hp"] = maxi(0, tc.get("hp", 0) - dmg)
	# Find client and send health update
	var tpeer: int = npc.get("target_peer", 0)
	if _clients.has(tpeer):
		var cl = _clients[tpeer]
		var hw := NetProtocol.PacketWriter.new()
		hw.write_i16(tc.get("hp", 0)); hw.write_i16(tc.get("mp", 0)); hw.write_i16(tc.get("sta", 0))
		cl.send_auth(NetProtocol.MsgType.S_HEALTH, hw.get_bytes())
		if tc.get("hp", 0) <= 0:
			_handle_npc_killed_player(npc, cl)


## ── Broadcast helper ─────────────────────────────────────────────────────────

func _broadcast_msg_to_map(map_id: int, writer: NetProtocol.PacketWriter) -> void:
	for pid in _clients:
		var cl = _clients[pid]
		if cl.state == _ServerClientSCR.State.CONNECTED and \
				cl.char.get("map_id", -1) == map_id:
			cl.send_auth(NetProtocol.MsgType.S_SERVER_MSG, writer.get_bytes())


func _npc_reset_to_idle(npc: Dictionary) -> void:
	## Resets NPC to idle state and returns it to spawn position.
	npc["ai_state"] = "idle"
	npc["target_peer"] = 0
	npc["x"] = npc["spawn_x"]
	npc["y"] = npc["spawn_y"]
	npc["heading"] = 3
	npc["enraged"] = false
	_schedule_npc_next_action(npc, Time.get_ticks_msec() / 1000.0, "idle")
	_broadcast_npc_set_char(npc)


func _npc_step_toward(npc: Dictionary, tx: int, ty: int) -> void:
	## Moves NPC one tile toward (tx, ty), checking walkability.
	## Simple axis-aligned approach: resolve largest axis difference first.
	var nx: int = npc["x"]
	var ny: int = npc["y"]
	var map_id: int = npc["map_id"]

	var dx := tx - nx
	var dy := ty - ny

	# Try primary axis (largest difference), fall back to secondary
	var candidates: Array = []
	if abs(dx) >= abs(dy):
		if dx != 0:
			candidates.append(Vector2i(nx + sign(dx), ny))
		if dy != 0:
			candidates.append(Vector2i(nx, ny + sign(dy)))
	else:
		if dy != 0:
			candidates.append(Vector2i(nx, ny + sign(dy)))
		if dx != 0:
			candidates.append(Vector2i(nx + sign(dx), ny))

	for step in candidates:
		var sx: int = step.x
		var sy: int = step.y
		if sx < 1 or sx > 100 or sy < 1 or sy > 100:
			continue
		var tile := GameData.get_map_tile(map_id, sx, sy)
		if tile.get("blocked", 0) != 0:
			continue

		# Determine heading from movement direction
		var move_dx := sx - nx
		var move_dy := sy - ny
		var new_heading := 3  # south default
		if move_dy < 0:
			new_heading = 1  # north
		elif move_dx > 0:
			new_heading = 2  # east
		elif move_dy > 0:
			new_heading = 3  # south
		elif move_dx < 0:
			new_heading = 4  # west

		npc["x"] = sx
		npc["y"] = sy
		npc["heading"] = new_heading

		# Broadcast movement to nearby clients
		var w := NetProtocol.PacketWriter.new()
		w.write_i32(npc["instance_id"])
		w.write_i16(sx)
		w.write_i16(sy)
		w.write_u8(new_heading)
		_broadcast_nearby(map_id, sx, sy, NetProtocol.MsgType.S_MOVE_CHAR,
				w.get_bytes(), -1)
		break  # Only one step per tick


func _npc_wander(npc: Dictionary) -> void:
	## Moves NPC one tile in a random direction, staying within 6 tiles of spawn.
	var nx: int     = int(npc["x"])
	var ny: int     = int(npc["y"])
	var map_id: int = int(npc["map_id"])
	var sx: int     = int(npc["spawn_x"])
	var sy: int     = int(npc["spawn_y"])
	# Random start index avoids creating + shuffling a temp array each call
	var dx: int
	var dy: int
	var start: int = randi() & 3
	for i in 4:
		match (start + i) & 3:
			0: dx =  0; dy = -1
			1: dx =  1; dy =  0
			2: dx =  0; dy =  1
			_: dx = -1; dy =  0
		var tx: int = nx + dx
		var ty: int = ny + dy
		if abs(tx - sx) > 6 or abs(ty - sy) > 6:
			continue
		if tx < 1 or tx > 100 or ty < 1 or ty > 100:
			continue
		if GameData.get_map_tile(map_id, tx, ty).get("blocked", 0) != 0:
			continue
		var new_heading: int = 3
		if dy < 0:   new_heading = 1
		elif dx > 0: new_heading = 2
		elif dy > 0: new_heading = 3
		else:        new_heading = 4
		npc["x"] = tx
		npc["y"] = ty
		npc["heading"] = new_heading
		var w := NetProtocol.PacketWriter.new()
		w.write_i32(npc["instance_id"])
		w.write_i16(tx); w.write_i16(ty); w.write_u8(new_heading)
		_broadcast_nearby(map_id, tx, ty, NetProtocol.MsgType.S_MOVE_CHAR, w.get_bytes(), -1)
		break


func _npc_attack(npc: Dictionary) -> void:
	## NPC attacks its current target player.
	var target_peer: int = npc["target_peer"]
	if not _clients.has(target_peer):
		return
	var target_client = _clients[target_peer]
	if target_client.state != _ServerClientSCR.State.CONNECTED:
		return

	# God mode: target is invincible
	if _god_mode.has(target_peer):
		return

	var tc: Dictionary = target_client.char
	var map_id: int = npc["map_id"]
	var nx: int = npc["x"]
	var ny: int = npc["y"]

	# Level-differential scaling: ±4 % per level difference, clamped to [50%, 160%]
	var attacker_level: int = maxi(1, npc["data"].get("level", 1))
	var target_level:   int = maxi(1, tc.get("level", 1))
	var lvl_mult := clampf(1.0 + (attacker_level - target_level) * 0.04, 0.5, 1.6)

	var result := _ServerCombatSCR.resolve_attack(npc, tc, lvl_mult)
	var dmg: int  = result["dmg"]
	var evaded: bool = result["evaded"]

	# Broadcast S_DAMAGE: i32=npc instance_id, i16=dmg, u8=evaded
	var dw := NetProtocol.PacketWriter.new()
	dw.write_i32(target_client.peer_id)
	dw.write_i16(dmg)
	dw.write_u8(1 if evaded else 0)
	_broadcast_nearby(map_id, nx, ny, NetProtocol.MsgType.S_DAMAGE, dw.get_bytes(), -1)

	# NPC-specific sound on attack, fallback to generic hit sounds
	var npc_snd: int = int(npc["data"].get("sound", 0))
	if npc_snd > 0:
		_broadcast_sound_near(map_id, Vector2i(nx, ny), npc_snd)
	elif not evaded and dmg > 0:
		_broadcast_sound_near(map_id, Vector2i(nx, ny), SOUND_MELEE_HIT)
		_broadcast_sound_near(map_id, Vector2i(nx, ny), SOUND_PLAYER_HIT)

	if not evaded and dmg > 0:
		tc["hp"] = maxi(0, tc.get("hp", 0) - dmg)

		# Send updated health to target player
		var hw := NetProtocol.PacketWriter.new()
		hw.write_i16(tc.get("hp", 0))
		hw.write_i16(tc.get("mp", 0))
		hw.write_i16(tc.get("sta", 0))
		target_client.send_auth(NetProtocol.MsgType.S_HEALTH, hw.get_bytes())

		# Handle player death from NPC attack (no killer_client — pass self-reference via null)
		if tc.get("hp", 0) <= 0:
			_handle_npc_killed_player(npc, target_client)


func _tick_summon_ai(npc: Dictionary, now: float) -> void:
	## AI for summoned familiars: hunt hostile NPCs independently of siblings.
	if now < float(npc.get("next_action_at", 0.0)):
		return
	var map_id: int  = npc["map_id"]
	var nx: int      = npc["x"]
	var ny: int      = npc["y"]
	var owner: int   = npc["data"].get("summoned_by", 0)
	var self_id: int = npc["instance_id"]

	# Validate current target (persist across ticks)
	var cur_target: int = npc.get("target_npc_id", -1)
	if cur_target != -1:
		if not _npcs.has(cur_target) or \
				_npcs[cur_target].get("ai_state", "dead") == "dead" or \
				_npcs[cur_target].get("map_id", -1) != map_id:
			cur_target = -1
			npc["target_npc_id"] = -1

	# Pick a new target if needed
	if cur_target == -1:
		# Collect targets already claimed by sibling summons so we spread out
		var claimed: Array = []
		for nid in _npcs:
			if nid == self_id:
				continue
			var sib: Dictionary = _npcs[nid]
			if sib["data"].get("summoned_by", 0) != owner:
				continue
			var sib_target: int = sib.get("target_npc_id", -1)
			if sib_target != -1:
				claimed.append(sib_target)

		# Two-pass: prefer unclaimed targets, fall back to any nearest
		var best_nid       := -1
		var best_dist      := 999
		var unclaimed_nid  := -1
		var unclaimed_dist := 999
		for nid in _npcs:
			if nid == self_id:
				continue
			var other: Dictionary = _npcs[nid]
			if other.get("ai_state", "dead") == "dead":
				continue
			if other.get("map_id", -1) != map_id:
				continue
			if other["data"].get("summoned_by", 0) == owner:
				continue  # Don't attack siblings
			if other["data"].get("hostile", 0) == 0:
				continue  # Ignore vendors / passive NPCs
			var dist := maxi(abs(other["x"] - nx), abs(other["y"] - ny))
			if dist < best_dist:
				best_dist = dist
				best_nid  = nid
			if nid not in claimed and dist < unclaimed_dist:
				unclaimed_dist = dist
				unclaimed_nid  = nid

		cur_target = unclaimed_nid if unclaimed_nid != -1 else best_nid
		npc["target_npc_id"] = cur_target

	if cur_target == -1:
		# No hostile NPC anywhere — wander independently
		if randf() < 0.55:
			_npc_wander(npc)
		elif randf() < 0.5:
			_npc_turn_in_place(npc)
		_schedule_npc_next_action(npc, now, "idle")
		return

	var target_npc: Dictionary = _npcs[cur_target]
	var tx: int = target_npc["x"]
	var ty: int = target_npc["y"]
	var dist := maxi(abs(tx - nx), abs(ty - ny))

	if dist <= NPC_ATTACK_RANGE:
		_summon_attack_npc(npc, target_npc)
		_schedule_npc_next_action(npc, now, "attack")
	else:
		_npc_step_toward(npc, tx, ty)
		_schedule_npc_next_action(npc, now, "chase")


func _summon_attack_npc(attacker: Dictionary, target: Dictionary) -> void:
	## A summoned familiar deals melee damage to a hostile NPC.
	var min_hit: int = attacker["data"].get("min_hit", 1)
	var max_hit: int = attacker["data"].get("max_hit", 5)
	var dmg := randi_range(min_hit, max_hit)
	var map_id: int = attacker["map_id"]

	target["hp"] = maxi(0, target.get("hp", 0) - dmg)

	# Broadcast damage floater on the target
	var dw := NetProtocol.PacketWriter.new()
	dw.write_i32(target["instance_id"])
	dw.write_i16(dmg)
	dw.write_u8(0)  # not evaded
	_broadcast_nearby(map_id, target["x"], target["y"],
			NetProtocol.MsgType.S_DAMAGE, dw.get_bytes(), -1)

	if target["hp"] <= 0:
		var owner_peer: int = attacker["data"].get("summoned_by", 0)
		var owner_client = _clients.get(owner_peer, null)
		if owner_client != null and \
				owner_client.state == _ServerClientSCR.State.CONNECTED:
			_npc_death(target, owner_client)
		else:
			_despawn_npc(target["instance_id"], target["map_id"])


## Drops all gold and all but 3 random unequipped items at the death location.
## Returns a human-readable loss string for the death message.
func _apply_death_penalty(dead_char: Dictionary) -> String:
	var dead_map: int = dead_char.get("map_id", 1)
	var dead_x: int   = dead_char.get("x", 10)
	var dead_y: int   = dead_char.get("y", 10)

	var lost_gold: int = dead_char.get("gold", 0)
	if lost_gold > 0:
		dead_char["gold"] = 0
		dead_char["_looted_gold"] = lost_gold  # caller may transfer to killer

	var dead_inv: Array = dead_char.get("inventory", [])
	var drop_slots: Array = []
	for i in dead_inv.size():
		var it: Dictionary = dead_inv[i] as Dictionary
		if it.is_empty() or it.get("equipped", false):
			continue
		drop_slots.append(i)
	drop_slots.shuffle()
	var actually_dropped: Array = drop_slots.slice(3)
	for si in actually_dropped:
		var it: Dictionary = dead_inv[si]
		_spawn_ground_item(dead_map, dead_x, dead_y, it.get("obj_index", 0), it.get("amount", 1))
		dead_inv[si] = {}
	dead_char["inventory"] = dead_inv

	var parts: Array = []
	if lost_gold > 0:
		parts.append("%d gold" % lost_gold)
	if actually_dropped.size() > 0:
		parts.append("%d item%s" % [actually_dropped.size(),
				"s" if actually_dropped.size() != 1 else ""])
	if parts.is_empty():
		return "You had nothing to lose."
	return "You lost %s." % ", ".join(parts)


func _handle_npc_killed_player(npc: Dictionary, dead_client) -> void:
	## Handles player death caused by an NPC.
	var dead_char: Dictionary = dead_client.char
	var map_id: int = dead_char.get("map_id", 1)
	var map_data := GameData.get_map(map_id)
	var sp: Dictionary = map_data.get("start_pos", {"x": 10, "y": 10})

	# Death penalty: drop gold and most items at death location
	var loss_msg: String = _apply_death_penalty(dead_char)

	# Respawn at map start
	dead_char["hp"] = dead_char.get("max_hp", 100)
	dead_char["x"]  = sp.get("x", 10)
	dead_char["y"]  = sp.get("y", 10)

	var dw_npc := NetProtocol.PacketWriter.new()
	dw_npc.write_str(npc["data"].get("name", "an NPC"))
	dead_client.send_auth(NetProtocol.MsgType.S_DEATH, dw_npc.get_bytes())
	_enter_world(dead_client, dead_char)

	_send_server_msg(dead_client, "You were slain by %s! %s" % [
			npc["data"].get("name", "an NPC"), loss_msg])


func _npc_death(npc: Dictionary, killer) -> void:
	## Called when an NPC's HP reaches zero from player attack.
	var now := Time.get_ticks_msec() / 1000.0
	npc["ai_state"]   = "dead"
	npc["target_peer"] = 0
	npc["respawn_at"] = now + NPC_RESPAWN_SECS

	var map_id: int = npc["map_id"]
	var nx: int = npc["x"]
	var ny: int = npc["y"]

	# Broadcast S_REMOVE_CHAR to nearby clients
	var rw := NetProtocol.PacketWriter.new()
	rw.write_i32(npc["instance_id"])
	_broadcast_nearby(map_id, nx, ny, NetProtocol.MsgType.S_REMOVE_CHAR,
			rw.get_bytes(), -1)

	# Broadcast corpse visual (lying body at death location)
	var cw := NetProtocol.PacketWriter.new()
	cw.write_i16(nx)
	cw.write_i16(ny)
	cw.write_i16(CORPSE_GRH)
	_broadcast_nearby(map_id, nx, ny, NetProtocol.MsgType.S_CORPSE,
			cw.get_bytes(), -1)

	# Play NPC-specific sound if defined, otherwise use generic death grunt.
	var npc_sound: int = int(npc["data"].get("sound", 0))
	if npc_sound > 0:
		_broadcast_sound_near(map_id, Vector2i(nx, ny), npc_sound)
	else:
		_broadcast_sound_near(map_id, Vector2i(nx, ny), SOUND_NPC_DEATH)

	# Award gold: use VB6 give_gld (kill reward), not "gold" (NPC's wallet)
	var gold_drop := int(npc["data"].get("give_gld", 0))
	if gold_drop <= 0:
		gold_drop = randi_range(5, 20)
	var kc: Dictionary = killer.char
	kc["gold"] = kc.get("gold", 0) + gold_drop

	# Award XP: prefer explicit give_exp from data, fall back to level formula
	var npc_level: int = maxi(1, npc["data"].get("level", 1))
	var give_exp_data: int = int(npc["data"].get("give_exp", 0))
	var xp_gain := give_exp_data if give_exp_data > 0 else _ServerCombatSCR.xp_for_kill(npc_level)
	kc["xp"] = kc.get("xp", 0) + xp_gain
	var levelled_up := _ServerCombatSCR.try_level_up(kc)

	# Update killer's stats display
	_send_stats(killer)

	# XP gain notification
	var xw := NetProtocol.PacketWriter.new()
	xw.write_i32(xp_gain)
	killer.send_auth(NetProtocol.MsgType.S_XP_GAIN, xw.get_bytes())

	# Level-up notification + sound (played only for the killer)
	if levelled_up:
		var lw := NetProtocol.PacketWriter.new()
		lw.write_u8(kc.get("level", 1))
		killer.send_auth(NetProtocol.MsgType.S_LEVEL_UP, lw.get_bytes())
		var sw := NetProtocol.PacketWriter.new()
		sw.write_u8(SOUND_LEVEL_UP)
		killer.send_auth(NetProtocol.MsgType.S_PLAY_SOUND, sw.get_bytes())

	# Item drop (35% chance — directly to killer inventory)
	var drop_table: Array = npc["data"].get("drop_items", [])
	if not drop_table.is_empty() and randf() < 0.35:
		var drop_obj_idx: int = drop_table[randi() % drop_table.size()]
		var drop_obj := GameData.get_object(drop_obj_idx)
		if not drop_obj.is_empty():
			var inv: Array = kc.get("inventory", [])
			while inv.size() < 20:
				inv.append({})
			var placed := false
			# Try to stack first
			for i in inv.size():
				var slot: Dictionary = inv[i]
				if not slot.is_empty() and slot.get("obj_index", 0) == drop_obj_idx:
					slot["amount"] = slot.get("amount", 0) + 1
					placed = true
					break
			# Find empty slot
			if not placed:
				for i in inv.size():
					if inv[i].is_empty():
						inv[i] = {"obj_index": drop_obj_idx, "amount": 1, "equipped": false}
						placed = true
						break
			if placed:
				kc["inventory"] = inv
				_send_inventory(killer)
				var dw2 := NetProtocol.PacketWriter.new()
				dw2.write_str("You looted: %s!" % drop_obj.get("name", "item"))
				killer.send_auth(NetProtocol.MsgType.S_SERVER_MSG, dw2.get_bytes())

	# Kill notification with gold reward
	var mw := NetProtocol.PacketWriter.new()
	mw.write_str("You killed %s and found %d gold!" % [
		npc["data"].get("name", "NPC"), gold_drop])
	killer.send_auth(NetProtocol.MsgType.S_SERVER_MSG, mw.get_bytes())

	# Quest kill progress (generic kills — hostile or attackable NPCs)
	if npc["data"].get("hostile", 0) != 0 or npc["data"].get("attackable", 0) != 0:
		_check_kill_quests(killer)
	# Quest kill_specific progress (name-matched kills for any NPC)
	_check_specific_kill_quests(killer, npc["data"].get("name", ""))

	# Achievements & leaderboards for NPC kills
	if npc["data"].get("hostile", 0) != 0 or npc["data"].get("attackable", 0) != 0:
		_check_achievements(killer, "kills", 1)
		_update_leaderboard("kills", kc.get("name", "?"),
				int(kc.get("achievement_progress", {}).get("kills", 0)))
	if levelled_up:
		_check_achievements(killer, "level", 0)
		_update_leaderboard("level", kc.get("name", "?"), kc.get("level", 1))

	# World event NPC death check
	var _ev_nid: int = npc["instance_id"]
	if _ev_nid in _world_event_npcs:
		_world_event_npcs.erase(_ev_nid)
		if _world_event_npcs.is_empty() and _world_event_active:
			_end_world_event("The town defenders were victorious! All monsters slain!")

	# Boss death handling
	var _boss_nid: int = npc["instance_id"]
	var _boss_map_for_death: int = -1
	for _bm in _boss_instances.keys():
		if _boss_instances[_bm] == _boss_nid:
			_boss_map_for_death = _bm
			break
	if _boss_map_for_death >= 0:
		_boss_instances.erase(_boss_map_for_death)
		# Bonus XP for boss kill (x5)
		var boss_bonus_xp: int = xp_gain * 4  # already awarded xp_gain above
		kc["xp"] = kc.get("xp", 0) + boss_bonus_xp
		_ServerCombatSCR.try_level_up(kc)
		_send_stats(killer)
		var _boss_name_death: String = npc["data"].get("name", "the boss")
		var _killer_name_death: String = kc.get("name", "a hero")
		var _bcast_boss_w := NetProtocol.PacketWriter.new()
		_bcast_boss_w.write_str("The %s has been defeated by %s! Legendary treasure awaits!" % [
				_boss_name_death, _killer_name_death])
		_broadcast_all_connected(NetProtocol.MsgType.S_SERVER_MSG, _bcast_boss_w.get_bytes())
		# Night sight gear: Iron Golem drops Owl Eye Helm (323); Serpent Queen / Gremlin Warlord
		# drop Night Stalker Hood (322) as a bonus guaranteed piece.
		var _boss_night_drop: int = 0
		if _boss_map_for_death == 80:   _boss_night_drop = 323  # Owl Eye Helm (night_sight+3)
		elif _boss_map_for_death == 115: _boss_night_drop = 322 # Night Stalker Hood (night_sight+1)
		elif _boss_map_for_death == 140: _boss_night_drop = 322 # Night Stalker Hood (night_sight+1)
		if _boss_night_drop > 0:
			var _bni: Array = kc.get("inventory", [])
			while _bni.size() < 20: _bni.append({})
			var _bn_placed := false
			for _i in _bni.size():
				if _bni[_i].is_empty():
					_bni[_i] = {"obj_index": _boss_night_drop, "amount": 1, "equipped": false}
					_bn_placed = true
					break
			if _bn_placed:
				kc["inventory"] = _bni
				_send_inventory(killer)
				var _bnd_obj := GameData.get_object(_boss_night_drop)
				var _bnw := NetProtocol.PacketWriter.new()
				_bnw.write_str("The boss dropped: %s!" % _bnd_obj.get("name", "rare gear"))
				killer.send_auth(NetProtocol.MsgType.S_SERVER_MSG, _bnw.get_bytes())

	print("[Server] NPC %s (id=%d) killed by %s" % [
		npc["data"].get("name", "?"), npc["instance_id"],
		kc.get("name", "?")])


func _respawn_npc(npc: Dictionary) -> void:
	## Restores a dead NPC to its spawn position.
	npc["hp"]          = npc["max_hp"]
	npc["x"]           = npc["spawn_x"]
	npc["y"]           = npc["spawn_y"]
	npc["heading"]     = 3
	npc["ai_state"]    = "idle"
	npc["target_peer"] = 0
	_schedule_npc_next_action(npc, Time.get_ticks_msec() / 1000.0, "idle")

	# Broadcast S_SET_CHAR for this NPC to all clients on the map
	_broadcast_npc_set_char(npc)

	print("[Server] NPC %s (id=%d) respawned on map %d" % [
		npc["data"].get("name", "?"), npc["instance_id"], npc["map_id"]])


# ---------------------------------------------------------------------------
# NPC S_SET_CHAR helpers
# ---------------------------------------------------------------------------

func _send_npc_set_char(client, npc: Dictionary) -> void:
	## Sends a single NPC's S_SET_CHAR to one specific client.
	var npc_data: Dictionary = npc["data"]
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(npc["instance_id"])
	w.write_i16(npc_data.get("body", 1))
	w.write_i16(npc_data.get("head", 1))
	w.write_i16(npc_data.get("weapon_anim", 0))
	w.write_i16(npc_data.get("shield_anim", 0))
	w.write_i16(npc["x"])
	w.write_i16(npc["y"])
	w.write_u8(npc["heading"])
	w.write_i16(npc.get("hp", npc.get("max_hp", 1)))
	w.write_i16(npc.get("max_hp", 1))
	w.write_str(npc_data.get("name", "NPC"))
	client.send_auth(NetProtocol.MsgType.S_SET_CHAR, w.get_bytes())


func _broadcast_npc_set_char(npc: Dictionary) -> void:
	## Broadcasts an NPC's S_SET_CHAR to all nearby connected clients on its map.
	var npc_data: Dictionary = npc["data"]
	var map_id: int = npc["map_id"]
	var nx: int = npc["x"]
	var ny: int = npc["y"]
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(npc["instance_id"])
	w.write_i16(npc_data.get("body", 1))
	w.write_i16(npc_data.get("head", 1))
	w.write_i16(npc_data.get("weapon_anim", 0))
	w.write_i16(npc_data.get("shield_anim", 0))
	w.write_i16(nx)
	w.write_i16(ny)
	w.write_u8(npc["heading"])
	w.write_i16(npc.get("hp", npc.get("max_hp", 1)))
	w.write_i16(npc.get("max_hp", 1))
	w.write_str(npc_data.get("name", "NPC"))
	_broadcast_nearby(map_id, nx, ny, NetProtocol.MsgType.S_SET_CHAR,
			w.get_bytes(), -1)


# ---------------------------------------------------------------------------
# Vendor shop
# ---------------------------------------------------------------------------

func _get_vendor_buy_price(obj: Dictionary) -> int:
	var base_value = obj.get("value", 10)
	if typeof(base_value) == TYPE_STRING:
		base_value = int(base_value)
	return maxi(1, int(round(int(base_value) * SHOP_BUY_PRICE_MULT)))


# ---------------------------------------------------------------------------
# Quest handlers
# ---------------------------------------------------------------------------

func _on_quest_talk(client, npc_instance_id: int) -> void:
	## Client right-clicked a quest NPC and chose "Talk to".
	## Look up quests for this NPC and send either an offer or turn-in packet.
	if not _npcs.has(npc_instance_id):
		_send_server_msg(client, "That NPC is not nearby.")
		return
	var npc: Dictionary = _npcs[npc_instance_id]
	var char_dict: Dictionary = client.char
	var npc_data: Dictionary = npc["data"]
	var npc_name: String = npc_data.get("name", "NPC")
	var npc_type: int = int(npc_data.get("npc_type", -1))

	# Range check — must be within 3 tiles
	var px: int = char_dict.get("x", 0)
	var py: int = char_dict.get("y", 0)
	var nx: int = npc.get("x", 0)
	var ny: int = npc.get("y", 0)
	if maxi(abs(nx - px), abs(ny - py)) > 3:
		_send_server_msg(client, "You are too far away.")
		return

	# Find quests for this NPC
	var available: Array = _ServerQuestsSCR.quests_for_npc(char_dict, npc_name, npc_type)
	if available.is_empty():
		_send_server_msg(client, npc_name + " has nothing for you right now.")
		return

	# Prefer turn-in over offer; if multiple, take first
	var chosen: Dictionary = {}
	for av in available:
		var avd: Dictionary = av as Dictionary
		if avd.get("mode", "") == "turnin":
			chosen = avd
			break
	if chosen.is_empty():
		chosen = available[0] as Dictionary

	var quest_id: int = int(chosen.get("quest_id", 0))
	var quest: Dictionary = _ServerQuestsSCR.get_quest(quest_id)
	if quest.is_empty():
		return

	# Determine mode: 0=offer, 1=turnin
	var q_mode: int = 1 if chosen.get("mode", "offer") == "turnin" else 0

	# Build and send S_QUEST_OFFER — mode byte first, then quest data
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(q_mode)
	w.write_u16(quest_id)
	w.write_str(npc_name)
	w.write_str(quest.get("name", ""))
	w.write_str(quest.get("desc", ""))

	var objectives: Array = quest.get("objectives", [])
	w.write_u8(objectives.size())
	for obj in objectives:
		var od: Dictionary = obj as Dictionary
		w.write_str(od.get("label", ""))
		# count field (new schema); fall back to required for legacy quests
		w.write_u16(int(od.get("count", od.get("count", 1))))
		# type byte: 0=kill, 1=gather, 2=cook, 3=kill_specific, 4=explore, 5=craft, 6=deliver
		var obj_type_str: String = od.get("type", "kill")
		var type_byte: int = 0
		match obj_type_str:
			"gather":        type_byte = 1
			"cook":          type_byte = 2
			"kill_specific": type_byte = 3
			"explore":       type_byte = 4
			"craft":         type_byte = 5
			"deliver":       type_byte = 6
		w.write_u8(type_byte)

	var rewards_d: Dictionary = quest.get("rewards", {})
	w.write_i32(int(rewards_d.get("gold", quest.get("reward_gold", 0))))
	w.write_i32(int(rewards_d.get("xp",   quest.get("reward_xp",   0))))
	var reward_items: Array = rewards_d.get("items", quest.get("reward_items", []))
	w.write_u8(reward_items.size())
	for ri in reward_items:
		var rid: Dictionary = ri as Dictionary
		var ri_obj_idx: int = int(rid.get("obj_index", 0))
		var ri_amt: int = int(rid.get("amount", 1))
		var ri_name: String = GameData.get_object(ri_obj_idx).get("name", "Item")
		w.write_i16(ri_obj_idx)
		w.write_u16(ri_amt)
		w.write_str(ri_name)

	client.send_auth(S_QUEST_OFFER, w.get_bytes())


func _on_quest_accept(client, quest_id: int) -> void:
	## Client accepted a quest offer.
	var char_dict: Dictionary = client.char
	# Check active quest cap before can_accept (can_accept also checks, but give explicit msg)
	var active_count: int = 0
	var quests_check: Dictionary = char_dict.get("quests", {})
	for qid_str_c in quests_check:
		var ec: Dictionary = quests_check[qid_str_c] as Dictionary
		if ec.get("accepted", false) and not ec.get("completed", false):
			active_count += 1
	if active_count >= 10:
		_send_server_msg(client, "Your quest log is full (10/10).")
		return
	if not _ServerQuestsSCR.can_accept(char_dict, quest_id):
		_send_server_msg(client, "You cannot accept that quest.")
		return

	# Init quest tracking in char_dict
	if not char_dict.has("quests"):
		char_dict["quests"] = {}
	char_dict["quests"][str(quest_id)] = {
		"accepted":  true,
		"progress":  {},
		"completed": false,
	}

	var quest: Dictionary = _ServerQuestsSCR.get_quest(quest_id)
	_send_server_msg(client, "Quest accepted: " + quest.get("name", ""))

	# Send initial progress update so journal populates
	_send_quest_update(client, quest_id)
	# Refresh quest indicators on the map
	_send_quest_indicators(client)
	_db.save_char(client.username, char_dict)


func _on_quest_turnin(client, quest_id: int) -> void:
	## Client turns in a completed quest.
	var char_dict: Dictionary = client.char
	if not _ServerQuestsSCR.check_progress(char_dict, quest_id):
		_send_server_msg(client, "You have not completed all objectives yet.")
		return

	var quest: Dictionary = _ServerQuestsSCR.get_quest(quest_id)
	if quest.is_empty():
		return

	# Mark completed
	var quests: Dictionary = char_dict.get("quests", {})
	var qstr: String = str(quest_id)
	if quests.has(qstr):
		(quests[qstr] as Dictionary)["completed"] = true
		(quests[qstr] as Dictionary)["accepted"] = false

	# Read rewards — support both new {rewards: {gold, xp, items}} and old flat fields
	var rewards_ti: Dictionary = quest.get("rewards", {})
	var reward_gold: int = int(rewards_ti.get("gold", quest.get("reward_gold", 0)))
	var reward_xp:   int = int(rewards_ti.get("xp",   quest.get("reward_xp",   0)))
	var reward_items: Array = rewards_ti.get("items", quest.get("reward_items", []))

	# Award gold
	if reward_gold > 0:
		char_dict["gold"] = int(char_dict.get("gold", 0)) + reward_gold

	# Award XP
	if reward_xp > 0:
		char_dict["xp"] = int(char_dict.get("xp", 0)) + reward_xp
		var levelled_up := _ServerCombatSCR.try_level_up(char_dict)
		if levelled_up:
			var lw := NetProtocol.PacketWriter.new()
			lw.write_u8(int(char_dict.get("level", 1)))
			client.send_auth(NetProtocol.MsgType.S_LEVEL_UP, lw.get_bytes())

	# Award item rewards
	for ri in reward_items:
		var rid: Dictionary = ri as Dictionary
		_give_item(char_dict, int(rid.get("obj_index", 0)), int(rid.get("amount", 1)))

	_send_stats(client)
	_send_inventory(client)

	# Send completion message if quest defines one
	var comp_msg: String = quest.get("completion_msg", "")
	if not comp_msg.is_empty():
		_send_server_msg(client, comp_msg)

	# Send S_QUEST_COMPLETE
	var cw := NetProtocol.PacketWriter.new()
	cw.write_u16(quest_id)
	cw.write_i32(reward_gold)
	cw.write_i32(reward_xp)
	client.send_auth(S_QUEST_COMPLETE, cw.get_bytes())

	_send_server_msg(client, "Quest complete: %s! Reward: %d gold, %d XP." % [
		quest.get("name", ""), reward_gold, reward_xp])
	# Award town reputation
	var rep_fac: String = quest.get("rep_faction", "")
	var rep_amt: int = int(quest.get("rep_amount", 0))
	if not rep_fac.is_empty() and rep_amt > 0:
		_add_rep(client, rep_fac, rep_amt)
	# Refresh quest indicators on the map
	_send_quest_indicators(client)
	_db.save_char(client.username, char_dict)


func _send_quest_update(client, quest_id: int) -> void:
	## Sends S_QUEST_UPDATE with current objectives progress string.
	var char_dict: Dictionary = client.char
	var obj_str: String = _ServerQuestsSCR.objective_progress_str(char_dict, quest_id)
	var w := NetProtocol.PacketWriter.new()
	w.write_u16(quest_id)
	w.write_str(obj_str)
	client.send_auth(S_QUEST_UPDATE, w.get_bytes())
	# Refresh quest indicators so "?" markers appear when objectives complete
	_send_quest_indicators(client)


func _check_kill_quests(killer_client) -> void:
	## Increments kill progress for any active kill quests the player has.
	var char_dict: Dictionary = killer_client.char
	var quests: Dictionary = char_dict.get("quests", {})
	var updated: bool = false
	for qid_str in quests.keys():
		var entry: Dictionary = quests[qid_str] as Dictionary
		if not entry.get("accepted", false) or entry.get("completed", false):
			continue
		var quest_id: int = int(qid_str)
		var quest: Dictionary = _ServerQuestsSCR.get_quest(quest_id)
		if quest.is_empty():
			continue
		for obj in quest.get("objectives", []):
			var od: Dictionary = obj as Dictionary
			if od.get("type", "") != "kill":
				continue
			var required: int = int(od.get("count", 1))
			var progress: Dictionary = entry.get("progress", {})
			var kills: int = int(progress.get("kills", 0))
			if kills < required:
				progress["kills"] = kills + 1
				entry["progress"] = progress
				updated = true
				# Check if now complete
				if _ServerQuestsSCR.check_progress(char_dict, quest_id):
					var quest_name: String = quest.get("name", "")
					_send_server_msg(killer_client,
						"Objective complete! Return to the quest giver to finish '%s'." % quest_name)
	if updated:
		# Send update for all changed quests
		for qid_str in quests.keys():
			var entry: Dictionary = quests[qid_str] as Dictionary
			if entry.get("accepted", false) and not entry.get("completed", false):
				_send_quest_update(killer_client, int(qid_str))
		_db.save_char(killer_client.username, char_dict)


func _check_cook_quests(client) -> void:
	## Increments cook progress for any active cooking quests the player has.
	var char_dict: Dictionary = client.char
	var quests: Dictionary = char_dict.get("quests", {})
	for qid_str in quests.keys():
		var entry: Dictionary = quests[qid_str] as Dictionary
		if not entry.get("accepted", false) or entry.get("completed", false):
			continue
		var quest_id: int = int(qid_str)
		var quest: Dictionary = _ServerQuestsSCR.get_quest(quest_id)
		if quest.is_empty():
			continue
		for obj in quest.get("objectives", []):
			var od: Dictionary = obj as Dictionary
			if od.get("type", "") != "cook":
				continue
			var required: int = int(od.get("count", 1))
			var progress: Dictionary = entry.get("progress", {})
			var cooks: int = int(progress.get("cooks", 0))
			if cooks < required:
				progress["cooks"] = cooks + 1
				entry["progress"] = progress
				if _ServerQuestsSCR.check_progress(char_dict, quest_id):
					_send_server_msg(client,
						"Objective complete! Return to the quest giver to finish '%s'." % \
						quest.get("name", ""))
		_send_quest_update(client, quest_id)


func _check_gather_quests(client) -> void:
	## Gather quests check live inventory, so just push an update for any
	## active gather-type quests. Called when inventory changes.
	var char_dict: Dictionary = client.char
	var quests: Dictionary = char_dict.get("quests", {})
	for qid_str in quests.keys():
		var entry: Dictionary = quests[qid_str] as Dictionary
		if not entry.get("accepted", false) or entry.get("completed", false):
			continue
		var quest_id: int = int(qid_str)
		var quest: Dictionary = _ServerQuestsSCR.get_quest(quest_id)
		if quest.is_empty():
			continue
		var has_gather: bool = false
		for obj in quest.get("objectives", []):
			var od: Dictionary = obj as Dictionary
			if od.get("type", "") == "gather":
				has_gather = true
				break
		if has_gather:
			_send_quest_update(client, quest_id)
			if _ServerQuestsSCR.check_progress(char_dict, quest_id):
				_send_server_msg(client,
					"Objective complete! Return to the quest giver to finish '%s'." % \
					quest.get("name", ""))


func _check_specific_kill_quests(killer_client, npc_name: String) -> void:
	## Increments kill_specific progress counters for matching active quests.
	var char_dict: Dictionary = killer_client.char
	var quests_dict: Dictionary = char_dict.get("quests", {})
	var npc_name_lower: String = npc_name.to_lower()
	for qid_str in quests_dict:
		var qs: Dictionary = quests_dict[qid_str] as Dictionary
		if not qs.get("accepted", false) or qs.get("completed", false):
			continue
		var qid: int = int(qid_str)
		var quest: Dictionary = _ServerQuestsSCR.get_quest(qid)
		if quest.is_empty():
			continue
		for obj in quest.get("objectives", []):
			var od: Dictionary = obj as Dictionary
			if od.get("type", "") != "kill_specific":
				continue
			var contains: String = od.get("npc_name_contains", "").to_lower()
			if contains.is_empty() or npc_name_lower.contains(contains):
				var prog: Dictionary = qs.get("progress", {})
				var key: String = "kills_" + contains
				prog[key] = int(prog.get(key, 0)) + 1
				qs["progress"] = prog
				_send_quest_update(killer_client, qid)
				if _ServerQuestsSCR.check_progress(char_dict, qid):
					_send_server_msg(killer_client,
						"Objective complete! Return to your quest giver.")
				_db.save_char(killer_client.username, char_dict)


func _check_craft_quests(client, action: String) -> void:
	## Increments craft progress counters for matching active quests.
	var char_dict: Dictionary = client.char
	var quests_dict: Dictionary = char_dict.get("quests", {})
	for qid_str in quests_dict:
		var qs: Dictionary = quests_dict[qid_str] as Dictionary
		if not qs.get("accepted", false) or qs.get("completed", false):
			continue
		var qid: int = int(qid_str)
		var quest: Dictionary = _ServerQuestsSCR.get_quest(qid)
		if quest.is_empty():
			continue
		for obj in quest.get("objectives", []):
			var od: Dictionary = obj as Dictionary
			if od.get("type", "") != "craft":
				continue
			if od.get("action", "") == action:
				var prog: Dictionary = qs.get("progress", {})
				var key: String = "crafts_" + action
				prog[key] = int(prog.get(key, 0)) + 1
				qs["progress"] = prog
				_send_quest_update(client, qid)
				if _ServerQuestsSCR.check_progress(char_dict, qid):
					_send_server_msg(client,
						"Objective complete! Return to your quest giver.")


func _check_explore_quests(client, map_id: int) -> void:
	## Checks explore objectives after a player enters a new map.
	var char_dict: Dictionary = client.char
	var quests_dict: Dictionary = char_dict.get("quests", {})
	for qid_str in quests_dict:
		var qs: Dictionary = quests_dict[qid_str] as Dictionary
		if not qs.get("accepted", false) or qs.get("completed", false):
			continue
		var qid: int = int(qid_str)
		var quest: Dictionary = _ServerQuestsSCR.get_quest(qid)
		if quest.is_empty():
			continue
		for obj in quest.get("objectives", []):
			var od: Dictionary = obj as Dictionary
			if od.get("type", "") == "explore" and int(od.get("map_id", -1)) == map_id:
				_send_quest_update(client, qid)
				if _ServerQuestsSCR.check_progress(char_dict, qid):
					_send_server_msg(client,
						"Objective complete! Return to your quest giver.")
				break


func _send_quest_indicators(client) -> void:
	## Sends S_QUEST_INDICATORS for all NPCs on the client's current map.
	var char_dict: Dictionary = client.char
	var map_id: int = char_dict.get("map_id", 0)
	var npc_entries: Array = []
	for inst_id in _npcs:
		var npc_entry: Dictionary = _npcs[inst_id]
		if int(npc_entry.get("map_id", 0)) != map_id:
			continue
		var npc_data: Dictionary = npc_entry.get("data", {})
		var npc_name: String = npc_data.get("name", "")
		var npc_type: int = int(npc_data.get("npc_type", 0))
		var indicator: String = _ServerQuestsSCR.get_npc_indicator(char_dict, npc_name, npc_type)
		if not indicator.is_empty():
			npc_entries.append({"inst_id": inst_id, "indicator": indicator})
	var w := NetProtocol.PacketWriter.new()
	w.write_u16(npc_entries.size())
	for entry in npc_entries:
		w.write_i32(int(entry["inst_id"]))
		w.write_str(entry["indicator"])
	client.send_auth(NetProtocol.MsgType.S_QUEST_INDICATORS, w.get_bytes())


# ---------------------------------------------------------------------------
# Shop helpers
# ---------------------------------------------------------------------------

func _on_shop_open(client, npc_instance_id: int) -> void:
	## Client requests to open a vendor NPC's shop.
	if not _npcs.has(npc_instance_id):
		return
	var npc: Dictionary = _npcs[npc_instance_id]

	# Vendor must be alive
	if npc["ai_state"] == "dead":
		return

	# Validate distance: within 3 tiles
	var cc: Dictionary = client.char
	var cx: int = cc.get("x", 0)
	var cy: int = cc.get("y", 0)
	if npc["map_id"] != cc.get("map_id", -1):
		return
	var dist := maxi(abs(npc["x"] - cx), abs(npc["y"] - cy))
	if dist > 3:
		return

	# Check vendor type: npc_type 2 = item vendor, npc_type 3 = spell vendor, npc_type 4 = trainer
	var npc_data: Dictionary = npc["data"]
	var npc_type: int = npc_data.get("npc_type", 0)
	if npc_type == 4:
		_on_trainer_open(client, npc_instance_id)
		return
	if npc_type == 3:
		_open_spell_shop(client, npc_instance_id)
		return
	if npc_type != 2:
		return

	# Build item list - merge rep-tiered arrays if vendor has rep_faction
	var cc_shop: Dictionary = client.char
	var items: Array = []
	var raw_items: Array
	if npc_data.has("rep_faction"):
		var shop_faction: String = npc_data["rep_faction"]
		if _get_rep(cc_shop, shop_faction) < 0:
			# Hated — vendor refuses service
			var pw_ref := NetProtocol.PacketWriter.new()
			pw_ref.write_str(shop_faction)
			client.send_auth(NetProtocol.MsgType.S_REP_REFUSED, pw_ref.get_bytes())
			_send_server_msg(client, "The merchant eyes you with contempt. \"Get out of my shop.\"")
			return
		raw_items = _build_vendor_items(npc_data, cc_shop)
	else:
		raw_items = npc_data.get("items", [])
	if raw_items.size() > 0:
		# Structured items array
		for obj_index in raw_items:
			var idx := int(obj_index)
			if idx <= 0:
				continue
			var obj := GameData.get_object(idx)
			if obj.is_empty():
				continue
			if obj.get("name", "").strip_edges().to_lower().begins_with("(none)"):
				continue
			var price := _get_vendor_buy_price(obj)
			items.append({
				"obj_index": idx,
				"price":     price,
				"name":      obj.get("name", "Item"),
			})
	else:
		# Fall back to obj1..obj40 fields (NPC.dat format)
		for i in range(1, 41):
			var field := "obj%d" % i
			var raw_val = npc_data.get(field, "")
			if raw_val == "" or raw_val == "0":
				continue
			# obj fields may be "index-amount-equipped" format
			var obj_index := 0
			if typeof(raw_val) == TYPE_STRING and raw_val.contains("-"):
				obj_index = int(raw_val.split("-")[0])
			else:
				obj_index = int(raw_val)
			if obj_index <= 0:
				continue
			var obj := GameData.get_object(obj_index)
			if obj.is_empty():
				continue
			if obj.get("name", "").strip_edges().to_lower().begins_with("(none)"):
				continue
			var price := _get_vendor_buy_price(obj)
			items.append({
				"obj_index": obj_index,
				"price":     price,
				"name":      obj.get("name", "Item"),
			})

	if items.is_empty():
		return

	# Send S_SHOP_LIST
	var w := NetProtocol.PacketWriter.new()
	w.write_str(npc_data.get("name", "Vendor"))
	w.write_u8(mini(items.size(), 255))
	for item in items:
		w.write_i16(item["obj_index"])
		w.write_i32(item["price"])
		w.write_str(item["name"])
	client.send_auth(S_SHOP_LIST, w.get_bytes())


func _on_buy(client, npc_id: int, obj_index: int, amount: int) -> void:
	## Client purchases an item from a vendor NPC.
	if not _npcs.has(npc_id):
		return
	var npc: Dictionary = _npcs[npc_id]
	if npc["ai_state"] == "dead":
		return

	# Validate NPC is a vendor and within range
	var npc_data: Dictionary = npc["data"]
	if npc_data.get("npc_type", 0) != 2:
		return
	var cc: Dictionary = client.char
	var cx: int = cc.get("x", 0)
	var cy: int = cc.get("y", 0)
	if npc["map_id"] != cc.get("map_id", -1):
		return
	var dist := maxi(abs(npc["x"] - cx), abs(npc["y"] - cy))
	if dist > 3:
		return

	# Clamp amount to valid range
	amount = clampi(amount, 1, 9999)

	# Look up item and verify it exists on this vendor
	var obj := GameData.get_object(obj_index)
	if obj.is_empty():
		_send_buy_result(client, false, "Item not found.")
		return

	# Verify the NPC actually sells this item (respecting rep tiers)
	var vendor_sells := false
	var cc_buy: Dictionary = client.char
	var raw_items_buy: Array
	if npc_data.has("rep_faction"):
		raw_items_buy = _build_vendor_items(npc_data, cc_buy)
	else:
		raw_items_buy = npc_data.get("items", [])
	if raw_items_buy.size() > 0:
		for vi in raw_items_buy:
			if int(vi) == obj_index:
				vendor_sells = true
				break
	else:
		for i in range(1, 41):
			var field := "obj%d" % i
			var raw_val = npc_data.get(field, "")
			if raw_val == "" or raw_val == "0":
				continue
			var vi_idx := 0
			if typeof(raw_val) == TYPE_STRING and raw_val.contains("-"):
				vi_idx = int(raw_val.split("-")[0])
			else:
				vi_idx = int(raw_val)
			if vi_idx == obj_index:
				vendor_sells = true
				break

	if not vendor_sells:
		_send_buy_result(client, false, "Vendor does not sell this item.")
		return

	# Calculate total price
	var unit_price := _get_vendor_buy_price(obj)
	var total_cost: int = unit_price * amount

	# Check gold
	if cc.get("gold", 0) < total_cost:
		_send_buy_result(client, false, "Not enough gold.")
		return

	# Find inventory slot: stack existing or find empty
	var inv: Array = cc.get("inventory", [])
	# Ensure inventory has at least 20 slots
	while inv.size() < 20:
		inv.append({})

	var placed := false
	# Try to stack into existing slot
	for i in inv.size():
		var slot: Dictionary = inv[i]
		if slot.is_empty():
			continue
		if slot.get("obj_index", 0) == obj_index:
			slot["amount"] = slot.get("amount", 0) + amount
			placed = true
			break

	# Place in first empty slot
	if not placed:
		for i in inv.size():
			if inv[i].is_empty():
				inv[i] = {"obj_index": obj_index, "amount": amount, "equipped": false}
				placed = true
				break

	if not placed:
		_send_buy_result(client, false, "Inventory is full.")
		return

	# Deduct gold
	cc["gold"] = cc.get("gold", 0) - total_cost
	cc["inventory"] = inv

	# Confirm and update client
	_send_buy_result(client, true, "")
	_send_inventory(client)
	_send_stats(client)


func _send_buy_result(client, success: bool, reason: String) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(1 if success else 0)
	w.write_str(reason)
	client.send_auth(S_BUY_RESULT, w.get_bytes())


## Sell one item from inventory back to the nearest open vendor.
func _on_sell(client, npc_id: int, inv_slot: int) -> void:
	var char_dict: Dictionary = client.char
	var inv: Array = char_dict.get("inventory", [])
	if inv_slot < 0 or inv_slot >= inv.size():
		_send_buy_result(client, false, "Invalid slot.")
		return
	var item: Dictionary = inv[inv_slot] as Dictionary
	if item.is_empty():
		_send_buy_result(client, false, "No item in that slot.")
		return
	if item.get("equipped", false):
		_send_buy_result(client, false, "Unequip the item first.")
		return
	var obj: Dictionary = GameData.get_object(item.get("obj_index", 0))
	if obj.get("value", 0) <= 0:
		_send_buy_result(client, false, "That item has no value.")
		return
	# Sell price = 50% of buy value
	var sell_price: int = maxi(1, int(float(obj.get("value", 0)) * SHOP_SELL_PRICE_MULT))
	# Remove item
	inv[inv_slot] = {}
	char_dict["inventory"] = inv
	char_dict["gold"] = char_dict.get("gold", 0) + sell_price
	_send_inventory(client)
	_send_stats(client)
	_send_buy_result(client, true, "Sold for %d gold." % sell_price)
	_db.save_char(client.username, char_dict)


## Open the bank for a player.
func _on_bank_open(client, _npc_id: int) -> void:
	_send_bank_contents(client)


func _send_bank_contents(client) -> void:
	var char_dict: Dictionary = client.char
	var bank: Array = char_dict.get("bank", [])
	while bank.size() < 20:
		bank.append({})
	char_dict["bank"] = bank
	var w := NetProtocol.PacketWriter.new()
	var count: int = 0
	# Count non-empty slots first
	for it in bank:
		if not (it as Dictionary).is_empty():
			count += 1
	w.write_u8(count)
	for i in bank.size():
		var it: Dictionary = bank[i] as Dictionary
		if it.is_empty():
			continue
		w.write_u8(i)
		w.write_i16(it.get("obj_index", 0))
		w.write_u16(it.get("amount", 0))
	w.write_i32(char_dict.get("bank_gold", 0))
	client.send_auth(NetProtocol.MsgType.S_BANK_CONTENTS, w.get_bytes())


func _on_bank_deposit(client, inv_slot: int) -> void:
	var char_dict: Dictionary = client.char
	var inv: Array = char_dict.get("inventory", [])
	if inv_slot < 0 or inv_slot >= inv.size():
		return
	var item: Dictionary = inv[inv_slot] as Dictionary
	if item.is_empty() or item.get("equipped", false):
		_send_server_msg(client, "Cannot deposit that item.")
		return
	var bank: Array = char_dict.get("bank", [])
	while bank.size() < 20:
		bank.append({})
	# Try to stack first
	var deposited := false
	for i in bank.size():
		var bs: Dictionary = bank[i] as Dictionary
		if not bs.is_empty() and bs.get("obj_index", 0) == item.get("obj_index", 0):
			bs["amount"] = bs.get("amount", 0) + item.get("amount", 1)
			deposited = true
			break
	if not deposited:
		for i in bank.size():
			if (bank[i] as Dictionary).is_empty():
				bank[i] = {"obj_index": item.get("obj_index", 0), "amount": item.get("amount", 1)}
				deposited = true
				break
	if not deposited:
		_send_server_msg(client, "Bank is full.")
		return
	inv[inv_slot] = {}
	char_dict["inventory"] = inv
	char_dict["bank"] = bank
	_send_inventory(client)
	_send_bank_contents(client)
	_db.save_char(client.username, char_dict)


func _on_bank_withdraw(client, bank_slot: int, requested: int = 0) -> void:
	var char_dict: Dictionary = client.char
	var bank: Array = char_dict.get("bank", [])
	if bank_slot < 0 or bank_slot >= bank.size():
		return
	var item: Dictionary = bank[bank_slot] as Dictionary
	if item.is_empty():
		return
	var have: int = item.get("amount", 1)
	var take: int = clampi(requested if requested > 0 else have, 1, have)
	_give_item(char_dict, item.get("obj_index", 0), take)
	if take >= have:
		bank[bank_slot] = {}
	else:
		item["amount"] = have - take
		bank[bank_slot] = item
	char_dict["bank"] = bank
	_send_inventory(client)
	_send_bank_contents(client)
	_db.save_char(client.username, char_dict)


func _on_bank_deposit_gold(client, amount: int) -> void:
	var char_dict: Dictionary = client.char
	var have: int = char_dict.get("gold", 0)
	var actual: int = mini(amount, have)
	if actual <= 0:
		return
	char_dict["gold"] = have - actual
	char_dict["bank_gold"] = char_dict.get("bank_gold", 0) + actual
	_send_stats(client)
	_send_bank_contents(client)
	_db.save_char(client.username, char_dict)


func _on_bank_withdraw_gold(client, amount: int) -> void:
	var char_dict: Dictionary = client.char
	var have: int = char_dict.get("bank_gold", 0)
	var actual: int = mini(amount, have)
	if actual <= 0:
		return
	char_dict["bank_gold"] = have - actual
	char_dict["gold"] = char_dict.get("gold", 0) + actual
	_send_stats(client)
	_send_bank_contents(client)
	_db.save_char(client.username, char_dict)


## Trade state: peer_id → {partner_pid, my_items:[{obj_index,amount,inv_slot}], confirmed:bool}
var _trades: Dictionary = {}
## Pending trade requests: target_peer_id → requester_peer_id (cleared when accepted or declined)
var _pending_trade_requests: Dictionary = {}


func _on_trade_request(client, target_id: int) -> void:
	var pid: int = client.peer_id
	if not _clients.has(target_id):
		_send_server_msg(client, "That player is not online.")
		return
	if _trades.has(pid) or _trades.has(target_id):
		_send_server_msg(client, "A trade is already in progress.")
		return
	var target_client = _clients[target_id]
	# Store pending request so respond can find the requester
	_pending_trade_requests[target_id] = pid
	# Send trade request to target
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(pid)
	w.write_str(client.char.get("name", "Unknown"))
	target_client.send_auth(NetProtocol.MsgType.S_TRADE_REQUEST, w.get_bytes())
	_send_server_msg(client, "Trade request sent to %s." % target_client.char.get("name", "?"))


func _on_trade_respond(client, accept: bool) -> void:
	var pid: int = client.peer_id
	if not _pending_trade_requests.has(pid):
		_send_server_msg(client, "No pending trade request.")
		return
	var requester_pid: int = _pending_trade_requests[pid]
	_pending_trade_requests.erase(pid)

	if not accept:
		# Notify requester of decline
		if _clients.has(requester_pid):
			_send_server_msg(_clients[requester_pid], "%s declined your trade request." % client.char.get("name", "?"))
		_send_server_msg(client, "You declined the trade request.")
		return

	if not _clients.has(requester_pid):
		_send_server_msg(client, "The other player has disconnected.")
		return
	if _trades.has(pid) or _trades.has(requester_pid):
		_send_server_msg(client, "A trade is already in progress.")
		return

	# Set up trade state for both players
	_trades[pid]           = {"partner_pid": requester_pid, "my_items": [], "confirmed": false}
	_trades[requester_pid] = {"partner_pid": pid,           "my_items": [], "confirmed": false}

	var req_client = _clients[requester_pid]
	_send_server_msg(client, "Trade started with %s. Click items in your inventory to offer them." % req_client.char.get("name", "?"))
	_send_server_msg(req_client, "%s accepted your trade request." % client.char.get("name", "?"))
	_broadcast_trade_state(pid, requester_pid)


func _on_trade_offer(client, inv_slot: int) -> void:
	var pid: int = client.peer_id
	if not _trades.has(pid):
		_send_server_msg(client, "You are not in a trade.")
		return
	var trade: Dictionary = _trades[pid]
	var char_dict: Dictionary = client.char
	var inv: Array = char_dict.get("inventory", [])
	if inv_slot < 0 or inv_slot >= inv.size():
		return
	var item: Dictionary = inv[inv_slot] as Dictionary
	if item.is_empty() or item.get("equipped", false):
		return
	var offer: Array = trade.get("my_items", [])
	offer.append({"obj_index": item.get("obj_index", 0), "amount": item.get("amount", 1), "inv_slot": inv_slot})
	trade["my_items"] = offer
	trade["confirmed"] = false
	_broadcast_trade_state(pid, trade.get("partner_pid", -1))


func _on_trade_retract(client, offer_slot: int) -> void:
	var pid: int = client.peer_id
	if not _trades.has(pid):
		return
	var trade: Dictionary = _trades[pid]
	var offer: Array = trade.get("my_items", [])
	if offer_slot < offer.size():
		offer.remove_at(offer_slot)
	trade["my_items"] = offer
	trade["confirmed"] = false
	_broadcast_trade_state(pid, trade.get("partner_pid", -1))


func _on_trade_confirm(client) -> void:
	var pid: int = client.peer_id
	if not _trades.has(pid):
		return
	var trade: Dictionary = _trades[pid]
	trade["confirmed"] = true
	var partner_pid: int = trade.get("partner_pid", -1)
	_broadcast_trade_state(pid, partner_pid)
	# Check if both confirmed
	if _trades.has(partner_pid) and _trades[partner_pid].get("confirmed", false):
		_complete_trade(pid, partner_pid)


func _on_trade_cancel(client) -> void:
	var pid: int = client.peer_id
	if not _trades.has(pid):
		return
	var partner_pid: int = _trades[pid].get("partner_pid", -1)
	_trades.erase(pid)
	if _trades.has(partner_pid):
		_trades.erase(partner_pid)
		if _clients.has(partner_pid):
			var w := NetProtocol.PacketWriter.new()
			w.write_str("Trade cancelled by other player.")
			_clients[partner_pid].send_auth(NetProtocol.MsgType.S_TRADE_CANCELLED, w.get_bytes())
	var w := NetProtocol.PacketWriter.new()
	w.write_str("Trade cancelled.")
	client.send_auth(NetProtocol.MsgType.S_TRADE_CANCELLED, w.get_bytes())


func _complete_trade(pid_a: int, pid_b: int) -> void:
	if not _clients.has(pid_a) or not _clients.has(pid_b):
		return
	var trade_a: Dictionary = _trades.get(pid_a, {})
	var trade_b: Dictionary = _trades.get(pid_b, {})
	var client_a = _clients[pid_a]
	var client_b = _clients[pid_b]
	var char_a: Dictionary = client_a.char
	var char_b: Dictionary = client_b.char
	var inv_a: Array = char_a.get("inventory", [])
	var inv_b: Array = char_b.get("inventory", [])
	# Remove offered items from inventories
	for offered in trade_a.get("my_items", []):
		var si: int = offered.get("inv_slot", -1)
		if si >= 0 and si < inv_a.size():
			inv_a[si] = {}
	for offered in trade_b.get("my_items", []):
		var si: int = offered.get("inv_slot", -1)
		if si >= 0 and si < inv_b.size():
			inv_b[si] = {}
	char_a["inventory"] = inv_a
	char_b["inventory"] = inv_b
	# Give items to each other
	for offered in trade_a.get("my_items", []):
		_give_item(char_b, offered.get("obj_index", 0), offered.get("amount", 1))
	for offered in trade_b.get("my_items", []):
		_give_item(char_a, offered.get("obj_index", 0), offered.get("amount", 1))
	# Notify both
	client_a.send_auth(NetProtocol.MsgType.S_TRADE_COMPLETE, PackedByteArray())
	client_b.send_auth(NetProtocol.MsgType.S_TRADE_COMPLETE, PackedByteArray())
	_send_inventory(client_a)
	_send_inventory(client_b)
	_db.save_char(client_a.username, char_a)
	_db.save_char(client_b.username, char_b)
	_trades.erase(pid_a)
	_trades.erase(pid_b)


func _broadcast_trade_state(pid_a: int, pid_b: int) -> void:
	if not _trades.has(pid_a) or not _trades.has(pid_b):
		return
	var trade_a: Dictionary = _trades[pid_a]
	var trade_b: Dictionary = _trades[pid_b]
	for pair in [[pid_a, trade_a, trade_b], [pid_b, trade_b, trade_a]]:
		var pid: int = pair[0]
		var my_t: Dictionary = pair[1]
		var their_t: Dictionary = pair[2]
		if not _clients.has(pid):
			continue
		var w := NetProtocol.PacketWriter.new()
		var my_items: Array = my_t.get("my_items", [])
		w.write_u8(my_items.size())
		for it in my_items:
			w.write_i16(it.get("obj_index", 0))
			w.write_u16(it.get("amount", 1))
		var their_items: Array = their_t.get("my_items", [])
		w.write_u8(their_items.size())
		for it in their_items:
			w.write_i16(it.get("obj_index", 0))
			w.write_u16(it.get("amount", 1))
		w.write_u8(1 if my_t.get("confirmed", false) else 0)
		w.write_u8(1 if their_t.get("confirmed", false) else 0)
		_clients[pid].send_auth(NetProtocol.MsgType.S_TRADE_STATE, w.get_bytes())


# ---------------------------------------------------------------------------
# Regen tick
# ---------------------------------------------------------------------------

## Update rain state randomly, broadcast changes to all players.
func _tick_weather() -> void:
	var new_raining: bool
	if _raining:
		new_raining = false   # always stop rain after one interval
	else:
		new_raining = randf() < RAIN_CHANCE   # 15% chance to start
	if new_raining == _raining:
		return
	_raining = new_raining
	var msg_type: int = NetProtocol.MsgType.S_RAIN_ON if _raining else NetProtocol.MsgType.S_RAIN_OFF
	for pid in _clients:
		var client = _clients[pid]
		if client.state == _ServerClientSCR.State.CONNECTED:
			client.send_auth(msg_type, PackedByteArray())
	print("[Server] Weather → %s" % ("Rain" if _raining else "Clear"))


func _tick_regen() -> void:
	for pid in _clients:
		var client = _clients[pid]
		if client.state != _ServerClientSCR.State.CONNECTED:
			continue
		var c: Dictionary = client.char

		# --- Hunger/Thirst decay ---
		var hunger: float = c.get("hunger", 80.0) - HUNGER_DECAY_PER_TICK
		var thirst: float = c.get("thirst", 80.0) - THIRST_DECAY_PER_TICK
		hunger = maxf(0.0, hunger)
		thirst = maxf(0.0, thirst)
		c["hunger"] = hunger
		c["thirst"] = thirst
		_send_vitals(client)

		var worst: float = minf(hunger, thirst)

		# --- Starvation / dehydration damage ---
		# Only at true 0%. Counter fires 1 HP every STARVATION_DMG_INTERVAL ticks (60s).
		if worst == 0.0:
			var starve_tick: int = c.get("_starve_tick", 0) + 1
			if starve_tick >= STARVATION_DMG_INTERVAL:
				starve_tick = 0
				if not _god_mode.has(pid):
					c["hp"] = maxi(0, c.get("hp", 0) - 1)
					_send_stats(client)
			c["_starve_tick"] = starve_tick
		else:
			c["_starve_tick"] = 0

		# --- Starvation death ---
		if c.get("hp", 1) <= 0 and not _god_mode.has(pid):
			_starve_death(client)
			continue

		# --- Vitals-based regen modifiers ---
		var regen_hp_bonus: int = 0
		var regen_mp_bonus: int = 0
		if hunger >= 75.0 and thirst >= 75.0:
			regen_hp_bonus += 2
			regen_mp_bonus += 1
		elif hunger >= 50.0 and thirst >= 50.0:
			regen_hp_bonus += 1
		elif worst < 25.0:
			# No regen when critically hungry/thirsty
			regen_hp_bonus = -999
			regen_mp_bonus = -999
		elif worst < 50.0:
			regen_hp_bonus -= 2

		# --- HP/MP/STA regen ---
		var changed := false
		for stat in ["hp", "mp", "sta"]:
			var max_stat: String = "max_" + stat
			var cur: int = c.get(stat, 0)
			var mx:  int = c.get(max_stat, 100)
			if cur < mx:
				var base_regen: int = maxi(1, mx / 20)
				var final_regen: int
				if stat == "hp":
					final_regen = maxi(0, base_regen + regen_hp_bonus)
				elif stat == "mp":
					final_regen = maxi(0, base_regen + regen_mp_bonus)
				else:
					final_regen = base_regen
				if final_regen > 0:
					c[stat] = mini(mx, cur + final_regen)
					changed = true
		if changed or worst < 25.0:
			var hw := NetProtocol.PacketWriter.new()
			hw.write_i16(c.get("hp", 0))
			hw.write_i16(c.get("mp", 0))
			hw.write_i16(c.get("sta", 0))
			client.send_auth(NetProtocol.MsgType.S_HEALTH, hw.get_bytes())


# ---------------------------------------------------------------------------
# Disconnect / cleanup
# ---------------------------------------------------------------------------

func _disconnect_client(pid: int) -> void:
	if not _clients.has(pid):
		return
	var client = _clients[pid]

	# Save character to disk
	if not client.username.is_empty() and not client.char.is_empty():
		_db.save_char(client.username, client.char)
		print("[Server] Saved char for %s" % client.username)

	# Broadcast removal to nearby clients
	if client.state == _ServerClientSCR.State.CONNECTED:
		_broadcast_remove(client)

	client.close()
	_clients.erase(pid)
	_spell_cooldowns.erase(pid)
	_poison_timers.erase(pid)
	_pending_trade_requests.erase(pid)
	_god_mode.erase(pid)
	_invisible.erase(pid)
	_mutes.erase(pid)
	# Cancel any active trade
	if _trades.has(pid):
		var partner_pid: int = _trades[pid].get("partner_pid", -1)
		_trades.erase(pid)
		if _trades.has(partner_pid):
			_trades.erase(partner_pid)
		if _clients.has(partner_pid):
			var w := NetProtocol.PacketWriter.new()
			w.write_str("Trade partner disconnected.")
			_clients[partner_pid].send_auth(NetProtocol.MsgType.S_TRADE_CANCELLED, w.get_bytes())
	print("[Server] Disconnected peer_id=%d (%s)" % [pid, client.username])


func _broadcast_remove(client) -> void:
	var c: Dictionary = client.char
	var map_id: int = c.get("map_id", 0)
	var cx: int = c.get("x", 0)
	var cy: int = c.get("y", 0)
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(client.peer_id)
	_broadcast_nearby(map_id, cx, cy, NetProtocol.MsgType.S_REMOVE_CHAR,
			w.get_bytes(), client.peer_id)


# ---------------------------------------------------------------------------
# Helpers: send to one client
# ---------------------------------------------------------------------------

func _send_auth_fail(client, reason: String) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_str(reason)
	client.send_preauth(NetProtocol.MsgType.AUTH_FAIL, w.get_bytes())


func _send_char_list(client) -> void:
	var chars: Array = _db.get_chars(client.username)
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(chars.size())
	for c in chars:
		var cd: Dictionary = c
		w.write_str(cd.get("name", ""))
		w.write_u8(cd.get("level", 1))
		w.write_u8(cd.get("class_id", 0))
		w.write_i16(cd.get("body", 1))
		w.write_i16(cd.get("head", 1))
	client.send_auth(NetProtocol.MsgType.S_CHAR_LIST, w.get_bytes())


func _send_create_result(client, success: bool, reason: String) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(1 if success else 0)
	w.write_str(reason)
	client.send_auth(NetProtocol.MsgType.S_CREATE_RESULT, w.get_bytes())


func _send_stats(client) -> void:
	var c: Dictionary = client.char
	# Apply vitals debuffs to visible max_hp/max_mp (base stats are unchanged in char dict)
	var worst: float = minf(c.get("hunger", 80.0), c.get("thirst", 80.0))
	var max_hp_debuff: int = 0
	var max_mp_debuff: int = 0
	if worst == 0.0:
		max_hp_debuff = -60
		max_mp_debuff = -30
	elif worst < 10.0:
		max_hp_debuff = -40
		max_mp_debuff = -20
	elif worst < 25.0:
		max_hp_debuff = -20
		max_mp_debuff = -10
	var eff_max_hp: int = maxi(1, c.get("max_hp", 100) + max_hp_debuff)
	var eff_max_mp: int = maxi(1, c.get("max_mp",  50) + max_mp_debuff)
	var eff_hp: int = mini(c.get("hp", 0), eff_max_hp)
	var eff_mp: int = mini(c.get("mp", 0), eff_max_mp)
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(c.get("level", 1))
	w.write_i16(eff_hp);           w.write_i16(eff_max_hp)
	w.write_i16(eff_mp);           w.write_i16(eff_max_mp)
	w.write_i16(c.get("sta", 0)); w.write_i16(c.get("max_sta", 100))
	w.write_i32(c.get("xp",       0)); w.write_i32(c.get("next_exp", 300))
	w.write_i32(c.get("gold",     0))
	client.send_auth(NetProtocol.MsgType.S_STATS, w.get_bytes())


func _send_inventory(client) -> void:
	var c: Dictionary = client.char
	var inv: Array = c.get("inventory", [])
	var w := NetProtocol.PacketWriter.new()
	var count := 0
	var items_data := PackedByteArray()
	for i in inv.size():
		var item: Dictionary = inv[i]
		if item.is_empty():
			continue
		var iw := NetProtocol.PacketWriter.new()
		iw.write_u8(i + 1)  # 1-based slot
		iw.write_i16(item.get("obj_index", 0))
		iw.write_u16(item.get("amount", 0))
		iw.write_u8(1 if item.get("equipped", false) else 0)
		items_data.append_array(iw.get_bytes())
		count += 1
	w.write_u8(count)
	w.write_bytes(items_data)
	client.send_auth(NetProtocol.MsgType.S_INVENTORY, w.get_bytes())


func _send_vitals(client) -> void:
	if client.state != _ServerClientSCR.State.CONNECTED:
		return
	if client.char.is_empty():
		return
	var c: Dictionary = client.char
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(int(clampf(c.get("hunger", 80.0), 0.0, 100.0)))
	w.write_u8(int(clampf(c.get("thirst", 80.0), 0.0, 100.0)))
	client.send_auth(NetProtocol.MsgType.S_VITALS, w.get_bytes())


func _send_skills(client) -> void:
	var c: Dictionary = client.char
	var sk:    Array = c.get("skills",   [])
	var sk_xp: Array = c.get("skill_xp", [])
	while sk.size()    < 28: sk.append(0)
	while sk_xp.size() < 28: sk_xp.append(0)
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(28)
	for i in 28:
		var lv:  int = sk[i]
		var xp:  int = sk_xp[i]
		w.write_u8(i + 1)                      # 1-based slot
		w.write_i16(lv)                         # skill level
		w.write_i32(xp)                         # XP within current level
		w.write_i32(_skill_xp_to_next(lv))     # XP needed for next level
	client.send_auth(NetProtocol.MsgType.S_SKILLS, w.get_bytes())


func _send_set_char(recipient, subject) -> void:
	var c: Dictionary = subject.char
	var equip: Dictionary = c.get("equipment", {})
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(subject.peer_id)
	w.write_i16(c.get("body",  1))
	w.write_i16(c.get("head",  1))
	var weapon_obj := GameData.get_object(equip.get("weapon", 0))
	w.write_i16(weapon_obj.get("weapon_anim", 0))
	var shield_obj := GameData.get_object(equip.get("shield", 0))
	w.write_i16(shield_obj.get("shield_anim", 0))
	w.write_i16(c.get("x", 1))
	w.write_i16(c.get("y", 1))
	w.write_u8(c.get("heading", 3))
	w.write_i16(c.get("hp", c.get("max_hp", 1)))
	w.write_i16(c.get("max_hp", 1))
	w.write_str(c.get("name", ""))
	recipient.send_auth(NetProtocol.MsgType.S_SET_CHAR, w.get_bytes())


func _broadcast_set_char(client) -> void:
	# Invisible players are not revealed to other clients
	if _invisible.has(client.peer_id):
		return
	var c: Dictionary = client.char
	var map_id: int = c.get("map_id", 0)
	var cx: int = c.get("x", 0)
	var cy: int = c.get("y", 0)
	var equip: Dictionary = c.get("equipment", {})
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(client.peer_id)
	w.write_i16(c.get("body",  1))
	w.write_i16(c.get("head",  1))
	var weapon_obj := GameData.get_object(equip.get("weapon", 0))
	w.write_i16(weapon_obj.get("weapon_anim", 0))
	var shield_obj := GameData.get_object(equip.get("shield", 0))
	w.write_i16(shield_obj.get("shield_anim", 0))
	w.write_i16(cx)
	w.write_i16(cy)
	w.write_u8(c.get("heading", 3))
	w.write_i16(c.get("hp", c.get("max_hp", 1)))
	w.write_i16(c.get("max_hp", 1))
	w.write_str(c.get("name", ""))
	_broadcast_nearby(map_id, cx, cy, NetProtocol.MsgType.S_SET_CHAR,
			w.get_bytes(), -1)


# ---------------------------------------------------------------------------
# Broadcast
# ---------------------------------------------------------------------------

func _broadcast_nearby(map_id: int, cx: int, cy: int, msg_type: int,
		payload: PackedByteArray, exclude_peer: int) -> void:
	## Uses _ai_map_clients cache when available (inside AI tick); falls back to
	## full client scan otherwise (e.g. player-initiated actions between AI ticks).
	if _ai_map_clients.has(map_id):
		for entry: Dictionary in _ai_map_clients[map_id]:
			if entry["pid"] == exclude_peer:
				continue
			if maxi(abs(int(entry["x"]) - cx), abs(int(entry["y"]) - cy)) <= NEARBY_RANGE:
				entry["cl"].send_auth(msg_type, payload)
	else:
		for pid in _clients:
			if pid == exclude_peer:
				continue
			var other = _clients[pid]
			if other.state != _ServerClientSCR.State.CONNECTED:
				continue
			var oc: Dictionary = other.char
			if oc.get("map_id", -1) != map_id:
				continue
			if maxi(abs(oc.get("x", 0) - cx), abs(oc.get("y", 0) - cy)) <= NEARBY_RANGE:
				other.send_auth(msg_type, payload)


func _broadcast_sound_near(map_id: int, tile: Vector2i, sound_num: int, radius: int = 12) -> void:
	## Sends S_PLAY_SOUND to all players within radius tiles on the same map.
	## Uses a direct client scan (not _ai_map_clients cache) so it works
	## both inside and outside the AI tick.
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(sound_num)
	var payload := w.get_bytes()
	for pid in _clients:
		var cl = _clients[pid]
		if cl.state != _ServerClientSCR.State.CONNECTED:
			continue
		var cc: Dictionary = cl.char
		if cc.get("map_id", 0) != map_id:
			continue
		if abs(cc.get("x", 0) - tile.x) > radius or abs(cc.get("y", 0) - tile.y) > radius:
			continue
		cl.send_auth(NetProtocol.MsgType.S_PLAY_SOUND, payload)


# ---------------------------------------------------------------------------
# Character creation
# ---------------------------------------------------------------------------

func _create_character(username: String, name_str: String,
		class_id: int, head_idx: int, body_idx: int = 0) -> Dictionary:
	if name_str.length() < 3 or name_str.length() > 16:
		return {"ok": false, "reason": "Name must be 3-16 characters."}
	for c in name_str:
		if not (c.unicode_at(0) >= 65 and c.unicode_at(0) <= 90) and \
				not (c.unicode_at(0) >= 97 and c.unicode_at(0) <= 122) and \
				not (c.unicode_at(0) >= 48 and c.unicode_at(0) <= 57) and \
				c != " ":
			return {"ok": false, "reason": "Name contains invalid characters."}
	class_id = clampi(class_id, 0, 3)
	var stats := _ServerCombatSCR.base_stats(class_id)
	# Use chosen body if provided and valid, otherwise fall back to class default
	var chosen_body: int = stats["body"]
	if body_idx > 0:
		var bd := GameData.get_body(body_idx)
		if not bd.is_empty():
			chosen_body = body_idx
	var char_dict := {
		"name":      name_str,
		"class_id":  class_id,
		"body":      chosen_body,
		"base_body": chosen_body,  # Original body index; restored when armor/clothing unequipped
		"head":      maxi(1, head_idx),
		"level":     1,
		"xp":        0,
		"next_exp":  _ServerCombatSCR.xp_to_next(1),
		"gold":      500,
		"map_id":    3,
		"x":         10,
		"y":         10,
		"hp":        stats["hp"],   "max_hp":  stats["hp"],
		"mp":        0,             "max_mp":  stats["max_mp"],
		"sta":       stats["sta"],  "max_sta": stats["sta"],
		"str":       stats["str"],
		"agi":       stats["agi"],
		"int_":      stats["int_"],
		"cha":       stats["cha"],
		"def":       stats["def"],
		"min_hit":   stats["min_hit"],
		"max_hit":   stats["max_hit"],
		"hunger":    80.0,
		"thirst":    80.0,
		"inventory": _class_starting_inventory(class_id),
		"equipment": {},
		"skills":    _class_starting_skills(class_id),
		"skill_xp":  [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],  # 28 slots
		"abilities": _class_starting_abilities(class_id),
		"spells":    _class_starting_spells(class_id),
	}
	return _db.add_char(username, char_dict)


func _class_starting_skills(class_id: int) -> Array:
	## Returns an Array of 28 ints (0-indexed) with class-appropriate starting skill values.
	var sk: Array = []
	sk.resize(28)
	sk.fill(0)
	match class_id:
		0:  # Warrior: sk6=8, sk16=12, sk17=9, sk22=2, sk24=5, sk26=2, sk19=1
			sk[5]  = 8;  sk[15] = 12; sk[16] = 9;  sk[21] = 2
			sk[23] = 5;  sk[25] = 2;  sk[18] = 1
		1:  # Mage: sk6=2, sk8=4, sk10=4, sk11=12, sk14=3, sk18=15, sk19=4, sk22=2, sk23=7, sk25=11, sk26=2, sk27=13
			sk[5]  = 2;  sk[7]  = 4;  sk[9]  = 4;  sk[10] = 12
			sk[13] = 3;  sk[17] = 15; sk[18] = 4;  sk[21] = 2
			sk[22] = 7;  sk[24] = 11; sk[25] = 2;  sk[26] = 13
		2:  # Rogue: sk1=8, sk2=2, sk15=2, sk19=3, sk23=12, sk25=4, sk26=1, sk27=5
			sk[0]  = 8;  sk[1]  = 2;  sk[14] = 2;  sk[18] = 3
			sk[22] = 12; sk[24] = 4;  sk[25] = 1;  sk[26] = 5
		3:  # Archer: sk6=8, sk3=4, sk7=1, sk8=3, sk10=2, sk16=0, sk19=14, sk23=4, sk25=10, sk26=3, sk27=4, sk28=20
			sk[5]  = 8;  sk[2]  = 4;  sk[6]  = 1;  sk[7]  = 3
			sk[9]  = 2;  sk[15] = 0;  sk[18] = 14; sk[22] = 4
			sk[24] = 10; sk[25] = 3;  sk[26] = 4;  sk[27] = 20  # Archery skill 20 (meets Aimed Shot req)
	return sk


func _class_starting_spells(class_id: int) -> Array:
	## Returns the starting spellbook for a given class.
	match class_id:
		1: return [3]   # Mage — Inner Flame (basic offensive projectile, 70 mana)
		_: return []    # All other classes start with no spells


func _class_starting_abilities(class_id: int) -> Array:
	## Returns the starting ability list for a given class.
	match class_id:
		0: return [0]   # Warrior  — Basic Attack
		1: return [0]   # Mage     — Basic Attack (spells are their real power)
		2: return [0]   # Rogue    — Basic Attack
		3: return [7]   # Archer   — Aimed Shot (class-defining basic ranged ability)
		_: return [0]


func _class_starting_inventory(class_id: int) -> Array:
	## Returns the starting inventory for a given class as a list of 20 slots.
	var inv: Array = []
	while inv.size() < 20:
		inv.append({})
	match class_id:
		3:  # Archer starts with Hunter's Bow + Pile Of Arrows
			inv[0] = {"obj_idx": 23, "amount": 1,  "equipped": false}  # Hunter's Bow
			inv[1] = {"obj_idx": 87, "amount": 50, "equipped": false}  # Pile Of Arrows
	return inv


# ---------------------------------------------------------------------------
# TLS setup
# ---------------------------------------------------------------------------

func _load_or_create_tls() -> TLSOptions:
	var key_path  := "user://server.key"
	var cert_path := "user://server.crt"
	var key:  CryptoKey
	var cert: X509Certificate
	var crypto := Crypto.new()

	if FileAccess.file_exists(key_path) and FileAccess.file_exists(cert_path):
		key  = CryptoKey.new()
		cert = X509Certificate.new()
		if key.load(key_path) == OK and cert.load(cert_path) == OK:
			print("[Server] Loaded existing TLS certificate.")
			return TLSOptions.server(key, cert)

	print("[Server] Generating self-signed TLS certificate...")
	key  = crypto.generate_rsa(2048)
	cert = crypto.generate_self_signed_certificate(key,
		"CN=EraOnline,O=EraOnline,C=US")
	key.save(key_path)
	cert.save(cert_path)
	print("[Server] TLS certificate saved to user://")
	return TLSOptions.server(key, cert)


# ---------------------------------------------------------------------------
# Autosave
# ---------------------------------------------------------------------------

func _save_all() -> void:
	for pid in _clients:
		var client = _clients[pid]
		if client.state == _ServerClientSCR.State.CONNECTED and \
				not client.username.is_empty() and not client.char.is_empty():
			_db.save_char(client.username, client.char)
	print("[Server] Autosave complete (%d connected)" % _clients.size())


# ---------------------------------------------------------------------------
# Misc helpers
# ---------------------------------------------------------------------------

func _generate_session_id() -> String:
	var b := Crypto.new().generate_random_bytes(8)
	return b.hex_encode()


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


# ---------------------------------------------------------------------------
# Magic / Spell system
# ---------------------------------------------------------------------------

func _send_spellbook(client) -> void:
	## Send the client their full learned spell list.
	var spell_ids: Array = client.char.get("spells", [])
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(mini(spell_ids.size(), 255))
	for sid in spell_ids:
		w.write_u8(int(sid))
	client.send_auth(S_SPELLBOOK, w.get_bytes())


## Skill name lookup for trainer validation messages (subset used by ability trainer).
const TRAINER_SKILL_NAMES := {
	6: "Tactics", 16: "Swordsmanship", 17: "Parrying", 28: "Archery"
}


func _send_abilities(client) -> void:
	## Send the client their full learned combat ability list.
	var char_dict: Dictionary = client.char
	var ability_ids: Array = char_dict.get("abilities", [0])
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(mini(ability_ids.size(), 255))
	for aid in ability_ids:
		w.write_u8(int(aid))
	client.send_auth(NetProtocol.MsgType.S_ABILITY_LIST, w.get_bytes())


func _send_hotbar(client) -> void:
	## Send the saved hotbar layout to the client on world entry.
	var slots: Array = client.char.get("hotbar", [])
	var w := NetProtocol.PacketWriter.new()
	var count: int = mini(slots.size(), 10)
	w.write_u8(count)
	for i in count:
		var s: Dictionary = slots[i]
		w.write_u8(i)                                        # slot index
		w.write_u8(0 if s.get("type","") == "ability" else 1)  # 0=ability 1=spell
		w.write_u8(int(s.get("id", 0)))                     # id
	client.send_auth(NetProtocol.MsgType.S_HOTBAR, w.get_bytes())


func _on_save_hotbar(client, r: NetProtocol.PacketReader) -> void:
	## Client sends their current hotbar layout to be persisted.
	var count: int = r.read_u8()
	var slots: Array = []
	for i in mini(count, 10):
		var slot_idx: int = r.read_u8()
		var slot_type: int = r.read_u8()  # 0=ability, 1=spell
		var slot_id: int  = r.read_u8()
		if slot_idx < 10:
			while slots.size() <= slot_idx:
				slots.append({})
			slots[slot_idx] = {"type": "ability" if slot_type == 0 else "spell", "id": slot_id}
	client.char["hotbar"] = slots


func _on_trainer_open(client, npc_instance_id: int) -> void:
	## Client opened a trainer NPC (npc_type == 4). Send the ability shop list.
	var npc: Dictionary = _npcs.get(npc_instance_id, {})
	if npc.is_empty() or npc.get("data", {}).get("npc_type", 0) != 4:
		return
	var char_dict: Dictionary = client.char
	var char_level: int = char_dict.get("level", 1)
	var char_skills: Array = char_dict.get("skills", [])
	var learned: Array = char_dict.get("abilities", [0])
	var trainer_abilities: Array = npc.get("data", {}).get("abilities", [])

	var w := NetProtocol.PacketWriter.new()
	w.write_u8(mini(trainer_abilities.size(), 255))
	for aid in trainer_abilities:
		var ab: Dictionary = GameData.get_ability(int(aid))
		if ab.is_empty():
			continue
		var req_lv: int     = ab.get("req_level", 1)
		var req_sk_id: int  = ab.get("req_skill_id", 16)
		var req_sk_val: int = ab.get("req_skill_val", 0)
		var sk_idx: int     = req_sk_id - 1  # 1-based to 0-based
		var char_skill_val: int = int(char_skills[sk_idx]) if sk_idx < char_skills.size() else 0
		var is_learned: int = 1 if learned.has(int(aid)) else 0
		w.write_u8(int(aid))
		w.write_str(ab.get("name", "?"))
		w.write_u16(int(ab.get("gold_cost", 0)))
		w.write_u8(req_lv)
		w.write_u8(req_sk_id)
		w.write_u8(req_sk_val)
		w.write_u8(is_learned)
	client.send_auth(NetProtocol.MsgType.S_ABILITY_SHOP, w.get_bytes())


func _on_learn_ability(client, r: NetProtocol.PacketReader) -> void:
	## Client wants to learn a combat ability from a trainer.
	var ability_id: int = r.read_u8()
	var char_dict: Dictionary = client.char
	var learned: Array = char_dict.get("abilities", [0])
	if learned.has(ability_id):
		_send_server_msg(client, "You already know that technique.")
		return
	var ab: Dictionary = GameData.get_ability(ability_id)
	if ab.is_empty():
		_send_server_msg(client, "Unknown ability.")
		return
	# Check level requirement
	var char_level: int = char_dict.get("level", 1)
	var req_lv: int     = ab.get("req_level", 1)
	if char_level < req_lv:
		_send_server_msg(client, "You must be level %d to learn %s." % [req_lv, ab.get("name", "?")])
		return
	# Check skill requirement
	var req_sk_id: int  = ab.get("req_skill_id", 16)
	var req_sk_val: int = ab.get("req_skill_val", 0)
	var char_skills: Array = char_dict.get("skills", [])
	var sk_idx: int = req_sk_id - 1
	var char_skill_val: int = int(char_skills[sk_idx]) if sk_idx < char_skills.size() else 0
	if char_skill_val < req_sk_val:
		var skill_name: String = TRAINER_SKILL_NAMES.get(req_sk_id, "Skill %d" % req_sk_id)
		_send_server_msg(client, "You need %s level %d to learn %s." % [skill_name, req_sk_val, ab.get("name", "?")])
		return
	# Check gold
	var gold_cost: int = ab.get("gold_cost", 0)
	if char_dict.get("gold", 0) < gold_cost:
		_send_server_msg(client, "You need %d gold to learn %s." % [gold_cost, ab.get("name", "?")])
		return
	# Deduct gold, add ability, save
	char_dict["gold"] -= gold_cost
	learned.append(ability_id)
	char_dict["abilities"] = learned
	_db.save_char(client.username, char_dict)
	# Confirm ability learned
	var aw := NetProtocol.PacketWriter.new()
	aw.write_u8(ability_id)
	client.send_auth(NetProtocol.MsgType.S_ABILITY_LEARNED, aw.get_bytes())
	_send_server_msg(client, "You have learned %s!" % ab.get("name", "?"))
	# Refresh gold display
	_send_stats(client)


func _open_spell_shop(client, npc_instance_id: int) -> void:
	## Send purchasable spell list from spells.json for an Arcane Vendor.
	var entries: Dictionary   = GameData.spells
	var player_spells: Array  = client.char.get("spells", [])
	var shop_spells: Array    = []
	for key in entries:
		var sp: Dictionary = entries[key]
		if not sp.get("purchasable", false):
			continue
		var sid := int(key)
		if sid in player_spells:
			continue
		shop_spells.append({"spell_id": sid, "price": sp.get("price", 100)})
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(mini(shop_spells.size(), 255))
	for entry in shop_spells:
		w.write_u8(entry["spell_id"])
		w.write_i16(entry["price"])
	client.send_auth(S_SPELL_SHOP, w.get_bytes())


func _handle_buy_spell(client, npc_instance_id: int, spell_id: int) -> void:
	## Client purchases a spell from the Arcane Vendor.
	if not _npcs.has(npc_instance_id):
		return
	var npc: Dictionary = _npcs[npc_instance_id]
	if npc["ai_state"] == "dead":
		return
	if npc["data"].get("npc_type", 0) != 3:
		return
	# Distance check
	var cc: Dictionary = client.char
	if npc["map_id"] != cc.get("map_id", -1):
		return
	var dist := maxi(abs(npc["x"] - cc.get("x",0)), abs(npc["y"] - cc.get("y",0)))
	if dist > 3:
		return

	# Look up spell
	var entries: Dictionary    = GameData.spells
	var key := str(spell_id)
	if not entries.has(key):
		return
	var sp: Dictionary = entries[key]
	if not sp.get("purchasable", false):
		return

	# Already learned?
	var player_spells: Array = cc.get("spells", [])
	if spell_id in player_spells:
		return

	# Deduct gold
	var price: int = sp.get("price", 100)
	var gold: int  = cc.get("gold", 0)
	if gold < price:
		return
	cc["gold"] = gold - price

	# Grant spell
	player_spells.append(spell_id)
	cc["spells"] = player_spells

	# Notify client
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(spell_id)
	client.send_auth(S_SPELL_UNLOCK, w.get_bytes())
	_send_stats(client)   # Refresh gold display
	_db.save_char(client.username, cc)   # Persist purchase immediately


func _handle_cast_spell(client, spell_id: int, target_id: int, tx: int, ty: int) -> void:
	## Validate and resolve a spell cast request.
	var cc: Dictionary = client.char

	# Must have learned this spell
	var player_spells: Array = cc.get("spells", [])
	if spell_id not in player_spells:
		print("[Server] SPELL REJECTED peer=%d spell=%d: not in spellbook (spellbook=%s)" % [
			client.peer_id, spell_id, str(player_spells)])
		return

	# Look up spell data
	var entries: Dictionary    = GameData.spells
	var key := str(spell_id)
	if not entries.has(key):
		print("[Server] SPELL REJECTED peer=%d spell=%d: no entry in GameData.spells" % [
			client.peer_id, spell_id])
		return
	var sp: Dictionary = entries[key]

	# Mana check (skip deduction during testing — infinite mana mode)
	var needs_mana: int = sp.get("needs_mana", 0)
	var _cur_mp: int    = cc.get("mp", 0)
	# TODO: re-enable mana deduction when mana regen is implemented
	# if _cur_mp < needs_mana:
	# 	print("[Server] SPELL REJECTED peer=%d spell=%d: not enough MP (%d/%d)" % [
	# 		client.peer_id, spell_id, _cur_mp, needs_mana])
	# 	return

	# Cooldown check
	var now_ms := Time.get_ticks_msec()
	var peer_cds: Dictionary = _spell_cooldowns.get(client.peer_id, {})
	if peer_cds.get(spell_id, 0) > now_ms:
		var remaining_ms: int = int(peer_cds.get(spell_id, 0)) - now_ms
		print("[Server] SPELL REJECTED peer=%d spell=%d: on cooldown (%d ms remaining)" % [
			client.peer_id, spell_id, remaining_ms])
		return

	# Deduct mana
	# cc["mp"] = maxi(0, _cur_mp - needs_mana)   # disabled: infinite mana mode

	# Set cooldown
	var cooldown_sec: float = sp.get("cooldown", 2.0)
	peer_cds[spell_id] = now_ms + int(cooldown_sec * 1000.0)
	_spell_cooldowns[client.peer_id] = peer_cds

	# Broadcast cast animation to everyone on this map
	var caster_id: int = client.peer_id
	var map_id: int    = cc.get("map_id", -1)
	_broadcast_spell_cast(map_id, caster_id, spell_id, target_id, tx, ty)

	# Spell cast sound — use per-spell sound if defined, else generic effect
	var spell_sound: int = int(sp.get("sound", 0))
	if spell_sound <= 0:
		spell_sound = SOUND_SPELL_CAST
	var cx_cast: int = cc.get("x", 0)
	var cy_cast: int = cc.get("y", 0)
	_broadcast_sound_near(map_id, Vector2i(cx_cast, cy_cast), spell_sound)

	# Resolve effect by target type
	var target_type: int = sp.get("target_type", 0)
	print("[Server] SPELL CAST peer=%d spell=%d target_type=%d target_id=%d map=%d" % [
		client.peer_id, spell_id, target_type, target_id, map_id])
	match target_type:
		0:  # SELF
			_spell_apply_to_char(client, client.peer_id, spell_id, sp, map_id)
		1:  # SINGLE_ENEMY (target_id >= NPC_ID_BASE = NPC, else player peer)
			_spell_single_target(client, target_id, spell_id, sp, map_id)
		2:  # SINGLE_ALLY
			_spell_single_target(client, target_id, spell_id, sp, map_id)
		3:  # GROUND_AOE
			_spell_ground_aoe(client, spell_id, sp, map_id, tx, ty)
		4:  # SELF_AOE
			_spell_self_aoe(client, spell_id, sp, map_id)
		_:
			print("[Server] SPELL WARNING peer=%d spell=%d: unknown target_type=%d" % [
				client.peer_id, spell_id, target_type])

	# Update caster HP/MP/STA bar
	_send_stats(client)

	# Grant Magery skill XP
	_award_skill_xp(client, cc, 11)


func _broadcast_spell_cast(map_id: int, caster_id: int, spell_id: int, target_id: int, tx: int, ty: int) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(caster_id)
	w.write_u8(spell_id)
	w.write_i32(target_id)
	w.write_i16(tx)
	w.write_i16(ty)
	var payload := w.get_bytes()
	for pid in _clients:
		var other = _clients[pid]
		if other.state == _ServerClientSCR.State.CONNECTED and \
				other.char.get("map_id", -1) == map_id:
			other.send_auth(S_SPELL_CAST, payload)


func _spell_apply_to_char(client, char_id: int, spell_id: int, sp: Dictionary, map_id: int) -> void:
	## Apply spell effects to a player (client). Used for SELF target or ally heals.
	var cc: Dictionary = client.char
	var dmg    := int(sp.get("damage_hp",  0))
	var heal   := int(sp.get("heal_hp",    0))
	var mdrn   := int(sp.get("damage_man", 0))
	var hmana  := int(sp.get("heal_man",   0))
	var status := int(sp.get("status_id",  0))
	var give_food  := int(sp.get("give_food",  0))
	var give_drink := int(sp.get("give_drink", 0))
	var give_money := int(sp.get("give_money", 0))
	var give_exp   := int(sp.get("give_exp",   0))
	var invis_ms   := int(sp.get("invisibility", 0))
	var teleport   := int(sp.get("teleport", 0))
	var resurrect  := int(sp.get("ressurection", 0))

	if dmg > 0 and not _god_mode.has(client.peer_id):
		cc["hp"] = maxi(0, cc.get("hp", 0) - dmg)
	if heal > 0:
		cc["hp"] = mini(cc.get("max_hp", 100), cc.get("hp", 0) + heal)
	if mdrn > 0:
		cc["mp"] = maxi(0, cc.get("mp", 0) - mdrn)
	if hmana > 0:
		# heal_man restores MP to the CASTER (self) when applied to self
		var caster_cc: Dictionary = client.char
		caster_cc["mp"] = mini(caster_cc.get("max_mp", 100), caster_cc.get("mp", 0) + hmana)
	if give_food > 0:
		cc["hunger"] = minf(100.0, cc.get("hunger", 80.0) + float(give_food))
		_send_vitals(client)
	if give_drink > 0:
		cc["thirst"] = minf(100.0, cc.get("thirst", 80.0) + float(give_drink))
		_send_vitals(client)
	if give_money > 0:
		cc["gold"] = cc.get("gold", 0) + give_money
	if give_exp > 0:
		cc["xp"] = cc.get("xp", 0) + give_exp
		_ServerCombatSCR.try_level_up(cc)
	if invis_ms > 0:
		# Grant invisibility status (status_id 10 = invisible)
		_broadcast_status_applied(map_id, char_id, 10, invis_ms)
	if status > 0:
		var dur_ms := int(sp.get("status_dur", 3.0) * 1000.0)
		_broadcast_status_applied(map_id, char_id, status, dur_ms)
	if teleport == 1:
		# Anchor/teleport toggle
		if cc.has("anchor_map"):
			# Teleport to anchor
			var amap: int = cc["anchor_map"]
			var ax: int   = cc["anchor_x"]
			var ay: int   = cc["anchor_y"]
			cc.erase("anchor_map"); cc.erase("anchor_x"); cc.erase("anchor_y")
			cc["map_id"] = amap; cc["x"] = ax; cc["y"] = ay
			_db.save_char(client.username, cc)
			var ww := NetProtocol.PacketWriter.new()
			ww.write_i32(amap); ww.write_i16(ax); ww.write_i16(ay)
			client.send_auth(NetProtocol.MsgType.S_MAP_CHANGE, ww.get_bytes())
		else:
			# Set anchor at current position
			cc["anchor_map"] = cc.get("map_id", 1)
			cc["anchor_x"]   = cc.get("x", 10)
			cc["anchor_y"]   = cc.get("y", 10)
			_db.save_char(client.username, cc)
	if resurrect == 1:
		# Heal self if very low (resurrection on self = fortify)
		if cc.get("hp", 1) <= 0:
			cc["hp"] = maxi(1, cc.get("max_hp", 100) / 4)

	# Send caster_message from spell data so the player sees text feedback
	var caster_msg: String = sp.get("caster_message", "")
	if not caster_msg.is_empty() and caster_msg != "You cast the spell at the target":
		var mw := NetProtocol.PacketWriter.new()
		mw.write_str(caster_msg)
		client.send_auth(NetProtocol.MsgType.S_SERVER_MSG, mw.get_bytes())

	_send_stats(client)
	_broadcast_spell_hit(map_id, char_id, spell_id, dmg, heal, mdrn)


func _spell_single_target(client, target_id: int, spell_id: int, sp: Dictionary, map_id: int) -> void:
	## Apply to a single NPC or player target.
	var effect_type: String = sp.get("effect_type", "hit")
	if effect_type == "chain":
		_spell_chain_lightning(client, target_id, spell_id, sp, map_id)
		return

	var dmg     := int(sp.get("damage_hp",   0))
	var heal    := int(sp.get("heal_hp",     0))
	var mdrn    := int(sp.get("damage_man",  0))
	var hmana   := int(sp.get("heal_man",    0))
	var status  := int(sp.get("status_id",   0))
	var give_money := int(sp.get("give_money", 0))
	var resurrect  := int(sp.get("ressurection", 0))
	var is_push: bool = (effect_type == "push")

	# NPC target
	if target_id >= NPC_ID_BASE and _npcs.has(target_id):
		var npc: Dictionary = _npcs[target_id]
		if npc["ai_state"] == "dead" or npc["map_id"] != map_id:
			print("[Server] SPELL SINGLE-TARGET REJECTED spell=%d target_id=%d: NPC dead or wrong map" % [
				spell_id, target_id])
			return
		var range_tiles: int = sp.get("range", 8)
		var cx: int = client.char.get("x", 0)
		var cy: int = client.char.get("y", 0)
		if maxi(abs(npc["x"] - cx), abs(npc["y"] - cy)) > range_tiles:
			print("[Server] SPELL SINGLE-TARGET REJECTED spell=%d target_id=%d: out of range (%d tiles, max %d)" % [
				spell_id, target_id,
				maxi(abs(npc["x"] - cx), abs(npc["y"] - cy)), range_tiles])
			return
		if dmg > 0:
			npc["hp"] = maxi(0, npc["hp"] - dmg)
		if mdrn > 0:
			# Drain mana from NPC (NPCs track mana as mp field)
			npc["mp"] = maxi(0, npc.get("mp", 0) - mdrn)
		if hmana > 0:
			# Drain/siphon: restore caster mana
			var cc: Dictionary = client.char
			cc["mp"] = mini(cc.get("max_mp", 100), cc.get("mp", 0) + hmana)
		if status > 0:
			var dur_ms := int(sp.get("status_dur", 3.0) * 1000.0)
			_broadcast_status_applied(map_id, target_id, status, dur_ms)
		if is_push:
			# Knockback: push NPC 2 tiles away from caster
			var dx: int = npc["x"] - cx
			var dy: int = npc["y"] - cy
			var push_dist := 2
			if abs(dx) >= abs(dy):
				npc["x"] = clampi(npc["x"] + (push_dist if dx >= 0 else -push_dist), 1, 100)
			else:
				npc["y"] = clampi(npc["y"] + (push_dist if dy >= 0 else -push_dist), 1, 100)
			# Broadcast NPC position update
			var mw := NetProtocol.PacketWriter.new()
			mw.write_i32(target_id)
			mw.write_i16(npc["x"]); mw.write_i16(npc["y"]); mw.write_u8(3)
			var mpayload := mw.get_bytes()
			for pid in _clients:
				var other = _clients[pid]
				if other.state == _ServerClientSCR.State.CONNECTED and \
						other.char.get("map_id", -1) == map_id:
					other.send_auth(NetProtocol.MsgType.S_MOVE_CHAR, mpayload)
		_broadcast_spell_hit(map_id, target_id, spell_id, dmg, heal, mdrn)
		if npc["hp"] <= 0:
			_npc_death(npc, client)
		return

	# Player target (ally heal, exp grant, etc.)
	if _clients.has(target_id):
		var other = _clients[target_id]
		if other.state != _ServerClientSCR.State.CONNECTED:
			print("[Server] SPELL SINGLE-TARGET REJECTED spell=%d target_id=%d: player not CONNECTED" % [
				spell_id, target_id])
			return
		if other.char.get("map_id", -1) != map_id:
			print("[Server] SPELL SINGLE-TARGET REJECTED spell=%d target_id=%d: player on different map" % [
				spell_id, target_id])
			return
		var oc: Dictionary = other.char
		if resurrect == 1 and oc.get("hp", 1) <= 0:
			oc["hp"] = maxi(1, oc.get("max_hp", 100) / 4)
		if give_money > 0:
			oc["gold"] = oc.get("gold", 0) + give_money
		_spell_apply_to_char(other, target_id, spell_id, sp, map_id)
		return

	# target_id resolved to neither a known NPC nor a connected player — log it.
	print("[Server] SPELL SINGLE-TARGET REJECTED spell=%d target_id=%d: target not found (not NPC, not player)" % [
		spell_id, target_id])


func _spell_ground_aoe(client, spell_id: int, sp: Dictionary, map_id: int, cx: int, cy: int) -> void:
	## Hit all NPCs/players within aoe_radius tiles of (cx, cy). Also handles summon.
	var summon_creature: int = sp.get("summon_creature", 0)
	if summon_creature > 0:
		_spell_summon_at(client, spell_id, sp, map_id, cx, cy)
		return

	var radius: int = sp.get("aoe_radius", 3)
	var dmg    := int(sp.get("damage_hp",  0))
	var status := int(sp.get("status_id",  0))
	for nid in _npcs:
		var npc: Dictionary = _npcs[nid]
		if npc["ai_state"] == "dead" or npc["map_id"] != map_id:
			continue
		if maxi(abs(npc["x"] - cx), abs(npc["y"] - cy)) > radius:
			continue
		if dmg > 0:
			npc["hp"] = maxi(0, npc["hp"] - dmg)
		if status > 0:
			var dur_ms := int(sp.get("status_dur", 3.0) * 1000.0)
			_broadcast_status_applied(map_id, nid, status, dur_ms)
		_broadcast_spell_hit(map_id, nid, spell_id, dmg, 0, 0)
		if npc["hp"] <= 0:
			_npc_death(npc, client)


func _spell_summon_at(client, spell_id: int, sp: Dictionary, map_id: int, cx: int, cy: int) -> void:
	## Spawn one or more summons defined by the spell's summon_* fields.
	var duration_sec: float = sp.get("status_dur", 30.0)
	var s_name: String      = sp.get("summon_name",  "Summon")
	var s_body: int         = sp.get("summon_body",  2)
	var s_head: int         = sp.get("summon_head",  5)
	var s_hp: int           = sp.get("summon_hp",    60)
	var s_min_hit: int      = sp.get("summon_dmg",   3)
	var s_max_hit: int      = s_min_hit + 5
	var s_count: int        = sp.get("summon_count", 1)

	var offsets: Array = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1),
		Vector2i(1,1), Vector2i(-1,1), Vector2i(1,-1), Vector2i(-1,-1)]

	for n in s_count:
		var spawn_x := cx
		var spawn_y := cy
		for off in offsets.slice(n * 2, n * 2 + 4):
			var tx: int = cx + int(off.x)
			var ty: int = cy + int(off.y)
			if tx < 1 or tx > 100 or ty < 1 or ty > 100:
				continue
			spawn_x = tx; spawn_y = ty; break

		var npc_data := {
			"name": s_name, "body": s_body, "head": s_head,
			"weapon_anim": 0, "shield_anim": 0,
			"npc_type": 1, "hostile": 1, "movement": 2,
			"max_hp": s_hp, "min_hit": s_min_hit, "max_hit": s_max_hit, "def": 0,
			"gold": 0, "level": 1, "summoned_by": client.peer_id
		}
		var npc_id := _npc_counter
		_npc_counter += 1
		_npcs[npc_id] = {
			"instance_id": npc_id, "data": npc_data,
			"map_id": map_id, "x": spawn_x, "y": spawn_y,
			"spawn_x": spawn_x, "spawn_y": spawn_y,
			"hp": s_hp, "max_hp": s_hp,
			"heading": 3, "ai_state": "idle",
			"target_peer": 0, "target_npc_id": -1,
			# Stagger each summon's first action so they don't tick in sync
			"next_action_at": Time.get_ticks_msec() / 1000.0 + float(n) * 0.4 + randf_range(0.0, 0.5),
			"respawn_at": 0.0,
		}
		_broadcast_npc_set_char(_npcs[npc_id])
		get_tree().create_timer(duration_sec).timeout.connect(func():
			if _npcs.has(npc_id):
				_despawn_npc(npc_id, map_id))


func _despawn_npc(npc_id: int, map_id: int) -> void:
	## Remove an NPC and notify all clients on its map.
	_npcs.erase(npc_id)
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(npc_id)
	var payload := w.get_bytes()
	for pid in _clients:
		var other = _clients[pid]
		if other.state == _ServerClientSCR.State.CONNECTED and \
				other.char.get("map_id", -1) == map_id:
			other.send_auth(NetProtocol.MsgType.S_REMOVE_CHAR, payload)


func _spell_self_aoe(client, spell_id: int, sp: Dictionary, map_id: int) -> void:
	## AoE centered on caster.
	var cx: int = client.char.get("x", 0)
	var cy: int = client.char.get("y", 0)
	_spell_ground_aoe(client, spell_id, sp, map_id, cx, cy)


func _spell_chain_lightning(client, first_target: int, spell_id: int, sp: Dictionary, map_id: int) -> void:
	## Chain between up to chain_count NPCs, diminishing damage each hop.
	var max_chain: int   = sp.get("chain_count", 3)
	var base_dmg: int    = sp.get("damage_hp",   0)
	var chain_range: int = sp.get("range",        6)
	var hit_ids: Array   = []
	var cur_target := first_target
	var cur_dmg    := base_dmg

	for _i in max_chain:
		if cur_target < NPC_ID_BASE or not _npcs.has(cur_target):
			break
		var npc: Dictionary = _npcs[cur_target]
		if npc["ai_state"] == "dead" or npc["map_id"] != map_id:
			break
		hit_ids.append(cur_target)
		if cur_dmg > 0:
			npc["hp"] = maxi(0, npc["hp"] - cur_dmg)
		_broadcast_spell_hit(map_id, cur_target, spell_id, cur_dmg, 0, 0)
		if npc["hp"] <= 0:
			_npc_death(npc, client)
		# Find nearest un-hit NPC within chain_range
		var next_id := -1
		var best_dist := chain_range + 1
		for nid in _npcs:
			if nid in hit_ids:
				continue
			var cand: Dictionary = _npcs[nid]
			if cand["ai_state"] == "dead" or cand["map_id"] != map_id:
				continue
			var d := maxi(abs(cand["x"] - npc["x"]), abs(cand["y"] - npc["y"]))
			if d < best_dist:
				best_dist = d
				next_id   = nid
		cur_dmg    = int(cur_dmg * 0.7)   # 30% falloff per hop
		cur_target = next_id

	# Broadcast chain packet
	if hit_ids.size() > 0:
		var w := NetProtocol.PacketWriter.new()
		w.write_u8(spell_id)
		w.write_u8(mini(hit_ids.size(), 255))
		for tid in hit_ids:
			w.write_i32(tid)
		var payload := w.get_bytes()
		for pid in _clients:
			var other = _clients[pid]
			if other.state == _ServerClientSCR.State.CONNECTED and \
					other.char.get("map_id", -1) == map_id:
				other.send_auth(S_SPELL_CHAIN, payload)


func _broadcast_spell_hit(map_id: int, target_id: int, spell_id: int, dmg: int, heal: int, mdrn: int) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(target_id)
	w.write_u8(spell_id)
	w.write_i16(dmg)
	w.write_i16(heal)
	w.write_i16(mdrn)
	var payload := w.get_bytes()
	for pid in _clients:
		var other = _clients[pid]
		if other.state == _ServerClientSCR.State.CONNECTED and \
				other.char.get("map_id", -1) == map_id:
			other.send_auth(S_SPELL_HIT, payload)


func _broadcast_status_applied(map_id: int, char_id: int, status_id: int, duration_ms: int) -> void:
	# Track expiry so we can auto-remove when duration ends
	if not _active_statuses.has(char_id):
		_active_statuses[char_id] = {}
	_active_statuses[char_id][status_id] = Time.get_ticks_msec() + duration_ms

	var w := NetProtocol.PacketWriter.new()
	w.write_i32(char_id)
	w.write_u8(status_id)
	w.write_u16(duration_ms)
	var payload := w.get_bytes()
	for pid in _clients:
		var other = _clients[pid]
		if other.state == _ServerClientSCR.State.CONNECTED and \
				other.char.get("map_id", -1) == map_id:
			other.send_auth(S_STATUS_APPLIED, payload)


func _broadcast_status_removed(map_id: int, char_id: int, status_id: int) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(char_id)
	w.write_u8(status_id)
	var payload := w.get_bytes()
	for pid in _clients:
		var other = _clients[pid]
		if other.state == _ServerClientSCR.State.CONNECTED and \
				other.char.get("map_id", -1) == map_id:
			other.send_auth(S_STATUS_REMOVED, payload)


# ---------------------------------------------------------------------------
# Random Encounter System
# ---------------------------------------------------------------------------

func _tick_random_encounters(now: float) -> void:
	## Rolls for a random ambush encounter on each connected player
	## who is on a non-town wilderness map.
	for pid in _clients:
		var cl = _clients[pid]
		if cl.state != _ServerClientSCR.State.CONNECTED:
			continue
		var tc: Dictionary = cl.char
		var map_id: int = tc.get("map_id", -1)
		if map_id in TOWN_MAPS:
			continue
		# Respect per-player cooldown
		if now < float(_encounter_cooldowns.get(pid, 0.0)):
			continue
		if randf() > ENCOUNTER_CHANCE:
			continue
		_spawn_random_encounter(pid, tc, map_id, now)


func _spawn_random_encounter(pid: int, tc: Dictionary, map_id: int, now: float) -> void:
	## Spawns a level-appropriate group of NPCs near the player.
	var player_level: int = maxi(1, tc.get("level", 1))
	var templates := _encounter_templates_for(player_level)
	if templates.is_empty():
		return

	# Pick a template entry — weight toward matching level range
	var tpl: Dictionary = templates[randi() % templates.size()]

	var px: int = tc.get("x", 50)
	var py: int = tc.get("y", 50)
	var group_size: int = tpl.get("count", 1)
	var spawned := 0

	for i in range(group_size):
		# Try up to 6 random offsets to find a walkable tile
		for _attempt in range(6):
			var ox := randi_range(-5, 5)
			var oy := randi_range(-5, 5)
			var ex := clampi(px + ox, 1, 100)
			var ey := clampi(py + oy, 1, 100)
			if GameData.get_map_tile(map_id, ex, ey).get("blocked", 0) != 0:
				continue

			var eid := _npc_counter
			_npc_counter += 1
			var enc_data: Dictionary = tpl["data"].duplicate(true)

			# Pull correct appearance from NPC.dat — template values are just fallbacks.
			var npc_idx: int = tpl.get("npc_index", 0)
			if npc_idx > 0:
				var npc_raw := GameData.get_npc(npc_idx)
				if not npc_raw.is_empty():
					enc_data["body"]        = npc_raw.get("body",        enc_data.get("body", 1))
					enc_data["head"]        = npc_raw.get("head",        enc_data.get("head", 1))
					enc_data["weapon_anim"] = npc_raw.get("weapon_anim", 0)
					enc_data["shield_anim"] = npc_raw.get("shield_anim", 0)

			var enc_hp: int = enc_data.get("max_hp", 100)
			var npc_state: Dictionary = {
				"instance_id":    eid,
				"npc_index":      npc_idx,
				"map_id":         map_id,
				"x": ex, "y": ey, "spawn_x": ex, "spawn_y": ey,
				"heading":        3,
				"hp":             enc_hp,
				"max_hp":         enc_hp,
				"min_hit":        enc_data.get("min_hit", 3),
				"max_hit":        enc_data.get("max_hit", 8),
				"def":            enc_data.get("def", 0),
				"give_exp":       enc_data.get("give_exp", player_level * 10),
				"ai_state":       "chase",
				"target_peer":    pid,
				"next_action_at": 0.0,
				"respawn_at":     0.0,
				"data":           enc_data,
				"is_encounter":   true,
			}
			_npc_init_behavior(npc_state)
			# Encounter NPCs always ambush — override non-hostile behaviors
			# (e.g. spiderling is "skittish" in the behavior table normally).
			if npc_state["behavior"] in ["skittish", "passive", "civilian", "patrol"]:
				npc_state["behavior"] = "aggressive"
			_npcs[eid] = npc_state
			_broadcast_npc_set_char(npc_state)
			_encounter_despawn_at[eid] = now + ENCOUNTER_DESPAWN_SECS
			spawned += 1
			break

	if spawned > 0:
		_encounter_cooldowns[pid] = now + randf_range(ENCOUNTER_COOLDOWN_MIN, ENCOUNTER_COOLDOWN_MAX)
		var msg_w := NetProtocol.PacketWriter.new()
		msg_w.write_str("You have been ambushed by %s!" % tpl.get("label", "enemies"))
		_clients[pid].send_auth(NetProtocol.MsgType.S_SERVER_MSG, msg_w.get_bytes())
		print("[Server] Encounter: spawned %d %s near player %d on map %d" % [
			spawned, tpl.get("label", "?"), pid, map_id])


func _encounter_templates_for(player_level: int) -> Array:
	## Returns an array of encounter template dicts appropriate for player_level.
	## Each template: {label, count, npc_index (optional), data, min_lv, max_lv}
	var all_templates: Array = [
		# ── Tier 1: L1-8 ────────────────────────────────────────────────────
		{
			"label": "giant spiders", "count": 2, "min_lv": 1, "max_lv": 8,
			"npc_index": 510,
			"data": {"name": "Giant Spider", "hostile": 1, "attackable": 1,
				"body": 8, "head": 1, "movement": 2, "heading": 3,
				"max_hp": 30, "min_hit": 2, "max_hit": 6, "def": 0,
				"level": 3, "give_exp": 20, "give_gld": 5},
		},
		{
			"label": "a skeleton wanderer", "count": 1, "min_lv": 1, "max_lv": 8,
			"npc_index": 502,
			"data": {"name": "Skeleton", "hostile": 1, "attackable": 1,
				"body": 3, "head": 1, "movement": 2, "heading": 3,
				"max_hp": 40, "min_hit": 3, "max_hit": 8, "def": 0,
				"level": 4, "give_exp": 30, "give_gld": 8},
		},
		# ── Tier 2: L5-15 ───────────────────────────────────────────────────
		{
			"label": "a pack of gnolls", "count": 3, "min_lv": 5, "max_lv": 15,
			"npc_index": 526,
			"data": {"name": "Gnoll", "hostile": 1, "attackable": 1,
				"body": 6, "head": 3, "movement": 2, "heading": 3,
				"max_hp": 70, "min_hit": 4, "max_hit": 10, "def": 1,
				"level": 8, "give_exp": 55, "give_gld": 12},
		},
		{
			"label": "orc warriors", "count": 2, "min_lv": 7, "max_lv": 15,
			"npc_index": 521,
			"data": {"name": "Orc Warrior", "hostile": 1, "attackable": 1,
				"body": 7, "head": 2, "movement": 2, "heading": 3,
				"max_hp": 90, "min_hit": 6, "max_hit": 14, "def": 2,
				"level": 10, "give_exp": 75, "give_gld": 18},
		},
		# ── Tier 3: L12-25 ──────────────────────────────────────────────────
		{
			"label": "bandits", "count": 3, "min_lv": 12, "max_lv": 25,
			"npc_index": 9,
			"data": {"name": "Bandit", "hostile": 1, "attackable": 1,
				"body": 4, "head": 2, "movement": 2, "heading": 3,
				"max_hp": 120, "min_hit": 8, "max_hit": 18, "def": 3,
				"level": 15, "give_exp": 100, "give_gld": 30},
		},
		{
			"label": "a troll pack", "count": 2, "min_lv": 14, "max_lv": 25,
			"npc_index": 523,
			"data": {"name": "Troll", "hostile": 1, "attackable": 1,
				"body": 9, "head": 4, "movement": 2, "heading": 3,
				"max_hp": 180, "min_hit": 10, "max_hit": 22, "def": 4,
				"level": 18, "give_exp": 140, "give_gld": 25},
		},
		# ── Tier 4: L20-35 ──────────────────────────────────────────────────
		{
			"label": "daemon followers", "count": 2, "min_lv": 20, "max_lv": 35,
			"npc_index": 524,
			"data": {"name": "Daemon", "hostile": 1, "attackable": 1,
				"body": 10, "head": 5, "movement": 2, "heading": 3,
				"max_hp": 250, "min_hit": 14, "max_hit": 28, "def": 5,
				"level": 25, "give_exp": 200, "give_gld": 45},
		},
		{
			"label": "a necromancer and zombies", "count": 2, "min_lv": 22, "max_lv": 35,
			"npc_index": 56,
			"data": {"name": "Necromancer", "hostile": 1, "attackable": 1,
				"body": 2, "head": 8, "movement": 2, "heading": 3,
				"max_hp": 160, "min_hit": 12, "max_hit": 26, "def": 3,
				"level": 24, "give_exp": 180, "give_gld": 60},
		},
		# ── Tier 5: L30-50 ──────────────────────────────────────────────────
		{
			"label": "snow yetis", "count": 2, "min_lv": 30, "max_lv": 45,
			"npc_index": 522,
			"data": {"name": "Snow Yeti", "hostile": 1, "attackable": 1,
				"body": 12, "head": 6, "movement": 2, "heading": 3,
				"max_hp": 350, "min_hit": 18, "max_hit": 36, "def": 7,
				"level": 35, "give_exp": 280, "give_gld": 55},
		},
		{
			"label": "a minotaur", "count": 1, "min_lv": 35, "max_lv": 50,
			"npc_index": 533,
			"data": {"name": "Minotaur", "hostile": 1, "attackable": 1,
				"body": 14, "head": 7, "movement": 2, "heading": 3,
				"max_hp": 500, "min_hit": 22, "max_hit": 44, "def": 9,
				"level": 42, "give_exp": 400, "give_gld": 80},
		},
	]

	# Filter by level range and return matching templates
	var result: Array = []
	for tpl in all_templates:
		if player_level >= tpl["min_lv"] and player_level <= tpl["max_lv"]:
			result.append(tpl)
	return result


# ---------------------------------------------------------------------------
# Admin / moderator command system
# ---------------------------------------------------------------------------

## ---------------------------------------------------------------------------
## HTTP Status Server — responds to GET /status on port 6969+1 (6970)
## Used by the launcher to show online/offline + player count.
## ---------------------------------------------------------------------------
const STATUS_HTTP_PORT : int = 6970
var _status_tcp: TCPServer = null
var _status_clients: Array = []

func _start_status_server() -> void:
	_status_tcp = TCPServer.new()
	var err := _status_tcp.listen(STATUS_HTTP_PORT)
	if err != OK:
		push_error("[Status] Could not listen on port %d" % STATUS_HTTP_PORT)
		return
	print("[Status] HTTP status server on port %d" % STATUS_HTTP_PORT)

func _tick_status_server() -> void:
	if _status_tcp == null:
		return
	if _status_tcp.is_connection_available():
		_status_clients.append(_status_tcp.take_connection())
	for i in range(_status_clients.size() - 1, -1, -1):
		var conn: StreamPeerTCP = _status_clients[i]
		if conn.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_status_clients.remove_at(i)
			continue
		var avail := conn.get_available_bytes()
		if avail <= 0:
			continue
		conn.get_string(avail)  # consume request, we don't parse it
		var player_count := _clients.size()
		var body := '{"online":true,"players":%d,"max":1000}' % player_count
		var response := "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [body.length(), body]
		conn.put_data(response.to_utf8_buffer())
		_status_clients.remove_at(i)

func _load_admin_list() -> void:
	var path := "user://server_data/admins.txt"
	if not FileAccess.file_exists(path):
		# Create empty file as a template
		DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path("user://server_data/"))
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_string("# Add one username per line to grant admin access\n# Example:\n# myusername\n")
			f.close()
		print("[Admin] admins.txt not found — created template at %s" % ProjectSettings.globalize_path(path))
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		_admin_names.append(line.to_lower())
	f.close()
	print("[Admin] Loaded %d admin name(s) from admins.txt" % _admin_names.size())


func _handle_admin_command(client, raw: String) -> void:
	var pid: int              = client.peer_id
	var char_dict: Dictionary = client.char
	var role: int             = int(char_dict.get("role", 0))
	var parts: Array          = raw.split(" ", false)
	if parts.is_empty():
		return
	var cmd: String = (parts[0] as String).to_lower()

	# Helper: find a connected client by character name (case-insensitive)
	var _find_by_name := func(target_name: String):
		for p in _clients:
			var cl = _clients[p]
			if cl.state != _ServerClientSCR.State.CONNECTED:
				continue
			if cl.char.get("name", "").to_lower() == target_name.to_lower():
				return cl
		return null

	# /help is available to everyone
	if cmd == "/help":
		_send_server_msg(client, "=== Commands ===")
		if role >= 1:
			_send_server_msg(client, "Mod: /kick /mute /unmute /goto /warn /info /broadcast")
		if role >= 2:
			_send_server_msg(client, "Admin: /ban /unban /give /giveto /gold /goldto /god /invis /map /tp /summon /heal /healall /level /setlevel /spawn /setadmin /setmod /demote /shutdown")
		_send_server_msg(client, "Chat: /w <player> <msg>  (private whisper)")
		return

	# Whisper — no role required
	if cmd == "/w" or cmd == "/whisper":
		if parts.size() < 3:
			_send_server_msg(client, "Usage: /w <player> <message>")
			return
		var target_name_w: String = parts[1]
		var whisper_msg: String   = " ".join(parts.slice(2))
		_send_whisper(client, target_name_w, whisper_msg)
		return

	# /wanted and /top — public, no role required
	if cmd == "/wanted":
		_send_bounty_board(client)
		return

	if cmd == "/top":
		_send_server_msg(client, "=== Leaderboards ===")
		var lb_cats: Array = ["kills", "crafts", "level", "fishing"]
		var lb_labels: Array = ["Kills", "Crafts", "Level", "Fishing"]
		for li in lb_cats.size():
			var cat: String = lb_cats[li] as String
			var board: Array = _leaderboards.get(cat, [])
			_send_server_msg(client, "-- Top %s --" % (lb_labels[li] as String))
			var show_n: int = mini(5, board.size())
			if show_n == 0:
				_send_server_msg(client, "(no data)")
				continue
			for i in show_n:
				var e: Dictionary = board[i] as Dictionary
				_send_server_msg(client, "  %d. %s — %d" % [i + 1, e.get("name", "?"), int(e.get("score", 0))])
		return

	# All remaining commands require at least moderator role
	if role < 1:
		_send_server_msg(client, "Unknown command.")
		return

	match cmd:
		"/kick":
			if parts.size() < 2:
				_send_server_msg(client, "Usage: /kick <player>"); return
			var target = _find_by_name.call(parts[1])
			if target == null:
				_send_server_msg(client, "Player not found."); return
			_send_server_msg(target, "You have been kicked by a moderator.")
			_disconnect_client(target.peer_id)
			_send_server_msg(client, "Kicked %s." % parts[1])

		"/mute":
			if parts.size() < 2:
				_send_server_msg(client, "Usage: /mute <player> [minutes]"); return
			var target = _find_by_name.call(parts[1])
			if target == null:
				_send_server_msg(client, "Player not found."); return
			var mins: int = int(parts[2]) if parts.size() >= 3 else 30
			var expiry: int = 0 if mins <= 0 else Time.get_ticks_msec() + mins * 60000
			_mutes[target.peer_id] = expiry
			var duration_str: String = "permanently" if mins <= 0 else "for %d minutes" % mins
			_send_server_msg(target, "You have been muted %s." % duration_str)
			_send_server_msg(client, "Muted %s %s." % [parts[1], duration_str])

		"/unmute":
			if parts.size() < 2:
				_send_server_msg(client, "Usage: /unmute <player>"); return
			var target = _find_by_name.call(parts[1])
			if target == null:
				_send_server_msg(client, "Player not found."); return
			_mutes.erase(target.peer_id)
			_send_server_msg(target, "You have been unmuted.")
			_send_server_msg(client, "Unmuted %s." % parts[1])

		"/goto":
			if parts.size() < 2:
				_send_server_msg(client, "Usage: /goto <player>"); return
			var target = _find_by_name.call(parts[1])
			if target == null:
				_send_server_msg(client, "Player not found."); return
			var tc: Dictionary = target.char
			_teleport(client, int(tc.get("map_id", 1)), int(tc.get("x", 10)), int(tc.get("y", 10)))

		"/warn":
			if parts.size() < 3:
				_send_server_msg(client, "Usage: /warn <player> <reason>"); return
			var target = _find_by_name.call(parts[1])
			if target == null:
				_send_server_msg(client, "Player not found."); return
			var reason_warn: String = " ".join(parts.slice(2))
			_send_server_msg(target, "[WARNING] %s" % reason_warn)
			_send_server_msg(client, "Warning sent to %s." % parts[1])

		"/info":
			if parts.size() < 2:
				_send_server_msg(client, "Usage: /info <player>"); return
			var target = _find_by_name.call(parts[1])
			if target == null:
				_send_server_msg(client, "Player not found."); return
			var tc: Dictionary = target.char
			_send_server_msg(client, "=== %s ===" % tc.get("name", "?"))
			_send_server_msg(client, "Map: %d  Pos: %d,%d  Level: %d" % [
				tc.get("map_id", 0), tc.get("x", 0), tc.get("y", 0), tc.get("level", 1)])
			_send_server_msg(client, "HP: %d/%d  Role: %d  Account: %s" % [
				tc.get("hp", 0), tc.get("max_hp", 0), int(tc.get("role", 0)), target.username])

		"/broadcast":
			if parts.size() < 2:
				_send_server_msg(client, "Usage: /broadcast <message>"); return
			var msg_text: String = "[ANNOUNCEMENT] " + " ".join(parts.slice(1))
			for p in _clients:
				var cl = _clients[p]
				if cl.state == _ServerClientSCR.State.CONNECTED:
					_send_server_msg(cl, msg_text)

		# Admin-only commands — gate by role >= 2
		"/bounty":
			if parts.size() < 2:
				_send_server_msg(client, "Usage: /bounty <player>"); return
			var _find_by_name_b := func(n: String):
				for p in _clients:
					var cl = _clients[p]
					if cl.state == _ServerClientSCR.State.CONNECTED and cl.char.get("name", "").to_lower() == n.to_lower():
						return cl
				return null
			var _bt = _find_by_name_b.call(parts[1])
			if _bt == null:
				_send_server_msg(client, "Player not found."); return
			var _bb: int = int(_bt.char.get("bounty", 0))
			_send_server_msg(client, "%s has a bounty of %d gold." % [parts[1], _bb])

		"/ban", "/unban", "/give", "/giveto", "/gold", "/goldto", "/spawn", "/god", "/invis", "/map", "/tp", "/summon", "/level", "/setlevel", "/heal", "/healall", "/setadmin", "/setmod", "/demote", "/shutdown":
			if role < 2:
				_send_server_msg(client, "You don't have permission to use that command.")
				return
			_handle_admin_only_command(client, cmd, parts)

		_:
			_send_server_msg(client, "Unknown command: %s" % cmd)


func _handle_admin_only_command(client, cmd: String, parts: Array) -> void:
	var pid: int              = client.peer_id
	var char_dict: Dictionary = client.char

	var _find_by_name := func(target_name: String):
		for p in _clients:
			var cl = _clients[p]
			if cl.state != _ServerClientSCR.State.CONNECTED:
				continue
			if cl.char.get("name", "").to_lower() == target_name.to_lower():
				return cl
		return null

	match cmd:
		"/ban":
			if parts.size() < 2:
				_send_server_msg(client, "Usage: /ban <player> [reason]"); return
			var ban_reason_str: String = " ".join(parts.slice(2)) if parts.size() > 2 else "Banned by admin"
			var target = _find_by_name.call(parts[1])
			if target != null:
				var acc_ban: Dictionary = _db.load_account(target.username)
				acc_ban["banned"]     = true
				acc_ban["ban_reason"] = ban_reason_str
				_db.save_account(target.username, acc_ban)
				_send_server_msg(target, "You have been banned: %s" % ban_reason_str)
				_disconnect_client(target.peer_id)
				_send_server_msg(client, "Banned %s: %s" % [parts[1], ban_reason_str])
			else:
				# Offline account ban
				var uname_ban: String = (parts[1] as String).to_lower()
				if _db.account_exists(uname_ban):
					var acc_ban: Dictionary = _db.load_account(uname_ban)
					acc_ban["banned"]     = true
					acc_ban["ban_reason"] = ban_reason_str
					_db.save_account(uname_ban, acc_ban)
					_send_server_msg(client, "Banned offline account %s." % uname_ban)
				else:
					_send_server_msg(client, "Account not found: %s" % parts[1])

		"/unban":
			if parts.size() < 2:
				_send_server_msg(client, "Usage: /unban <username>"); return
			var uname_unban: String = (parts[1] as String).to_lower()
			if _db.account_exists(uname_unban):
				var acc_ub: Dictionary = _db.load_account(uname_unban)
				acc_ub.erase("banned")
				acc_ub.erase("ban_reason")
				_db.save_account(uname_unban, acc_ub)
				_send_server_msg(client, "Unbanned %s." % uname_unban)
			else:
				_send_server_msg(client, "Account not found: %s" % parts[1])

		"/give":
			if parts.size() < 2:
				_send_server_msg(client, "Usage: /give <item_id> [amount]"); return
			var obj_idx_give: int = int(parts[1])
			var amount_give: int  = int(parts[2]) if parts.size() >= 3 else 1
			if GameData.get_object(obj_idx_give).is_empty():
				_send_server_msg(client, "Invalid item ID."); return
			_give_item(char_dict, obj_idx_give, amount_give)
			_send_inventory(client)
			_send_server_msg(client, "Gave yourself %dx item %d." % [amount_give, obj_idx_give])

		"/giveto":
			if parts.size() < 3:
				_send_server_msg(client, "Usage: /giveto <player> <item_id> [amount]"); return
			var target = _find_by_name.call(parts[1])
			if target == null:
				_send_server_msg(client, "Player not found."); return
			var obj_idx_gt: int = int(parts[2])
			var amount_gt: int  = int(parts[3]) if parts.size() >= 4 else 1
			if GameData.get_object(obj_idx_gt).is_empty():
				_send_server_msg(client, "Invalid item ID."); return
			_give_item(target.char, obj_idx_gt, amount_gt)
			_send_inventory(target)
			_send_server_msg(target, "An admin gave you %dx %s." % [amount_gt, GameData.get_object(obj_idx_gt).get("name", "item")])
			_send_server_msg(client, "Gave %s %dx item %d." % [parts[1], amount_gt, obj_idx_gt])

		"/gold":
			if parts.size() < 2:
				_send_server_msg(client, "Usage: /gold <amount>"); return
			char_dict["gold"] = char_dict.get("gold", 0) + int(parts[1])
			_send_stats(client)
			_send_server_msg(client, "Added %d gold." % int(parts[1]))

		"/goldto":
			if parts.size() < 3:
				_send_server_msg(client, "Usage: /goldto <player> <amount>"); return
			var target = _find_by_name.call(parts[1])
			if target == null:
				_send_server_msg(client, "Player not found."); return
			var gold_amt: int = int(parts[2])
			target.char["gold"] = target.char.get("gold", 0) + gold_amt
			_send_stats(target)
			_send_server_msg(target, "An admin gave you %d gold." % gold_amt)
			_send_server_msg(client, "Gave %s %d gold." % [parts[1], gold_amt])

		"/god":
			if _god_mode.has(pid):
				_god_mode.erase(pid)
				_send_server_msg(client, "God mode OFF.")
			else:
				_god_mode[pid] = true
				_send_server_msg(client, "God mode ON — you are invincible.")

		"/invis":
			if _invisible.has(pid):
				_invisible.erase(pid)
				_broadcast_set_char(client)
				_send_server_msg(client, "Invisibility OFF.")
			else:
				_invisible[pid] = true
				_broadcast_remove(client)
				_send_server_msg(client, "Invisibility ON — others cannot see you.")

		"/map":
			if parts.size() < 2:
				_send_server_msg(client, "Usage: /map <map_id>"); return
			var dest_map: int = int(parts[1])
			if GameData.get_map(dest_map).is_empty():
				_send_server_msg(client, "Map %d does not exist." % dest_map); return
			_teleport(client, dest_map, 0, 0)

		"/tp":
			if parts.size() < 2:
				_send_server_msg(client, "Usage: /tp <x> <y>  OR  /tp <player>"); return
			if parts.size() >= 3 and (parts[1] as String).is_valid_int() and (parts[2] as String).is_valid_int():
				_teleport(client, int(char_dict.get("map_id", 1)), int(parts[1]), int(parts[2]))
			else:
				var target = _find_by_name.call(parts[1])
				if target == null:
					_send_server_msg(client, "Player not found."); return
				var tc_tp: Dictionary = target.char
				_teleport(client, int(tc_tp.get("map_id", 1)), int(tc_tp.get("x", 10)), int(tc_tp.get("y", 10)))

		"/summon":
			if parts.size() < 2:
				_send_server_msg(client, "Usage: /summon <player>"); return
			var target = _find_by_name.call(parts[1])
			if target == null:
				_send_server_msg(client, "Player not found."); return
			_teleport(target, int(char_dict.get("map_id", 1)), int(char_dict.get("x", 10)), int(char_dict.get("y", 10)))
			_send_server_msg(target, "You have been summoned by an admin.")
			_send_server_msg(client, "Summoned %s." % parts[1])

		"/heal":
			char_dict["hp"] = char_dict.get("max_hp", 100)
			char_dict["mp"] = char_dict.get("max_mp", 100)
			_send_stats(client)
			_send_server_msg(client, "Fully healed.")

		"/healall":
			for p in _clients:
				var cl = _clients[p]
				if cl.state == _ServerClientSCR.State.CONNECTED:
					cl.char["hp"] = cl.char.get("max_hp", 100)
					cl.char["mp"] = cl.char.get("max_mp", 100)
					_send_stats(cl)
			_send_server_msg(client, "Healed all players.")

		"/level":
			if parts.size() < 2:
				_send_server_msg(client, "Usage: /level <1-50>"); return
			var new_level_self: int = clampi(int(parts[1]), 1, 50)
			char_dict["level"] = new_level_self
			_ServerCombatSCR.recalculate_combat_stats(char_dict)
			_send_stats(client)
			_send_server_msg(client, "Level set to %d." % new_level_self)

		"/setlevel":
			if parts.size() < 3:
				_send_server_msg(client, "Usage: /setlevel <player> <1-50>"); return
			var target = _find_by_name.call(parts[1])
			if target == null:
				_send_server_msg(client, "Player not found."); return
			var new_level_t: int = clampi(int(parts[2]), 1, 50)
			target.char["level"] = new_level_t
			_ServerCombatSCR.recalculate_combat_stats(target.char)
			_send_stats(target)
			_send_server_msg(target, "An admin set your level to %d." % new_level_t)
			_send_server_msg(client, "Set %s to level %d." % [parts[1], new_level_t])

		"/setadmin":
			if parts.size() < 2:
				_send_server_msg(client, "Usage: /setadmin <player>"); return
			var target = _find_by_name.call(parts[1])
			if target == null:
				_send_server_msg(client, "Player not found (must be online)."); return
			target.char["role"] = 2
			_db.save_char(target.username, target.char)
			_send_server_msg(target, "You have been granted admin privileges.")
			_send_server_msg(client, "Promoted %s to admin." % parts[1])

		"/setmod":
			if parts.size() < 2:
				_send_server_msg(client, "Usage: /setmod <player>"); return
			var target = _find_by_name.call(parts[1])
			if target == null:
				_send_server_msg(client, "Player not found (must be online)."); return
			target.char["role"] = 1
			_db.save_char(target.username, target.char)
			_send_server_msg(target, "You have been granted moderator privileges.")
			_send_server_msg(client, "Promoted %s to moderator." % parts[1])

		"/demote":
			if parts.size() < 2:
				_send_server_msg(client, "Usage: /demote <player>"); return
			var target = _find_by_name.call(parts[1])
			if target == null:
				_send_server_msg(client, "Player not found (must be online)."); return
			target.char["role"] = 0
			_db.save_char(target.username, target.char)
			_send_server_msg(target, "Your staff privileges have been removed.")
			_send_server_msg(client, "Demoted %s to player." % parts[1])

		"/spawn":
			if parts.size() < 2:
				_send_server_msg(client, "Usage: /spawn <npc_id>"); return
			var npc_idx_spawn: int = int(parts[1])
			if GameData.get_npc(npc_idx_spawn).is_empty():
				_send_server_msg(client, "Invalid NPC ID."); return
			var spawn_map: int = int(char_dict.get("map_id", 1))
			var spawn_cx: int  = int(char_dict.get("x", 10))
			var spawn_cy: int  = int(char_dict.get("y", 10))
			_spawn_npc_at(spawn_map, npc_idx_spawn, spawn_cx + 1, spawn_cy)
			_send_server_msg(client, "Spawned NPC %d." % npc_idx_spawn)

		"/shutdown":
			for p in _clients:
				var cl = _clients[p]
				if cl.state == _ServerClientSCR.State.CONNECTED:
					_send_server_msg(cl, "Server is shutting down. Goodbye!")
					_db.save_char(cl.username, cl.char)
			_send_server_msg(client, "Shutting down...")
			await get_tree().create_timer(1.0).timeout
			get_tree().quit()

		_:
			_send_server_msg(client, "Unknown admin command: %s" % cmd)


func _spawn_npc_at(map_id: int, npc_index: int, x: int, y: int) -> void:
	## Spawns a single NPC instance at the given position on the given map.
	## Uses the same initialisation logic as _spawn_map_npcs.
	var npc_data := GameData.get_npc(npc_index)
	if npc_data.is_empty():
		print("[Server] _spawn_npc_at: Unknown NPC %d" % npc_index)
		return

	var eff_data: Dictionary = npc_data.duplicate(false)
	var is_hostile: bool = npc_data.get("hostile", 0) != 0
	var attackable: bool = npc_data.get("attackable", 0) != 0
	var inventory: Array = npc_data.get("inventory", [])
	if (not is_hostile) and (not attackable) and inventory.size() >= 5:
		eff_data["npc_type"] = 2
		var shop_items: Array = []
		for inv_entry in inventory:
			var oi: int = int(inv_entry.get("obj_index", 0))
			if oi > 0:
				shop_items.append(oi)
		eff_data["items"] = shop_items
	elif is_hostile or attackable:
		eff_data["npc_type"] = 1
		var drops: Array = []
		for inv_entry in inventory:
			var oi: int = int(inv_entry.get("obj_index", 0))
			if oi > 0:
				drops.append(oi)
		if not drops.is_empty():
			eff_data["drop_items"] = drops
	else:
		eff_data["npc_type"] = 0

	var level: int   = maxi(1, int(npc_data.get("level", 1)))
	var max_hp: int  = int(npc_data.get("max_hp", 0))
	if max_hp <= 0:
		max_hp = level * 15 + 20 if is_hostile else 300
	var min_hit: int = int(npc_data.get("min_hit", 0))
	if min_hit <= 0:
		min_hit = maxi(1, level - 1) if is_hostile else 0
	var max_hit: int = int(npc_data.get("max_hit", 0))
	if max_hit <= 0:
		max_hit = (level * 2 + 2) if is_hostile else 0
	var def_v: int   = int(npc_data.get("def", 0))
	var give_exp: int = int(npc_data.get("give_exp", level * 15))
	var heading: int  = int(npc_data.get("heading", 3))
	if heading <= 0:
		heading = 3

	var safe := _find_safe_spawn(map_id, x, y)
	var instance_id := _npc_counter
	_npc_counter += 1
	var npc_state: Dictionary = {
		"instance_id": instance_id,
		"npc_index":   npc_index,
		"map_id":      map_id,
		"x":           safe.x,
		"y":           safe.y,
		"spawn_x":     safe.x,
		"spawn_y":     safe.y,
		"heading":     heading,
		"hp":          max_hp,
		"max_hp":      max_hp,
		"min_hit":     min_hit,
		"max_hit":     max_hit,
		"def":         def_v,
		"give_exp":    give_exp,
		"ai_state":    "idle",
		"target_peer": 0,
		"next_action_at": 0.0,
		"respawn_at":  0.0,
		"data":        eff_data,
	}
	_npc_init_behavior(npc_state)
	_schedule_npc_next_action(npc_state, Time.get_ticks_msec() / 1000.0, "idle")
	_npcs[instance_id] = npc_state
	_broadcast_npc_set_char(npc_state)
	print("[Server] Admin spawned NPC %d (instance %d) on map %d @ (%d,%d)" % [
		npc_index, instance_id, map_id, safe.x, safe.y])


# ---------------------------------------------------------------------------
# Feature 1: Loot Rarity System
# ---------------------------------------------------------------------------

func _rarity_suffix(rarity: int) -> String:
	match rarity:
		1: return " [Uncommon]"
		2: return " [Rare]"
		3: return " [LEGENDARY]"
	return ""


func _roll_item_rarity() -> int:
	## Returns 0=Common, 1=Uncommon, 2=Rare, 3=Legendary
	var r := randf()
	if r < 0.01:   return 3  # 1%
	if r < 0.08:   return 2  # 7%
	if r < 0.25:   return 1  # 17%
	return 0                  # 75%


func _apply_item_rarity(item_dict: Dictionary, obj_data: Dictionary, map_id: int, x: int, y: int) -> void:
	## Rolls rarity on a dropped item, modifies its value multiplier, and notifies map.
	var rarity: int = _roll_item_rarity()
	item_dict["rarity"] = rarity
	if rarity == 0:
		return
	var obj_name: String = obj_data.get("name", "item")
	var rw := NetProtocol.PacketWriter.new()
	rw.write_str(obj_name + _rarity_suffix(rarity))
	rw.write_u8(rarity)
	rw.write_i16(x)
	rw.write_i16(y)
	_broadcast_map(map_id, S_RARE_DROP_NOTIFY, rw.get_bytes())


# ---------------------------------------------------------------------------
# Feature 4: Bounty / Wanted System
# ---------------------------------------------------------------------------

func _send_bounty_board(client) -> void:
	## Sends the top 5 most-wanted players as server messages.
	var bounties: Array = []
	for pid in _clients:
		var cl = _clients[pid]
		if cl.state == _ServerClientSCR.State.CONNECTED:
			var b: int = int(cl.char.get("bounty", 0))
			if b > 0:
				bounties.append({"name": cl.char.get("name", "?"), "bounty": b})
	bounties.sort_custom(func(a, b): return int(a["bounty"]) > int(b["bounty"]))
	_send_server_msg(client, "=== Most Wanted ===")
	if bounties.is_empty():
		_send_server_msg(client, "No outlaws at large.")
		return
	var limit: int = mini(5, bounties.size())
	for i in limit:
		var entry: Dictionary = bounties[i] as Dictionary
		_send_server_msg(client,
				"%d. %s — %d gold" % [i + 1, entry.get("name", "?"), int(entry.get("bounty", 0))])


# ---------------------------------------------------------------------------
# Feature 8: Player Titles
# ---------------------------------------------------------------------------

func _update_title(client) -> void:
	## Checks for newly earned titles and updates char_dict if a new one is earned.
	var char_dict: Dictionary = client.char
	var progress: Dictionary = char_dict.get("achievement_progress", {})
	var new_title: String = ""

	# Iterate in reverse so highest-threshold titles take priority
	var defs_copy: Array = TITLE_DEFS.duplicate()
	defs_copy.reverse()
	for td in defs_copy:
		var td_d: Dictionary = td as Dictionary
		var event: String    = td_d.get("event", "")
		var threshold: int   = int(td_d.get("threshold", 0))
		var current_val: int = 0
		match event:
			"gold":  current_val = int(char_dict.get("gold", 0))
			"level": current_val = int(char_dict.get("level", 1))
			"maps":  current_val = char_dict.get("visited_maps", []).size()
			_:       current_val = int(progress.get(event, 0))
		if current_val >= threshold:
			new_title = td_d.get("title", "")
			break

	if new_title.is_empty() or new_title == char_dict.get("title", ""):
		return

	char_dict["title"] = new_title
	var map_id: int = int(char_dict.get("map_id", 0))

	var tw := NetProtocol.PacketWriter.new()
	tw.write_i32(client.peer_id)
	tw.write_str(new_title)
	_broadcast_map(map_id, S_TITLE_UPDATE, tw.get_bytes())
	_send_server_msg(client, "You have earned the title [%s]!" % new_title)
	_db.save_char(client.username, char_dict)


# ---------------------------------------------------------------------------
# Broadcast helpers (addiction loop systems)
# ---------------------------------------------------------------------------

func _broadcast_map(map_id: int, msg_type: int, bytes: PackedByteArray) -> void:
	## Sends a message to every connected player on a specific map.
	for _bm_pid in _clients:
		var _bm_cl = _clients[_bm_pid]
		if _bm_cl.state == _ServerClientSCR.State.CONNECTED and \
				_bm_cl.char.get("map_id", -1) == map_id:
			_bm_cl.send_auth(msg_type, bytes)


func _broadcast_all_connected(msg_type: int, bytes: PackedByteArray) -> void:
	## Sends a message to every connected player on the server.
	for _bac_pid in _clients:
		var _bac_cl = _clients[_bac_pid]
		if _bac_cl.state == _ServerClientSCR.State.CONNECTED:
			_bac_cl.send_auth(msg_type, bytes)


func _send_server_msg_to_map(map_id: int, message: String) -> void:
	## Sends a server message string to all connected players on a given map.
	var _mw := NetProtocol.PacketWriter.new()
	_mw.write_str(message)
	for _mm_pid in _clients:
		var _mm_cl = _clients[_mm_pid]
		if _mm_cl.state == _ServerClientSCR.State.CONNECTED and _mm_cl.char.get("map_id", -1) == map_id:
			_mm_cl.send_auth(NetProtocol.MsgType.S_SERVER_MSG, _mw.get_bytes())


# ---------------------------------------------------------------------------
# Feature 2: Boss Monster Spawns
# ---------------------------------------------------------------------------

func _try_spawn_boss(map_id: int) -> void:
	## Attempts to spawn the boss for the given map_id.
	var boss_def: Dictionary = {}
	for _bd in BOSS_DEFS:
		if int(_bd["map_id"]) == map_id:
			boss_def = _bd
			break
	if boss_def.is_empty():
		_boss_timers.erase(map_id)
		return

	# Check if already spawned and alive
	if _boss_instances.get(map_id, 0) != 0:
		var existing_id: int = int(_boss_instances[map_id])
		if _npcs.has(existing_id) and _npcs[existing_id]["ai_state"] != "dead":
			_boss_timers[map_id] = float(boss_def["spawn_interval"])
			return

	var safe_pos: Vector2i = _find_safe_spawn(map_id, 50, 50)
	var npc_index: int = int(boss_def["npc_index"])
	var boss_name: String = boss_def.get("name", "Boss")

	_spawn_npc_at(map_id, npc_index, safe_pos.x, safe_pos.y)

	var new_instance_id: int = _npc_counter - 1
	if _npcs.has(new_instance_id):
		var boss_npc: Dictionary = _npcs[new_instance_id]
		boss_npc["hp"]      = boss_npc["max_hp"] * 3
		boss_npc["max_hp"]  = boss_npc["max_hp"] * 3
		boss_npc["min_hit"] = boss_npc["min_hit"] * 2
		boss_npc["max_hit"] = boss_npc["max_hit"] * 2
		boss_npc["data"]["is_boss"]   = true
		boss_npc["data"]["boss_name"] = boss_name
		_boss_instances[map_id] = new_instance_id

	var map_data := GameData.get_map(map_id)
	var map_name: String = "the wilderness"
	if not map_data.is_empty():
		map_name = map_data.get("name", "the wilderness")
	_send_server_msg_to_map(map_id,
			"A powerful boss has appeared: %s on %s! Seek it out for great rewards!" % [boss_name, map_name])

	var sw := NetProtocol.PacketWriter.new()
	sw.write_str("A powerful boss has appeared somewhere in the world...")
	_broadcast_all_connected(NetProtocol.MsgType.S_SERVER_MSG, sw.get_bytes())
	_boss_timers[map_id] = float(boss_def["spawn_interval"])
	print("[Boss] Spawned %s (instance %d) on map %d" % [boss_name, new_instance_id, map_id])


# ---------------------------------------------------------------------------
# Feature 3: Achievement System
# ---------------------------------------------------------------------------

func _check_achievements(client, event: String, value: int) -> void:
	## Checks and awards newly unlocked achievements for the given event.
	## value=0 is a sentinel meaning read the current value from char_dict directly.
	var char_dict: Dictionary = client.char
	if not char_dict.has("achievement_progress"):
		char_dict["achievement_progress"] = {}
	var progress: Dictionary = char_dict["achievement_progress"]
	if not char_dict.has("achievements"):
		char_dict["achievements"] = []
	var unlocked: Array = char_dict["achievements"]

	var actual_value: int = value
	if value > 0:
		progress[event] = int(progress.get(event, 0)) + value
		actual_value = int(progress[event])
	else:
		match event:
			"gold":   actual_value = int(char_dict.get("gold", 0))
			"level":  actual_value = int(char_dict.get("level", 1))
			"maps":   actual_value = char_dict.get("visited_maps", []).size()
			_:        actual_value = int(progress.get(event, 0))
		progress[event] = actual_value

	for ach in ACHIEVEMENTS:
		var ach_d: Dictionary = ach as Dictionary
		if ach_d.get("event", "") != event:
			continue
		var ach_id: int = int(ach_d["id"])
		if ach_id in unlocked:
			continue
		if actual_value < int(ach_d["threshold"]):
			continue
		unlocked.append(ach_id)
		var ach_gold: int = int(ach_d.get("gold", 0))
		var ach_xp: int   = int(ach_d.get("xp", 0))
		if ach_gold > 0:
			char_dict["gold"] = int(char_dict.get("gold", 0)) + ach_gold
		if ach_xp > 0:
			char_dict["xp"] = int(char_dict.get("xp", 0)) + ach_xp
			_ServerCombatSCR.try_level_up(char_dict)
		var ach_w := NetProtocol.PacketWriter.new()
		ach_w.write_u16(ach_id)
		ach_w.write_str(ach_d.get("name", ""))
		ach_w.write_str(ach_d.get("desc", ""))
		ach_w.write_i32(ach_gold)
		ach_w.write_i32(ach_xp)
		client.send_auth(S_ACHIEVEMENT_UNLOCK, ach_w.get_bytes())
		_send_server_msg(client, "Achievement Unlocked: %s!" % ach_d.get("name", ""))
		_send_stats(client)

	char_dict["achievement_progress"] = progress
	char_dict["achievements"] = unlocked
	_update_title(client)


# ---------------------------------------------------------------------------
# Feature 5: Item Enchanting
# ---------------------------------------------------------------------------

func _on_enchant(client, item_slot: int, mat_slot: int) -> void:
	## Handles the C_ENCHANT message.
	var char_dict: Dictionary = client.char
	var inv: Array = char_dict.get("inventory", [])
	while inv.size() < 20:
		inv.append({})

	if item_slot < 0 or item_slot >= inv.size() or mat_slot < 0 or mat_slot >= inv.size():
		_send_server_msg(client, "Invalid slot.")
		return
	if item_slot == mat_slot:
		_send_server_msg(client, "Item and material cannot be the same slot.")
		return

	var item: Dictionary = inv[item_slot] as Dictionary
	var mat:  Dictionary = inv[mat_slot]  as Dictionary
	if item.is_empty():
		_send_server_msg(client, "No item in that slot.")
		return
	if mat.is_empty():
		_send_server_msg(client, "No material in that slot.")
		return

	var item_obj: Dictionary = GameData.get_object(int(item.get("obj_index", 0)))
	var item_obj_type: int = int(item_obj.get("obj_type", 0))
	const ENCHANTABLE_TYPES_LOCAL: Array = [1, 2, 3, 4, 5, 6, 7, 8]
	if item_obj_type not in ENCHANTABLE_TYPES_LOCAL:
		_send_server_msg(client, "This item cannot be enchanted.")
		return

	var mat_obj: Dictionary = GameData.get_object(int(mat.get("obj_index", 0)))
	var mat_obj_type: int = int(mat_obj.get("obj_type", 0))
	if mat_obj_type not in ENCHANT_MATERIAL_OBJ_TYPES:
		_send_server_msg(client, "That is not a valid enchanting material.")
		return

	var enchant_level: int = int(item.get("enchant_level", 0))
	if enchant_level >= 4:
		_send_server_msg(client, "This item is already at maximum enchantment (+4).")
		return

	var required: int = ENCHANT_MATERIAL_REQUIRED[enchant_level]
	var mat_amount: int = int(mat.get("amount", 0))
	if mat_amount < required:
		_send_server_msg(client,
				"You need %d %s but only have %d." % [required, mat_obj.get("name", "material"), mat_amount])
		return

	mat["amount"] = mat_amount - required
	if int(mat["amount"]) <= 0:
		inv[mat_slot] = {}
	char_dict["inventory"] = inv

	var success_roll := randf()
	var new_level: int = enchant_level
	var result_code: int = 0
	var result_msg: String = ""

	if success_roll < ENCHANT_SUCCESS_RATES[enchant_level]:
		new_level = enchant_level + 1
		item["enchant_level"] = new_level
		result_code = 1
		result_msg = "+%d enchantment applied!" % new_level
	elif success_roll < ENCHANT_SUCCESS_RATES[enchant_level] + ENCHANT_BREAK_CHANCE[enchant_level]:
		inv[item_slot] = {}
		char_dict["inventory"] = inv
		result_code = 2
		result_msg = "The item shattered!"
	else:
		result_code = 0
		result_msg = "The enchantment failed... try again."

	var ew := NetProtocol.PacketWriter.new()
	ew.write_u8(result_code)
	ew.write_u8(new_level)
	ew.write_str(result_msg)
	client.send_auth(S_ENCHANT_RESULT, ew.get_bytes())
	_send_inventory(client)

	if result_code == 1 and new_level >= 3:
		var prog: Dictionary = char_dict.get("achievement_progress", {})
		prog["enchant3"] = int(prog.get("enchant3", 0)) + 1
		char_dict["achievement_progress"] = prog
		_check_achievements(client, "enchant3", 0)

	_db.save_char(client.username, char_dict)


# ---------------------------------------------------------------------------
# Feature 6: Daily Login Streak
# ---------------------------------------------------------------------------

func _check_daily_login(client) -> void:
	var char_dict: Dictionary = client.char
	var today: String = Time.get_date_string_from_system()
	var last_login: String = char_dict.get("last_login_date", "")
	var streak: int = int(char_dict.get("login_streak", 0))

	if last_login == today:
		return

	var yesterday: String = _date_yesterday()
	if last_login != yesterday:
		streak = 0

	streak = mini(streak + 1, 7)
	char_dict["login_streak"] = streak
	char_dict["last_login_date"] = today

	var rewards: Array = [
		{"gold": 50,  "msg": "Day 1 login bonus: 50 gold!"},
		{"gold": 75,  "msg": "Day 2 streak: 75 gold!"},
		{"gold": 100, "msg": "Day 3 streak: 100 gold!"},
		{"gold": 125, "msg": "Day 4 streak: 125 gold!"},
		{"gold": 150, "msg": "Day 5 streak: 150 gold!"},
		{"gold": 200, "msg": "Day 6 streak: 200 gold!"},
		{"gold": 500, "msg": "7-DAY STREAK! 500 gold reward! Keep it up!"},
	]
	var reward: Dictionary = rewards[streak - 1] as Dictionary
	var gold_reward: int = int(reward["gold"])
	char_dict["gold"] = int(char_dict.get("gold", 0)) + gold_reward

	var w := NetProtocol.PacketWriter.new()
	w.write_u8(streak)
	w.write_i32(gold_reward)
	w.write_str(reward.get("msg", ""))
	client.send_auth(S_LOGIN_REWARD, w.get_bytes())
	_send_stats(client)
	_db.save_char(client.username, char_dict)


func _date_yesterday() -> String:
	var unix_now: int = int(Time.get_unix_time_from_system())
	var unix_yesterday: int = unix_now - 86400
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(unix_yesterday)
	return "%04d-%02d-%02d" % [int(dt.year), int(dt.month), int(dt.day)]


# ---------------------------------------------------------------------------
# Feature 7: World Events / Invasions
# ---------------------------------------------------------------------------

func _start_world_event() -> void:
	var town_idx: int = randi() % WORLD_EVENT_TOWNS.size()
	var map_id: int = int(WORLD_EVENT_TOWNS[town_idx])
	var wave: Array = WORLD_EVENT_NPC_WAVES.get(map_id, [])

	_world_event_npcs.clear()
	for npc_idx in wave:
		var safe_pos: Vector2i = _find_safe_spawn(map_id, randi_range(30, 70), randi_range(30, 70))
		_spawn_npc_at(map_id, int(npc_idx), safe_pos.x, safe_pos.y)
		var new_nid: int = _npc_counter - 1
		if _npcs.has(new_nid):
			_npcs[new_nid]["data"]["world_event_npc"] = true
		_world_event_npcs.append(new_nid)

	_world_event_active = true
	_world_event_map    = map_id
	_world_event_end_at = Time.get_ticks_msec() / 1000.0 + 300.0

	var start_w := NetProtocol.PacketWriter.new()
	start_w.write_str("Monster Invasion")
	start_w.write_str("Town " + str(map_id))
	_broadcast_all_connected(S_WORLD_EVENT_START, start_w.get_bytes())

	var announce_w := NetProtocol.PacketWriter.new()
	announce_w.write_str("INVASION! Monsters are attacking Town %d! Defend the town!" % map_id)
	_broadcast_all_connected(NetProtocol.MsgType.S_SERVER_MSG, announce_w.get_bytes())
	print("[WorldEvent] Invasion started on map %d with %d NPCs" % [map_id, _world_event_npcs.size()])


func _end_world_event(result_msg: String) -> void:
	for nid in _world_event_npcs:
		if _npcs.has(nid) and _npcs[nid]["ai_state"] != "dead":
			var ev_npc: Dictionary = _npcs[nid]
			ev_npc["ai_state"] = "dead"
			var rw := NetProtocol.PacketWriter.new()
			rw.write_i32(nid)
			_broadcast_map(ev_npc["map_id"], NetProtocol.MsgType.S_REMOVE_CHAR, rw.get_bytes())

	var end_w := NetProtocol.PacketWriter.new()
	end_w.write_str("Monster Invasion")
	end_w.write_str(result_msg)
	_broadcast_all_connected(S_WORLD_EVENT_END, end_w.get_bytes())

	var msg_w := NetProtocol.PacketWriter.new()
	msg_w.write_str(result_msg)
	_broadcast_all_connected(NetProtocol.MsgType.S_SERVER_MSG, msg_w.get_bytes())

	_world_event_active = false
	_world_event_npcs.clear()
	print("[WorldEvent] Event ended: %s" % result_msg)


# ---------------------------------------------------------------------------
# Feature 9: Leaderboards
# ---------------------------------------------------------------------------

func _update_leaderboard(category: String, name: String, score: int) -> void:
	if not _leaderboards.has(category):
		return
	var board: Array = _leaderboards[category]
	var found: bool = false
	for entry in board:
		var ed: Dictionary = entry as Dictionary
		if ed.get("name", "") == name:
			if score > int(ed.get("score", 0)):
				ed["score"] = score
			found = true
			break
	if not found:
		board.append({"name": name, "score": score})
	board.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	if board.size() > 10:
		board.resize(10)


func _on_leaderboard_request(client, type: int) -> void:
	var categories: Array = ["kills", "crafts", "level", "fishing"]
	if type < 0 or type >= categories.size():
		return
	var cat: String = categories[type] as String
	var board: Array = _leaderboards.get(cat, [])
	var lw := NetProtocol.PacketWriter.new()
	lw.write_u8(type)
	lw.write_u8(mini(board.size(), 255))
	for entry in board:
		var ed: Dictionary = entry as Dictionary
		lw.write_str(ed.get("name", "?"))
		lw.write_i32(int(ed.get("score", 0)))
	client.send_auth(S_LEADERBOARD_DATA, lw.get_bytes())


# ---------------------------------------------------------------------------
# Feature 10: Fishing Tournament
# ---------------------------------------------------------------------------

func _start_fishing_tourney() -> void:
	_tourney_active = true
	_tourney_scores.clear()
	_tourney_end_at = Time.get_ticks_msec() / 1000.0 + TOURNEY_DURATION

	var tw := NetProtocol.PacketWriter.new()
	tw.write_i32(int(TOURNEY_DURATION))
	tw.write_str("Grand Fishing Trophy + %d gold!" % int(TOURNEY_PRIZES[0]))
	_broadcast_all_connected(S_TOURNEY_START, tw.get_bytes())

	var aw := NetProtocol.PacketWriter.new()
	aw.write_str("FISHING TOURNAMENT STARTED! Best catch in 10 minutes wins %d gold!" % int(TOURNEY_PRIZES[0]))
	_broadcast_all_connected(NetProtocol.MsgType.S_SERVER_MSG, aw.get_bytes())
	print("[Tourney] Fishing tournament started.")


func _broadcast_tourney_scores() -> void:
	var scores_list: Array = []
	for pid in _tourney_scores:
		var entry: Dictionary = _tourney_scores[pid] as Dictionary
		scores_list.append({"name": entry.get("name", "?"), "score": int(entry.get("best_catch", 0))})
	scores_list.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	var top_n: int = mini(5, scores_list.size())
	var sw := NetProtocol.PacketWriter.new()
	sw.write_u8(top_n)
	for i in top_n:
		var e: Dictionary = scores_list[i] as Dictionary
		sw.write_str(e.get("name", "?"))
		sw.write_i32(int(e.get("score", 0)))
	_broadcast_all_connected(S_TOURNEY_SCORES, sw.get_bytes())


func _end_fishing_tourney() -> void:
	_tourney_active = false
	var scores_list: Array = []
	for pid in _tourney_scores:
		var entry: Dictionary = _tourney_scores[pid] as Dictionary
		scores_list.append({
			"pid": pid,
			"name": entry.get("name", "?"),
			"score": int(entry.get("best_catch", 0))
		})
	scores_list.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))

	var award_count: int = mini(3, scores_list.size())
	var ew := NetProtocol.PacketWriter.new()
	ew.write_u8(award_count)
	var winner_msgs: Array = []
	for i in award_count:
		var e: Dictionary = scores_list[i] as Dictionary
		var prize_gold: int = int(TOURNEY_PRIZES[i])
		ew.write_str(e.get("name", "?"))
		ew.write_i32(int(e.get("score", 0)))
		ew.write_i32(prize_gold)
		var winner_pid: int = int(e.get("pid", 0))
		if _clients.has(winner_pid):
			var wcl = _clients[winner_pid]
			if wcl.state == _ServerClientSCR.State.CONNECTED:
				wcl.char["gold"] = int(wcl.char.get("gold", 0)) + prize_gold
				_send_stats(wcl)
				_send_server_msg(wcl,
						"You placed %d in the Fishing Tournament! Prize: %d gold!" % [i + 1, prize_gold])
		var place_str: String = ["1st", "2nd", "3rd"][i]
		winner_msgs.append("%s: %s (%d)" % [place_str, e.get("name", "?"), int(e.get("score", 0))])
	_broadcast_all_connected(S_TOURNEY_END, ew.get_bytes())

	var result_text: String = "Fishing Tournament Over! " + (", ".join(winner_msgs) if not winner_msgs.is_empty() else "No participants.")
	var rw := NetProtocol.PacketWriter.new()
	rw.write_str(result_text)
	_broadcast_all_connected(NetProtocol.MsgType.S_SERVER_MSG, rw.get_bytes())
	_tourney_scores.clear()
	print("[Tourney] Fishing tournament ended.")



# ---------------------------------------------------------------------------
# Day / night cycle
# ---------------------------------------------------------------------------

func _broadcast_time_of_day() -> void:
	## Sends current in-game time to every connected client.
	var minutes: int = int(_time_of_day * 60.0) % 1440
	var w := NetProtocol.PacketWriter.new()
	w.write_u16(minutes)
	var bytes := w.get_bytes()
	for pid in _clients:
		var cl = _clients[pid]
		if cl.state == _ServerClientSCR.State.CONNECTED:
			cl.send_auth(S_TIME_OF_DAY, bytes)


func _get_night_sight_radius(char_dict: Dictionary) -> int:
	## Returns the player's base night-visibility radius in pixels.
	## 96px = 3 tiles. Inventory items with "night_sight" property add to this.
	var radius: int = 96
	var inv: Array = char_dict.get("inventory", [])
	for item in inv:
		var d: Dictionary = item as Dictionary
		if d.is_empty():
			continue
		var obj_idx: int = int(d.get("obj_index", 0))
		var obj: Dictionary = GameData.get_object(obj_idx)
		radius += int(obj.get("night_sight", 0)) * 32  # each night_sight point = 1 tile
	# Clamp: minimum 64px (2 tiles), maximum 320px (10 tiles = full screen width)
	return clampi(radius, 64, 320)


# ---------------------------------------------------------------------------
# Reputation helpers
# ---------------------------------------------------------------------------

func _get_rep(char_dict: Dictionary, faction: String) -> int:
	var rep: Dictionary = char_dict.get("reputation", {})
	return int(rep.get(faction, 0))


func _add_rep(client, faction: String, amount: int) -> void:
	## Award reputation with faction and penalise rivals.
	## amount can be negative (direct penalty, e.g. from a rival quest).
	var char_dict: Dictionary = client.char
	var rep: Dictionary = char_dict.get("reputation", {})
	var old_val: int = int(rep.get(faction, 0))
	var new_val: int = clampi(old_val + amount, REP_MIN, REP_MAX)
	rep[faction] = new_val
	char_dict["reputation"] = rep
	_send_rep_update(client, faction, new_val)
	# Notify on tier change
	var old_tier: int = _rep_tier(old_val)
	var new_tier: int = _rep_tier(new_val)
	if new_tier > old_tier:
		var tier_names: Array = ["Neutral", "Friendly", "Honored", "Revered"]
		_send_server_msg(client, "Your reputation with %s is now: %s!" % [
				faction.capitalize(), tier_names[new_tier]])
	elif new_tier < old_tier and amount > 0:
		# This shouldn't happen, but guard anyway
		pass
	# Apply rival penalty when gaining rep (not when losing)
	if amount > 0:
		var penalty: int = maxi(1, int(float(amount) * RIVAL_PENALTY))
		var rivals: Array = FACTION_RIVALS.get(faction, [])
		for rival in rivals:
			var rival_old: int = int(rep.get(rival, 0))
			var rival_new: int = clampi(rival_old - penalty, REP_MIN, REP_MAX)
			rep[rival] = rival_new
			char_dict["reputation"] = rep
			_send_rep_update(client, rival, rival_new)
			# Notify when crossing into a lower tier (or Hated)
			var r_old_tier: int = _rep_tier(rival_old)
			var r_new_tier: int = _rep_tier(rival_new)
			if r_new_tier < r_old_tier:
				var tier_names2: Array = ["Neutral", "Friendly", "Honored", "Revered"]
				_send_server_msg(client,
						"%s has grown to distrust you (rep: %s)." % [
						rival.capitalize(), tier_names2[r_new_tier]])
			elif rival_new <= 0 and rival_old > 0:
				_send_server_msg(client,
						"[%s] now views you with hostility. Their vendors will refuse to deal with you." % rival.capitalize())
	# Check Diplomat achievement (all 5 factions at Revered)
	if amount > 0:
		_check_diplomat(client)


func _rep_tier(rep: int) -> int:
	if rep >= REP_REVERED:  return 3
	if rep >= REP_HONORED:  return 2
	if rep >= REP_FRIENDLY: return 1
	return 0


func _send_rep_update(client, faction: String, value: int) -> void:
	## Sends a single rep stat to the client via S_SET_STATS.
	var sw := NetProtocol.PacketWriter.new()
	sw.write_u16(1)
	sw.write_str("rep_" + faction)
	sw.write_i32(value)
	client.send_auth(NetProtocol.MsgType.S_SET_STATS, sw.get_bytes())


func _build_vendor_items(npc_data: Dictionary, char_dict: Dictionary) -> Array:
	## Returns items this vendor shows to this player, based on rep tier.
	## Returns empty array if the player is hated (rep < 0) by this faction.
	var faction: String = npc_data.get("rep_faction", "")
	var rep: int = _get_rep(char_dict, faction) if not faction.is_empty() else REP_REVERED
	# Hated players (rep < 0) get nothing — vendor refuses service
	if rep < 0:
		return []
	var all_items: Array = []
	for idx in npc_data.get("items", []):
		all_items.append(int(idx))
	if rep >= REP_FRIENDLY:
		for idx in npc_data.get("items_friendly", []):
			all_items.append(int(idx))
	if rep >= REP_HONORED:
		for idx in npc_data.get("items_honored", []):
			all_items.append(int(idx))
	if rep >= REP_REVERED:
		for idx in npc_data.get("items_revered", []):
			all_items.append(int(idx))
	return all_items


func _check_diplomat(client) -> void:
	## Award the Diplomat achievement + title if all 5 factions are Revered.
	var char_dict: Dictionary = client.char
	var rep: Dictionary = char_dict.get("reputation", {})
	for faction in TOWN_FACTIONS.keys():
		if int(rep.get(faction, 0)) < REP_REVERED:
			return
	# All factions at Revered!
	var achieved: Array = char_dict.get("achievements", [])
	if 99 not in achieved:   # ID 99 reserved for Diplomat
		achieved.append(99)
		char_dict["achievements"] = achieved
		char_dict["gold"] = int(char_dict.get("gold", 0)) + 10000
		char_dict["title"] = "Diplomat"
		var aw := NetProtocol.PacketWriter.new()
		aw.write_u16(99)
		aw.write_str("Diplomat")
		aw.write_str("Achieved Revered status with all five factions.")
		aw.write_i32(10000)
		client.send_auth(S_ACHIEVEMENT_UNLOCK, aw.get_bytes())
		var tw := NetProtocol.PacketWriter.new()
		tw.write_i32(client.peer_id)
		tw.write_str("Diplomat")
		_broadcast_all_connected(S_TITLE_UPDATE, tw.get_bytes())
		_broadcast_all_connected(NetProtocol.MsgType.S_SERVER_MSG,
				_pack_str("The legendary Diplomat %s has befriended all factions of the known world!" % char_dict.get("name", "Someone")))
		_db.save_char(client.username, char_dict)


func _pack_str(s: String) -> PackedByteArray:
	var w := NetProtocol.PacketWriter.new()
	w.write_str(s)
	return w.get_bytes()


## Handle penance purchase: player spends gold to repair rep with a faction.
## Called from C_PENANCE message handler.
func _on_penance(client, faction: String) -> void:
	if not TOWN_FACTIONS.has(faction):
		return
	var char_dict: Dictionary = client.char
	var gold: int = int(char_dict.get("gold", 0))
	if gold < PENANCE_GOLD_COST:
		_send_server_msg(client, "You need %d gold for a penance offering. (You have %d)" % [
				PENANCE_GOLD_COST, gold])
		return
	var cur_rep: int = _get_rep(char_dict, faction)
	if cur_rep >= REP_MAX:
		_send_server_msg(client, "Your standing with %s cannot be improved further." % faction.capitalize())
		return
	char_dict["gold"] = gold - PENANCE_GOLD_COST
	_add_rep(client, faction, PENANCE_REP_GAIN)
	_send_stats(client)
	_send_server_msg(client, "You made a %d-gold penance offering to %s. Reputation +%d." % [
			PENANCE_GOLD_COST, faction.capitalize(), PENANCE_REP_GAIN])
	_db.save_char(client.username, char_dict)
