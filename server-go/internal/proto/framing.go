package proto

import (
	"encoding/binary"
	"fmt"
	"io"
)

// FramePreauth builds a 4-byte-header pre-auth packet (no HMAC).
//
//	[u16 type][u16 payload_len][payload]
func FramePreauth(msgType uint16, payload []byte) []byte {
	out := make([]byte, PreAuthHdrSize+len(payload))
	binary.BigEndian.PutUint16(out[0:], msgType)
	binary.BigEndian.PutUint16(out[2:], uint16(len(payload)))
	copy(out[PreAuthHdrSize:], payload)
	return out
}

// FrameAuth builds an authenticated packet with sequence number and HMAC.
//
//	[u32 seq][u16 type][u16 payload_len][payload][16-byte HMAC]
func FrameAuth(msgType uint16, payload []byte, seq uint32, sessionKey []byte) []byte {
	hdrAndPayload := make([]byte, AuthHdrSize+len(payload))
	binary.BigEndian.PutUint32(hdrAndPayload[0:], seq)
	binary.BigEndian.PutUint16(hdrAndPayload[4:], msgType)
	binary.BigEndian.PutUint16(hdrAndPayload[6:], uint16(len(payload)))
	copy(hdrAndPayload[AuthHdrSize:], payload)

	tag := SignPacket(sessionKey, hdrAndPayload)
	return append(hdrAndPayload, tag...)
}

// PreAuthHeader holds the decoded pre-auth packet header.
type PreAuthHeader struct {
	Type       uint16
	PayloadLen uint16
}

// AuthHeader holds the decoded authenticated packet header.
type AuthHeader struct {
	Seq        uint32
	Type       uint16
	PayloadLen uint16
}

// ReadPreAuthHeader reads and decodes a 4-byte pre-auth header from r.
func ReadPreAuthHeader(r io.Reader) (PreAuthHeader, error) {
	var hdr [PreAuthHdrSize]byte
	if _, err := io.ReadFull(r, hdr[:]); err != nil {
		return PreAuthHeader{}, err
	}
	return PreAuthHeader{
		Type:       binary.BigEndian.Uint16(hdr[0:]),
		PayloadLen: binary.BigEndian.Uint16(hdr[2:]),
	}, nil
}

// ReadAuthHeader reads and decodes an 8-byte authenticated packet header from r.
func ReadAuthHeader(r io.Reader) (AuthHeader, error) {
	var hdr [AuthHdrSize]byte
	if _, err := io.ReadFull(r, hdr[:]); err != nil {
		return AuthHeader{}, err
	}
	return AuthHeader{
		Seq:        binary.BigEndian.Uint32(hdr[0:]),
		Type:       binary.BigEndian.Uint16(hdr[4:]),
		PayloadLen: binary.BigEndian.Uint16(hdr[6:]),
	}, nil
}

// ReadPreAuthPacket reads a complete pre-auth packet from r.
// Returns (msgType, payload, error).
func ReadPreAuthPacket(r io.Reader) (uint16, []byte, error) {
	hdr, err := ReadPreAuthHeader(r)
	if err != nil {
		return 0, nil, err
	}
	if int(hdr.PayloadLen) > MaxPayloadSize {
		return 0, nil, fmt.Errorf("pre-auth payload too large: %d", hdr.PayloadLen)
	}
	payload := make([]byte, hdr.PayloadLen)
	if hdr.PayloadLen > 0 {
		if _, err := io.ReadFull(r, payload); err != nil {
			return 0, nil, err
		}
	}
	return hdr.Type, payload, nil
}

// ReadAuthPacket reads a complete authenticated packet from r and verifies HMAC.
// Returns (seq, msgType, payload, error).
func ReadAuthPacket(r io.Reader, sessionKey []byte, expectedSeq uint32) (uint32, uint16, []byte, error) {
	hdr, err := ReadAuthHeader(r)
	if err != nil {
		return 0, 0, nil, err
	}
	if int(hdr.PayloadLen) > MaxPayloadSize {
		return 0, 0, nil, fmt.Errorf("auth payload too large: %d", hdr.PayloadLen)
	}

	// Read payload + HMAC tag in one read.
	rest := make([]byte, int(hdr.PayloadLen)+HMACSize)
	if _, err := io.ReadFull(r, rest); err != nil {
		return 0, 0, nil, err
	}

	payload := rest[:hdr.PayloadLen]
	tag := rest[hdr.PayloadLen:]

	// Reconstruct hdr bytes for HMAC verification.
	var hdrBytes [AuthHdrSize]byte
	binary.BigEndian.PutUint32(hdrBytes[0:], hdr.Seq)
	binary.BigEndian.PutUint16(hdrBytes[4:], hdr.Type)
	binary.BigEndian.PutUint16(hdrBytes[6:], hdr.PayloadLen)
	signed := append(hdrBytes[:], payload...)

	if !VerifyPacket(sessionKey, signed, tag) {
		return 0, 0, nil, fmt.Errorf("HMAC verification failed (type=0x%04X seq=%d)", hdr.Type, hdr.Seq)
	}

	// Sequence number check: must be exactly expectedSeq.
	if hdr.Seq != expectedSeq {
		return 0, 0, nil, fmt.Errorf("sequence mismatch: got %d, want %d", hdr.Seq, expectedSeq)
	}

	return hdr.Seq, hdr.Type, payload, nil
}
