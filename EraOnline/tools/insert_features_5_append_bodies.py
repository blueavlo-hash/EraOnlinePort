"""
Insert Step 5: Append the main new function bodies that were called but not yet defined.
These functions had their *calls* inserted in previous steps but the function bodies
were incorrectly skipped because the calls made them appear 'already present'.
"""

FILE = r"C:\eo3\EraOnline\scripts\server\game_server.gd"

with open(FILE, "r", encoding="utf-8") as f:
    content = f.read()

NEW_BODIES = ""

# ---- Broadcast helpers ----
if "func _broadcast_all_connected(" not in content:
    NEW_BODIES += """

# ---------------------------------------------------------------------------
# Broadcast helpers (addiction loop systems)
# ---------------------------------------------------------------------------

func _broadcast_all_connected(msg_type: int, bytes: PackedByteArray) -> void:
\t## Sends a message to every connected player on the server.
\tfor _bac_pid in _clients:
\t\tvar _bac_cl = _clients[_bac_pid]
\t\tif _bac_cl.state == _ServerClientSCR.State.CONNECTED:
\t\t\t_bac_cl.send_auth(msg_type, bytes)


func _send_server_msg_to_map(map_id: int, message: String) -> void:
\t## Sends a server message string to all connected players on a given map.
\tvar _mw := NetProtocol.PacketWriter.new()
\t_mw.write_str(message)
\tfor _mm_pid in _clients:
\t\tvar _mm_cl = _clients[_mm_pid]
\t\tif _mm_cl.state == _ServerClientSCR.State.CONNECTED and _mm_cl.char.get("map_id", -1) == map_id:
\t\t\t_mm_cl.send_auth(NetProtocol.MsgType.S_SERVER_MSG, _mw.get_bytes())
"""

# ---- Feature 2: Boss Monster Spawns ----
if "func _try_spawn_boss(" not in content:
    NEW_BODIES += """

# ---------------------------------------------------------------------------
# Feature 2: Boss Monster Spawns
# ---------------------------------------------------------------------------

func _try_spawn_boss(map_id: int) -> void:
\t## Attempts to spawn the boss for the given map_id.
\tvar boss_def: Dictionary = {}
\tfor _bd in BOSS_DEFS:
\t\tif int(_bd["map_id"]) == map_id:
\t\t\tboss_def = _bd
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

\tvar safe_pos: Vector2i = _find_safe_spawn(map_id, 50, 50)
\tvar npc_index: int = int(boss_def["npc_index"])
\tvar boss_name: String = boss_def.get("name", "Boss")

\t_spawn_npc_at(map_id, npc_index, safe_pos.x, safe_pos.y)

\tvar new_instance_id: int = _npc_counter - 1
\tif _npcs.has(new_instance_id):
\t\tvar boss_npc: Dictionary = _npcs[new_instance_id]
\t\tboss_npc["hp"]      = boss_npc["max_hp"] * 3
\t\tboss_npc["max_hp"]  = boss_npc["max_hp"] * 3
\t\tboss_npc["min_hit"] = boss_npc["min_hit"] * 2
\t\tboss_npc["max_hit"] = boss_npc["max_hit"] * 2
\t\tboss_npc["data"]["is_boss"]   = true
\t\tboss_npc["data"]["boss_name"] = boss_name
\t\t_boss_instances[map_id] = new_instance_id

\tvar map_data := GameData.get_map(map_id)
\tvar map_name: String = "the wilderness"
\tif not map_data.is_empty():
\t\tmap_name = map_data.get("name", "the wilderness")
\t_send_server_msg_to_map(map_id,
\t\t\t"A powerful boss has appeared: %s on %s! Seek it out for great rewards!" % [boss_name, map_name])

\tvar sw := NetProtocol.PacketWriter.new()
\tsw.write_str("A powerful boss has appeared somewhere in the world...")
\t_broadcast_all_connected(NetProtocol.MsgType.S_SERVER_MSG, sw.get_bytes())
\t_boss_timers[map_id] = float(boss_def["spawn_interval"])
\tprint("[Boss] Spawned %s (instance %d) on map %d" % [boss_name, new_instance_id, map_id])
"""

# ---- Feature 3: Achievement System ----
if "func _check_achievements(" not in content:
    NEW_BODIES += """

# ---------------------------------------------------------------------------
# Feature 3: Achievement System
# ---------------------------------------------------------------------------

func _check_achievements(client, event: String, value: int) -> void:
\t## Checks and awards newly unlocked achievements for the given event.
\t## value=0 is a sentinel meaning read the current value from char_dict directly.
\tvar char_dict: Dictionary = client.char
\tif not char_dict.has("achievement_progress"):
\t\tchar_dict["achievement_progress"] = {}
\tvar progress: Dictionary = char_dict["achievement_progress"]
\tif not char_dict.has("achievements"):
\t\tchar_dict["achievements"] = []
\tvar unlocked: Array = char_dict["achievements"]

\tvar actual_value: int = value
\tif value > 0:
\t\tprogress[event] = int(progress.get(event, 0)) + value
\t\tactual_value = int(progress[event])
\telse:
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
\t\t_send_server_msg(client, "Achievement Unlocked: %s!" % ach_d.get("name", ""))
\t\t_send_stats(client)

\tchar_dict["achievement_progress"] = progress
\tchar_dict["achievements"] = unlocked
\t_update_title(client)
"""

# ---- Feature 5: Item Enchanting ----
if "func _on_enchant(" not in content:
    NEW_BODIES += """

# ---------------------------------------------------------------------------
# Feature 5: Item Enchanting
# ---------------------------------------------------------------------------

func _on_enchant(client, item_slot: int, mat_slot: int) -> void:
\t## Handles the C_ENCHANT message.
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

\tvar item_obj: Dictionary = GameData.get_object(int(item.get("obj_index", 0)))
\tvar item_obj_type: int = int(item_obj.get("obj_type", 0))
\tconst ENCHANTABLE_TYPES_LOCAL: Array = [1, 2, 3, 4, 5, 6, 7, 8]
\tif item_obj_type not in ENCHANTABLE_TYPES_LOCAL:
\t\t_send_server_msg(client, "This item cannot be enchanted.")
\t\treturn

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

\tmat["amount"] = mat_amount - required
\tif int(mat["amount"]) <= 0:
\t\tinv[mat_slot] = {}
\tchar_dict["inventory"] = inv

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
\t\tvar prog: Dictionary = char_dict.get("achievement_progress", {})
\t\tprog["enchant3"] = int(prog.get("enchant3", 0)) + 1
\t\tchar_dict["achievement_progress"] = prog
\t\t_check_achievements(client, "enchant3", 0)

\t_db.save_char(client.username, char_dict)
"""

# ---- Feature 6: Daily Login Streak ----
if "func _check_daily_login(" not in content:
    NEW_BODIES += """

# ---------------------------------------------------------------------------
# Feature 6: Daily Login Streak
# ---------------------------------------------------------------------------

func _check_daily_login(client) -> void:
\tvar char_dict: Dictionary = client.char
\tvar today: String = Time.get_date_string_from_system()
\tvar last_login: String = char_dict.get("last_login_date", "")
\tvar streak: int = int(char_dict.get("login_streak", 0))

\tif last_login == today:
\t\treturn

\tvar yesterday: String = _date_yesterday()
\tif last_login != yesterday:
\t\tstreak = 0

\tstreak = mini(streak + 1, 7)
\tchar_dict["login_streak"] = streak
\tchar_dict["last_login_date"] = today

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
\tvar unix_now: int = int(Time.get_unix_time_from_system())
\tvar unix_yesterday: int = unix_now - 86400
\tvar dt: Dictionary = Time.get_datetime_dict_from_unix_time(unix_yesterday)
\treturn "%04d-%02d-%02d" % [int(dt.year), int(dt.month), int(dt.day)]
"""

# ---- Feature 7: World Events / Invasions ----
if "func _start_world_event(" not in content:
    NEW_BODIES += """

# ---------------------------------------------------------------------------
# Feature 7: World Events / Invasions
# ---------------------------------------------------------------------------

func _start_world_event() -> void:
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

# ---- Feature 9: Leaderboards ----
if "func _update_leaderboard(" not in content:
    NEW_BODIES += """

# ---------------------------------------------------------------------------
# Feature 9: Leaderboards
# ---------------------------------------------------------------------------

func _update_leaderboard(category: String, name: String, score: int) -> void:
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
if "func _start_fishing_tourney(" not in content:
    NEW_BODIES += """

# ---------------------------------------------------------------------------
# Feature 10: Fishing Tournament
# ---------------------------------------------------------------------------

func _start_fishing_tourney() -> void:
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
\t\t\t\t\t\t"You placed %d in the Fishing Tournament! Prize: %d gold!" % [i + 1, prize_gold])
\t\tvar place_str: String = ["1st", "2nd", "3rd"][i]
\t\twinner_msgs.append("%s: %s (%d)" % [place_str, e.get("name", "?"), int(e.get("score", 0))])
\t_broadcast_all_connected(S_TOURNEY_END, ew.get_bytes())

\tvar result_text: String = "Fishing Tournament Over! " + (", ".join(winner_msgs) if not winner_msgs.is_empty() else "No participants.")
\tvar rw := NetProtocol.PacketWriter.new()
\trw.write_str(result_text)
\t_broadcast_all_connected(NetProtocol.MsgType.S_SERVER_MSG, rw.get_bytes())
\t_tourney_scores.clear()
\tprint("[Tourney] Fishing tournament ended.")
"""

if NEW_BODIES:
    content = content.rstrip() + "\n" + NEW_BODIES + "\n"
    with open(FILE, "w", encoding="utf-8") as f:
        f.write(content)
    print("Appended missing function bodies.")
else:
    print("All function bodies already present.")

# Final verification
with open(FILE, "r", encoding="utf-8") as f:
    final_content = f.read()

funcs_to_check = [
    "func _broadcast_all_connected(",
    "func _send_server_msg_to_map(",
    "func _try_spawn_boss(",
    "func _check_achievements(",
    "func _on_enchant(",
    "func _check_daily_login(",
    "func _date_yesterday(",
    "func _start_world_event(",
    "func _end_world_event(",
    "func _update_leaderboard(",
    "func _on_leaderboard_request(",
    "func _start_fishing_tourney(",
    "func _broadcast_tourney_scores(",
    "func _end_fishing_tourney(",
]

missing = [f for f in funcs_to_check if f not in final_content]
if missing:
    print("STILL MISSING:")
    for m in missing:
        print("  -", m)
else:
    print("All function definitions verified present!")

print("Final line count:", final_content.count('\n'))
