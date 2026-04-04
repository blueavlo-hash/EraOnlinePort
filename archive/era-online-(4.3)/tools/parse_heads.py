"""
parse_heads.py - Parse Head.dat (INI format) into heads.json.

Fields per [Headn]: Head1-4 (N/E/S/W GrhIndex).

Source: /c/eo3/MapEditorSource/Head.dat
Output: /c/eo3/EraOnline/data/heads.json
"""

import json
import os
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from parse_ini import INIParser
from paths import HEAD_DAT, OUT_HEADS

SRC_PATH = str(HEAD_DAT)
OUT_PATH  = str(OUT_HEADS)


def parse_heads(src: str = SRC_PATH, out: str = OUT_PATH) -> int:
    if not os.path.exists(src):
        print(f"[parse_heads] ERROR: Source file not found: {src}")
        return 0

    ini = INIParser(src)
    count = ini.get_int("INIT", "NumHeads", 0)
    if count == 0:
        count = 200  # fallback

    entries: dict[str, dict] = {}

    for i in range(1, count + 1):
        sec = f"Head{i}"
        if not ini.has_section(sec):
            sec = f"HEAD{i}"
            if not ini.has_section(sec):
                continue

        def gi(key, default=0): return ini.get_int(sec, key, default)

        entry = {
            # Head directions: [North, East, South, West]
            "head": [gi("Head1"), gi("Head2"), gi("Head3"), gi("Head4")],
        }
        entries[str(i)] = entry

    result = {"count": len(entries), "entries": entries}
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

    print(f"[parse_heads] Parsed {len(entries)} head definitions -> {out}")
    return len(entries)


if __name__ == "__main__":
    parse_heads()
