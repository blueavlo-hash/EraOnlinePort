package world

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/blueavlo-hash/eraonline-server/internal/db"
	"github.com/blueavlo-hash/eraonline-server/internal/proto"
)

// ---------------------------------------------------------------------------
// Movement
// ---------------------------------------------------------------------------

func (w *World) handleMove(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	dir, err := r.ReadU8()
	if err != nil {
		return
	}
	if dir < 1 || dir > 4 {
		return
	}

	dx, dy := wanderDelta(dir)
	nx, ny := p.X+dx, p.Y+dy

	if !w.isTileWalkable(p.MapID, nx, ny) {
		return
	}

	// Check tile exit (warp).
	m := w.gameData.GetMap(p.MapID)
	if m != nil {
		tileKey := fmt.Sprintf("%d,%d", ny, nx)
		if tile, ok := m.Tiles[tileKey]; ok && tile.ExitMap > 0 {
			w.warpPlayer(p, tile.ExitMap, tile.ExitX, tile.ExitY)
			return
		}
	}

	p.X = nx
	p.Y = ny
	p.Heading = dir

	w.broadcastMapAndSelf(p.MapID, proto.MsgSMoveChar,
		buildMoveChar(p.InstanceID, p.X, p.Y, p.Heading))

	// Track map visit for explorer achievements.
	w.trackMapVisit(p, p.MapID)
}

func (w *World) warpPlayer(p *Player, mapID, x, y int) {
	oldMap := p.MapID

	// Validate destination.
	destMap := w.gameData.GetMap(mapID)
	if destMap == nil || !destMap.HasGroundTiles() {
		mapID = w.cfg.SpawnMap
		x = w.cfg.SpawnX
		y = w.cfg.SpawnY
	}

	// Remove from old map.
	w.broadcastMap(oldMap, proto.MsgSRemoveChar, buildRemoveChar(p.InstanceID), p.InstanceID)

	p.MapID = mapID
	p.X = x
	p.Y = y

	// Send map change to player.
	wr := proto.NewWriter(8)
	wr.WriteI32(int32(mapID))
	wr.WriteI16(int16(x))
	wr.WriteI16(int16(y))
	w.sendTo(p, proto.MsgSMapChange, wr.Bytes())

	// Announce on new map.
	w.broadcastMap(mapID, proto.MsgSSetChar, p.BuildSetChar(), p.InstanceID)

	// Send all existing chars on new map to player.
	for _, other := range w.players {
		if other.InstanceID == p.InstanceID || other.MapID != mapID {
			continue
		}
		w.sendTo(p, proto.MsgSSetChar, other.BuildSetChar())
	}
	for _, npc := range w.npcs {
		if npc.MapID == mapID && !npc.Dead {
			w.sendTo(p, proto.MsgSSetChar, npc.BuildSetChar())
		}
	}

	// Rain state.
	if destMap2 := w.gameData.GetMap(mapID); destMap2 != nil {
		if destMap2.Rain || w.raining {
			w.sendTo(p, proto.MsgSRainOn, nil)
		} else {
			w.sendTo(p, proto.MsgSRainOff, nil)
		}
	}

	w.trackMapVisit(p, mapID)
}

// ---------------------------------------------------------------------------
// Combat
// ---------------------------------------------------------------------------

func (w *World) handleAttack(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	targetID, err := r.ReadI32()
	if err != nil {
		return
	}

	if p.CombatCooldown > 0 {
		return
	}

	minDmg, maxDmg := 1, 5 // default fist
	if p.WeaponSlot > 0 {
		obj := w.gameData.GetObject(p.WeaponSlot)
		if obj != nil {
			minDmg = obj.MinHit
			maxDmg = obj.MaxHit
		}
	}

	// NPC target.
	if npc, ok := w.npcs[targetID]; ok {
		if npc.MapID != p.MapID || npc.Dead {
			return
		}
		dx := npc.X - p.X
		dy := npc.Y - p.Y
		if dx*dx+dy*dy > 4 {
			return
		}
		dmg, evaded := resolveAttack(minDmg, maxDmg, 0, p.Level, npc.Def.Defense, 1)
		w.broadcastMap(p.MapID, proto.MsgSDamage, buildDamage(targetID, int16(dmg), evaded), -1)

		if !evaded {
			npc.HP -= dmg
			if npc.HP <= 0 {
				w.npcDied(p, npc)
			}
		}
		// Award weapon skill XP.
		w.awardSkillXPForWeapon(p)
		p.CombatCooldown = w.cfg.CombatTickMS / w.cfg.TickRateMS
		p.InCombat = true

	} else if target, ok := w.players[targetID]; ok {
		// PvP — only on PK maps.
		m := w.gameData.GetMap(p.MapID)
		if m == nil || !m.PKZone {
			return
		}
		dx := target.X - p.X
		dy := target.Y - p.Y
		if dx*dx+dy*dy > 4 {
			return
		}
		targetDef := getObjDef(w, target.ShieldSlot) + getObjDef(w, target.ArmorSlot)
		dmg, evaded := resolveAttack(minDmg, maxDmg, 0, p.Level, targetDef, target.Level)
		w.broadcastMap(p.MapID, proto.MsgSDamage, buildDamage(targetID, int16(dmg), evaded), -1)

		if !evaded {
			target.HP -= dmg
			if target.HP < 0 {
				target.HP = 0
			}
			wr := proto.NewWriter(6)
			wr.WriteI16(int16(target.HP))
			wr.WriteI16(int16(target.MP))
			wr.WriteI16(int16(target.Stamina))
			w.sendTo(target, proto.MsgSHealth, wr.Bytes())

			if target.HP == 0 {
				w.playerDied(target, p.CharName)
			}
		}
		p.CombatCooldown = w.cfg.CombatTickMS / w.cfg.TickRateMS
	}
}

// awardSkillXPForWeapon awards XP to the appropriate weapon skill based on equipped weapon.
func (w *World) awardSkillXPForWeapon(p *Player) {
	if p.WeaponSlot == 0 {
		return
	}
	obj := w.gameData.GetObject(p.WeaponSlot)
	if obj == nil {
		return
	}
	switch obj.WeaponAnim {
	case 1: // sword/1h
		w.awardSkillXP(p, SkillSwordsmanship, 1)
	case 2: // axe
		w.awardSkillXP(p, SkillAxemanship, 1)
	case 3: // bow
		w.awardSkillXP(p, SkillBowmanship, 1)
	}
}

func (w *World) npcDied(killer *Player, npc *NPC) {
	w.log.Info("NPC died", "npc", npc.Def.Name, "killer", killer.CharName)
	npc.Dead = true
	npc.RespawnTicks = 120 // ~30 seconds at 4 ticks/sec

	w.broadcastMap(npc.MapID, proto.MsgSRemoveChar, buildRemoveChar(npc.InstanceID), -1)

	// Drop items.
	if npc.Def.DeathObj > 0 {
		w.spawnGroundItem(npc.MapID, npc.X, npc.Y, npc.Def.DeathObj, 1)
	}
	if npc.Def.Gold > 0 {
		gold := npc.Def.Gold/2 + randN(npc.Def.Gold/2+1)
		killer.Gold += gold
	}

	// Award XP.
	xp := npc.Def.ExpReward
	if xp == 0 {
		xp = npc.Def.MinHP / 2 // fallback: half of min HP
	}
	killer.Exp += xp
	{
		wr := proto.NewWriter(4)
		wr.WriteI32(int32(xp))
		w.sendTo(killer, proto.MsgSXPGain, wr.Bytes())
	}

	// Check level up (handles stat recalc, S_LEVEL_UP, S_STATS, and achievements).
	w.checkLevelUp(killer)

	// Kill count achievements.
	w.checkAchievements(killer, "kill", 1)

	// Gold achievement (gold may have changed).
	if npc.Def.Gold > 0 {
		w.checkAchievements(killer, "gold", 0)
	}

	// Quest kill progress.
	w.onKillNPC(killer, npc.DefIndex)
}

func (w *World) spawnGroundItem(mapID, x, y, objIndex, amount int) {
	id := w.allocGroundID()
	gi := &GroundItem{
		ID:       id,
		MapID:    mapID,
		X:        x,
		Y:        y,
		ObjIndex: objIndex,
		Amount:   amount,
		Timeout:  600, // ~2.5 minutes at 4 ticks/sec
	}
	w.groundItems[id] = gi

	wr := proto.NewWriter(12)
	wr.WriteI16(id)
	wr.WriteI16(int16(objIndex))
	wr.WriteU16(uint16(amount))
	wr.WriteI16(int16(x))
	wr.WriteI16(int16(y))
	w.broadcastMap(mapID, proto.MsgSGroundItemAdd, wr.Bytes(), -1)
}

// ---------------------------------------------------------------------------
// Chat
// ---------------------------------------------------------------------------

func (w *World) handleChat(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	msg, err := r.ReadStr()
	if err != nil || len(msg) == 0 {
		return
	}
	if len(msg) > 200 {
		msg = msg[:200]
	}
	w.broadcastMapAndSelf(p.MapID, proto.MsgSChat,
		buildChat(p.InstanceID, proto.ChatNormal, msg))
}

// ---------------------------------------------------------------------------
// Inventory
// ---------------------------------------------------------------------------

func (w *World) handlePickup(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	itemID, err := r.ReadI16()
	if err != nil {
		return
	}
	gi, ok := w.groundItems[itemID]
	if !ok || gi.MapID != p.MapID {
		return
	}
	dx := gi.X - p.X
	dy := gi.Y - p.Y
	if dx*dx+dy*dy > 4 {
		return
	}

	if !w.giveItem(p, gi.ObjIndex, gi.Amount) {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("Inventory full."))
		return
	}

	delete(w.groundItems, itemID)
	wr := proto.NewWriter(2)
	wr.WriteI16(itemID)
	w.broadcastMap(p.MapID, proto.MsgSGroundItemRemove, wr.Bytes(), -1)

	w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
}

func (w *World) handleDrop(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	slot, err := r.ReadU8()
	if err != nil {
		return
	}
	amount, err := r.ReadU16()
	if err != nil {
		return
	}
	if int(slot) >= 20 || p.Inventory[slot] == nil {
		return
	}
	inv := p.Inventory[slot]
	if inv.Equipped {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("Unequip the item first."))
		return
	}
	if int(amount) > inv.Amount {
		amount = uint16(inv.Amount)
	}

	objIndex := inv.ObjIndex
	inv.Amount -= int(amount)
	if inv.Amount <= 0 {
		p.Inventory[slot] = nil
	}
	w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
	w.spawnGroundItem(p.MapID, p.X, p.Y, objIndex, int(amount))
}

func (w *World) handleEquip(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	slot, _ := r.ReadU8()
	if int(slot) >= 20 || p.Inventory[slot] == nil {
		return
	}
	inv := p.Inventory[slot]
	obj := w.gameData.GetObject(inv.ObjIndex)
	if obj == nil {
		return
	}
	// Enforce level requirement.
	if obj.Level > 0 && p.Level < obj.Level {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(
			fmt.Sprintf("You need level %d to equip that.", obj.Level)))
		return
	}
	inv.Equipped = true
	switch obj.ClothingType {
	case 1: // weapon
		p.WeaponSlot = obj.Index
	case 2: // shield
		p.ShieldSlot = obj.Index
	case 3: // helmet
		p.HelmetSlot = obj.Index
	case 4: // armor
		p.ArmorSlot = obj.Index
	}
	w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
	w.broadcastMap(p.MapID, proto.MsgSSetChar, p.BuildSetChar(), p.InstanceID)
}

func (w *World) handleUnequip(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	slot, _ := r.ReadU8()
	if int(slot) >= 20 || p.Inventory[slot] == nil {
		return
	}
	inv := p.Inventory[slot]
	obj := w.gameData.GetObject(inv.ObjIndex)
	if obj != nil {
		switch obj.ClothingType {
		case 1:
			p.WeaponSlot = 0
		case 2:
			p.ShieldSlot = 0
		case 3:
			p.HelmetSlot = 0
		case 4:
			p.ArmorSlot = 0
		}
	}
	inv.Equipped = false
	w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
	w.broadcastMap(p.MapID, proto.MsgSSetChar, p.BuildSetChar(), p.InstanceID)
}

func (w *World) handleUseItem(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	slot, _ := r.ReadU8()
	if int(slot) >= 20 || p.Inventory[slot] == nil {
		return
	}
	obj := w.gameData.GetObject(p.Inventory[slot].ObjIndex)
	if obj == nil {
		return
	}
	if obj.Food > 0 {
		// Restore hunger (fill the hunger bar, capped at 100) and HP.
		p.Hunger = fmin(p.Hunger+float64(obj.Food), 100.0)
		p.HP = imin(p.HP+obj.Food/2, p.MaxHP)
		p.Inventory[slot].Amount--
		if p.Inventory[slot].Amount <= 0 {
			p.Inventory[slot] = nil
		}
		w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
		wr := proto.NewWriter(6)
		wr.WriteI16(int16(p.HP))
		wr.WriteI16(int16(p.MP))
		wr.WriteI16(int16(p.Stamina))
		w.sendTo(p, proto.MsgSHealth, wr.Bytes())
		// Track cooking achievement.
		w.checkAchievements(p, "craft", 1)
	}
}

// ---------------------------------------------------------------------------
// Enchanting
// ---------------------------------------------------------------------------

// enchantMaterials maps obj_type → enchant power. ObjType 9 = magic material.
const enchantMaterialObjType = 9

func (w *World) handleEnchant(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	itemSlot, err := r.ReadU8()
	if err != nil {
		return
	}
	matSlot, err := r.ReadU8()
	if err != nil {
		return
	}
	if int(itemSlot) >= 20 || int(matSlot) >= 20 {
		return
	}
	item := p.Inventory[itemSlot]
	mat := p.Inventory[matSlot]
	if item == nil || mat == nil {
		w.sendEnchantResult(p, false, 0, "Invalid slot.")
		return
	}
	if itemSlot == matSlot {
		w.sendEnchantResult(p, false, 0, "Cannot enchant with itself.")
		return
	}

	// Validate item is a weapon or armor.
	itemObj := w.gameData.GetObject(item.ObjIndex)
	if itemObj == nil || (itemObj.ClothingType == 0) {
		w.sendEnchantResult(p, false, 0, "That item cannot be enchanted.")
		return
	}

	// Validate material.
	matObj := w.gameData.GetObject(mat.ObjIndex)
	if matObj == nil || matObj.ObjType != enchantMaterialObjType {
		w.sendEnchantResult(p, false, 0, "Invalid enchanting material.")
		return
	}

	// Cap enchant level at 5.
	if item.Enchant >= 5 {
		w.sendEnchantResult(p, false, item.Enchant, "This item is already at maximum enchantment.")
		return
	}

	// 70% success chance, reduced by current enchant level.
	successChance := 0.70 - float64(item.Enchant)*0.12
	if randN(100) < int(successChance*100) {
		item.Enchant++
		// Consume one material.
		mat.Amount--
		if mat.Amount <= 0 {
			p.Inventory[matSlot] = nil
		}
		w.sendEnchantResult(p, true, item.Enchant, fmt.Sprintf("+%d enchantment applied!", item.Enchant))
	} else {
		// Failure: consume material, no enchant.
		mat.Amount--
		if mat.Amount <= 0 {
			p.Inventory[matSlot] = nil
		}
		w.sendEnchantResult(p, false, item.Enchant, "Enchantment failed! The material was consumed.")
	}
	w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
}

func (w *World) sendEnchantResult(p *Player, success bool, newLevel int, msg string) {
	wr := proto.NewWriter(32)
	if success {
		wr.WriteU8(1)
	} else {
		wr.WriteU8(0)
	}
	wr.WriteU8(uint8(newLevel))
	wr.WriteStr(msg)
	w.sendTo(p, proto.MsgSEnchantResult, wr.Bytes())
}

// ---------------------------------------------------------------------------
// Leaderboard
// ---------------------------------------------------------------------------

func (w *World) handleLeaderboardReq(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	lbType, _ := r.ReadU8() // 0=level, 1=gold (future expansion)

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	entries, err := w.db.GetLeaderboard(ctx, 10)
	if err != nil {
		w.log.Warn("leaderboard query failed", "err", err)
		return
	}

	wr := proto.NewWriter(4 + len(entries)*32)
	wr.WriteU8(lbType)
	wr.WriteU8(uint8(len(entries)))
	for _, e := range entries {
		wr.WriteStr(e.Name)
		wr.WriteI32(int32(e.Score))
	}
	w.sendTo(p, proto.MsgSLeaderboardData, wr.Bytes())
}

// ---------------------------------------------------------------------------
// Abilities
// ---------------------------------------------------------------------------

// abilityDef defines one learnable passive ability.
type abilityDef struct {
	ID        int
	Name      string
	GoldCost  int
	ReqLevel  int
	ReqSkill  int // 0 = no skill req
	ReqSkillV int // minimum skill level
}

var abilityDefs = []abilityDef{
	{1, "Second Wind", 500, 5, 0, 0},    // passive: +10 max HP
	{2, "Steady Aim", 1000, 10, 13, 5},  // passive: +2 max ranged damage
	{3, "Shield Bash", 1500, 15, 14, 5}, // active: stun on block
	{4, "Battle Cry", 2000, 20, 11, 10}, // active: nearby allies gain +5 atk
	{5, "Swift Feet", 2500, 25, 17, 10}, // passive: move speed bonus
	{6, "Arcane Focus", 3000, 20, 10, 10}, // passive: -10% spell MP cost
	{7, "Iron Skin", 2000, 15, 14, 8},   // passive: +5 defense
	{8, "Eagle Eye", 1500, 10, 13, 8},   // passive: +1 ranged range
}

func (w *World) handleLearnAbility(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	abilityID, err := r.ReadU8()
	if err != nil {
		return
	}

	// Find ability definition.
	var def *abilityDef
	for i := range abilityDefs {
		if abilityDefs[i].ID == int(abilityID) {
			def = &abilityDefs[i]
			break
		}
	}
	if def == nil {
		w.sendAbilityFail(p, "Unknown ability.")
		return
	}

	// Already learned?
	for _, id := range p.Abilities {
		if id == int(abilityID) {
			w.sendAbilityFail(p, "You already know that ability.")
			return
		}
	}

	// Level requirement.
	if p.Level < def.ReqLevel {
		w.sendAbilityFail(p, fmt.Sprintf("You need level %d to learn %s.", def.ReqLevel, def.Name))
		return
	}

	// Skill requirement.
	if def.ReqSkill > 0 {
		if p.getSkillLevel(def.ReqSkill) < def.ReqSkillV {
			w.sendAbilityFail(p, fmt.Sprintf("You need skill level %d to learn %s.", def.ReqSkillV, def.Name))
			return
		}
	}

	// Gold cost.
	if p.Gold < def.GoldCost {
		w.sendAbilityFail(p, fmt.Sprintf("You need %d gold to learn %s.", def.GoldCost, def.Name))
		return
	}

	p.Gold -= def.GoldCost
	p.Abilities = append(p.Abilities, int(abilityID))

	// Persist to DB.
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := w.db.LearnAbility(ctx, p.charDBID, int(abilityID)); err != nil {
		w.log.Warn("failed to persist ability", "char", p.CharName, "ability", abilityID, "err", err)
	}

	// Send confirmation.
	wr := proto.NewWriter(2)
	wr.WriteU8(abilityID)
	w.sendTo(p, proto.MsgSAbilityLearned, wr.Bytes())
	w.sendTo(p, proto.MsgSAbilityList, p.BuildAbilityList())
	w.sendTo(p, proto.MsgSStats, p.BuildStats())
}

// sendAbilityShop sends the available abilities list to a player.
func (w *World) sendAbilityShop(p *Player) {
	learned := make(map[int]bool)
	for _, id := range p.Abilities {
		learned[id] = true
	}
	wr := proto.NewWriter(4 + len(abilityDefs)*16)
	wr.WriteU8(uint8(len(abilityDefs)))
	for _, def := range abilityDefs {
		wr.WriteU8(uint8(def.ID))
		wr.WriteStr(def.Name)
		wr.WriteU16(uint16(def.GoldCost))
		wr.WriteU8(uint8(def.ReqLevel))
		wr.WriteU8(uint8(def.ReqSkill))
		wr.WriteU8(uint8(def.ReqSkillV))
		if learned[def.ID] {
			wr.WriteU8(1)
		} else {
			wr.WriteU8(0)
		}
	}
	w.sendTo(p, proto.MsgSAbilityShop, wr.Bytes())
}

func (w *World) sendAbilityFail(p *Player, reason string) {
	wr := proto.NewWriter(4 + len(reason))
	wr.WriteStr(reason)
	w.sendTo(p, proto.MsgSAbilityFail, wr.Bytes())
}

// ---------------------------------------------------------------------------
// Hotbar
// ---------------------------------------------------------------------------

func (w *World) handleSaveHotbar(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	count, err := r.ReadU8()
	if err != nil {
		return
	}
	if int(count) > 10 {
		count = 10
	}

	var slots []db.HotbarSlot
	for i := 0; i < int(count); i++ {
		slot, err := r.ReadU8()
		if err != nil {
			break
		}
		itype, err := r.ReadU8()
		if err != nil {
			break
		}
		id, err := r.ReadU8()
		if err != nil {
			break
		}
		slots = append(slots, db.HotbarSlot{
			Slot:     int(slot),
			ItemType: int(itype),
			ItemID:   int(id),
		})
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := w.db.SaveHotbar(ctx, p.charDBID, slots); err != nil {
		w.log.Warn("failed to save hotbar", "char", p.CharName, "err", err)
	}

	// Echo hotbar back so client stays in sync.
	wr := proto.NewWriter(4 + len(slots)*3)
	wr.WriteU8(uint8(len(slots)))
	for _, s := range slots {
		wr.WriteU8(uint8(s.Slot))
		wr.WriteU8(uint8(s.ItemType))
		wr.WriteU8(uint8(s.ItemID))
	}
	w.sendTo(p, proto.MsgSHotbar, wr.Bytes())
}

// ---------------------------------------------------------------------------
// Penance (faction reputation)
// ---------------------------------------------------------------------------

// penanceCostPerPoint is the gold cost per 1 point of negative reputation to clear.
const penanceCostPerPoint = 10

func (w *World) handlePenance(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	faction, err := r.ReadStr()
	if err != nil || faction == "" {
		return
	}
	faction = strings.TrimSpace(faction)

	rep, ok := p.Reputation[faction]
	if !ok || rep >= 0 {
		w.sendTo(p, proto.MsgSRepRefused, buildServerMsg(faction))
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You have no debt with the "+faction+"."))
		return
	}

	// Cost to restore to 0.
	debt := -rep
	cost := debt * penanceCostPerPoint
	if p.Gold < cost {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(
			fmt.Sprintf("Penance with %s costs %d gold (you have %d).", faction, cost, p.Gold)))
		return
	}

	p.Gold -= cost
	p.Reputation[faction] = 0

	w.sendTo(p, proto.MsgSStats, p.BuildStats())
	w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(
		fmt.Sprintf("Your sins with %s have been forgiven.", faction)))
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

func randN(n int) int {
	if n <= 0 {
		return 0
	}
	return int(randSource.Int63n(int64(n)))
}

func imax_f(a, b float64) float64 {
	if a > b {
		return a
	}
	return b
}

func fmin(a, b float64) float64 {
	if a < b {
		return a
	}
	return b
}

func getObjMinHit(w *World, idx int) int {
	if idx == 0 {
		return 1
	}
	obj := w.gameData.GetObject(idx)
	if obj == nil {
		return 1
	}
	return obj.MinHit
}

func getObjMaxHit(w *World, idx int) int {
	if idx == 0 {
		return 5
	}
	obj := w.gameData.GetObject(idx)
	if obj == nil {
		return 5
	}
	return obj.MaxHit
}

func getObjDef(w *World, idx int) int {
	if idx == 0 {
		return 0
	}
	obj := w.gameData.GetObject(idx)
	if obj == nil {
		return 0
	}
	return obj.Defense
}
