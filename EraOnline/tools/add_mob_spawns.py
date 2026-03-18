import json

path = "C:/eo3/EraOnline/data/npc_spawns.json"
with open(path) as f:
    spawns = json.load(f)

def add_mobs(map_id, entries):
    key = str(map_id)
    if key not in spawns:
        spawns[key] = []
    spawns[key].extend(entries)

# TIER 1: Easy (bats=508, giant snake=509, spiderling=510, chicken=516, pig=515, tree snake=528)
add_mobs(2,  [{"npc_index":508,"x":20,"y":30},{"npc_index":509,"x":40,"y":25},
              {"npc_index":510,"x":60,"y":50},{"npc_index":508,"x":75,"y":70},
              {"npc_index":528,"x":15,"y":65},{"npc_index":516,"x":50,"y":80}])
add_mobs(4,  [{"npc_index":509,"x":25,"y":20},{"npc_index":510,"x":55,"y":35},
              {"npc_index":528,"x":80,"y":60},{"npc_index":508,"x":35,"y":75},
              {"npc_index":515,"x":65,"y":15},{"npc_index":516,"x":45,"y":55}])
add_mobs(5,  [{"npc_index":508,"x":30,"y":40},{"npc_index":510,"x":70,"y":25},
              {"npc_index":528,"x":20,"y":70},{"npc_index":509,"x":85,"y":45},
              {"npc_index":515,"x":50,"y":90}])
add_mobs(6,  [{"npc_index":510,"x":15,"y":35},{"npc_index":508,"x":45,"y":60},
              {"npc_index":516,"x":72,"y":30},{"npc_index":528,"x":88,"y":75},
              {"npc_index":509,"x":35,"y":88}])
add_mobs(7,  [{"npc_index":509,"x":22,"y":18},{"npc_index":510,"x":55,"y":42},
              {"npc_index":515,"x":78,"y":65},{"npc_index":508,"x":38,"y":80},
              {"npc_index":528,"x":68,"y":20}])
add_mobs(8,  [{"npc_index":516,"x":30,"y":50},{"npc_index":509,"x":62,"y":38},
              {"npc_index":508,"x":82,"y":22},{"npc_index":510,"x":18,"y":72},
              {"npc_index":515,"x":48,"y":88}])
add_mobs(9,  [{"npc_index":509,"x":40,"y":30},{"npc_index":510,"x":70,"y":55},
              {"npc_index":528,"x":25,"y":80},{"npc_index":508,"x":58,"y":15},
              {"npc_index":515,"x":85,"y":70}])

# TIER 2: Medium-Easy (gnoll=526, bandit=9, brown bear=531, deer=512, skeleton=502)
add_mobs(11, [{"npc_index":526,"x":28,"y":35},{"npc_index":9,"x":58,"y":22},
              {"npc_index":531,"x":75,"y":60},{"npc_index":512,"x":42,"y":78},
              {"npc_index":526,"x":88,"y":40},{"npc_index":513,"x":15,"y":55}])
add_mobs(12, [{"npc_index":9,"x":35,"y":28},{"npc_index":526,"x":65,"y":48},
              {"npc_index":531,"x":22,"y":68},{"npc_index":512,"x":80,"y":30},
              {"npc_index":9,"x":50,"y":85}])
add_mobs(13, [{"npc_index":531,"x":20,"y":42},{"npc_index":526,"x":50,"y":25},
              {"npc_index":502,"x":72,"y":65},{"npc_index":9,"x":38,"y":82},
              {"npc_index":531,"x":85,"y":50}])
add_mobs(14, [{"npc_index":526,"x":32,"y":55},{"npc_index":512,"x":62,"y":30},
              {"npc_index":9,"x":80,"y":72},{"npc_index":502,"x":18,"y":85},
              {"npc_index":526,"x":48,"y":18}])
add_mobs(16, [{"npc_index":9,"x":30,"y":22},{"npc_index":526,"x":60,"y":45},
              {"npc_index":502,"x":82,"y":68},{"npc_index":531,"x":22,"y":75},
              {"npc_index":9,"x":48,"y":90}])
add_mobs(19, [{"npc_index":526,"x":35,"y":48},{"npc_index":502,"x":65,"y":25},
              {"npc_index":9,"x":85,"y":62},{"npc_index":531,"x":20,"y":88},
              {"npc_index":512,"x":52,"y":72}])
add_mobs(21, [{"npc_index":502,"x":28,"y":55},{"npc_index":9,"x":58,"y":32},
              {"npc_index":526,"x":78,"y":75},{"npc_index":531,"x":42,"y":18},
              {"npc_index":9,"x":88,"y":45}])

# TIER 3: Medium (orc=521, troll=523, gnome=511, desert troll=506, follower=520)
add_mobs(30, [{"npc_index":521,"x":32,"y":45},{"npc_index":523,"x":62,"y":28},
              {"npc_index":511,"x":80,"y":65},{"npc_index":521,"x":20,"y":80},
              {"npc_index":506,"x":50,"y":18},{"npc_index":523,"x":88,"y":52}])
add_mobs(35, [{"npc_index":523,"x":25,"y":38},{"npc_index":521,"x":55,"y":55},
              {"npc_index":506,"x":78,"y":25},{"npc_index":511,"x":38,"y":78},
              {"npc_index":521,"x":85,"y":68}])
add_mobs(40, [{"npc_index":506,"x":30,"y":52},{"npc_index":521,"x":62,"y":35},
              {"npc_index":523,"x":82,"y":72},{"npc_index":511,"x":18,"y":62},
              {"npc_index":520,"x":50,"y":88},{"npc_index":506,"x":72,"y":18}])
add_mobs(45, [{"npc_index":521,"x":28,"y":42},{"npc_index":520,"x":58,"y":65},
              {"npc_index":506,"x":78,"y":30},{"npc_index":523,"x":40,"y":85},
              {"npc_index":511,"x":88,"y":55}])
add_mobs(50, [{"npc_index":523,"x":35,"y":48},{"npc_index":521,"x":65,"y":22},
              {"npc_index":520,"x":82,"y":70},{"npc_index":506,"x":22,"y":78},
              {"npc_index":521,"x":50,"y":35}])
add_mobs(55, [{"npc_index":506,"x":25,"y":35},{"npc_index":520,"x":55,"y":58},
              {"npc_index":523,"x":80,"y":28},{"npc_index":521,"x":38,"y":82},
              {"npc_index":511,"x":88,"y":60}])
add_mobs(60, [{"npc_index":520,"x":32,"y":45},{"npc_index":523,"x":62,"y":25},
              {"npc_index":506,"x":80,"y":68},{"npc_index":521,"x":20,"y":72},
              {"npc_index":520,"x":50,"y":90}])
add_mobs(65, [{"npc_index":521,"x":28,"y":52},{"npc_index":506,"x":58,"y":32},
              {"npc_index":523,"x":78,"y":72},{"npc_index":520,"x":42,"y":85},
              {"npc_index":511,"x":85,"y":45}])
add_mobs(70, [{"npc_index":506,"x":30,"y":38},{"npc_index":521,"x":60,"y":62},
              {"npc_index":520,"x":82,"y":28},{"npc_index":523,"x":22,"y":78},
              {"npc_index":511,"x":52,"y":88}])
add_mobs(75, [{"npc_index":523,"x":35,"y":55},{"npc_index":520,"x":65,"y":30},
              {"npc_index":506,"x":85,"y":68},{"npc_index":521,"x":20,"y":88},
              {"npc_index":511,"x":48,"y":20}])

# TIER 4: Hard (wraith=525, minotaur=533, polar bear=532, cyclop whelp=529, beholder=505)
add_mobs(85, [{"npc_index":525,"x":32,"y":45},{"npc_index":533,"x":62,"y":28},
              {"npc_index":532,"x":80,"y":65},{"npc_index":529,"x":22,"y":75},
              {"npc_index":525,"x":50,"y":88}])
add_mobs(90, [{"npc_index":533,"x":28,"y":52},{"npc_index":525,"x":58,"y":35},
              {"npc_index":529,"x":80,"y":72},{"npc_index":532,"x":40,"y":82},
              {"npc_index":505,"x":85,"y":48}])
add_mobs(95, [{"npc_index":529,"x":25,"y":38},{"npc_index":533,"x":55,"y":62},
              {"npc_index":525,"x":78,"y":28},{"npc_index":505,"x":38,"y":80},
              {"npc_index":532,"x":88,"y":55}])
add_mobs(100,[{"npc_index":505,"x":30,"y":48},{"npc_index":525,"x":60,"y":25},
              {"npc_index":533,"x":82,"y":70},{"npc_index":529,"x":18,"y":70},
              {"npc_index":532,"x":52,"y":88}])
add_mobs(105,[{"npc_index":525,"x":35,"y":55},{"npc_index":529,"x":65,"y":32},
              {"npc_index":505,"x":85,"y":68},{"npc_index":533,"x":22,"y":82},
              {"npc_index":532,"x":48,"y":18}])
add_mobs(110,[{"npc_index":533,"x":28,"y":42},{"npc_index":505,"x":58,"y":65},
              {"npc_index":525,"x":78,"y":28},{"npc_index":529,"x":42,"y":85},
              {"npc_index":532,"x":88,"y":52}])

# TIER 5: Very Hard (mummy=527, zombie=503, daemon=524, serpent man=501, devil angel=507)
add_mobs(116,[{"npc_index":527,"x":32,"y":48},{"npc_index":503,"x":62,"y":28},
              {"npc_index":524,"x":80,"y":68},{"npc_index":501,"x":22,"y":78},
              {"npc_index":507,"x":50,"y":18},{"npc_index":527,"x":85,"y":45}])
add_mobs(120,[{"npc_index":503,"x":28,"y":55},{"npc_index":524,"x":58,"y":30},
              {"npc_index":527,"x":80,"y":72},{"npc_index":507,"x":40,"y":88},
              {"npc_index":501,"x":88,"y":52}])
add_mobs(125,[{"npc_index":524,"x":25,"y":42},{"npc_index":527,"x":55,"y":65},
              {"npc_index":507,"x":78,"y":28},{"npc_index":503,"x":38,"y":82},
              {"npc_index":501,"x":85,"y":55}])
add_mobs(130,[{"npc_index":501,"x":30,"y":52},{"npc_index":524,"x":60,"y":28},
              {"npc_index":503,"x":82,"y":70},{"npc_index":507,"x":20,"y":78},
              {"npc_index":527,"x":50,"y":90}])
add_mobs(135,[{"npc_index":507,"x":35,"y":45},{"npc_index":501,"x":65,"y":68},
              {"npc_index":524,"x":82,"y":32},{"npc_index":527,"x":22,"y":82},
              {"npc_index":503,"x":50,"y":18}])

# TIER 6: Endgame (snow yeti=522, cyclop=530, werewolf=500, air elemental=504)
add_mobs(141,[{"npc_index":522,"x":30,"y":48},{"npc_index":530,"x":60,"y":28},
              {"npc_index":500,"x":80,"y":68},{"npc_index":504,"x":22,"y":75},
              {"npc_index":522,"x":50,"y":88}])
add_mobs(143,[{"npc_index":530,"x":28,"y":55},{"npc_index":500,"x":58,"y":32},
              {"npc_index":522,"x":80,"y":72},{"npc_index":504,"x":40,"y":85},
              {"npc_index":530,"x":85,"y":48}])
add_mobs(145,[{"npc_index":500,"x":25,"y":42},{"npc_index":522,"x":55,"y":62},
              {"npc_index":504,"x":78,"y":28},{"npc_index":530,"x":38,"y":82},
              {"npc_index":500,"x":88,"y":55}])
add_mobs(150,[{"npc_index":504,"x":32,"y":50},{"npc_index":530,"x":62,"y":28},
              {"npc_index":522,"x":80,"y":70},{"npc_index":500,"x":20,"y":80},
              {"npc_index":504,"x":50,"y":90}])
add_mobs(160,[{"npc_index":530,"x":28,"y":45},{"npc_index":522,"x":58,"y":68},
              {"npc_index":504,"x":78,"y":28},{"npc_index":500,"x":42,"y":85},
              {"npc_index":530,"x":85,"y":52}])
add_mobs(170,[{"npc_index":500,"x":30,"y":52},{"npc_index":504,"x":60,"y":32},
              {"npc_index":530,"x":82,"y":70},{"npc_index":522,"x":22,"y":78},
              {"npc_index":500,"x":50,"y":90}])

# Dragon lair deep in the world
add_mobs(190,[{"npc_index":534,"x":50,"y":50},{"npc_index":530,"x":35,"y":40},
              {"npc_index":530,"x":65,"y":40},{"npc_index":522,"x":40,"y":65},
              {"npc_index":522,"x":60,"y":65}])

with open(path, "w") as f:
    json.dump(spawns, f, indent="\t")

total = sum(len(v) for v in spawns.values())
print("Done. %d maps, %d total spawn entries." % (len(spawns), total))
