"""
parse_bodies.py - Parse body.dat (INI format) into bodies.json.

Fields per [Bodyn]: Walk1-4 (N/E/S/W GrhIndex), HeadoffsetX, HeadoffsetY.

Source: /c/eo3/MapEditorSource/body.dat
Output: /c/eo3/EraOnline/data/bodies.json
"""

import json
import os
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from parse_ini import INIParser
from paths import BODY_DAT, OUT_BODIES

SRC_PATH = str(BODY_DAT)
OUT_PATH  = str(OUT_BODIES)


def parse_bodies(src: str = SRC_PATH, out: str = OUT_PATH) -> int:
    if not os.path.exists(src):
        print(f"[parse_bodies] ERROR: Source file not found: {src}")
        return 0

    ini = INIParser(src)
    count = ini.get_int("INIT", "NumBodies", 0)
    if count == 0:
        count = 200  # fallback

    entries: dict[str, dict] = {}

    for i in range(1, count + 1):
        sec = f"Body{i}"
        if not ini.has_section(sec):
            # Also try uppercase
            sec = f"BODY{i}"
            if not ini.has_section(sec):
                continue

        def gi(key, default=0): return ini.get_int(sec, key, default)

        entry = {
            # Walk directions: [North, East, South, West] (VB6 Walk1=N, Walk2=E, Walk3=S, Walk4=W)
            "walk": [gi("Walk1"), gi("Walk2"), gi("Walk3"), gi("Walk4")],
            "head_offset_x": gi("HeadoffsetX"),
            "head_offset_y": gi("HeadoffsetY"),
        }
        entries[str(i)] = entry

    result = {"count": len(entries), "entries": entries}
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

    print(f"[parse_bodies] Parsed {len(entries)} body definitions -> {out}")
    return len(entries)


if __name__ == "__main__":
    parse_bodies()
