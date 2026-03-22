package world

import (
	"math"
	"math/rand"
)

// Class IDs
const (
	ClassWarrior  = 1
	ClassMage     = 2
	ClassRogue    = 3
	ClassArcher   = 4
	ClassBard     = 5
	ClassDruid    = 6
	ClassPaladin  = 7
	ClassAssassin = 8
)

// statBlock holds derived base stats for a class at level 1.
type statBlock struct {
	hp, mp, sta, str_, agi, int_, con int
}

var classStats = map[int]statBlock{
	ClassWarrior:  {120, 30, 80, 12, 8, 5, 10},
	ClassMage:     {70, 120, 60, 5, 7, 14, 5},
	ClassRogue:    {90, 40, 90, 10, 12, 6, 7},
	ClassArcher:   {95, 40, 85, 9, 11, 7, 8},
	ClassBard:     {85, 80, 70, 7, 9, 11, 6},
	ClassDruid:    {95, 90, 75, 8, 8, 12, 8},
	ClassPaladin:  {110, 60, 75, 11, 7, 8, 11},
	ClassAssassin: {85, 50, 85, 10, 13, 6, 7},
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

// xpForKill returns XP awarded for killing an NPC.
func xpForKill(npcLevel, npcType int) int {
	base := npcLevel * 15
	switch npcType {
	case 2: // boss
		base *= 5
	case 3: // elite
		base *= 2
	}
	return base
}

// xpToNextLevel returns XP required to reach the next level.
// Formula: 1500 * 1.35^(level-1)
func xpToNextLevel(level int) int {
	return int(1500.0 * math.Pow(1.35, float64(level-1)))
}

// recalcCombatStats recomputes a player's derived combat stats.
// Returns (maxHP, maxMP, maxSTA, minDmg, maxDmg, defense, agi, str_).
func recalcCombatStats(classID, level, weaponMinHit, weaponMaxHit, weaponDef, shieldDef, armorDef int) (maxHP, maxMP, maxSTA, minDmg, maxDmg, defense, agi, str_ int) {
	s := baseStats(classID)
	maxHP = s.hp + (level-1)*s.con*2
	maxMP = s.mp + (level-1)*s.int_*2
	maxSTA = s.sta + (level-1)*2
	minDmg = s.str_ + weaponMinHit + (level-1)/3
	maxDmg = s.str_ + weaponMaxHit + (level-1)/3
	defense = weaponDef + shieldDef + armorDef + (level-1)/4
	agi = s.agi
	str_ = s.str_
	return
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
