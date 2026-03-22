package world

import (
	"time"

	"github.com/blueavlo-hash/eraonline-server/internal/gamedata"
	"github.com/blueavlo-hash/eraonline-server/internal/proto"
)

// Spell target types (must match spell data in spells.json).
const (
	SpellTargetSelf       = 0
	SpellTargetSingleEnemy = 1
	SpellTargetSingleAlly  = 2
	SpellTargetGroundAOE   = 3
	SpellTargetSelfAOE     = 4
)

// SpellCooldown tracks per-spell cooldown expiry.
type SpellCooldown map[int]time.Time // spell_id → expiry

func (w *World) handleCastSpell(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	spellID, err := r.ReadU8()
	if err != nil {
		return
	}
	targetID, err := r.ReadI32()
	if err != nil {
		return
	}
	tx, _ := r.ReadI16()
	ty, _ := r.ReadI16()

	// Verify player has learned this spell.
	hasSpell := false
	for _, id := range p.Spells {
		if id == int(spellID) {
			hasSpell = true
			break
		}
	}
	if !hasSpell {
		return
	}

	// Look up spell data.
	spell := w.gameData.GetSpell(int(spellID))
	if spell == nil {
		return
	}

	// Cooldown check.
	if cd, ok := p.spellCooldowns[int(spellID)]; ok && time.Now().Before(cd) {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("That spell is on cooldown."))
		return
	}

	// Mana check.
	if p.MP < spell.MPCost {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("Not enough mana."))
		return
	}
	p.MP -= spell.MPCost

	// Set cooldown.
	if p.spellCooldowns == nil {
		p.spellCooldowns = make(SpellCooldown)
	}
	p.spellCooldowns[int(spellID)] = time.Now().Add(time.Duration(spell.Cooldown) * time.Millisecond)

	// Broadcast cast animation.
	{
		wr := proto.NewWriter(16)
		wr.WriteI32(p.InstanceID)
		wr.WriteU8(spellID)
		wr.WriteI32(targetID)
		wr.WriteI16(tx)
		wr.WriteI16(ty)
		w.broadcastMapAndSelf(p.MapID, proto.MsgSSpellCast, wr.Bytes())
	}

	// Apply effect.
	switch spell.SpellType {
	case SpellTargetSelf:
		w.applySpellToPlayer(p, p, int(spellID), spell)
	case SpellTargetSingleEnemy, SpellTargetSingleAlly:
		w.spellSingleTarget(p, targetID, int(spellID), spell)
	case SpellTargetGroundAOE:
		w.spellGroundAOE(p, int(spellID), spell, int(tx), int(ty))
	case SpellTargetSelfAOE:
		w.spellSelfAOE(p, int(spellID), spell)
	}

	// Award Magery skill XP.
	w.awardSkillXP(p, SkillMagery, 1)

	// Update stats.
	wr := proto.NewWriter(6)
	wr.WriteI16(int16(p.HP))
	wr.WriteI16(int16(p.MP))
	wr.WriteI16(int16(p.Stamina))
	w.sendTo(p, proto.MsgSHealth, wr.Bytes())
}

func (w *World) applySpellToPlayer(caster, target *Player, spellID int, spell *gamedata.SpellData) {
	dmg := spell.MinEffect + randN(imax(1, spell.MaxEffect-spell.MinEffect+1))
	heal := 0
	if spell.Effect < 0 { // negative effect = healing
		heal = -dmg
		dmg = 0
	}

	if dmg > 0 {
		target.HP = imax(0, target.HP-dmg)
		if target.HP == 0 {
			w.playerDied(target, caster.CharName)
			return
		}
	}
	if heal > 0 {
		target.HP = imin(target.HP+heal, target.MaxHP)
	}

	// Send spell hit.
	{
		wr := proto.NewWriter(12)
		wr.WriteI32(target.InstanceID)
		wr.WriteU8(uint8(spellID))
		wr.WriteI16(int16(dmg))
		wr.WriteI16(int16(heal))
		wr.WriteI16(0) // mana drain
		w.broadcastMapAndSelf(target.MapID, proto.MsgSSpellHit, wr.Bytes())
	}

	// Update target's health.
	{
		wr := proto.NewWriter(6)
		wr.WriteI16(int16(target.HP))
		wr.WriteI16(int16(target.MP))
		wr.WriteI16(int16(target.Stamina))
		w.sendTo(target, proto.MsgSHealth, wr.Bytes())
	}
}

func (w *World) spellSingleTarget(caster *Player, targetID int32, spellID int, spell *gamedata.SpellData) {
	// NPC target.
	if npc, ok := w.npcs[targetID]; ok {
		if npc.MapID != caster.MapID || npc.Dead {
			return
		}
		dmg := spell.MinEffect + randN(imax(1, spell.MaxEffect-spell.MinEffect+1))
		if dmg > 0 {
			npc.HP = imax(0, npc.HP-dmg)
			{
				wr := proto.NewWriter(12)
				wr.WriteI32(targetID)
				wr.WriteU8(uint8(spellID))
				wr.WriteI16(int16(dmg))
				wr.WriteI16(0) // heal
				wr.WriteI16(0) // mana drain
				w.broadcastMap(caster.MapID, proto.MsgSSpellHit, wr.Bytes(), -1)
			}
			if npc.HP <= 0 {
				w.npcDied(caster, npc)
			}
		}
		return
	}

	// Player target.
	if target, ok := w.players[targetID]; ok {
		w.applySpellToPlayer(caster, target, spellID, spell)
	}
}

func (w *World) spellGroundAOE(caster *Player, spellID int, spell *gamedata.SpellData, tx, ty int) {
	aoeRadius := spell.Range
	if aoeRadius <= 0 {
		aoeRadius = 3
	}

	var hitTargets []int32

	// Hit all NPCs and players in radius.
	for _, npc := range w.npcs {
		if npc.MapID != caster.MapID || npc.Dead {
			continue
		}
		dx := npc.X - tx
		dy := npc.Y - ty
		if dx*dx+dy*dy <= aoeRadius*aoeRadius {
			dmg := spell.MinEffect + randN(imax(1, spell.MaxEffect-spell.MinEffect+1))
			if dmg > 0 {
				npc.HP = imax(0, npc.HP-dmg)
				hitTargets = append(hitTargets, npc.InstanceID)
				if npc.HP <= 0 {
					w.npcDied(caster, npc)
				}
			}
		}
	}

	if len(hitTargets) > 0 {
		wr := proto.NewWriter(4 + len(hitTargets)*4)
		wr.WriteU8(uint8(spellID))
		wr.WriteU8(uint8(len(hitTargets)))
		for _, id := range hitTargets {
			wr.WriteI32(id)
		}
		w.broadcastMap(caster.MapID, proto.MsgSSpellChain, wr.Bytes(), -1)
	}
}

func (w *World) spellSelfAOE(caster *Player, spellID int, spell *gamedata.SpellData) {
	w.spellGroundAOE(caster, spellID, spell, caster.X, caster.Y)
}

func (w *World) handleBuySpell(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	_, _ = r.ReadI32() // npc_id
	spellID, err := r.ReadU8()
	if err != nil {
		return
	}

	// Check if already learned.
	for _, id := range p.Spells {
		if id == int(spellID) {
			w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You already know that spell."))
			return
		}
	}

	spell := w.gameData.GetSpell(int(spellID))
	if spell == nil {
		return
	}

	// Spell cost = spell index * 100 gold (fallback formula).
	cost := int(spellID) * 100
	if p.Gold < cost {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("Not enough gold."))
		return
	}

	p.Gold -= cost
	p.Spells = append(p.Spells, int(spellID))

	wr := proto.NewWriter(2)
	wr.WriteU8(spellID)
	w.sendTo(p, proto.MsgSSpellUnlock, wr.Bytes())
	w.sendTo(p, proto.MsgSSpellbook, p.BuildSpellbook())
	w.sendTo(p, proto.MsgSStats, p.BuildStats())
}
