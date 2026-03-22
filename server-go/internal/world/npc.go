package world

import (
	"math/rand"

	"github.com/blueavlo-hash/eraonline-server/internal/gamedata"
	"github.com/blueavlo-hash/eraonline-server/internal/proto"
)

const npcInstanceBase = 10001 // NPC instance IDs start here (players are 1-9999)

// NPC is one spawned NPC instance in the world.
type NPC struct {
	InstanceID int32
	DefIndex   int // index into GameData.NPCs
	Def        *gamedata.NPCData

	MapID   int
	X, Y    int
	Heading uint8

	HP    int
	MaxHP int

	// Respawn tracking.
	SpawnX, SpawnY int
	SpawnMapID     int
	Dead           bool
	RespawnTicks   int // ticks until respawn (0 = alive)

	// Combat.
	CombatCooldown int // ticks remaining
	Target         int32 // player instance ID (0=none)

	// Wander / patrol.
	WanderTimer int
}

// NewNPC creates an NPC instance.
func NewNPC(instanceID int32, def *gamedata.NPCData, mapID, x, y int) *NPC {
	hp := def.MinHP + rand.Intn(max(1, def.MaxHP-def.MinHP+1))
	return &NPC{
		InstanceID: instanceID,
		DefIndex:   def.Index,
		Def:        def,
		MapID:      mapID,
		X:          x,
		Y:          y,
		Heading:    uint8(def.Heading),
		HP:         hp,
		MaxHP:      hp,
		SpawnX:     x,
		SpawnY:     y,
		SpawnMapID: mapID,
	}
}

// BuildSetChar builds the S_SET_CHAR payload for this NPC.
func (n *NPC) BuildSetChar() []byte {
	w := proto.NewWriter(64)
	w.WriteI32(n.InstanceID)
	w.WriteI16(int16(n.Def.Body))
	w.WriteI16(int16(n.Def.Head))
	w.WriteI16(int16(n.Def.WeaponAnim))
	w.WriteI16(int16(n.Def.ShieldAnim))
	w.WriteI16(int16(n.X))
	w.WriteI16(int16(n.Y))
	w.WriteU8(n.Heading)
	w.WriteI16(int16(n.HP))
	w.WriteI16(int16(n.MaxHP))
	w.WriteStr(n.Def.Name)
	return w.Bytes()
}

// wanderDirections for random NPC movement.
var wanderDirections = []uint8{1, 2, 3, 4} // N E S W

// wanderDelta returns (dx, dy) for a direction code.
func wanderDelta(dir uint8) (int, int) {
	switch dir {
	case 1:
		return 0, -1 // N
	case 2:
		return 1, 0 // E
	case 3:
		return 0, 1 // S
	case 4:
		return -1, 0 // W
	}
	return 0, 0
}
