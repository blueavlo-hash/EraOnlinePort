"""
parse_objects.py - Parse OBJ.dat (INI format) into objects.json.

Source: /c/eo3/Server/OBJ.dat
Output: /c/eo3/EraOnline/data/objects.json
"""

import json
import os
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from parse_ini import INIParser
from paths import OBJ_DAT, OUT_OBJECTS

SRC_PATH = str(OBJ_DAT)
OUT_PATH = str(OUT_OBJECTS)


def parse_objects(src: str = SRC_PATH, out: str = OUT_PATH) -> int:
    if not os.path.exists(src):
        print(f"[parse_objects] ERROR: Source file not found: {src}")
        return 0

    ini = INIParser(src)
    count = ini.get_int("INIT", "NumOBJs", 0)
    if count == 0:
        print("[parse_objects] WARNING: NumOBJs=0 or missing [INIT] section")
        count = 500  # Try up to 500

    entries: dict[str, dict] = {}

    for i in range(1, count + 1):
        sec = f"OBJ{i}"
        if not ini.has_section(sec):
            continue

        def g(key, default=""): return ini.get(sec, key, default)
        def gi(key, default=0): return ini.get_int(sec, key, default)

        # ObjType key name varies in original (ObjType, Objtype, OBJTYPE)
        obj_type = gi("ObjType") or gi("Objtype") or gi("OBJTYPE")
        min_hit = gi("MinHIT") or gi("MinHit") or gi("MINHIT")
        max_hit = gi("MaxHIT") or gi("MaxHit") or gi("MAXHIT")

        entry = {
            "name":              g("Name"),
            "category":          g("Category"),
            "grh_index":         gi("GrhIndex"),
            "obj_type":          obj_type,
            "value":             g("Value", "0"),
            "pickable":          gi("Pickable"),
            "sellable":          gi("Sellable"),
            "food":              gi("Food"),
            "level":             gi("Level"),
            "spell_type":        gi("SpellType") or gi("SPELLTYPE"),
            "make_item":         gi("MakeItem") or gi("Makeitem"),
            "need_planks":       gi("NeedPlanks"),
            "need_folded_cloth": gi("NeedFoldedCloth"),
            "need_steel":        gi("NeedSteel"),
            "skill":             gi("Skill"),
            "min_hit":           min_hit,
            "max_hit":           max_hit,
            "min_hp":            gi("MinHP"),
            "max_hp":            gi("MaxHP"),
            "def":               gi("DEF"),
            "clothing_type":     gi("ClothingType"),
            "handle_rain":       gi("TakeRain"),
            "shield_anim":       gi("ShieldAnim"),
            "weapon_anim":       gi("WeaponAnim"),
            "class_forbid":      [
                g("Classforbid1"), g("Classforbid2"), g("Classforbid3"),
                g("Classforbid4"), g("Classforbid5"), g("Classforbid6"),
                g("Classforbid7"),
            ],
        }
        # Remove trailing empty class_forbid entries
        while entry["class_forbid"] and not entry["class_forbid"][-1]:
            entry["class_forbid"].pop()

        entries[str(i)] = entry

    result = {"count": len(entries), "entries": entries}
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

    print(f"[parse_objects] Parsed {len(entries)} objects -> {out}")
    return len(entries)


if __name__ == "__main__":
    parse_objects()
