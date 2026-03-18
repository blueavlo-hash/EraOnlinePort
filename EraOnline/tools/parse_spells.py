"""
parse_spells.py - Parse Spells.dat (INI format) into spells.json.

Source: /c/eo3/Server/Spells.dat
Output: /c/eo3/EraOnline/data/spells.json
"""

import json
import os
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from parse_ini import INIParser
from paths import SPELLS_DAT, OUT_SPELLS

SRC_PATH = str(SPELLS_DAT)
OUT_PATH  = str(OUT_SPELLS)


def parse_spells(src: str = SRC_PATH, out: str = OUT_PATH) -> int:
    if not os.path.exists(src):
        print(f"[parse_spells] ERROR: Source file not found: {src}")
        return 0

    ini = INIParser(src)
    count = ini.get_int("INIT", "NumSPELLs", 0) or ini.get_int("INIT", "NumSpells", 0)
    if count == 0:
        count = 200  # fallback

    entries: dict[str, dict] = {}

    for i in range(1, count + 1):
        sec = f"SPELL{i}"
        if not ini.has_section(sec):
            continue

        def g(key, default=""): return ini.get(sec, key, default)
        def gi(key, default=0): return ini.get_int(sec, key, default)

        entry = {
            "name":             g("Name"),
            "desc":             g("Desc"),
            "caster_message":   g("CasterMessage"),
            "target_message":   g("TargetMessage"),
            "school1":          g("School1"),
            "school2":          g("School2"),
            "school3":          g("School3"),
            "grh_effect":       gi("GRHEFFECT"),
            "grh_index":        gi("GRHIndex") or gi("GrhIndex"),
            "grh_icon":         gi("GRHICON") or gi("GrhIcon"),
            "sound":            gi("SOUND") or gi("Sound"),
            "needs_mana":       gi("NeedsMana"),
            "give_hp":          gi("GiveHP"),
            "give_man":         gi("GiveMan"),
            "give_fat":         gi("GiveFat"),
            "give_money":       gi("GiveMoney"),
            "give_food":        gi("GiveFood"),
            "give_drink":       gi("GiveDrink"),
            "give_exp":         gi("GiveExp"),
            "heal_hp":          gi("HealHP"),
            "heal_man":         gi("HealMAN") or gi("HealMan"),
            "heal_fat":         gi("HealFAT") or gi("HealFat"),
            "damage_hp":        gi("DamageHP"),
            "damage_man":       gi("DamageMan") or gi("DamageMAn"),
            "damage_fat":       gi("DamageFAT") or gi("DamageFat"),
            "invisibility":     gi("Invisibility"),
            "create_obj":       gi("CreateOBJ") or gi("CreateObj"),
            "teleport":         gi("Teleport"),
            "summon_creature":  gi("SummonCreature"),
            "paralyze":         gi("Paralyze"),
            "destruction":      gi("Destruction"),
            "ressurection":     gi("Ressurection"),  # original typo preserved
        }
        entries[str(i)] = entry

    result = {"count": len(entries), "entries": entries}
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)

    print(f"[parse_spells] Parsed {len(entries)} spells -> {out}")
    return len(entries)


if __name__ == "__main__":
    parse_spells()
