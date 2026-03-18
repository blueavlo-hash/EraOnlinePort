"""Main patch script for game_server.gd - item distribution, crafting stations, reputation."""
import sys

gd = "C:/eo3/EraOnline/scripts/server/game_server.gd"
with open(gd, "r", encoding="utf-8") as f:
    content = f.read()

emdash = "\u2014"

# ─── 2. CRAFTING_STATIONS + rep constants ────────────────────────────────────
old2 = "const COOKING_STATION_TYPES:   Array = [21, 34, 52]  # campfire, campfire2, cooking stove"
assert old2 in content, "anchor 2 missing"
new2 = old2 + """

## Hardcoded crafting station positions per map (server authority).
## Format: map_id -> Array of {x, y, obj_type}
## obj_type 21/34/52 = cooking  |  50 = forge  |  51 = anvil
const CRAFTING_STATIONS: Dictionary = {
\t3:  [
\t\t{"x": 15, "y": 8,  "obj_type": 21},
\t],
\t18: [
\t\t{"x": 30, "y": 35, "obj_type": 52},
\t\t{"x": 12, "y": 15, "obj_type": 21},
\t\t{"x": 12, "y": 16, "obj_type": 34},
\t],
\t80: [
\t\t{"x": 39, "y": 44, "obj_type": 50},
\t\t{"x": 40, "y": 44, "obj_type": 51},
\t\t{"x": 38, "y": 48, "obj_type": 52},
\t],
\t115: [
\t\t{"x": 38, "y": 65, "obj_type": 52},
\t\t{"x": 42, "y": 62, "obj_type": 21},
\t],
\t140: [
\t\t{"x": 68, "y": 40, "obj_type": 50},
\t\t{"x": 69, "y": 40, "obj_type": 51},
\t\t{"x": 72, "y": 28, "obj_type": 52},
\t],
\t142: [
\t\t{"x": 38, "y": 37, "obj_type": 50},
\t\t{"x": 39, "y": 37, "obj_type": 51},
\t\t{"x": 36, "y": 37, "obj_type": 52},
\t],
}

const TOWN_FACTIONS: Dictionary = {
\t"haven":      3,
\t"thornwall":  18,
\t"ironhaven":  80,
\t"sealport":   115,
\t"shadowmoor": 140,
}
const REP_NEUTRAL:   int = 0
const REP_FRIENDLY:  int = 100
const REP_HONORED:   int = 250
const REP_REVERED:   int = 500"""
content = content.replace(old2, new2, 1)
print("2 CRAFTING_STATIONS + rep constants done")

# ─── 3. Extend _has_station_near ─────────────────────────────────────────────
old3 = "\treturn false\n\n\n## Returns true if the character has at least one item with the given obj_index."
assert old3 in content, "anchor 3 missing"
new3 = """\t# Also check hardcoded CRAFTING_STATIONS
\tvar cs_map: Array = CRAFTING_STATIONS.get(map_id, [])
\tfor cs in cs_map:
\t\tif not station_types.has(int(cs["obj_type"])):
\t\t\tcontinue
\t\tvar cdx: int = abs(int(cs["x"]) - char_tile.x)
\t\tvar cdy: int = abs(int(cs["y"]) - char_tile.y)
\t\tif maxi(cdx, cdy) <= STATION_RANGE:
\t\t\treturn true
\treturn false


## Returns true if the character has at least one item with the given obj_index."""
content = content.replace(old3, new3, 1)
print("3 _has_station_near extended")

# ─── 4a. Strip Tim's inventory ───────────────────────────────────────────────
old4a = (
    '\t\t\t\t{"name": "Merchant Tim", "x": 14, "y": 9, "npc_type": 2, "hostile": 0,\n'
    '\t\t\t\t "movement": 0, "body": 22, "head": 13, "weapon_anim": 0, "shield_anim": 0,\n'
    '\t\t\t\t "max_hp": 500, "min_hit": 0, "max_hit": 0, "def": 0, "gold": 0, "level": 1,\n'
    '\t\t\t\t "rep_faction": "haven",\n'
    '\t\t\t\t # Base: food, water, starter weapon, fishing rod, campfire, basic clothing, bandage\n'
    '\t\t\t\t "items": [6, 95, 22, 21, 33, 50, 80, 116, 212, 145, 147, 286, 321],\n'
    '\t\t\t\t # Friendly (100+ haven rep): better gear, lantern, more tools\n'
    '\t\t\t\t "items_friendly": [7, 128, 38, 306, 3, 60, 87, 23, 43, 57, 116, 155],\n'
    '\t\t\t\t # Honored (250+ haven rep): leather armor, better weapons\n'
    '\t\t\t\t "items_honored": [216, 46, 58, 214, 32, 61, 149, 152, 151],\n'
    '\t\t\t\t # Revered (500+ haven rep): carpentry blueprints, better apparel\n'
    '\t\t\t\t "items_revered": [257, 258, 259, 260, 215, 147]},'
)
old4a_orig = (
    '\t\t\t\t{"name": "Merchant Tim", "x": 14, "y": 9, "npc_type": 2, "hostile": 0,\n'
    '\t\t\t\t "movement": 0, "body": 22, "head": 13, "weapon_anim": 0, "shield_anim": 0,\n'
    '\t\t\t\t "max_hp": 500, "min_hit": 0, "max_hit": 0, "def": 0, "gold": 0, "level": 1,\n'
    '\t\t\t\t "items": [6, 19, 20, 21, 22, 8,\n'
    '\t\t\t\t           306, 7, 80, 38, 128,\n'
    '\t\t\t\t           185, 178, 153,\n'
    '\t\t\t\t           216, 244, 212, 57, 58, 59, 46, 43, 41,\n'
    '\t\t\t\t           321, 322]},  # 321=Lantern (night_sight+2), 322=Night Stalker Hood (night_sight+1)'
)
assert old4a_orig in content, "Tim original block missing"
new4a = (
    '\t\t\t\t# Merchant Tim: minimal starter vendor\n'
    '\t\t\t\t{"name": "Merchant Tim", "x": 14, "y": 9, "npc_type": 2, "hostile": 0,\n'
    '\t\t\t\t "movement": 0, "body": 22, "head": 13, "weapon_anim": 0, "shield_anim": 0,\n'
    '\t\t\t\t "max_hp": 500, "min_hit": 0, "max_hit": 0, "def": 0, "gold": 0, "level": 1,\n'
    '\t\t\t\t "rep_faction": "haven",\n'
    '\t\t\t\t "items":          [6, 95, 22, 21, 33, 50, 80, 116, 212, 145, 147, 286, 321],\n'
    '\t\t\t\t "items_friendly": [7, 128, 38, 306, 3, 60, 87, 23, 43, 57, 155],\n'
    '\t\t\t\t "items_honored":  [216, 46, 58, 214, 32, 61, 149, 152, 151],\n'
    '\t\t\t\t "items_revered":  [257, 258, 259, 260, 215]},'
)
content = content.replace(old4a_orig, new4a, 1)
print("4a Tim stripped")

# ─── 4b. Ranger Holt to Map 18 (handle both LF and CRLF) ─────────────────────
def try_replace(content, old_lf, new_lf):
    if old_lf in content:
        return content.replace(old_lf, new_lf, 1), True
    old_crlf = old_lf.replace("\n", "\r\n")
    new_crlf = new_lf.replace("\n", "\r\n")
    if old_crlf in content:
        return content.replace(old_crlf, new_crlf, 1), True
    return content, False

guard_line = '\t\t\t\t{"npc_index": 57, "x": 22, "y": 30},  # guard ' + emdash + ' chain 4 hunter/exploration quests\n'
cook_line  = '\t\t\t\t{"npc_index": 20, "x": 30, "y": 35},  # cook ' + emdash + ' chain 3 cooking quests\n'
old4b = guard_line + cook_line + '\t\t\t]'
new4b = (guard_line + cook_line +
    '\t\t\t\t# Ranger Holt: Thornwall general goods vendor\n'
    '\t\t\t\t{"name": "Ranger Holt", "x": 40, "y": 35, "npc_type": 2, "hostile": 0,\n'
    '\t\t\t\t "movement": 0, "body": 8, "head": 5, "weapon_anim": 0, "shield_anim": 0,\n'
    '\t\t\t\t "max_hp": 400, "min_hit": 0, "max_hit": 0, "def": 0, "gold": 0, "level": 1,\n'
    '\t\t\t\t "rep_faction": "thornwall",\n'
    '\t\t\t\t "items":          [7, 128, 38, 306, 3, 32, 60, 61, 87, 23, 46, 43, 57, 212, 214, 6, 99, 22, 286, 321, 149, 152, 151],\n'
    '\t\t\t\t "items_friendly": [58, 216, 26, 81, 86, 259, 260, 322],\n'
    '\t\t\t\t "items_honored":  [51, 56, 44, 59, 261, 262, 244],\n'
    '\t\t\t\t "items_revered":  [71, 41, 25, 256, 255]},\n'
    '\t\t\t]'
)
content, ok = try_replace(content, old4b, new4b)
print("4b Ranger Holt:", "done" if ok else "MISS")

# ─── 4c. Expand Aldric ───────────────────────────────────────────────────────
old4c = (
    '\t\t\t\t# Master Blacksmith ' + emdash + ' unique name so only THIS smith offers the crafting quest chain\n'
    '\t\t\t\t{"name": "Master Blacksmith Aldric", "x": 38, "y": 43, "npc_type": 2, "hostile": 0,\n'
    '\t\t\t\t "movement": 0, "body": 21, "head": 7, "weapon_anim": 4, "shield_anim": 0,\n'
    '\t\t\t\t "max_hp": 500, "min_hit": 0, "max_hit": 0, "def": 0, "gold": 0, "level": 1,\n'
    '\t\t\t\t "items": [6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17]},'
)
new4c = (
    '\t\t\t\t# Master Blacksmith Aldric ' + emdash + ' unique name so only THIS smith offers the crafting quest chain\n'
    '\t\t\t\t{"name": "Master Blacksmith Aldric", "x": 38, "y": 43, "npc_type": 2, "hostile": 0,\n'
    '\t\t\t\t "movement": 0, "body": 21, "head": 7, "weapon_anim": 4, "shield_anim": 0,\n'
    '\t\t\t\t "max_hp": 500, "min_hit": 0, "max_hit": 0, "def": 0, "gold": 0, "level": 1,\n'
    '\t\t\t\t "rep_faction": "ironhaven",\n'
    '\t\t\t\t "items":          [38, 306, 153, 154, 185, 178, 180, 50, 32],\n'
    '\t\t\t\t "items_friendly": [186, 187, 181, 184, 56, 51, 46, 322],\n'
    '\t\t\t\t "items_honored":  [189, 168, 192, 73, 71, 44, 59, 323],\n'
    '\t\t\t\t "items_revered":  [169, 172, 175, 68, 11, 47, 194]},'
)
content, ok = try_replace(content, old4c, new4c)
print("4c Aldric:", "done" if ok else "MISS")

# ─── 4d. Add Pirate Trader after Sylvara ─────────────────────────────────────
old4d = (
    '\t\t\t\t# Sylvara ' + emdash + ' arcane vendor and quest giver for magic chain (level 4+, remote location)\n'
    '\t\t\t\t{"name": "Sylvara the Arcanist", "x": 35, "y": 60, "npc_type": 3, "hostile": 0,\n'
    '\t\t\t\t "movement": 0, "body": 5, "head": 8, "weapon_anim": 0, "shield_anim": 0,\n'
    '\t\t\t\t "max_hp": 500, "min_hit": 0, "max_hit": 0, "def": 0, "gold": 0, "level": 1},'
)
new4d = old4d + (
    '\n\t\t\t\t# Pirate Trader Mogs: Sealport general goods vendor\n'
    '\t\t\t\t{"name": "Pirate Trader Mogs", "x": 55, "y": 40, "npc_type": 2, "hostile": 0,\n'
    '\t\t\t\t "movement": 0, "body": 14, "head": 9, "weapon_anim": 0, "shield_anim": 0,\n'
    '\t\t\t\t "max_hp": 400, "min_hit": 0, "max_hit": 0, "def": 0, "gold": 0, "level": 1,\n'
    '\t\t\t\t "rep_faction": "sealport",\n'
    '\t\t\t\t "items":          [80, 217, 219, 141, 87, 81, 82, 119, 122, 321, 220, 286, 22, 19],\n'
    '\t\t\t\t "items_friendly": [26, 60, 73, 71, 84, 83],\n'
    '\t\t\t\t "items_honored":  [76, 14, 68, 194, 216, 85, 86],\n'
    '\t\t\t\t "items_revered":  [64, 77, 139, 291, 25, 120]},'
)
content, ok = try_replace(content, old4d, new4d)
print("4d Pirate Trader:", "done" if ok else "MISS")

# ─── 4e. Add Shadow Merchant to Map 140 ──────────────────────────────────────
idx140 = content.find('\t\t140:\n')
if idx140 < 0:
    idx140 = content.find('\t\t140:\r\n')
assert idx140 >= 0, "140 block not found"
seg = content[idx140:]
old4e = '\t\t\t\t{"npc_index": 31, "x": 20, "y": 42},  # alchemist\n\t\t\t]'
new4e = (
    '\t\t\t\t{"npc_index": 31, "x": 20, "y": 42},  # alchemist\n'
    '\t\t\t\t# Shadow Merchant Vex: Shadowmoor elite vendor\n'
    '\t\t\t\t{"name": "Shadow Merchant Vex", "x": 60, "y": 30, "npc_type": 2, "hostile": 0,\n'
    '\t\t\t\t "movement": 0, "body": 17, "head": 12, "weapon_anim": 0, "shield_anim": 0,\n'
    '\t\t\t\t "max_hp": 600, "min_hit": 0, "max_hit": 0, "def": 0, "gold": 0, "level": 1,\n'
    '\t\t\t\t "rep_faction": "shadowmoor",\n'
    '\t\t\t\t "items":          [56, 51, 68, 44, 41, 59, 216, 213, 286, 321, 322, 22],\n'
    '\t\t\t\t "items_friendly": [71, 12, 13, 42, 47, 194],\n'
    '\t\t\t\t "items_honored":  [64, 77, 76, 139, 291, 192, 169],\n'
    '\t\t\t\t "items_revered":  [14, 15, 142, 195, 175, 176, 63, 323]},\n'
    '\t\t\t]'
)
seg, ok = try_replace(seg, old4e, new4e)
if ok:
    content = content[:idx140] + seg
print("4e Shadow Merchant:", "done" if ok else "MISS")

# ─── 5. Patch _on_shop_open ───────────────────────────────────────────────────
old5 = (
    '\t# Build item list from NPC data (obj1..obj10 style fields or "items" array)\n'
    '\tvar items: Array = []\n'
    '\tvar raw_items: Array = npc_data.get("items", [])\n'
    '\tif raw_items.size() > 0:\n'
    '\t\t# Structured items array\n'
    '\t\tfor obj_index in raw_items:'
)
assert old5 in content, "shop open block missing"
new5 = (
    '\t# Build item list - merge rep-tiered arrays if vendor has rep_faction\n'
    '\tvar cc_shop: Dictionary = client.char\n'
    '\tvar items: Array = []\n'
    '\tvar raw_items: Array\n'
    '\tif npc_data.has("rep_faction"):\n'
    '\t\traw_items = _build_vendor_items(npc_data, cc_shop)\n'
    '\telse:\n'
    '\t\traw_items = npc_data.get("items", [])\n'
    '\tif raw_items.size() > 0:\n'
    '\t\t# Structured items array\n'
    '\t\tfor obj_index in raw_items:'
)
content = content.replace(old5, new5, 1)
print("5 _on_shop_open patched")

# ─── 6. Patch _on_buy ─────────────────────────────────────────────────────────
old6 = (
    '\t# Verify the NPC actually sells this item\n'
    '\tvar vendor_sells := false\n'
    '\tvar raw_items: Array = npc_data.get("items", [])\n'
    '\tif raw_items.size() > 0:\n'
    '\t\tfor vi in raw_items:\n'
    '\t\t\tif int(vi) == obj_index:\n'
    '\t\t\t\tvendor_sells = true\n'
    '\t\t\t\tbreak\n'
    '\telse:'
)
assert old6 in content, "buy validate block missing"
new6 = (
    '\t# Verify the NPC actually sells this item (respecting rep tiers)\n'
    '\tvar vendor_sells := false\n'
    '\tvar cc_buy: Dictionary = client.char\n'
    '\tvar raw_items_buy: Array\n'
    '\tif npc_data.has("rep_faction"):\n'
    '\t\traw_items_buy = _build_vendor_items(npc_data, cc_buy)\n'
    '\telse:\n'
    '\t\traw_items_buy = npc_data.get("items", [])\n'
    '\tif raw_items_buy.size() > 0:\n'
    '\t\tfor vi in raw_items_buy:\n'
    '\t\t\tif int(vi) == obj_index:\n'
    '\t\t\t\tvendor_sells = true\n'
    '\t\t\t\tbreak\n'
    '\telse:'
)
content = content.replace(old6, new6, 1)
print("6 _on_buy patched")

# ─── 7. Patch _on_quest_turnin ────────────────────────────────────────────────
old7 = (
    '\t_send_server_msg(client, "Quest complete: %s! Reward: %d gold, %d XP." % [\n'
    '\t\tquest.get("name", ""), reward_gold, reward_xp])\n'
    '\t# Refresh quest indicators on the map'
)
assert old7 in content, "quest turnin msg missing"
new7 = (
    '\t_send_server_msg(client, "Quest complete: %s! Reward: %d gold, %d XP." % [\n'
    '\t\tquest.get("name", ""), reward_gold, reward_xp])\n'
    '\t# Award town reputation\n'
    '\tvar rep_fac: String = quest.get("rep_faction", "")\n'
    '\tvar rep_amt: int = int(quest.get("rep_amount", 0))\n'
    '\tif not rep_fac.is_empty() and rep_amt > 0:\n'
    '\t\t_add_rep(client, rep_fac, rep_amt)\n'
    '\t# Refresh quest indicators on the map'
)
content = content.replace(old7, new7, 1)
print("7 _on_quest_turnin patched")

# ─── 8. Append rep helpers ─────────────────────────────────────────────────────
rep_helpers = (
    "\n\n"
    "# ---------------------------------------------------------------------------\n"
    "# Reputation helpers\n"
    "# ---------------------------------------------------------------------------\n"
    "\n"
    "func _get_rep(char_dict: Dictionary, faction: String) -> int:\n"
    "\tvar rep: Dictionary = char_dict.get(\"reputation\", {})\n"
    "\treturn int(rep.get(faction, 0))\n"
    "\n"
    "\n"
    "func _add_rep(client, faction: String, amount: int) -> void:\n"
    "\tvar char_dict: Dictionary = client.char\n"
    "\tvar rep: Dictionary = char_dict.get(\"reputation\", {})\n"
    "\tvar old_val: int = int(rep.get(faction, 0))\n"
    "\tvar new_val: int = old_val + amount\n"
    "\trep[faction] = new_val\n"
    "\tchar_dict[\"reputation\"] = rep\n"
    "\tvar sw := NetProtocol.PacketWriter.new()\n"
    "\tsw.write_u16(1)\n"
    "\tsw.write_str(\"rep_\" + faction)\n"
    "\tsw.write_i32(new_val)\n"
    "\tclient.send_auth(NetProtocol.MsgType.S_SET_STATS, sw.get_bytes())\n"
    "\tvar old_tier: int = _rep_tier(old_val)\n"
    "\tvar new_tier: int = _rep_tier(new_val)\n"
    "\tif new_tier > old_tier:\n"
    "\t\tvar tier_names: Array = [\"Neutral\", \"Friendly\", \"Honored\", \"Revered\"]\n"
    "\t\t_send_server_msg(client, \"Your reputation with %s is now: %s!\" % [\n"
    "\t\t\t\tfaction.capitalize(), tier_names[new_tier]])\n"
    "\n"
    "\n"
    "func _rep_tier(rep: int) -> int:\n"
    "\tif rep >= REP_REVERED:  return 3\n"
    "\tif rep >= REP_HONORED:  return 2\n"
    "\tif rep >= REP_FRIENDLY: return 1\n"
    "\treturn 0\n"
    "\n"
    "\n"
    "func _build_vendor_items(npc_data: Dictionary, char_dict: Dictionary) -> Array:\n"
    "\tvar faction: String = npc_data.get(\"rep_faction\", \"\")\n"
    "\tvar rep: int = _get_rep(char_dict, faction) if not faction.is_empty() else REP_REVERED\n"
    "\tvar all_items: Array = []\n"
    "\tfor idx in npc_data.get(\"items\", []):\n"
    "\t\tall_items.append(int(idx))\n"
    "\tif rep >= REP_FRIENDLY:\n"
    "\t\tfor idx in npc_data.get(\"items_friendly\", []):\n"
    "\t\t\tall_items.append(int(idx))\n"
    "\tif rep >= REP_HONORED:\n"
    "\t\tfor idx in npc_data.get(\"items_honored\", []):\n"
    "\t\t\tall_items.append(int(idx))\n"
    "\tif rep >= REP_REVERED:\n"
    "\t\tfor idx in npc_data.get(\"items_revered\", []):\n"
    "\t\t\tall_items.append(int(idx))\n"
    "\treturn all_items\n"
)
content = content.rstrip() + "\n" + rep_helpers
print("8 rep helpers appended")

with open(gd, "w", encoding="utf-8") as f:
    f.write(content)
print("\nAll patches written successfully.")
