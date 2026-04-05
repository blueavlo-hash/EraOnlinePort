package world

import (
	"context"
	"fmt"
	"math/rand"
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
		// Cardinal map-edge exits — seamless edge-to-edge transitions.
		// Trigger at the very edge (1 or 100), spawn 1 tile from opposite edge.
		const (
			exitN, exitS, exitW, exitE     = 1, 100, 1, 100
			spawnN, spawnS, spawnW, spawnE = 99, 2, 99, 2
		)
		// Cardinal exits — only warp if the destination tile is walkable.
		if ny <= exitN && m.NorthExit > 1 && w.isTileWalkable(m.NorthExit, nx, spawnN) {
			w.warpPlayer(p, m.NorthExit, nx, spawnN)
			return
		} else if ny >= exitS && m.SouthExit > 1 && w.isTileWalkable(m.SouthExit, nx, spawnS) {
			w.warpPlayer(p, m.SouthExit, nx, spawnS)
			return
		} else if nx <= exitW && m.WestExit > 1 && w.isTileWalkable(m.WestExit, spawnW, ny) {
			w.warpPlayer(p, m.WestExit, spawnW, ny)
			return
		} else if nx >= exitE && m.EastExit > 1 && w.isTileWalkable(m.EastExit, spawnE, ny) {
			w.warpPlayer(p, m.EastExit, spawnE, ny)
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
	if destMap == nil || !destMap.HasGroundTiles() || !destMap.HasAnyExit() {
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

	// Send quest indicators for NPCs on the new map.
	w.sendQuestIndicators(p)
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
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You are not ready to attack yet."))
		return
	}

	minDmg, maxDmg := 1, 5 // default fist
	if p.WeaponSlot > 0 {
		obj := w.gameData.GetObject(p.WeaponSlot)
		if obj != nil {
			minDmg = obj.MinHit
			maxDmg = obj.MaxHit

			// Gap 21: Archer class requires arrows (item type = ammo/arrow obj_type 87).
			// WeaponAnim == 3 signals a ranged/bow weapon.
			if obj.WeaponAnim == 3 {
				if !w.consumeArrow(p) {
					w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You have no arrows!"))
					return
				}
			}
		}
	}

	// NPC target.
	if npc, ok := w.npcs[targetID]; ok {
		if npc.MapID != p.MapID || npc.Dead {
			return
		}
		dx := npc.X - p.X
		dy := npc.Y - p.Y
		if iabs(dx) > 2 || iabs(dy) > 2 {
			w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You are too far away!"))
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
		if iabs(dx) > 2 || iabs(dy) > 2 {
			w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You are too far away!"))
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
				// Bounty: killer collects the victim's bounty, victim gets a new bounty.
				if target.Bounty > 0 {
					p.Gold += target.Bounty
					w.sendTo(p, proto.MsgSServerMsg,
						buildServerMsg(fmt.Sprintf("You collected a bounty of %d gold!", target.Bounty)))
					w.sendTo(p, proto.MsgSStats, p.BuildStats())
					w.checkAchievements(p, "bounties_collected", 1)
					target.Bounty = 0
				}
				// Add bounty to killer and broadcast.
				p.Bounty += 200
				{
					wr := proto.NewWriter(16 + len(p.CharName))
					wr.WriteI32(p.InstanceID)
					wr.WriteStr(p.CharName)
					wr.WriteI32(int32(p.Bounty))
					w.broadcastMap(p.MapID, proto.MsgSBountyUpdate, wr.Bytes(), -1)
				}
				w.broadcastMap(p.MapID, proto.MsgSServerMsg,
					buildServerMsg(fmt.Sprintf("WARNING: %s is now wanted! Bounty: %d gold.", p.CharName, p.Bounty)), -1)

				w.playerDied(target, p.CharName)
				// Gap 19: track player kill for killer.
				w.checkAchievements(p, "player_kills", 1)
				// Gap 19: track death for victim.
				w.checkAchievements(target, "deaths", 1)
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
	case 1: // sword/1h — Swordsmanship (ID 16 in original order)
		w.awardSkillXP(p, SkillSwordsmanship, 1)
	case 2: // axe — also Swordsmanship (no separate axe skill in original)
		w.awardSkillXP(p, SkillSwordsmanship, 1)
	case 3: // bow — Archery (ID 28)
		w.awardSkillXP(p, SkillArchery, 1)
	}
}

// rollLootRarity returns a rarity tier: 0=common, 1=uncommon, 2=rare, 3=legendary.
func rollLootRarity() int {
	r := rand.Float64()
	switch {
	case r < 0.01:
		return 3 // 1% legendary
	case r < 0.08:
		return 2 // 7% rare
	case r < 0.25:
		return 1 // 17% uncommon
	default:
		return 0 // 75% common
	}
}

// rarityLabel returns the display suffix for a rarity tier.
func rarityLabel(rarity int) string {
	switch rarity {
	case 1:
		return " [Uncommon]"
	case 2:
		return " [Rare]"
	case 3:
		return " [LEGENDARY]"
	default:
		return ""
	}
}

func (w *World) npcDied(killer *Player, npc *NPC) {
	w.log.Info("NPC died", "npc", npc.Def.Name, "killer", killer.CharName)
	npc.Dead = true
	npc.RespawnTicks = 120 // ~30 seconds at 4 ticks/sec

	// Boss: extra XP, server-wide broadcast, clear boss instance tracker.
	if npc.IsBoss {
		w.clearBossInstance(npc.InstanceID)
		npc.RespawnTicks = -1 // handled by boss timer, not normal respawn
		wr := proto.NewWriter(64)
		wr.WriteStr("The " + npc.Def.Name + " has been defeated by " + killer.CharName + "! Legendary treasure awaits!")
		w.broadcastAll(proto.MsgSServerMsg, wr.Bytes())
	}

	// World event: notify the event system.
	if npc.IsEventNPC {
		w.onEventNPCDied(npc.InstanceID)
	}

	w.broadcastMap(npc.MapID, proto.MsgSRemoveChar, buildRemoveChar(npc.InstanceID), -1)

	// Drop items with rarity roll.
	if npc.Def.DeathObj > 0 {
		w.spawnGroundItemWithRarity(npc.MapID, npc.X, npc.Y, npc.Def.DeathObj, 1)
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

	// Quest kill progress and kill achievements (onKillNPC handles both).
	w.onKillNPC(killer, npc.Def.Name)
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
		Timeout:  480, // Gap 18: 120 seconds at 4 ticks/sec (was 600)
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

// spawnGroundItemWithRarity spawns a ground item and, if rarity > common, broadcasts
// a rare drop notification to players on the map.
func (w *World) spawnGroundItemWithRarity(mapID, x, y, objIndex, amount int) {
	w.spawnGroundItem(mapID, x, y, objIndex, amount)
	rarity := rollLootRarity()
	if rarity == 0 {
		return
	}
	obj := w.gameData.GetObject(objIndex)
	name := "an item"
	if obj != nil {
		name = obj.Name
	}
	wr := proto.NewWriter(32)
	wr.WriteStr(name + rarityLabel(rarity))
	wr.WriteU8(uint8(rarity))
	wr.WriteI16(int16(x))
	wr.WriteI16(int16(y))
	w.broadcastMap(mapID, proto.MsgSRareDropNotify, wr.Bytes(), -1)
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
		buildChat(p.InstanceID, proto.ChatNormal, msg, p.CharName))
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

// foodRestore defines hunger and thirst restoration per item index.
// Matches original EO3 FOOD_RESTORE table.
var foodRestore = map[int][2]int{ // [hunger, thirst]
	6:   {15, 0},  // Apple
	19:  {0, 25},  // Snake Wine
	20:  {0, 20},  // Cyclop Blood Ale
	21:  {5, 30},  // Grape Juice
	22:  {0, 35},  // Water Flask
	29:  {40, 15}, // Bowl of Stew
	95:  {25, 0},  // Bread
	99:  {20, 0},  // Carrots
	117: {0, 0},   // Meat (raw — no nutrition, poisons you)
	135: {0, 0},   // 1kg fish (raw — no nutrition, poisons you)
	156: {30, 0},  // Roasted meat
	220: {20, 10}, // Rations of Shimmer
	307: {30, 5},  // Roasted fish
	308: {0, 0},   // 2kg fish (raw — no nutrition, poisons you)
	309: {0, 0},   // 3kg fish (raw — no nutrition, poisons you)
	310: {0, 0},   // 4kg fish (raw — no nutrition, poisons you)
	311: {0, 0},   // 5kg fish (raw — no nutrition, poisons you)
	312: {0, 0},   // 6kg fish (raw — no nutrition, poisons you)
	313: {0, 0},   // 7kg fish (raw — no nutrition, poisons you)
	314: {0, 0},   // 8kg fish (raw — no nutrition, poisons you)
	315: {0, 0},   // 9kg fish (raw — no nutrition, poisons you)
	316: {0, 0},   // 10kg fish (raw — no nutrition, poisons you)
	317: {0, 0},   // 20kg fish (raw — no nutrition, poisons you)
}

func (w *World) handleUseItem(p *Player, payload []byte) {
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

	restore, isFood := foodRestore[inv.ObjIndex]
	if !isFood && obj.Food <= 0 {
		return // not consumable
	}

	// Restore HP from food's heal value.
	if obj.Food > 0 {
		p.HP = imin(p.HP+obj.Food, p.MaxHP)
	}

	// Restore hunger and thirst.
	hungerGain := float64(restore[0])
	thirstGain := float64(restore[1])
	if hungerGain > 0 {
		p.Hunger = fmin(p.Hunger+hungerGain, 100.0)
	}
	if thirstGain > 0 {
		p.Thirst = fmin(p.Thirst+thirstGain, 100.0)
	}

	// Consume one item.
	inv.Amount--
	if inv.Amount <= 0 {
		p.Inventory[slot] = nil
	}

	w.sendTo(p, proto.MsgSInventory, p.BuildInventory())

	// Send updated vitals.
	vrw := proto.NewWriter(2)
	vrw.WriteU8(uint8(p.Hunger))
	vrw.WriteU8(uint8(p.Thirst))
	w.sendTo(p, proto.MsgSVitals, vrw.Bytes())

	// Send updated HP/MP/STA.
	hrw := proto.NewWriter(6)
	hrw.WriteI16(int16(p.HP))
	hrw.WriteI16(int16(p.MP))
	hrw.WriteI16(int16(p.Stamina))
	w.sendTo(p, proto.MsgSHealth, hrw.Bytes())

	// Raw food (obj_type 39) poisons the player.
	if obj.ObjType == 39 {
		w.applyPoison(p)
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You feel sick from eating raw food!"))
	}
}

// ---------------------------------------------------------------------------
// Enchanting
// ---------------------------------------------------------------------------

// enchantMaterialObjType is the obj_type value for enchanting reagents.
const enchantMaterialObjType = 9

// enchantLevel defines one tier of the enchanting system (Gap 15).
type enchantLevelDef struct {
	Materials   int     // materials consumed per attempt
	SuccessRate float64 // probability of success (0.0–1.0)
	BreakChance float64 // probability the item is destroyed on failure
}

// enchantLevels defines the 4 enchant tiers (index 0 = upgrading to +1, etc.).
// Gap 15: Level 1: 2 mats 90% / 0% break; Level 2: 5 mats 70% / 5%; Level 3: 10 mats 45% / 15%; Level 4: 20 mats 20% / 35%.
var enchantLevels = [4]enchantLevelDef{
	{Materials: 2, SuccessRate: 0.90, BreakChance: 0.00}, // +1
	{Materials: 5, SuccessRate: 0.70, BreakChance: 0.05}, // +2
	{Materials: 10, SuccessRate: 0.45, BreakChance: 0.15}, // +3
	{Materials: 20, SuccessRate: 0.20, BreakChance: 0.35}, // +4
}

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
	if itemObj == nil || itemObj.ClothingType == 0 {
		w.sendEnchantResult(p, false, 0, "That item cannot be enchanted.")
		return
	}

	// Validate material.
	matObj := w.gameData.GetObject(mat.ObjIndex)
	if matObj == nil || matObj.ObjType != enchantMaterialObjType {
		w.sendEnchantResult(p, false, 0, "Invalid enchanting material.")
		return
	}

	// Cap enchant level at 4 (Gap 15: only 4 levels).
	if item.Enchant >= 4 {
		w.sendEnchantResult(p, false, item.Enchant, "This item is already at maximum enchantment (+4).")
		return
	}

	// Get the tier definition for the NEXT enchant level.
	tier := enchantLevels[item.Enchant] // item.Enchant is 0-based: enchant 0 → try for +1 = index 0

	// Check material count.
	if mat.Amount < tier.Materials {
		w.sendEnchantResult(p, false, item.Enchant,
			fmt.Sprintf("You need %d materials to attempt this enchantment (you have %d).", tier.Materials, mat.Amount))
		return
	}

	// Consume materials.
	mat.Amount -= tier.Materials
	if mat.Amount <= 0 {
		p.Inventory[matSlot] = nil
	}

	roll := randSource.Float64()
	if roll < tier.SuccessRate {
		// Success.
		item.Enchant++
		w.sendEnchantResult(p, true, item.Enchant, fmt.Sprintf("+%d enchantment applied!", item.Enchant))
		// Track achievement for reaching +3.
		if item.Enchant >= 3 {
			w.checkAchievementsNew(p, "enchant_3_achieved", 1)
		}
	} else if tier.BreakChance > 0 && (roll-tier.SuccessRate)/(1.0-tier.SuccessRate) < tier.BreakChance {
		// Item destroyed on failure.
		p.Inventory[itemSlot] = nil
		w.sendEnchantResult(p, false, 0, "Enchantment failed! The item was destroyed!")
	} else {
		// Failure, item preserved.
		w.sendEnchantResult(p, false, item.Enchant, "Enchantment failed! The materials were consumed.")
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
	{1, "Second Wind", 500, 5, 0, 0},                         // passive: +10 max HP
	{2, "Steady Aim", 1000, 10, SkillArchery, 5},              // passive: +2 max ranged damage (req Archery 5)
	{3, "Shield Bash", 1500, 15, SkillParrying, 5},            // active: stun on block (req Parrying 5)
	{4, "Battle Cry", 2000, 20, SkillSwordsmanship, 10},       // active: nearby allies +5 atk (req Swordsmanship 10)
	{5, "Swift Feet", 2500, 25, SkillStealth, 10},             // passive: move speed (req Stealth 10)
	{6, "Arcane Focus", 3000, 20, SkillMagery, 10},            // passive: -10% spell MP cost (req Magery 10)
	{7, "Iron Skin", 2000, 15, SkillParrying, 8},              // passive: +5 defense (req Parrying 8)
	{8, "Eagle Eye", 1500, 10, SkillArchery, 8},               // passive: +1 ranged range (req Archery 8)
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

// Gap 17: Penance costs a flat 500 gold and grants +75 reputation.
const (
	penanceFlatCost   = 500
	penanceRepGain    = 75
)

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

	// Gap 17: flat 500 gold cost.
	if p.Gold < penanceFlatCost {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(
			fmt.Sprintf("Penance costs %d gold (you have %d).", penanceFlatCost, p.Gold)))
		return
	}

	p.Gold -= penanceFlatCost
	// Gap 17: +75 reputation.
	p.Reputation[faction] += penanceRepGain
	if p.Reputation[faction] > 100 {
		p.Reputation[faction] = 100
	}

	w.sendTo(p, proto.MsgSStats, p.BuildStats())
	w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(
		fmt.Sprintf("Your sins with %s have been forgiven. (+%d reputation)", faction, penanceRepGain)))
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

// consumeArrow removes 1 arrow from the player's inventory.
// Arrows are identified by ObjType == arrowObjType (Gap 21).
// Returns true if an arrow was consumed, false if none available.
func (w *World) consumeArrow(p *Player) bool {
	for i, slot := range p.Inventory {
		if slot == nil || slot.ObjIndex == 0 {
			continue
		}
		obj := w.gameData.GetObject(slot.ObjIndex)
		if obj == nil {
			continue
		}
		// Arrow items: ObjType 18 (ammo/arrow type in EO3 data, e.g. Pile of Arrows).
		if obj.ObjType == 18 {
			slot.Amount--
			if slot.Amount <= 0 {
				p.Inventory[i] = nil
			}
			w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
			return true
		}
	}
	return false
}
