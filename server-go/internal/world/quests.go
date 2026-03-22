package world

import (
	"fmt"
	"strings"

	"github.com/blueavlo-hash/eraonline-server/internal/proto"
)

// Quest objective types.
const (
	QuestObjKill         = 0
	QuestObjGather       = 1
	QuestObjCraft        = 2
	QuestObjExplore      = 3
	QuestObjDeliver      = 4
	QuestObjKillSpecific = 5
	QuestObjCook         = 6
)

// QuestObjective is one step of a quest.
type QuestObjective struct {
	Label    string
	Required int
	Type     int
	Param    int    // explore: map_id
	ParamStr string // kill_specific: npc_name_contains; craft: action string
	ObjTypes []int  // gather: obj_type values to match in inventory
}

// QuestDef defines one quest. Mirrored from server_quests.gd.
type QuestDef struct {
	ID              int
	Name            string
	Desc            string
	GiverNameMatch  string // case-insensitive substring of NPC name
	TurninNameMatch string // may differ from giver
	Prereqs         []int  // all must be completed before this quest can be accepted
	LevelReq        int
	Objectives      []QuestObjective
	RewardGold      int
	RewardXP        int
	RewardItems     []QuestRewardItem
	FactionName     string
	FactionRep      int
	CompletionMsg   string
}

// QuestRewardItem is an item rewarded on quest completion.
type QuestRewardItem struct {
	ObjIndex int
	Amount   int
}

// questDefs is the master quest list. Mirrored from server_quests.gd.
var questDefs = []QuestDef{
	// -----------------------------------------------------------------------
	// Chain 1 — Mayor (tutorial chain)
	// -----------------------------------------------------------------------
	{
		ID: 1, Name: "A Warrior's Beginning",
		Desc:            "You look capable, adventurer. Prove yourself by defeating some of the creatures plaguing our lands.",
		GiverNameMatch:  "mayor",
		TurninNameMatch: "mayor",
		LevelReq:        1,
		Objectives:      []QuestObjective{{Label: "Kill hostile NPCs", Required: 5, Type: QuestObjKill}},
		RewardGold: 100, RewardXP: 200,
		FactionName: "haven", FactionRep: 75,
		CompletionMsg: "Well done, warrior. You are ready for greater challenges.",
	},
	{
		ID: 2, Name: "Gather Resources",
		Desc:            "Good work. Now learn to gather resources. Bring me materials.",
		GiverNameMatch:  "mayor",
		TurninNameMatch: "mayor",
		Prereqs:         []int{1},
		LevelReq:        1,
		Objectives:      []QuestObjective{{Label: "Gather ore or logs", Required: 5, Type: QuestObjGather, ObjTypes: []int{32, 20}}},
		RewardGold: 50, RewardXP: 100, RewardItems: []QuestRewardItem{{3, 1}},
		FactionName: "haven", FactionRep: 75,
		CompletionMsg: "Excellent! These materials will serve you well.",
	},
	{
		ID: 4, Name: "The Elder's Errand",
		Desc:            "I need you to deliver this letter to the Blacksmith. He must know of the danger approaching.",
		GiverNameMatch:  "mayor",
		TurninNameMatch: "master blacksmith",
		Prereqs:         []int{2},
		LevelReq:        2,
		Objectives:      []QuestObjective{{Label: "Deliver the letter to the Blacksmith", Required: 1, Type: QuestObjDeliver}},
		RewardGold: 75, RewardXP: 150,
		FactionName: "haven", FactionRep: 50,
		CompletionMsg: "Thank you for the message. The Elder was right to send you.",
	},
	{
		ID: 5, Name: "Clearing the Road",
		Desc:            "The roads are not safe. I need you to clear more creatures before the merchants can travel safely.",
		GiverNameMatch:  "mayor",
		TurninNameMatch: "mayor",
		Prereqs:         []int{4},
		LevelReq:        3,
		Objectives:      []QuestObjective{{Label: "Kill hostile creatures", Required: 20, Type: QuestObjKill}},
		RewardGold: 200, RewardXP: 400,
		FactionName: "haven", FactionRep: 100,
		CompletionMsg: "The roads are safer now. Thank you, adventurer.",
	},
	{
		ID: 6, Name: "The Ancient Threat",
		Desc:            "Ancient serpents have returned to the land. Slay five of them to protect the village.",
		GiverNameMatch:  "mayor",
		TurninNameMatch: "mayor",
		Prereqs:         []int{5},
		LevelReq:        5,
		Objectives:      []QuestObjective{{Label: "Kill Serpents", Required: 5, Type: QuestObjKillSpecific, ParamStr: "serpent"}},
		RewardGold: 300, RewardXP: 600,
		FactionName: "haven", FactionRep: 150,
		CompletionMsg: "The ancient threat is no more. The village owes you a great debt.",
	},

	// -----------------------------------------------------------------------
	// Chain 2 — Master Blacksmith
	// -----------------------------------------------------------------------
	{
		ID: 7, Name: "Raw Materials",
		Desc:            "Ah, a fresh face. I am Master Blacksmith Aldric. Gather ten pieces of ore and prove you are worth teaching.",
		GiverNameMatch:  "master blacksmith",
		TurninNameMatch: "master blacksmith",
		LevelReq:        1,
		Objectives:      []QuestObjective{{Label: "Gather ore", Required: 10, Type: QuestObjGather, ObjTypes: []int{32}}},
		RewardGold: 80, RewardXP: 160,
		FactionName: "ironhaven", FactionRep: 100,
		CompletionMsg: "Good haul! Now let me show you what to do with all this ore.",
	},
	{
		ID: 8, Name: "Learning to Smelt",
		Desc:            "Every blacksmith must learn to smelt ore into steel. Smelt three batches for me.",
		GiverNameMatch:  "master blacksmith",
		TurninNameMatch: "master blacksmith",
		Prereqs:         []int{7},
		LevelReq:        2,
		Objectives:      []QuestObjective{{Label: "Smelt ore into steel", Required: 3, Type: QuestObjCraft, ParamStr: "smelt"}},
		RewardGold: 120, RewardXP: 240,
		FactionName: "ironhaven", FactionRep: 150,
		CompletionMsg: "Fine steel! Now you are ready to forge real weapons.",
	},
	{
		ID: 9, Name: "First Weapon",
		Desc:            "Use a blacksmithing blueprint to forge your first weapon. Show me what you can do!",
		GiverNameMatch:  "master blacksmith",
		TurninNameMatch: "master blacksmith",
		Prereqs:         []int{8},
		LevelReq:        3,
		Objectives:      []QuestObjective{{Label: "Forge a weapon or armour", Required: 1, Type: QuestObjCraft, ParamStr: "forge"}},
		RewardGold: 200, RewardXP: 300, RewardItems: []QuestRewardItem{{5, 1}},
		FactionName: "ironhaven", FactionRep: 175,
		CompletionMsg: "An excellent piece of work! You have the makings of a true smith.",
	},
	{
		ID: 10, Name: "Arming the Militia",
		Desc:            "The militia needs weapons. Forge five items from blueprints to equip them.",
		GiverNameMatch:  "master blacksmith",
		TurninNameMatch: "master blacksmith",
		Prereqs:         []int{9},
		LevelReq:        5,
		Objectives:      []QuestObjective{{Label: "Forge weapons or armour", Required: 5, Type: QuestObjCraft, ParamStr: "forge"}},
		RewardGold: 500, RewardXP: 800,
		FactionName: "ironhaven", FactionRep: 200,
		CompletionMsg: "The militia is armed and ready. You have done great service for this town.",
	},

	// -----------------------------------------------------------------------
	// Chain 3 — Cook
	// -----------------------------------------------------------------------
	{
		ID: 3, Name: "The Hungry Traveler",
		Desc:            "I could use some help in the kitchen. Show me you can cook.",
		GiverNameMatch:  "cook",
		TurninNameMatch: "cook",
		LevelReq:        1,
		Objectives:      []QuestObjective{{Label: "Cook food items", Required: 3, Type: QuestObjCook}},
		RewardGold: 75, RewardXP: 150,
		FactionName: "thornwall", FactionRep: 100,
		CompletionMsg: "Delicious! You have real talent in the kitchen.",
	},
	{
		ID: 11, Name: "Feed the Village",
		Desc:            "Winter is coming and the village needs food. Cook ten meals for the storeroom.",
		GiverNameMatch:  "cook",
		TurninNameMatch: "cook",
		Prereqs:         []int{3},
		LevelReq:        2,
		Objectives:      []QuestObjective{{Label: "Cook food for the village", Required: 10, Type: QuestObjCook}},
		RewardGold: 150, RewardXP: 250,
		FactionName: "thornwall", FactionRep: 150,
		CompletionMsg: "The village will eat well this winter, thanks to you!",
	},
	{
		ID: 12, Name: "Rare Catch",
		Desc:            "I need fresh fish for a special feast. Bring me five fish from the nearby waters.",
		GiverNameMatch:  "cook",
		TurninNameMatch: "cook",
		Prereqs:         []int{11},
		LevelReq:        3,
		Objectives:      []QuestObjective{{Label: "Gather fresh fish", Required: 5, Type: QuestObjGather, ObjTypes: []int{39}}},
		RewardGold: 100, RewardXP: 200,
		FactionName: "thornwall", FactionRep: 125,
		CompletionMsg: "What a wonderful catch! The feast will be remembered for years.",
	},

	// -----------------------------------------------------------------------
	// Chain 4 — Guard
	// -----------------------------------------------------------------------
	{
		ID: 13, Name: "Pest Control",
		Desc:            "Giant spiders have been terrorizing travellers on the road. Kill ten of them.",
		GiverNameMatch:  "guard",
		TurninNameMatch: "guard",
		LevelReq:        2,
		Objectives:      []QuestObjective{{Label: "Kill Spiders", Required: 10, Type: QuestObjKillSpecific, ParamStr: "spider"}},
		RewardGold: 120, RewardXP: 250,
		FactionName: "thornwall", FactionRep: 100,
		CompletionMsg: "Well done! The roads are safe again for now.",
	},
	{
		ID: 14, Name: "Into the Wilderness",
		Desc:            "We need scouts in the eastern forest. Explore the area and report back.",
		GiverNameMatch:  "guard",
		TurninNameMatch: "guard",
		LevelReq:        1,
		Objectives:      []QuestObjective{{Label: "Explore the Eastern Forest", Required: 1, Type: QuestObjExplore, Param: 4}},
		RewardGold: 50, RewardXP: 100,
		FactionName: "thornwall", FactionRep: 75,
		CompletionMsg: "Good scouting! Now we know what lurks out there.",
	},
	{
		ID: 15, Name: "Big Game",
		Desc:            "Trolls have moved into the region. Take down five of them before they destroy the farmsteads.",
		GiverNameMatch:  "guard",
		TurninNameMatch: "guard",
		Prereqs:         []int{13, 14},
		LevelReq:        5,
		Objectives:      []QuestObjective{{Label: "Kill Trolls", Required: 5, Type: QuestObjKillSpecific, ParamStr: "troll"}},
		RewardGold: 250, RewardXP: 500,
		FactionName: "thornwall", FactionRep: 175,
		CompletionMsg: "Those trolls won't be bothering anyone anymore. Exceptional work!",
	},
	{
		ID: 16, Name: "Ancient Ruins",
		Desc:            "Strange lights have been seen in the ancient ruins to the south-east. Scout the area.",
		GiverNameMatch:  "guard",
		TurninNameMatch: "guard",
		Prereqs:         []int{14},
		LevelReq:        3,
		Objectives:      []QuestObjective{{Label: "Explore the Ancient Ruins", Required: 1, Type: QuestObjExplore, Param: 6}},
		RewardGold: 100, RewardXP: 200,
		FactionName: "thornwall", FactionRep: 100,
		CompletionMsg: "Those ruins are indeed dangerous. Good to have a full report.",
	},

	// -----------------------------------------------------------------------
	// Chain 5 — Merchant Tim
	// -----------------------------------------------------------------------
	{
		ID: 17, Name: "Supply Run",
		Desc:            "My lumber supply is depleted. Bring me five logs and I will make it worth your while.",
		GiverNameMatch:  "tim",
		TurninNameMatch: "tim",
		LevelReq:        1,
		Objectives:      []QuestObjective{{Label: "Gather logs", Required: 5, Type: QuestObjGather, ObjTypes: []int{20}}},
		RewardGold: 60, RewardXP: 120,
		FactionName: "haven", FactionRep: 75,
		CompletionMsg: "Perfect! That's exactly what I needed. Come back if you want more work.",
	},
	{
		ID: 18, Name: "Timber!",
		Desc:            "I need planks cut from logs for my workshop. Use the carpentry station to cut three batches.",
		GiverNameMatch:  "tim",
		TurninNameMatch: "tim",
		Prereqs:         []int{17},
		LevelReq:        2,
		Objectives:      []QuestObjective{{Label: "Cut logs into planks", Required: 3, Type: QuestObjCraft, ParamStr: "planks"}},
		RewardGold: 100, RewardXP: 200,
		FactionName: "haven", FactionRep: 100,
		CompletionMsg: "Good clean cuts! Those planks will build something fine.",
	},
	{
		ID: 19, Name: "Well Equipped",
		Desc:            "I need a reliable supply of ore for trade. Gather ten pieces and bring them here.",
		GiverNameMatch:  "tim",
		TurninNameMatch: "tim",
		Prereqs:         []int{17},
		LevelReq:        2,
		Objectives:      []QuestObjective{{Label: "Gather ore", Required: 10, Type: QuestObjGather, ObjTypes: []int{32}}},
		RewardGold: 150, RewardXP: 250,
		FactionName: "haven", FactionRep: 125,
		CompletionMsg: "Excellent stock! The trade caravans will be pleased.",
	},

	// -----------------------------------------------------------------------
	// Chain 6 — Sylvara the Spell Merchant
	// -----------------------------------------------------------------------
	{
		ID: 20, Name: "Magical Aptitude",
		Desc:            "You found me all the way out here — good. The air elementals in the ancient ruins are a danger to all. Slay three and I will teach you something priceless.",
		GiverNameMatch:  "sylvara",
		TurninNameMatch: "sylvara",
		LevelReq:        4,
		Objectives:      []QuestObjective{{Label: "Kill Elementals", Required: 3, Type: QuestObjKillSpecific, ParamStr: "elemental"}},
		RewardGold: 200, RewardXP: 400,
		FactionName: "sealport", FactionRep: 150,
		CompletionMsg: "Impressive! You have proven yourself worthy of learning the higher arts.",
	},
}

// questDefByID returns a quest definition by ID.
func questDefByID(id int) *QuestDef {
	for i := range questDefs {
		if questDefs[i].ID == id {
			return &questDefs[i]
		}
	}
	return nil
}

// questsForNPCByName returns quests where this NPC is the giver or turn-in target,
// matching by case-insensitive substring of the NPC name.
func questsForNPCByName(npcName string) []*QuestDef {
	nameLower := strings.ToLower(npcName)
	var out []*QuestDef
	for i := range questDefs {
		qd := &questDefs[i]
		giver := strings.ToLower(qd.GiverNameMatch)
		turnin := strings.ToLower(qd.TurninNameMatch)
		if (giver != "" && strings.Contains(nameLower, giver)) ||
			(turnin != "" && strings.Contains(nameLower, turnin)) {
			out = append(out, qd)
		}
	}
	return out
}

func (w *World) handleQuestTalk(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	npcID, err := r.ReadI32()
	if err != nil {
		return
	}
	npc, ok := w.npcs[npcID]
	if !ok || npc.MapID != p.MapID {
		return
	}

	nameLower := strings.ToLower(npc.Def.Name)

	npcIsGiver := func(qd *QuestDef) bool {
		m := strings.ToLower(qd.GiverNameMatch)
		return m != "" && strings.Contains(nameLower, m)
	}
	npcIsTurnin := func(qd *QuestDef) bool {
		m := strings.ToLower(qd.TurninNameMatch)
		return m != "" && strings.Contains(nameLower, m)
	}

	// Priority 1: active quests that can be turned in at this NPC.
	for questID := range p.ActiveQuests {
		qd := questDefByID(questID)
		if qd == nil || !npcIsTurnin(qd) {
			continue
		}
		if w.questCanTurnIn(p, qd) {
			w.sendQuestOffer(p, npc, qd, true)
			return
		}
	}

	// Priority 2: active quests — show progress reminder if this NPC is the giver
	// (only when giver != turnin, otherwise they would have been caught above).
	for questID := range p.ActiveQuests {
		qd := questDefByID(questID)
		if qd == nil || !npcIsGiver(qd) {
			continue
		}
		if !npcIsTurnin(qd) {
			progress := w.questProgressStr(p, qd)
			w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("["+qd.Name+"] "+progress))
			return
		}
		// Same giver+turnin but not yet complete — show progress.
		progress := w.questProgressStr(p, qd)
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("["+qd.Name+"] "+progress))
		return
	}

	// Priority 3: offer the first available quest this NPC can give.
	for i := range questDefs {
		qd := &questDefs[i]
		if !npcIsGiver(qd) {
			continue
		}
		if p.hasActiveQuest(qd.ID) || p.hasCompletedQuest(qd.ID) {
			continue
		}
		if !p.hasAllPrereqsComplete(qd.Prereqs) {
			continue
		}
		w.sendQuestOffer(p, npc, qd, false)
		return
	}

	w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(npc.Def.Name+" has nothing for you."))
}

func (w *World) sendQuestOffer(p *Player, npc *NPC, qd *QuestDef, isTurnin bool) {
	mode := uint8(0)
	if isTurnin {
		mode = 1
	}

	wr := proto.NewWriter(256)
	wr.WriteU8(mode)
	wr.WriteU16(uint16(qd.ID))
	wr.WriteStr(npc.Def.Name)
	wr.WriteStr(qd.Name)
	wr.WriteStr(qd.Desc)

	wr.WriteU8(uint8(len(qd.Objectives)))
	for _, obj := range qd.Objectives {
		wr.WriteStr(obj.Label)
		wr.WriteU16(uint16(obj.Required))
		wr.WriteU8(uint8(obj.Type))
	}
	wr.WriteI32(int32(qd.RewardGold))
	wr.WriteI32(int32(qd.RewardXP))
	wr.WriteU8(uint8(len(qd.RewardItems)))
	for _, item := range qd.RewardItems {
		wr.WriteI16(int16(item.ObjIndex))
		wr.WriteU16(uint16(item.Amount))
		obj := w.gameData.GetObject(item.ObjIndex)
		name := ""
		if obj != nil {
			name = obj.Name
		}
		wr.WriteStr(name)
	}
	w.sendTo(p, proto.MsgSQuestOffer, wr.Bytes())
}

func (w *World) handleQuestAccept(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	questID, err := r.ReadU16()
	if err != nil {
		return
	}
	qd := questDefByID(int(questID))
	if qd == nil {
		return
	}

	if !p.hasAllPrereqsComplete(qd.Prereqs) {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You must complete the required quests first."))
		return
	}
	if p.hasActiveQuest(qd.ID) || p.hasCompletedQuest(qd.ID) {
		return
	}

	p.ActiveQuests[int(questID)] = make(map[int]int) // objective index → progress
	w.sendQuestUpdate(p, int(questID))
	w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("Quest accepted: "+qd.Name))
	w.sendQuestIndicators(p)
}

func (w *World) handleQuestTurnin(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	questID, err := r.ReadU16()
	if err != nil {
		return
	}
	qd := questDefByID(int(questID))
	if qd == nil || !p.hasActiveQuest(qd.ID) {
		return
	}
	if !w.questCanTurnIn(p, qd) {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("Quest not yet complete."))
		return
	}

	// Remove required items from inventory for gather objectives.
	for _, obj := range qd.Objectives {
		if obj.Type == QuestObjGather {
			w.removeItemsFromInventoryByTypes(p, obj.ObjTypes, obj.Required)
		}
	}

	// Award rewards.
	p.Gold += qd.RewardGold
	p.Exp += qd.RewardXP
	for _, item := range qd.RewardItems {
		w.giveItem(p, item.ObjIndex, item.Amount)
	}

	delete(p.ActiveQuests, qd.ID)
	if p.CompletedQuests == nil {
		p.CompletedQuests = make(map[int]bool)
	}
	p.CompletedQuests[qd.ID] = true

	wr := proto.NewWriter(16)
	wr.WriteU16(uint16(qd.ID))
	wr.WriteI32(int32(qd.RewardGold))
	wr.WriteI32(int32(qd.RewardXP))
	w.sendTo(p, proto.MsgSQuestComplete, wr.Bytes())
	w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
	w.sendTo(p, proto.MsgSStats, p.BuildStats())
	if qd.CompletionMsg != "" {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(qd.CompletionMsg))
	}

	w.checkAchievements(p, "quest", 1)
	w.checkLevelUp(p)
	w.sendQuestIndicators(p)
}

func (w *World) questCanTurnIn(p *Player, qd *QuestDef) bool {
	progress, ok := p.ActiveQuests[qd.ID]
	if !ok {
		return false
	}
	for i, obj := range qd.Objectives {
		var current int
		switch obj.Type {
		case QuestObjGather:
			current = w.countInInventoryByTypes(p, obj.ObjTypes)
		case QuestObjDeliver:
			current = obj.Required // deliver is always ready once accepted
		default:
			current = progress[i]
		}
		if current < obj.Required {
			return false
		}
	}
	return true
}

func (w *World) questProgressStr(p *Player, qd *QuestDef) string {
	progress, ok := p.ActiveQuests[qd.ID]
	if !ok {
		return ""
	}
	out := ""
	for i, obj := range qd.Objectives {
		var current int
		switch obj.Type {
		case QuestObjGather:
			current = w.countInInventoryByTypes(p, obj.ObjTypes)
		case QuestObjDeliver:
			current = obj.Required
		default:
			current = progress[i]
		}
		if out != "" {
			out += ", "
		}
		out += fmt.Sprintf("%s: %d/%d", obj.Label, current, obj.Required)
	}
	return out
}

func (w *World) sendQuestUpdate(p *Player, questID int) {
	qd := questDefByID(questID)
	if qd == nil {
		return
	}
	progress := w.questProgressStr(p, qd)
	wr := proto.NewWriter(64)
	wr.WriteU16(uint16(questID))
	wr.WriteStr(progress)
	w.sendTo(p, proto.MsgSQuestUpdate, wr.Bytes())
}

func (w *World) sendQuestIndicators(p *Player) {
	type indicator struct {
		npcInstanceID int32
		symbol        string
	}
	var indicators []indicator

	for _, npc := range w.npcs {
		if npc.MapID != p.MapID {
			continue
		}
		nameLower := strings.ToLower(npc.Def.Name)
		sym := ""
		for i := range questDefs {
			qd := &questDefs[i]
			giverMatch := strings.ToLower(qd.GiverNameMatch)
			turninMatch := strings.ToLower(qd.TurninNameMatch)
			isGiver := giverMatch != "" && strings.Contains(nameLower, giverMatch)
			isTurnin := turninMatch != "" && strings.Contains(nameLower, turninMatch)

			if isTurnin && p.hasActiveQuest(qd.ID) && w.questCanTurnIn(p, qd) {
				sym = "?"
				break
			}
			if isGiver && sym != "?" && !p.hasActiveQuest(qd.ID) && !p.hasCompletedQuest(qd.ID) && p.hasAllPrereqsComplete(qd.Prereqs) {
				sym = "!"
			}
		}
		if sym != "" {
			indicators = append(indicators, indicator{npc.InstanceID, sym})
		}
	}

	wr := proto.NewWriter(64)
	wr.WriteU16(uint16(len(indicators)))
	for _, ind := range indicators {
		wr.WriteI32(ind.npcInstanceID)
		wr.WriteStr(ind.symbol)
	}
	w.sendTo(p, proto.MsgSQuestIndicators, wr.Bytes())
}

// onKillNPC updates quest progress for kill and kill_specific objectives.
func (w *World) onKillNPC(p *Player, npcName string) {
	nameLower := strings.ToLower(npcName)
	for questID, progress := range p.ActiveQuests {
		qd := questDefByID(questID)
		if qd == nil {
			continue
		}
		changed := false
		for i, obj := range qd.Objectives {
			switch obj.Type {
			case QuestObjKill:
				progress[i] = imax(0, progress[i]) + 1
				changed = true
			case QuestObjKillSpecific:
				if obj.ParamStr != "" && strings.Contains(nameLower, strings.ToLower(obj.ParamStr)) {
					progress[i] = imax(0, progress[i]) + 1
					changed = true
				}
			}
		}
		if changed {
			w.sendQuestUpdate(p, questID)
			if w.questCanTurnIn(p, qd) {
				w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("["+qd.Name+"] Quest complete! Return to turn in."))
			}
		}
	}
	w.checkAchievements(p, "kill", 1)
}

// onCraftItem updates quest progress for craft objectives matching the given action string.
func (w *World) onCraftItem(p *Player, action string) {
	actionLower := strings.ToLower(action)
	for questID, progress := range p.ActiveQuests {
		qd := questDefByID(questID)
		if qd == nil {
			continue
		}
		changed := false
		for i, obj := range qd.Objectives {
			if obj.Type == QuestObjCraft && strings.ToLower(obj.ParamStr) == actionLower {
				progress[i] = imax(0, progress[i]) + 1
				changed = true
			}
		}
		if changed {
			w.sendQuestUpdate(p, questID)
			if w.questCanTurnIn(p, qd) {
				w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("["+qd.Name+"] Quest complete! Return to turn in."))
			}
		}
	}
	w.checkAchievements(p, "craft", 1)
}

// onCookItem updates quest progress for cook objectives.
func (w *World) onCookItem(p *Player) {
	for questID, progress := range p.ActiveQuests {
		qd := questDefByID(questID)
		if qd == nil {
			continue
		}
		changed := false
		for i, obj := range qd.Objectives {
			if obj.Type == QuestObjCook {
				progress[i] = imax(0, progress[i]) + 1
				changed = true
			}
		}
		if changed {
			w.sendQuestUpdate(p, questID)
			if w.questCanTurnIn(p, qd) {
				w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("["+qd.Name+"] Quest complete! Return to turn in."))
			}
		}
	}
	w.checkAchievements(p, "craft", 1)
}

// onExploreMap updates quest progress for explore objectives.
func (w *World) onExploreMap(p *Player, mapID int) {
	w.trackMapVisit(p, mapID)
	for questID, progress := range p.ActiveQuests {
		qd := questDefByID(questID)
		if qd == nil {
			continue
		}
		for i, obj := range qd.Objectives {
			if obj.Type == QuestObjExplore && obj.Param == mapID {
				if progress[i] < obj.Required {
					progress[i]++
					w.sendQuestUpdate(p, questID)
					if w.questCanTurnIn(p, qd) {
						w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("["+qd.Name+"] Quest complete! Return to turn in."))
					}
				}
			}
		}
	}
}

// countInInventory counts items with objIndex in the player's inventory.
func (w *World) countInInventory(p *Player, objIndex int) int {
	count := 0
	for _, slot := range p.Inventory {
		if slot != nil && slot.ObjIndex == objIndex {
			count += slot.Amount
		}
	}
	return count
}

// countInInventoryByTypes counts inventory items whose obj_type is in the given set.
func (w *World) countInInventoryByTypes(p *Player, objTypes []int) int {
	if len(objTypes) == 0 {
		return 0
	}
	typeSet := make(map[int]bool, len(objTypes))
	for _, t := range objTypes {
		typeSet[t] = true
	}
	count := 0
	for _, slot := range p.Inventory {
		if slot == nil {
			continue
		}
		obj := w.gameData.GetObject(slot.ObjIndex)
		if obj != nil && typeSet[obj.ObjType] {
			count += slot.Amount
		}
	}
	return count
}

// removeItemsFromInventoryByTypes removes `required` total items whose obj_type is in the set.
func (w *World) removeItemsFromInventoryByTypes(p *Player, objTypes []int, required int) {
	if len(objTypes) == 0 || required <= 0 {
		return
	}
	typeSet := make(map[int]bool, len(objTypes))
	for _, t := range objTypes {
		typeSet[t] = true
	}
	remaining := required
	for i, slot := range p.Inventory {
		if remaining <= 0 {
			break
		}
		if slot == nil {
			continue
		}
		obj := w.gameData.GetObject(slot.ObjIndex)
		if obj == nil || !typeSet[obj.ObjType] {
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

// Player quest helpers.
func (p *Player) hasActiveQuest(questID int) bool {
	if p.ActiveQuests == nil {
		return false
	}
	_, ok := p.ActiveQuests[questID]
	return ok
}

func (p *Player) hasCompletedQuest(questID int) bool {
	if p.CompletedQuests == nil {
		return false
	}
	return p.CompletedQuests[questID]
}

func (p *Player) hasAllPrereqsComplete(prereqs []int) bool {
	for _, id := range prereqs {
		if !p.hasCompletedQuest(id) {
			return false
		}
	}
	return true
}
