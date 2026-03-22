class_name WorldMap
extends Node2D
## WorldMap - Core tile map renderer and character movement system.
## Mirrors VB6 Graphics.bas RenderScreen() and General.bas movement logic.
##
## Rendering passes (matches VB6 order):
##   Pass 1: Layer 1 - opaque ground tiles (no transparency, no centering)
##   Pass 2: Layer 2 (transparent, centered), Map Objects, Layer 3 (rain only),
##            Characters (head, body, shield, weapon in that order)
##
## Movement: delta-based smooth camera.
##   cam_tile     = logical player tile (1..100)
##   _cam_target  = world pixel target (cam_tile * TILE)
##   _cam_pixel   = smooth float position sliding toward _cam_target at 240px/s
##   Camera2D.position = _cam_pixel each frame

const TILE            := 32       # World-space pixels per tile
const VIEW_W          := 20       # Viewport width in tiles
const VIEW_H          := 11       # Viewport height in tiles
const MOVE_PX_PER_SEC := 240.0    # 8px * 30fps — matches original VB6 speed

## Cardinal exit trigger zones — matches VB6 DoTileEvents() conditions.
## North: cam_tile.y < EXIT_N  →  spawn at SPAWN_N on destination map
## South: cam_tile.y > EXIT_S  →  spawn at SPAWN_S
## West:  cam_tile.x < EXIT_W  →  spawn at SPAWN_W
## East:  cam_tile.x > EXIT_E  →  spawn at SPAWN_E
const EXIT_N  := 7;   const SPAWN_N := 94
const EXIT_S  := 94;  const SPAWN_S := 7
const EXIT_W  := 9;   const SPAWN_W := 91
const EXIT_E  := 92;  const SPAWN_E := 10
## Preload neighbor map tiles this many tiles from the exit edge.
const NEIGHBOR_PRELOAD := 12

@onready var _camera: Camera2D = $Camera2D

## Player's current logical tile position (center of view).
var cam_tile: Vector2i = Vector2i(10, 10)
## Smooth camera world-pixel position (updated each frame toward _cam_target).
var _cam_pixel: Vector2 = Vector2.ZERO
## Camera destination in world pixels (cam_tile * TILE after each step).
var _cam_target: Vector2 = Vector2.ZERO

var cur_map_id: int = 3
## Sparse tile dictionary: "y,x" -> {layers, blocked, obj, ...}
var _tiles: Dictionary = {}
## Characters: char_index -> CharData
var _chars: Dictionary = {}
## Local player's char index (0 = player)
var _player_idx: int = 0
## Map-spawned NPCs: instance_id -> CharData (populated from tile npc_index at load time)
var _map_npcs: Dictionary = {}
## Extra NPC metadata for offline-mode vendors: npc_id → {npc_type, items, name}
var _map_npc_meta: Dictionary = {}
## Dropped ground items on the current map: id → {obj_index, amount, x, y}
var _ground_items: Dictionary = {}

var raining: bool = false
var tex_cache: TextureCache

var _anim_acc:      float = 0.0
var _tile_anim_tick: int  = 0   # global tick counter for tile GRH animation

## Footstep counter — incremented each tile step; AudioManager rotates variants.
var _step_counter: int = 0

var _hud_ui: Node = null
var _inventory_ui: Node = null
var _chat_ui:   Node = null
var _minimap:   Node = null
var _skills_ui: Node = null
var _spellbook_ui: Node = null
var _spell_hotbar_ui: Node = null
var _character_panel: Node = null
var _context_menu: ContextMenuUI = null
var _skill_progress_ui: Node = null
var _pause_menu: PauseMenuUI = null
var _death_screen: DeathScreenUI = null
# Bank UI
var _bank_ui: BankUI = null
# Trade UI
var _trade_ui: TradeUI = null
# Quest UI
var _quest_ui: QuestUI = null
var _quest_dialog_ui: QuestDialogUI = null
## Respawn destination held while death screen is showing; applied on player confirm.
var _pending_respawn: Dictionary = {}
var _level_up_ui: Node = null

## Day/night lighting
var _time_of_day:     float = 8.0     # in-game hours 0-24, set by server
var _canvas_mod:      CanvasModulate = null
var _player_light:    PointLight2D   = null
var _light_tex:       ImageTexture   = null  # generated radial gradient

# Addiction-loop UIs
var _achievement_ui: Node = null
var _leaderboard_ui: Node = null
var _bounty_ui: Node = null
var _event_ui:  Node = null
var _enchanting_ui: Node = null

## World-space damage floaters drawn via _draw() using draw_string().
## Each entry: {text, wx, wy, alpha, color, timer}
var _world_floaters: Array = []

## Corpse visuals drawn at death tile, auto-despawn after CORPSE_DURATION seconds.
## Each entry: {grh_index, x, y, timer}
const CORPSE_DURATION: float = 30.0
var _corpses: Array = []

## Spell visual effects. Each entry is a Dictionary:
##   projectile: {type="proj",  from, to, timer, max_timer, color}
##   aoe ring:   {type="aoe",   center, timer, max_timer, max_r, color}
##   flash:      {type="flash", center, timer, max_timer, color}
##   chain:      {type="chain", points, timer, max_timer, color}
var _spell_effects: Array = []

## NPC id of the last shop we requested, so _on_shop_list can forward it.
var _last_shop_npc_id: int = 0

## Quest indicators: npc_instance_id (int) -> "!" or "?" string
var _quest_indicators: Dictionary = {}

## Training dummy (local combat test target, target_id -1 in CombatSystem)
var _dummy_tile: Vector2i = Vector2i.ZERO
var _dummy_char: CharData = null

## Seconds remaining for the player attack animation flash
var _attack_anim_timer: float = 0.0

## AOE aim mode: spell_id > 0 means we're waiting for a right-click ground target
var _aoe_aim_spell: int = 0       # GROUND_AOE aim: left/right-click ground to fire
var _pending_cast_spell: int = 0  # SINGLE_ENEMY aim: left-click NPC to fire
var _pending_ability: int = 0     # Ranged ability aim: left-click NPC to fire

## Neighbor map tiles for seamless border rendering: direction → tiles dict.
var _neighbor_tiles: Dictionary = {}
## Neighbor map IDs currently loaded: direction → map_id.
var _neighbor_ids: Dictionary = {}

## ---------------------------------------------------------------------------
## Sound constants (VB6 snd{N}.wav numbering — see server/game_server.gd)
## ---------------------------------------------------------------------------
## Footstep sound — VB6 used SOUND_BUMP (1) for wall bumps, but there is no
## dedicated footstep in the original; we re-use the closest ambient clink.
## snd1 = BUMP, snd34 = SWORDSWING.  Footstep is intentionally silent (0)
## by default — replace with a WAV number once a suitable sound is added.
const SND_FOOTSTEP : int = 0   # 0 = disabled; set to a valid snd number to enable
const SND_UI_CLICK : int = 58  # snd58 = CLICK (used for inventory/UI opens in VB6)


## Per-character animation state (mirrors VB6 Char type).
class CharData:
	var active: bool = true
	var heading: int = 3        # SOUTH (VB6: NORTH=1 EAST=2 SOUTH=3 WEST=4)
	var tile_pos: Vector2i
	var move_offset: Vector2 = Vector2.ZERO  # Float pixels for smooth NPC slide
	var moving: bool = false
	var attacking: bool = false   # weapon-only swing, body stays static
	var body_idx: int = 1
	## Base body index before any armor/clothing override.
	## Preserved so that unequipping armor restores the original body sprite.
	var base_body_idx: int = 1
	var head_idx: int = 1
	var weapon_idx: int = 0
	var shield_idx: int = 0
	var hp: int = 0
	var max_hp: int = 0
	var body_anims: Array = []    # 4 x GrhAnimator [N, E, S, W]
	var weapon_anims: Array = []  # 4 x GrhAnimator
	var shield_anims: Array = []  # 4 x GrhAnimator
	var char_name: String = ""


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex_cache = TextureCache.new()
	_camera.zoom = Vector2(2.0, 2.0)

	# Wire Network signals → WorldMap handlers
	Network.on_world_state.connect(_on_net_world_state)
	Network.on_set_char.connect(_on_net_set_char)
	Network.on_move_char.connect(_on_net_move_char)
	Network.on_remove_char.connect(_on_net_remove_char)
	Network.on_map_change.connect(_on_net_map_change)
	Network.on_play_sound.connect(_on_net_play_sound)
	Network.on_chat.connect(_on_net_chat)
	Network.on_kicked.connect(_on_net_kicked)
	Network.on_damage.connect(_on_net_damage)
	Network.shop_list_received.connect(_on_shop_list)
	Network.on_ability_shop.connect(_on_ability_shop_received)
	Network.rain_changed.connect(_on_rain_changed)
	Network.on_ground_item_add.connect(_on_ground_item_add)
	Network.on_ground_item_remove.connect(_on_ground_item_remove)
	Network.on_corpse.connect(_on_net_corpse)
	Network.on_spell_cast.connect(_on_spell_cast_fx)
	Network.on_spell_hit.connect(_on_spell_hit_fx)
	Network.on_spell_chain.connect(_on_spell_chain_fx)
	Network.on_projectile.connect(_on_net_projectile)

	# HUD (always visible)
	_hud_ui = preload("res://scripts/ui/hud_ui.gd").new()
	add_child(_hud_ui)

	# Inventory (toggle with I)
	_inventory_ui = preload("res://scripts/ui/inventory_ui.gd").new()
	add_child(_inventory_ui)
	_inventory_ui.enchant_requested.connect(_on_enchant_requested)

	# Chat box (layer 8, below HUD)
	_chat_ui = preload("res://scripts/ui/chat_ui.gd").new()
	add_child(_chat_ui)

	# Minimap (layer 9, top-right, collapsible) — must be ready before _load_map
	_minimap = preload("res://scripts/ui/minimap_ui.gd").new()
	add_child(_minimap)
	_minimap.set_world(self)

	# Load the map — UI nodes must exist first so update_map fires correctly.
	if Network.state == Network.State.DISCONNECTED:
		# Offline / training dummy mode
		PlayerState.seed_offline_debug()
		_load_map(cur_map_id)
	elif Network.state == Network.State.CONNECTED and \
			not Network.last_world_state.is_empty():
		# World scene loaded after char select; server already sent S_WORLD_STATE.
		var ws := Network.last_world_state
		_load_map_at(ws["map_id"], Vector2i(ws["x"], ws["y"]))

	# Skills panel (layer 9, legacy — still toggled with K for power users)
	_skills_ui = preload("res://scripts/ui/skills_ui.gd").new()
	add_child(_skills_ui)

	# Spellbook (layer 9, legacy — still toggled with B for power users)
	_spellbook_ui = preload("res://scripts/ui/spellbook_ui.gd").new()
	add_child(_spellbook_ui)

	# Spell hotbar (legacy visual hidden; kept only for spell shop panel)
	_spell_hotbar_ui = preload("res://scripts/ui/spell_hotbar_ui.gd").new()
	add_child(_spell_hotbar_ui)
	Network.on_spell_shop.connect(_on_spell_shop)

	# Unified character panel (layer 15, C key)
	_character_panel = preload("res://scripts/ui/character_panel_ui.gd").new()
	add_child(_character_panel)

	# Wire unified HUD hotbar → slot routing
	if _hud_ui != null:
		(_hud_ui as HudUI).slot_activated.connect(_on_hotbar_slot_activated)

	# Right-click context menu
	_context_menu = ContextMenuUI.new()
	add_child(_context_menu)
	_context_menu.skill_requested.connect(_on_context_skill)
	_context_menu.walk_requested.connect(_on_context_walk)
	_context_menu.examine_requested.connect(_on_context_examine)
	_context_menu.pickup_requested.connect(_on_context_pickup)
	_context_menu.spell_cast_requested.connect(_on_context_spell_cast)
	_context_menu.trade_requested.connect(_on_context_trade)

	# Skill progress bar (layer 11 — above HUD)
	_skill_progress_ui = preload("res://scripts/ui/skill_progress_ui.gd").new()
	add_child(_skill_progress_ui)
	Network.on_skill_progress.connect(_on_skill_progress)

	# Death screen (layer 19 — below pause menu)
	_death_screen = DeathScreenUI.new()
	add_child(_death_screen)
	_death_screen.respawn_confirmed.connect(_on_death_respawn_confirmed)
	Network.on_death.connect(_on_net_death)
	Network.disconnected_from_server.connect(_on_disconnected)

	# Level-up fanfare (layer 18 — above HUD, below death/pause)
	_level_up_ui = preload("res://scripts/ui/level_up_ui.gd").new()
	add_child(_level_up_ui)
	Network.on_xp_gain.connect(_on_net_xp_gain)
	Network.on_level_up.connect(_on_net_level_up)

	# Pause / ESC menu (layer 20 — topmost)
	_pause_menu = PauseMenuUI.new()
	add_child(_pause_menu)
	_pause_menu.resume_requested.connect(func() -> void: pass)
	_pause_menu.quit_to_menu_requested.connect(_on_quit_to_menu)

	# Bank UI
	_bank_ui = preload("res://scripts/ui/bank_ui.gd").new()
	add_child(_bank_ui)

	# Trade UI
	_trade_ui = preload("res://scripts/ui/trade_ui.gd").new()
	add_child(_trade_ui)

	# Quest journal (layer 6, collapsible, Q key)
	_quest_ui = preload("res://scripts/ui/quest_ui.gd").new()
	add_child(_quest_ui)

	# Quest offer/turn-in dialog (layer 12, modal)
	_quest_dialog_ui = preload("res://scripts/ui/quest_dialog_ui.gd").new()
	add_child(_quest_dialog_ui)
	_quest_dialog_ui.accepted.connect(_on_quest_dialog_accepted)
	_quest_dialog_ui.turned_in.connect(_on_quest_dialog_turnin)

	# Achievement UI (A key)
	_achievement_ui = preload("res://scripts/ui/achievement_ui.gd").new()
	add_child(_achievement_ui)

	# Leaderboard UI (L key)
	_leaderboard_ui = preload("res://scripts/ui/leaderboard_ui.gd").new()
	add_child(_leaderboard_ui)

	# Bounty tracker (no panel — state only)
	_bounty_ui = preload("res://scripts/ui/bounty_ui.gd").new()
	add_child(_bounty_ui)

	# Event/tournament/login reward banners
	_event_ui = preload("res://scripts/ui/event_ui.gd").new()
	add_child(_event_ui)

	# Enchanting UI (opened from inventory right-click)
	_enchanting_ui = preload("res://scripts/ui/enchanting_ui.gd").new()
	add_child(_enchanting_ui)

	# Day/night lighting — CanvasModulate tints the whole scene
	_canvas_mod = CanvasModulate.new()
	_canvas_mod.color = Color.WHITE
	add_child(_canvas_mod)

	# Player point light — visible at night, radius driven by gear/skill
	_light_tex = _make_light_texture(256)
	_player_light = PointLight2D.new()
	_player_light.texture = _light_tex
	_player_light.texture_scale = 1.0
	_player_light.energy = 1.5
	_player_light.shadow_enabled = false
	_player_light.visible = false
	add_child(_player_light)

	# Quest context-menu signal
	_context_menu.talk_requested.connect(_on_context_talk)

	# Quest network signals
	Network.on_quest_offer.connect(_on_net_quest_offer)
	Network.on_quest_update.connect(_on_net_quest_update)
	Network.on_quest_complete.connect(_on_net_quest_complete)
	Network.on_quest_indicators.connect(_on_quest_indicators)
	Network.on_title_update.connect(_on_net_title_update)
	Network.on_time_of_day.connect(_on_net_time_of_day)
	Network.on_rare_drop.connect(_on_net_rare_drop)

	# Rebuild player visuals when equipment changes
	PlayerState.equipment_changed.connect(_on_equipment_changed)

	# Brief weapon animation when a skill fires
	CombatSystem.skill_used.connect(_on_skill_used)


func load_map(map_id: int) -> void:
	_load_map(map_id)


## Load map and place player at the map's default start position.
func _load_map(map_id: int) -> void:
	var map := GameData.get_map(map_id)
	if map.is_empty():
		push_error("[WorldMap] Map %d not found - run tools/run_pipeline.py first" % map_id)
		return
	var sp: Dictionary = map.get("start_pos", {"x": 10, "y": 10})
	_load_map_at(map_id, Vector2i(sp.get("x", 10), sp.get("y", 10)))


## Load map and place player at a specific tile (used for exits and direct calls).
func _load_map_at(map_id: int, spawn: Vector2i) -> void:
	var map := GameData.get_map(map_id)
	if map.is_empty():
		push_error("[WorldMap] Map %d not found" % map_id)
		return

	# Preserve current player appearance before clearing
	var prev_player := _chars.get(_player_idx, null) as CharData
	var prev_body   := prev_player.body_idx   if prev_player != null else 1
	var prev_head   := prev_player.head_idx   if prev_player != null else 1
	var prev_wpn    := prev_player.weapon_idx if prev_player != null else 0
	var prev_shd    := prev_player.shield_idx if prev_player != null else 0
	var prev_head_v := prev_player.heading    if prev_player != null else 3

	cur_map_id         = map_id
	_attack_anim_timer = 0.0
	_tiles     = map.get("tiles", {})
	cam_tile   = _safe_spawn(spawn, _tiles)
	_cam_target = Vector2(cam_tile * TILE)
	_cam_pixel  = _cam_target        # snap camera instantly
	if is_inside_tree():
		_camera.position = _cam_pixel  # sync Camera2D immediately
	_world_floaters.clear()
	_spell_effects.clear()
	_neighbor_tiles.clear()
	_neighbor_ids.clear()
	_chars.clear()
	_ground_items.clear()
	_corpses.clear()

	# Player placeholder — preserves appearance; overwritten by _on_net_set_char in online mode.
	_chars[_player_idx] = _make_char(prev_body, prev_head, prev_wpn, prev_shd, cam_tile, prev_head_v)

	if Network.state != Network.State.CONNECTED:
		# Offline / debug mode only — online NPCs come from server via S_SET_CHAR.
		_spawn_map_npcs()
		_spawn_training_dummy(spawn)
	else:
		_map_npcs.clear()  # Ensure no stale local NPCs bleed into online mode.

	# Play map music (music field is e.g. "3-1" — take the first number)
	var music_str: String = map.get("music", "0")
	var music_num := int(music_str.split("-")[0])
	if music_num > 0:
		AudioManager.play_music(music_num)

	_update_neighbors()

	# Update minimap terrain image for new map
	if _minimap != null:
		var map_name: String = map.get("name", "")
		_minimap.update_map(_tiles, map_name)

	print("[WorldMap] Map %d loaded: %d tiles, %d NPCs, spawn %s" % [
		map_id, _tiles.size(), _map_npcs.size(), cam_tile])


## Find the nearest walkable tile at or near the preferred spawn.
## Searches outward in rings so water/blocked spawns don't strand the player.
func _safe_spawn(preferred: Vector2i, tiles: Dictionary) -> Vector2i:
	if _spawn_tile_ok(preferred, tiles):
		return preferred
	for radius in range(1, 8):
		for ddx in range(-radius, radius + 1):
			for ddy in range(-radius, radius + 1):
				if abs(ddx) != radius and abs(ddy) != radius:
					continue  # Only perimeter of this ring
				var t: Vector2i = preferred + Vector2i(ddx, ddy)
				if _spawn_tile_ok(t, tiles):
					return t
	push_warning("[WorldMap] No walkable spawn near %s" % str(preferred))
	return preferred


func _spawn_tile_ok(t: Vector2i, tiles: Dictionary) -> bool:
	return t.x >= 1 and t.x <= 100 and t.y >= 1 and t.y <= 100 \
			and tiles.get("%d,%d" % [t.y, t.x], {}).get("blocked", 0) == 0


## Load or unload adjacent map tile data for seamless border rendering.
## Called after each map load and each tile step.
func _update_neighbors() -> void:
	var md := GameData.get_map(cur_map_id)
	# [direction, exit_key, distance_from_that_edge]
	var checks := [
		["north", "north_exit", cam_tile.y],
		["south", "south_exit", 101 - cam_tile.y],
		["west",  "west_exit",  cam_tile.x],
		["east",  "east_exit",  101 - cam_tile.x],
	]
	for entry in checks:
		var dir: String  = entry[0]
		var key: String  = entry[1]
		var dist: int    = entry[2]
		var exit_id: int = md.get(key, 0)
		if exit_id > 1 and dist <= NEIGHBOR_PRELOAD:
			if _neighbor_ids.get(dir, 0) != exit_id:
				var nm := GameData.get_map(exit_id)
				if not nm.is_empty():
					_neighbor_tiles[dir] = nm.get("tiles", {})
					_neighbor_ids[dir]   = exit_id
		else:
			_neighbor_tiles.erase(dir)
			_neighbor_ids.erase(dir)


## Populate _map_npcs from tile npc_index values on the current map.
func _spawn_map_npcs() -> void:
	_map_npcs.clear()
	_map_npc_meta.clear()
	var npc_id := 0
	for tile_key in _tiles:
		var tile: Dictionary = _tiles[tile_key]
		var npc_idx: int = tile.get("npc_index", 0)
		if npc_idx <= 0:
			continue
		var npc_data := GameData.get_npc(npc_idx)
		if npc_data.is_empty():
			continue
		var parts := str(tile_key).split(",")
		var ty := int(parts[0])
		var tx := int(parts[1])
		var c := _make_char(
			npc_data.get("body", 1),
			npc_data.get("head", 1),
			npc_data.get("weapon_anim", 0),
			npc_data.get("shield_anim", 0),
			Vector2i(tx, ty),
			npc_data.get("heading", 3)
		)
		c.char_name = npc_data.get("name", "")
		_map_npcs[npc_id] = c
		# Store vendor metadata for offline shop interaction
		var is_hostile: bool = npc_data.get("hostile", 0) != 0
		var attackable: bool = npc_data.get("attackable", 0) != 0
		var inventory: Array = npc_data.get("inventory", [])
		if (not is_hostile) and (not attackable) and inventory.size() >= 5:
			var shop_items: Array = []
			for inv_entry in inventory:
				var oi := int(inv_entry.get("obj_index", 0))
				if oi > 0:
					shop_items.append(oi)
			_map_npc_meta[npc_id] = {
				"npc_type": 2,
				"items": shop_items,
				"name": npc_data.get("name", ""),
			}
		npc_id += 1
	# Hardcoded vendors for specific maps (mirrors server's _spawn_hardcoded_npcs)
	_spawn_offline_vendors(npc_id)


## Spawn hardcoded vendors for offline mode (mirrors server's _spawn_hardcoded_npcs).
## Supports {"npc_index": N, "x": X, "y": Y} to load body/head/items from NPC.dat,
## or a fully-specified dict for custom NPCs.
func _spawn_offline_vendors(start_id: int) -> void:
	var pos_defs: Array = []
	match cur_map_id:
		1:
			pos_defs = [
				{"npc_index": 93, "x": 55, "y": 15},
				{"npc_index": 31, "x": 65, "y": 12},
			]
		3:
			pos_defs = [
				{"body": 22, "head": 13, "x": 14, "y": 9, "heading": 3,
				 "name": "Merchant Tim",
				 "items": [6, 19, 20, 21, 22, 8, 306, 7, 80, 185, 178, 153,
						   216, 244, 212, 57, 58, 59, 46, 43, 41]},
				{"body": 5, "head": 8, "x": 19, "y": 14, "heading": 3,
				 "name": "Sylvara the Arcanist", "npc_type": 3, "items": []},
				{"npc_index": 11, "x": 30, "y": 12},
				{"npc_index": 12, "x": 38, "y": 12},
				{"npc_index": 55, "x": 48, "y": 12},
				{"npc_index": 48, "x": 28, "y": 20},
				{"npc_index": 93, "x": 40, "y": 20},
				{"npc_index": 31, "x": 52, "y": 20},
			]
		18:
			pos_defs = [
				{"npc_index": 11, "x": 35, "y": 45},
				{"npc_index": 48, "x": 47, "y": 45},
				{"npc_index": 93, "x": 58, "y": 45},
				{"npc_index": 31, "x": 40, "y": 62},
			]
		80:
			pos_defs = [
				{"npc_index": 11, "x": 35, "y": 40},
				{"npc_index": 12, "x": 52, "y": 35},
				{"npc_index": 48, "x": 62, "y": 35},
				{"npc_index": 93, "x": 42, "y": 58},
				{"npc_index": 31, "x": 55, "y": 58},
			]
		115:
			pos_defs = [
				{"npc_index": 55, "x": 55, "y": 50},
				{"npc_index": 48, "x": 50, "y": 30},
				{"npc_index": 31, "x": 30, "y": 75},
				{"npc_index": 93, "x": 45, "y": 40},
			]
		140:
			pos_defs = [
				{"npc_index": 55, "x": 68, "y": 42},
				{"npc_index": 12, "x": 50, "y": 25},
				{"npc_index": 48, "x": 25, "y": 18},
				{"npc_index": 93, "x": 40, "y": 42},
				{"npc_index": 31, "x": 20, "y": 42},
			]
		142:
			pos_defs = [
				{"npc_index": 11, "x": 35, "y": 35},
				{"npc_index": 12, "x": 45, "y": 50},
				{"npc_index": 55, "x": 60, "y": 50},
				{"npc_index": 48, "x": 70, "y": 30},
				{"npc_index": 93, "x": 35, "y": 60},
				{"npc_index": 31, "x": 50, "y": 60},
			]

	var npc_id := start_id
	for d in pos_defs:
		var body: int
		var head: int
		var heading: int = 3
		var name_str: String
		var shop_items: Array = []
		var ntype: int = 0
		var npc_idx: int = d.get("npc_index", 0)

		if npc_idx > 0:
			var npc_data := GameData.get_npc(npc_idx)
			if npc_data.is_empty():
				continue
			body    = npc_data.get("body", 1)
			head    = npc_data.get("head", 1)
			heading = int(npc_data.get("heading", 3))
			if heading <= 0:
				heading = 3
			name_str = npc_data.get("name", "")
			var is_hostile: bool = npc_data.get("hostile", 0) != 0
			var attackable: bool = npc_data.get("attackable", 0) != 0
			var inventory: Array = npc_data.get("inventory", [])
			if (not is_hostile) and (not attackable) and inventory.size() >= 5:
				ntype = 2
				for inv_entry in inventory:
					var oi := int(inv_entry.get("obj_index", 0))
					if oi > 0:
						shop_items.append(oi)
		else:
			body     = d.get("body", 1)
			head     = d.get("head", 1)
			heading  = d.get("heading", 3)
			name_str = d.get("name", "")
			shop_items = d.get("items", [])
			ntype    = d.get("npc_type", 2)

		var c := _make_char(body, head, 0, 0, Vector2i(d["x"], d["y"]), heading)
		c.char_name = name_str
		_map_npcs[npc_id] = c
		_map_npc_meta[npc_id] = {
			"npc_type": ntype,
			"items":    shop_items,
			"name":     name_str,
		}
		npc_id += 1


## Place a training dummy near the spawn point for offline combat testing.
func _spawn_training_dummy(spawn: Vector2i) -> void:
	_dummy_char = null
	# Try offsets in order until we find a walkable tile
	var offsets: Array[Vector2i] = [Vector2i(3, 0), Vector2i(-3, 0), Vector2i(0, 3),
			Vector2i(0, -3), Vector2i(2, 0), Vector2i(0, 2)]
	for off in offsets:
		var t := spawn + off
		if t.x >= 1 and t.x <= 100 and t.y >= 1 and t.y <= 100 \
				and _walkable(t):
			_dummy_tile = t
			_dummy_char = _make_char(1, 1, 0, 0, _dummy_tile, 3)
			CombatSystem.reset_dummy()   # ensure fresh HP on each map load
			_dummy_char.active = CombatSystem.dummy_alive
			return


# ---------------------------------------------------------------------------
# Character factory
# ---------------------------------------------------------------------------

func _make_char(body: int, head: int, weapon: int, shield: int,
		tile: Vector2i, heading: int, hp: int = 0, max_hp: int = 0) -> CharData:
	var c := CharData.new()
	c.body_idx      = body
	c.base_body_idx = body  # Preserve for armor unequip restoration
	c.head_idx      = head
	c.weapon_idx    = weapon
	c.shield_idx    = shield
	c.tile_pos      = tile
	c.heading       = heading
	c.hp            = hp
	c.max_hp        = max_hp
	_build_anims(c)
	return c


func _build_anims(c: CharData) -> void:
	c.body_anims.clear()
	c.weapon_anims.clear()
	c.shield_anims.clear()

	var bw: Array = GameData.get_body(c.body_idx).get("walk", [0, 0, 0, 0])
	var ww: Array = GameData.get_weapon_anim(c.weapon_idx).get("walk", [0, 0, 0, 0])
	var sw: Array = GameData.get_shield_anim(c.shield_idx).get("walk", [0, 0, 0, 0])

	for i in 4:
		var ba := GrhAnimator.new()
		ba.init(bw[i] if i < bw.size() else 0)
		var wa := GrhAnimator.new()
		wa.init(ww[i] if i < ww.size() else 0)
		var sa := GrhAnimator.new()
		sa.init(sw[i] if i < sw.size() else 0)
		c.body_anims.append(ba)
		c.weapon_anims.append(wa)
		c.shield_anims.append(sa)


# ---------------------------------------------------------------------------
# Public API (called by Network.gd in Phase 3+)
# ---------------------------------------------------------------------------

## Add or update a character received from the server.
func set_char(c_idx: int, body: int, head: int, weapon: int, shield: int,
		tile: Vector2i, heading: int, name_str: String = "", hp: int = 0, max_hp: int = 0) -> void:
	var c := _make_char(body, head, weapon, shield, tile, heading, hp, max_hp)
	c.char_name = name_str
	_chars[c_idx] = c
	# Store combat classification so targeting can skip service/vendor NPCs.
	if c_idx >= 10001 and not name_str.is_empty():
		var npc_type := 1  # default: combat
		for k in GameData.npcs:
			var nd: Dictionary = GameData.npcs[k]
			if nd.get("name", "") == name_str:
				var h: bool = nd.get("hostile", 0) != 0
				var a: bool = nd.get("attackable", 0) != 0
				if (not h) and (not a):
					npc_type = 0  # service NPC — not a combat target
				break
		_map_npc_meta[c_idx] = {"npc_type": npc_type, "name": name_str, "items": []}


## Remove a character.
func remove_char(c_idx: int) -> void:
	_chars.erase(c_idx)


## Smoothly move a character to a new tile.
func move_char_to(c_idx: int, new_tile: Vector2i) -> void:
	if not _chars.has(c_idx):
		return
	var c: CharData = _chars[c_idx]
	var d := new_tile - c.tile_pos
	if d == Vector2i.ZERO:
		return
	c.move_offset = Vector2(-d.x * TILE, -d.y * TILE)
	c.moving      = true
	c.tile_pos    = new_tile
	if   d.x > 0: c.heading = 2   # EAST
	elif d.x < 0: c.heading = 4   # WEST
	elif d.y < 0: c.heading = 1   # NORTH
	else:         c.heading = 3   # SOUTH
	var di := _hidx(c.heading)
	for anims in [c.body_anims, c.weapon_anims, c.shield_anims]:
		if di < anims.size():
			(anims[di] as GrhAnimator).started = true


# ---------------------------------------------------------------------------
# Per-frame update
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not GameData.is_loaded:
		return

	_handle_input()
	_advance_movement(delta)
	_update_lighting()

	# Drive player attack animation — weapon/shield swing only, body stays static.
	# Runs BEFORE _tick_anims so flags are set before animators are ticked this frame.
	if _attack_anim_timer > 0.0:
		_attack_anim_timer -= delta
		var p: CharData = _chars.get(_player_idx, null)
		if p != null:
			if not p.moving:
				# Standing still: weapon swings in reverse once (last→first frame),
				# which shows the strike coming IN rather than pulling away.
				if not p.attacking:
					p.attacking = true
					var di := _hidx(p.heading)
					for anims in [p.weapon_anims, p.shield_anims]:
						if di < anims.size():
							var ga := anims[di] as GrhAnimator
							var entry := GameData.get_grh(ga.grh_index)
							ga.frame_counter = entry.get("num_frames", 8)
							ga.play_once     = true
							ga.play_reverse  = true
							ga.started       = true
			if _attack_anim_timer <= 0.0:
				p.attacking = false

	# Tick walk animations + tile animations at ~30fps (original VB6 rate)
	_anim_acc += delta
	var ticks := int(_anim_acc * 30.0)
	if ticks > 0:
		_anim_acc -= float(ticks) / 30.0
		_tile_anim_tick += ticks
		for _i in ticks:
			_tick_anims()

	# Sync training dummy visibility to CombatSystem state
	if _dummy_char != null:
		_dummy_char.active = CombatSystem.dummy_alive

	# Tick world-space damage floaters
	if _world_floaters.size() > 0:
		for i in range(_world_floaters.size() - 1, -1, -1):
			var f: Dictionary = _world_floaters[i]
			f["timer"] -= delta
			f["wy"]    -= 24.0 * delta   # float upward in world space
			f["alpha"]  = clampf(f["timer"] / 0.8, 0.0, 1.0)
			if f["timer"] <= 0.0:
				_world_floaters.remove_at(i)
		queue_redraw()

	# Tick corpse despawn timers
	if _corpses.size() > 0:
		for i in range(_corpses.size() - 1, -1, -1):
			_corpses[i]["timer"] -= delta
			if _corpses[i]["timer"] <= 0.0:
				_corpses.remove_at(i)
		queue_redraw()

	# Tick spell visual effects
	if _spell_effects.size() > 0:
		for i in range(_spell_effects.size() - 1, -1, -1):
			_spell_effects[i]["timer"] -= delta
			if _spell_effects[i]["timer"] <= 0.0:
				_spell_effects.remove_at(i)
		queue_redraw()

	_camera.position = _cam_pixel
	queue_redraw()


func _hidx(heading: int) -> int:
	## Convert VB6 heading (1-4) to array index (0-3).
	return clampi(heading - 1, 0, 3)


func _tick_anims() -> void:
	for c_idx in _chars:
		var c: CharData = _chars[c_idx]
		var di := _hidx(c.heading)
		if c.moving:
			# Walking: animate body + weapon + shield
			for anims in [c.body_anims, c.weapon_anims, c.shield_anims]:
				if di < anims.size():
					(anims[di] as GrhAnimator).tick()
		elif c.attacking:
			# Swing: only weapon + shield; body stays on standing frame
			for anims in [c.weapon_anims, c.shield_anims]:
				if di < anims.size():
					(anims[di] as GrhAnimator).tick()
	for npc_id in _map_npcs:
		var c: CharData = _map_npcs[npc_id]
		if not c.moving:
			continue
		var di := _hidx(c.heading)
		for anims in [c.body_anims, c.weapon_anims, c.shield_anims]:
			if di < anims.size():
				(anims[di] as GrhAnimator).tick()


## Slide camera and NPC offsets toward their targets at MOVE_PX_PER_SEC.
func _advance_movement(delta: float) -> void:
	var step := MOVE_PX_PER_SEC * delta

	# Camera: detect the transition "was moving → just arrived".
	# cam_was_moving is evaluated after _handle_input may have set a new _cam_target,
	# so a newly-started move won't spuriously trigger _finish_player_move this frame.
	var cam_was_moving := (_cam_pixel != _cam_target)
	_cam_pixel = _cam_pixel.move_toward(_cam_target, step)
	if cam_was_moving and _cam_pixel == _cam_target:
		_finish_player_move()

	# NPC characters: slide move_offset toward zero, stop walk anim on arrival.
	for c_idx in _chars:
		if c_idx == _player_idx:
			continue
		var c: CharData = _chars[c_idx]
		if not c.moving:
			continue
		c.move_offset = c.move_offset.move_toward(Vector2.ZERO, step)
		if c.move_offset == Vector2.ZERO:
			c.moving = false
			_stop_walk_anims(c)
	for npc_id in _map_npcs:
		var c: CharData = _map_npcs[npc_id]
		if not c.moving:
			continue
		c.move_offset = c.move_offset.move_toward(Vector2.ZERO, step)
		if c.move_offset == Vector2.ZERO:
			c.moving = false
			_stop_walk_anims(c)


func _finish_player_move() -> void:
	var p: CharData = _chars.get(_player_idx, null)
	if p == null:
		return
	p.moving = false
	# Do NOT reset animation here — let it run continuously while walking.
	# _handle_input will stop and reset it when the player releases all keys.

	_step_counter += 1
	if _step_counter % 3 == 0:
		AudioManager.play_footstep()

	# Cardinal exits (VB6: y<7=North, y>94=South, x<9=West, x>92=East).
	var md       := GameData.get_map(cur_map_id)
	var dest_map := 0
	var dest_x   := cam_tile.x
	var dest_y   := cam_tile.y
	if cam_tile.y < EXIT_N:
		dest_map = md.get("north_exit", 0); dest_y = SPAWN_N
	elif cam_tile.y > EXIT_S:
		dest_map = md.get("south_exit", 0); dest_y = SPAWN_S
	elif cam_tile.x < EXIT_W:
		dest_map = md.get("west_exit",  0); dest_x = SPAWN_W
	elif cam_tile.x > EXIT_E:
		dest_map = md.get("east_exit",  0); dest_x = SPAWN_E
	if dest_map > 1:
		print("[WorldMap] Cardinal exit → map %d @ (%d,%d)" % [dest_map, dest_x, dest_y])
		_load_map_at(dest_map, Vector2i(dest_x, dest_y))
		return

	# Check tile-based exit on the tile we just arrived at.
	var tile_data: Dictionary = _tiles.get("%d,%d" % [cam_tile.y, cam_tile.x], {})
	var exit_d: Dictionary    = tile_data.get("exit", {})
	if not exit_d.is_empty():
		dest_map = exit_d.get("map", 0)
		dest_x   = exit_d.get("x", cam_tile.x)
		dest_y   = exit_d.get("y", cam_tile.y)
		if dest_map > 1:
			print("[WorldMap] Tile exit → map %d @ (%d,%d)" % [dest_map, dest_x, dest_y])
			_load_map_at(dest_map, Vector2i(dest_x, dest_y))
			return

	# No exit — update neighbors for seamless rendering.
	_update_neighbors()


# ---------------------------------------------------------------------------
# Input (local player only — Phase 2 demo)
# ---------------------------------------------------------------------------

## Mouse input: left-click fires spell in aim mode; right-click shows context menu.
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if _chat_ui != null and _chat_ui.is_input_open():
		return

	# Compute world tile from mouse position (shared by all branches)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var zoom: float = _camera.zoom.x if _camera != null else 2.0
	var world_offset: Vector2 = (mb.position - viewport_size * 0.5) / zoom
	var world_px: Vector2 = _cam_pixel + world_offset
	var tile := Vector2i(int(round(world_px.x / TILE)), int(round(world_px.y / TILE)))
	tile = tile.clamp(Vector2i(1, 1), Vector2i(100, 100))

	# --- Left-click handling ---
	if mb.button_index == MOUSE_BUTTON_LEFT:
		# GROUND_AOE aim mode: left-click fires at clicked tile
		if _aoe_aim_spell > 0:
			var sid := _aoe_aim_spell
			_aoe_aim_spell = 0
			_do_cast_spell(sid, 0, tile.x, tile.y)
			get_viewport().set_input_as_handled()
			return

		# SINGLE_ENEMY pending cast: left-click on nearest NPC within range
		if _pending_cast_spell > 0:
			var sid := _pending_cast_spell
			_pending_cast_spell = 0
			var best_id := -1
			var best_dist := 999
			for char_id in _chars:
				if char_id == _player_idx:
					continue
				var c: CharData = _chars[char_id]
				if not c.active:
					continue
				# Skip service/vendor NPCs — only npc_type==1 (combat) are valid targets
				var cmeta: Dictionary = _map_npc_meta.get(char_id, {})
				if cmeta.get("npc_type", 1) != 1:
					continue
				var d := maxi(abs(c.tile_pos.x - tile.x), abs(c.tile_pos.y - tile.y))
				if d < best_dist:
					best_dist = d
					best_id = char_id
			for npc_id in _map_npcs:
				var c: CharData = _map_npcs[npc_id]
				if not c.active:
					continue
				var cmeta: Dictionary = _map_npc_meta.get(npc_id, {})
				if cmeta.get("npc_type", 1) != 1:
					continue
				var d := maxi(abs(c.tile_pos.x - tile.x), abs(c.tile_pos.y - tile.y))
				if d < best_dist:
					best_dist = d
					best_id = npc_id
			# Include training dummy (offline target id = -1)
			if _dummy_char != null and _dummy_char.active:
				var d := maxi(abs(_dummy_tile.x - tile.x), abs(_dummy_tile.y - tile.y))
				if d < best_dist:
					best_id = -1
			if best_id != _player_idx:
				_do_cast_spell(sid, best_id, 0, 0)
			get_viewport().set_input_as_handled()
			return

		# RANGED ABILITY aim: left-click fires at nearest NPC to clicked tile
		if _pending_ability > 0:
			var sid := _pending_ability
			_pending_ability = 0
			if _hud_ui != null:
				(_hud_ui as HudUI).hide_aim_mode()
			var best_id := -1
			var best_dist := 999
			for char_id in _chars:
				if char_id == _player_idx:
					continue
				var c: CharData = _chars[char_id]
				if not c.active:
					continue
				var d := maxi(abs(c.tile_pos.x - tile.x), abs(c.tile_pos.y - tile.y))
				if d < best_dist:
					best_dist = d
					best_id = char_id
			for npc_id in _map_npcs:
				var c: CharData = _map_npcs[npc_id]
				if not c.active:
					continue
				var d := maxi(abs(c.tile_pos.x - tile.x), abs(c.tile_pos.y - tile.y))
				if d < best_dist:
					best_dist = d
					best_id = npc_id
			if _dummy_char != null and _dummy_char.active:
				var d := maxi(abs(_dummy_tile.x - tile.x), abs(_dummy_tile.y - tile.y))
				if d < best_dist:
					best_id = -1
			if best_id != _player_idx:
				if Network.state == Network.State.CONNECTED:
					CombatSystem.use_skill(sid, best_id)
				else:
					CombatSystem.use_skill(sid, best_id)
			get_viewport().set_input_as_handled()
			return

		return   # Normal left-click — not consumed here

	# --- Right-click handling ---
	if mb.button_index != MOUSE_BUTTON_RIGHT:
		return

	# Right-click also fires GROUND_AOE aim mode
	if _aoe_aim_spell > 0:
		var sid := _aoe_aim_spell
		_aoe_aim_spell = 0
		_do_cast_spell(sid, 0, tile.x, tile.y)
		get_viewport().set_input_as_handled()
		return

	# Cancel SINGLE_ENEMY pending cast on right-click without firing
	if _pending_cast_spell > 0:
		_pending_cast_spell = 0
		if _spell_hotbar_ui != null and _spell_hotbar_ui.has_method("hide_aim_mode"):
			_spell_hotbar_ui.hide_aim_mode()
		get_viewport().set_input_as_handled()
		return

	# Cancel ranged ability aim on right-click
	if _pending_ability > 0:
		_pending_ability = 0
		if _hud_ui != null:
			(_hud_ui as HudUI).hide_aim_mode()
		get_viewport().set_input_as_handled()
		return

	# Gather context: NPCs within 2 tiles of the clicked tile.
	var npc_ids: Array = []
	var npc_names: Dictionary = {}
	for char_id in _chars:
		if char_id == _player_idx:
			continue
		var c: CharData = _chars[char_id]
		if not c.active:
			continue
		var dist := maxi(abs(c.tile_pos.x - tile.x), abs(c.tile_pos.y - tile.y))
		if dist <= 2:
			npc_ids.append(char_id)
			npc_names[char_id] = c.char_name if c.char_name != "" else "NPC"
	for npc_id in _map_npcs:
		var c: CharData = _map_npcs[npc_id]
		if not c.active:
			continue
		var dist := maxi(abs(c.tile_pos.x - tile.x), abs(c.tile_pos.y - tile.y))
		if dist <= 2:
			npc_ids.append(npc_id)
			npc_names[npc_id] = "NPC"

	# Check player inventory for tools and craftable blueprints.
	# obj_type: 48=pickaxe, 17=lumberjack axe, 16=fishing rod, 26=blacksmithing drawing
	var has_pickaxe := false
	var has_axe := false
	var has_fishing_rod := false
	var blueprint_label: String = ""   # non-empty = player has a usable blueprint
	for inv_slot in PlayerState.inventory:
		if (inv_slot as Dictionary).is_empty():
			continue
		var obj_data: Dictionary = GameData.get_object((inv_slot as Dictionary).get("obj_index", 0))
		if obj_data.is_empty():
			continue
		var obj_type: int = obj_data.get("obj_type", 0)
		if obj_type == 48:
			has_pickaxe = true
		if obj_type == 17:
			has_axe = true
		if obj_type == 16:
			has_fishing_rod = true
		elif obj_type == 26 and blueprint_label.is_empty():
			# Show the output item name (make_item) so it reads "Forge Dagger" etc.
			var out_idx: int = obj_data.get("make_item", 0)
			var out_name: String = GameData.get_object(out_idx).get("name", "") if out_idx > 0 else ""
			blueprint_label = out_name if not out_name.is_empty() else obj_data.get("name", "Item")

	# Check for dropped ground items at this tile.
	var ground_item: Dictionary = {}
	for gi_id in _ground_items:
		var gi: Dictionary = _ground_items[gi_id]
		if gi["x"] == tile.x and gi["y"] == tile.y:
			var obj_data: Dictionary = GameData.get_object(gi["obj_index"])
			ground_item = {"id": gi_id, "name": obj_data.get("name", "Item"), "index": gi["obj_index"]}
			break

	# Resource proximity checks — mirrors server _has_resource_near().
	# Server is authoritative; these just prevent showing useless menu options.
	var _pc: CharData = _chars.get(_player_idx, null)
	var player_tile := Vector2i(_pc.tile_pos) if _pc != null else tile

	# Fishing: only show when adjacent to water tile (grh 3500).
	if has_fishing_rod:
		var near_water := false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var td: Dictionary = _tiles.get(
					"%d,%d" % [player_tile.y + dy, player_tile.x + dx], {})
				var layers: Array = td.get("layers", [0])
				if layers.size() > 0 and (layers[0] as int) == 3500:
					near_water = true
					break
			if near_water:
				break
		if not near_water:
			has_fishing_rod = false

	# Mining: only show when an ore node (obj_type 32) is within 2 tiles.
	if has_pickaxe:
		var near_ore := false
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var td: Dictionary = _tiles.get(
					"%d,%d" % [player_tile.y + dy, player_tile.x + dx], {})
				var tobj: Dictionary = td.get("obj", {})
				if tobj.is_empty():
					continue
				var tobj_data: Dictionary = GameData.get_object(tobj.get("index", 0))
				if tobj_data.get("obj_type", 0) == 32:
					near_ore = true
					break
			if near_ore:
				break
		if not near_ore:
			has_pickaxe = false

	# Lumberjacking: only show when a wood node (obj_type 20) is within 2 tiles.
	if has_axe:
		var near_tree := false
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var td: Dictionary = _tiles.get(
					"%d,%d" % [player_tile.y + dy, player_tile.x + dx], {})
				var tobj: Dictionary = td.get("obj", {})
				if tobj.is_empty():
					continue
				var tobj_data: Dictionary = GameData.get_object(tobj.get("index", 0))
				if tobj_data.get("obj_type", 0) == 20:
					near_tree = true
					break
			if near_tree:
				break
		if not near_tree:
			has_axe = false

	# Spells are cast via the unified hotbar (aim mode), not the context menu.
	var target_spells: Array = []

	# Station crafting: scan tiles near the PLAYER for craft stations.
	# Options appear whenever the player is within range, regardless of what tile was clicked.
	# obj_type 50=Forge, 51=Anvil, 52=Cooking Stove, 21/34=campfire
	const STATION_RANGE_CLIENT := 4
	var near_forge := false
	var near_anvil := false
	var near_cook_station := false
	for dy2 in range(-STATION_RANGE_CLIENT, STATION_RANGE_CLIENT + 1):
		for dx2 in range(-STATION_RANGE_CLIENT, STATION_RANGE_CLIENT + 1):
			var std: Dictionary = _tiles.get(
					"%d,%d" % [player_tile.y + dy2, player_tile.x + dx2], {})
			var raw_idx = std.get("obj", {}).get("index", 0)
			if raw_idx == 0:
				continue
			var sobj_idx: int = int(raw_idx)
			var obj_data: Dictionary = GameData.get_object(sobj_idx)
			match int(obj_data.get("obj_type", 0)):
				50: near_forge = true
				51: near_anvil = true
				21, 34, 52: near_cook_station = true

	var smelt_option: bool = false      # "Smelt Ore" entry
	var forge_label: String = ""        # "Forge <item>" entry
	var cook_items: Array  = []         # [{name, raw_obj_index}] one entry per unique raw food type

	# Forge + Anvil both nearby — check inventory for smelting / smithing ingredients
	if near_forge and near_anvil:
		var has_ore := false
		var bs_blueprint_label: String = ""
		for inv_slot2 in PlayerState.inventory:
			var isd: Dictionary = inv_slot2 as Dictionary
			if isd.is_empty(): continue
			var iod: Dictionary = GameData.get_object(isd.get("obj_index", 0))
			match int(iod.get("obj_type", 0)):
				32: has_ore = true   # ore
				26:  # blacksmithing drawing
					if bs_blueprint_label.is_empty():
						var out_idx2: int = iod.get("make_item", 0)
						var out_name2: String = GameData.get_object(out_idx2).get("name", "") if out_idx2 > 0 else ""
						bs_blueprint_label = out_name2 if not out_name2.is_empty() else iod.get("name", "Item")
		if has_ore:
			smelt_option = true
		if not bs_blueprint_label.is_empty():
			forge_label = bs_blueprint_label

	# Cooking station nearby — check inventory for raw food
	if near_cook_station:
		var seen_raw: Dictionary = {}   # obj_index → true, deduplicate
		for inv_slot2 in PlayerState.inventory:
			var isd: Dictionary = inv_slot2 as Dictionary
			if isd.is_empty(): continue
			var iod: Dictionary = GameData.get_object(isd.get("obj_index", 0))
			var raw_idx2: int = isd.get("obj_index", 0)
			# obj_type 39 = raw fish/meat; obj_index 117 = raw meat
			if (int(iod.get("obj_type", 0)) == 39 or raw_idx2 == 117) \
					and not seen_raw.has(raw_idx2):
				seen_raw[raw_idx2] = true
				cook_items.append({
					"name": iod.get("name", "food"),
					"raw_obj_index": raw_idx2,
				})

	var context: Dictionary = {
		"tile":             tile,
		"npc_ids":          npc_ids,
		"npc_names":        npc_names,
		"local_char_id":    _player_idx,
		"has_pickaxe":      has_pickaxe,
		"has_axe":          has_axe,
		"has_fishing_rod":  has_fishing_rod,
		"blueprint_label":  blueprint_label,
		"ground_item":      ground_item,
		"target_spells":    target_spells,
		"smelt_option":     smelt_option,
		"forge_label":      forge_label,
		"cook_items":       cook_items,
	}
	if _context_menu != null:
		_context_menu.show_menu(mb.global_position, context)
	get_viewport().set_input_as_handled()


## Debug: F1-F9 jump to maps 1-9 directly (kept in _input for one-shot F-key handling).
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var fkeys := [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9]
	for i in fkeys.size():
		if event.keycode == fkeys[i]:
			_load_map(i + 1)
			return


## Interact with the nearest vendor NPC within 2 tiles (press E).
func _try_open_shop() -> void:
	var best_id:   int    = -1
	var best_dist: int    = 3   # exclusive upper bound (must be <= 2)

	# Scan offline map NPCs (both tile-based and hardcoded vendors)
	for npc_id in _map_npcs:
		var c: CharData = _map_npcs[npc_id]
		if not c.active:
			continue
		var dist := maxi(abs(cam_tile.x - c.tile_pos.x),
				abs(cam_tile.y - c.tile_pos.y))
		if dist < best_dist:
			best_dist = dist
			best_id   = npc_id

	# Also scan server-sent chars with char_id >= 10001 (NPC range)
	for char_id in _chars:
		if char_id < 10001:
			continue
		var c: CharData = _chars[char_id]
		if not c.active:
			continue
		var dist := maxi(abs(cam_tile.x - c.tile_pos.x),
				abs(cam_tile.y - c.tile_pos.y))
		if dist < best_dist:
			best_dist = dist
			best_id   = char_id

	if best_id < 0:
		return   # No NPC in range

	_last_shop_npc_id = best_id

	# Offline mode: open shop directly using cached vendor metadata
	if Network.state != Network.State.CONNECTED:
		var meta: Dictionary = _map_npc_meta.get(best_id, {})
		var npc_type: int = meta.get("npc_type", 0)
		var npc_name_lower: String = meta.get("name", "").to_lower()
		if npc_name_lower.contains("bank") or npc_name_lower.contains("banker"):
			_bank_ui.open(best_id)
		elif npc_type == 4:
			# Trainer NPC — build offline ability list from metadata
			var trainer_abilities: Array = meta.get("abilities", [])
			var offline_ab_list: Array = []
			for aid in trainer_abilities:
				var ab: Dictionary = GameData.get_ability(int(aid))
				if ab.is_empty():
					continue
				offline_ab_list.append({
					"id":            int(aid),
					"name":          ab.get("name", "?"),
					"gold_cost":     ab.get("gold_cost", 0),
					"req_level":     ab.get("req_level", 1),
					"req_skill_id":  ab.get("req_skill_id", 16),
					"req_skill_val": ab.get("req_skill_val", 0),
					"learned":       PlayerState.has_ability(int(aid)),
					"sta_cost":      ab.get("sta_cost", 0),
					"cooldown":      ab.get("cooldown", 0.0),
				})
			_on_ability_shop_received(offline_ab_list)
		elif npc_type == 2 and meta.get("items", []).size() > 0:
			_on_shop_list(meta.get("name", "Shop"), meta["items"])
		return

	# Online mode: check if this NPC is a banker
	var npc_char: CharData = null
	if _chars.has(best_id):
		npc_char = _chars[best_id]
	var npc_name_check: String = npc_char.char_name.to_lower() if npc_char != null else ""
	if npc_name_check.contains("bank") or npc_name_check.contains("banker"):
		_bank_ui.open(best_id)
		return

	Network.send_shop_open(best_id)


## Routes a unified hotbar slot activation to the appropriate action.
func _on_hotbar_slot_activated(slot_idx: int) -> void:
	if _chat_ui != null and _chat_ui.is_input_open():
		return
	var slot = PlayerState.get_unified_hotbar_slot(slot_idx)
	if slot == null:
		return
	var stype: String = slot.get("type", "")
	var sid:   int    = slot.get("id",   0)
	match stype:
		"ability":
			_try_skill(sid)
		"spell":
			_try_cast_unified_spell(sid)


## Cast a spell from the unified hotbar — routes based on target type.
func _try_cast_unified_spell(spell_id: int) -> void:
	var sp: Dictionary = GameData.get_spell(spell_id)
	if sp.is_empty():
		return
	if not PlayerState.is_spell_ready(spell_id):
		return
	var tt: int = sp.get("target_type", 0)
	match tt:
		0, 4:  # SELF / SELF_AOE
			_do_cast_spell(spell_id, -1, 0, 0)
		1, 2:  # SINGLE_ENEMY / SINGLE_ALLY
			_on_single_aim_requested(spell_id)
		3:     # GROUND_AOE
			_on_aoe_aim_requested(spell_id)


## Use a combat ability. Ranged abilities enter aim mode; melee auto-targets.
func _try_skill(skill_id: int) -> void:
	var ab: Dictionary = GameData.get_ability(skill_id)
	if ab.is_empty():
		return
	# Ranged abilities require explicit target selection (aim mode)
	if ab.get("req_skill_id", 0) == 28:
		_pending_ability = skill_id
		var aname: String = ab.get("name", "Ability")
		if _hud_ui != null:
			(_hud_ui as HudUI).show_aim_mode("🏹  CLICK TARGET: " + aname)
		return
	# Melee / physical — fire immediately
	if Network.state == Network.State.CONNECTED:
		# Find nearest attackable character within melee range (server validates range+type)
		var best_id := -1
		var best_dist := 999
		for char_id in _chars:
			if char_id == _player_idx:
				continue
			var c: CharData = _chars[char_id]
			if not c.active:
				continue
			var d := maxi(abs(c.tile_pos.x - cam_tile.x), abs(c.tile_pos.y - cam_tile.y))
			if d < best_dist:
				best_dist = d
				best_id = char_id
		if best_id >= 0:
			CombatSystem.use_skill(skill_id, best_id)
		return
	if _dummy_char == null or not _dummy_char.active:
		return
	var dist := maxi(abs(cam_tile.x - _dummy_tile.x), abs(cam_tile.y - _dummy_tile.y))
	if dist > 2:
		return
	CombatSystem.use_skill(skill_id, -1)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return

	# Don't process game hotkeys while the chat input is open.
	if _chat_ui != null and _chat_ui.is_input_open():
		return

	if key.physical_keycode == KEY_ESCAPE:
		# Cancel aim modes first; only open pause if nothing was cancelled.
		if _aoe_aim_spell != 0 or _pending_cast_spell != 0 or _pending_ability != 0:
			_aoe_aim_spell      = 0
			_pending_cast_spell = 0
			_pending_ability    = 0
			if _hud_ui != null:
				(_hud_ui as HudUI).hide_aim_mode()
			if _spell_hotbar_ui != null and _spell_hotbar_ui.has_method("hide_aim_mode"):
				_spell_hotbar_ui.hide_aim_mode()
			return
		# Toggle pause menu.
		if _pause_menu != null:
			if _pause_menu.is_open():
				_pause_menu.close()
			else:
				_pause_menu.open()
		return

	if event.is_action_pressed("ui_char"):
		# Unified character panel (C = Character)
		if _character_panel != null:
			(_character_panel as CharacterPanelUI).toggle()
			AudioManager.play_sound(SND_UI_CLICK)
	elif event.is_action_pressed("ui_inventory"):
		if _inventory_ui != null:
			_inventory_ui.toggle()
			AudioManager.play_sound(SND_UI_CLICK)
	elif event.is_action_pressed("ui_interact"):
		_try_open_shop()
	elif event.is_action_pressed("ui_pickup"):
		# Pick up the first ground item on the player's current tile
		if Network.state == Network.State.CONNECTED:
			for gi_id in _ground_items:
				var gi: Dictionary = _ground_items[gi_id]
				if gi["x"] == cam_tile.x and gi["y"] == cam_tile.y:
					Network.send_pickup(gi_id)
					break
	elif event.is_action_pressed("ui_leaderboard"):
		if _leaderboard_ui != null:
			_leaderboard_ui.toggle()
			AudioManager.play_sound(SND_UI_CLICK)


func _handle_input() -> void:
	# Block movement input while camera is still sliding to its target
	if _cam_pixel.distance_squared_to(_cam_target) > 1.0:
		return

	var dir := Vector2i.ZERO
	var heading := 0

	if Input.is_action_pressed("move_north"):
		dir = Vector2i(0, -1); heading = 1
	elif Input.is_action_pressed("move_south"):
		dir = Vector2i(0,  1); heading = 3
	elif Input.is_action_pressed("move_east"):
		dir = Vector2i( 1, 0); heading = 2
	elif Input.is_action_pressed("move_west"):
		dir = Vector2i(-1, 0); heading = 4

	var p: CharData = _chars.get(_player_idx, null)

	if dir == Vector2i.ZERO:
		if p != null and _attack_anim_timer <= 0.0:
			_stop_walk_anims(p)
		return

	var new_tile := cam_tile + dir
	if not _walkable(new_tile):
		if p != null:
			p.heading = heading
			if _attack_anim_timer <= 0.0:
				_stop_walk_anims(p)
		return

	cam_tile    = new_tile
	_cam_target = Vector2(cam_tile * TILE)

	# Notify server — runs alongside local prediction for responsiveness.
	if Network.state == Network.State.CONNECTED:
		Network.send_move(heading)

	if p == null:
		return

	var prev_heading := p.heading
	p.tile_pos = new_tile
	p.heading  = heading
	p.moving   = true

	# If direction changed, stop the old direction's anim so it doesn't keep
	# ticking invisibly, and reset the new direction's anim for a clean start.
	if heading != prev_heading:
		_stop_walk_anims(p)

	# Ensure the current direction's walk anim is running
	var di := _hidx(heading)
	for anims in [p.body_anims, p.weapon_anims, p.shield_anims]:
		if di < anims.size():
			(anims[di] as GrhAnimator).started = true


## Stop and reset walk animations for all four directions on a character.
func _stop_walk_anims(p: CharData) -> void:
	for anims in [p.body_anims, p.weapon_anims, p.shield_anims]:
		for a in anims:
			var ga := a as GrhAnimator
			ga.frame_counter = 1
			ga.started       = false
			ga.play_once     = false
			ga.play_reverse  = false


func _walkable(tile: Vector2i) -> bool:
	if tile.x < 1 or tile.x > 100 or tile.y < 1 or tile.y > 100:
		return false
	if _tiles.get("%d,%d" % [tile.y, tile.x], {}).get("blocked", 0) != 0:
		return false
	# Block movement into tiles occupied by any NPC (index != player)
	for idx in _chars:
		if idx == _player_idx:
			continue
		var c = _chars[idx]
		if c.tile_pos == tile:
			return false
	return true


# ---------------------------------------------------------------------------
# Rendering (_draw is called by queue_redraw each frame)
# ---------------------------------------------------------------------------

func _draw() -> void:
	# Black background — covers current map plus all four neighbor map areas.
	# VB6 cleared to black before each render; neighbor offsets are ±100*TILE,
	# so we need at least 300*TILE square to cover every reachable neighbor.
	draw_rect(Rect2(-100 * TILE, -100 * TILE, 300 * TILE, 300 * TILE), Color.BLACK)

	# Derive visible tile range from smooth camera pixel position
	var cx := int(_cam_pixel.x / TILE)
	var cy := int(_cam_pixel.y / TILE)

	# +margin covers the up-to-1-tile sub-pixel offset during movement
	var min_x := clampi(cx - 12, 1, 100)
	var max_x := clampi(cx + 12, 1, 100)
	var min_y := clampi(cy - 8,  1, 100)
	var max_y := clampi(cy + 8,  1, 100)

	# --- Pass 1: Layer 1 (opaque ground) — current map + neighbors ---
	# Neighbors drawn here so their ground appears under layer-2 of both maps.
	for ty in range(min_y, max_y + 1):
		for tx in range(min_x, max_x + 1):
			var t: Dictionary = _tiles.get("%d,%d" % [ty, tx], {})
			var layers: Array = t.get("layers", [])
			if layers.size() > 0 and layers[0] > 0:
				_draw_grh(layers[0], tx * TILE, ty * TILE, false)
	if _neighbor_tiles.has("north"):
		_draw_neighbor_layer1(_neighbor_tiles["north"], 0, -100 * TILE)
	if _neighbor_tiles.has("south"):
		_draw_neighbor_layer1(_neighbor_tiles["south"], 0,  100 * TILE)
	if _neighbor_tiles.has("west"):
		_draw_neighbor_layer1(_neighbor_tiles["west"],  -100 * TILE, 0)
	if _neighbor_tiles.has("east"):
		_draw_neighbor_layer1(_neighbor_tiles["east"],   100 * TILE, 0)

	# --- Pass 2: Transparent layers + objects + characters ---
	# Neighbor layer-2 drawn before current-map characters so characters at the
	# boundary edge appear on top of the adjacent map's decorations.
	if _neighbor_tiles.has("north"):
		_draw_neighbor_layer2(_neighbor_tiles["north"], 0, -100 * TILE)
	if _neighbor_tiles.has("south"):
		_draw_neighbor_layer2(_neighbor_tiles["south"], 0,  100 * TILE)
	if _neighbor_tiles.has("west"):
		_draw_neighbor_layer2(_neighbor_tiles["west"],  -100 * TILE, 0)
	if _neighbor_tiles.has("east"):
		_draw_neighbor_layer2(_neighbor_tiles["east"],   100 * TILE, 0)
	for ty in range(min_y, max_y + 1):
		for tx in range(min_x, max_x + 1):
			var t: Dictionary = _tiles.get("%d,%d" % [ty, tx], {})
			var layers: Array = t.get("layers", [])
			var wx := tx * TILE
			var wy := ty * TILE

			# Layer 2 (walls/objects above floor, transparent, centered)
			if layers.size() > 1 and layers[1] > 0:
				_draw_grh(layers[1], wx, wy, true)

			# Object on this tile (dropped items, furniture)
			var obj: Dictionary = t.get("obj", {})
			if not obj.is_empty():
				var obj_grh: int = GameData.get_object(obj.get("index", 0)).get("grh_index", 0)
				if obj_grh > 0:
					_draw_grh(obj_grh, wx, wy, true)

			# Layer 3: only rendered during rain
			if raining and layers.size() > 2 and layers[2] > 0:
				_draw_grh(layers[2], wx, wy, true)

			# Characters at this tile (head, body, shield, weapon)
			_draw_chars_at(Vector2i(tx, ty), wx, wy)

	# --- Ground items (world-space gold dot + name label) ---
	for gi_id in _ground_items:
		var gi: Dictionary = _ground_items[gi_id]
		var wx: int = gi["x"] * TILE
		var wy: int = gi["y"] * TILE
		# Only draw if on screen (using same visible range check as tile loop)
		if gi["x"] < min_x - 1 or gi["x"] > max_x + 1 or gi["y"] < min_y - 1 or gi["y"] > max_y + 1:
			continue
		# Gold dot at tile center
		draw_circle(Vector2(wx + 16, wy + 20), 4, Color(0.85, 0.68, 0.12, 0.90))
		# Item name below
		var obj_name: String = GameData.get_object(gi["obj_index"]).get("name", "?")
		var amt: int = gi.get("amount", 1)
		var label: String = obj_name if amt <= 1 else "%s x%d" % [obj_name, amt]
		draw_string(ThemeDB.fallback_font, Vector2(wx, wy + 30), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.95, 0.82, 0.40, 0.95))

	# --- Corpse visuals (lying body sprites, fade out near expiry) ---
	for corpse in _corpses:
		var corp_x: int = corpse["x"]
		var corp_y: int = corpse["y"]
		if corp_x < min_x - 1 or corp_x > max_x + 1 or corp_y < min_y - 1 or corp_y > max_y + 1:
			continue
		var alpha: float = clampf(corpse["timer"] / 3.0, 0.0, 1.0)
		var fd := GameData.get_grh_frame(corpse["grh_index"], 0)
		if fd.is_empty():
			continue
		var ctex := tex_cache.get_texture(fd.get("file_num", 0))
		if ctex == null:
			continue
		var cpw: int = fd.get("pixel_width", TILE)
		var cph: int = fd.get("pixel_height", TILE)
		var cdx := corp_x * TILE - cpw / 2 + 16
		var cdy := corp_y * TILE - cph + TILE
		draw_texture_rect_region(ctex,
			Rect2(float(cdx), float(cdy), float(cpw), float(cph)),
			Rect2(float(fd.get("sx", 0)), float(fd.get("sy", 0)), float(cpw), float(cph)),
			Color(1.0, 1.0, 1.0, alpha))

	# --- Damage floaters (world-space, drawn on top of all tile content) ---
	for f in _world_floaters:
		if f["alpha"] <= 0.0:
			continue
		var col: Color = f["color"]
		col.a = f["alpha"]
		draw_string(ThemeDB.fallback_font, Vector2(f["wx"], f["wy"]), f["text"],
				HORIZONTAL_ALIGNMENT_CENTER, -1, 14, col)

	# --- AOE aim mode cursor ---
	if _aoe_aim_spell > 0:
		var sp: Dictionary  = GameData.get_spell(_aoe_aim_spell)
		var radius: int     = sp.get("aoe_radius", 3)
		var col: Color      = _SPELL_COLORS.get(sp.get("effect_type", "aoe_burst"),
				Color(1.0, 0.5, 0.1))
		# Get mouse tile in world space
		var vp_sz: Vector2  = get_viewport().get_visible_rect().size
		var zm: float       = _camera.zoom.x if _camera != null else 2.0
		var mp: Vector2     = get_viewport().get_mouse_position()
		var wp: Vector2     = _cam_pixel + (mp - vp_sz * 0.5) / zm
		var mt: Vector2i    = Vector2i(int(round(wp.x / TILE)), int(round(wp.y / TILE)))
		var center: Vector2 = Vector2(mt.x * TILE + 16, mt.y * TILE + 16)
		var pulse: float    = 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.006)
		draw_arc(center, float(radius) * TILE + 8.0, 0.0, TAU, 32,
				Color(col.r, col.g, col.b, pulse), 2.5)
		draw_circle(center, 6.0, Color(col.r, col.g, col.b, pulse * 0.8))
		draw_string(ThemeDB.fallback_font,
				Vector2(center.x - 40, center.y - float(radius) * TILE - 16),
				sp.get("name", "Spell"), HORIZONTAL_ALIGNMENT_CENTER, 80, 11,
				Color(col.r, col.g, col.b, pulse))

	# --- Spell visual effects ---
	for fx in _spell_effects:
		var t: float    = fx["timer"]
		var mt: float   = fx["max_timer"]
		var frac: float = clampf(t / mt, 0.0, 1.0)   # 1.0→0.0 over lifetime
		var alpha: float = frac
		var c: Color    = fx["color"]
		match fx["type"]:
			"proj":
				# Bolt with trailing glow circles
				var pos: Vector2 = fx["from"].lerp(fx["to"], 1.0 - frac)
				for i in range(6):
					var trail_t: float = float(i) / 6.0
					var tp: Vector2 = fx["from"].lerp(pos, trail_t)
					var ta: float = alpha * (1.0 - trail_t) * 0.55
					draw_circle(tp, maxf(1.5, 4.0 - trail_t * 2.5), Color(c.r, c.g, c.b, ta))
				draw_circle(pos, 5.5, Color(c.r, c.g, c.b, alpha))
				draw_circle(pos, 3.5, Color(1.0, 1.0, 1.0, alpha * 0.9))
			"aoe_burst":
				var ctr: Vector2  = fx["center"]
				var max_r: float  = fx["max_r"]
				var r: float      = max_r * (1.0 - frac)
				var r2: float     = r * 0.60
				var r3: float     = max_r * (1.0 - frac * 0.5)
				# Three expanding rings
				draw_arc(ctr, r,  0.0, TAU, 64, Color(c.r, c.g, c.b, alpha),       3.0)
				draw_arc(ctr, r2, 0.0, TAU, 48, Color(c.r, c.g, c.b, alpha * 0.7), 2.0)
				draw_arc(ctr, r3, 0.0, TAU, 40, Color(c.r, c.g, c.b, alpha * 0.35),1.5)
				# Radiating spokes
				for i in range(10):
					var angle: float = (TAU * i) / 10.0
					var dir := Vector2(cos(angle), sin(angle))
					draw_line(ctr, ctr + dir * r, Color(c.r, c.g, c.b, alpha * 0.80), 2.0)
				# Bright center flash
				draw_circle(ctr, r * 0.15 + 4.0, Color(c.r, c.g, c.b, alpha * 0.6))
			"nova":
				var ctr: Vector2  = fx["center"]
				var max_r: float  = fx["max_r"]
				var r: float      = max_r * (1.0 - frac)
				var spike_n := 20
				# Jagged spike polygon
				var pts: PackedVector2Array = PackedVector2Array()
				for i in range(spike_n * 2):
					var angle: float = (TAU * i) / (spike_n * 2)
					var rad: float   = r * (1.18 if (i % 2) == 0 else 0.88)
					pts.append(ctr + Vector2(cos(angle), sin(angle)) * rad)
				draw_polygon(pts, PackedColorArray([Color(c.r, c.g, c.b, alpha * 0.28)]))
				draw_polyline(pts, Color(c.r, c.g, c.b, alpha), 1.8)
				pts.append(pts[0])
				# Smooth outer ring
				draw_arc(ctr, r, 0.0, TAU, 96, Color(c.r, c.g, c.b, alpha), 2.5)
				draw_arc(ctr, r * 0.55, 0.0, TAU, 64, Color(c.r, c.g, c.b, alpha * 0.6), 1.8)
			"chain":
				var chain_pts: Array = fx["points"]
				for pi in range(chain_pts.size() - 1):
					var p1: Vector2 = chain_pts[pi]
					var p2: Vector2 = chain_pts[pi + 1]
					var dir: Vector2 = (p2 - p1).normalized()
					var perp: Vector2 = Vector2(-dir.y, dir.x)
					# Zigzag midpoints
					var seg: PackedVector2Array = PackedVector2Array()
					seg.append(p1)
					for j in range(1, 4):
						var mid: Vector2 = p1.lerp(p2, float(j) / 4.0)
						mid += perp * ((randf() - 0.5) * 8.0)
						seg.append(mid)
					seg.append(p2)
					draw_polyline(seg, Color(c.r, c.g, c.b, alpha), 3.0)
					draw_polyline(seg, Color(1.0, 1.0, 1.0, alpha * 0.6), 1.5)
					# Branch
					if seg.size() > 2:
						var branch_end: Vector2 = seg[2] + Vector2(randf() - 0.5, randf() - 0.5).normalized() * 22.0
						draw_line(seg[2], branch_end, Color(c.r, c.g, c.b, alpha * 0.55), 1.5)
			"status_fx":
				var ctr: Vector2 = fx["center"]
				var spin: float  = Time.get_ticks_msec() * 0.004
				var pulse: float = 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.007)
				# Pulsing center glow
				draw_circle(ctr, 7.0 * pulse, Color(c.r, c.g, c.b, alpha * 0.9))
				# Three orbiting dots
				for i in range(3):
					var phase: float  = spin + (TAU * i) / 3.0
					var orb: Vector2  = ctr + Vector2(cos(phase), sin(phase)) * 36.0
					var op: float     = 0.75 + 0.25 * sin(spin * 2.0 + phase)
					draw_circle(orb, 4.5 * op, Color(c.r, c.g, c.b, alpha * op))
					draw_circle(orb, 2.5 * op, Color(1.0, 1.0, 1.0, alpha * op * 0.7))
				draw_arc(ctr, 36.0, 0.0, TAU, 32, Color(c.r, c.g, c.b, alpha * 0.35), 1.5)
			"heal_fx":
				var ctr: Vector2   = fx["center"]
				var age: float     = mt - t
				var part_n := 10
				for i in range(part_n):
					var spawn_t: float = (float(i) / part_n) * mt * 0.6
					var a2: float      = age - spawn_t
					if a2 < 0.0:
						continue
					var af: float  = clampf(a2 / (mt - spawn_t), 0.0, 1.0)
					var drift_x    = sin(a2 * 3.0 + i * 1.7) * 14.0
					var pp: Vector2 = ctr + Vector2(drift_x, -72.0 * af)
					var pa: float  = alpha * (1.0 - af) * 0.95
					draw_circle(pp, maxf(1.0, 5.5 * (1.0 - af * 0.5)), Color(c.r, c.g, c.b, pa))
					draw_circle(pp, maxf(1.0, 3.0 * (1.0 - af * 0.5)), Color(1.0, 1.0, 1.0, pa * 0.7))
				# Swirling center
				var spin2: float = Time.get_ticks_msec() * 0.005
				for i in range(4):
					var a3: float = spin2 + (TAU * i / 4.0)
					var sp: Vector2 = ctr + Vector2(cos(a3), sin(a3)) * 18.0
					draw_circle(sp, 3.2, Color(c.r, c.g, c.b, alpha * 0.7))
			"drain_fx":
				var part_n := 14
				for i in range(part_n):
					var phase: float = frac + float(i) / part_n
					if phase > 1.0: phase -= 1.0
					var pp: Vector2  = fx["from"].lerp(fx["to"], 1.0 - phase)
					var dev_ang: float = atan2(fx["to"].y - fx["from"].y, fx["to"].x - fx["from"].x) + PI * 0.5
					pp += Vector2(cos(dev_ang), sin(dev_ang)) * sin(phase * TAU) * 9.0
					var pa: float    = alpha * sin(phase * PI)
					draw_circle(pp, 4.0, Color(c.r, c.g, c.b, pa))
					draw_circle(pp, 2.5, Color(1.0, 0.8, 1.0, pa * 0.8))
			"push_fx":
				var ctr: Vector2    = fx["center"]
				var expand: float   = 110.0 * (1.0 - frac)
				for i in range(14):
					var angle: float = (TAU * i) / 14.0
					var dir := Vector2(cos(angle), sin(angle))
					var inner: Vector2 = ctr + dir * expand * 0.2
					var outer: Vector2 = ctr + dir * expand
					draw_line(inner, outer, Color(c.r, c.g, c.b, alpha), 2.5)
				draw_circle(ctr, 9.0, Color(c.r, c.g, c.b, alpha * 0.75))
				draw_arc(ctr, 9.0, 0.0, TAU, 18, Color(1.0, 1.0, 1.0, alpha), 2.0)
			"shimmer_fx":
				var ctr: Vector2 = fx["center"]
				var spin3: float = Time.get_ticks_msec() * 0.003
				for i in range(9):
					var angle: float = (TAU * i) / 9.0 + spin3
					var dist: float  = 22.0 + 16.0 * sin(float(i) * 1.3)
					var sp: Vector2  = ctr + Vector2(cos(angle), sin(angle)) * dist
					var tw: float    = abs(sin(spin3 * 2.0 + float(i)))
					draw_circle(sp, 3.5 * tw + 1.0, Color(c.r, c.g, c.b, alpha * tw))
					draw_circle(sp, (3.5 * tw + 1.0) * 0.5, Color(1.0, 1.0, 1.0, alpha * tw * 0.7))
				draw_circle(ctr, 6.0, Color(c.r, c.g, c.b, alpha * 0.6))
			"summon_fx":
				var ctr: Vector2 = fx["center"]
				var rot: float   = Time.get_ticks_msec() * 0.004 * (1.0 + (1.0 - frac) * 2.0)
				# Wavy concentric rings (3)
				for ring_i in range(3):
					var rr: float = 22.0 + ring_i * 18.0
					var ring_pts: PackedVector2Array = PackedVector2Array()
					for j in range(64):
						var ang: float = (TAU * j) / 64.0
						var wave: float = sin(ang * 3.0 + rot) * 3.5
						ring_pts.append(ctr + Vector2(cos(ang), sin(ang)) * (rr + wave))
					draw_polyline(ring_pts, Color(c.r, c.g, c.b, alpha * (1.0 - ring_i * 0.28)), 2.0)
				# Orbiting dots
				for i in range(10):
					var phase: float = rot * 0.7 + (TAU * i) / 10.0
					var orb: Vector2 = ctr + Vector2(cos(phase), sin(phase)) * 42.0
					var op: float    = 0.65 + 0.35 * sin(rot + phase)
					draw_circle(orb, 3.5 * op, Color(c.r, c.g, c.b, alpha * op))
					draw_circle(orb, 2.0 * op, Color(1.0, 1.0, 1.0, alpha * op * 0.6))
			"portal_fx":
				var ctr: Vector2   = fx["center"]
				var tgt_r: float   = fx.get("target_r", 80.0)
				var phase_f: float = 1.0 - (t / mt)
				var cur_r: float
				if phase_f < 0.25:
					cur_r = tgt_r * (phase_f / 0.25)
				else:
					cur_r = tgt_r * (0.93 + 0.07 * sin((phase_f - 0.25) * TAU * 2.5))
				draw_arc(ctr, cur_r, 0.0, TAU, 128, Color(c.r, c.g, c.b, alpha),       3.5)
				draw_arc(ctr, cur_r * 0.93, 0.0, TAU, 112, Color(c.r, c.g, c.b, alpha * 0.7), 2.0)
				draw_arc(ctr, cur_r * 0.65, 0.0, TAU, 80,  Color(c.r, c.g, c.b, alpha * 0.4), 1.5)
				draw_circle(ctr, cur_r * 0.55, Color(c.r, c.g, c.b, alpha * 0.08))
				# Cardinal sparkles
				var spin4: float = Time.get_ticks_msec() * 0.005
				for i in range(4):
					var ang: float = (TAU * i) / 4.0 + spin4
					var sp: Vector2 = ctr + Vector2(cos(ang), sin(ang)) * (cur_r + 12.0)
					var sp2: float  = 0.55 + 0.45 * sin(spin4 * 3.0 + ang)
					draw_circle(sp, 3.0 * sp2, Color(1.0, 1.0, 1.0, alpha * sp2))
			"hit_flash":
				var ctr: Vector2   = fx["center"]
				var fs: float      = fx.get("flash_size", 22.0)
				draw_circle(ctr, fs, Color(c.r, c.g, c.b, alpha * 0.75))
				draw_circle(ctr, fs * 0.65, Color(1.0, 1.0, 1.0, alpha))
				var ring_r: float  = fs * (1.0 - frac * 0.6)
				draw_arc(ctr, ring_r, 0.0, TAU, 24, Color(c.r, c.g, c.b, alpha), 2.5)
				var ring_r2: float = fs * 0.55 * (1.0 - frac * 0.6)
				draw_arc(ctr, ring_r2, 0.0, TAU, 18, Color(1.0, 1.0, 1.0, alpha * 0.5), 1.5)

	# --- Pass 3: Name labels and HP bars above all visible characters ---
	# Drawn last so they appear on top of all tile/sprite content.
	# Clip: skip characters outside viewport + 64px margin.
	var p3_font := ThemeDB.fallback_font
	var p3_font_sz: int = 9
	var p3_bar_w: int = 24
	var p3_bar_h: int = 4
	var p3_clip_x: float = 160.0 + 64.0
	var p3_clip_y: float = 88.0 + 64.0

	# _chars: local player + server NPCs (id >= 10001) + other players.
	for p3_idx in _chars:
		var p3c: CharData = _chars[p3_idx]
		if not p3c.active or p3c.char_name == "":
			continue
		var p3x: int
		var p3y: int
		if p3_idx == _player_idx:
			p3x = int(_cam_pixel.x)
			p3y = int(_cam_pixel.y)
		else:
			p3x = p3c.tile_pos.x * TILE + int(p3c.move_offset.x)
			p3y = p3c.tile_pos.y * TILE + int(p3c.move_offset.y)
		if abs(float(p3x) - _cam_pixel.x) > p3_clip_x:
			continue
		if abs(float(p3y) - _cam_pixel.y) > p3_clip_y:
			continue
		var p3_is_npc: bool = (p3_idx >= 10001)
		var p3_col: Color
		if p3_idx == _player_idx:
			p3_col = Color(1.0, 0.95, 0.4, 1.0)
		elif p3_is_npc:
			p3_col = Color(0.80, 0.70, 0.52, 0.95)
		else:
			p3_col = Color(1.0, 1.0, 1.0, 1.0)
		var p3_ly: int = p3y - 42
		if p3_idx != _player_idx and p3c.max_hp > 0 and p3c.hp < p3c.max_hp:
			var p3_frac := clampf(float(p3c.hp) / float(p3c.max_hp), 0.0, 1.0)
			var p3_bx: int = p3x - p3_bar_w / 2 + 16
			var p3_by: int = p3_ly - p3_bar_h - 3
			draw_rect(Rect2(float(p3_bx - 1), float(p3_by - 1), float(p3_bar_w + 2), float(p3_bar_h + 2)), Color(0.0, 0.0, 0.0, 0.75))
			draw_rect(Rect2(float(p3_bx), float(p3_by), float(p3_bar_w), float(p3_bar_h)), Color(0.30, 0.02, 0.02, 0.95))
			var p3_fc: Color
			if p3_frac > 0.5:
				p3_fc = Color(0.15, 0.85, 0.10, 1.0).lerp(Color(1.0, 1.0, 0.0, 1.0), (p3_frac - 0.5) * 2.0)
			else:
				p3_fc = Color(0.95, 0.10, 0.05, 1.0).lerp(Color(1.0, 0.85, 0.0, 1.0), p3_frac * 2.0)
			draw_rect(Rect2(float(p3_bx), float(p3_by), float(p3_bar_w) * p3_frac, float(p3_bar_h)), p3_fc)
		var p3_nw: float = p3_font.get_string_size(p3c.char_name, HORIZONTAL_ALIGNMENT_LEFT, -1, p3_font_sz).x
		var p3_nx: int = p3x + 16 - int(p3_nw * 0.5)
		draw_string(p3_font, Vector2(float(p3_nx) - 1.0, float(p3_ly) + 1.0), p3c.char_name, HORIZONTAL_ALIGNMENT_LEFT, -1, p3_font_sz, Color(0.0, 0.0, 0.0, 0.75))
		draw_string(p3_font, Vector2(float(p3_nx), float(p3_ly)), p3c.char_name, HORIZONTAL_ALIGNMENT_LEFT, -1, p3_font_sz, p3_col)
		# Draw quest indicator (! or ?) above nameplate for NPCs with quests
		if p3_is_npc and _quest_indicators.has(p3_idx):
			var p3_ind: String = _quest_indicators[p3_idx]
			var p3_ind_col: Color = Color(1.0, 0.9, 0.0, 1.0) if p3_ind == "!" else Color(0.3, 0.9, 0.3, 1.0)
			var p3_ind_sz: int = 14
			var p3_ind_font: Font = ThemeDB.fallback_font
			var p3_ind_w: float = p3_ind_font.get_string_size(p3_ind, HORIZONTAL_ALIGNMENT_LEFT, -1, p3_ind_sz).x
			var p3_ind_x: int = p3x + 16 - int(p3_ind_w * 0.5)
			var p3_ind_y: int = p3_ly - p3_ind_sz - 2
			draw_string(p3_ind_font, Vector2(float(p3_ind_x) - 1.0, float(p3_ind_y) + 1.0), p3_ind, HORIZONTAL_ALIGNMENT_LEFT, -1, p3_ind_sz, Color(0.0, 0.0, 0.0, 0.7))
			draw_string(p3_ind_font, Vector2(float(p3_ind_x), float(p3_ind_y)), p3_ind, HORIZONTAL_ALIGNMENT_LEFT, -1, p3_ind_sz, p3_ind_col)

	# _map_npcs: offline-mode map-spawned NPCs.
	for p3_nid in _map_npcs:
		var p3c: CharData = _map_npcs[p3_nid]
		if not p3c.active or p3c.char_name == "":
			continue
		var p3x: int = p3c.tile_pos.x * TILE + int(p3c.move_offset.x)
		var p3y: int = p3c.tile_pos.y * TILE + int(p3c.move_offset.y)
		if abs(float(p3x) - _cam_pixel.x) > p3_clip_x:
			continue
		if abs(float(p3y) - _cam_pixel.y) > p3_clip_y:
			continue
		var p3_ly: int = p3y - 42
		if p3c.max_hp > 0 and p3c.hp < p3c.max_hp:
			var p3_frac := clampf(float(p3c.hp) / float(p3c.max_hp), 0.0, 1.0)
			var p3_bx: int = p3x - p3_bar_w / 2 + 16
			var p3_by: int = p3_ly - p3_bar_h - 3
			draw_rect(Rect2(float(p3_bx - 1), float(p3_by - 1), float(p3_bar_w + 2), float(p3_bar_h + 2)), Color(0.0, 0.0, 0.0, 0.75))
			draw_rect(Rect2(float(p3_bx), float(p3_by), float(p3_bar_w), float(p3_bar_h)), Color(0.30, 0.02, 0.02, 0.95))
			var p3_fc: Color
			if p3_frac > 0.5:
				p3_fc = Color(0.15, 0.85, 0.10, 1.0).lerp(Color(1.0, 1.0, 0.0, 1.0), (p3_frac - 0.5) * 2.0)
			else:
				p3_fc = Color(0.95, 0.10, 0.05, 1.0).lerp(Color(1.0, 0.85, 0.0, 1.0), p3_frac * 2.0)
			draw_rect(Rect2(float(p3_bx), float(p3_by), float(p3_bar_w) * p3_frac, float(p3_bar_h)), p3_fc)
		var p3_nw: float = p3_font.get_string_size(p3c.char_name, HORIZONTAL_ALIGNMENT_LEFT, -1, p3_font_sz).x
		var p3_nx: int = p3x + 16 - int(p3_nw * 0.5)
		draw_string(p3_font, Vector2(float(p3_nx) - 1.0, float(p3_ly) + 1.0), p3c.char_name, HORIZONTAL_ALIGNMENT_LEFT, -1, p3_font_sz, Color(0.0, 0.0, 0.0, 0.75))
		draw_string(p3_font, Vector2(float(p3_nx), float(p3_ly)), p3c.char_name, HORIZONTAL_ALIGNMENT_LEFT, -1, p3_font_sz, Color(0.80, 0.70, 0.52, 0.95))

	# Training dummy.
	if _dummy_char != null and _dummy_char.active and _dummy_char.char_name != "":
		var p3x: int = _dummy_char.tile_pos.x * TILE
		var p3y: int = _dummy_char.tile_pos.y * TILE
		if abs(float(p3x) - _cam_pixel.x) <= p3_clip_x and abs(float(p3y) - _cam_pixel.y) <= p3_clip_y:
			var p3_ly: int = p3y - 42
			var p3_nw: float = p3_font.get_string_size(_dummy_char.char_name, HORIZONTAL_ALIGNMENT_LEFT, -1, p3_font_sz).x
			var p3_nx: int = p3x + 16 - int(p3_nw * 0.5)
			draw_string(p3_font, Vector2(float(p3_nx) - 1.0, float(p3_ly) + 1.0), _dummy_char.char_name, HORIZONTAL_ALIGNMENT_LEFT, -1, p3_font_sz, Color(0.0, 0.0, 0.0, 0.75))
			draw_string(p3_font, Vector2(float(p3_nx), float(p3_ly)), _dummy_char.char_name, HORIZONTAL_ALIGNMENT_LEFT, -1, p3_font_sz, Color(0.80, 0.70, 0.52, 0.95))

func _draw_chars_at(map_tile: Vector2i, wx: int, wy: int) -> void:
	# Network characters (player + server-provided)
	for c_idx in _chars:
		var c: CharData = _chars[c_idx]
		if not c.active or c.tile_pos != map_tile:
			continue
		var dx: int
		var dy: int
		if c_idx == _player_idx:
			# Player always draws at camera center — world slides around them.
			dx = int(_cam_pixel.x)
			dy = int(_cam_pixel.y)
		else:
			dx = wx + int(c.move_offset.x)
			dy = wy + int(c.move_offset.y)
		_draw_char(c, dx, dy)

	# Map-spawned NPCs
	for npc_id in _map_npcs:
		var c: CharData = _map_npcs[npc_id]
		if not c.active or c.tile_pos != map_tile:
			continue
		var ndx := wx + int(c.move_offset.x)
		var ndy := wy + int(c.move_offset.y)
		_draw_char(c, ndx, ndy)

	# Training dummy (offline combat test target)
	if _dummy_char != null and _dummy_char.active and _dummy_char.tile_pos == map_tile:
		_draw_char(_dummy_char, wx, wy)
		_draw_dummy_hp_bar(wx, wy)


## Draw a single character at world pixel (dx, dy).
## VB6 draw order: Head (static), Body, Shield, Weapon.
func _draw_char(c: CharData, dx: int, dy: int) -> void:
	var di := _hidx(c.heading)
	var body_d := GameData.get_body(c.body_idx)
	var hox: int = body_d.get("head_offset_x", 0)
	var hoy: int = body_d.get("head_offset_y", 0)

	var hgrh := GameData.get_head_grh(c.head_idx, di)
	if hgrh > 0:
		_draw_grh(hgrh, dx + hox, dy + hoy, true)
	if di < c.body_anims.size():
		_draw_animator(c.body_anims[di] as GrhAnimator, dx, dy)
	if di < c.shield_anims.size():
		_draw_animator(c.shield_anims[di] as GrhAnimator, dx, dy)
	if di < c.weapon_anims.size():
		_draw_animator(c.weapon_anims[di] as GrhAnimator, dx, dy)



func _draw_hp_bar(c: CharData, wx: int, wy: int) -> void:
	if c.max_hp <= 0:
		return
	var frac := clampf(float(c.hp) / float(c.max_hp), 0.0, 1.0)
	const BAR_W := 28
	const BAR_H := 4
	var bx := wx - BAR_W / 2 + 16
	var by := wy - 28
	draw_rect(Rect2(float(bx - 1), float(by - 1), float(BAR_W + 2), float(BAR_H + 2)), Color(0.0, 0.0, 0.0, 0.75))
	draw_rect(Rect2(float(bx), float(by), float(BAR_W), float(BAR_H)), Color(0.18, 0.02, 0.02, 0.95))
	draw_rect(Rect2(float(bx), float(by), float(BAR_W) * frac, float(BAR_H)), Color(0.88, 0.12, 0.12, 1.0))


# ---------------------------------------------------------------------------
# Low-level draw helpers
# ---------------------------------------------------------------------------

## Draw a static GRH at world position (wx, wy).
func _draw_grh(grh_index: int, wx: int, wy: int, centered: bool) -> void:
	if grh_index <= 0:
		return
	var entry := GameData.get_grh(grh_index)
	if entry.is_empty():
		return
	var frame := 0
	var num_frames: int = entry.get("num_frames", 1)
	if num_frames > 1:
		var speed: int = max(1, entry.get("speed", 1) + 1)
		frame = (_tile_anim_tick / speed) % num_frames
	var fd := GameData.get_grh_frame(grh_index, frame)
	if fd.is_empty():
		return
	_blit(fd, wx, wy, centered)


## Draw the current frame of a GrhAnimator.
func _draw_animator(anim: GrhAnimator, wx: int, wy: int) -> void:
	if anim == null or anim.grh_index <= 0:
		return
	var fd := anim.get_frame_data()
	if fd.is_empty():
		return
	_blit(fd, wx, wy, true)


## Compute the visible tile range for a neighbor map given its world offset.
func _neighbor_range(offset_x: int, offset_y: int) -> Array:
	var cpx := int(_cam_pixel.x)
	var cpy := int(_cam_pixel.y)
	const HW := 13 * TILE
	const HH :=  9 * TILE
	return [
		clampi(int((cpx - HW - offset_x) / TILE),     1, 100),
		clampi(int((cpx + HW - offset_x) / TILE) + 1, 1, 100),
		clampi(int((cpy - HH - offset_y) / TILE),     1, 100),
		clampi(int((cpy + HH - offset_y) / TILE) + 1, 1, 100),
	]


## Render Layer 1 (opaque ground) of a neighbor map.
func _draw_neighbor_layer1(ntiles: Dictionary, offset_x: int, offset_y: int) -> void:
	var r := _neighbor_range(offset_x, offset_y)
	for ty in range(r[2], r[3] + 1):
		for tx in range(r[0], r[1] + 1):
			var layers: Array = ntiles.get("%d,%d" % [ty, tx], {}).get("layers", [])
			if layers.size() > 0 and layers[0] > 0:
				_draw_grh(layers[0], tx * TILE + offset_x, ty * TILE + offset_y, false)


## Render Layer 2 + objects + layer-3 rain of a neighbor map (transparent, centered).
func _draw_neighbor_layer2(ntiles: Dictionary, offset_x: int, offset_y: int) -> void:
	var r := _neighbor_range(offset_x, offset_y)
	for ty in range(r[2], r[3] + 1):
		for tx in range(r[0], r[1] + 1):
			var t: Dictionary = ntiles.get("%d,%d" % [ty, tx], {})
			var layers: Array = t.get("layers", [])
			var wx := tx * TILE + offset_x
			var wy := ty * TILE + offset_y
			if layers.size() > 1 and layers[1] > 0:
				_draw_grh(layers[1], wx, wy, true)
			var obj: Dictionary = t.get("obj", {})
			if not obj.is_empty():
				var og: int = GameData.get_object(obj.get("index", 0)).get("grh_index", 0)
				if og > 0:
					_draw_grh(og, wx, wy, true)
			if raining and layers.size() > 2 and layers[2] > 0:
				_draw_grh(layers[2], wx, wy, true)


## Core blit: draw a GRH frame dict at (wx, wy) in world space.
## VB6 centering formula:
##   dx = wx - pixel_width/2 + 16   (centers wide sprites on tile anchor)
##   dy = wy - pixel_height  + 32   (aligns sprite bottom to tile bottom)
func _blit(fd: Dictionary, wx: int, wy: int, centered: bool) -> void:
	var file_num: int = fd.get("file_num", 0)
	if file_num <= 0:
		return
	var tex := tex_cache.get_texture(file_num)
	if tex == null:
		return

	var sx: int = fd.get("sx", 0)
	var sy: int = fd.get("sy", 0)
	var pw: int = fd.get("pixel_width",  TILE)
	var ph: int = fd.get("pixel_height", TILE)

	var dx := wx
	var dy := wy
	if centered:
		dx = wx - pw / 2 + 16
		dy = wy - ph + TILE

	draw_texture_rect_region(tex,
		Rect2(float(dx), float(dy), float(pw), float(ph)),
		Rect2(float(sx), float(sy), float(pw), float(ph)))


# ---------------------------------------------------------------------------
# World-space damage floaters
# ---------------------------------------------------------------------------

## Spawn a floating damage number at the world position of char_id.
## Uses draw_string() in _draw() so the floater moves with the camera naturally.
func spawn_damage_floater(char_id: int, amount: int, evaded: bool) -> void:
	# Resolve tile position for this character.
	var tile_pos := cam_tile  # fallback: player tile

	# Check player
	if char_id == Network.local_char_id or char_id == _player_idx:
		tile_pos = cam_tile
	else:
		# Other networked characters
		var c := _chars.get(char_id, null) as CharData
		if c != null:
			tile_pos = c.tile_pos
		else:
			# Map NPCs (instance IDs stored in _map_npcs keyed by npc_id int)
			var npc := _map_npcs.get(char_id, null) as CharData
			if npc != null:
				tile_pos = npc.tile_pos

	# World pixel center of the tile, slightly above the head
	var wx := float(tile_pos.x * TILE) + 16.0 + randf_range(-8.0, 8.0)
	var wy := float(tile_pos.y * TILE) - 10.0

	# Choose text and colour
	var text: String
	var col: Color
	if evaded:
		text = "Miss"
		col  = Color(0.85, 0.85, 0.35, 1.0)   # yellow
	else:
		text = "-%d" % amount
		# Brighter / more orange-red for big hits
		var intensity := minf(1.0, 0.5 + float(amount) / 20.0)
		col = Color(1.0, intensity * 0.35, 0.1, 1.0)

	_world_floaters.append({
		"text":  text,
		"wx":    wx,
		"wy":    wy,
		"alpha": 1.0,
		"color": col,
		"timer": 1.2,
	})


# ---------------------------------------------------------------------------
# Network signal handlers
# ---------------------------------------------------------------------------

## Server placed us on a map — load it and position the camera.
func _on_net_world_state(map_id: int, x: int, y: int) -> void:
	# If the death screen is visible, hold respawn data until player clicks Respawn.
	if _death_screen != null and _death_screen.is_open():
		_pending_respawn = {"map_id": map_id, "x": x, "y": y}
		_death_screen.on_respawn_data_ready()
		return
	_load_map_at(map_id, Vector2i(x, y))


## Server sent full char data (spawn or update).
func _on_net_set_char(char_id: int, body: int, head: int, weapon: int, shield: int,
		x: int, y: int, heading: int, hp: int, max_hp: int, _char_name: String) -> void:
	if char_id == Network.local_char_id:
		# This is us — update our CharData but don't move the camera;
		# camera is already positioned by local prediction.
		var p := _chars.get(_player_idx, null) as CharData
		if p != null:
			p.body_idx   = body
			p.head_idx   = head
			p.weapon_idx = weapon
			p.shield_idx = shield
			p.heading    = heading
			p.hp         = hp
			p.max_hp     = max_hp
			# Update base_body_idx when no armor/helmet is equipped
			# (server sends the unadorned base body in that case).
			var armor_eq: int = PlayerState.get_equipped("armor")
			var helmet_eq: int = PlayerState.get_equipped("helmet")
			if armor_eq == 0 and helmet_eq == 0:
				p.base_body_idx = body
			_build_anims(p)
	else:
		# Another player entering our visible area.
		set_char(char_id, body, head, weapon, shield, Vector2i(x, y), heading, _char_name, hp, max_hp)


## Server moved a character to a new tile.
func _on_net_move_char(char_id: int, x: int, y: int, heading: int) -> void:
	if char_id == Network.local_char_id:
		# Server position confirmation — correct if we drifted (e.g. server rejected a move).
		var server_tile := Vector2i(x, y)
		if server_tile != cam_tile:
			cam_tile    = server_tile
			_cam_target = Vector2(cam_tile * TILE)
			var p := _chars.get(_player_idx, null) as CharData
			if p != null:
				p.tile_pos = server_tile
				p.heading  = heading
	else:
		move_char_to(char_id, Vector2i(x, y))
		# Update heading on the char
		var c := _chars.get(char_id, null) as CharData
		if c != null:
			c.heading = heading


## Server removed a character (logout, out of range, death).
func _on_net_remove_char(char_id: int) -> void:
	remove_char(char_id)


## Server warped us to a different map (tile exit, spell, GM warp).
func _on_net_map_change(map_id: int, x: int, y: int) -> void:
	_load_map_at(map_id, Vector2i(x, y))


## Server triggered a sound effect.
func _on_net_play_sound(sound_num: int) -> void:
	AudioManager.play_sound(sound_num)


func _on_rain_changed(is_raining: bool) -> void:
	raining = is_raining
	if is_raining:
		AudioManager.play_sound(43)   # snd43.wav — VB6 rain sound


## Chat message received — forwarded to ChatUI; keep console fallback.
func _on_net_chat(char_id: int, chat_type: int, message: String) -> void:
	print("[CHAT type=%d char=%d] %s" % [chat_type, char_id, message])
	# ChatUI connects to Network.on_chat directly, so no explicit forward needed.
	# The print is kept for debugging; ChatUI handles display independently.


## Server kicked us.
func _on_net_kicked(reason: String) -> void:
	push_warning("[WorldMap] Kicked: " + reason)
	_on_quit_to_menu()


## Player died — show the death overlay until S_WORLD_STATE fires.
func _on_net_death(killer_name: String) -> void:
	if _death_screen != null:
		_pending_respawn = {}
		_death_screen.show_death(killer_name)


## Player clicked Respawn on death screen — apply the held teleport data.
func _on_death_respawn_confirmed() -> void:
	if not _pending_respawn.is_empty():
		_load_map_at(_pending_respawn["map_id"],
				Vector2i(_pending_respawn["x"], _pending_respawn["y"]))
		_pending_respawn = {}


## XP gained — spawn a green floater at the player's position.
func _on_net_xp_gain(amount: int) -> void:
	var wx := float(cam_tile.x * TILE)
	var wy := float(cam_tile.y * TILE - 16)
	_world_floaters.append({
		"text":  "+%d XP" % amount,
		"wx":    wx,
		"wy":    wy,
		"alpha": 1.0,
		"color": Color(0.4, 0.9, 0.4, 1.0),
		"timer": 2.0,
	})
	queue_redraw()


## Level gained — show the fanfare panel.
func _on_net_level_up(new_level: int) -> void:
	if _level_up_ui != null:
		_level_up_ui.show_level_up(new_level)


## Connection dropped unexpectedly — return to main menu.
func _on_disconnected(reason: String) -> void:
	push_warning("[WorldMap] Disconnected: " + reason)
	_on_quit_to_menu()


func _on_quit_to_menu() -> void:
	if Network.state != Network.State.DISCONNECTED:
		Network.disconnect_from_server()
	get_tree().change_scene_to_file("res://scenes/main/Main.tscn")


## Server sent damage event — spawn a world-space floater over the target.
func _on_net_damage(char_id: int, damage: int, evaded: bool) -> void:
	if not evaded:
		if char_id == Network.local_char_id:
			var p := _chars.get(_player_idx, null) as CharData
			if p != null:
				p.hp = maxi(0, p.hp - damage)
		else:
			var pc := _chars.get(char_id, null) as CharData
			if pc != null:
				pc.hp = maxi(0, pc.hp - damage)
			var npc := _map_npcs.get(char_id, null) as CharData
			if npc != null:
				npc.hp = maxi(0, npc.hp - damage)
	spawn_damage_floater(char_id, damage, evaded)


## Server responded to our shop_open request with the shop inventory.
func _on_shop_list(shop_name: String, items: Array) -> void:
	AudioManager.play_sound(SND_UI_CLICK)
	var shop := preload("res://scripts/ui/shop_ui.gd").new()
	add_child(shop)
	shop.open(shop_name, items, _last_shop_npc_id)


## Server sent a trainer ability shop — open the trainer UI.
func _on_ability_shop_received(_abilities: Array) -> void:
	AudioManager.play_sound(SND_UI_CLICK)
	var trainer := preload("res://scripts/ui/trainer_ui.gd").new()
	add_child(trainer)
	# trainer_ui wires on_ability_shop itself in _connect_signals/_ready,
	# but it was already emitted — call open directly since the signal already fired.
	# Re-emit approach: store abilities and open. The TrainerUI connects on _ready,
	# so we call populate directly after adding it.
	trainer._on_ability_shop(_abilities)


# ---------------------------------------------------------------------------
# Training dummy rendering
# ---------------------------------------------------------------------------

## Draw a small HP bar above the training dummy in world space.
func _draw_dummy_hp_bar(wx: int, wy: int) -> void:
	var frac := clampf(float(CombatSystem.dummy_hp) / float(CombatSystem.OFFLINE_DUMMY_HP), 0.0, 1.0)
	const BAR_W := 28
	const BAR_H := 4
	var bx := wx - BAR_W / 2 + 16
	var by := wy - 12
	draw_rect(Rect2(float(bx), float(by), float(BAR_W), float(BAR_H)), Color(0.2, 0.02, 0.02))
	draw_rect(Rect2(float(bx), float(by), float(BAR_W) * frac, float(BAR_H)), Color(0.85, 0.1, 0.1))
	# Label "DUMMY" in small text
	draw_string(ThemeDB.fallback_font, Vector2(bx - 2, by - 2), "DUMMY",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.9, 0.7, 0.4))


# ---------------------------------------------------------------------------
# Equipment changed handler
# ---------------------------------------------------------------------------

## Trigger a brief weapon-swing animation when any skill fires.
func _on_skill_used(_skill_id: int, target_id: int) -> void:
	_attack_anim_timer = 0.4   # seconds; covers ~12 walk-anim frames at 30fps
	# Spawn local arrow projectile when using a ranged weapon
	var wpn_idx: int = PlayerState.get_equipped("weapon")
	if wpn_idx > 0:
		var wpn_data: Dictionary = GameData.get_object(wpn_idx)
		if wpn_data.get("category", "") == "Archery":
			var from_pos: Vector2 = _entity_world_pos(_player_idx)
			var to_pos: Vector2   = _entity_world_pos(target_id)
			if to_pos != Vector2.ZERO and from_pos != Vector2.ZERO:
				var dist: float = from_pos.distance_to(to_pos)
				var flight_time: float = clampf(dist / (12.0 * TILE), 0.15, 0.9)
				# Arrow: warm gold color; crossbow bolt: cool steel-blue
				var proj_col := Color(0.85, 0.72, 0.30)
				_spell_effects.append({
					"type": "proj", "from": from_pos, "to": to_pos,
					"color": proj_col, "timer": flight_time, "max_timer": flight_time
				})


## Rebuild player character animations when equipment changes (e.g. after equipping a weapon).
func _on_equipment_changed() -> void:
	var p := _chars.get(_player_idx, null) as CharData
	if p == null:
		return
	var wpn_idx := PlayerState.get_equipped("weapon")
	var shd_idx := PlayerState.get_equipped("shield")
	var armor_idx := PlayerState.get_equipped("armor")
	var helmet_idx := PlayerState.get_equipped("helmet")

	if wpn_idx > 0:
		p.weapon_idx = GameData.get_object(wpn_idx).get("weapon_anim", 0)
	else:
		p.weapon_idx = 0
	if shd_idx > 0:
		p.shield_idx = GameData.get_object(shd_idx).get("shield_anim", 0)
	else:
		p.shield_idx = 0

	# VB6 faithful: equipping armor or helmet changes the body sprite index to
	# the item's clothing_type, which is a direct index into body.dat.
	# Helmet takes priority over armor (matches VB6 OBJTYPE_HELMET case).
	# Start from base_body_idx so unequipping always reverts correctly.
	var new_body_idx: int = p.base_body_idx
	if armor_idx > 0:
		var armor_obj := GameData.get_object(armor_idx)
		var ct: int = armor_obj.get("clothing_type", 0)
		if ct > 0:
			new_body_idx = ct
	if helmet_idx > 0:
		var helmet_obj := GameData.get_object(helmet_idx)
		var ct: int = helmet_obj.get("clothing_type", 0)
		if ct > 0:
			new_body_idx = ct
	p.body_idx = new_body_idx

	_build_anims(p)


# ---------------------------------------------------------------------------
# Context menu signal handlers
# ---------------------------------------------------------------------------

func _on_context_skill(skill_id: int, tile: Vector2i) -> void:
	## Right-click skill use: send to server when online, or print to chat offline.
	if Network.state == Network.State.CONNECTED:
		Network.send_use_skill(skill_id, tile.x, tile.y)
	else:
		# Offline: show a message in chat (no local skill simulation yet)
		var msg := "Skill %d used at (%d,%d) [offline]" % [skill_id, tile.x, tile.y]
		if _chat_ui != null and _chat_ui.has_method("add_message"):
			_chat_ui.add_message(msg)
		else:
			print("[WorldMap] " + msg)


func _on_skill_progress(skill_id: int, duration_ms: int) -> void:
	## Server notified us of a skill progress update (start or cancel).
	if _skill_progress_ui != null and _skill_progress_ui.has_method("start_progress"):
		_skill_progress_ui.start_progress(skill_id, duration_ms)


func _on_context_walk(tile: Vector2i) -> void:
	## Right-click walk: move the camera target toward the selected tile.
	## Simple one-step movement toward the target tile (not pathfinding).
	var dx: int = sign(tile.x - cam_tile.x)
	var dy: int = sign(tile.y - cam_tile.y)
	var dir := Vector2i.ZERO
	var heading := 0
	if dx != 0:
		dir = Vector2i(dx, 0)
		heading = 2 if dx > 0 else 4
	elif dy != 0:
		dir = Vector2i(0, dy)
		heading = 3 if dy > 0 else 1
	if dir == Vector2i.ZERO:
		return
	var new_tile := cam_tile + dir
	if not _walkable(new_tile):
		return
	cam_tile    = new_tile
	_cam_target = Vector2(cam_tile * TILE)
	if Network.state == Network.State.CONNECTED:
		Network.send_move(heading)
	var pc := _chars.get(_player_idx, null) as CharData
	if pc != null:
		pc.tile_pos = new_tile
		pc.heading  = heading
		pc.moving   = true


func _on_context_examine(char_id: int) -> void:
	## Right-click examine: display character name in chat.
	var char_name := ""
	var c := _chars.get(char_id, null) as CharData
	if c != null:
		char_name = c.char_name
	if char_name.is_empty():
		var npc := _map_npcs.get(char_id, null) as CharData
		if npc != null:
			char_name = npc.char_name
	if char_name.is_empty():
		char_name = "NPC"
	if _chat_ui != null and _chat_ui.has_method("add_message"):
		_chat_ui.add_message("[Examine] " + char_name)
	else:
		print("[WorldMap] Examine: " + char_name)


func _on_context_trade(char_id: int) -> void:
	## Right-click trade: send a trade request to another player.
	if Network.state != Network.State.CONNECTED:
		if _chat_ui != null:
			_chat_ui.add_message("Trade requires an online connection.", 1)
		return
	Network.send_trade_request(char_id)


func _on_context_talk(char_id: int) -> void:
	## Right-click "Talk to" — sends quest talk request to server.
	if Network.state != Network.State.CONNECTED:
		if _chat_ui != null:
			_chat_ui.add_message("No quests available in offline mode.", 0)
		return
	Network.send_quest_talk(char_id)


func _on_net_quest_offer(mode: int, quest_id: int, npc_name: String, quest_name: String,
		desc: String, objectives: Array, rewards: Dictionary) -> void:
	## Server offers or requests turn-in — show the appropriate dialog.
	if mode == 1:
		# Turn-in mode
		_quest_dialog_ui.show_turnin(npc_name, quest_id, quest_name, rewards)
	else:
		# Offer mode
		_quest_dialog_ui.show_offer(npc_name, quest_id, quest_name, desc,
				objectives, rewards)
		# Pre-register in journal so the quest name is known before accept
		if _quest_ui != null:
			var obj_parts: Array = []
			for obj in objectives:
				var od: Dictionary = obj as Dictionary
				obj_parts.append(od.get("label", "") + ": 0/" + str(od.get("count", od.get("required", 1))))
			_quest_ui.update_quest(quest_id, quest_name, "\n".join(obj_parts), false)


func _on_quest_dialog_accepted(quest_id: int) -> void:
	Network.send_quest_accept(quest_id)


func _on_quest_dialog_turnin(quest_id: int) -> void:
	Network.send_quest_turnin(quest_id)


func _on_net_quest_update(quest_id: int, progress: Dictionary) -> void:
	## Server pushed progress update — refresh the journal.
	var obj_str: String = progress.get("objectives_str", "")
	# We may not know the quest name here if journal doesn't have it yet;
	# QuestUI handles the case gracefully.
	if _quest_ui != null:
		_quest_ui.update_quest(quest_id,
				_quest_ui._quests.get(quest_id, {}).get("name", "Quest"),
				obj_str, false)


func _on_net_quest_complete(quest_id: int, reward_gold: int, reward_xp: int) -> void:
	## Server signals quest is complete — update journal and show chat message.
	if _quest_ui != null:
		var entry: Dictionary = (_quest_ui._quests.get(quest_id, {}) as Dictionary)
		_quest_ui.update_quest(quest_id, entry.get("name", "Quest"), "", true)
	if _chat_ui != null:
		_chat_ui.add_message(
			"Quest complete! Reward: %d gold, %d XP." % [reward_gold, reward_xp], 0)


func _on_quest_indicators(indicators: Dictionary) -> void:
	## Server sent updated quest markers for NPCs on this map.
	_quest_indicators = indicators
	queue_redraw()


func _on_ground_item_add(id: int, obj_index: int, amount: int, x: int, y: int) -> void:
	_ground_items[id] = {"obj_index": obj_index, "amount": amount, "x": x, "y": y}
	queue_redraw()


func _on_ground_item_remove(id: int) -> void:
	_ground_items.erase(id)
	queue_redraw()


func _on_net_corpse(x: int, y: int, grh_index: int) -> void:
	_corpses.append({"grh_index": grh_index, "x": x, "y": y, "timer": CORPSE_DURATION})
	queue_redraw()


func _on_context_pickup(item_id: int) -> void:
	if Network.state == Network.State.CONNECTED:
		Network.send_pickup(item_id)


# ---------------------------------------------------------------------------
# Spell FX colors by effect_type
# ---------------------------------------------------------------------------
const _SPELL_COLORS: Dictionary = {
	"projectile": Color(0.35, 0.70, 1.00),   # cyan-blue bolt
	"aoe_burst":  Color(1.00, 0.45, 0.10),   # orange-red fire
	"nova":       Color(0.55, 0.92, 1.00),   # frost blue
	"chain":      Color(1.00, 0.95, 0.20),   # yellow lightning
	"status":     Color(0.75, 0.10, 0.95),   # bright purple
	"heal":       Color(0.20, 0.92, 0.38),   # green
	"drain":      Color(0.90, 0.20, 0.90),   # magenta-purple
	"push":       Color(0.92, 0.92, 1.00),   # near-white
	"shimmer":    Color(1.00, 0.80, 0.10),   # gold
	"summon":     Color(0.50, 0.20, 0.90),   # deep purple
	"portal":     Color(0.15, 0.90, 0.75),   # teal
	"warp":       Color(0.15, 0.90, 0.75),   # teal (alias for portal)
	"hit":        Color(1.00, 0.30, 0.10),   # red-orange
}

func _entity_world_pos(entity_id: int) -> Vector2:
	## Returns the center pixel position of a char/NPC by their ID.
	## Returns Vector2.ZERO if not found.
	if entity_id == -1 and _dummy_char != null and _dummy_char.active:
		return Vector2(_dummy_tile.x * TILE + 16, _dummy_tile.y * TILE + 16)
	if _chars.has(entity_id):
		var c: CharData = _chars[entity_id]
		return Vector2(c.tile_pos.x * TILE + 16, c.tile_pos.y * TILE + 16)
	if _map_npcs.has(entity_id):
		var c: CharData = _map_npcs[entity_id]
		return Vector2(c.tile_pos.x * TILE + 16, c.tile_pos.y * TILE + 16)
	return Vector2.ZERO


func _spell_color(spell_id: int) -> Color:
	var sp: Dictionary = GameData.get_spell(spell_id)
	var et: String = sp.get("effect_type", "hit")
	return _SPELL_COLORS.get(et, Color(0.5, 0.5, 1.0))


func _on_spell_cast_fx(caster_id: int, spell_id: int, target_id: int, tx: int, ty: int) -> void:
	var sp: Dictionary = GameData.get_spell(spell_id)
	var et: String     = sp.get("effect_type", "hit")
	var col: Color     = _SPELL_COLORS.get(et, Color(0.5, 0.5, 1.0))
	var from_pos: Vector2 = _entity_world_pos(caster_id)
	var aoe_r: float = float(sp.get("aoe_radius", 3)) * TILE + 32.0

	match et:
		"projectile", "hit":
			var to_pos: Vector2
			if target_id >= 10001 or _chars.has(target_id) or target_id == -1:
				to_pos = _entity_world_pos(target_id)
			else:
				to_pos = Vector2(tx * TILE + 16, ty * TILE + 16)
			if from_pos != Vector2.ZERO and to_pos != Vector2.ZERO:
				_spell_effects.append({
					"type": "proj", "from": from_pos, "to": to_pos,
					"timer": 0.35, "max_timer": 0.35, "color": col
				})
		"drain":
			var to_pos: Vector2 = _entity_world_pos(target_id)
			if from_pos != Vector2.ZERO and to_pos != Vector2.ZERO:
				_spell_effects.append({
					"type": "drain_fx", "from": to_pos, "to": from_pos,
					"timer": 0.65, "max_timer": 0.65, "color": col
				})
		"aoe_burst":
			var center := Vector2(tx * TILE + 16, ty * TILE + 16)
			_spell_effects.append({
				"type": "aoe_burst", "center": center,
				"timer": 0.65, "max_timer": 0.65,
				"max_r": aoe_r, "color": col
			})
		"nova":
			if from_pos != Vector2.ZERO:
				_spell_effects.append({
					"type": "nova", "center": from_pos,
					"timer": 0.70, "max_timer": 0.70,
					"max_r": aoe_r, "color": col
				})
		"status":
			var tgt_pos: Vector2 = _entity_world_pos(target_id)
			if tgt_pos != Vector2.ZERO:
				_spell_effects.append({
					"type": "status_fx", "center": tgt_pos,
					"timer": 1.40, "max_timer": 1.40, "color": col
				})
		"heal":
			var tgt_pos: Vector2 = _entity_world_pos(
				target_id if target_id != -1 else caster_id)
			if tgt_pos != Vector2.ZERO:
				_spell_effects.append({
					"type": "heal_fx", "center": tgt_pos,
					"timer": 0.90, "max_timer": 0.90, "color": col
				})
		"push":
			var tgt_pos: Vector2 = _entity_world_pos(target_id)
			if tgt_pos != Vector2.ZERO:
				_spell_effects.append({
					"type": "push_fx", "center": tgt_pos,
					"timer": 0.50, "max_timer": 0.50, "color": col
				})
		"shimmer":
			var tgt_pos: Vector2 = _entity_world_pos(
				target_id if target_id != -1 else caster_id)
			if tgt_pos != Vector2.ZERO:
				_spell_effects.append({
					"type": "shimmer_fx", "center": tgt_pos,
					"timer": 0.85, "max_timer": 0.85, "color": col
				})
		"summon":
			var center := Vector2(tx * TILE + 16, ty * TILE + 16)
			_spell_effects.append({
				"type": "summon_fx", "center": center,
				"timer": 1.20, "max_timer": 1.20, "color": col
			})
		"portal", "warp":
			var center := Vector2(tx * TILE + 16, ty * TILE + 16)
			if tx == 0 and ty == 0 and from_pos != Vector2.ZERO:
				center = from_pos
			_spell_effects.append({
				"type": "portal_fx", "center": center,
				"timer": 1.80, "max_timer": 1.80, "color": col,
				"target_r": 80.0
			})
		"chain":
			# Chain effects are handled separately in _on_spell_chain_fx
			# Just spawn a quick proj from caster to first target
			var to_pos: Vector2 = _entity_world_pos(target_id)
			if from_pos != Vector2.ZERO and to_pos != Vector2.ZERO:
				_spell_effects.append({
					"type": "proj", "from": from_pos, "to": to_pos,
					"timer": 0.25, "max_timer": 0.25, "color": col
				})


func _on_spell_hit_fx(target_id: int, spell_id: int, damage: int, heal: int, mana_drain: int) -> void:
	# Update target's HP bar client-side so it reflects spell damage
	if damage > 0 and target_id != -1:
		if target_id == Network.local_char_id:
			var p := _chars.get(_player_idx, null) as CharData
			if p != null:
				p.hp = maxi(0, p.hp - damage)
		else:
			var pc := _chars.get(target_id, null) as CharData
			if pc != null:
				pc.hp = maxi(0, pc.hp - damage)
	if heal > 0 and target_id != -1:
		if target_id == Network.local_char_id:
			var p := _chars.get(_player_idx, null) as CharData
			if p != null:
				p.hp = mini(p.max_hp, p.hp + heal)

	var tgt_pos: Vector2 = _entity_world_pos(target_id)
	if tgt_pos == Vector2.ZERO and target_id != -1:
		return
	if tgt_pos == Vector2.ZERO:
		tgt_pos = Vector2(cam_tile.x * TILE + 16.0, cam_tile.y * TILE + 16.0)

	var col: Color = _spell_color(spell_id)
	# Impact flash
	_spell_effects.append({
		"type": "hit_flash", "center": tgt_pos,
		"timer": 0.22, "max_timer": 0.22,
		"flash_size": 22.0 + minf(float(damage) / 5.0, 18.0),
		"color": col
	})

	# Damage/heal number floaters
	var jitter_x := randf_range(-10.0, 10.0)
	if damage > 0:
		_world_floaters.append({"text": "-%d" % damage,
			"wx": tgt_pos.x + jitter_x, "wy": tgt_pos.y - 14.0,
			"alpha": 1.0, "timer": 1.1, "color": Color(1.0, 0.30, 0.12)})
	if heal > 0:
		_world_floaters.append({"text": "+%d" % heal,
			"wx": tgt_pos.x + jitter_x, "wy": tgt_pos.y - 14.0,
			"alpha": 1.0, "timer": 1.1, "color": Color(0.22, 0.96, 0.42)})
	if mana_drain > 0:
		_world_floaters.append({"text": "-%dMP" % mana_drain,
			"wx": tgt_pos.x + jitter_x, "wy": tgt_pos.y - 26.0,
			"alpha": 1.0, "timer": 1.1, "color": Color(0.60, 0.20, 0.98)})


func _on_spell_chain_fx(_spell_id: int, target_ids: Array) -> void:
	if target_ids.size() < 1:
		return
	var col: Color = _SPELL_COLORS.get("chain", Color(1, 0.95, 0.2))
	# Collect positions
	var points: Array = []
	for tid in target_ids:
		var p: Vector2 = _entity_world_pos(tid)
		if p != Vector2.ZERO:
			points.append(p)
	if points.size() >= 2:
		_spell_effects.append({
			"type": "chain", "points": points,
			"timer": 0.50, "max_timer": 0.50, "color": col
		})
	# Flash on each target
	for p in points:
		_spell_effects.append({
			"type": "hit_flash", "center": p,
			"timer": 0.20, "max_timer": 0.20,
			"flash_size": 18.0, "color": col
		})


func _on_net_projectile(caster_id: int, target_id: int, proj_type: int) -> void:
	## Renders an incoming projectile from another player (or an NPC with ranged attacks).
	## proj_type: 0 = arrow (warm gold), 1 = crossbow bolt (steel blue)
	var from_pos: Vector2 = _entity_world_pos(caster_id)
	var to_pos: Vector2   = _entity_world_pos(target_id)
	if from_pos == Vector2.ZERO or to_pos == Vector2.ZERO:
		return
	var dist: float = from_pos.distance_to(to_pos)
	var flight_time: float = clampf(dist / (12.0 * TILE), 0.15, 0.9)
	var proj_col: Color
	match proj_type:
		1:    proj_col = Color(0.7, 0.75, 0.85)   # crossbow bolt: steel blue
		_:    proj_col = Color(0.85, 0.72, 0.30)  # arrow: warm gold
	_spell_effects.append({
		"type": "proj", "from": from_pos, "to": to_pos,
		"color": proj_col, "timer": flight_time, "max_timer": flight_time
	})


func _do_cast_spell(spell_id: int, target_id: int, tx: int, ty: int) -> void:
	## Forward spell cast to the server and apply optimistic client-side cooldown.
	Network.send_cast_spell(spell_id, target_id, tx, ty)
	# Apply cooldown immediately so the hotbar dims and further key presses are
	# blocked until the cooldown expires. The server will reject a duplicate cast
	# anyway, but this prevents the UI from appearing "ready" while waiting.
	var sp: Dictionary = GameData.get_spell(spell_id)
	var cd: float = sp.get("cooldown", 1.0)
	PlayerState.set_spell_cooldown(spell_id, cd)
	PlayerState.spell_cast_started.emit(spell_id)


func _on_aoe_aim_requested(spell_id: int) -> void:
	## Hotbar GROUND_AOE spell pressed — left/right-click ground to fire.
	_aoe_aim_spell = spell_id
	var sp := GameData.get_spell(spell_id)
	var sname: String = sp.get("name", "Spell")
	if _hud_ui != null:
		(_hud_ui as HudUI).show_aim_mode("◎  CLICK GROUND: " + sname)
	if _spell_hotbar_ui != null and _spell_hotbar_ui.has_method("show_aim_mode"):
		_spell_hotbar_ui.show_aim_mode(sname, "ground")


func _on_single_aim_requested(spell_id: int) -> void:
	## Hotbar SINGLE_ENEMY/ALLY spell pressed — left-click an NPC to fire.
	_pending_cast_spell = spell_id
	var sp := GameData.get_spell(spell_id)
	var sname: String = sp.get("name", "Spell")
	if _hud_ui != null:
		(_hud_ui as HudUI).show_aim_mode("✦  CLICK TARGET: " + sname)
	if _spell_hotbar_ui != null and _spell_hotbar_ui.has_method("show_aim_mode"):
		_spell_hotbar_ui.show_aim_mode(sname, "target")


func _on_context_spell_cast(spell_id: int, target_id: int) -> void:
	## Right-click context menu: cast SINGLE_ENEMY spell on a specific NPC.
	_do_cast_spell(spell_id, target_id, 0, 0)


func _on_spell_cast_requested(spell_id: int, target_id: int, tx: int, ty: int) -> void:
	## Forwarded from SpellHotbarUI for SELF / SELF_AOE spells.
	_do_cast_spell(spell_id, target_id, tx, ty)


func _on_spell_shop(spells: Array) -> void:
	## Received spell shop list from server (via Arcane Vendor interaction).
	if _spell_hotbar_ui != null and _spell_hotbar_ui.has_method("open_spell_shop"):
		_spell_hotbar_ui.open_spell_shop(_last_shop_npc_id, spells)


func _on_net_title_update(instance_id: int, title: String) -> void:
	## Server assigned a title to a character — update their CharData name display.
	## instance_id matches the peer_id (players) or NPC instance_id used in _chars.
	if _chars.has(instance_id):
		var c: CharData = _chars[instance_id]
		if title.is_empty():
			var _old_prefix: String = _get_title_prefix(c.char_name)
			if not _old_prefix.is_empty():
				c.char_name = c.char_name.substr(_old_prefix.length())
		else:
			# Strip any existing title prefix then prepend new one
			var bare: String = _get_title_prefix(c.char_name)
			if bare.is_empty():
				c.char_name = "[" + title + "] " + c.char_name
			else:
				c.char_name = "[" + title + "] " + c.char_name.substr(bare.length())
		queue_redraw()


func _get_title_prefix(name: String) -> String:
	## Returns the "[Title] " prefix portion of a name, or "" if none.
	if name.begins_with("["):
		var end: int = name.find("] ")
		if end >= 0:
			return name.substr(0, end + 2)
	return ""


func _on_net_rare_drop(item_name: String, rarity: int, x: int, y: int) -> void:
	## Server notified us of a rare item drop — show colored chat notification.
	if _chat_ui == null:
		return
	var rarity_colors: Array = [
		Color.WHITE,
		Color(0.12, 0.85, 0.12),   # Uncommon — green
		Color(0.2,  0.5,  1.0),    # Rare — blue
		Color(1.0,  0.5,  0.0),    # Legendary — orange
	]
	var rarity_labels: Array = ["", "[Uncommon]", "[Rare]", "[LEGENDARY]"]
	var r: int = clampi(rarity, 0, 3)
	var msg: String = "%s %s dropped at (%d, %d)!" % [rarity_labels[r], item_name, x, y]
	_chat_ui.add_message(msg, rarity_colors[r])


func _on_enchant_requested(slot: int, item_name: String, enchant_level: int) -> void:
	if _enchanting_ui != null:
		_enchanting_ui.open(slot, item_name, enchant_level)


# ---------------------------------------------------------------------------
# Day / night lighting
# ---------------------------------------------------------------------------

func _on_net_time_of_day(hour: float) -> void:
	_time_of_day = hour


func _update_lighting() -> void:
	if _canvas_mod == null:
		return

	# --- Compute darkness 0.0 (full day) to 1.0 (full night) ---
	# Day:   06:00–19:00  → 0.0
	# Dusk:  19:00–21:00  → 0.0→1.0
	# Night: 21:00–05:00  → 1.0
	# Dawn:  05:00–06:00  → 1.0→0.0
	var darkness: float = 0.0
	var t: float = _time_of_day
	if t >= 6.0 and t < 19.0:
		darkness = 0.0
	elif t >= 19.0 and t < 21.0:
		darkness = (t - 19.0) / 2.0          # dusk ramp 0→1
	elif t >= 21.0 or t < 5.0:
		darkness = 1.0
	elif t >= 5.0 and t < 6.0:
		darkness = 1.0 - (t - 5.0)           # dawn ramp 1→0

	# Night sky tint: dark navy — min brightness 0.25 so the world is never pitch black
	var day_col   := Color(1.0,  1.0,  1.0,  1.0)
	var night_col := Color(0.25, 0.25, 0.35, 1.0)
	_canvas_mod.color = day_col.lerp(night_col, darkness)

	# Propagate darkness to minimap
	if _minimap != null and _minimap.has_method("set_darkness"):
		_minimap.set_darkness(darkness)

	# Player light — only visible when it's meaningfully dark
	if _player_light != null:
		var is_dark: bool = darkness > 0.15
		_player_light.visible = is_dark
		if is_dark:
			# Position at player's world-pixel centre
			var px: int = int(_cam_pixel.x)
			var py: int = int(_cam_pixel.y)
			_player_light.position = Vector2(float(px), float(py))

			# Radius from Night Sight stat (stored in PlayerState, updated on stat sync)
			var night_sight: int = PlayerState.stats.get("night_sight", 0)
			# base 3 tiles + 1 tile per night_sight point; scale drives radius
			var radius_tiles: float = 3.0 + float(night_sight)
			# texture is 256px wide; scale so it covers radius_tiles * TILE pixels
			_player_light.texture_scale = (radius_tiles * float(TILE)) / 128.0

			# Light dims as darkness deepens (full dark = full energy)
			_player_light.energy = lerpf(0.0, 1.8, darkness)


static func _make_light_texture(size: int) -> ImageTexture:
	## Generates a radial white→transparent gradient texture for PointLight2D.
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := Vector2(size * 0.5, size * 0.5)
	var r: float = size * 0.5
	for y in size:
		for x in size:
			var d: float = Vector2(x, y).distance_to(centre)
			var alpha: float = clampf(1.0 - (d / r), 0.0, 1.0)
			# Soften with a power curve so the edge fades smoothly
			alpha = pow(alpha, 1.8)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)
