package gamedata

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// GameData holds all loaded static game data.
type GameData struct {
	Maps    map[int]*MapData
	NPCs    map[int]*NPCData
	Objects map[int]*ObjectData
	Spells  map[int]*SpellData
	// HardcodedSpawns: map_id → list of extra NPC spawns from npc_spawns.json.
	HardcodedSpawns map[int][]HardcodedSpawn
}

// HardcodedSpawn is one entry from npc_spawns.json.
// Either NpcIndex > 0 (reference existing NPC def) or Def is non-nil (inline def).
type HardcodedSpawn struct {
	X   int
	Y   int
	// One of these is set:
	NpcIndex int      // reference to existing NPCData
	Def      *NPCData // inline definition (custom NPC)
}

// Load reads all game data JSON files from the given directory.
// Expected files: maps/map_N.json, npcs.json, objects.json, spells.json
func Load(dir string) (*GameData, error) {
	gd := &GameData{
		Maps:            make(map[int]*MapData),
		NPCs:            make(map[int]*NPCData),
		Objects:         make(map[int]*ObjectData),
		Spells:          make(map[int]*SpellData),
		HardcodedSpawns: make(map[int][]HardcodedSpawn),
	}

	mapsDir := filepath.Join(dir, "maps")
	entries, err := os.ReadDir(mapsDir)
	if err != nil {
		return nil, fmt.Errorf("gamedata: read maps dir %s: %w", mapsDir, err)
	}
	for _, e := range entries {
		if e.IsDir() || filepath.Ext(e.Name()) != ".json" {
			continue
		}
		m, err := loadMap(filepath.Join(mapsDir, e.Name()))
		if err != nil {
			return nil, fmt.Errorf("gamedata: load map %s: %w", e.Name(), err)
		}
		base := e.Name()[:len(e.Name())-5]
		if len(base) > 4 {
			if idStr := base[4:]; idStr != "" {
				if id, err := strconv.Atoi(idStr); err == nil {
					m.ID = id
				}
			}
		}
		gd.Maps[m.ID] = m
	}

	npcs, err := loadNPCs(filepath.Join(dir, "npcs.json"))
	if err != nil {
		return nil, fmt.Errorf("gamedata: load npcs.json: %w", err)
	}
	for i := range npcs {
		gd.NPCs[npcs[i].Index] = &npcs[i]
	}

	objects, err := loadObjects(filepath.Join(dir, "objects.json"))
	if err != nil {
		return nil, fmt.Errorf("gamedata: load objects.json: %w", err)
	}
	for i := range objects {
		gd.Objects[objects[i].Index] = &objects[i]
	}

	spells, err := loadSpells(filepath.Join(dir, "spells.json"))
	if err != nil {
		spells = nil
	}
	for i := range spells {
		gd.Spells[spells[i].Index] = &spells[i]
	}

	// Load npc_spawns.json (optional — missing file is not an error).
	spawnsPath := filepath.Join(dir, "npc_spawns.json")
	if _, statErr := os.Stat(spawnsPath); statErr == nil {
		hardcoded, loadErr := loadNPCSpawns(spawnsPath, gd.NPCs)
		if loadErr == nil {
			gd.HardcodedSpawns = hardcoded
		}
	}

	return gd, nil
}

// GetMap returns the MapData for the given map ID, or nil if not found.
func (gd *GameData) GetMap(id int) *MapData { return gd.Maps[id] }

// GetNPC returns the NPCData for the given NPC index, or nil if not found.
func (gd *GameData) GetNPC(index int) *NPCData { return gd.NPCs[index] }

// GetObject returns the ObjectData for the given object index, or nil.
func (gd *GameData) GetObject(index int) *ObjectData { return gd.Objects[index] }

// GetSpell returns the SpellData for the given spell index, or nil.
func (gd *GameData) GetSpell(index int) *SpellData { return gd.Spells[index] }

func loadJSON(path string, v any) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	return json.NewDecoder(f).Decode(v)
}

type mapExport struct {
	Name       string                   `json:"name"`
	Music      string                   `json:"music"`
	PKFreeZone bool                     `json:"pk_free_zone"`
	NorthExit  float64                  `json:"north_exit"`
	SouthExit  float64                  `json:"south_exit"`
	WestExit   float64                  `json:"west_exit"`
	EastExit   float64                  `json:"east_exit"`
	Tiles      map[string]mapTileExport `json:"tiles"`
}

type mapTileExport struct {
	Blocked  any       `json:"blocked"`
	Layers   []float64 `json:"layers"`
	ExitMap  float64   `json:"exit_map"`
	ExitX    float64   `json:"exit_x"`
	ExitY    float64   `json:"exit_y"`
	NPCIndex float64   `json:"npc_index"`
	ObjIndex float64   `json:"obj_index"`
	ObjAmt   float64   `json:"obj_amount"`
}

func loadMap(path string) (*MapData, error) {
	var raw mapExport
	if err := loadJSON(path, &raw); err != nil {
		return nil, err
	}

	m := &MapData{
		Name:      raw.Name,
		MusicNum:  parseLeadingInt(raw.Music),
		PKZone:    raw.PKFreeZone,
		NorthExit: int(raw.NorthExit),
		SouthExit: int(raw.SouthExit),
		WestExit:  int(raw.WestExit),
		EastExit:  int(raw.EastExit),
		Tiles:     make(map[string]MapTile, len(raw.Tiles)),
	}
	for key, tile := range raw.Tiles {
		var layers [3]int
		for i := 0; i < len(tile.Layers) && i < len(layers); i++ {
			layers[i] = int(tile.Layers[i])
		}
		m.Tiles[key] = MapTile{
			Blocked:  anyToBool(tile.Blocked),
			Layers:   layers,
			ExitMap:  int(tile.ExitMap),
			ExitX:    int(tile.ExitX),
			ExitY:    int(tile.ExitY),
			NPCIndex: int(tile.NPCIndex),
			ObjIndex: int(tile.ObjIndex),
			ObjAmt:   int(tile.ObjAmt),
		}
	}
	return m, nil
}

type npcFileExport struct {
	Entries map[string]npcExport `json:"entries"`
}

type npcExport struct {
	Name       string          `json:"name"`
	Desc       string          `json:"desc"`
	Head       int             `json:"head"`
	Body       int             `json:"body"`
	Heading    int             `json:"heading"`
	Movement   int             `json:"movement"`
	NPCType    int             `json:"npc_type"`
	WeaponAnim int             `json:"weapon_anim"`
	ShieldAnim int             `json:"shield_anim"`
	Hostile    int             `json:"hostile"`
	Attackable int             `json:"attackable"`
	Tameable   int             `json:"tameable"`
	DeathObj   int             `json:"death_obj"`
	GiveGold   int             `json:"give_gld"`
	MinHP      int             `json:"min_hp"`
	MaxHP      int             `json:"max_hp"`
	MinHit     int             `json:"min_hit"`
	MaxHit     int             `json:"max_hit"`
	Defense    int             `json:"def"`
	GiveExp    int             `json:"give_exp"`
	Inventory  []npcItemExport `json:"inventory"`
}

type npcItemExport struct {
	ObjIndex int `json:"obj_index"`
}

func loadNPCs(path string) ([]NPCData, error) {
	var raw npcFileExport
	if err := loadJSON(path, &raw); err != nil {
		return nil, err
	}

	npcs := make([]NPCData, 0, len(raw.Entries))
	for key, entry := range raw.Entries {
		index, err := strconv.Atoi(key)
		if err != nil {
			continue
		}
		npc := NPCData{
			Index:      index,
			Name:       entry.Name,
			Desc:       entry.Desc,
			Head:       entry.Head,
			Body:       entry.Body,
			Heading:    entry.Heading,
			Movement:   entry.Movement,
			NPCType:    entry.NPCType,
			WeaponAnim: entry.WeaponAnim,
			ShieldAnim: entry.ShieldAnim,
			Hostile:    entry.Hostile != 0,
			Attackable: entry.Attackable != 0,
			Tameable:   entry.Tameable != 0,
			DeathObj:   entry.DeathObj,
			Gold:       entry.GiveGold,
			MinHP:      entry.MinHP,
			MaxHP:      entry.MaxHP,
			MinDmg:     entry.MinHit,
			MaxDmg:     entry.MaxHit,
			Defense:    entry.Defense,
			ExpReward:  entry.GiveExp,
			Vendor:     len(entry.Inventory) > 0,
		}
		for i, item := range entry.Inventory {
			if i >= len(npc.ShopItems) {
				break
			}
			npc.ShopItems[i] = item.ObjIndex
		}
		npcs = append(npcs, npc)
	}
	return npcs, nil
}

type objectFileExport struct {
	Entries map[string]objectExport `json:"entries"`
}

type objectExport struct {
	Name         string `json:"name"`
	GrhIndex     int    `json:"grh_index"`
	ObjType      int    `json:"obj_type"`
	Value        string `json:"value"`
	Pickable     int    `json:"pickable"`
	Sellable     int    `json:"sellable"`
	Food         int    `json:"food"`
	Level        int    `json:"level"`
	MinHit       int    `json:"min_hit"`
	MaxHit       int    `json:"max_hit"`
	Defense      int    `json:"def"`
	ClothingType int    `json:"clothing_type"`
	WeaponAnim   int    `json:"weapon_anim"`
	ShieldAnim   int    `json:"shield_anim"`
}

func loadObjects(path string) ([]ObjectData, error) {
	var raw objectFileExport
	if err := loadJSON(path, &raw); err != nil {
		return nil, err
	}

	objects := make([]ObjectData, 0, len(raw.Entries))
	for key, entry := range raw.Entries {
		index, err := strconv.Atoi(key)
		if err != nil {
			continue
		}
		objects = append(objects, ObjectData{
			Index:        index,
			Name:         entry.Name,
			GrhIndex:     entry.GrhIndex,
			ObjType:      entry.ObjType,
			MinHit:       entry.MinHit,
			MaxHit:       entry.MaxHit,
			Defense:      entry.Defense,
			Value:        parseLeadingInt(entry.Value),
			Pickable:     entry.Pickable != 0,
			Sellable:     entry.Sellable != 0,
			Food:         entry.Food,
			Level:        entry.Level,
			WeaponAnim:   entry.WeaponAnim,
			ShieldAnim:   entry.ShieldAnim,
			ClothingType: entry.ClothingType,
		})
	}
	return objects, nil
}

type spellFileExport struct {
	Entries map[string]spellExport `json:"entries"`
}

type spellExport struct {
	Name       string  `json:"name"`
	Desc       string  `json:"desc"`
	TargetType int     `json:"target_type"`
	NeedsMana  int     `json:"needs_mana"`
	HealHP     int     `json:"heal_hp"`
	DamageHP   int     `json:"damage_hp"`
	Cooldown   float64 `json:"cooldown"`
	Range      int     `json:"range"`
}

func loadSpells(path string) ([]SpellData, error) {
	var raw spellFileExport
	if err := loadJSON(path, &raw); err != nil {
		return nil, err
	}

	spells := make([]SpellData, 0, len(raw.Entries))
	for key, entry := range raw.Entries {
		index, err := strconv.Atoi(key)
		if err != nil {
			continue
		}

		effect := 0
		minEffect := 0
		maxEffect := 0
		switch {
		case entry.DamageHP > 0:
			effect = 1
			minEffect = entry.DamageHP
			maxEffect = entry.DamageHP
		case entry.HealHP > 0:
			effect = -1
			minEffect = entry.HealHP
			maxEffect = entry.HealHP
		}

		spells = append(spells, SpellData{
			Index:     index,
			Name:      entry.Name,
			Desc:      entry.Desc,
			SpellType: entry.TargetType,
			Effect:    effect,
			MinEffect: minEffect,
			MaxEffect: maxEffect,
			MPCost:    entry.NeedsMana,
			Cooldown:  int(entry.Cooldown * 1000),
			Range:     entry.Range,
		})
	}
	return spells, nil
}

func anyToBool(v any) bool {
	switch n := v.(type) {
	case bool:
		return n
	case float64:
		return n != 0
	case int:
		return n != 0
	default:
		return false
	}
}

func parseLeadingInt(s string) int {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0
	}
	if i, err := strconv.Atoi(s); err == nil {
		return i
	}
	if dash := strings.IndexByte(s, '-'); dash > 0 {
		if i, err := strconv.Atoi(s[:dash]); err == nil {
			return i
		}
	}
	return 0
}

// npcSpawnRaw is one entry in npc_spawns.json.
// Fields for inline defs are parsed from float64 (JSON numbers).
type npcSpawnRaw struct {
	NpcIndex float64 `json:"npc_index"`
	X        float64 `json:"x"`
	Y        float64 `json:"y"`
	// Inline definition fields (only set when NpcIndex == 0).
	Name       string    `json:"name"`
	Body       float64   `json:"body"`
	Head       float64   `json:"head"`
	NPCType    float64   `json:"npc_type"`
	WeaponAnim float64   `json:"weapon_anim"`
	ShieldAnim float64   `json:"shield_anim"`
	Hostile    float64   `json:"hostile"`
	Attackable float64   `json:"attackable"`
	MaxHP      float64   `json:"max_hp"`
	Gold       float64   `json:"gold"`
	Movement   float64   `json:"movement"`
	Heading    float64   `json:"heading"`
	Items      []float64 `json:"items"`
}

// inlineNPCBaseIndex is the starting pseudo-index for inline NPC definitions
// (must not collide with real NPC indices, which top out at 535).
const inlineNPCBaseIndex = 10000

func loadNPCSpawns(path string, knownNPCs map[int]*NPCData) (map[int][]HardcodedSpawn, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var raw map[string][]npcSpawnRaw
	if err := json.NewDecoder(f).Decode(&raw); err != nil {
		return nil, fmt.Errorf("npc_spawns.json decode: %w", err)
	}

	result := make(map[int][]HardcodedSpawn)
	inlineIdx := inlineNPCBaseIndex

	for mapKey, entries := range raw {
		mapID, err := strconv.Atoi(mapKey)
		if err != nil {
			continue
		}
		for _, e := range entries {
			x := int(e.X)
			y := int(e.Y)
			if npcIdx := int(e.NpcIndex); npcIdx > 0 {
				// Reference to an existing NPC definition.
				if _, ok := knownNPCs[npcIdx]; ok {
					result[mapID] = append(result[mapID], HardcodedSpawn{
						X: x, Y: y, NpcIndex: npcIdx,
					})
				}
			} else if e.Name != "" {
				// Inline definition — build a synthetic NPCData.
				maxHP := int(e.MaxHP)
				if maxHP == 0 {
					maxHP = 100
				}
				var shopItems [40]int
				for i, item := range e.Items {
					if i >= 40 {
						break
					}
					shopItems[i] = int(item)
				}
				heading := int(e.Heading)
				if heading == 0 {
					heading = 3
				}
				def := &NPCData{
					Index:      inlineIdx,
					Name:       e.Name,
					Body:       int(e.Body),
					Head:       int(e.Head),
					Heading:    heading,
					NPCType:    int(e.NPCType),
					WeaponAnim: int(e.WeaponAnim),
					ShieldAnim: int(e.ShieldAnim),
					Hostile:    e.Hostile != 0,
					Attackable: e.Attackable != 0,
					Movement:   int(e.Movement),
					MinHP:      maxHP,
					MaxHP:      maxHP,
					Gold:       int(e.Gold),
					Vendor:     len(e.Items) > 0,
					ShopItems:  shopItems,
				}
				result[mapID] = append(result[mapID], HardcodedSpawn{
					X: x, Y: y, Def: def,
				})
				// Register inline NPC in the global NPC map so GetNPC works.
				knownNPCs[inlineIdx] = def
				inlineIdx++
			}
		}
	}
	return result, nil
}
