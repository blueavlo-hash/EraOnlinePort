"""
parse_maps.py - Parse map binary files into JSON.

Map file set per map N (in /c/eo3/Server/Maps/):
  MapN.map  - binary, 7 bytes/tile  (blocked + 3 layer GrhIndices)
  MapN.inf  - binary, 16 bytes/tile (exits + NPC index + 4 dummy int16s)
  MapN.obj  - binary, 14 bytes/tile (obj + locked + sign + 2 dummy int16s)
  MapN.dat  - text INI             (name, music, start pos, exits, pk zone)

Loop order (matches VB6): outer y=1..100, inner x=1..100.
Output: /c/eo3/EraOnline/data/maps/map_N.json (sparse - only non-zero tiles)
"""

import struct
import json
import os
import sys
import glob
import re
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from parse_ini import INIParser
from paths import SRC_MAPS, MAPS_DATA_DIR

SRC_DIR = str(SRC_MAPS)
OUT_DIR  = str(MAPS_DATA_DIR)
MAP_W    = 100
MAP_H    = 100


def read_i16(data: bytes, offset: int) -> tuple[int, int]:
    return struct.unpack_from("<h", data, offset)[0], offset + 2


def _parse_dat_meta(map_num: int) -> dict:
    """Parse MapN.dat text metadata."""
    dat_path = os.path.join(SRC_DIR, f"Map{map_num}.dat")
    if not os.path.exists(dat_path):
        return {}
    try:
        ini = INIParser(dat_path)
        sec = f"Map{map_num}"

        def g(k, d=""): return ini.get(sec, k, d)
        def gi(k, d=0): return ini.get_int(sec, k, d)

        # StartPos format: "map-x-y"
        start_raw = g("StartPos", "")
        start_parts = start_raw.split("-") if start_raw else []
        start_pos = {
            "map": int(start_parts[0]) if len(start_parts) > 0 else map_num,
            "x":   int(start_parts[1]) if len(start_parts) > 1 else 10,
            "y":   int(start_parts[2]) if len(start_parts) > 2 else 10,
        }

        return {
            "name":        g("Name"),
            "music":       g("MusicNum", "0"),
            "start_pos":   start_pos,
            "north_exit":  gi("NorthExit"),
            "south_exit":  gi("SouthExit"),
            "west_exit":   gi("WestExit"),
            "east_exit":   gi("EastExit"),
            "pk_free_zone": g("PKFREEZONE", "0") not in ("0", "", "false", "False"),
        }
    except Exception as e:
        print(f"  [warn] Could not parse Map{map_num}.dat: {e}")
        return {}


def parse_map(map_num: int) -> dict | None:
    map_path = os.path.join(SRC_DIR, f"Map{map_num}.map")
    inf_path = os.path.join(SRC_DIR, f"Map{map_num}.inf")
    obj_path = os.path.join(SRC_DIR, f"Map{map_num}.obj")

    if not os.path.exists(map_path):
        return None

    # Read all binary files
    with open(map_path, "rb") as f:
        map_data = f.read()

    inf_data = b""
    if os.path.exists(inf_path):
        with open(inf_path, "rb") as f:
            inf_data = f.read()

    obj_data = b""
    if os.path.exists(obj_path):
        with open(obj_path, "rb") as f:
            obj_data = f.read()

    # Validate sizes
    expected_map = MAP_W * MAP_H * 7
    expected_inf = MAP_W * MAP_H * 16
    expected_obj = MAP_W * MAP_H * 14

    if len(map_data) < expected_map:
        print(f"  [warn] Map{map_num}.map too small ({len(map_data)} < {expected_map})")

    # Parse tiles (outer y, inner x to match VB6 loop order)
    tiles: dict[str, dict] = {}  # "y,x" -> sparse tile data
    map_off = 0
    inf_off = 0
    obj_off = 0

    for y in range(1, MAP_H + 1):
        for x in range(1, MAP_W + 1):
            tile: dict = {}

            # --- .map file (7 bytes per tile) ---
            if map_off + 7 <= len(map_data):
                blocked = map_data[map_off]
                map_off += 1
                l1, map_off = read_i16(map_data, map_off)
                l2, map_off = read_i16(map_data, map_off)
                l3, map_off = read_i16(map_data, map_off)

                if blocked:
                    tile["blocked"] = blocked
                layers = [l1, l2, l3]
                if any(layers):
                    tile["layers"] = layers

            # --- .inf file (16 bytes = 8 × int16 per tile) ---
            if inf_off + 16 <= len(inf_data):
                exit_map, inf_off = read_i16(inf_data, inf_off)
                exit_x,   inf_off = read_i16(inf_data, inf_off)
                exit_y,   inf_off = read_i16(inf_data, inf_off)
                npc_idx,  inf_off = read_i16(inf_data, inf_off)
                # 4 legacy/dummy int16s
                for _ in range(4):
                    inf_off += 2

                if exit_map > 0:
                    tile["exit"] = {"map": exit_map, "x": exit_x, "y": exit_y}
                if npc_idx > 0:
                    tile["npc_index"] = npc_idx

            # --- .obj file (14 bytes = 7 × int16 per tile) ---
            if obj_off + 14 <= len(obj_data):
                obj_idx,    obj_off = read_i16(obj_data, obj_off)
                obj_amount, obj_off = read_i16(obj_data, obj_off)
                locked,     obj_off = read_i16(obj_data, obj_off)
                sign,       obj_off = read_i16(obj_data, obj_off)
                sign_owner, obj_off = read_i16(obj_data, obj_off)
                # 2 legacy/dummy int16s
                for _ in range(2):
                    obj_off += 2

                if obj_idx > 0:
                    tile["obj"] = {"index": obj_idx, "amount": obj_amount}
                if locked:
                    tile["locked"] = locked
                if sign:
                    tile["sign"] = sign
                if sign_owner:
                    tile["sign_owner"] = sign_owner

            # Only store tile if it has any non-default data
            if tile:
                tiles[f"{y},{x}"] = tile

    meta = _parse_dat_meta(map_num)
    result = {
        "id":          map_num,
        "name":        meta.get("name", ""),
        "music":       meta.get("music", "0"),
        "start_pos":   meta.get("start_pos", {"map": map_num, "x": 10, "y": 10}),
        "north_exit":  meta.get("north_exit", 0),
        "south_exit":  meta.get("south_exit", 0),
        "west_exit":   meta.get("west_exit", 0),
        "east_exit":   meta.get("east_exit", 0),
        "pk_free_zone": meta.get("pk_free_zone", False),
        "tile_count":  len(tiles),
        "tiles":       tiles,
    }
    return result


def parse_maps(src_dir: str = SRC_DIR, out_dir: str = OUT_DIR) -> int:
    os.makedirs(out_dir, exist_ok=True)

    # Find all map numbers from Map.dat index
    map_dat = os.path.join(src_dir, "Map.dat")
    num_maps = 0
    if os.path.exists(map_dat):
        try:
            ini = INIParser(map_dat)
            num_maps = ini.get_int("INIT", "NumMaps", 0)
        except Exception:
            pass

    # Fallback: discover from .map files
    map_files = glob.glob(os.path.join(src_dir, "Map*.map"))
    map_nums = set()
    for f in map_files:
        basename = os.path.basename(f)
        m = re.match(r"Map(\d+)\.map$", basename, re.IGNORECASE)
        if m:
            map_nums.add(int(m.group(1)))

    if num_maps > 0:
        map_nums = map_nums | set(range(1, num_maps + 1))

    map_nums = sorted(map_nums)
    parsed = 0
    index = []

    print(f"[parse_maps] Found {len(map_nums)} potential map files...")

    for map_num in map_nums:
        data = parse_map(map_num)
        if data is None:
            continue

        out_path = os.path.join(out_dir, f"map_{map_num}.json")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(data, f, separators=(",", ":"))  # compact for map files

        index.append(map_num)
        parsed += 1
        if parsed % 50 == 0:
            print(f"  ...{parsed} maps done")

    # Write index
    index_path = os.path.join(out_dir, "map_index.json")
    with open(index_path, "w", encoding="utf-8") as f:
        json.dump({"count": len(index), "maps": index}, f, indent=2)

    print(f"[parse_maps] Parsed {parsed} maps -> {out_dir}")
    return parsed


if __name__ == "__main__":
    parse_maps()
