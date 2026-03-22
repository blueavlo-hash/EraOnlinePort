package world

import (
	"github.com/blueavlo-hash/eraonline-server/internal/proto"
)

const shopSellMult = 0.30 // players sell at 30% of base value

func (w *World) handleShopOpen(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	npcID, err := r.ReadI32()
	if err != nil {
		return
	}
	npc, ok := w.npcs[npcID]
	if !ok || npc.MapID != p.MapID {
		return
	}
	// npc_type 4 = ability trainer — open ability shop instead of item shop.
	if npc.Def.NPCType == 4 {
		w.sendAbilityShop(p)
		return
	}
	if !npc.Def.Vendor {
		return
	}
	w.sendShopList(p, npc)
}

func (w *World) sendShopList(p *Player, npc *NPC) {
	// Build item list from NPC definition fields Obj1-40.
	var items []shopItem
	for i := 1; i <= 40; i++ {
		objIdx := npc.Def.ShopItems[i-1]
		if objIdx == 0 {
			continue
		}
		obj := w.gameData.GetObject(objIdx)
		if obj == nil {
			continue
		}
		items = append(items, shopItem{
			ObjIndex: objIdx,
			Price:    obj.Value,
			Name:     obj.Name,
		})
	}

	wr := proto.NewWriter(256)
	wr.WriteStr(npc.Def.ShopName)
	wr.WriteU8(uint8(len(items)))
	for _, it := range items {
		wr.WriteI16(int16(it.ObjIndex))
		wr.WriteI32(int32(it.Price))
		wr.WriteStr(it.Name)
	}
	w.sendTo(p, proto.MsgSShopList, wr.Bytes())
}

type shopItem struct {
	ObjIndex int
	Price    int
	Name     string
}

func (w *World) handleBuy(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	npcID, err := r.ReadI32()
	if err != nil {
		return
	}
	objIndex, err := r.ReadI16()
	if err != nil {
		return
	}
	amount, err := r.ReadU16()
	if err != nil {
		return
	}
	if amount == 0 {
		amount = 1
	}

	npc, ok := w.npcs[npcID]
	if !ok || npc.MapID != p.MapID || !npc.Def.Vendor {
		w.sendBuyResult(p, false, "Vendor not found.")
		return
	}

	obj := w.gameData.GetObject(int(objIndex))
	if obj == nil {
		w.sendBuyResult(p, false, "Unknown item.")
		return
	}

	// Verify vendor sells this item.
	vendorSells := false
	for _, idx := range npc.Def.ShopItems {
		if idx == int(objIndex) {
			vendorSells = true
			break
		}
	}
	if !vendorSells {
		w.sendBuyResult(p, false, "Vendor does not sell this item.")
		return
	}

	totalCost := obj.Value * int(amount)
	if p.Gold < totalCost {
		w.sendBuyResult(p, false, "Not enough gold.")
		return
	}

	if !w.giveItem(p, int(objIndex), int(amount)) {
		w.sendBuyResult(p, false, "Inventory is full.")
		return
	}

	p.Gold -= totalCost
	w.sendBuyResult(p, true, "")
	w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
	w.sendTo(p, proto.MsgSStats, p.BuildStats())
}

func (w *World) sendBuyResult(p *Player, success bool, reason string) {
	wr := proto.NewWriter(16)
	if success {
		wr.WriteU8(1)
	} else {
		wr.WriteU8(0)
	}
	wr.WriteStr(reason)
	w.sendTo(p, proto.MsgSBuyResult, wr.Bytes())
}

func (w *World) handleSell(p *Player, payload []byte) {
	r := proto.NewReader(payload)
	_, err := r.ReadI32() // npc_instance_id
	if err != nil {
		return
	}
	invSlot, err := r.ReadU8()
	if err != nil || int(invSlot) >= 20 {
		return
	}
	item := p.Inventory[invSlot]
	if item == nil || item.ObjIndex == 0 {
		w.sendBuyResult(p, false, "No item in that slot.")
		return
	}
	if item.Equipped {
		w.sendBuyResult(p, false, "Unequip the item first.")
		return
	}

	obj := w.gameData.GetObject(item.ObjIndex)
	if obj == nil || obj.Value <= 0 || !obj.Sellable {
		w.sendBuyResult(p, false, "That item cannot be sold.")
		return
	}

	sellPrice := imax(1, int(float64(obj.Value)*shopSellMult))
	p.Inventory[invSlot] = nil
	p.Gold += sellPrice

	w.sendBuyResult(p, true, "")
	w.sendTo(p, proto.MsgSInventory, p.BuildInventory())
	w.sendTo(p, proto.MsgSStats, p.BuildStats())
}
