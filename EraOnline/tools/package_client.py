"""
package_client.py — Build the EraOnline client distribution zip.

Run this AFTER exporting the Godot project via:
  Project → Export → Windows Desktop → Export Project → build/EraOnline.exe

Usage:
    python tools/package_client.py [version]

Default version: 0.5.1-alpha
Output: build/EraOnline-v{version}-client.zip
"""

import os
import sys
import zipfile
from pathlib import Path

VERSION = sys.argv[1] if len(sys.argv) > 1 else "0.5.1-alpha"

REPO_ROOT   = Path(__file__).resolve().parent.parent.parent  # C:/eo3
BUILD_DIR   = REPO_ROOT / "EraOnline" / "build"
EXE         = BUILD_DIR / "EraOnline.exe"
GRAPHICS    = REPO_ROOT / "EraOnline" / "assets" / "graphics"
OUT_ZIP     = BUILD_DIR / f"EraOnline-v{VERSION}-client.zip"

if not EXE.exists():
    print(f"ERROR: {EXE} not found — export the Godot project first.")
    sys.exit(1)

print(f"Packaging Era Online v{VERSION}...")
print(f"  EXE:      {EXE} ({EXE.stat().st_size / 1e6:.1f} MB)")
print(f"  Graphics: {GRAPHICS}")
print(f"  Output:   {OUT_ZIP}")

with zipfile.ZipFile(OUT_ZIP, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=1) as z:
    # Add the exe
    z.write(EXE, "EraOnline.exe")
    print("  + EraOnline.exe")

    # Add all graphics files (skip .import editor artifacts)
    count = 0
    for f in sorted(GRAPHICS.iterdir()):
        if f.suffix.lower() == ".import":
            continue
        z.write(f, f"assets/graphics/{f.name}")
        count += 1
    print(f"  + {count} graphics files")

size_mb = OUT_ZIP.stat().st_size / 1e6
print(f"\nDone! {OUT_ZIP.name} ({size_mb:.1f} MB)")
print(f"\nNext steps:")
print(f"  1. Upload {OUT_ZIP.name} to the v0.5.0-alpha GitHub release")
print(f"  2. git add public/launcher/latest.json && git commit -m 'game v{VERSION}'")
print(f"  3. git push")
