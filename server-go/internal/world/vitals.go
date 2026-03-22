package world

import (
	"math"
	"time"

	"github.com/blueavlo-hash/eraonline-server/internal/proto"
)

// Vitals constants (mirrored from game_server.gd)
const (
	HungerDecayPerTick    = 0.01  // hunger lost per world tick
	ThirstDecayPerTick    = 0.012 // thirst lost per world tick (slightly faster)
	StarvationDmgInterval = 240   // ticks between starvation damage (60s at 4 tps)
	StarvationDmgAmt      = 1     // HP lost per starvation interval

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
	p.Hunger -= HungerDecayPerTick
	p.Thirst -= ThirstDecayPerTick
	if p.Hunger < 0 {
		p.Hunger = 0
	}
	if p.Thirst < 0 {
		p.Thirst = 0
	}

	// Send vitals update.
	wr := proto.NewWriter(2)
	wr.WriteU8(uint8(math.Round(p.Hunger)))
	wr.WriteU8(uint8(math.Round(p.Thirst)))
	w.sendTo(p, proto.MsgSVitals, wr.Bytes())

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
func (w *World) tickPlayerRegen(p *Player) {
	// Vitals-based regen modifier.
	regenHPBonus := 0
	regenMPBonus := 0
	worst := p.Hunger
	if p.Thirst < worst {
		worst = p.Thirst
	}
	switch {
	case p.Hunger >= 75 && p.Thirst >= 75:
		regenHPBonus = 2
		regenMPBonus = 1
	case p.Hunger >= 50 && p.Thirst >= 50:
		regenHPBonus = 1
	case worst < 25:
		// No regen when critically hungry/thirsty.
		regenHPBonus = -999
		regenMPBonus = -999
	case worst < 50:
		regenHPBonus -= 2
	}

	changed := false
	if p.HP < p.MaxHP {
		base := imax(1, p.MaxHP/20)
		gain := imax(0, base+regenHPBonus)
		if gain > 0 {
			p.HP = imin(p.HP+gain, p.MaxHP)
			changed = true
		}
	}
	if p.MP < p.MaxMP {
		base := imax(1, p.MaxMP/20)
		gain := imax(0, base+regenMPBonus)
		if gain > 0 {
			p.MP = imin(p.MP+gain, p.MaxMP)
			changed = true
		}
	}
	if p.Stamina < p.MaxStamina {
		base := imax(1, p.MaxStamina/20)
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
