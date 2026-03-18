"""
paths.py - Centralized path configuration for the Era Online pipeline.

Paths are computed relative to this file's location so the scripts work
correctly on both Windows (C:\\eo3\\...) and Unix (/c/eo3/...) environments.

Directory layout:
    C:\\eo3\\                          <- SRC_ROOT
        Client\\
        Server\\
        MapEditorSource\\
        GameData\\
        EraOnline\\                   <- PROJECT_ROOT
            tools\\                   <- this file lives here
            data\\                    <- OUTPUT: JSON data
            assets\\graphics\\        <- OUTPUT: copied BMPs
"""

from pathlib import Path

# --- Tool / Project paths ---
TOOLS_DIR    = Path(__file__).parent.resolve()
PROJECT_ROOT = TOOLS_DIR.parent
DATA_DIR     = PROJECT_ROOT / "data"
ASSETS_DIR   = PROJECT_ROOT / "assets"
GRAPHICS_DIR = ASSETS_DIR / "graphics"
SOUNDS_DIR   = ASSETS_DIR / "sounds"
MUSIC_DIR    = ASSETS_DIR / "music"
MAPS_DATA_DIR= DATA_DIR / "maps"

# --- Source VB6 data paths ---
SRC_ROOT        = PROJECT_ROOT.parent   # One level above EraOnline/ = C:\eo3\
SRC_SERVER      = SRC_ROOT / "Server"
SRC_MAP_EDITOR  = SRC_ROOT / "MapEditorSource"
SRC_GAMEDATA    = SRC_ROOT / "GameData"
SRC_GRAPHICS    = SRC_GAMEDATA / "Grh"
SRC_SOUNDS      = SRC_GAMEDATA / "Sound"
SRC_MUSIC       = SRC_GAMEDATA / "Music"
SRC_MAPS        = SRC_SERVER / "Maps"

# --- Individual data files ---
GRH_DAT         = SRC_MAP_EDITOR / "Grh.dat"
OBJ_DAT         = SRC_SERVER / "OBJ.dat"
NPC_DAT         = SRC_SERVER / "NPC.dat"
NPC2_DAT        = SRC_SERVER / "NPC2.dat"
SPELLS_DAT      = SRC_SERVER / "Spells.dat"
BODY_DAT        = SRC_MAP_EDITOR / "body.dat"
HEAD_DAT        = SRC_MAP_EDITOR / "Head.dat"
WPANIM_DAT      = SRC_MAP_EDITOR / "wpanim.dat"
SHANIM_DAT      = SRC_MAP_EDITOR / "shanim.dat"

# --- Output JSON files ---
OUT_GRH         = DATA_DIR / "grh_data.json"
OUT_OBJECTS     = DATA_DIR / "objects.json"
OUT_NPCS        = DATA_DIR / "npcs.json"
OUT_SPELLS      = DATA_DIR / "spells.json"
OUT_BODIES      = DATA_DIR / "bodies.json"
OUT_HEADS       = DATA_DIR / "heads.json"
OUT_WEAPON_ANIMS= DATA_DIR / "weapon_anims.json"
OUT_SHIELD_ANIMS= DATA_DIR / "shield_anims.json"
OUT_MAP_INDEX   = MAPS_DATA_DIR / "map_index.json"


def ensure_output_dirs() -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    MAPS_DATA_DIR.mkdir(parents=True, exist_ok=True)
    GRAPHICS_DIR.mkdir(parents=True, exist_ok=True)
    SOUNDS_DIR.mkdir(parents=True, exist_ok=True)
    MUSIC_DIR.mkdir(parents=True, exist_ok=True)


if __name__ == "__main__":
    print("Path configuration:")
    print(f"  SRC_ROOT:    {SRC_ROOT}")
    print(f"  PROJECT_ROOT:{PROJECT_ROOT}")
    print(f"  DATA_DIR:    {DATA_DIR}")
    print(f"  GRH_DAT:     {GRH_DAT}  exists={GRH_DAT.exists()}")
    print(f"  OBJ_DAT:     {OBJ_DAT}  exists={OBJ_DAT.exists()}")
    print(f"  NPC_DAT:     {NPC_DAT}  exists={NPC_DAT.exists()}")
    print(f"  SRC_MAPS:    {SRC_MAPS}  exists={SRC_MAPS.exists()}")
