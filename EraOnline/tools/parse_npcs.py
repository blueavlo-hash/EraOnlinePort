"""
parse_npcs.py - Parse NPC.dat and NPC2.dat (INI format) into npcs.json.

NPC indices 1-499 come from NPC.dat.
NPC indices 500+ come from NPC2.dat.

Source: /c/eo3/Server/NPC.dat, /c/eo3/Server/NPC2.dat
Output: /c/eo3/EraOnline/data/npcs.json
"""

import json
import os
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from parse_ini import INIParser
from paths import NPC_DAT, NPC2_DAT, OUT_NPCS

SRC_NPC1 = str(NPC_DAT)
SRC_NPC2 = str(NPC2_DAT)
OUT_PATH  = str(OUT_NPCS)


def _parse_file(ini: INIParser, entries: dict, prefix: str, max_count: int) -> int:
    parsed = 0
    count = ini.get_int("INIT", "NumNPCs", 0)
    if count == 0:
        count = max_count

    for i in range(1, count + 1):
        sec = f"{prefix}{i}"
        if not ini.has_section(sec):
            continue

        def g(key, default=""): return ini.get(sec, key, default)
        def gi(key, default=0): return ini.get_int(sec, key, default)

        # Parse Obj1-Obj40 inventory items (format: "objindex-amount-equipped")
        inventory = []
        for slot in range(1, 41):
            obj_str = g(f"Obj{slot}", "")
            if not obj_str:
                continue
            parts = obj_str.split("-")
            try:
                obj_index = int(parts[0]) if len(parts) > 0 else 0
                amount    = int(parts[1]) if len(parts) > 1 else 0
                equipped  = int(parts[2]) if len(parts) > 2 else 0
                if obj_index > 0:
                    inventory.append({
                        "slot": slot,
                        "obj_index": obj_index,
                        "amount": amount,
                        "equipped": equipped,
                    })
            except (ValueError, IndexError):
                pass

        entry = {
            "name":        g("Name"),
            "desc":        g("Desc"),
            "hail":        g("Hail"),
            "head":        gi("Head"),
            "body":        gi("Body"),
            "heading":     gi("Heading"),
            "movement":    gi("Movement"),
            "npc_type":    gi("NpcType"),
            "weapon_anim": gi("WeaponAnim"),
            "shield_anim": gi("ShieldAnim"),
            "hostile":     gi("Hostile"),
            "attackable":  gi("Attackable"),
            "tameable":    gi("Tameable"),
            "death_obj":   gi("DeathObj"),
            "gold":        gi("Gold"),
            "npc_number":  gi("NpcNumber", i),
            "level":       gi("Level"),
            "give_exp":    gi("GiveEXP"),
            "give_gld":    gi("GiveGLD"),
            "loot_chance": gi("LootChance"),
            "max_hp":      gi("MaxHP"),
            "min_hp":      gi("MinHP"),
            "max_hit":     gi("MaxHIT"),
            "min_hit":     gi("MinHIT"),
            "def":         gi("DEF"),
            "category":    g("Category1"),
            "inventory":   inventory,
        }
        entries[str(i)] = entry
        parsed += 1

    return parsed


def parse_npcs(
    src1: str = SRC_NPC1,
    src2: str = SRC_NPC2,
    out:  str = OUT_PATH,
) -> int:
    entries: dict[str, dict] = {}
    total = 0

    if os.path.exists(src1):
        ini1 = INIParser(src1)
        n = _parse_file(ini1, entries, "NPC", 499)
        print(f"[parse_npcs] Parsed {n} NPCs from NPC.dat")
        total += n
    else:
        print(f"[parse_npcs] WARNING: {src1} not found")

    if os.path.exists(src2):
        ini2 = INIParser(src2)
        # NPC2.dat uses sections NPC500, NPC501, ... directly.
        # Detect range by scanning actual section names.
        npc2_sections = [s for s in ini2.sections() if s.upper().startswith("NPC") and s[3:].isdigit()]
        npc2_indices = sorted(int(s[3:]) for s in npc2_sections)
        n2 = 0
        for i in npc2_indices:
            sec = f"NPC{i}"
            if not ini2.has_section(sec):
                continue
            def g(key, default=""): return ini2.get(sec, key, default)
            def gi(key, default=0): return ini2.get_int(sec, key, default)
            inventory = []
            for slot in range(1, 41):
                obj_str = g(f"Obj{slot}", "")
                if not obj_str:
                    continue
                parts = obj_str.split("-")
                try:
                    obj_index = int(parts[0]) if len(parts) > 0 else 0
                    amount    = int(parts[1]) if len(parts) > 1 else 0
                    equipped  = int(parts[2]) if len(parts) > 2 else 0
                    if obj_index > 0:
                        inventory.append({"slot": slot, "obj_index": obj_index,
                                          "amount": amount, "equipped": equipped})
                except (ValueError, IndexError):
                    pass
            entries[str(i)] = {
                "name": g("Name"), "desc": g("Desc"), "hail": g("Hail"),
                "head": gi("Head"), "body": gi("Body"), "heading": gi("Heading"),
                "movement": gi("Movement"), "npc_type": gi("NpcType"),
                "weapon_anim": gi("WeaponAnim"), "shield_anim": gi("ShieldAnim"),
                "hostile": gi("Hostile"), "attackable": gi("Attackable"),
                "tameable": gi("Tameable"), "death_obj": gi("DeathObj"),
                "gold": gi("Gold"), "npc_number": gi("NpcNumber", i),
                "level": gi("Level"), "give_exp": gi("GiveEXP"),
                "give_gld": gi("GiveGLD"), "loot_chance": gi("LootChance"),
                "max_hp": gi("MaxHP"), "min_hp": gi("MinHP"),
                "max_hit": gi("MaxHIT"), "min_hit": gi("MinHIT"),
                "def": gi("DEF"),
                "category": g("Category1"), "inventory": inventory,
            }
            n2 += 1
        print(f"[parse_npcs] Parsed {n2} NPCs from NPC2.dat (indices {npc2_indices[0] if npc2_indices else '?'}-{npc2_indices[-1] if npc2_indices else '?'})")
        total += n2
    else:
        print(f"[parse_npcs] WARNING: {src2} not found (NPC2.dat is optional)")

    result = {"count": total, "entries": entries}
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

    print(f"[parse_npcs] Total {total} NPCs -> {out}")
    return total


if __name__ == "__main__":
    parse_npcs()
