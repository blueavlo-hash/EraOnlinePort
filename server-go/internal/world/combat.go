package world

import (
	"math"
	"math/rand"
)

// Class IDs — 0-indexed to match the client (Warrior=0, Mage=1, Rogue=2, Archer=3).
const (
	ClassWarrior  = 0
	ClassMage     = 1
	ClassRogue    = 2
	ClassArcher   = 3
	ClassBard     = 4
	ClassDruid    = 5
	ClassPaladin  = 6
	ClassAssassin = 7
)

// statBlock holds derived base stats for a class at level 1.
type statBlock struct {
	hp, mp, sta, str_, agi, int_, con int
}

var classStats = map[int]statBlock{
	// Original EO3 base stats (level 1).
	ClassWarrior:  {150, 30, 150, 18, 10, 8, 10},
	ClassMage:     {80, 120, 100, 8, 10, 18, 5},
	ClassRogue:    {100, 60, 120, 14, 18, 10, 7},
	ClassArcher:   {100, 80, 110, 12, 16, 12, 8},
	ClassBard:     {85, 80, 70, 7, 9, 11, 6},
	ClassDruid:    {95, 90, 75, 8, 8, 12, 8},
	ClassPaladin:  {110, 60, 75, 11, 7, 8, 11},
	ClassAssassin: {85, 50, 85, 10, 13, 6, 7},
}

// levelGain holds the fixed stat gains per level-up per class.
type levelGain struct {
	hp, mp, sta int
	// primary stat gain: str for Warrior, int_ for Mage, agi for Rogue/Archer.
	primaryStat int // which stat: 1=str, 2=agi, 3=int_
}

var classLevelGains = map[int]levelGain{
	ClassWarrior:  {15, 2, 12, 1},  // +1 STR, +2 MP/level (enough for skills at high level)
	ClassMage:     {5, 8, 7, 3},    // +1 INT
	ClassRogue:    {8, 4, 10, 2},   // +1 AGI
	ClassArcher:   {8, 6, 8, 2},    // +1 AGI
	ClassBard:     {6, 5, 7, 3},
	ClassDruid:    {7, 6, 7, 3},
	ClassPaladin:  {10, 3, 9, 1},
	ClassAssassin: {7, 4, 9, 2},
}

// baseStats returns the stat block for a class (defaults to Warrior).
func baseStats(classID int) statBlock {
	if s, ok := classStats[classID]; ok {
		return s
	}
	return classStats[ClassWarrior]
}

// resolveAttack resolves one melee attack.
// Returns (damage dealt, evaded).
// Evade: 3% + 0.3% per attacker agi, capped at 25%.
// DEF absorption: (def*0.6)/(def*0.6+30).
// Level scaling: ±4% per level difference (capped at ±20%).
func resolveAttack(atkMinDmg, atkMaxDmg, atkAGI, atkLevel, defDef, defLevel int) (damage int, evaded bool) {
	evadeChance := 0.03 + float64(atkAGI)*0.003
	if evadeChance > 0.25 {
		evadeChance = 0.25
	}
	if rand.Float64() < evadeChance {
		return 0, true
	}

	raw := atkMinDmg + rand.Intn(imax(1, atkMaxDmg-atkMinDmg+1))

	// DEF absorption
	defFloat := float64(defDef) * 0.6
	absorbed := defFloat / (defFloat + 30.0)
	rawAfterDef := float64(raw) * (1.0 - absorbed)

	// Level scaling: ±4% per level difference, capped at ±20%
	levelDiff := atkLevel - defLevel
	if levelDiff > 5 {
		levelDiff = 5
	} else if levelDiff < -5 {
		levelDiff = -5
	}
	scale := 1.0 + float64(levelDiff)*0.04
	dmg := int(math.Round(rawAfterDef * scale))
	if dmg < 1 {
		dmg = 1
	}
	return dmg, false
}

// xpToNextLevel returns XP required to reach the next level.
// Formula: 1500 * 1.25^(level-1) — gentler curve for a level-50 cap.
func xpToNextLevel(level int) int {
	return int(1500.0 * math.Pow(1.25, float64(level-1)))
}

// recalcCombatStats recomputes a player's derived combat stats using fixed
// per-level gains matching the original EO3 VB6 server.
// Returns (maxHP, maxMP, maxSTA, minDmg, maxDmg, defense, agi, str_).
func recalcCombatStats(classID, level, weaponMinHit, weaponMaxHit, weaponDef, shieldDef, armorDef int) (maxHP, maxMP, maxSTA, minDmg, maxDmg, defense, agi, str_ int) {
	s := baseStats(classID)
	gains, ok := classLevelGains[classID]
	if !ok {
		gains = classLevelGains[ClassWarrior] // default fallback
	}
	if level < 1 {
		level = 1
	}
	levelsGained := level - 1
	maxHP = s.hp + levelsGained*gains.hp
	maxMP = s.mp + levelsGained*gains.mp
	maxSTA = s.sta + levelsGained*gains.sta

	// Primary stat accumulates +1 per level.
	str_  = s.str_
	agi   = s.agi
	int_  := s.int_
	switch gains.primaryStat {
	case 1:
		str_ += levelsGained
	case 2:
		agi += levelsGained
	case 3:
		int_ += levelsGained
	}

	minDmg = str_ + weaponMinHit + levelsGained/3
	maxDmg = str_ + weaponMaxHit + levelsGained/3
	defense = weaponDef + shieldDef + armorDef + levelsGained/4
	_ = int_ // available for future spell-damage scaling
	return
}

// ---------------------------------------------------------------------------
// Status effects
// ---------------------------------------------------------------------------

// Status effect IDs (match MsgSStatusApplied / MsgSStatusRemoved).
const (
	FXBleed  = 1 // DoT: 3 ticks over 6s
	FXStun   = 2 // next swing blocked
	FXRoot   = 3 // movement blocked for duration
	FXMDrain = 4 // mana drain (instant, brief icon)
	FXDrunk  = 5 // movement randomisation + chat garble
)

const FleeBaseChance = 0.35

// StatusEffect is an active effect on a player.
type StatusEffect struct {
	Type       int     // FXBleed / FXStun / FXRoot / FXMDrain
	Remaining  float64 // seconds remaining
	TickTimer  float64 // bleed: seconds until next damage tick
	DmgPerTick int     // bleed: damage per tick
}

// skillEffectMap maps skill_id (from C_ATTACK u8) to its effect string.
var skillEffectMap = map[uint8]string{
	1: "bleed",      // Rend
	2: "stun",       // Stun Strike
	3: "root",       // Cripple
	4: "mana_drain", // Mana Sap
	5: "execute",    // Execute
	6: "triple",     // Triple Strike
	7: "five_hit",   // Flurry
	8: "cleave",     // Cleave
}

// resolveSkillEffect applies a named skill modifier on top of an attack.
// Returns (effectID, effectDurSec, bonusDmg, manaDrain).
func resolveSkillEffect(effect string, dmg int, attacker, target *Player) (effectID int, effectDur float64, bonusDmg int, manaDrain int) {
	switch effect {
	case "bleed":
		return FXBleed, 6.0, 0, 0
	case "stun":
		return FXStun, 0.0, 0, 0
	case "root":
		return FXRoot, 2.0, 0, 0
	case "mana_drain":
		drain := imin(attacker.MaxMP/5, target.MP)
		if drain > 0 {
			return FXMDrain, 1.5, 0, drain
		}
		return 0, 0, 0, 0
	case "execute":
		if target.MaxHP > 0 && float64(target.HP)/float64(target.MaxHP) < 0.30 {
			return 0, 0, dmg, 0 // double damage below 30% HP
		}
	case "triple":
		return 0, 0, dmg * 2, 0 // total ×3 via bonus
	case "five_hit":
		return 0, 0, dmg * 4, 0 // total ×5 via bonus
	case "cleave":
		return FXRoot, 0.5, 0, 0 // brief stagger
	}
	return 0, 0, 0, 0
}

// applyStatusEffect adds or refreshes a status effect on a player.
func applyStatusEffect(p *Player, effectID int, duration float64, dmgPerTick int) {
	for _, fx := range p.StatusEffects {
		if fx.Type == effectID {
			if duration > fx.Remaining {
				fx.Remaining = duration
			}
			if effectID == FXBleed && dmgPerTick > 0 {
				fx.DmgPerTick = dmgPerTick
			}
			return
		}
	}
	fx := &StatusEffect{Type: effectID, Remaining: duration}
	if effectID == FXBleed {
		fx.TickTimer = 2.0
		fx.DmgPerTick = dmgPerTick
	}
	p.StatusEffects = append(p.StatusEffects, fx)
}

// hasEffect returns whether a player has a specific effect active.
func hasEffect(p *Player, effectID int) bool {
	for _, fx := range p.StatusEffects {
		if fx.Type == effectID && fx.Remaining > 0 {
			return true
		}
	}
	return false
}

// clearEffect removes one effect type from a player.
func clearEffect(p *Player, effectID int) {
	out := p.StatusEffects[:0]
	for _, fx := range p.StatusEffects {
		if fx.Type != effectID {
			out = append(out, fx)
		}
	}
	p.StatusEffects = out
}

// fleeChance returns the probability of a flee attempt succeeding.
// 35% base + 0.5% per AGI - 2% per level diff (pursuer higher), clamped 10-80%.
func fleeChance(fleeingLevel, fleeingAGI, pursuerLevel int) float64 {
	base := FleeBaseChance + float64(fleeingAGI)*0.005
	base -= float64(pursuerLevel-fleeingLevel) * 0.02
	if base < 0.10 {
		return 0.10
	}
	if base > 0.80 {
		return 0.80
	}
	return base
}

func imax(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func imin(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func iabs(x int) int {
	if x < 0 {
		return -x
	}
	return x
}
