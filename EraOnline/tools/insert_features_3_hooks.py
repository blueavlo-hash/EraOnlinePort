"""
Insert Step 3: Hook achievement/leaderboard/bounty/tournament calls into existing logic:
  - After NPC kill (in _npc_death)
  - After crafting (in _handle_blacksmithing and _complete_skill smelt/planks/cook branches)
  - After fishing (in _complete_skill default branch)
  - After level up (in _npc_death and _complete_skill)
  - After player-kills-player (in _handle_player_death)
  - _enter_world: add _check_daily_login and map achievement check
"""

FILE = r"C:\eo3\EraOnline\scripts\server\game_server.gd"

with open(FILE, "r", encoding="utf-8") as f:
    content = f.read()

# ---- 1. Hook into _npc_death after quest kill checks ----
NPC_DEATH_END = """\t# Quest kill progress (generic hostile kills)
\tif npc["data"].get("hostile", 0) != 0:
\t\t_check_kill_quests(killer)
\t# Quest kill_specific progress (name-matched kills for any NPC)
\t_check_specific_kill_quests(killer, npc["data"].get("name", ""))

\tprint("[Server] NPC %s (id=%d) killed by %s" % [
\t\tnpc["data"].get("name", "?"), npc["instance_id"],
\t\tkc.get("name", "?")])"""

NPC_DEATH_END_NEW = """\t# Quest kill progress (generic hostile kills)
\tif npc["data"].get("hostile", 0) != 0:
\t\t_check_kill_quests(killer)
\t# Quest kill_specific progress (name-matched kills for any NPC)
\t_check_specific_kill_quests(killer, npc["data"].get("name", ""))

\t# Achievements & leaderboards for NPC kills
\tif npc["data"].get("hostile", 0) != 0:
\t\t_check_achievements(killer, "kills", 1)
\t\t_update_leaderboard("kills", kc.get("name", "?"),
\t\t\t\tint(kc.get("achievement_progress", {}).get("kills", 0)))
\tif levelled_up:
\t\t_check_achievements(killer, "level", 0)
\t\t_update_leaderboard("level", kc.get("name", "?"), kc.get("level", 1))

\t# Boss death handling
\tvar _boss_nid: int = npc["instance_id"]
\tvar _boss_map_for_death: int = -1
\tfor _bm in _boss_instances.keys():
\t\tif _boss_instances[_bm] == _boss_nid:
\t\t\t_boss_map_for_death = _bm
\t\t\tbreak
\tif _boss_map_for_death >= 0:
\t\t_boss_instances.erase(_boss_map_for_death)
\t\t# Bonus XP for boss kill (x5)
\t\tvar boss_bonus_xp: int = xp_gain * 4  # already awarded xp_gain above
\t\tkc["xp"] = kc.get("xp", 0) + boss_bonus_xp
\t\t_ServerCombatSCR.try_level_up(kc)
\t\t_send_stats(killer)
\t\tvar _boss_name_death: String = npc["data"].get("name", "the boss")
\t\tvar _killer_name_death: String = kc.get("name", "a hero")
\t\tvar _bcast_boss_w := NetProtocol.PacketWriter.new()
\t\t_bcast_boss_w.write_str("The %s has been defeated by %s! Legendary treasure awaits!" % [
\t\t\t\t_boss_name_death, _killer_name_death])
\t\t_broadcast_all_connected(NetProtocol.MsgType.S_SERVER_MSG, _bcast_boss_w.get_bytes())

\tprint("[Server] NPC %s (id=%d) killed by %s" % [
\t\tnpc["data"].get("name", "?"), npc["instance_id"],
\t\tkc.get("name", "?")])"""

if "_check_achievements(killer, \"kills\"" not in content:
    content = content.replace(NPC_DEATH_END, NPC_DEATH_END_NEW, 1)
    print("Added achievement/boss hooks to _npc_death.")
else:
    print("NPC death hooks already present, skipping.")

# ---- 2. Hook achievements into _handle_blacksmithing after the forge ----
BLACKSMITH_END = """\tvar out_name: String = GameData.get_object(make_item).get("name", "item")
\t_send_server_msg(client, "You forge: %s!" % out_name)

\t# Award Blacksmithing skill XP
\t_award_skill_xp(client, char_dict, 9)
\t_db.save_char(client.username, char_dict)
\t# Quest craft progress
\t_check_craft_quests(client, "forge")"""

BLACKSMITH_END_NEW = """\tvar out_name: String = GameData.get_object(make_item).get("name", "item")
\t_send_server_msg(client, "You forge: %s!" % out_name)

\t# Award Blacksmithing skill XP
\t_award_skill_xp(client, char_dict, 9)
\t_db.save_char(client.username, char_dict)
\t# Quest craft progress
\t_check_craft_quests(client, "forge")
\t# Achievements & leaderboards for crafting
\t_check_achievements(client, "crafts", 1)
\t_update_leaderboard("crafts", char_dict.get("name", "?"),
\t\t\tint(char_dict.get("achievement_progress", {}).get("crafts", 0)))"""

if "_check_achievements(client, \"crafts\", 1)" not in content:
    content = content.replace(BLACKSMITH_END, BLACKSMITH_END_NEW, 1)
    print("Added achievement hooks to _handle_blacksmithing.")
else:
    print("Blacksmithing achievement hooks already present, skipping.")

# ---- 3. Hook achievements into _complete_skill smelt/planks/cook branches ----
SMELT_END = """\t\t\t_send_server_msg(client, "You smelt the ore into %d steel clumps." % SMELT_STEEL_YIELD)
\t\t\t# Quest craft progress
\t\t\t_check_craft_quests(client, "smelt")

\t\t"planks":"""

SMELT_END_NEW = """\t\t\t_send_server_msg(client, "You smelt the ore into %d steel clumps." % SMELT_STEEL_YIELD)
\t\t\t# Quest craft progress
\t\t\t_check_craft_quests(client, "smelt")
\t\t\t_check_achievements(client, "crafts", 1)
\t\t\t_update_leaderboard("crafts", char_dict.get("name", "?"),
\t\t\t\t\tint(char_dict.get("achievement_progress", {}).get("crafts", 0)))

\t\t"planks":"""

if '_check_achievements(client, "crafts", 1)\n\t\t\t_update_leaderboard("crafts"' not in content:
    content = content.replace(SMELT_END, SMELT_END_NEW, 1)
    print("Added achievement hooks to smelt branch.")
else:
    print("Smelt achievement hook already present, skipping.")

PLANKS_END = """\t\t\t_send_server_msg(client, "You cut the logs into %d planks." % PLANK_YIELD)
\t\t\t# Quest craft progress
\t\t\t_check_craft_quests(client, "planks")

\t\t"cook":"""

PLANKS_END_NEW = """\t\t\t_send_server_msg(client, "You cut the logs into %d planks." % PLANK_YIELD)
\t\t\t# Quest craft progress
\t\t\t_check_craft_quests(client, "planks")
\t\t\t_check_achievements(client, "crafts", 1)
\t\t\t_update_leaderboard("crafts", char_dict.get("name", "?"),
\t\t\t\t\tint(char_dict.get("achievement_progress", {}).get("crafts", 0)))

\t\t"cook":"""

if 'cut the logs' in content and '_check_achievements(client, "crafts", 1)\n\t\t\t_update_leaderboard("crafts", char_dict.get("name", "?"),\n\t\t\t\t\tint(char_dict.get("achievement_progress"' not in content:
    content = content.replace(PLANKS_END, PLANKS_END_NEW, 1)
    print("Added achievement hooks to planks branch.")
else:
    print("Planks achievement hook already present, skipping.")

COOK_END = """\t\t\t_send_server_msg(client, "You cook the food into %s." % cooked_name)
\t\t\t# Quest: cooking progress
\t\t\t_check_cook_quests(client)

\t\t_:
\t\t\t# Default gathering actions (lumberjacking, mining, fishing)"""

COOK_END_NEW = """\t\t\t_send_server_msg(client, "You cook the food into %s." % cooked_name)
\t\t\t# Quest: cooking progress
\t\t\t_check_cook_quests(client)
\t\t\t_check_achievements(client, "crafts", 1)
\t\t\t_update_leaderboard("crafts", char_dict.get("name", "?"),
\t\t\t\t\tint(char_dict.get("achievement_progress", {}).get("crafts", 0)))

\t\t_:
\t\t\t# Default gathering actions (lumberjacking, mining, fishing)"""

if 'cook the food' in content and '_check_achievements(client, "crafts", 1)\n\t\t\t_update_leaderboard("crafts", char_dict.get("name", "?"),\n\t\t\t\t\tint(char_dict.get("achievement_progress", {}).get("crafts"' not in content:
    content = content.replace(COOK_END, COOK_END_NEW, 1)
    print("Added achievement hooks to cook branch.")
else:
    print("Cook achievement hook already present, skipping.")

# ---- 4. Hook fishing achievements in the default gathering branch ----
FISHING_GATHER_END = """\t\t\tif yield_index > 0:
\t\t\t\t_give_item(char_dict, yield_index, yield_amount)
\t\t\t\t_send_inventory(client)
\t\t\t\tvar obj_name: String = GameData.get_object(yield_index).get("name", "item")
\t\t\t\t_send_server_msg(client, "You obtained: %s." % obj_name)
\t\t\t\t# Quest gather progress check
\t\t\t\t_check_gather_quests(client)"""

FISHING_GATHER_END_NEW = """\t\t\tif yield_index > 0:
\t\t\t\t_give_item(char_dict, yield_index, yield_amount)
\t\t\t\t_send_inventory(client)
\t\t\t\tvar obj_name: String = GameData.get_object(yield_index).get("name", "item")
\t\t\t\t_send_server_msg(client, "You obtained: %s." % obj_name)
\t\t\t\t# Quest gather progress check
\t\t\t\t_check_gather_quests(client)
\t\t\t\t# Achievements for fishing
\t\t\t\tif skill_id == 20:
\t\t\t\t\t_check_achievements(client, "fish", 1)
\t\t\t\t\t_update_leaderboard("fishing", char_dict.get("name", "?"),
\t\t\t\t\t\t\tint(char_dict.get("achievement_progress", {}).get("fish", 0)))
\t\t\t\t\t# Fishing tournament tracking
\t\t\t\t\tif _tourney_active:
\t\t\t\t\t\tvar _fish_obj: Dictionary = GameData.get_object(yield_index)
\t\t\t\t\t\tvar _fish_val: int = int(_fish_obj.get("value", 1))
\t\t\t\t\t\tvar _existing_score: int = 0
\t\t\t\t\t\tif _tourney_scores.has(client.peer_id):
\t\t\t\t\t\t\t_existing_score = int(_tourney_scores[client.peer_id].get("best_catch", 0))
\t\t\t\t\t\t_tourney_scores[client.peer_id] = {
\t\t\t\t\t\t\t"name": char_dict.get("name", "?"),
\t\t\t\t\t\t\t"best_catch": maxi(_existing_score, _fish_val)
\t\t\t\t\t\t}
\t\t\t\t\t\t# Broadcast updated scores (top 5)
\t\t\t\t\t\t_broadcast_tourney_scores()"""

if "_tourney_active" not in content or "_broadcast_tourney_scores" not in content:
    if "# Achievements for fishing" not in content:
        content = content.replace(FISHING_GATHER_END, FISHING_GATHER_END_NEW, 1)
        print("Added fishing achievement and tournament hooks.")
    else:
        print("Fishing achievement hooks already present, skipping.")
else:
    print("Fishing hooks already present, skipping.")

# ---- 5. Hook achievements into _complete_skill after level-up check ----
SKILL_LEVELUP_BLOCK = """\tif xp_gain > 0:
\t\tchar_dict["xp"] = char_dict.get("xp", 0) + xp_gain
\t\tvar levelled_up := _ServerCombatSCR.try_level_up(char_dict)
\t\t_send_stats(client)
\t\tvar xgw := NetProtocol.PacketWriter.new()
\t\txgw.write_i32(xp_gain)
\t\tclient.send_auth(NetProtocol.MsgType.S_XP_GAIN, xgw.get_bytes())
\t\tif levelled_up:
\t\t\tvar lw := NetProtocol.PacketWriter.new()
\t\t\tlw.write_u8(char_dict.get("level", 1))
\t\t\tclient.send_auth(NetProtocol.MsgType.S_LEVEL_UP, lw.get_bytes())
\t\t\t# Level-up sound (played only to the levelling player)
\t\t\tvar slw := NetProtocol.PacketWriter.new()
\t\t\tslw.write_u8(SOUND_LEVEL_UP)
\t\t\tclient.send_auth(NetProtocol.MsgType.S_PLAY_SOUND, slw.get_bytes())"""

SKILL_LEVELUP_BLOCK_NEW = """\tif xp_gain > 0:
\t\tchar_dict["xp"] = char_dict.get("xp", 0) + xp_gain
\t\tvar levelled_up := _ServerCombatSCR.try_level_up(char_dict)
\t\t_send_stats(client)
\t\tvar xgw := NetProtocol.PacketWriter.new()
\t\txgw.write_i32(xp_gain)
\t\tclient.send_auth(NetProtocol.MsgType.S_XP_GAIN, xgw.get_bytes())
\t\tif levelled_up:
\t\t\tvar lw := NetProtocol.PacketWriter.new()
\t\t\tlw.write_u8(char_dict.get("level", 1))
\t\t\tclient.send_auth(NetProtocol.MsgType.S_LEVEL_UP, lw.get_bytes())
\t\t\t# Level-up sound (played only to the levelling player)
\t\t\tvar slw := NetProtocol.PacketWriter.new()
\t\t\tslw.write_u8(SOUND_LEVEL_UP)
\t\t\tclient.send_auth(NetProtocol.MsgType.S_PLAY_SOUND, slw.get_bytes())
\t\t\t# Level achievements & leaderboard
\t\t\t_check_achievements(client, "level", 0)
\t\t\t_update_leaderboard("level", char_dict.get("name", "?"), char_dict.get("level", 1))"""

if '_check_achievements(client, "level", 0)\n\t\t\t_update_leaderboard("level"' not in content:
    content = content.replace(SKILL_LEVELUP_BLOCK, SKILL_LEVELUP_BLOCK_NEW, 1)
    print("Added level achievement hooks to _complete_skill.")
else:
    print("Level achievement hooks already present, skipping.")

# ---- 6. Hook bounty system into _handle_player_death ----
PVP_DEATH_XP_BLOCK = """\tfunc _handle_player_death(killer_client, dead_client) -> void:
\tvar dead_char: Dictionary = dead_client.char
\tvar level: int = dead_char.get("level", 1)

\t# Award XP to killer
\tvar xp_gain := _ServerCombatSCR.xp_for_kill(level)
\tvar kc: Dictionary = killer_client.char
\tkc["xp"] = kc.get("xp", 0) + xp_gain
\tvar levelled_up := _ServerCombatSCR.try_level_up(kc)

\t_send_stats(killer_client)"""

# Find a more specific anchor - after _send_stats(killer_client) and before XP gain notification
PVP_KILLER_NOTIFY = """\t# XP gain notification
\tvar xw := NetProtocol.PacketWriter.new()
\txw.write_i32(xp_gain)
\tkiller_client.send_auth(NetProtocol.MsgType.S_XP_GAIN, xw.get_bytes())

\t# Level-up notification + sound (killer only)
\tif levelled_up:
\t\tvar lw := NetProtocol.PacketWriter.new()
\t\tlw.write_u8(kc.get("level", 1))
\t\tkiller_client.send_auth(NetProtocol.MsgType.S_LEVEL_UP, lw.get_bytes())
\t\tvar sw := NetProtocol.PacketWriter.new()
\t\tsw.write_u8(SOUND_LEVEL_UP)
\t\tkiller_client.send_auth(NetProtocol.MsgType.S_PLAY_SOUND, sw.get_bytes())

\t# Respawn dead player at map start position"""

PVP_KILLER_NOTIFY_NEW = """\t# XP gain notification
\tvar xw := NetProtocol.PacketWriter.new()
\txw.write_i32(xp_gain)
\tkiller_client.send_auth(NetProtocol.MsgType.S_XP_GAIN, xw.get_bytes())

\t# Level-up notification + sound (killer only)
\tif levelled_up:
\t\tvar lw := NetProtocol.PacketWriter.new()
\t\tlw.write_u8(kc.get("level", 1))
\t\tkiller_client.send_auth(NetProtocol.MsgType.S_LEVEL_UP, lw.get_bytes())
\t\tvar sw := NetProtocol.PacketWriter.new()
\t\tsw.write_u8(SOUND_LEVEL_UP)
\t\tkiller_client.send_auth(NetProtocol.MsgType.S_PLAY_SOUND, sw.get_bytes())
\t\t_check_achievements(killer_client, "level", 0)
\t\t_update_leaderboard("level", kc.get("name", "?"), kc.get("level", 1))

\t# Bounty system: killer gets dead player's bounty, gains new bounty
\tvar _dead_bounty: int = int(dead_char.get("bounty", 0))
\tvar _killer_map_id: int = int(kc.get("map_id", 0))
\tvar _killer_name_pvp: String = kc.get("name", "unknown")
\tif _dead_bounty > 0:
\t\tkc["gold"] = int(kc.get("gold", 0)) + _dead_bounty
\t\tdead_char["bounty"] = 0
\t\t_send_server_msg(killer_client, "You collected a bounty of %d gold!" % _dead_bounty)
\t\t_send_stats(killer_client)
\t\t_check_achievements(killer_client, "bounties", 1)
\tkc["bounty"] = int(kc.get("bounty", 0)) + 200
\tvar _new_bounty: int = int(kc.get("bounty", 0))
\tvar _bw := NetProtocol.PacketWriter.new()
\t_bw.write_i32(killer_client.peer_id)
\t_bw.write_str(_killer_name_pvp)
\t_bw.write_i32(_new_bounty)
\t_broadcast_map(_killer_map_id, S_BOUNTY_UPDATE, _bw.get_bytes())
\t_send_server_msg_to_map(_killer_map_id, "WARNING: %s is now wanted! Bounty: %d gold." % [_killer_name_pvp, _new_bounty])
\t# PK achievement
\t_check_achievements(killer_client, "pks", 1)

\t# Respawn dead player at map start position"""

if "_dead_bounty" not in content:
    content = content.replace(PVP_KILLER_NOTIFY, PVP_KILLER_NOTIFY_NEW, 1)
    print("Added bounty hooks to _handle_player_death.")
else:
    print("Bounty hooks already present, skipping.")

# ---- 7. Add _check_daily_login call in _enter_world after quest indicators ----
ENTER_WORLD_QUEST = """\t# Check explore quests (client has accepted quests for this map_id)
\t_check_explore_quests(client, map_id)
\t# Send quest indicators for NPCs on this map
\t_send_quest_indicators(client)

\tprint("[Server] %s entered map %d @ (%d,%d)" % [
\t\tchar_dict.get("name","?"), map_id, cx, cy])"""

ENTER_WORLD_QUEST_NEW = """\t# Check explore quests (client has accepted quests for this map_id)
\t_check_explore_quests(client, map_id)
\t# Send quest indicators for NPCs on this map
\t_send_quest_indicators(client)

\t# Daily login reward
\t_check_daily_login(client)

\t# Map exploration achievement
\t_check_achievements(client, "maps", 0)

\tprint("[Server] %s entered map %d @ (%d,%d)" % [
\t\tchar_dict.get("name","?"), map_id, cx, cy])"""

if "_check_daily_login" not in content:
    content = content.replace(ENTER_WORLD_QUEST, ENTER_WORLD_QUEST_NEW, 1)
    print("Added _check_daily_login and map achievement to _enter_world.")
else:
    print("_check_daily_login already present, skipping.")

# ---- 8. Hook achievements into quest completion ----
# Find _check_quest_complete or _on_quest_turnin for quest completions
QUEST_TURNIN_FUNC = """func _on_quest_turnin(client, quest_id: int) -> void:"""
# We need to find what happens after a successful quest complete
# Search for S_QUEST_COMPLETE being sent
QUEST_COMPLETE_SEND = """\t\tw_qc.write_u16(quest_id)
\t\tw_qc.write_str(quest.get("reward_text", "Quest complete!"))
\t\tclient.send_auth(S_QUEST_COMPLETE, w_qc.get_bytes())"""

QUEST_COMPLETE_SEND_NEW = """\t\tw_qc.write_u16(quest_id)
\t\tw_qc.write_str(quest.get("reward_text", "Quest complete!"))
\t\tclient.send_auth(S_QUEST_COMPLETE, w_qc.get_bytes())
\t\t_check_achievements(client, "quests", 1)"""

if "S_QUEST_COMPLETE" in content and "_check_achievements(client, \"quests\"" not in content:
    content = content.replace(QUEST_COMPLETE_SEND, QUEST_COMPLETE_SEND_NEW, 1)
    print("Added quest achievement hook.")
else:
    print("Quest achievement hook already present or S_QUEST_COMPLETE not found, skipping.")

with open(FILE, "w", encoding="utf-8") as f:
    f.write(content)

print("Step 3 complete.")
