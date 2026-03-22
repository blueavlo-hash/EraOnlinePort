package world

import (
	"github.com/blueavlo-hash/eraonline-server/internal/db"
	"github.com/blueavlo-hash/eraonline-server/internal/proto"
)

// TradeOffer is one item offered in a trade.
type TradeOffer struct {
	ObjIndex int
	Amount   int
	InvSlot  int
}

// TradeState is the active trade for one participant.
type TradeState struct {
	PartnerID int32
	MyItems   []TradeOffer
	Confirmed bool
}

func (w *World) handleTradeRequest(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	targetID, err := r.ReadI32()
	if err != nil {
		return
	}
	target, ok := w.players[targetID]
	if !ok {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("That player is not online."))
		return
	}
	if p.activeTrade != nil || target.activeTrade != nil {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("A trade is already in progress."))
		return
	}

	w.pendingTrades[targetID] = p.InstanceID

	wr := proto.NewWriter(32)
	wr.WriteI32(p.InstanceID)
	wr.WriteStr(p.CharName)
	w.sendTo(target, proto.MsgSTrade, wr.Bytes())
	w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("Trade request sent to "+target.CharName+"."))
}

func (w *World) handleTradeRespond(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	accept, err := r.ReadU8()
	if err != nil {
		return
	}
	requesterID, ok := w.pendingTrades[p.InstanceID]
	if !ok {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("No pending trade request."))
		return
	}
	delete(w.pendingTrades, p.InstanceID)

	requester, reqOK := w.players[requesterID]
	if !reqOK {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("The other player has disconnected."))
		return
	}

	if accept == 0 {
		w.sendTo(requester, proto.MsgSServerMsg, buildServerMsg(p.CharName+" declined your trade request."))
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("You declined the trade request."))
		return
	}

	if p.activeTrade != nil || requester.activeTrade != nil {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("A trade is already in progress."))
		return
	}

	p.activeTrade = &TradeState{PartnerID: requesterID}
	requester.activeTrade = &TradeState{PartnerID: p.InstanceID}

	w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("Trade started with "+requester.CharName+". Click items to offer them."))
	w.sendTo(requester, proto.MsgSServerMsg, buildServerMsg(p.CharName+" accepted your trade."))
	w.broadcastTradeState(p.InstanceID, requesterID)
}

func (w *World) handleTradeOffer(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	invSlot, err := r.ReadU8()
	if err != nil || p.activeTrade == nil {
		return
	}
	if int(invSlot) >= 20 || p.Inventory[invSlot] == nil {
		return
	}
	item := p.Inventory[invSlot]
	if item.Equipped {
		return
	}
	p.activeTrade.MyItems = append(p.activeTrade.MyItems, TradeOffer{
		ObjIndex: item.ObjIndex,
		Amount:   item.Amount,
		InvSlot:  int(invSlot),
	})
	p.activeTrade.Confirmed = false
	w.broadcastTradeState(p.InstanceID, p.activeTrade.PartnerID)
}

func (w *World) handleTradeRetract(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	offerSlot, err := r.ReadU8()
	if err != nil || p.activeTrade == nil {
		return
	}
	items := p.activeTrade.MyItems
	idx := int(offerSlot)
	if idx < len(items) {
		p.activeTrade.MyItems = append(items[:idx], items[idx+1:]...)
	}
	p.activeTrade.Confirmed = false
	w.broadcastTradeState(p.InstanceID, p.activeTrade.PartnerID)
}

func (w *World) handleTradeConfirm(p *Player, _ []byte) {
	if p.activeTrade == nil {
		return
	}
	p.activeTrade.Confirmed = true
	partnerID := p.activeTrade.PartnerID
	w.broadcastTradeState(p.InstanceID, partnerID)

	partner, ok := w.players[partnerID]
	if ok && partner.activeTrade != nil && partner.activeTrade.Confirmed {
		w.completeTrade(p.InstanceID, partnerID)
	}
}

func (w *World) handleTradeCancel(p *Player, _ []byte) {
	if p.activeTrade == nil {
		return
	}
	partnerID := p.activeTrade.PartnerID
	p.activeTrade = nil

	if partner, ok := w.players[partnerID]; ok && partner.activeTrade != nil {
		partner.activeTrade = nil
		wr := proto.NewWriter(32)
		wr.WriteStr("Trade cancelled by other player.")
		w.sendTo(partner, proto.MsgSTradeCancelled, wr.Bytes())
	}

	wr := proto.NewWriter(32)
	wr.WriteStr("Trade cancelled.")
	w.sendTo(p, proto.MsgSTradeCancelled, wr.Bytes())
}

func (w *World) completeTrade(pidA, pidB int32) {
	a, okA := w.players[pidA]
	b, okB := w.players[pidB]
	if !okA || !okB {
		return
	}

	aItems := a.activeTrade.MyItems
	bItems := b.activeTrade.MyItems

	// Count free slots in each player's inventory (slots that will be freed by giving away items
	// or are already empty), to verify the trade can complete without data loss.
	// Temporarily count free slots: empty slots + slots being given away.
	aFreeAfter := w.countFreeInvSlotsAfterTrade(a, aItems)
	bFreeAfter := w.countFreeInvSlotsAfterTrade(b, bItems)

	// Count unique new stacks the receiver needs (items that can't stack on existing).
	aNeedsSlots := w.countNewStacksNeeded(a, bItems, aItems)
	bNeedsSlots := w.countNewStacksNeeded(b, aItems, bItems)

	if aNeedsSlots > aFreeAfter {
		w.sendTo(a, proto.MsgSServerMsg, buildServerMsg("Trade failed: your inventory is full."))
		w.sendTo(b, proto.MsgSServerMsg, buildServerMsg("Trade failed: other player's inventory is full."))
		a.activeTrade = nil
		b.activeTrade = nil
		wr := proto.NewWriter(32)
		wr.WriteStr("Inventory full.")
		w.sendTo(a, proto.MsgSTradeCancelled, wr.Bytes())
		w.sendTo(b, proto.MsgSTradeCancelled, wr.Bytes())
		return
	}
	if bNeedsSlots > bFreeAfter {
		w.sendTo(b, proto.MsgSServerMsg, buildServerMsg("Trade failed: your inventory is full."))
		w.sendTo(a, proto.MsgSServerMsg, buildServerMsg("Trade failed: other player's inventory is full."))
		a.activeTrade = nil
		b.activeTrade = nil
		wr := proto.NewWriter(32)
		wr.WriteStr("Inventory full.")
		w.sendTo(a, proto.MsgSTradeCancelled, wr.Bytes())
		w.sendTo(b, proto.MsgSTradeCancelled, wr.Bytes())
		return
	}

	// Remove offered items from inventories.
	for _, offer := range aItems {
		if offer.InvSlot >= 0 && offer.InvSlot < 20 {
			a.Inventory[offer.InvSlot] = nil
		}
	}
	for _, offer := range bItems {
		if offer.InvSlot >= 0 && offer.InvSlot < 20 {
			b.Inventory[offer.InvSlot] = nil
		}
	}

	// Give items to each other. These cannot fail given the checks above.
	for _, offer := range aItems {
		w.giveItem(b, offer.ObjIndex, offer.Amount)
	}
	for _, offer := range bItems {
		w.giveItem(a, offer.ObjIndex, offer.Amount)
	}

	a.activeTrade = nil
	b.activeTrade = nil

	w.sendTo(a, proto.MsgSTradeComplete, nil)
	w.sendTo(b, proto.MsgSTradeComplete, nil)
	w.sendTo(a, proto.MsgSInventory, a.BuildInventory())
	w.sendTo(b, proto.MsgSInventory, b.BuildInventory())
}

// countFreeInvSlotsAfterTrade returns how many inventory slots a player will have free
// after giving away their offered items.
func (w *World) countFreeInvSlotsAfterTrade(p *Player, giving []TradeOffer) int {
	// Build set of slots being given away.
	givingSlots := make(map[int]bool, len(giving))
	for _, offer := range giving {
		if offer.InvSlot >= 0 && offer.InvSlot < 20 {
			givingSlots[offer.InvSlot] = true
		}
	}
	free := 0
	for i, slot := range p.Inventory {
		if slot == nil || slot.ObjIndex == 0 || givingSlots[i] {
			free++
		}
	}
	return free
}

// countNewStacksNeeded returns how many new inventory slots the receiver needs
// to hold the incoming items (items that can't stack on existing non-given slots).
func (w *World) countNewStacksNeeded(receiver *Player, incoming []TradeOffer, giving []TradeOffer) int {
	givingSlots := make(map[int]bool, len(giving))
	for _, offer := range giving {
		if offer.InvSlot >= 0 && offer.InvSlot < 20 {
			givingSlots[offer.InvSlot] = true
		}
	}
	// Build a set of obj_indexes already in receiver's remaining inventory.
	existing := make(map[int]bool)
	for i, slot := range receiver.Inventory {
		if slot != nil && slot.ObjIndex > 0 && !givingSlots[i] {
			existing[slot.ObjIndex] = true
		}
	}
	newSlots := 0
	for _, offer := range incoming {
		if !existing[offer.ObjIndex] {
			newSlots++
			existing[offer.ObjIndex] = true // only needs one new slot per unique type
		}
	}
	return newSlots
}

func (w *World) broadcastTradeState(pidA, pidB int32) {
	a, okA := w.players[pidA]
	b, okB := w.players[pidB]
	if !okA || !okB || a.activeTrade == nil || b.activeTrade == nil {
		return
	}
	// Send state to each participant.
	for _, pair := range [][2]*Player{{a, b}, {b, a}} {
		me, them := pair[0], pair[1]
		wr := proto.NewWriter(128)
		wr.WriteU8(uint8(len(me.activeTrade.MyItems)))
		for _, it := range me.activeTrade.MyItems {
			wr.WriteI16(int16(it.ObjIndex))
			wr.WriteU16(uint16(it.Amount))
		}
		wr.WriteU8(uint8(len(them.activeTrade.MyItems)))
		for _, it := range them.activeTrade.MyItems {
			wr.WriteI16(int16(it.ObjIndex))
			wr.WriteU16(uint16(it.Amount))
		}
		mc := uint8(0)
		if me.activeTrade.Confirmed {
			mc = 1
		}
		tc := uint8(0)
		if them.activeTrade.Confirmed {
			tc = 1
		}
		wr.WriteU8(mc)
		wr.WriteU8(tc)
		w.sendTo(me, proto.MsgSTradeState, wr.Bytes())
	}
}

// giveItem adds an item to a player's inventory, stacking if possible.
func (w *World) giveItem(p *Player, objIndex, amount int) bool {
	// Try to stack.
	for _, slot := range p.Inventory {
		if slot != nil && slot.ObjIndex == objIndex {
			slot.Amount += amount
			return true
		}
	}
	// Find free slot.
	for i, slot := range p.Inventory {
		if slot == nil || slot.ObjIndex == 0 {
			p.Inventory[i] = &db.InventorySlot{Slot: i, ObjIndex: objIndex, Amount: amount}
			return true
		}
	}
	return false // inventory full
}
