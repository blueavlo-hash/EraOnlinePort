"""
Insert Step 2: Modify _ready() to init boss timers,
               Modify _process() to add boss/world-event/tourney ticks,
               Add C_ENCHANT and C_LEADERBOARD_REQUEST to _handle_game dispatch.
"""

FILE = r"C:\eo3\EraOnline\scripts\server\game_server.gd"

with open(FILE, "r", encoding="utf-8") as f:
    content = f.read()

# ---- 1. Add boss timer init in _ready() after _load_admin_list() ----
READY_END = """\t_load_admin_list()


func _process(delta: float) -> void:"""

READY_END_NEW = """\t_load_admin_list()

\t# Initialise boss timers with staggered initial spawns
\tfor boss_def in BOSS_DEFS:
\t\tvar mid: int = int(boss_def["map_id"])
\t\t_boss_timers[mid] = randf_range(
\t\t\t\tfloat(boss_def["spawn_interval"]) * 0.3,
\t\t\t\tfloat(boss_def["spawn_interval"]) * 0.7)
\t\t_boss_instances[mid] = 0


func _process(delta: float) -> void:"""

if "_boss_timers[mid]" not in content:
    content = content.replace(READY_END, READY_END_NEW, 1)
    print("Added boss timer init to _ready().")
else:
    print("Boss timer init already present, skipping.")

# ---- 2. Add boss/world-event/tourney ticks to _process() ----
# Insert after the housekeeping block (the last existing tick in _process)
HOUSEKEEP_BLOCK = """\t## Housekeeping: NPC respawns, status effects, ground items — throttled to 1 Hz
\t_housekeep_acc += delta
\tif _housekeep_acc >= HOUSEKEEP_INTERVAL:
\t\t_housekeep_acc = 0.0
\t\t_tick_housekeep(now)


# ---------------------------------------------------------------------------
# Housekeeping tick"""

HOUSEKEEP_BLOCK_NEW = """\t## Housekeeping: NPC respawns, status effects, ground items — throttled to 1 Hz
\t_housekeep_acc += delta
\tif _housekeep_acc >= HOUSEKEEP_INTERVAL:
\t\t_housekeep_acc = 0.0
\t\t_tick_housekeep(now)

\t## Boss spawn timers
\tfor _boss_map_id in _boss_timers.keys():
\t\t_boss_timers[_boss_map_id] -= delta
\t\tif _boss_timers[_boss_map_id] <= 0.0:
\t\t\t_try_spawn_boss(_boss_map_id)
\t\t\tbreak  # erase-safe: restart next frame

\t## World event tick
\tif not _world_event_active:
\t\t_world_event_acc += delta
\t\tif _world_event_acc >= WORLD_EVENT_INTERVAL:
\t\t\t_world_event_acc = 0.0
\t\t\t_start_world_event()
\telse:
\t\tif Time.get_ticks_msec() / 1000.0 >= _world_event_end_at:
\t\t\t_end_world_event("The invasion has been repelled!" if _world_event_npcs.is_empty() else "The monsters retreated into the darkness.")

\t## Fishing tournament tick
\tif not _tourney_active:
\t\t_tourney_acc += delta
\t\tif _tourney_acc >= TOURNEY_INTERVAL:
\t\t\t_tourney_acc = 0.0
\t\t\t_start_fishing_tourney()
\telse:
\t\tif Time.get_ticks_msec() / 1000.0 >= _tourney_end_at:
\t\t\t_end_fishing_tourney()


# ---------------------------------------------------------------------------
# Housekeeping tick"""

if "_try_spawn_boss" not in content:
    content = content.replace(HOUSEKEEP_BLOCK, HOUSEKEEP_BLOCK_NEW, 1)
    print("Added boss/world-event/tourney ticks to _process().")
else:
    print("Process ticks already present, skipping.")

# ---- 3. Add C_ENCHANT and C_LEADERBOARD_REQUEST to _handle_game dispatch ----
QUEST_TALK_DISPATCH = """\t\tC_QUEST_TALK:
\t\t\t_on_quest_talk(client, r.read_i32())

\t\tC_QUEST_ACCEPT:
\t\t\t_on_quest_accept(client, r.read_u16())

\t\tC_QUEST_TURNIN:
\t\t\t_on_quest_turnin(client, r.read_u16())


# ---------------------------------------------------------------------------
# Game actions"""

QUEST_TALK_DISPATCH_NEW = """\t\tC_QUEST_TALK:
\t\t\t_on_quest_talk(client, r.read_i32())

\t\tC_QUEST_ACCEPT:
\t\t\t_on_quest_accept(client, r.read_u16())

\t\tC_QUEST_TURNIN:
\t\t\t_on_quest_turnin(client, r.read_u16())

\t\tC_ENCHANT:
\t\t\t_on_enchant(client, r.read_u8(), r.read_u8())

\t\tC_LEADERBOARD_REQUEST:
\t\t\t_on_leaderboard_request(client, r.read_u8())


# ---------------------------------------------------------------------------
# Game actions"""

if "C_ENCHANT:" not in content:
    content = content.replace(QUEST_TALK_DISPATCH, QUEST_TALK_DISPATCH_NEW, 1)
    print("Added C_ENCHANT and C_LEADERBOARD_REQUEST to dispatch.")
else:
    print("Dispatch entries already present, skipping.")

with open(FILE, "w", encoding="utf-8") as f:
    f.write(content)

print("Step 2 complete.")
