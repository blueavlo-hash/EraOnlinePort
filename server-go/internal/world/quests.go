package world

import (
	"fmt"

	"github.com/blueavlo-hash/eraonline-server/internal/proto"
)

// Quest objective types.
const (
	QuestObjKill    = 0
	QuestObjGather  = 1
	QuestObjCraft   = 2
	QuestObjExplore = 3
	QuestObjDeliver = 4
)

// QuestObjective is one step of a quest.
type QuestObjective struct {
	Label    string
	Required int
	Type     int // QuestObj* constants
	Param    int // kill: NPC index; gather/deliver: obj_index; explore: map_id
}

// QuestDef defines one quest.
type QuestDef struct {
	ID          int
	Name        string
	Desc        string
	NPCID       int // NPC that gives/completes this quest (by NPC def index)
	Prereq      int // quest ID that must be complete first (0 = none)
	Objectives  []QuestObjective
	RewardGold  int
	RewardXP    int
	RewardItems []QuestRewardItem
	FactionName string
	FactionRep  int
}

// QuestRewardItem is an item rewarded on quest completion.
type QuestRewardItem struct {
	ObjIndex int
	Amount   int
}

// questDefs is the master quest list. Mirrored from server_quests.gd.
var questDefs = []QuestDef{
	// Elder chain (NPC index 1)
	{1, "The Elder's Request", "The village elder needs rats killed.", 1, 0,
		[]QuestObjective{{Label: "Kill rats", Required: 5, Type: QuestObjKill, Param: 1}},
		100, 200, nil, "Millwall", 75},
	{2, "Mushroom Stew", "Gather mushrooms for the elder.", 1, 1,
		[]QuestObjective{{Label: "Gather mushrooms", Required: 10, Type: QuestObjGather, Param: 60}},
		150, 300, nil, "Millwall", 100},
	{3, "Protect the Farm", "Kill wolves threatening the farm.", 1, 2,
		[]QuestObjective{{Label: "Kill wolves", Required: 8, Type: QuestObjKill, Param: 5}},
		200, 500, nil, "Millwall", 100},
	{4, "Ancient Ruins", "Explore the ancient ruins.", 1, 3,
		[]QuestObjective{{Label: "Visit the ruins", Required: 1, Type: QuestObjExplore, Param: 12}},
		300, 750, nil, "Millwall", 150},
	{5, "The Elder's Legacy", "Defeat the dungeon boss.", 1, 4,
		[]QuestObjective{{Label: "Defeat the boss", Required: 1, Type: QuestObjKill, Param: 50}},
		500, 1500, []QuestRewardItem{{101, 1}}, "Millwall", 200},
	// Blacksmith chain (NPC index 2)
	{6, "Ore Delivery", "Mine ore for the blacksmith.", 2, 0,
		[]QuestObjective{{Label: "Mine ore", Required: 10, Type: QuestObjGather, Param: 30}},
		120, 250, nil, "Ironhold", 75},
	{7, "Steel for the Forge", "Smelt steel bars for the blacksmith.", 2, 6,
		[]QuestObjective{{Label: "Smelt steel", Required: 5, Type: QuestObjCraft, Param: 31}},
		200, 400, nil, "Ironhold", 100},
	{8, "A Sturdy Sword", "Craft a sword for the blacksmith.", 2, 7,
		[]QuestObjective{{Label: "Craft a sword", Required: 1, Type: QuestObjCraft, Param: 102}},
		350, 700, []QuestRewardItem{{102, 1}}, "Ironhold", 150},
	{9, "Armory Restocked", "Deliver the weapons to the guard.", 2, 8,
		[]QuestObjective{{Label: "Deliver to guard", Required: 1, Type: QuestObjDeliver, Param: 102}},
		500, 1000, nil, "Ironhold", 200},
	// Cook chain (NPC index 3)
	{10, "Hungry Village", "Cook meals for the village.", 3, 0,
		[]QuestObjective{{Label: "Cook fish", Required: 3, Type: QuestObjCraft, Param: 51}},
		100, 200, nil, "Millwall", 75},
	{11, "Festival Feast", "Prepare a grand feast.", 3, 10,
		[]QuestObjective{
			{Label: "Cook fish", Required: 5, Type: QuestObjCraft, Param: 51},
			{Label: "Gather mushrooms", Required: 5, Type: QuestObjGather, Param: 60},
		},
		200, 500, nil, "Millwall", 100},
	{12, "The Secret Recipe", "Find the lost recipe scroll.", 3, 11,
		[]QuestObjective{{Label: "Find scroll", Required: 1, Type: QuestObjGather, Param: 200}},
		300, 750, nil, "Millwall", 150},
	// Guard chain (NPC index 4)
	{13, "Patrol Duty", "Kill bandits on the road.", 4, 0,
		[]QuestObjective{{Label: "Kill bandits", Required: 5, Type: QuestObjKill, Param: 10}},
		150, 300, nil, "Ironhold", 75},
	{14, "The Bandit Leader", "Track down the bandit leader.", 4, 13,
		[]QuestObjective{
			{Label: "Kill bandits", Required: 10, Type: QuestObjKill, Param: 10},
			{Label: "Defeat bandit leader", Required: 1, Type: QuestObjKill, Param: 11},
		},
		300, 600, nil, "Ironhold", 100},
	{15, "Evidence Trail", "Gather bandit insignia.", 4, 14,
		[]QuestObjective{{Label: "Collect insignia", Required: 3, Type: QuestObjGather, Param: 201}},
		400, 800, nil, "Ironhold", 150},
	{16, "Justice Served", "Bring the evidence to the magistrate.", 4, 15,
		[]QuestObjective{{Label: "Deliver evidence", Required: 1, Type: QuestObjDeliver, Param: 201}},
		600, 1200, []QuestRewardItem{{200, 1}}, "Ironhold", 200},
	// Merchant chain (NPC index 5)
	{17, "Trade Route", "Clear the road of monsters.", 5, 0,
		[]QuestObjective{{Label: "Kill monsters on road", Required: 10, Type: QuestObjKill, Param: 15}},
		200, 400, nil, "Millwall", 75},
	{18, "Missing Goods", "Recover stolen merchant goods.", 5, 17,
		[]QuestObjective{{Label: "Recover goods", Required: 5, Type: QuestObjGather, Param: 202}},
		300, 600, nil, "Millwall", 100},
	{19, "Merchant's Favor", "Escort goods to the next town.", 5, 18,
		[]QuestObjective{{Label: "Deliver goods", Required: 1, Type: QuestObjDeliver, Param: 202}},
		500, 1000, nil, "Millwall", 150},
	// Spell Merchant (NPC index 6)
	{20, "Arcane Components", "Gather magical reagents.", 6, 0,
		[]QuestObjective{
			{Label: "Gather reagents", Required: 5, Type: QuestObjGather, Param: 203},
			{Label: "Kill elementals", Required: 3, Type: QuestObjKill, Param: 20},
		},
		400, 1000, []QuestRewardItem{{204, 1}}, "Wizards", 200},
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

// questsForNPC returns all quest defs assigned to a given NPC def index.
func questsForNPC(npcDefIndex int) []*QuestDef {
	var out []*QuestDef
	for i := range questDefs {
		if questDefs[i].NPCID == npcDefIndex {
			out = append(out, &questDefs[i])
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

	quests := questsForNPC(npc.DefIndex)
	if len(quests) == 0 {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(npc.Def.Name+" has nothing for you."))
		return
	}

	// Find first quest that is: available (prereq done, not started) or active (can turn in).
	for _, qd := range quests {
		// Check prereq.
		if qd.Prereq > 0 && !p.hasCompletedQuest(qd.Prereq) {
			continue
		}
		// Already completed?
		if p.hasCompletedQuest(qd.ID) {
			continue
		}
		// Active — check if completable.
		if p.hasActiveQuest(qd.ID) {
			if w.questCanTurnIn(p, qd) {
				w.sendQuestOffer(p, npc, qd, true)
			} else {
				// Send progress reminder.
				progress := w.questProgressStr(p, qd)
				w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("["+qd.Name+"] "+progress))
			}
			return
		}
		// Available — offer it.
		w.sendQuestOffer(p, npc, qd, false)
		return
	}

	// No quests available.
	w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(npc.Def.Name+" has no more quests for you."))
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

	// Validate prereqs.
	if qd.Prereq > 0 && !p.hasCompletedQuest(qd.Prereq) {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You must complete another quest first."))
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

	// Remove required items from inventory (for gather/deliver objectives).
	for _, obj := range qd.Objectives {
		if obj.Type == QuestObjGather || obj.Type == QuestObjDeliver {
			w.removeItemFromInventory(p, obj.Param, obj.Required)
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
		current := progress[i]
		// For gather objectives, also check current inventory.
		if obj.Type == QuestObjGather || obj.Type == QuestObjDeliver {
			current = w.countInInventory(p, obj.Param)
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
		current := progress[i]
		if obj.Type == QuestObjGather || obj.Type == QuestObjDeliver {
			current = w.countInInventory(p, obj.Param)
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
	// Build indicator list for NPCs that have available/completable quests.
	type indicator struct {
		npcInstanceID int32
		symbol        string // "!" = available, "?" = completable, "" = none
	}
	var indicators []indicator

	for _, npc := range w.npcs {
		if npc.MapID != p.MapID {
			continue
		}
		quests := questsForNPC(npc.DefIndex)
		for _, qd := range quests {
			sym := ""
			if p.hasActiveQuest(qd.ID) && w.questCanTurnIn(p, qd) {
				sym = "?"
			} else if !p.hasActiveQuest(qd.ID) && !p.hasCompletedQuest(qd.ID) {
				if qd.Prereq == 0 || p.hasCompletedQuest(qd.Prereq) {
					sym = "!"
				}
			}
			if sym != "" {
				indicators = append(indicators, indicator{npc.InstanceID, sym})
				break
			}
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

// onKillNPC updates quest progress for kill objectives.
func (w *World) onKillNPC(p *Player, npcDefIndex int) {
	for questID, progress := range p.ActiveQuests {
		qd := questDefByID(questID)
		if qd == nil {
			continue
		}
		for i, obj := range qd.Objectives {
			if obj.Type == QuestObjKill && obj.Param == npcDefIndex {
				progress[i] = imax(0, progress[i]) + 1
				w.sendQuestUpdate(p, questID)
				if w.questCanTurnIn(p, qd) {
					w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("["+qd.Name+"] Quest complete! Return to turn in."))
				}
			}
		}
	}
	w.checkAchievements(p, "kill", 1)
}

// onCraftItem updates quest progress for craft objectives.
func (w *World) onCraftItem(p *Player, objIndex int) {
	for questID, progress := range p.ActiveQuests {
		qd := questDefByID(questID)
		if qd == nil {
			continue
		}
		for i, obj := range qd.Objectives {
			if obj.Type == QuestObjCraft && obj.Param == objIndex {
				progress[i] = imax(0, progress[i]) + 1
				w.sendQuestUpdate(p, questID)
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
