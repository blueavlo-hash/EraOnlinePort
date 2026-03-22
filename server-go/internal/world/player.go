package world

import (
	"github.com/blueavlo-hash/eraonline-server/internal/db"
	"github.com/blueavlo-hash/eraonline-server/internal/proto"
)


// Player is the in-world representation of a connected character.
type Player struct {
	// ConnID links back to the server.Conn.
	ConnID uint64
	// Send is the per-player outbound channel. The world goroutine writes here;
	// the conn goroutine reads and sends over TLS.
	Send chan []byte
	// sendKey is the session HMAC key for this player (derived during handshake).
	sendKey []byte
	// charDBID is the database character ID (for save operations).
	charDBID int64

	// Core identity.
	AccountID  int64
	Username   string
	CharName   string
	ClassID    int
	InstanceID int32 // unique in-world ID (peer_id equivalent, 1–9999)

	// Position.
	MapID   int
	X, Y    int
	Heading uint8

	// Stats.
	Level      int
	Exp        int
	HP         int
	MaxHP      int
	MP         int
	MaxMP      int
	Stamina    int
	MaxStamina int
	Gold       int

	// Appearance.
	HeadIndex  int
	BodyIndex  int
	WeaponSlot int // obj_index of equipped weapon
	ShieldSlot int
	HelmetSlot int
	ArmorSlot  int

	// Inventory (mirrors db.CharData.Inventory).
	Inventory [20]*db.InventorySlot
	// Skills (index 0 unused; skills are 1-28).
	Skills [29]*db.SkillSlot
	// Spells — unlocked spell IDs.
	Spells []int
	// Abilities — learned ability IDs.
	Abilities []int

	// Bank.
	BankItems [40]*db.InventorySlot
	BankGold  int

	// Combat.
	InCombat       bool
	CombatCooldown int // ticks remaining until next attack
	Target         int32 // 0 = no target

	// Vitals (float for sub-tick decay).
	Hunger float64
	Thirst float64

	// Poison.
	poison *PoisonState

	// Starvation tick counter.
	starveTick int

	// Spells cooldowns: spell_id → expiry time.
	spellCooldowns SpellCooldown

	// In-progress timed skill action.
	timedAction *TimedAction

	// Trade state (nil if not trading).
	activeTrade *TradeState

	// Quests.
	ActiveQuests    map[int]map[int]int // quest_id → {obj_idx → progress}
	CompletedQuests map[int]bool

	// Achievement tracking.
	AchievementIDs      []int
	AchievementProgress map[string]int
	VisitedMaps         map[int]bool

	// Bounty (gold on this player's head).
	Bounty int

	// Faction reputation.
	Reputation map[string]int

	// Sequence for outbound send (must only be written by world goroutine).
	SendSeq uint32
}

// FromCharData initialises a Player from a loaded database character.
func (p *Player) FromCharData(cd *db.CharData, connID uint64, instanceID int32, sendCh chan []byte) {
	p.ConnID = connID
	p.Send = sendCh
	p.charDBID = cd.ID
	p.AccountID = cd.AccountID
	p.CharName = cd.Name
	p.ClassID = cd.ClassID
	p.InstanceID = instanceID
	p.MapID = cd.MapID
	p.X = cd.PosX
	p.Y = cd.PosY
	p.Heading = uint8(cd.Heading)
	p.Level = cd.Level
	p.Exp = cd.Exp
	p.HP = cd.HP
	p.MaxHP = cd.MaxHP
	p.MP = cd.MP
	p.MaxMP = cd.MaxMP
	p.Stamina = cd.Stamina
	p.MaxStamina = cd.MaxStamina
	p.Gold = cd.Gold
	p.HeadIndex = cd.HeadIndex
	p.BodyIndex = cd.BodyIndex
	p.WeaponSlot = cd.WeaponSlot
	p.ShieldSlot = cd.ShieldSlot
	p.HelmetSlot = cd.HelmetSlot
	p.ArmorSlot = cd.ArmorSlot
	p.Inventory = cd.Inventory
	p.Skills = cd.Skills
	p.Spells = cd.Spells
	p.Abilities = cd.Abilities
	// Treat 0 as full (100) — handles legacy rows created before the DEFAULT was fixed.
	if cd.Hunger == 0 {
		p.Hunger = 100
	} else {
		p.Hunger = float64(cd.Hunger)
	}
	if cd.Thirst == 0 {
		p.Thirst = 100
	} else {
		p.Thirst = float64(cd.Thirst)
	}
	// Bank.
	p.BankItems = cd.BankItems
	p.BankGold = cd.BankGold

	// Quests.
	if cd.QuestActive != nil {
		p.ActiveQuests = cd.QuestActive
	} else {
		p.ActiveQuests = make(map[int]map[int]int)
	}
	if cd.QuestCompleted != nil {
		p.CompletedQuests = cd.QuestCompleted
	} else {
		p.CompletedQuests = make(map[int]bool)
	}

	// Achievements.
	p.AchievementIDs = cd.AchievementIDs
	p.AchievementProgress = make(map[string]int)
	p.Reputation = make(map[string]int)
	p.VisitedMaps = make(map[int]bool)
}

// ToCharData writes the in-world player state back to a db.CharData for saving.
func (p *Player) ToCharData() *db.CharData {
	return &db.CharData{
		ID:         0, // set by caller if needed
		AccountID:  p.AccountID,
		Name:       p.CharName,
		Level:      p.Level,
		Exp:        p.Exp,
		MapID:      p.MapID,
		PosX:       p.X,
		PosY:       p.Y,
		Heading:    int(p.Heading),
		HP:         p.HP,
		MaxHP:      p.MaxHP,
		MP:         p.MP,
		MaxMP:      p.MaxMP,
		Stamina:    p.Stamina,
		MaxStamina: p.MaxStamina,
		Gold:       p.Gold,
		HeadIndex:  p.HeadIndex,
		BodyIndex:  p.BodyIndex,
		WeaponSlot: p.WeaponSlot,
		ShieldSlot: p.ShieldSlot,
		HelmetSlot: p.HelmetSlot,
		ArmorSlot:  p.ArmorSlot,
		Inventory:  p.Inventory,
		Skills:     p.Skills,
		Spells:     p.Spells,
		Abilities:  p.Abilities,
		Hunger:     int(p.Hunger),
		Thirst:     int(p.Thirst),

		BankItems:      p.BankItems,
		BankGold:       p.BankGold,
		QuestActive:    p.ActiveQuests,
		QuestCompleted: p.CompletedQuests,
		AchievementIDs: p.AchievementIDs,
	}
}

// BuildSetChar builds the S_SET_CHAR packet payload for this player.
func (p *Player) BuildSetChar() []byte {
	w := proto.NewWriter(64)
	w.WriteI32(p.InstanceID)
	w.WriteI16(int16(p.BodyIndex))
	w.WriteI16(int16(p.HeadIndex))
	w.WriteI16(int16(p.WeaponSlot))
	w.WriteI16(int16(p.ShieldSlot))
	w.WriteI16(int16(p.X))
	w.WriteI16(int16(p.Y))
	w.WriteU8(p.Heading)
	w.WriteI16(int16(p.HP))
	w.WriteI16(int16(p.MaxHP))
	w.WriteStr(p.CharName)
	return w.Bytes()
}

// BuildStats builds the S_STATS packet payload for this player.
func (p *Player) BuildStats() []byte {
	w := proto.NewWriter(32)
	w.WriteU8(uint8(p.Level))
	w.WriteI16(int16(p.HP))
	w.WriteI16(int16(p.MaxHP))
	w.WriteI16(int16(p.MP))
	w.WriteI16(int16(p.MaxMP))
	w.WriteI16(int16(p.Stamina))
	w.WriteI16(int16(p.MaxStamina))
	w.WriteI32(int32(p.Exp))
	w.WriteI32(int32(xpToNextLevel(p.Level)))
	w.WriteI32(int32(p.Gold))
	return w.Bytes()
}

// BuildInventory builds the S_INVENTORY packet payload.
func (p *Player) BuildInventory() []byte {
	w := proto.NewWriter(128)
	count := 0
	for _, slot := range p.Inventory {
		if slot != nil && slot.ObjIndex > 0 {
			count++
		}
	}
	w.WriteU8(uint8(count))
	for _, slot := range p.Inventory {
		if slot == nil || slot.ObjIndex == 0 {
			continue
		}
		eq := uint8(0)
		if slot.Equipped {
			eq = 1
		}
		w.WriteU8(uint8(slot.Slot))
		w.WriteI16(int16(slot.ObjIndex))
		w.WriteU16(uint16(slot.Amount))
		w.WriteU8(eq)
	}
	return w.Bytes()
}

// BuildSkills builds the S_SKILLS packet payload.
func (p *Player) BuildSkills() []byte {
	w := proto.NewWriter(64)
	count := 0
	for i := 1; i <= 28; i++ {
		if p.Skills[i] != nil {
			count++
		}
	}
	w.WriteU8(uint8(count))
	for i := 1; i <= 28; i++ {
		sk := p.Skills[i]
		if sk == nil {
			continue
		}
		w.WriteU8(uint8(i))
		w.WriteI16(int16(sk.Level))
		w.WriteI32(int32(sk.XP))
		w.WriteI32(int32(xpToNextLevel(sk.Level))) // placeholder skill XP curve
	}
	return w.Bytes()
}

// BuildSpellbook builds the S_SPELLBOOK packet payload.
func (p *Player) BuildSpellbook() []byte {
	w := proto.NewWriter(8 + len(p.Spells))
	w.WriteU8(uint8(len(p.Spells)))
	for _, id := range p.Spells {
		w.WriteU8(uint8(id))
	}
	return w.Bytes()
}

// BuildAbilityList builds the S_ABILITY_LIST packet payload.
func (p *Player) BuildAbilityList() []byte {
	w := proto.NewWriter(8 + len(p.Abilities))
	w.WriteU8(uint8(len(p.Abilities)))
	for _, id := range p.Abilities {
		w.WriteU8(uint8(id))
	}
	return w.Bytes()
}
