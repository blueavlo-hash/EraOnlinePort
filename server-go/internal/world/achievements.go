package world

import "github.com/blueavlo-hash/eraonline-server/internal/proto"

// Achievement defines one achievement.
type Achievement struct {
	ID        int
	Name      string
	Desc      string
	Event     string // "kill", "level", "craft", "gold", "fish", "maps"
	Threshold int
	GoldReward int
	XPReward  int
}

// Achievements is the master list (mirrors the 15 from game_server.gd).
var achievements = []Achievement{
	{1, "First Blood", "Kill your first enemy.", "kill", 1, 50, 100},
	{2, "Slayer", "Kill 100 enemies.", "kill", 100, 200, 500},
	{3, "Warrior", "Kill 1000 enemies.", "kill", 1000, 500, 2000},
	{4, "Novice", "Reach level 10.", "level", 10, 100, 0},
	{5, "Apprentice", "Reach level 25.", "level", 25, 300, 0},
	{6, "Veteran", "Reach level 50.", "level", 50, 1000, 0},
	{7, "Wealthy", "Accumulate 10,000 gold.", "gold", 10000, 0, 200},
	{8, "Rich", "Accumulate 100,000 gold.", "gold", 100000, 0, 500},
	{9, "Cook", "Cook 10 meals.", "craft", 10, 100, 100},
	{10, "Chef", "Cook 100 meals.", "craft", 100, 300, 500},
	{11, "Fisherman", "Catch 10 fish.", "fish", 10, 100, 100},
	{12, "Angler", "Catch 100 fish.", "fish", 100, 300, 500},
	{13, "Explorer", "Visit 10 different maps.", "maps", 10, 200, 200},
	{14, "Traveler", "Visit 25 different maps.", "maps", 25, 500, 500},
	{15, "World Wanderer", "Visit 50 different maps.", "maps", 50, 1000, 1000},
}

// checkAchievements evaluates achievements for a given event and value.
func (w *World) checkAchievements(p *Player, event string, value int) {
	// Update the progress counter ONCE before iterating achievements.
	// Special cases where progress = current char stat (not cumulative).
	switch event {
	case "gold":
		p.AchievementProgress[event] = p.Gold
	case "level":
		p.AchievementProgress[event] = p.Level
	case "maps":
		p.AchievementProgress[event] = len(p.VisitedMaps)
	default:
		p.AchievementProgress[event] += value
	}
	current := p.AchievementProgress[event]

	for _, ach := range achievements {
		if ach.Event != event {
			continue
		}

		// Skip if already unlocked.
		alreadyUnlocked := false
		for _, id := range p.AchievementIDs {
			if id == ach.ID {
				alreadyUnlocked = true
				break
			}
		}
		if alreadyUnlocked {
			continue
		}

		if current < ach.Threshold {
			continue
		}

		// Unlock!
		p.AchievementIDs = append(p.AchievementIDs, ach.ID)
		if ach.GoldReward > 0 {
			p.Gold += ach.GoldReward
		}
		if ach.XPReward > 0 {
			p.Exp += ach.XPReward
			w.checkLevelUp(p)
		}

		wr := proto.NewWriter(64)
		wr.WriteU16(uint16(ach.ID))
		wr.WriteStr(ach.Name)
		wr.WriteStr(ach.Desc)
		wr.WriteI32(int32(ach.GoldReward))
		wr.WriteI32(int32(ach.XPReward))
		w.sendTo(p, proto.MsgSAchievementUnlock, wr.Bytes())
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("Achievement Unlocked: "+ach.Name+"!"))
		w.sendTo(p, proto.MsgSStats, p.BuildStats())
	}
}

// trackMapVisit records a map visit and checks explorer achievements.
func (w *World) trackMapVisit(p *Player, mapID int) {
	if p.VisitedMaps == nil {
		p.VisitedMaps = make(map[int]bool)
	}
	if !p.VisitedMaps[mapID] {
		p.VisitedMaps[mapID] = true
		w.checkAchievements(p, "maps", 0) // re-evaluate against current map count
	}
}

// checkLevelUp checks if the player has enough XP to level up.
func (w *World) checkLevelUp(p *Player) {
	if p.Level >= 50 {
		return
	}
	for p.Exp >= xpToNextLevel(p.Level) && p.Level < 50 {
		p.Exp -= xpToNextLevel(p.Level)
		p.Level++

		// Recompute stats.
		maxHP, maxMP, maxSTA, minDmg, maxDmg, _, _, _ := recalcCombatStats(
			p.ClassID, p.Level,
			getObjMinHit(w, p.WeaponSlot), getObjMaxHit(w, p.WeaponSlot),
			0, getObjDef(w, p.ShieldSlot), getObjDef(w, p.ArmorSlot),
		)
		_, _ = minDmg, maxDmg
		p.MaxHP = maxHP
		p.MaxMP = maxMP
		p.MaxStamina = maxSTA
		p.HP = maxHP
		p.MP = maxMP

		wr := proto.NewWriter(1)
		wr.WriteU8(uint8(p.Level))
		w.sendTo(p, proto.MsgSLevelUp, wr.Bytes())
	}
	w.sendTo(p, proto.MsgSStats, p.BuildStats())
	w.checkAchievements(p, "level", 0)
}
