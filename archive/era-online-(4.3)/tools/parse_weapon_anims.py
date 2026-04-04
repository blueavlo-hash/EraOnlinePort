"""
parse_weapon_anims.py - Parse wpanim.dat (INI format) into weapon_anims.json.

Fields per [WeaponAnimn]: WeaponWalk1-4 (N/E/S/W GrhIndex).

Source: /c/eo3/MapEditorSource/wpanim.dat
Output: /c/eo3/EraOnline/data/weapon_anims.json
"""

import json
import os
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from parse_ini import INIParser
from paths import WPANIM_DAT, OUT_WEAPON_ANIMS

SRC_PATH = str(WPANIM_DAT)
OUT_PATH  = str(OUT_WEAPON_ANIMS)


def parse_weapon_anims(src: str = SRC_PATH, out: str = OUT_PATH) -> int:
    if not os.path.exists(src):
        print(f"[parse_weapon_anims] ERROR: Source file not found: {src}")
        return 0

    ini = INIParser(src)
    count = ini.get_int("INIT", "NumWeaponAnims", 0)
    if count == 0:
        count = 50  # fallback

    entries: dict[str, dict] = {}

    for i in range(1, count + 1):
        sec = f"WeaponAnim{i}"
        if not ini.has_section(sec):
            continue

        def gi(key, default=0): return ini.get_int(sec, key, default)

        entry = {
            # Walk directions: [North, East, South, West]
            "walk": [
                gi("WeaponWalk1"),
                gi("WeaponWalk2"),
                gi("WeaponWalk3"),
                gi("WeaponWalk4"),
            ],
        }
        entries[str(i)] = entry

    result = {"count": len(entries), "entries": entries}
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

    print(f"[parse_weapon_anims] Parsed {len(entries)} weapon animations -> {out}")
    return len(entries)


if __name__ == "__main__":
    parse_weapon_anims()
