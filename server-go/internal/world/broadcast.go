package world

import "github.com/blueavlo-hash/eraonline-server/internal/proto"

// sendTo sends an authenticated packet to a single player.
// Must be called from the world goroutine.
func (w *World) sendTo(p *Player, msgType uint16, payload []byte) {
	seq := p.SendSeq
	p.SendSeq++
	pkt := proto.FrameAuth(msgType, payload, seq, p.sendKey)
	select {
	case p.Send <- pkt:
	default:
		// Channel full — player is too slow. Will be cleaned up by idle timeout.
	}
}

// sendPreauth sends a pre-auth packet (no HMAC, used during handshake).
func sendPreauth(ch chan []byte, msgType uint16, payload []byte) {
	pkt := proto.FramePreauth(msgType, payload)
	select {
	case ch <- pkt:
	default:
	}
}

// broadcastMap sends a packet to every player on the given map.
func (w *World) broadcastMap(mapID int, msgType uint16, payload []byte, excludeID int32) {
	for _, p := range w.players {
		if p.MapID == mapID && p.InstanceID != excludeID {
			w.sendTo(p, msgType, payload)
		}
	}
}

// broadcastMapAndSelf sends to everyone on the map including the sender.
func (w *World) broadcastMapAndSelf(mapID int, msgType uint16, payload []byte) {
	for _, p := range w.players {
		if p.MapID == mapID {
			w.sendTo(p, msgType, payload)
		}
	}
}

// broadcastAll sends a packet to every connected player.
func (w *World) broadcastAll(msgType uint16, payload []byte) {
	for _, p := range w.players {
		w.sendTo(p, msgType, payload)
	}
}

// buildServerMsg builds a S_SERVER_MSG payload.
func buildServerMsg(msg string) []byte {
	wr := proto.NewWriter(4 + len(msg))
	wr.WriteStr(msg)
	return wr.Bytes()
}

// buildChat builds a S_CHAT payload.
func buildChat(charID int32, chatType uint8, msg string) []byte {
	wr := proto.NewWriter(8 + len(msg))
	wr.WriteI32(charID)
	wr.WriteU8(chatType)
	wr.WriteStr(msg)
	return wr.Bytes()
}

// buildMoveChar builds a S_MOVE_CHAR payload.
func buildMoveChar(charID int32, x, y int, heading uint8) []byte {
	wr := proto.NewWriter(10)
	wr.WriteI32(charID)
	wr.WriteI16(int16(x))
	wr.WriteI16(int16(y))
	wr.WriteU8(heading)
	return wr.Bytes()
}

// buildRemoveChar builds a S_REMOVE_CHAR payload.
func buildRemoveChar(charID int32) []byte {
	wr := proto.NewWriter(4)
	wr.WriteI32(charID)
	return wr.Bytes()
}

// buildDamage builds a S_DAMAGE payload.
func buildDamage(charID int32, damage int16, evaded bool) []byte {
	wr := proto.NewWriter(8)
	wr.WriteI32(charID)
	wr.WriteI16(damage)
	ev := uint8(0)
	if evaded {
		ev = 1
	}
	wr.WriteU8(ev)
	return wr.Bytes()
}

// buildKick builds a S_KICK payload.
func buildKick(reason string) []byte {
	wr := proto.NewWriter(4 + len(reason))
	wr.WriteStr(reason)
	return wr.Bytes()
}
