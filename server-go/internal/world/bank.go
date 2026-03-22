package world

import (
	"github.com/blueavlo-hash/eraonline-server/internal/db"
	"github.com/blueavlo-hash/eraonline-server/internal/proto"
)

const maxBankSlots = 40

func (w *World) handleBankOpen(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	npcID, err := r.ReadI32()
	if err != nil {
		return
	}
	// Verify a bank NPC is nearby (NPC type 4 = banker, or name contains "bank").
	npc, ok := w.npcs[npcID]
	if !ok || npc.MapID != p.MapID {
		return
	}
	isBank := npc.Def.NPCType == 4 || containsInsensitive(npc.Def.Name, "bank")
	if !isBank {
		return
	}
	w.sendBankContents(p)
}

// containsInsensitive reports whether s contains sub (ASCII case-insensitive).
func containsInsensitive(s, sub string) bool {
	if len(sub) == 0 {
		return true
	}
	ls := toLower(s)
	lsub := toLower(sub)
	return searchStr(ls, lsub)
}

func toLower(s string) string {
	b := make([]byte, len(s))
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c >= 'A' && c <= 'Z' {
			c += 32
		}
		b[i] = c
	}
	return string(b)
}

func searchStr(s, sub string) bool {
	for i := 0; i <= len(s)-len(sub); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}

func (w *World) sendBankContents(p *Player) {
	wr := proto.NewWriter(128)
	count := 0
	for _, slot := range p.BankItems {
		if slot != nil && slot.ObjIndex > 0 {
			count++
		}
	}
	wr.WriteU8(uint8(count))
	for i, slot := range p.BankItems {
		if slot == nil || slot.ObjIndex == 0 {
			continue
		}
		wr.WriteU8(uint8(i))
		wr.WriteI16(int16(slot.ObjIndex))
		wr.WriteU16(uint16(slot.Amount))
	}
	wr.WriteI32(int32(p.BankGold))
	w.sendTo(p, proto.MsgSBankContents, wr.Bytes())
}

func (w *World) handleBankDeposit(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	invSlot, err := r.ReadU8()
	if err != nil || int(invSlot) >= 20 {
		return
	}
	item := p.Inventory[invSlot]
	if item == nil || item.ObjIndex == 0 || item.Equipped {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("Cannot deposit that item."))
		return
	}

	// Try to stack into existing bank slot first.
	deposited := false
	for _, bs := range p.BankItems {
		if bs != nil && bs.ObjIndex == item.ObjIndex {
			bs.Amount += item.Amount
			deposited = true
			break
		}
	}
	if !deposited {
		for i, bs := range p.BankItems {
			if bs == nil || bs.ObjIndex == 0 {
				p.BankItems[i] = &db.InventorySlot{Slot: i, ObjIndex: item.ObjIndex, Amount: item.Amount}
				deposited = true
				break
			}
		}
	}
	if !deposited {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("Bank is full."))
		return
	}

	p.Inventory[invSlot] = nil
	w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
	w.sendBankContents(p)
}

func (w *World) handleBankWithdraw(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	bankSlot, err := r.ReadU8()
	if err != nil || int(bankSlot) >= maxBankSlots {
		return
	}
	item := p.BankItems[bankSlot]
	if item == nil || item.ObjIndex == 0 {
		return
	}

	// Find free inventory slot.
	freeSlot := -1
	for i, s := range p.Inventory {
		if s == nil || s.ObjIndex == 0 {
			freeSlot = i
			break
		}
	}
	// Also check for stackable items.
	for i, s := range p.Inventory {
		if s != nil && s.ObjIndex == item.ObjIndex {
			freeSlot = i
			break
		}
	}
	if freeSlot == -1 {
		w.sendTo(p, proto.MsgSServerMsg, buildServerMsg("Inventory is full."))
		return
	}

	existing := p.Inventory[freeSlot]
	if existing != nil && existing.ObjIndex == item.ObjIndex {
		existing.Amount += item.Amount
	} else {
		p.Inventory[freeSlot] = &db.InventorySlot{Slot: freeSlot, ObjIndex: item.ObjIndex, Amount: item.Amount}
	}
	p.BankItems[bankSlot] = nil

	w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
	w.sendBankContents(p)
}

func (w *World) handleBankDepositGold(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	amount, err := r.ReadI32()
	if err != nil || amount <= 0 {
		return
	}
	actual := imin(int(amount), p.Gold)
	if actual <= 0 {
		return
	}
	p.Gold -= actual
	p.BankGold += actual
	w.sendTo(p, proto.MsgSStats, p.BuildStats())
	w.sendBankContents(p)
}

func (w *World) handleBankWithdrawGold(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	amount, err := r.ReadI32()
	if err != nil || amount <= 0 {
		return
	}
	actual := imin(int(amount), p.BankGold)
	if actual <= 0 {
		return
	}
	p.BankGold -= actual
	p.Gold += actual
	w.sendTo(p, proto.MsgSStats, p.BuildStats())
	w.sendBankContents(p)
}
