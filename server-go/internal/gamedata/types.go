// Package gamedata loads static game data from the JSON files produced by the Python pipeline.
package gamedata

// GrhFrame holds one animation frame.
type GrhFrame struct {
	FileNum int     `json:"file_num"`
	SX      int     `json:"sx"`
	SY      int     `json:"sy"`
	Width   float64 `json:"width"`
	Height  float64 `json:"height"`
}

// Grh is either a static graphic or an animation.
type Grh struct {
	Index     int        `json:"index"`
	NumFrames int        `json:"num_frames"`
	Frames    []int      `json:"frames,omitempty"` // animated: frame GrhIndex references
	Speed     float64    `json:"speed,omitempty"`
	Frame     *GrhFrame  `json:"frame,omitempty"` // static: single frame
}

// MapTile holds one tile's layer/NPC/object data.
type MapTile struct {
	Blocked  bool     `json:"blocked"`
	Layers   [3]int   `json:"layers"`  // [layer1, layer2, layer3] GrhIndex
	ExitMap  int      `json:"exit_map"`
	ExitX    int      `json:"exit_x"`
	ExitY    int      `json:"exit_y"`
	NPCIndex int      `json:"npc_index"`
	ObjIndex int      `json:"obj_index"`
	ObjAmt   int      `json:"obj_amount"`
}

// MapData is one game map.
type MapData struct {
	ID        int                `json:"id"`
	Name      string             `json:"name"`
	MusicNum  int                `json:"music_num"`
	Rain      bool               `json:"rain"`
	PKZone    bool               `json:"pk_zone"`
	NorthExit int                `json:"north_exit"`
	SouthExit int                `json:"south_exit"`
	WestExit  int                `json:"west_exit"`
	EastExit  int                `json:"east_exit"`
	Tiles     map[string]MapTile `json:"tiles"` // key: "y,x" (matches VB6 loop order, pipeline output)
}

// HasGroundTiles returns true if the map has at least one layer-1 ground tile.
func (m *MapData) HasGroundTiles() bool {
	for _, t := range m.Tiles {
		if t.Layers[0] > 0 {
			return true
		}
	}
	return false
}

// NPCData holds one NPC definition.
type NPCData struct {
	Index      int    `json:"index"`
	Name       string `json:"name"`
	Desc       string `json:"desc"`
	Head       int    `json:"head"`
	Body       int    `json:"body"`
	Heading    int    `json:"heading"`
	Movement   int    `json:"movement"`
	NPCType    int    `json:"npc_type"`
	WeaponAnim int    `json:"weapon_anim"`
	ShieldAnim int    `json:"shield_anim"`
	Hostile    bool   `json:"hostile"`
	Attackable bool   `json:"attackable"`
	Tameable   bool   `json:"tameable"`
	DeathObj   int    `json:"death_obj"`
	Gold       int    `json:"gold"`
	MinHP      int    `json:"min_hp"`
	MaxHP      int    `json:"max_hp"`
	MinDmg     int    `json:"min_dmg"`
	MaxDmg     int    `json:"max_dmg"`
	Defense    int    `json:"defense"`
	ExpReward  int    `json:"exp_reward"`
	Vendor     bool     `json:"vendor"`
	ShopName   string   `json:"shop_name"`
	ShopItems  [40]int  `json:"shop_items"` // obj_index of each item for sale (0 = empty slot)
}

// ObjectData holds one item/object definition.
type ObjectData struct {
	Index        int    `json:"index"`
	Name         string `json:"name"`
	GrhIndex     int    `json:"grh_index"`
	ObjType      int    `json:"obj_type"`
	MinHit       int    `json:"min_hit"`
	MaxHit       int    `json:"max_hit"`
	Defense      int    `json:"defense"`
	Value        int    `json:"value"` // buy price
	Pickable     bool   `json:"pickable"`
	Sellable     bool   `json:"sellable"`
	Food         int    `json:"food"`   // hunger restore
	Level        int    `json:"level"`  // required level
	WeaponAnim   int    `json:"weapon_anim"`
	ShieldAnim   int    `json:"shield_anim"`
	ClothingType int    `json:"clothing_type"`
	Stackable    bool   `json:"stackable"`
	Weight       int    `json:"weight"`
}

// SpellData holds one spell definition.
type SpellData struct {
	Index      int    `json:"index"`
	Name       string `json:"name"`
	Desc       string `json:"desc"`
	SpellType  int    `json:"spell_type"`
	Effect     int    `json:"effect"`
	MinEffect  int    `json:"min_effect"`
	MaxEffect  int    `json:"max_effect"`
	MPCost     int    `json:"mp_cost"`
	Cooldown   int    `json:"cooldown_ms"`
	Range      int    `json:"range"`
}
