package world

import (
	"math"
	"time"

	"github.com/blueavlo-hash/eraonline-server/internal/db"
	"github.com/blueavlo-hash/eraonline-server/internal/proto"
)

// Skill IDs (1-indexed, matching the original game).
const (
	SkillCooking        = 1
	SkillFishing        = 2
	SkillLumberjacking  = 3
	SkillCarpentry      = 4
	SkillBlacksmithing  = 5
	SkillMining         = 6
	SkillHunting        = 7
	SkillTailoring      = 8
	SkillAlchemy        = 9
	SkillMagery         = 10
	SkillSwordsmanship  = 11
	SkillAxemanship     = 12
	SkillBowmanship     = 13
	SkillShielding      = 14
	SkillTactics        = 15
	SkillHiding         = 16
	SkillSneaking       = 17
	SkillLockpicking    = 18
	SkillPoisoning      = 19
	SkillHealing        = 20
	SkillAnimalTaming   = 21
	SkillAnimalLore     = 22
	SkillMeditation     = 23
	SkillResistSpells   = 24
	SkillEvalIntel      = 25
	SkillSpiritSpeak    = 26
	SkillCartography    = 27
	SkillDetectHidden   = 28
)

// Skill durations in seconds (base, before speed factor).
var skillDurations = map[int]float64{
	SkillCooking:       6.0,
	SkillFishing:       12.0,
	SkillLumberjacking: 10.0,
	SkillCarpentry:     6.0,
	SkillBlacksmithing: 8.0,
	SkillMining:        8.0,
}

// skillXPToNext returns XP needed to raise a skill from level to level+1.
// Formula: 100 * 1.09^(level-1)
func skillXPToNext(level int) int {
	if level <= 0 {
		return 100
	}
	return int(math.Ceil(100.0 * math.Pow(1.09, float64(level-1))))
}

// skillSuccessChance returns the probability of a skill action succeeding.
// Formula: 30% + 0.6% per skill level, capped at 95%.
func skillSuccessChance(level int) float64 {
	chance := 0.30 + float64(level)*0.006
	if chance > 0.95 {
		chance = 0.95
	}
	return chance
}

// skillSpeedFactor returns the duration multiplier for a skill action.
// Formula: max(0.50, 1.0 - level * 0.005)
func skillSpeedFactor(level int) float64 {
	f := 1.0 - float64(level)*0.005
	if f < 0.50 {
		f = 0.50
	}
	return f
}

// TimedAction is an in-progress skill action.
type TimedAction struct {
	SkillID   int
	ExpiresAt time.Time
	Action    string // "cook", "fish", "log", "mine", "smelt", "planks"
	AuxSlot   int    // inventory slot for context (e.g., raw food slot)
}

func (w *World) handleUseSkill(p *Player, payload []byte) {
	if p.timedAction != nil {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You are already busy."))
		return
	}

	r := proto.NewReader(payload)
	skillID, err := r.ReadU8()
	if err != nil {
		return
	}
	tileX, _ := r.ReadI16()
	tileY, _ := r.ReadI16()
	_, _ = tileX, tileY

	switch int(skillID) {
	case SkillCooking:
		w.startCooking(p)
	case SkillFishing:
		w.startGathering(p, SkillFishing, "fish", 0)
	case SkillLumberjacking:
		w.startGathering(p, SkillLumberjacking, "log", 0)
	case SkillMining:
		w.startGathering(p, SkillMining, "mine", 0)
	case SkillBlacksmithing, SkillCarpentry:
		w.startCrafting(p, int(skillID))
	default:
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("That skill is not yet implemented."))
	}
}

func (w *World) startCooking(p *Player) {
	// Find raw food in inventory.
	rawSlot := -1
	for i, slot := range p.Inventory {
		if slot == nil || slot.ObjIndex == 0 {
			continue
		}
		obj := w.gameData.GetObject(slot.ObjIndex)
		if obj != nil && obj.ObjType == 39 { // raw food obj_type
			rawSlot = i
			break
		}
	}
	if rawSlot == -1 {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You have no raw food to cook."))
		return
	}

	skillLevel := p.getSkillLevel(SkillCooking)
	dur := time.Duration(float64(skillDurations[SkillCooking]*float64(time.Second)) * skillSpeedFactor(skillLevel))
	p.timedAction = &TimedAction{
		SkillID:   SkillCooking,
		ExpiresAt: time.Now().Add(dur),
		Action:    "cook",
		AuxSlot:   rawSlot,
	}
	durMS := int(dur / time.Millisecond)

	wr := proto.NewWriter(3)
	wr.WriteU8(uint8(SkillCooking))
	wr.WriteU16(uint16(durMS))
	w.sendTo(p, proto.MsgSSkillProgress, wr.Bytes())
	w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You begin cooking..."))
}

func (w *World) startGathering(p *Player, skillID int, action string, toolType int) {
	skillLevel := p.getSkillLevel(skillID)
	baseDur, ok := skillDurations[skillID]
	if !ok {
		baseDur = 8.0
	}
	dur := time.Duration(baseDur*float64(time.Second)) * time.Duration(skillSpeedFactor(skillLevel)*1000) / 1000
	p.timedAction = &TimedAction{
		SkillID:   skillID,
		ExpiresAt: time.Now().Add(dur),
		Action:    action,
	}

	msg := "You begin working..."
	switch skillID {
	case SkillFishing:
		msg = "You cast your fishing line..."
	case SkillLumberjacking:
		msg = "You begin chopping wood..."
	case SkillMining:
		msg = "You begin mining for ore..."
	}

	wr := proto.NewWriter(3)
	wr.WriteU8(uint8(skillID))
	wr.WriteU16(uint16(dur / time.Millisecond))
	w.sendTo(p, proto.MsgSSkillProgress, wr.Bytes())
	w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(msg))
}

func (w *World) startCrafting(p *Player, skillID int) {
	skillLevel := p.getSkillLevel(skillID)
	baseDur := skillDurations[skillID]
	dur := time.Duration(baseDur*float64(time.Second)) * time.Duration(skillSpeedFactor(skillLevel)*1000) / 1000

	action := "craft"
	msg := "You begin crafting..."

	p.timedAction = &TimedAction{
		SkillID:   skillID,
		ExpiresAt: time.Now().Add(dur),
		Action:    action,
	}

	wr := proto.NewWriter(3)
	wr.WriteU8(uint8(skillID))
	wr.WriteU16(uint16(dur / time.Millisecond))
	w.sendTo(p, proto.MsgSSkillProgress, wr.Bytes())
	w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(msg))
}

// tickSkillActions checks all in-progress skill timers.
func (w *World) tickSkillActions() {
	now := time.Now()
	for _, p := range w.players {
		if p.timedAction == nil {
			continue
		}
		if now.Before(p.timedAction.ExpiresAt) {
			continue
		}
		ta := p.timedAction
		p.timedAction = nil

		// Send "done" progress packet (duration=0).
		wr := proto.NewWriter(3)
		wr.WriteU8(uint8(ta.SkillID))
		wr.WriteU16(0)
		w.sendTo(p, proto.MsgSSkillProgress, wr.Bytes())

		// Check success.
		skillLevel := p.getSkillLevel(ta.SkillID)
		if randSource.Float64() > skillSuccessChance(skillLevel) {
			w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You failed."))
			continue
		}

		w.completeSkillAction(p, ta)
	}
}

// completeSkillAction resolves the reward for a successful skill action.
func (w *World) completeSkillAction(p *Player, ta *TimedAction) {
	switch ta.Action {
	case "cook":
		if ta.AuxSlot >= 0 && ta.AuxSlot < 20 && p.Inventory[ta.AuxSlot] != nil {
			raw := p.Inventory[ta.AuxSlot]
			// Replace raw food with cooked version (cooked obj_index = raw + 1, by convention).
			cookedIdx := raw.ObjIndex + 1
			raw.ObjIndex = cookedIdx
			w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
			w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You cooked the food."))
		}
	case "fish":
		// Award random fish (obj_index 50-55 are fish, by convention).
		fishIdx := 50 + randN(6)
		if w.giveItem(p, fishIdx, 1) {
			w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
			w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You caught a fish!"))
		}
	case "log":
		logIdx := 10 // logs object index
		if w.giveItem(p, logIdx, 1+randN(3)) {
			w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
			w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You cut some logs."))
		}
	case "mine":
		oreIdx := 30 // ore object index
		if w.giveItem(p, oreIdx, 1+randN(2)) {
			w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
			w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You mined some ore."))
		}
	case "smelt":
		// 2 ore → 4 steel
		oreIdx := 30
		steelIdx := 31
		oreCount := 0
		for _, slot := range p.Inventory {
			if slot != nil && slot.ObjIndex == oreIdx {
				oreCount += slot.Amount
			}
		}
		toSmelt := imin(oreCount, 2)
		if toSmelt > 0 {
			w.removeItemFromInventory(p, oreIdx, toSmelt)
			w.giveItem(p, steelIdx, toSmelt*2)
			w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
			w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You smelted the ore into steel bars."))
		}
	case "planks":
		logIdx := 10
		plankIdx := 11
		w.removeItemFromInventory(p, logIdx, 1)
		w.giveItem(p, plankIdx, 2)
		w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You cut the log into planks."))
	case "craft":
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You crafted something."))
	}

	// Achievement and quest tracking based on action type.
	switch ta.Action {
	case "cook", "craft":
		w.onCraftItem(p, 0) // also calls checkAchievements("craft") internally
	case "fish":
		w.checkAchievements(p, "fish", 1)
	}

	// Award skill XP.
	w.awardSkillXP(p, ta.SkillID, 1)
}

// awardSkillXP adds XP to a skill and handles level-up.
func (w *World) awardSkillXP(p *Player, skillID, xpGain int) {
	if skillID < 1 || skillID > 28 {
		return
	}
	if p.Skills[skillID] == nil {
		p.Skills[skillID] = &db.SkillSlot{SkillID: skillID, Level: 0, XP: 0}
	}
	sk := p.Skills[skillID]
	sk.XP += xpGain

	xpNeeded := skillXPToNext(sk.Level + 1)

	// Send XP update.
	wr := proto.NewWriter(10)
	wr.WriteU8(uint8(skillID))
	wr.WriteI32(int32(sk.XP))
	wr.WriteI32(int32(xpNeeded))
	w.sendTo(p, proto.MsgSSkillXP, wr.Bytes())

	if sk.XP >= xpNeeded {
		sk.XP -= xpNeeded
		sk.Level++

		wr2 := proto.NewWriter(3)
		wr2.WriteU8(uint8(skillID))
		wr2.WriteI16(int16(sk.Level))
		w.sendTo(p, proto.MsgSSkillRaise, wr2.Bytes())
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("Your "+skillName(skillID)+" skill has increased!"))
	}
}

// getSkillLevel returns the current level of a skill.
func (p *Player) getSkillLevel(skillID int) int {
	if skillID < 1 || skillID > 28 || p.Skills[skillID] == nil {
		return 0
	}
	return p.Skills[skillID].Level
}

func skillName(id int) string {
	names := map[int]string{
		1: "Cooking", 2: "Fishing", 3: "Lumberjacking", 4: "Carpentry",
		5: "Blacksmithing", 6: "Mining", 7: "Hunting", 8: "Tailoring",
		9: "Alchemy", 10: "Magery", 11: "Swordsmanship", 12: "Axemanship",
		13: "Bowmanship", 14: "Shielding", 15: "Tactics", 16: "Hiding",
		17: "Sneaking", 18: "Lockpicking", 19: "Poisoning", 20: "Healing",
		21: "Animal Taming", 22: "Animal Lore", 23: "Meditation",
		24: "Resist Spells", 25: "Eval Intelligence", 26: "Spirit Speak",
		27: "Cartography", 28: "Detect Hidden",
	}
	if n, ok := names[id]; ok {
		return n
	}
	return "Unknown"
}

// removeItemFromInventory removes `amount` of the given objIndex from inventory.
func (w *World) removeItemFromInventory(p *Player, objIndex, amount int) {
	remaining := amount
	for i, slot := range p.Inventory {
		if slot == nil || slot.ObjIndex != objIndex || remaining <= 0 {
			continue
		}
		if slot.Amount <= remaining {
			remaining -= slot.Amount
			p.Inventory[i] = nil
		} else {
			slot.Amount -= remaining
			remaining = 0
		}
	}
}
