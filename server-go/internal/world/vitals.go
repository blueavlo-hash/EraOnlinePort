package world

import (
	"math"
	"time"

	"github.com/blueavlo-hash/eraonline-server/internal/proto"
)

// Vitals constants (mirrored from original EO3 GDScript server)
const (
	// Gap 6: original decay was 0.139 hunger / 0.093 thirst per 5-second regen
	// interval (20 ticks at 4 TPS = 250ms tick).
	HungerDecayPerTick    = 0.00695 // 0.139 / 20 ticks
	ThirstDecayPerTick    = 0.00465 // 0.093 / 20 ticks
	StarvationDmgInterval = 140     // Gap 8: 35 seconds = 140 ticks at 4 TPS (not 240)
	StarvationDmgAmt      = 1       // HP lost per starvation interval

	PoisonTickDmg    = 1
	PoisonDurationMs = 60000 // 60s
	PoisonTickMs     = 3000  // 1 damage every 3s

	WeatherCheckTicks = 1200 // every 5 minutes at 4 tps
	RainChance        = 0.15

	PoisonStatusID = 3 // status ID for poison
)

// PoisonState tracks a player's active poison.
type PoisonState struct {
	ExpiryNs  int64
	NextTickNs int64
}

// tickVitals runs hunger/thirst decay and starvation for one player.
func (w *World) tickVitals(p *Player) {
	prevH := uint8(math.Round(p.Hunger))
	prevT := uint8(math.Round(p.Thirst))

	p.Hunger -= HungerDecayPerTick
	p.Thirst -= ThirstDecayPerTick
	if p.Hunger < 0 {
		p.Hunger = 0
	}
	if p.Thirst < 0 {
		p.Thirst = 0
	}

	// Only send vitals update when the displayed integer value changes.
	newH := uint8(math.Round(p.Hunger))
	newT := uint8(math.Round(p.Thirst))
	if newH != prevH || newT != prevT {
		wr := proto.NewWriter(2)
		wr.WriteU8(newH)
		wr.WriteU8(newT)
		w.sendTo(p, proto.MsgSVitals, wr.Bytes())
	}

	// Starvation damage.
	worst := p.Hunger
	if p.Thirst < worst {
		worst = p.Thirst
	}
	if worst <= 0 {
		p.starveTick++
		if p.starveTick >= StarvationDmgInterval {
			p.starveTick = 0
			p.HP -= StarvationDmgAmt
			if p.HP < 0 {
				p.HP = 0
			}
			wr2 := proto.NewWriter(6)
			wr2.WriteI16(int16(p.HP))
			wr2.WriteI16(int16(p.MP))
			wr2.WriteI16(int16(p.Stamina))
			w.sendTo(p, proto.MsgSHealth, wr2.Bytes())
		}
	} else {
		p.starveTick = 0
	}
}

// tickPlayerRegen regenerates HP/MP/STA based on vitals.
// Regen is gated behind vitals — you must stay fed and hydrated to heal.
// Rates are intentionally slow to keep combat dangerous.
func (w *World) tickPlayerRegen(p *Player) {
	worst := p.Hunger
	if p.Thirst < worst {
		worst = p.Thirst
	}

	// No regen at all when critically hungry/thirsty or in active combat.
	if worst < 25 || p.InCombat {
		return
	}
	// No regen when low on vitals.
	if worst < 50 {
		return
	}

	// Base regen: MaxHP/100 per 5s tick — very slow, full recovery ~8 min.
	// Well fed (both >= 75) bumps it to MaxHP/60 — still slow, ~5 min.
	changed := false
	if p.HP < p.MaxHP {
		base := imax(1, p.MaxHP/100)
		if p.Hunger >= 75 && p.Thirst >= 75 {
			base = imax(1, p.MaxHP/60)
		}
		p.HP = imin(p.HP+base, p.MaxHP)
		changed = true
	}
	if p.MP < p.MaxMP {
		base := imax(1, p.MaxMP/100)
		if p.Hunger >= 75 && p.Thirst >= 75 {
			base = imax(1, p.MaxMP/60)
		}
		p.MP = imin(p.MP+base, p.MaxMP)
		changed = true
	}
	if p.Stamina < p.MaxStamina {
		base := imax(1, p.MaxStamina/80)
		p.Stamina = imin(p.Stamina+base, p.MaxStamina)
		changed = true
	}
	if changed {
		wr := proto.NewWriter(6)
		wr.WriteI16(int16(p.HP))
		wr.WriteI16(int16(p.MP))
		wr.WriteI16(int16(p.Stamina))
		w.sendTo(p, proto.MsgSHealth, wr.Bytes())
	}
}

// applyPoison starts a poison effect on a player.
func (w *World) applyPoison(p *Player) {
	now := time.Now().UnixNano()
	p.poison = &PoisonState{
		ExpiryNs:   now + PoisonDurationMs*int64(time.Millisecond),
		NextTickNs: now + PoisonTickMs*int64(time.Millisecond),
	}

	// Send S_STATUS_APPLIED.
	wr := proto.NewWriter(8)
	wr.WriteI32(p.InstanceID)
	wr.WriteU8(PoisonStatusID)
	wr.WriteU16(uint16(PoisonDurationMs))
	w.broadcastMap(p.MapID, proto.MsgSStatusApplied, wr.Bytes(), -1)

	w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You feel sick!"))
}

// tickPoison processes active poison on all players.
func (w *World) tickPoison() {
	now := time.Now().UnixNano()
	for _, p := range w.players {
		if p.poison == nil {
			continue
		}
		if now >= p.poison.ExpiryNs {
			// Poison expired.
			wr := proto.NewWriter(8)
			wr.WriteI32(p.InstanceID)
			wr.WriteU8(PoisonStatusID)
			w.broadcastMap(p.MapID, proto.MsgSStatusRemoved, wr.Bytes(), -1)
			w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You no longer feel poisoned."))
			p.poison = nil
			continue
		}
		if now >= p.poison.NextTickNs {
			p.poison.NextTickNs = now + PoisonTickMs*int64(time.Millisecond)
			p.HP = imax(0, p.HP-PoisonTickDmg)
			w.broadcastMap(p.MapID, proto.MsgSDamage, buildDamage(p.InstanceID, PoisonTickDmg, false), -1)
			wr := proto.NewWriter(6)
			wr.WriteI16(int16(p.HP))
			wr.WriteI16(int16(p.MP))
			wr.WriteI16(int16(p.Stamina))
			w.sendTo(p, proto.MsgSHealth, wr.Bytes())
			if p.HP == 0 {
				w.playerDied(p, "")
			}
		}
	}
}

// tickStatusEffects ticks all active status effects on a player for one world tick.
// Bleed fires every 2 seconds; stun/root/mdrain just track remaining time.
func (w *World) tickStatusEffects(p *Player, deltaSec float64) {
	if len(p.StatusEffects) == 0 {
		return
	}
	active := p.StatusEffects[:0]
	for _, fx := range p.StatusEffects {
		fx.Remaining -= deltaSec

		// FXDrunk: just track remaining (visual on client); no server-side tick actions.
		if fx.Type == FXDrunk && fx.Remaining <= 0 {
			// Expiry handled below — fall through.
		}
		if fx.Type == FXBleed && fx.Remaining > 0 {
			fx.TickTimer -= deltaSec
			if fx.TickTimer <= 0 {
				fx.TickTimer += 2.0
				dmg := imax(1, fx.DmgPerTick)
				p.HP = imax(0, p.HP-dmg)
				w.broadcastMap(p.MapID, proto.MsgSDamage, buildDamage(p.InstanceID, int16(dmg), false), -1)
				wr := proto.NewWriter(6)
				wr.WriteI16(int16(p.HP))
				wr.WriteI16(int16(p.MP))
				wr.WriteI16(int16(p.Stamina))
				w.sendTo(p, proto.MsgSHealth, wr.Bytes())
				if p.HP == 0 {
					killerName := ""
					if src, ok := w.players[p.BleedSourceID]; ok {
						killerName = src.CharName
					}
					w.playerDied(p, killerName)
					p.StatusEffects = nil
					return
				}
			}
		}

		if fx.Remaining > 0 {
			active = append(active, fx)
		} else {
			// Effect expired — notify clients.
			wr := proto.NewWriter(5)
			wr.WriteI32(p.InstanceID)
			wr.WriteU8(uint8(fx.Type))
			w.broadcastMap(p.MapID, proto.MsgSStatusRemoved, wr.Bytes(), -1)
		}
	}
	p.StatusEffects = active
}

// tickWeather checks for rain changes.
func (w *World) tickWeather() {
	var newRaining bool
	if w.raining {
		newRaining = false // rain stops after one interval
	} else {
		newRaining = randSource.Float64() < RainChance
	}
	if newRaining == w.raining {
		return
	}
	w.raining = newRaining
	if w.raining {
		w.broadcastAll(proto.MsgSRainOn, nil)
	} else {
		w.broadcastAll(proto.MsgSRainOff, nil)
	}
}
