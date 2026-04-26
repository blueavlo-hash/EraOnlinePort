package world

import (
	"fmt"

	"github.com/blueavlo-hash/eraonline-server/internal/proto"
)

// DuelState tracks one active duel between two players.
type DuelState struct {
	ChallengerID int32
	TargetID     int32
	// Bets: bettorID → gold amount.
	// Positive gold = bet on challenger; negative = bet on target.
	Bets map[int32]int32
	// TimeoutSec counts down; duel auto-cancels at zero.
	TimeoutSec float64
}

const duelTimeoutSec = 300.0 // 5-minute duel timeout

// handleDuelRequest sends a challenge from p to targetID.
func (w *World) handleDuelRequest(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	targetID, err := r.ReadI32()
	if err != nil {
		return
	}
	if p.InDuel {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You are already in a duel."))
		return
	}
	target, ok := w.players[targetID]
	if !ok || target.MapID != p.MapID {
		return
	}
	if target.InDuel {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(fmt.Sprintf("%s is already in a duel.", target.CharName)))
		return
	}
	// Check for existing pending challenge from p.
	if _, alreadySent := w.pendingDuels[p.InstanceID]; alreadySent {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You already have a pending duel challenge."))
		return
	}
	w.pendingDuels[p.InstanceID] = targetID

	// Notify target.
	wr := proto.NewWriter(16)
	wr.WriteI32(p.InstanceID)
	wr.WriteStr(p.CharName)
	w.sendTo(target, proto.MsgSDuelChallenge, wr.Bytes())

	w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(fmt.Sprintf("Duel challenge sent to %s.", target.CharName)))
}

// handleDuelRespond accepts or declines a pending challenge targeting p.
func (w *World) handleDuelRespond(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	accept, err := r.ReadU8()
	if err != nil {
		return
	}
	// Find the challenger who targeted p.
	var challengerID int32
	var found bool
	for cID, tID := range w.pendingDuels {
		if tID == p.InstanceID {
			challengerID = cID
			found = true
			break
		}
	}
	if !found {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("No pending duel challenge."))
		return
	}
	delete(w.pendingDuels, challengerID)

	challenger, ok := w.players[challengerID]
	if !ok {
		return
	}

	if accept == 0 {
		w.sendTo(challenger, proto.MsgSServerMsg, buildServerMsg(fmt.Sprintf("%s declined your duel.", p.CharName)))
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("Duel declined."))
		return
	}

	// Start duel.
	duel := &DuelState{
		ChallengerID: challengerID,
		TargetID:     p.InstanceID,
		Bets:         make(map[int32]int32),
		TimeoutSec:   duelTimeoutSec,
	}
	w.duels[challengerID] = duel

	challenger.InDuel = true
	challenger.DuelTarget = p.InstanceID
	p.InDuel = true
	p.DuelTarget = challengerID

	// Notify both.
	{
		wr := proto.NewWriter(16)
		wr.WriteI32(p.InstanceID)
		wr.WriteStr(p.CharName)
		w.sendTo(challenger, proto.MsgSDuelStart, wr.Bytes())
	}
	{
		wr := proto.NewWriter(16)
		wr.WriteI32(challengerID)
		wr.WriteStr(challenger.CharName)
		w.sendTo(p, proto.MsgSDuelStart, wr.Bytes())
	}

	// Announce on-map.
	msg := fmt.Sprintf("⚔  %s and %s have entered a duel! Place your bets!", challenger.CharName, p.CharName)
	w.broadcastMap(p.MapID, proto.MsgSServerMsg, buildServerMsg(msg), -1)
}

// handleDuelBet lets a spectator bet on an active duel.
func (w *World) handleDuelBet(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	challengerID, err := r.ReadI32()
	if err != nil {
		return
	}
	side, err2 := r.ReadU8()
	if err2 != nil {
		return
	}
	gold, err3 := r.ReadI32()
	if err3 != nil {
		return
	}

	if gold <= 0 || int(gold) > p.Gold {
		w.sendTo(p, proto.MsgSDuelBetAck, buildDuelBetAck(false, "Invalid amount."))
		return
	}
	duel, ok := w.duels[challengerID]
	if !ok {
		w.sendTo(p, proto.MsgSDuelBetAck, buildDuelBetAck(false, "No active duel to bet on."))
		return
	}
	if p.InstanceID == duel.ChallengerID || p.InstanceID == duel.TargetID {
		w.sendTo(p, proto.MsgSDuelBetAck, buildDuelBetAck(false, "You cannot bet on your own duel."))
		return
	}
	if _, already := duel.Bets[p.InstanceID]; already {
		w.sendTo(p, proto.MsgSDuelBetAck, buildDuelBetAck(false, "You have already bet on this duel."))
		return
	}

	p.Gold -= int(gold)
	w.sendTo(p, proto.MsgSStats, p.BuildStats())

	// Positive = on challenger, negative = on target.
	if side == 0 {
		duel.Bets[p.InstanceID] = gold
	} else {
		duel.Bets[p.InstanceID] = -gold
	}

	challenger := w.players[duel.ChallengerID]
	target := w.players[duel.TargetID]
	cName, tName := "?", "?"
	if challenger != nil {
		cName = challenger.CharName
	}
	if target != nil {
		tName = target.CharName
	}
	sideName := cName
	if side != 0 {
		sideName = tName
	}
	w.sendTo(p, proto.MsgSDuelBetAck, buildDuelBetAck(true, ""))
	w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(fmt.Sprintf("Bet of %d gold on %s!", gold, sideName)))
}

// resolveDuel ends a duel with winnerID as the victor.
// winnerID must be either the challenger or the target.
func (w *World) resolveDuel(winnerID int32) {
	// Find the duel (keyed by challengerID).
	var duel *DuelState
	var duelKey int32
	if d, ok := w.duels[winnerID]; ok {
		duel = d
		duelKey = winnerID
	} else {
		for k, d := range w.duels {
			if d.TargetID == winnerID {
				duel = d
				duelKey = k
				break
			}
		}
	}
	if duel == nil {
		return
	}

	loserID := duel.ChallengerID
	if winnerID == duel.ChallengerID {
		loserID = duel.TargetID
	}

	delete(w.duels, duelKey)

	winner := w.players[winnerID]
	loser := w.players[loserID]

	if winner != nil {
		winner.InDuel = false
		winner.DuelTarget = 0
		winner.HP = winner.MaxHP // restore winner to full HP
		w.sendTo(winner, proto.MsgSHealth, buildHealth(winner.HP, winner.MP, winner.Stamina))
		wr := proto.NewWriter(1)
		wr.WriteU8(1) // won
		w.sendTo(winner, proto.MsgSDuelEnd, wr.Bytes())
	}
	if loser != nil {
		loser.InDuel = false
		loser.DuelTarget = 0
		loser.HP = imax(1, loser.MaxHP/4) // restore loser to 25% HP
		w.sendTo(loser, proto.MsgSHealth, buildHealth(loser.HP, loser.MP, loser.Stamina))
		wr := proto.NewWriter(1)
		wr.WriteU8(0) // lost
		w.sendTo(loser, proto.MsgSDuelEnd, wr.Bytes())
	}

	// Announce.
	wName, lName := "???", "???"
	if winner != nil {
		wName = winner.CharName
	}
	if loser != nil {
		lName = loser.CharName
	}
	mapID := 0
	if winner != nil {
		mapID = winner.MapID
	} else if loser != nil {
		mapID = loser.MapID
	}
	w.broadcastMap(mapID, proto.MsgSServerMsg,
		buildServerMsg(fmt.Sprintf("⚔  Duel over! %s defeats %s!", wName, lName)), -1)

	// Pay out bets.
	challengerWon := winnerID == duel.ChallengerID
	for bettorID, bet := range duel.Bets {
		bettor := w.players[bettorID]
		if bettor == nil {
			continue
		}
		onChallenger := bet > 0
		abs := bet
		if abs < 0 {
			abs = -abs
		}
		won := (onChallenger && challengerWon) || (!onChallenger && !challengerWon)
		if won {
			bettor.Gold += int(abs) * 2
			w.sendTo(bettor, proto.MsgSServerMsg, buildServerMsg(fmt.Sprintf("Your duel bet paid off! +%d gold.", abs)))
		} else {
			w.sendTo(bettor, proto.MsgSServerMsg, buildServerMsg(fmt.Sprintf("You lost your %d gold duel bet.", abs)))
		}
		w.sendTo(bettor, proto.MsgSStats, bettor.BuildStats())
	}
}

// cancelDuel cancels any duel p is involved in and refunds bets.
func (w *World) cancelDuel(p *Player) {
	if !p.InDuel {
		return
	}

	var duel *DuelState
	var duelKey int32
	if d, ok := w.duels[p.InstanceID]; ok {
		duel = d
		duelKey = p.InstanceID
	} else {
		for k, d := range w.duels {
			if d.TargetID == p.InstanceID {
				duel = d
				duelKey = k
				break
			}
		}
	}
	if duel == nil {
		p.InDuel = false
		p.DuelTarget = 0
		return
	}
	delete(w.duels, duelKey)

	cancelPkt := proto.NewWriter(1)
	cancelPkt.WriteU8(2) // cancelled

	p.InDuel = false
	p.DuelTarget = 0
	w.sendTo(p, proto.MsgSDuelEnd, cancelPkt.Bytes())

	other := w.players[p.DuelTarget]
	if p.DuelTarget == 0 {
		if p.InstanceID == duel.ChallengerID {
			other = w.players[duel.TargetID]
		} else {
			other = w.players[duel.ChallengerID]
		}
	}
	if other != nil {
		other.InDuel = false
		other.DuelTarget = 0
		w.sendTo(other, proto.MsgSDuelEnd, cancelPkt.Bytes())
		w.sendTo(other, proto.MsgSServerMsg, buildServerMsg(fmt.Sprintf("%s cancelled the duel.", p.CharName)))
	}

	// Refund all bets.
	for bettorID, bet := range duel.Bets {
		abs := bet
		if abs < 0 {
			abs = -abs
		}
		bettor := w.players[bettorID]
		if bettor == nil {
			continue
		}
		bettor.Gold += int(abs)
		w.sendTo(bettor, proto.MsgSStats, bettor.BuildStats())
		w.sendTo(bettor, proto.MsgSServerMsg, buildServerMsg(fmt.Sprintf("Duel cancelled — %d gold refunded.", abs)))
	}
}

// tickDuels advances duel timeout timers and auto-cancels expired duels.
func (w *World) tickDuels(deltaSec float64) {
	for key, duel := range w.duels {
		duel.TimeoutSec -= deltaSec
		if duel.TimeoutSec <= 0 {
			// Auto-cancel.
			if c := w.players[duel.ChallengerID]; c != nil {
				w.cancelDuel(c)
			}
			delete(w.duels, key)
		}
	}
}

func buildDuelBetAck(success bool, reason string) []byte {
	wr := proto.NewWriter(4 + len(reason))
	if success {
		wr.WriteU8(1)
	} else {
		wr.WriteU8(0)
	}
	wr.WriteStr(reason)
	return wr.Bytes()
}

func buildHealth(hp, mp, sta int) []byte {
	wr := proto.NewWriter(6)
	wr.WriteI16(int16(hp))
	wr.WriteI16(int16(mp))
	wr.WriteI16(int16(sta))
	return wr.Bytes()
}
