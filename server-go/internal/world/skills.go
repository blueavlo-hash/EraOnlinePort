package world

import (
	"fmt"
	"math"
	"time"

	"github.com/blueavlo-hash/eraonline-server/internal/db"
	"github.com/blueavlo-hash/eraonline-server/internal/proto"
)

// Skill IDs (1-indexed, matching the original EO3 game order exactly).
const (
	SkillCooking       = 1
	SkillMusicianship  = 2
	SkillTailoring     = 3
	SkillCarpentry     = 4
	SkillLumberjacking = 5
	SkillTactics       = 6
	SkillDisguise      = 7
	SkillMerchant      = 8
	SkillBlacksmithing = 9
	SkillHiding        = 10
	SkillMagery        = 11
	SkillLockpicking   = 12
	SkillPickpocketing = 13
	SkillStealth       = 14
	SkillPoisoning     = 15
	SkillSwordsmanship = 16
	SkillParrying      = 17
	SkillAnimalTaming  = 18
	SkillReligionLore  = 19
	SkillFishing       = 20
	SkillMining        = 21
	SkillBackstabbing  = 22
	SkillHealing       = 23
	SkillSurviving     = 24
	SkillEtiquette     = 25
	SkillStreetwise    = 26
	SkillMeditating    = 27
	SkillArchery       = 28
)

// Skill durations in seconds (base, before speed factor).
// Matches original EO3 GDScript values.
var skillDurations = map[int]float64{
	SkillCooking:       8.0,  // Gap 5: 8s
	SkillCarpentry:     6.0,  // Gap 5: 6s
	SkillLumberjacking: 10.0, // Gap 5: 10s
	SkillBlacksmithing: 7.0,  // Gap 5: 7s
	SkillFishing:       12.0, // Gap 5: 12s
	SkillMining:        7.0,  // Gap 5: 7s
}

// skillXPGains maps skill ID to XP awarded per successful action.
// Matches original EO3 values (Gap 4).
var skillXPGains = map[int]int{
	SkillCooking:       12,
	SkillCarpentry:     10,
	SkillLumberjacking: 10,
	SkillBlacksmithing: 25,
	SkillFishing:       8,
	SkillMining:        15,
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
		w.startGathering(p, SkillFishing, "fish", 16)
	case SkillLumberjacking:
		w.startGathering(p, SkillLumberjacking, "log", 17)
	case SkillMining:
		w.startGathering(p, SkillMining, "mine", 48)
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

func (w *World) startGathering(p *Player, skillID int, action string, toolItemType int) {
	// Gap 22: verify tool is in inventory when required.
	if toolItemType > 0 {
		hasTool := false
		for _, slot := range p.Inventory {
			if slot == nil || slot.ObjIndex == 0 {
				continue
			}
			obj := w.gameData.GetObject(slot.ObjIndex)
			if obj != nil && obj.ObjType == toolItemType {
				hasTool = true
				break
			}
		}
		if !hasTool {
			var toolMsg string
			switch skillID {
			case SkillFishing:
				toolMsg = "You need a fishing rod to fish."
			case SkillLumberjacking:
				toolMsg = "You need an axe to chop wood."
			case SkillMining:
				toolMsg = "You need a pickaxe to mine."
			default:
				toolMsg = "You need the required tool."
			}
			w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(toolMsg))
			return
		}
	}

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

		// Check success. Award 1 XP even on failure so progress is always visible.
		skillLevel := p.getSkillLevel(ta.SkillID)
		if randSource.Float64() > skillSuccessChance(skillLevel) {
			w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You failed."))
			w.awardSkillXP(p, ta.SkillID, 1)
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
			rawIdx := raw.ObjIndex
			// Consume one raw item.
			raw.Amount--
			if raw.Amount <= 0 {
				p.Inventory[ta.AuxSlot] = nil
			}
			// Meat (117) → Roasted Meat (156); everything else → Roasted Fish (307).
			cookedIdx := 307
			if rawIdx == 117 {
				cookedIdx = 156
			}
			w.giveItem(p, cookedIdx, 1)
			w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
			obj := w.gameData.GetObject(cookedIdx)
			name := "food"
			if obj != nil {
				name = obj.Name
			}
			w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You cook the food into "+name+"."))
		}
	case "fish":
		// 15% chance of small catch (item 135), otherwise random fish 308-317.
		fishIdx := 135
		catchSize := 1
		if randSource.Float64() >= 0.15 {
			fishIdx = 308 + randN(10) // items 308-317
			catchSize = 1 + randN(5)  // larger fish for tournament scoring
		}
		if w.giveItem(p, fishIdx, catchSize) {
			w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
			obj := w.gameData.GetObject(fishIdx)
			name := "a fish"
			if obj != nil {
				name = obj.Name
			}
			w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You caught "+name+"!"))
			w.checkAchievements(p, "fish_caught", 1)
			// Tournament tracking.
			w.recordTourneyCatch(p, catchSize)
		}
	case "log":
		// Gap 25: log = item 114 (Log, obj_type 20).
		logIdx := 114
		if w.giveItem(p, logIdx, 1+randN(3)) {
			w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
			w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You cut some logs."))
		}
	case "mine":
		// Gap 25: ore = item 154 (ore, obj_type 32).
		oreIdx := 154
		if w.giveItem(p, oreIdx, 1+randN(2)) {
			w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
			w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You mined some ore."))
		}
	case "smelt":
		// Gap 25: ore = 154, steel = 153. 2 ore → 4 steel.
		oreIdx := 154
		steelIdx := 153
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
		// Gap 25: log = 114, plank = 148. 1 log → 2 planks.
		logIdx := 114
		plankIdx := 148
		w.removeItemFromInventory(p, logIdx, 1)
		w.giveItem(p, plankIdx, 2)
		w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You cut the log into planks."))
	case "craft":
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You crafted something."))
	}

	// Achievement and quest tracking based on action type.
	switch ta.Action {
	case "cook":
		w.onCookItem(p)
	case "craft":
		w.onCraftItem(p, "forge")
	case "smelt":
		w.onCraftItem(p, "smelt")
	case "planks":
		w.onCraftItem(p, "planks")
	}

	// Award skill XP — use per-skill XP gain if defined, otherwise 1 (Gap 4).
	xpGain := 1
	if g, ok := skillXPGains[ta.SkillID]; ok {
		xpGain = g
	}
	w.awardSkillXP(p, ta.SkillID, xpGain)
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

	w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(
		fmt.Sprintf("%s +%d XP (%d/%d)", skillName(skillID), xpGain, sk.XP, xpNeeded)))

	if sk.XP >= xpNeeded {
		sk.XP -= xpNeeded
		sk.Level++

		wr2 := proto.NewWriter(3)
		wr2.WriteU8(uint8(skillID))
		wr2.WriteI16(int16(sk.Level))
		w.sendTo(p, proto.MsgSSkillRaise, wr2.Bytes())
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(fmt.Sprintf("Your %s skill has increased to %d!", skillName(skillID), sk.Level)))
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
		1:  "Cooking",
		2:  "Musicianship",
		3:  "Tailoring",
		4:  "Carpenting",
		5:  "Lumberjacking",
		6:  "Tactics",
		7:  "Disguise",
		8:  "Merchant",
		9:  "Blacksmithing",
		10: "Hiding",
		11: "Magery",
		12: "Lockpicking",
		13: "Pickpocketing",
		14: "Stealth",
		15: "Poisoning",
		16: "Swordsmanship",
		17: "Parrying",
		18: "Animal Taming",
		19: "Religion Lore",
		20: "Fishing",
		21: "Mining",
		22: "Backstabbing",
		23: "Healing",
		24: "Surviving",
		25: "Etiquette",
		26: "Streetwise",
		27: "Meditating",
		28: "Archery",
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
