"""
parse_grh.py - Parse the binary Grh.dat file into JSON.

Grh.dat format:
  - 10-byte header (5 x int16, all zeros)
  - Variable-length records until GrhIndex == 0:
    - GrhIndex:   int16
    - NumFrames:  int16
    - IF animated (NumFrames > 1):
        Frames[1..NumFrames]: int16 each
        Speed: int16
        (pixel size derived from first static frame after all are loaded)
    - IF static (NumFrames == 1):
        FileNum:    int16
        sX:         int16
        sY:         int16
        pixelWidth: int16
        pixelHeight:int16
    - TileWidth  = pixelWidth  / 32.0  (computed, not stored)
    - TileHeight = pixelHeight / 32.0  (computed, not stored)
"""

import struct
import json
import os
import sys
from pathlib import Path

# Allow running from any directory
sys.path.insert(0, str(Path(__file__).parent))
from paths import GRH_DAT, OUT_GRH

SRC_PATH = str(GRH_DAT)
OUT_PATH = str(OUT_GRH)
TILE_SIZE = 32


def read_int16(data: bytes, offset: int) -> tuple[int, int]:
    """Read a signed 16-bit little-endian integer, return (value, new_offset)."""
    val = struct.unpack_from("<h", data, offset)[0]
    return val, offset + 2


def parse_grh(src: str = SRC_PATH, out: str = OUT_PATH) -> int:
    if not os.path.exists(src):
        print(f"[parse_grh] ERROR: Source file not found: {src}")
        return 0

    with open(src, "rb") as f:
        data = f.read()

    # Skip 10-byte header (5 x int16, all zeros)
    offset = 10
    entries: dict[int, dict] = {}

    # Pass 1: Load all static entries and collect animated entries
    animated_pending: list[tuple[int, dict]] = []  # (grh_index, entry)

    while offset < len(data):
        if offset + 2 > len(data):
            break

        grh_index, offset = read_int16(data, offset)
        if grh_index == 0:
            break
        if offset + 2 > len(data):
            break

        num_frames, offset = read_int16(data, offset)

        if num_frames > 1:
            # Animated entry
            frames = []
            for _ in range(num_frames):
                if offset + 2 > len(data):
                    break
                frame_idx, offset = read_int16(data, offset)
                frames.append(frame_idx)
            speed, offset = read_int16(data, offset)
            entry = {
                "num_frames": num_frames,
                "frames": frames,
                "speed": speed,
                # pixel size resolved in pass 2
                "file_num": 0,
                "sx": 0,
                "sy": 0,
                "pixel_width": 0,
                "pixel_height": 0,
            }
            entries[grh_index] = entry
            animated_pending.append((grh_index, entry))
        else:
            # Static entry
            file_num, offset = read_int16(data, offset)
            sx, offset = read_int16(data, offset)
            sy, offset = read_int16(data, offset)
            pixel_width, offset = read_int16(data, offset)
            pixel_height, offset = read_int16(data, offset)

            if sy < 0:
                # VB6 error handler would have stopped here; skip
                continue

            entry = {
                "num_frames": 1,
                "frames": [grh_index],
                "speed": 0,
                "file_num": file_num,
                "sx": sx,
                "sy": sy,
                "pixel_width": pixel_width,
                "pixel_height": pixel_height,
            }
            entries[grh_index] = entry

    # Pass 2: Resolve pixel sizes for animated entries from their first frame
    for grh_index, entry in animated_pending:
        frames = entry["frames"]
        if not frames:
            continue
        first_frame_idx = frames[0]
        # Walk the chain to find a static entry
        visited = set()
        idx = first_frame_idx
        while idx in entries and idx not in visited:
            visited.add(idx)
            first = entries[idx]
            if first["num_frames"] == 1:
                entry["file_num"] = first["file_num"]
                entry["sx"] = first["sx"]
                entry["sy"] = first["sy"]
                entry["pixel_width"] = first["pixel_width"]
                entry["pixel_height"] = first["pixel_height"]
                break
            # Animated pointing to animated - follow first frame
            next_frames = first.get("frames", [])
            if not next_frames:
                break
            idx = next_frames[0]

    # Convert keys to strings for JSON
    entries_str = {str(k): v for k, v in entries.items()}

    result = {"count": len(entries), "entries": entries_str}

    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

    print(f"[parse_grh] Parsed {len(entries)} GRH entries -> {out}")
    return len(entries)


if __name__ == "__main__":
    parse_grh()
