"""
parse_shield_anims.py - Parse shanim.dat (INI format) into shield_anims.json.

Fields per [ShieldAnimn]: ShieldWalk1-4 (N/E/S/W GrhIndex).

Source: /c/eo3/MapEditorSource/shanim.dat
Output: /c/eo3/EraOnline/data/shield_anims.json
"""

import json
import os
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from parse_ini import INIParser
from paths import SHANIM_DAT, OUT_SHIELD_ANIMS

SRC_PATH = str(SHANIM_DAT)
OUT_PATH  = str(OUT_SHIELD_ANIMS)


def parse_shield_anims(src: str = SRC_PATH, out: str = OUT_PATH) -> int:
    if not os.path.exists(src):
        print(f"[parse_shield_anims] ERROR: Source file not found: {src}")
        return 0

    ini = INIParser(src)
    count = ini.get_int("INIT", "NumShieldAnims", 0)
    if count == 0:
        count = 50  # fallback

    entries: dict[str, dict] = {}

    for i in range(1, count + 1):
        sec = f"ShieldAnim{i}"
        if not ini.has_section(sec):
            continue

        def gi(key, default=0): return ini.get_int(sec, key, default)

        entry = {
            # Walk directions: [North, East, South, West]
            "walk": [
                gi("ShieldWalk1"),
                gi("ShieldWalk2"),
                gi("ShieldWalk3"),
                gi("ShieldWalk4"),
            ],
        }
        entries[str(i)] = entry

    result = {"count": len(entries), "entries": entries}
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

    print(f"[parse_shield_anims] Parsed {len(entries)} shield animations -> {out}")
    return len(entries)


if __name__ == "__main__":
    parse_shield_anims()
