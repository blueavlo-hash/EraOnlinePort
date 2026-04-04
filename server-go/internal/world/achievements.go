package world

import "github.com/blueavlo-hash/eraonline-server/internal/proto"

// Achievement defines one achievement milestone within a category.
// Gap 19: Updated to match original EO3 achievement types, thresholds, and rewards.
type Achievement struct {
	ID         int
	Name       string
	Desc       string
	Event      string // matches AchievementProgress key
	Threshold  int
	GoldReward int
	XPReward   int
}

// achievements is the master list matching the original EO3 server.
// Gap 19: kills_monsters, player_kills, deaths, quests_completed, items_crafted,
//         bounties_collected, enchant_3_achieved.
var achievements = []Achievement{
	// kills_monsters: thresholds 10/25/50/100/250, rewards 50/100/250/500/1000g
	{1, "Monster Slayer I", "Kill 10 monsters.", "kills_monsters", 10, 50, 0},
	{2, "Monster Slayer II", "Kill 25 monsters.", "kills_monsters", 25, 100, 0},
	{3, "Monster Slayer III", "Kill 50 monsters.", "kills_monsters", 50, 250, 0},
	{4, "Monster Slayer IV", "Kill 100 monsters.", "kills_monsters", 100, 500, 0},
	{5, "Monster Slayer V", "Kill 250 monsters.", "kills_monsters", 250, 1000, 0},

	// player_kills: thresholds 1/5/10/25/50, rewards 100/250/500/1000/2500g
	{6, "First Blood", "Kill your first player.", "player_kills", 1, 100, 0},
	{7, "Killer", "Kill 5 players.", "player_kills", 5, 250, 0},
	{8, "Murderer", "Kill 10 players.", "player_kills", 10, 500, 0},
	{9, "Warlord", "Kill 25 players.", "player_kills", 25, 1000, 0},
	{10, "Tyrant", "Kill 50 players.", "player_kills", 50, 2500, 0},

	// deaths: thresholds 1/10/25/50/100, rewards 25/50/100/250/500g
	{11, "First Death", "Die for the first time.", "deaths", 1, 25, 0},
	{12, "Reckless", "Die 10 times.", "deaths", 10, 50, 0},
	{13, "Risk Taker", "Die 25 times.", "deaths", 25, 100, 0},
	{14, "Daredevil", "Die 50 times.", "deaths", 50, 250, 0},
	{15, "Glutton for Punishment", "Die 100 times.", "deaths", 100, 500, 0},

	// quests_completed: thresholds 1/5/10/25/50, rewards 100/200/500/1000/2500g
	{16, "Quester I", "Complete 1 quest.", "quests_completed", 1, 100, 0},
	{17, "Quester II", "Complete 5 quests.", "quests_completed", 5, 200, 0},
	{18, "Quester III", "Complete 10 quests.", "quests_completed", 10, 500, 0},
	{19, "Quester IV", "Complete 25 quests.", "quests_completed", 25, 1000, 0},
	{20, "Hero", "Complete 50 quests.", "quests_completed", 50, 2500, 0},

	// items_crafted: thresholds 5/25/50/100/250, rewards 50/100/250/500/1000g
	{21, "Crafter I", "Craft 5 items.", "items_crafted", 5, 50, 0},
	{22, "Crafter II", "Craft 25 items.", "items_crafted", 25, 100, 0},
	{23, "Crafter III", "Craft 50 items.", "items_crafted", 50, 250, 0},
	{24, "Artisan", "Craft 100 items.", "items_crafted", 100, 500, 0},
	{25, "Master Craftsman", "Craft 250 items.", "items_crafted", 250, 1000, 0},

	// bounties_collected: thresholds 1/5/10/25/50, rewards 200/500/1000/2500/5000g
	{26, "Bounty Hunter I", "Collect 1 bounty.", "bounties_collected", 1, 200, 0},
	{27, "Bounty Hunter II", "Collect 5 bounties.", "bounties_collected", 5, 500, 0},
	{28, "Bounty Hunter III", "Collect 10 bounties.", "bounties_collected", 10, 1000, 0},
	{29, "Bounty Hunter IV", "Collect 25 bounties.", "bounties_collected", 25, 2500, 0},
	{30, "Bounty Hunter V", "Collect 50 bounties.", "bounties_collected", 50, 5000, 0},

	// enchant_3_achieved: thresholds 1/5/10/25/50, rewards 200/400/800/2000/5000g
	{31, "Enchanter I", "Achieve +3 enchantment once.", "enchant_3_achieved", 1, 200, 0},
	{32, "Enchanter II", "Achieve +3 enchantment 5 times.", "enchant_3_achieved", 5, 400, 0},
	{33, "Enchanter III", "Achieve +3 enchantment 10 times.", "enchant_3_achieved", 10, 800, 0},
	{34, "Enchanter IV", "Achieve +3 enchantment 25 times.", "enchant_3_achieved", 25, 2000, 0},
	{35, "Enchanter V", "Achieve +3 enchantment 50 times.", "enchant_3_achieved", 50, 5000, 0},
}

// ---------------------------------------------------------------------------
// Gap 20: Titles system — 13 titles unlocked at specific achievement milestones.
// ---------------------------------------------------------------------------

// TitleDef defines one title and the condition to unlock it.
type TitleDef struct {
	ID          int
	Name        string
	Event       string // achievement event key; "" = default starting title
	Threshold   int    // progress value at which title unlocks
}

// titleDefs lists all 13 titles.
var titleDefs = []TitleDef{
	{1, "Novice", "", 0},                       // default starting title
	{2, "Warrior", "kills_monsters", 10},
	{3, "Veteran", "kills_monsters", 50},
	{4, "Champion", "kills_monsters", 100},
	{5, "Legend", "kills_monsters", 250},
	{6, "Murderer", "player_kills", 5},
	{7, "Warlord", "player_kills", 25},
	{8, "Artisan", "items_crafted", 25},
	{9, "Master Craftsman", "items_crafted", 100},
	{10, "Bounty Hunter", "bounties_collected", 5},
	{11, "Enchanter", "enchant_3_achieved", 5},
	{12, "Quester", "quests_completed", 10},
	{13, "Hero", "quests_completed", 25},
}

// checkTitles checks whether any new titles have been unlocked for the player,
// and auto-upgrades their active title to the highest-threshold unlocked title.
func (w *World) checkTitles(p *Player) {
	newTitle := ""
	// Iterate in reverse so the highest-threshold title wins.
	for i := len(titleDefs) - 1; i >= 0; i-- {
		td := titleDefs[i]
		if td.Event == "" {
			continue
		}
		prog := p.AchievementProgress[td.Event]
		if prog < td.Threshold {
			continue
		}
		// Check if this title is newly unlocked.
		alreadyHave := false
		for _, id := range p.TitleIDs {
			if id == td.ID {
				alreadyHave = true
				break
			}
		}
		if !alreadyHave {
			p.TitleIDs = append(p.TitleIDs, td.ID)
			w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("New title unlocked: ["+td.Name+"]!"))
		}
		// First match (highest threshold met) becomes the active title.
		if newTitle == "" {
			newTitle = td.Name
		}
	}
	if newTitle == "" {
		newTitle = "Novice"
	}
	if newTitle != p.ActiveTitle {
		p.ActiveTitle = newTitle
		// Broadcast title change to everyone on the map.
		wr := proto.NewWriter(8 + len(newTitle))
		wr.WriteI32(p.InstanceID)
		wr.WriteStr(newTitle)
		w.broadcastMap(p.MapID, proto.MsgSTitleUpdate, wr.Bytes(), -1)
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("Your title is now ["+newTitle+"]!"))
	}
}

// checkAchievements evaluates achievements for a given event and value.
func (w *World) checkAchievements(p *Player, event string, value int) {
	// Update the progress counter before iterating achievements.
	switch event {
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

	// Also check titles whenever achievements are checked.
	w.checkTitles(p)
}

// checkAchievementsNew is a helper for events not previously covered by checkAchievements.
func (w *World) checkAchievementsNew(p *Player, event string, value int) {
	w.checkAchievements(p, event, value)
}

// trackMapVisit records a map visit and checks explorer achievements.
func (w *World) trackMapVisit(p *Player, mapID int) {
	if p.VisitedMaps == nil {
		p.VisitedMaps = make(map[int]bool)
	}
	if !p.VisitedMaps[mapID] {
		p.VisitedMaps[mapID] = true
		w.checkAchievements(p, "maps", 0)
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
