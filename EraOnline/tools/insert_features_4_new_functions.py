"""
Insert Step 4: Append all new functions to end of game_server.gd
"""

FILE = r"C:\eo3\EraOnline\scripts\server\game_server.gd"

with open(FILE, "r", encoding="utf-8") as f:
    content = f.read()

# Check what's already there
already_has = {
    "_rarity_suffix": "_rarity_suffix" in content,
    "_try_spawn_boss": "_try_spawn_boss" in content,
    "_check_achievements": "_check_achievements" in content,
    "_send_bounty_board": "_send_bounty_board" in content,
    "_on_enchant": "_on_enchant" in content,
    "_check_daily_login": "_check_daily_login" in content,
    "_start_world_event": "_start_world_event" in content,
    "_update_title": "_update_title" in content,
    "_update_leaderboard": "_update_leaderboard" in content,
    "_on_leaderboard_request": "_on_leaderboard_request" in content,
    "_start_fishing_tourney": "_start_fishing_tourney" in content,
    "_broadcast_all_connected": "_broadcast_all_connected" in content,
    "_send_server_msg_to_map": "_send_server_msg_to_map" in content,
    "_broadcast_tourney_scores": "_broadcast_tourney_scores" in content,
}

print("Already present:", {k: v for k, v in already_has.items() if v})
print("Need to add:", {k: v for k, v in already_has.items() if not v})

NEW_FUNCTIONS = ""

# ---- Helper: _broadcast_all_connected ----
if not already_has["_broadcast_all_connected"]:
    NEW_FUNCTIONS += """

# ---------------------------------------------------------------------------
# Broadcast helpers
# ---------------------------------------------------------------------------

func _broadcast_all_connected(msg_type: int, bytes: PackedByteArray) -> void:
\t## Sends a message to every connected player on the server.
\tfor pid in _clients:
\t\tvar cl = _clients[pid]
\t\tif cl.state == _ServerClientSCR.State.CONNECTED:
\t\t\tcl.send_auth(msg_type, bytes)


func _send_server_msg_to_map(map_id: int, message: String) -> void:
\t## Sends a server message string to all connected players on a given map.
\tvar w := NetProtocol.PacketWriter.new()
\tw.write_str(message)
\tfor pid in _clients:
\t\tvar cl = _clients[pid]
\t\tif cl.state == _ServerClientSCR.State.CONNECTED and cl.char.get("map_id", -1) == map_id:
\t\t\tcl.send_auth(NetProtocol.MsgType.S_SERVER_MSG, w.get_bytes())
"""

# ---- Feature 1: Loot Rarity ----
if not already_has["_rarity_suffix"]:
    NEW_FUNCTIONS += """

# ---------------------------------------------------------------------------
# Feature 1: Loot Rarity System
# ---------------------------------------------------------------------------

func _rarity_suffix(rarity: int) -> String:
\tmatch rarity:
\t\t1: return " [Uncommon]"
\t\t2: return " [Rare]"
\t\t3: return " [LEGENDARY]"
\treturn ""


func _roll_item_rarity() -> int:
\t## Returns 0=Common, 1=Uncommon, 2=Rare, 3=Legendary
\tvar r := randf()
\tif r < 0.01:   return 3  # 1%
\tif r < 0.08:   return 2  # 7%
\tif r < 0.25:   return 1  # 17%
\treturn 0                  # 75%


func _apply_item_rarity(item_dict: Dictionary, obj_data: Dictionary, map_id: int, x: int, y: int) -> void:
\t## Rolls rarity on a dropped item, modifies its value multiplier, and notifies map.
\tvar rarity: int = _roll_item_rarity()
\titem_dict["rarity"] = rarity
\tif rarity == 0:
\t\treturn
\tvar obj_name: String = obj_data.get("name", "item")
\tvar rw := NetProtocol.PacketWriter.new()
\trw.write_str(obj_name + _rarity_suffix(rarity))
\trw.write_u8(rarity)
\trw.write_i16(x)
\trw.write_i16(y)
\t_broadcast_map(map_id, S_RARE_DROP_NOTIFY, rw.get_bytes())
"""

# ---- Feature 2: Boss Monster Spawns ----
if not already_has["_try_spawn_boss"]:
    NEW_FUNCTIONS += """

# ---------------------------------------------------------------------------
# Feature 2: Boss Monster Spawns
# ---------------------------------------------------------------------------

func _try_spawn_boss(map_id: int) -> void:
\t## Attempts to spawn the boss for the given map_id.
\tvar boss_def: Dictionary = {}
\tfor bd in BOSS_DEFS:
\t\tif int(bd["map_id"]) == map_id:
\t\t\tboss_def = bd
\t\t\tbreak
\tif boss_def.is_empty():
\t\t_boss_timers.erase(map_id)
\t\treturn

\t# Check if already spawned and alive
\tif _boss_instances.get(map_id, 0) != 0:
\t\tvar existing_id: int = int(_boss_instances[map_id])
\t\tif _npcs.has(existing_id) and _npcs[existing_id]["ai_state"] != "dead":
\t\t\t_boss_timers[map_id] = float(boss_def["spawn_interval"])
\t\t\treturn

\t# Find a safe spawn near map center
\tvar safe_pos: Vector2i = _find_safe_spawn(map_id, 50, 50)
\tvar npc_index: int = int(boss_def["npc_index"])
\tvar boss_name: String = boss_def.get("name", "Boss")
\tvar loot_bonus: int = int(boss_def.get("loot_bonus", 1))

\t# Spawn with boosted stats — we spawn normally then override HP/combat stats
\t_spawn_npc_at(map_id, npc_index, safe_pos.x, safe_pos.y)

\t# The newly spawned NPC is _npc_counter - 1
\tvar new_instance_id: int = _npc_counter - 1
\tif _npcs.has(new_instance_id):
\t\tvar boss_npc: Dictionary = _npcs[new_instance_id]
\t\tboss_npc["hp"]      = boss_npc["max_hp"] * 3
\t\tboss_npc["max_hp"]  = boss_npc["max_hp"] * 3
\t\tboss_npc["min_hit"] = boss_npc["min_hit"] * 2
\t\tboss_npc["max_hit"] = boss_npc["max_hit"] * 2
\t\tboss_npc["data"]["is_boss"]    = true
\t\tboss_npc["data"]["boss_name"]  = boss_name
\t\tboss_npc["data"]["loot_bonus"] = loot_bonus
\t\t_boss_instances[map_id] = new_instance_id

\t# Notify players on the map
\tvar map_data := GameData.get_map(map_id)
\tvar map_name: String = map_data.get("name", "the wilderness") if not map_data.is_empty() else "the wilderness"
\t_send_server_msg_to_map(map_id,
\t\t\t"A powerful boss has appeared: %s on %s! Seek it out for great rewards!" % [boss_name, map_name])

\t# Server-wide announcement
\tvar sw := NetProtocol.PacketWriter.new()
\tsw.write_str("A powerful boss has appeared somewhere in the world...")
\t_broadcast_all_connected(NetProtocol.MsgType.S_SERVER_MSG, sw.get_bytes())

\t# Reset spawn timer
\t_boss_timers[map_id] = float(boss_def["spawn_interval"])
\tprint("[Boss] Spawned %s (instance %d) on map %d" % [boss_name, new_instance_id, map_id])
"""

# ---- Feature 3: Achievement System ----
if not already_has["_check_achievements"]:
    NEW_FUNCTIONS += """

# ---------------------------------------------------------------------------
# Feature 3: Achievement System
# ---------------------------------------------------------------------------

func _check_achievements(client, event: String, value: int) -> void:
\t## Checks and awards any newly unlocked achievements for the given event.
\t## value=0 is a sentinel for events where we read the current value directly.
\tvar char_dict: Dictionary = client.char
\tif not char_dict.has("achievement_progress"):
\t\tchar_dict["achievement_progress"] = {}
\tvar progress: Dictionary = char_dict["achievement_progress"]
\tif not char_dict.has("achievements"):
\t\tchar_dict["achievements"] = []
\tvar unlocked: Array = char_dict["achievements"]

\t# Determine actual value
\tvar actual_value: int = value
\tif value > 0:
\t\tprogress[event] = int(progress.get(event, 0)) + value
\t\tactual_value = int(progress[event])
\telse:
\t\t# Read current value from char_dict directly for gold/level/maps
\t\tmatch event:
\t\t\t"gold":   actual_value = int(char_dict.get("gold", 0))
\t\t\t"level":  actual_value = int(char_dict.get("level", 1))
\t\t\t"maps":   actual_value = char_dict.get("visited_maps", []).size()
\t\t\t_:        actual_value = int(progress.get(event, 0))
\t\tprogress[event] = actual_value

\tfor ach in ACHIEVEMENTS:
\t\tvar ach_d: Dictionary = ach as Dictionary
\t\tif ach_d.get("event", "") != event:
\t\t\tcontinue
\t\tvar ach_id: int = int(ach_d["id"])
\t\tif ach_id in unlocked:
\t\t\tcontinue
\t\tif actual_value < int(ach_d["threshold"]):
\t\t\tcontinue
\t\t# Award achievement
\t\tunlocked.append(ach_id)
\t\tvar ach_gold: int = int(ach_d.get("gold", 0))
\t\tvar ach_xp: int   = int(ach_d.get("xp", 0))
\t\tif ach_gold > 0:
\t\t\tchar_dict["gold"] = int(char_dict.get("gold", 0)) + ach_gold
\t\tif ach_xp > 0:
\t\t\tchar_dict["xp"] = int(char_dict.get("xp", 0)) + ach_xp
\t\t\t_ServerCombatSCR.try_level_up(char_dict)
\t\tvar ach_w := NetProtocol.PacketWriter.new()
\t\tach_w.write_u16(ach_id)
\t\tach_w.write_str(ach_d.get("name", ""))
\t\tach_w.write_str(ach_d.get("desc", ""))
\t\tach_w.write_i32(ach_gold)
\t\tach_w.write_i32(ach_xp)
\t\tclient.send_auth(S_ACHIEVEMENT_UNLOCK, ach_w.get_bytes())
\t\t_send_server_msg(client,
\t\t\t\t"Achievement Unlocked: %s!" % ach_d.get("name", ""))
\t\t_send_stats(client)

\tchar_dict["achievement_progress"] = progress
\tchar_dict["achievements"] = unlocked

\t# Check for new titles
\t_update_title(client)
"""

# ---- Feature 4: Bounty/Wanted System (helpers) ----
if not already_has["_send_bounty_board"]:
    NEW_FUNCTIONS += """

# ---------------------------------------------------------------------------
# Feature 4: Bounty / Wanted System
# ---------------------------------------------------------------------------

func _send_bounty_board(client) -> void:
\t## Sends the top 5 most-wanted players as server messages.
\tvar bounties: Array = []
\tfor pid in _clients:
\t\tvar cl = _clients[pid]
\t\tif cl.state == _ServerClientSCR.State.CONNECTED:
\t\t\tvar b: int = int(cl.char.get("bounty", 0))
\t\t\tif b > 0:
\t\t\t\tbounties.append({"name": cl.char.get("name", "?"), "bounty": b})
\tbounties.sort_custom(func(a, b): return int(a["bounty"]) > int(b["bounty"]))
\t_send_server_msg(client, "=== Most Wanted ===")
\tif bounties.is_empty():
\t\t_send_server_msg(client, "No outlaws at large.")
\t\treturn
\tvar limit: int = mini(5, bounties.size())
\tfor i in limit:
\t\tvar entry: Dictionary = bounties[i] as Dictionary
\t\t_send_server_msg(client,
\t\t\t\t"%d. %s — %d gold" % [i + 1, entry.get("name", "?"), int(entry.get("bounty", 0))])
"""

# ---- Feature 5: Item Enchanting ----
if not already_has["_on_enchant"]:
    NEW_FUNCTIONS += """

# ---------------------------------------------------------------------------
# Feature 5: Item Enchanting
# ---------------------------------------------------------------------------

func _on_enchant(client, item_slot: int, mat_slot: int) -> void:
\t## Handles the C_ENCHANT message: enchant item at item_slot using material at mat_slot.
\tvar char_dict: Dictionary = client.char
\tvar inv: Array = char_dict.get("inventory", [])
\twhile inv.size() < 20:
\t\tinv.append({})

\tif item_slot < 0 or item_slot >= inv.size() or mat_slot < 0 or mat_slot >= inv.size():
\t\t_send_server_msg(client, "Invalid slot.")
\t\treturn
\tif item_slot == mat_slot:
\t\t_send_server_msg(client, "Item and material cannot be the same slot.")
\t\treturn

\tvar item: Dictionary = inv[item_slot] as Dictionary
\tvar mat:  Dictionary = inv[mat_slot]  as Dictionary
\tif item.is_empty():
\t\t_send_server_msg(client, "No item in that slot.")
\t\treturn
\tif mat.is_empty():
\t\t_send_server_msg(client, "No material in that slot.")
\t\treturn

\t# Validate item is a weapon or armour (obj_type 1-5 cover combat gear in EO3)
\tvar item_obj: Dictionary = GameData.get_object(int(item.get("obj_index", 0)))
\tvar item_obj_type: int = int(item_obj.get("obj_type", 0))
\tconst ENCHANTABLE_TYPES: Array = [1, 2, 3, 4, 5, 6, 7, 8]  # weapon/armour/shield types
\tif item_obj_type not in ENCHANTABLE_TYPES:
\t\t_send_server_msg(client, "This item cannot be enchanted.")
\t\treturn

\t# Validate material type
\tvar mat_obj: Dictionary = GameData.get_object(int(mat.get("obj_index", 0)))
\tvar mat_obj_type: int = int(mat_obj.get("obj_type", 0))
\tif mat_obj_type not in ENCHANT_MATERIAL_OBJ_TYPES:
\t\t_send_server_msg(client, "That is not a valid enchanting material.")
\t\treturn

\tvar enchant_level: int = int(item.get("enchant_level", 0))
\tif enchant_level >= 4:
\t\t_send_server_msg(client, "This item is already at maximum enchantment (+4).")
\t\treturn

\tvar required: int = ENCHANT_MATERIAL_REQUIRED[enchant_level]
\tvar mat_amount: int = int(mat.get("amount", 0))
\tif mat_amount < required:
\t\t_send_server_msg(client,
\t\t\t\t"You need %d %s but only have %d." % [required, mat_obj.get("name", "material"), mat_amount])
\t\treturn

\t# Consume materials
\tmat["amount"] = mat_amount - required
\tif int(mat["amount"]) <= 0:
\t\tinv[mat_slot] = {}
\tchar_dict["inventory"] = inv

\t# Roll enchantment result
\tvar success_roll := randf()
\tvar new_level: int = enchant_level
\tvar result_code: int = 0
\tvar result_msg: String = ""

\tif success_roll < ENCHANT_SUCCESS_RATES[enchant_level]:
\t\tnew_level = enchant_level + 1
\t\titem["enchant_level"] = new_level
\t\tresult_code = 1
\t\tresult_msg = "+%d enchantment applied!" % new_level
\telif success_roll < ENCHANT_SUCCESS_RATES[enchant_level] + ENCHANT_BREAK_CHANCE[enchant_level]:
\t\tinv[item_slot] = {}
\t\tchar_dict["inventory"] = inv
\t\tresult_code = 2
\t\tresult_msg = "The item shattered!"
\telse:
\t\tresult_code = 0
\t\tresult_msg = "The enchantment failed... try again."

\tvar ew := NetProtocol.PacketWriter.new()
\tew.write_u8(result_code)
\tew.write_u8(new_level)
\tew.write_str(result_msg)
\tclient.send_auth(S_ENCHANT_RESULT, ew.get_bytes())
\t_send_inventory(client)

\tif result_code == 1 and new_level >= 3:
\t\t_check_achievements(client, "enchant3", 0)
\t\tvar prog: Dictionary = char_dict.get("achievement_progress", {})
\t\tprog["enchant3"] = int(prog.get("enchant3", 0)) + 1
\t\tchar_dict["achievement_progress"] = prog

\t_db.save_char(client.username, char_dict)
"""

# ---- Feature 6: Daily Login Streak ----
if not already_has["_check_daily_login"]:
    NEW_FUNCTIONS += """

# ---------------------------------------------------------------------------
# Feature 6: Daily Login Streak
# ---------------------------------------------------------------------------

func _check_daily_login(client) -> void:
\tvar char_dict: Dictionary = client.char
\tvar today: String = Time.get_date_string_from_system()
\tvar last_login: String = char_dict.get("last_login_date", "")
\tvar streak: int = int(char_dict.get("login_streak", 0))

\tif last_login == today:
\t\treturn  # Already logged in today

\t# Check if streak continues (logged in yesterday) or resets
\tvar yesterday: String = _date_yesterday()
\tif last_login != yesterday:
\t\tstreak = 0  # Streak broken

\tstreak = mini(streak + 1, 7)
\tchar_dict["login_streak"] = streak
\tchar_dict["last_login_date"] = today

\t# Rewards by streak day
\tvar rewards: Array = [
\t\t{"gold": 50,  "msg": "Day 1 login bonus: 50 gold!"},
\t\t{"gold": 75,  "msg": "Day 2 streak: 75 gold!"},
\t\t{"gold": 100, "msg": "Day 3 streak: 100 gold!"},
\t\t{"gold": 125, "msg": "Day 4 streak: 125 gold!"},
\t\t{"gold": 150, "msg": "Day 5 streak: 150 gold!"},
\t\t{"gold": 200, "msg": "Day 6 streak: 200 gold!"},
\t\t{"gold": 500, "msg": "7-DAY STREAK! 500 gold reward! Keep it up!"},
\t]
\tvar reward: Dictionary = rewards[streak - 1] as Dictionary
\tvar gold_reward: int = int(reward["gold"])
\tchar_dict["gold"] = int(char_dict.get("gold", 0)) + gold_reward

\tvar w := NetProtocol.PacketWriter.new()
\tw.write_u8(streak)
\tw.write_i32(gold_reward)
\tw.write_str(reward.get("msg", ""))
\tclient.send_auth(S_LOGIN_REWARD, w.get_bytes())

\t_send_stats(client)
\t_db.save_char(client.username, char_dict)


func _date_yesterday() -> String:
\t## Returns YYYY-MM-DD string for yesterday.
\tvar unix_now: int = int(Time.get_unix_time_from_system())
\tvar unix_yesterday: int = unix_now - 86400
\tvar dt: Dictionary = Time.get_datetime_dict_from_unix_time(unix_yesterday)
\treturn "%04d-%02d-%02d" % [int(dt.year), int(dt.month), int(dt.day)]
"""

# ---- Feature 7: World Events / Invasions ----
if not already_has["_start_world_event"]:
    NEW_FUNCTIONS += """

# ---------------------------------------------------------------------------
# Feature 7: World Events / Invasions
# ---------------------------------------------------------------------------

func _start_world_event() -> void:
\t## Starts a random world invasion event on a town map.
\tvar town_idx: int = randi() % WORLD_EVENT_TOWNS.size()
\tvar map_id: int = int(WORLD_EVENT_TOWNS[town_idx])
\tvar wave: Array = WORLD_EVENT_NPC_WAVES.get(map_id, [])

\t_world_event_npcs.clear()
\tfor npc_idx in wave:
\t\tvar safe_pos: Vector2i = _find_safe_spawn(map_id, randi_range(30, 70), randi_range(30, 70))
\t\t_spawn_npc_at(map_id, int(npc_idx), safe_pos.x, safe_pos.y)
\t\tvar new_nid: int = _npc_counter - 1
\t\tif _npcs.has(new_nid):
\t\t\t_npcs[new_nid]["data"]["world_event_npc"] = true
\t\t_world_event_npcs.append(new_nid)

\t_world_event_active = true
\t_world_event_map    = map_id
\t_world_event_end_at = Time.get_ticks_msec() / 1000.0 + 300.0

\tvar start_w := NetProtocol.PacketWriter.new()
\tstart_w.write_str("Monster Invasion")
\tstart_w.write_str("Town " + str(map_id))
\t_broadcast_all_connected(S_WORLD_EVENT_START, start_w.get_bytes())

\tvar announce_w := NetProtocol.PacketWriter.new()
\tannounce_w.write_str("INVASION! Monsters are attacking Town %d! Defend the town!" % map_id)
\t_broadcast_all_connected(NetProtocol.MsgType.S_SERVER_MSG, announce_w.get_bytes())
\tprint("[WorldEvent] Invasion started on map %d with %d NPCs" % [map_id, _world_event_npcs.size()])


func _end_world_event(result_msg: String) -> void:
\t## Ends the active world event, despawning remaining NPCs and notifying players.
\t# Despawn remaining event NPCs
\tfor nid in _world_event_npcs:
\t\tif _npcs.has(nid) and _npcs[nid]["ai_state"] != "dead":
\t\t\tvar ev_npc: Dictionary = _npcs[nid]
\t\t\tev_npc["ai_state"] = "dead"
\t\t\tvar rw := NetProtocol.PacketWriter.new()
\t\t\trw.write_i32(nid)
\t\t\t_broadcast_map(ev_npc["map_id"], NetProtocol.MsgType.S_REMOVE_CHAR, rw.get_bytes())

\tvar end_w := NetProtocol.PacketWriter.new()
\tend_w.write_str("Monster Invasion")
\tend_w.write_str(result_msg)
\t_broadcast_all_connected(S_WORLD_EVENT_END, end_w.get_bytes())

\tvar msg_w := NetProtocol.PacketWriter.new()
\tmsg_w.write_str(result_msg)
\t_broadcast_all_connected(NetProtocol.MsgType.S_SERVER_MSG, msg_w.get_bytes())

\t_world_event_active = false
\t_world_event_npcs.clear()
\tprint("[WorldEvent] Event ended: %s" % result_msg)
"""

# ---- Feature 8: Player Titles ----
if not already_has["_update_title"]:
    NEW_FUNCTIONS += """

# ---------------------------------------------------------------------------
# Feature 8: Player Titles
# ---------------------------------------------------------------------------

func _update_title(client) -> void:
\t## Checks for newly earned titles and updates char_dict if a new one is earned.
\tvar char_dict: Dictionary = client.char
\tvar progress: Dictionary = char_dict.get("achievement_progress", {})
\tvar new_title: String = ""

\t# Iterate in reverse so highest-threshold titles take priority
\tvar defs_copy: Array = TITLE_DEFS.duplicate()
\tdefs_copy.reverse()
\tfor td in defs_copy:
\t\tvar td_d: Dictionary = td as Dictionary
\t\tvar event: String    = td_d.get("event", "")
\t\tvar threshold: int   = int(td_d.get("threshold", 0))
\t\tvar current_val: int = 0
\t\tmatch event:
\t\t\t"gold":  current_val = int(char_dict.get("gold", 0))
\t\t\t"level": current_val = int(char_dict.get("level", 1))
\t\t\t"maps":  current_val = char_dict.get("visited_maps", []).size()
\t\t\t_:       current_val = int(progress.get(event, 0))
\t\tif current_val >= threshold:
\t\t\tnew_title = td_d.get("title", "")
\t\t\tbreak

\tif new_title.is_empty() or new_title == char_dict.get("title", ""):
\t\treturn

\tchar_dict["title"] = new_title
\tvar map_id: int = int(char_dict.get("map_id", 0))

\tvar tw := NetProtocol.PacketWriter.new()
\ttw.write_i32(client.peer_id)
\ttw.write_str(new_title)
\t_broadcast_map(map_id, S_TITLE_UPDATE, tw.get_bytes())
\t_send_server_msg(client, "You have earned the title [%s]!" % new_title)
\t_db.save_char(client.username, char_dict)
"""

# ---- Feature 9: Leaderboards ----
if not already_has["_update_leaderboard"]:
    NEW_FUNCTIONS += """

# ---------------------------------------------------------------------------
# Feature 9: Leaderboards
# ---------------------------------------------------------------------------

func _update_leaderboard(category: String, name: String, score: int) -> void:
\t## Updates a leaderboard category with the given player name and score.
\tif not _leaderboards.has(category):
\t\treturn
\tvar board: Array = _leaderboards[category]
\tvar found: bool = false
\tfor entry in board:
\t\tvar ed: Dictionary = entry as Dictionary
\t\tif ed.get("name", "") == name:
\t\t\tif score > int(ed.get("score", 0)):
\t\t\t\ted["score"] = score
\t\t\tfound = true
\t\t\tbreak
\tif not found:
\t\tboard.append({"name": name, "score": score})
\tboard.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
\tif board.size() > 10:
\t\tboard.resize(10)


func _on_leaderboard_request(client, type: int) -> void:
\t## Handles C_LEADERBOARD_REQUEST — sends leaderboard data to the requesting client.
\tvar categories: Array = ["kills", "crafts", "level", "fishing"]
\tif type < 0 or type >= categories.size():
\t\treturn
\tvar cat: String = categories[type] as String
\tvar board: Array = _leaderboards.get(cat, [])
\tvar lw := NetProtocol.PacketWriter.new()
\tlw.write_u8(type)
\tlw.write_u8(mini(board.size(), 255))
\tfor entry in board:
\t\tvar ed: Dictionary = entry as Dictionary
\t\tlw.write_str(ed.get("name", "?"))
\t\tlw.write_i32(int(ed.get("score", 0)))
\tclient.send_auth(S_LEADERBOARD_DATA, lw.get_bytes())
"""

# ---- Feature 10: Fishing Tournament ----
if not already_has["_start_fishing_tourney"]:
    NEW_FUNCTIONS += """

# ---------------------------------------------------------------------------
# Feature 10: Fishing Tournament
# ---------------------------------------------------------------------------

func _start_fishing_tourney() -> void:
\t## Begins a fishing tournament lasting TOURNEY_DURATION seconds.
\t_tourney_active = true
\t_tourney_scores.clear()
\t_tourney_end_at = Time.get_ticks_msec() / 1000.0 + TOURNEY_DURATION

\tvar tw := NetProtocol.PacketWriter.new()
\ttw.write_i32(int(TOURNEY_DURATION))
\ttw.write_str("Grand Fishing Trophy + %d gold!" % int(TOURNEY_PRIZES[0]))
\t_broadcast_all_connected(S_TOURNEY_START, tw.get_bytes())

\tvar aw := NetProtocol.PacketWriter.new()
\taw.write_str("FISHING TOURNAMENT STARTED! Best catch in 10 minutes wins %d gold!" % int(TOURNEY_PRIZES[0]))
\t_broadcast_all_connected(NetProtocol.MsgType.S_SERVER_MSG, aw.get_bytes())
\tprint("[Tourney] Fishing tournament started.")


func _broadcast_tourney_scores() -> void:
\t## Sends current top-5 tournament scores to all connected players.
\tvar scores_list: Array = []
\tfor pid in _tourney_scores:
\t\tvar entry: Dictionary = _tourney_scores[pid] as Dictionary
\t\tscores_list.append({"name": entry.get("name", "?"), "score": int(entry.get("best_catch", 0))})
\tscores_list.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
\tvar top_n: int = mini(5, scores_list.size())
\tvar sw := NetProtocol.PacketWriter.new()
\tsw.write_u8(top_n)
\tfor i in top_n:
\t\tvar e: Dictionary = scores_list[i] as Dictionary
\t\tsw.write_str(e.get("name", "?"))
\t\tsw.write_i32(int(e.get("score", 0)))
\t_broadcast_all_connected(S_TOURNEY_SCORES, sw.get_bytes())


func _end_fishing_tourney() -> void:
\t## Ends the fishing tournament and awards prizes.
\t_tourney_active = false

\tvar scores_list: Array = []
\tfor pid in _tourney_scores:
\t\tvar entry: Dictionary = _tourney_scores[pid] as Dictionary
\t\tscores_list.append({
\t\t\t"pid": pid,
\t\t\t"name": entry.get("name", "?"),
\t\t\t"score": int(entry.get("best_catch", 0))
\t\t})
\tscores_list.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))

\tvar award_count: int = mini(3, scores_list.size())
\tvar ew := NetProtocol.PacketWriter.new()
\tew.write_u8(award_count)
\tvar winner_msgs: Array = []
\tfor i in award_count:
\t\tvar e: Dictionary = scores_list[i] as Dictionary
\t\tvar prize_gold: int = int(TOURNEY_PRIZES[i])
\t\tew.write_str(e.get("name", "?"))
\t\tew.write_i32(int(e.get("score", 0)))
\t\tew.write_i32(prize_gold)
\t\tvar winner_pid: int = int(e.get("pid", 0))
\t\tif _clients.has(winner_pid):
\t\t\tvar wcl = _clients[winner_pid]
\t\t\tif wcl.state == _ServerClientSCR.State.CONNECTED:
\t\t\t\twcl.char["gold"] = int(wcl.char.get("gold", 0)) + prize_gold
\t\t\t\t_send_stats(wcl)
\t\t\t\t_send_server_msg(wcl,
\t\t\t\t\t\t"You won %d place in the Fishing Tournament! Prize: %d gold!" % [i + 1, prize_gold])
\t\tvar place_str: String = ["1st", "2nd", "3rd"][i]
\t\twinner_msgs.append("%s: %s (%d value)" % [place_str, e.get("name", "?"), int(e.get("score", 0))])
\t_broadcast_all_connected(S_TOURNEY_END, ew.get_bytes())

\tvar result_text: String = "Fishing Tournament Over! " + (", ".join(winner_msgs) if not winner_msgs.is_empty() else "No participants.")
\tvar rw := NetProtocol.PacketWriter.new()
\trw.write_str(result_text)
\t_broadcast_all_connected(NetProtocol.MsgType.S_SERVER_MSG, rw.get_bytes())

\t_tourney_scores.clear()
\tprint("[Tourney] Fishing tournament ended. Winners: %s" % str(winner_msgs))
"""

# ---- Add /wanted and /bounty and /top commands to _handle_admin_command ----
# These go in the public commands section (no role required), before the role >= 1 gate

if "_send_bounty_board" in NEW_FUNCTIONS or "_send_bounty_board" in content:
    WHISPER_CMD = """\t# Whisper — no role required
\tif cmd == "/w" or cmd == "/whisper":
\t\tif parts.size() < 3:
\t\t\t_send_server_msg(client, "Usage: /w <player> <message>")
\t\t\treturn
\t\tvar target_name_w: String = parts[1]
\t\tvar whisper_msg: String   = " ".join(parts.slice(2))
\t\t_send_whisper(client, target_name_w, whisper_msg)
\t\treturn

\t# All remaining commands require at least moderator role
\tif role < 1:"""

    WHISPER_CMD_NEW = """\t# Whisper — no role required
\tif cmd == "/w" or cmd == "/whisper":
\t\tif parts.size() < 3:
\t\t\t_send_server_msg(client, "Usage: /w <player> <message>")
\t\t\treturn
\t\tvar target_name_w: String = parts[1]
\t\tvar whisper_msg: String   = " ".join(parts.slice(2))
\t\t_send_whisper(client, target_name_w, whisper_msg)
\t\treturn

\t# /wanted and /top — public, no role required
\tif cmd == "/wanted":
\t\t_send_bounty_board(client)
\t\treturn

\tif cmd == "/top":
\t\t_send_server_msg(client, "=== Leaderboards ===")
\t\tvar lb_cats: Array = ["kills", "crafts", "level", "fishing"]
\t\tvar lb_labels: Array = ["Kills", "Crafts", "Level", "Fishing"]
\t\tfor li in lb_cats.size():
\t\t\tvar cat: String = lb_cats[li] as String
\t\t\tvar board: Array = _leaderboards.get(cat, [])
\t\t\t_send_server_msg(client, "-- Top %s --" % (lb_labels[li] as String))
\t\t\tvar show_n: int = mini(5, board.size())
\t\t\tif show_n == 0:
\t\t\t\t_send_server_msg(client, "(no data)")
\t\t\t\tcontinue
\t\t\tfor i in show_n:
\t\t\t\tvar e: Dictionary = board[i] as Dictionary
\t\t\t\t_send_server_msg(client, "  %d. %s — %d" % [i + 1, e.get("name", "?"), int(e.get("score", 0))])
\t\treturn

\t# All remaining commands require at least moderator role
\tif role < 1:"""

    if "/wanted" not in content:
        NEW_FUNCTIONS = NEW_FUNCTIONS  # Will be appended
        content = content.replace(WHISPER_CMD, WHISPER_CMD_NEW, 1)
        print("Added /wanted and /top commands.")
    else:
        print("/wanted already present, skipping.")

    # Also add /bounty command in admin section
    ADMIN_COMMANDS_MATCH = """\t\t"/ban", "/unban", "/give", "/giveto", "/gold", "/goldto", "/spawn", "/god", "/invis", "/map", "/tp", "/summon", "/level", "/setlevel", "/heal", "/healall", "/setadmin", "/setmod", "/demote", "/shutdown":"""
    ADMIN_COMMANDS_MATCH_NEW = """\t\t"/bounty":
\t\t\tif parts.size() < 2:
\t\t\t\t_send_server_msg(client, "Usage: /bounty <player>"); return
\t\t\tvar _find_by_name_b := func(n: String):
\t\t\t\tfor p in _clients:
\t\t\t\t\tvar cl = _clients[p]
\t\t\t\t\tif cl.state == _ServerClientSCR.State.CONNECTED and cl.char.get("name", "").to_lower() == n.to_lower():
\t\t\t\t\t\treturn cl
\t\t\t\treturn null
\t\t\tvar _bt = _find_by_name_b.call(parts[1])
\t\t\tif _bt == null:
\t\t\t\t_send_server_msg(client, "Player not found."); return
\t\t\tvar _bb: int = int(_bt.char.get("bounty", 0))
\t\t\t_send_server_msg(client, "%s has a bounty of %d gold." % [parts[1], _bb])

\t\t"/ban", "/unban", "/give", "/giveto", "/gold", "/goldto", "/spawn", "/god", "/invis", "/map", "/tp", "/summon", "/level", "/setlevel", "/heal", "/healall", "/setadmin", "/setmod", "/demote", "/shutdown":"""

    if '"/bounty":' not in content:
        content = content.replace(ADMIN_COMMANDS_MATCH, ADMIN_COMMANDS_MATCH_NEW, 1)
        print("Added /bounty command to admin section.")
    else:
        print("/bounty already present, skipping.")

# ---- Add world event NPC death hook into _npc_death ----
WORLD_EVENT_HOOK = """\t# Boss death handling
\tvar _boss_nid: int = npc["instance_id"]"""

if WORLD_EVENT_HOOK in content and "_world_event_npcs" not in content.split(WORLD_EVENT_HOOK)[1][:500]:
    WORLD_EVENT_NPC_CHECK = """\t# Boss death handling
\tvar _boss_nid: int = npc["instance_id"]"""
    WORLD_EVENT_NPC_CHECK_NEW = """\t# World event NPC death check
\tvar _ev_nid: int = npc["instance_id"]
\tif _ev_nid in _world_event_npcs:
\t\t_world_event_npcs.erase(_ev_nid)
\t\tif _world_event_npcs.is_empty() and _world_event_active:
\t\t\t_end_world_event("The town defenders were victorious! All monsters slain!")

\t# Boss death handling
\tvar _boss_nid: int = npc["instance_id"]"""
    content = content.replace(WORLD_EVENT_NPC_CHECK, WORLD_EVENT_NPC_CHECK_NEW, 1)
    print("Added world event NPC death hook.")
else:
    print("World event NPC death hook check - may already be present or anchor not found.")

# ---- Append all new functions at end of file ----
if NEW_FUNCTIONS:
    content = content.rstrip() + "\n" + NEW_FUNCTIONS + "\n"
    print("Appended new functions.")

with open(FILE, "w", encoding="utf-8") as f:
    f.write(content)

print("Step 4 complete.")
