## Era Online - Shared Constants
## Mirrors VB6 constants from Declares.bas and game logic.
## Access as Constants.MAP_WIDTH etc., or load as a class.

# Map dimensions
const MAP_WIDTH  := 100
const MAP_HEIGHT := 100

# Tile size in pixels
const TILE_SIZE := 32

# Viewport size in tiles (original client was 20x11)
const VIEWPORT_TILES_X := 20
const VIEWPORT_TILES_Y := 11

# Character directions (matches VB6: NORTH=1, EAST=2, SOUTH=3, WEST=4)
enum Direction {
	NONE  = 0,
	NORTH = 1,
	EAST  = 2,
	SOUTH = 3,
	WEST  = 4,
}

# Direction -> Vector2i movement delta
const DIR_VECTORS: Dictionary = {
	Direction.NORTH: Vector2i( 0, -1),
	Direction.SOUTH: Vector2i( 0,  1),
	Direction.EAST:  Vector2i( 1,  0),
	Direction.WEST:  Vector2i(-1,  0),
}

# Direction -> Walk animation index (0-based, matches VB6 Walk1=N, Walk2=E, Walk3=S, Walk4=W)
const DIR_TO_ANIM_IDX: Dictionary = {
	Direction.NORTH: 0,
	Direction.EAST:  1,
	Direction.SOUTH: 2,
	Direction.WEST:  3,
}

# Slot limits
const MAX_INVENTORY_SLOTS := 20
const MAX_SPELL_SLOTS      := 50
const MAX_NPC_INVENTORY    := 40

# Progression
const MAX_LEVEL       := 50
const MAX_SKILL_LEVEL := 100

## XP required to advance from `lv` to `lv+1`.
## Exponential curve: each level costs ~9% more than the last.
##   Level  1→ 2: 100 XP    (a handful of actions)
##   Level 25→26: ~739 XP   (~1 minute)
##   Level 50→51: ~7,400 XP (~30 min session)
##   Level 90→91: ~269,000 XP (~days of grinding)
##   Level 99→100: ~573,000 XP (~weeks)
static func skill_xp_to_next(lv: int) -> int:
	if lv <= 0:   return 100
	if lv >= 100: return 0   # maxed — no further XP needed
	return roundi(100.0 * pow(1.09, lv - 1))

# Level-up EXP thresholds (LevelSkill in VB6 FileIO.bas)
const LEVEL_EXP: Array[int] = [
	0,      # unused (1-indexed)
	1000,   # L1->L2  (approximate, original used ELU/ELV system)
	2000, 3500, 5500, 8000, 11000, 14500, 19000, 24000, 30000,
	37000, 45000, 54000, 64000, 75000, 87000, 100000, 114000, 129000,
	145000, 162000, 180000, 199000, 219000, 240000, 262000, 285000, 309000,
	334000, 360000, 387000, 415000, 444000, 474000, 505000, 537000, 570000,
	604000, 639000, 675000, 712000, 750000, 789000, 829000, 870000, 912000,
	955000, 999000, 1044000,
]

# Timing (seconds)
const ATTACK_COOLDOWN    := 4.0
const NPC_ATTACK_COOLDOWN:= 4.0
const CRIMINAL_TIMER     := 60.0
const MEDITATE_INTERVAL  := 10.0
const EAT_DRINK_INTERVAL := 15.0
const CAMPFIRE_INTERVAL  := 10.0
const RAIN_CHECK_INTERVAL:= 30.0

# Object types (ObjType field)
enum ObjType {
	NONE         = 0,
	ARMOR        = 1,
	WEAPON       = 2,
	SHIELD_ARMOR = 3,
	FURNITURE    = 4,
	LETTER       = 5,
	FOOD         = 6,
	DRINK        = 7,
	MONEY        = 8,
	KEY          = 9,
	SPELL_SCROLL = 10,
	RING         = 11,
	HELMET       = 12,
	TOOL         = 13,
	RESOURCE     = 14,
	BOAT         = 15,
	ARROW        = 16,
	AXE_TOOL     = 17,
	FISHING_ROD  = 18,
	CONTAINER    = 19,
	CLOTHING     = 20,
	CORPSE       = 40,
}

## Magic system enums
enum SpellTargetType {
	SELF        = 0,   # targets caster only, no click needed
	SINGLE_ENEMY = 1,  # right-click enemy
	SINGLE_ALLY  = 2,  # right-click friendly player
	GROUND_AOE   = 3,  # right-click ground position
	SELF_AOE     = 4,  # instant cast centered on caster
}

enum StatusEffect {
	NONE       = 0,
	PARALYZED  = 1,  # cannot move or attack (4s default)
	FROZEN     = 2,  # cannot move or attack, -20% def (3s default)
	SLOWED     = 3,  # 50% movement speed (5s default)
}

# Reputation factions
const FACTIONS: Array[String] = [
	"noble", "under", "common", "bendarr",
	"veega", "zeendic", "griigo", "hyliios"
]

# Towns (index -> name, spawn map-x-y from Server.ini)
const TOWNS: Dictionary = {
	"Bernvillage": {"map": 1,   "x": 12, "y": 12},
	"CastleFall":  {"map": 81,  "x": 59, "y": 41},
	"AngelMoor":   {"map": 18,  "x": 30, "y": 30},
	"Gorth":       {"map": 140, "x": 35, "y": 42},
	"Jemhoo":      {"map": 115, "x": 10, "y": 10},
	"Denc":        {"map": 22,  "x": 13, "y": 13},
	"Valen":       {"map": 155, "x": 12, "y": 12},
	"ValenFall":   {"map": 169, "x": 12, "y": 12},
	"Molg":        {"map": 206, "x": 12, "y": 12},
	"Ug":          {"map": 189, "x": 12, "y": 12},
}

# --- Network message prefixes ---

# Server → Client
const MSG_SET_USER_INDEX  := "SUI"
const MSG_SET_CHAR_INDEX  := "SUC"
const MSG_CHANGE_MAP      := "SCM"
const MSG_MAP_NAME        := "SMN"
const MSG_SET_SCREEN_POS  := "SSP"
const MSG_USER_POSITION   := "SUP"
const MSG_MAKE_CHARACTER  := "MAC"
const MSG_ERASE_CHARACTER := "ERC"
const MSG_MOVE_CHARACTER  := "MOC"
const MSG_CHANGE_CHARACTER:= "CHC"
const MSG_MAKE_OBJECT     := "MOB"
const MSG_ERASE_OBJECT    := "EOB"
const MSG_SET_STATS       := "SST"
const MSG_PLAY_SOUND      := "PLW"
const MSG_CHAT            := "@"
const MSG_DIALOG          := "!"
const MSG_TENT            := "TEN"
const MSG_CHANGE_NPC      := "CNC"

# Client → Server
const CMSG_WALK           := "WAL"
const CMSG_ATTACK         := "ATK"
const CMSG_CHAT           := "SAY"
const CMSG_PICKUP         := "PIC"
const CMSG_DROP           := "DRP"
const CMSG_USE_ITEM       := "USE"
const CMSG_EQUIP          := "EQP"
const CMSG_CAST_SPELL     := "CST"
const CMSG_GM_HELP        := "GMH"
const CMSG_LOGIN          := "LOG"
const CMSG_CREATE_CHAR    := "CRC"
const CMSG_SELECT_CHAR    := "SLC"
