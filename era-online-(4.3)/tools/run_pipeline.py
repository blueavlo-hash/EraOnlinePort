"""
run_pipeline.py - Master data pipeline for Era Online VB6 -> Godot 4 port.

Run this script once (and again any time original data changes) to:
  1. Parse all VB6 binary/INI data files into JSON
  2. Copy graphics assets to the Godot project
  3. Copy sound assets to the Godot project
  4. Report any errors

Usage:
    cd /c/eo3/EraOnline/tools/
    python run_pipeline.py
"""

import os
import sys
import shutil
import time
import glob

# Ensure the tools directory is in path for sibling imports
TOOLS_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS_DIR)

from parse_grh          import parse_grh
from parse_objects      import parse_objects
from parse_npcs         import parse_npcs
from parse_spells       import parse_spells
from parse_bodies       import parse_bodies
from parse_heads        import parse_heads
from parse_weapon_anims import parse_weapon_anims
from parse_shield_anims import parse_shield_anims
from parse_maps         import parse_maps

# Project paths
PROJECT_ROOT   = os.path.dirname(TOOLS_DIR)
DATA_DIR       = os.path.join(PROJECT_ROOT, "data")
ASSETS_DIR     = os.path.join(PROJECT_ROOT, "assets")
GRAPHICS_DIR   = os.path.join(ASSETS_DIR, "graphics")
SOUNDS_DIR     = os.path.join(ASSETS_DIR, "sounds")
MUSIC_DIR      = os.path.join(ASSETS_DIR, "music")

# Source paths
from paths import SRC_GRAPHICS, SRC_SOUNDS, SRC_MUSIC
SRC_GRAPHICS   = str(SRC_GRAPHICS)
SRC_SOUNDS     = str(SRC_SOUNDS)
SRC_MUSIC      = str(SRC_MUSIC)

DIVIDER = "=" * 60


def step(name: str) -> None:
    print(f"\n{DIVIDER}")
    print(f"  {name}")
    print(DIVIDER)


def copy_assets(src_dir: str, dst_dir: str, extensions: list[str], label: str) -> int:
    if not os.path.exists(src_dir):
        print(f"  [warn] Source directory not found: {src_dir}")
        return 0
    os.makedirs(dst_dir, exist_ok=True)
    copied = 0
    skipped = 0
    for ext in extensions:
        pattern = os.path.join(src_dir, f"*.{ext}")
        for src_file in glob.glob(pattern):
            dst_file = os.path.join(dst_dir, os.path.basename(src_file))
            if os.path.exists(dst_file):
                skipped += 1
                continue
            shutil.copy2(src_file, dst_file)
            copied += 1
    print(f"  {label}: {copied} copied, {skipped} already present -> {dst_dir}")
    return copied


def run_step(name: str, func, *args, **kwargs) -> tuple[bool, int]:
    step(name)
    start = time.time()
    try:
        result = func(*args, **kwargs)
        elapsed = time.time() - start
        print(f"  Done in {elapsed:.2f}s")
        return True, result or 0
    except Exception as e:
        print(f"  ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False, 0


def main() -> None:
    print(f"\n{'#' * 60}")
    print("  Era Online - Data Pipeline")
    print(f"  Project: {PROJECT_ROOT}")
    print(f"{'#' * 60}")

    # Create output directories
    os.makedirs(DATA_DIR, exist_ok=True)
    os.makedirs(os.path.join(DATA_DIR, "maps"), exist_ok=True)
    os.makedirs(GRAPHICS_DIR, exist_ok=True)
    os.makedirs(SOUNDS_DIR, exist_ok=True)
    os.makedirs(MUSIC_DIR, exist_ok=True)

    results = {}
    errors  = []

    # --- Parse data files ---
    ok, n = run_step("Parsing GRH animation data (Grh.dat)", parse_grh)
    results["grh"] = n
    if not ok: errors.append("grh")

    ok, n = run_step("Parsing objects (OBJ.dat)", parse_objects)
    results["objects"] = n
    if not ok: errors.append("objects")

    ok, n = run_step("Parsing NPCs (NPC.dat + NPC2.dat)", parse_npcs)
    results["npcs"] = n
    if not ok: errors.append("npcs")

    ok, n = run_step("Parsing spells (Spells.dat)", parse_spells)
    results["spells"] = n
    if not ok: errors.append("spells")

    ok, n = run_step("Parsing body animations (body.dat)", parse_bodies)
    results["bodies"] = n
    if not ok: errors.append("bodies")

    ok, n = run_step("Parsing head animations (Head.dat)", parse_heads)
    results["heads"] = n
    if not ok: errors.append("heads")

    ok, n = run_step("Parsing weapon animations (wpanim.dat)", parse_weapon_anims)
    results["weapon_anims"] = n
    if not ok: errors.append("weapon_anims")

    ok, n = run_step("Parsing shield animations (shanim.dat)", parse_shield_anims)
    results["shield_anims"] = n
    if not ok: errors.append("shield_anims")

    ok, n = run_step("Parsing maps (Maps/*.map/.inf/.obj/.dat)", parse_maps)
    results["maps"] = n
    if not ok: errors.append("maps")

    # --- Copy assets ---
    step("Copying graphics assets")
    g_copied = copy_assets(SRC_GRAPHICS, GRAPHICS_DIR, ["bmp", "BMP", "jpg", "JPG", "jpeg", "JPEG"], "Graphics")

    step("Copying sound assets")
    s_copied = copy_assets(SRC_SOUNDS, SOUNDS_DIR, ["wav", "WAV", "mp3", "MP3"], "Sounds")

    step("Checking music assets")
    midi_files = glob.glob(os.path.join(SRC_MUSIC, "*.mid")) + glob.glob(os.path.join(SRC_MUSIC, "*.MID"))
    ogg_files  = glob.glob(os.path.join(MUSIC_DIR, "*.ogg"))
    if ogg_files:
        print(f"  Music: {len(ogg_files)} OGG files already in {MUSIC_DIR}")
    else:
        print(f"  Music: {len(midi_files)} MIDI files need conversion.")
        print()
        print("  To convert MIDI -> OGG, install FluidSynth + ffmpeg, then run:")
        print("  (You'll need a soundfont .sf2 file, e.g. GeneralUser GS)")
        print()
        print("  On Windows (PowerShell):")
        sf2 = "C:/soundfonts/GeneralUser.sf2"
        midi_src = str(SRC_MUSIC)
        ogg_dst  = str(MUSIC_DIR)
        print(f"  $sf2='{sf2}'")
        print(f"  for ($i=1; $i -le 32; $i++) {{")
        print(f"      fluidsynth -ni $sf2 '{midi_src}/Mus$i.mid' -F '{ogg_dst}/Mus$i.wav' -r 44100")
        print(f"      ffmpeg -i '{ogg_dst}/Mus$i.wav' '{ogg_dst}/Mus$i.ogg'")
        print(f"      Remove-Item '{ogg_dst}/Mus$i.wav'")
        print(f"  }}")

    # --- Summary ---
    print(f"\n{'#' * 60}")
    print("  PIPELINE COMPLETE")
    print(f"{'#' * 60}")
    print(f"  GRH entries:     {results.get('grh', 0)}")
    print(f"  Objects:         {results.get('objects', 0)}")
    print(f"  NPCs:            {results.get('npcs', 0)}")
    print(f"  Spells:          {results.get('spells', 0)}")
    print(f"  Body anims:      {results.get('bodies', 0)}")
    print(f"  Head anims:      {results.get('heads', 0)}")
    print(f"  Weapon anims:    {results.get('weapon_anims', 0)}")
    print(f"  Shield anims:    {results.get('shield_anims', 0)}")
    print(f"  Maps:            {results.get('maps', 0)}")
    print(f"  Graphics copied: {g_copied}")
    print(f"  Sounds copied:   {s_copied}")

    if errors:
        print(f"\n  ERRORS in: {', '.join(errors)}")
        print("  Check output above for details.")
        sys.exit(1)
    else:
        print("\n  All steps completed successfully!")
        print(f"  Open Godot 4 and import: {PROJECT_ROOT}")


if __name__ == "__main__":
    main()
