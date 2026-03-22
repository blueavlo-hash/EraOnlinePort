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
}

// Load reads all game data JSON files from the given directory.
// Expected files: maps/map_N.json, npcs.json, objects.json, spells.json
func Load(dir string) (*GameData, error) {
	gd := &GameData{
		Maps:    make(map[int]*MapData),
		NPCs:    make(map[int]*NPCData),
		Objects: make(map[int]*ObjectData),
		Spells:  make(map[int]*SpellData),
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
