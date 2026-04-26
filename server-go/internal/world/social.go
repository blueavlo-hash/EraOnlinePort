package world

import (
	"fmt"
	"math/rand"
	"strings"

	"github.com/blueavlo-hash/eraonline-server/internal/proto"
)

// ---------------------------------------------------------------------------
// WorldSign — persistent graffiti / sign post
// ---------------------------------------------------------------------------

// WorldSign is a player-placed sign on the map.
type WorldSign struct {
	MapID    int
	X, Y     int
	Text     string
	PlacedBy string
}

func signKey(mapID, x, y int) string {
	return fmt.Sprintf("%d:%d:%d", mapID, x, y)
}

// handlePlaceSign places a sign at the player's current position.
func (w *World) handlePlaceSign(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	text, err := r.ReadStr()
	if err != nil || text == "" {
		return
	}
	if len(text) > 120 {
		text = text[:120]
	}
	key := signKey(p.MapID, p.X, p.Y)
	if _, exists := w.signs[key]; exists {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("There is already a sign here."))
		return
	}
	w.signs[key] = &WorldSign{
		MapID:    p.MapID,
		X:        p.X,
		Y:        p.Y,
		Text:     text,
		PlacedBy: p.CharName,
	}
	// Tell everyone on the map there's a new sign here.
	wr := proto.NewWriter(4)
	wr.WriteI16(int16(p.X))
	wr.WriteI16(int16(p.Y))
	w.broadcastMapAndSelf(p.MapID, proto.MsgSSignAdd, wr.Bytes())
}

// handleReadSign sends sign content to the requesting player.
func (w *World) handleReadSign(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	x, err := r.ReadI16()
	if err != nil {
		return
	}
	y, err2 := r.ReadI16()
	if err2 != nil {
		return
	}
	key := signKey(p.MapID, int(x), int(y))
	sign, ok := w.signs[key]
	if !ok {
		return
	}
	wr := proto.NewWriter(8 + len(sign.Text) + len(sign.PlacedBy))
	wr.WriteStr(sign.Text)
	wr.WriteStr(sign.PlacedBy)
	w.sendTo(p, proto.MsgSSignContent, wr.Bytes())
}

// sendSignsForMap sends all sign positions on mapID to a player (on join).
func (w *World) sendSignsForMap(p *Player) {
	for _, sign := range w.signs {
		if sign.MapID != p.MapID {
			continue
		}
		wr := proto.NewWriter(4)
		wr.WriteI16(int16(sign.X))
		wr.WriteI16(int16(sign.Y))
		w.sendTo(p, proto.MsgSSignAdd, wr.Bytes())
	}
}

// ---------------------------------------------------------------------------
// Carry / throw
// ---------------------------------------------------------------------------

// handleCarryRequest attempts to pick up target player.
func (w *World) handleCarryRequest(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	targetID, err := r.ReadI32()
	if err != nil {
		return
	}
	if p.CarryingID != 0 {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You are already carrying someone."))
		return
	}
	if p.CarriedByID != 0 {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You are being carried."))
		return
	}
	target, ok := w.players[targetID]
	if !ok || target.MapID != p.MapID {
		return
	}
	if target.CarriedByID != 0 || target.CarryingID != 0 {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(fmt.Sprintf("%s is already involved in a carry.", target.CharName)))
		return
	}
	// Must be adjacent (Chebyshev ≤ 1).
	if iabs(target.X-p.X) > 1 || iabs(target.Y-p.Y) > 1 {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You are too far away to carry someone."))
		return
	}

	p.CarryingID = targetID
	target.CarriedByID = p.InstanceID
	// Snap carried player to carrier's tile.
	target.X = p.X
	target.Y = p.Y

	w.broadcastCarryState(p, target)
	w.broadcastMapAndSelf(p.MapID, proto.MsgSMoveChar, buildMoveChar(target.InstanceID, target.X, target.Y, target.Heading))
	w.sendTo(target, proto.MsgSServerMsg, buildServerMsg(fmt.Sprintf("%s picked you up! Press Drop to escape.", p.CharName)))
}

// handleThrow launches the carried player in the carrier's facing direction.
func (w *World) handleThrow(p *Player) {
	if p.CarryingID == 0 {
		return
	}
	carried, ok := w.players[p.CarryingID]
	if !ok {
		p.CarryingID = 0
		return
	}

	// Throw distance: 2–4 tiles (random, flavour of chaos).
	dist := 2 + rand.Intn(3)
	dx, dy := wanderDelta(p.Heading)
	nx, ny := carried.X+dx*dist, carried.Y+dy*dist

	// Clamp to map bounds and find first walkable tile along the trajectory.
	for i := dist; i >= 1; i-- {
		cx, cy := carried.X+dx*i, carried.Y+dy*i
		if w.isTileWalkable(p.MapID, cx, cy) {
			nx, ny = cx, cy
			break
		}
	}
	if !w.isTileWalkable(p.MapID, nx, ny) {
		nx, ny = carried.X, carried.Y // no walkable tile: drop in place
	}

	// Release.
	carried.X = nx
	carried.Y = ny
	p.CarryingID = 0
	carried.CarriedByID = 0

	w.broadcastCarryState(p, carried) // broadcast release
	w.broadcastMapAndSelf(p.MapID, proto.MsgSMoveChar, buildMoveChar(carried.InstanceID, carried.X, carried.Y, carried.Heading))

	w.sendTo(carried, proto.MsgSServerMsg, buildServerMsg("You were thrown!"))
	// 1-tick stun on landing for carried player — comedy effect.
	applyStatusEffect(carried, FXStun, 0.5, 0)
}

// handleDropCarried lets the carried player break free.
func (w *World) handleDropCarried(p *Player) {
	if p.CarriedByID == 0 {
		return
	}
	carrier, ok := w.players[p.CarriedByID]
	if ok {
		carrier.CarryingID = 0
	}
	p.CarriedByID = 0
	w.broadcastCarryStateByIDs(p.MapID, 0, 0)
	w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You broke free!"))
}

// broadcastCarryState tells all map players about the carry relationship.
func (w *World) broadcastCarryState(carrier, carried *Player) {
	wr := proto.NewWriter(8)
	wr.WriteI32(carrier.InstanceID)
	wr.WriteI32(carried.InstanceID)
	w.broadcastMapAndSelf(carrier.MapID, proto.MsgSCarryState, wr.Bytes())
}

func (w *World) broadcastCarryStateByIDs(mapID int, carrierID, carriedID int32) {
	wr := proto.NewWriter(8)
	wr.WriteI32(carrierID)
	wr.WriteI32(carriedID)
	w.broadcastMapAndSelf(mapID, proto.MsgSCarryState, wr.Bytes())
}

// releaseCarry unconditionally drops any carry relationship p is part of.
func (w *World) releaseCarry(p *Player) {
	if p.CarryingID != 0 {
		if carried, ok := w.players[p.CarryingID]; ok {
			carried.CarriedByID = 0
			w.broadcastCarryStateByIDs(p.MapID, 0, 0)
		}
		p.CarryingID = 0
	}
	if p.CarriedByID != 0 {
		if carrier, ok := w.players[p.CarriedByID]; ok {
			carrier.CarryingID = 0
			w.broadcastCarryStateByIDs(p.MapID, 0, 0)
		}
		p.CarriedByID = 0
	}
}

// ---------------------------------------------------------------------------
// Pickpocket
// ---------------------------------------------------------------------------

const (
	pickpocketSuccessBase = 0.35 // 35% base success
	pickpocketMinSteal    = 0.05 // 5% of target's gold
	pickpocketMaxSteal    = 0.15 // 15% of target's gold
)

func (w *World) handlePickpocket(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	targetID, err := r.ReadI32()
	if err != nil {
		return
	}
	target, ok := w.players[targetID]
	if !ok || target.MapID != p.MapID {
		return
	}
	if iabs(target.X-p.X) > 1 || iabs(target.Y-p.Y) > 1 {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("Too far away to pickpocket."))
		return
	}
	if target.Gold <= 0 {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(fmt.Sprintf("%s has no gold.", target.CharName)))
		return
	}

	// AGI bonus: each point of AGI above 10 adds 1%.
	_, _, _, _, _, _, agi, _ := recalcCombatStats(p.ClassID, p.Level, 0, 0, 0, 0, 0)
	chance := pickpocketSuccessBase + float64(agi-10)*0.01
	if chance < 0.05 {
		chance = 0.05
	}
	if chance > 0.80 {
		chance = 0.80
	}

	wr := proto.NewWriter(5)
	if rand.Float64() < chance {
		// Success — steal 5–15% of gold.
		stolen := imax(1, int(float64(target.Gold)*(pickpocketMinSteal+rand.Float64()*(pickpocketMaxSteal-pickpocketMinSteal))))
		if stolen > target.Gold {
			stolen = target.Gold
		}
		target.Gold -= stolen
		p.Gold += stolen
		w.sendTo(p, proto.MsgSStats, p.BuildStats())
		w.sendTo(target, proto.MsgSStats, target.BuildStats())

		wr.WriteU8(1)
		wr.WriteI32(int32(stolen))
		w.sendTo(p, proto.MsgSPickpocketResult, wr.Bytes())
		w.sendTo(target, proto.MsgSServerMsg,
			buildServerMsg(fmt.Sprintf("You've been pickpocketed! Lost %d gold.", stolen)))
		// Alert to map in chat (caught = embarrassment).
		w.broadcastMap(p.MapID, proto.MsgSChat,
			buildChat(p.InstanceID, proto.ChatSystem,
				fmt.Sprintf("%s stole %d gold from %s!", p.CharName, stolen, target.CharName),
				"System"), -1)
	} else {
		// Fail — target is alerted.
		wr.WriteU8(0)
		wr.WriteI32(0)
		w.sendTo(p, proto.MsgSPickpocketResult, wr.Bytes())
		w.sendTo(target, proto.MsgSServerMsg,
			buildServerMsg(fmt.Sprintf("%s tried to pickpocket you!", p.CharName)))
		// Brief stun on thief (caught red-handed).
		applyStatusEffect(p, FXStun, 1.0, 0)
	}
}

// ---------------------------------------------------------------------------
// Bounty board
// ---------------------------------------------------------------------------

func (w *World) handleBountyPost(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	targetName, err := r.ReadStr()
	if err != nil {
		return
	}
	gold, err2 := r.ReadI32()
	if err2 != nil || gold <= 0 || int(gold) > p.Gold {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("Invalid bounty amount."))
		return
	}
	// Find target player (online or offline — we just bump their Bounty).
	found := false
	for _, target := range w.players {
		if strings.EqualFold(target.CharName, targetName) {
			target.Bounty += int(gold)
			p.Gold -= int(gold)
			w.sendTo(p, proto.MsgSStats, p.BuildStats())
			w.sendTo(target, proto.MsgSServerMsg,
				buildServerMsg(fmt.Sprintf("A bounty of %d gold has been placed on your head!", gold)))
			// Broadcast bounty update.
			bwr := proto.NewWriter(16 + len(target.CharName))
			bwr.WriteI32(target.InstanceID)
			bwr.WriteStr(target.CharName)
			bwr.WriteI32(int32(target.Bounty))
			w.broadcastAll(proto.MsgSBountyUpdate, bwr.Bytes())
			found = true
			break
		}
	}
	if !found {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(fmt.Sprintf("Player '%s' is not online.", targetName)))
	}
}

func (w *World) handleBountyList(p *Player) {
	// Collect all players with active bounties.
	type entry struct {
		name   string
		bounty int
	}
	var entries []entry
	for _, target := range w.players {
		if target.Bounty > 0 {
			entries = append(entries, entry{target.CharName, target.Bounty})
		}
	}
	wr := proto.NewWriter(4 + len(entries)*20)
	wr.WriteU8(uint8(len(entries)))
	for _, e := range entries {
		wr.WriteStr(e.name)
		wr.WriteI32(int32(e.bounty))
	}
	w.sendTo(p, proto.MsgSBountyList, wr.Bytes())
}

// ---------------------------------------------------------------------------
// Marriage
// ---------------------------------------------------------------------------

const marriageXPBonus = 0.05 // 5% XP when spouse is on same map

func (w *World) handleMarryPropose(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	targetID, err := r.ReadI32()
	if err != nil {
		return
	}
	if p.MarriedTo != "" {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You are already married. Divorce first."))
		return
	}
	target, ok := w.players[targetID]
	if !ok || target.MapID != p.MapID {
		return
	}
	if target.MarriedTo != "" {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(fmt.Sprintf("%s is already married.", target.CharName)))
		return
	}
	if _, pending := w.pendingMarriages[p.InstanceID]; pending {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You already have a pending proposal."))
		return
	}
	w.pendingMarriages[p.InstanceID] = targetID

	wr := proto.NewWriter(16)
	wr.WriteI32(p.InstanceID)
	wr.WriteStr(p.CharName)
	w.sendTo(target, proto.MsgSMarryRequest, wr.Bytes())
	w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(fmt.Sprintf("Proposal sent to %s! ♥", target.CharName)))
}

func (w *World) handleMarryRespond(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	accept, err := r.ReadU8()
	if err != nil {
		return
	}
	// Find proposer targeting p.
	var proposerID int32
	var found bool
	for pID, tID := range w.pendingMarriages {
		if tID == p.InstanceID {
			proposerID = pID
			found = true
			break
		}
	}
	if !found {
		return
	}
	delete(w.pendingMarriages, proposerID)

	proposer, ok := w.players[proposerID]
	if !ok {
		return
	}

	if accept == 0 {
		w.sendTo(proposer, proto.MsgSServerMsg, buildServerMsg(fmt.Sprintf("%s rejected your proposal.", p.CharName)))
		wr := proto.NewWriter(4)
		wr.WriteU8(0)
		wr.WriteStr("")
		w.sendTo(p, proto.MsgSMarryResult, wr.Bytes())
		return
	}

	// Marry them!
	proposer.MarriedTo = p.CharName
	p.MarriedTo = proposer.CharName

	sendMarryResult := func(player *Player, spouse string) {
		wr := proto.NewWriter(4 + len(spouse))
		wr.WriteU8(1)
		wr.WriteStr(spouse)
		w.sendTo(player, proto.MsgSMarryResult, wr.Bytes())
	}
	sendMarryResult(proposer, p.CharName)
	sendMarryResult(p, proposer.CharName)

	msg := fmt.Sprintf("♥  %s and %s are now married! Congratulations!", proposer.CharName, p.CharName)
	w.broadcastMap(p.MapID, proto.MsgSServerMsg, buildServerMsg(msg), -1)
}

// marryXPBonus returns bonus XP to award for a kill (5% if spouse is on same map).
func (w *World) marryXPBonus(p *Player, baseXP int) int {
	if p.MarriedTo == "" {
		return 0
	}
	for _, other := range w.players {
		if other.CharName == p.MarriedTo && other.MapID == p.MapID {
			return int(float64(baseXP) * marriageXPBonus)
		}
	}
	return 0
}

// ---------------------------------------------------------------------------
// Karma / alignment
// ---------------------------------------------------------------------------

const (
	KarmaThresholdChaotic = -200
	KarmaThresholdLawful  = 200
	KarmaPvPKillCost      = -200
	KarmaClamp            = 1000
)

// karmaAlignment returns 0=neutral, 1=lawful, 2=chaotic.
func karmaAlignment(karma int) uint8 {
	switch {
	case karma > KarmaThresholdLawful:
		return 1
	case karma < KarmaThresholdChaotic:
		return 2
	default:
		return 0
	}
}

func (w *World) updateKarma(p *Player, delta int) {
	p.Karma += delta
	if p.Karma > KarmaClamp {
		p.Karma = KarmaClamp
	}
	if p.Karma < -KarmaClamp {
		p.Karma = -KarmaClamp
	}
	w.sendKarmaUpdate(p)
}

func (w *World) sendKarmaUpdate(p *Player) {
	wr := proto.NewWriter(5)
	wr.WriteI32(int32(p.Karma))
	wr.WriteU8(karmaAlignment(p.Karma))
	w.sendTo(p, proto.MsgSKarmaUpdate, wr.Bytes())
}

// ---------------------------------------------------------------------------
// Spectating
// ---------------------------------------------------------------------------

// setSpectating toggles spectating state for a player and notifies the client.
func (w *World) setSpectating(p *Player, on bool) {
	if p.Spectating == on {
		return
	}
	p.Spectating = on
	wr := proto.NewWriter(1)
	if on {
		wr.WriteU8(1)
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You are now spectating. You cannot be attacked."))
	} else {
		wr.WriteU8(0)
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You are no longer spectating."))
	}
	w.sendTo(p, proto.MsgSSpectateState, wr.Bytes())
}

// ---------------------------------------------------------------------------
// Drunk text mangling
// ---------------------------------------------------------------------------

// drunkMangleText garbles a message to simulate intoxication.
func drunkMangleText(s string) string {
	b := []rune(strings.ToLower(s))
	// Swap every ~5th adjacent pair of characters.
	for i := 4; i < len(b)-1; i += 5 {
		b[i], b[i+1] = b[i+1], b[i]
	}
	result := string(b)
	if rand.Float64() < 0.45 {
		result += " *hic*"
	}
	return result
}
