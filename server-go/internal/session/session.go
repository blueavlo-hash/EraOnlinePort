package session

import (
	"sync/atomic"
	"time"

	"github.com/blueavlo-hash/eraonline-server/internal/db"
)

// State represents the connection lifecycle state.
type State int32

const (
	StateHandshake   State = iota // TCP connected, waiting for CLIENT_HELLO
	StateAuth                     // CLIENT_HELLO received and verified, waiting for AUTH_LOGIN/REGISTER
	StateCharSelect               // Authenticated, waiting for C_SELECT_CHAR / C_CREATE_CHAR
	StateInWorld                  // Character selected, in world
	StateClosing                  // Disconnect in progress
)

func (s State) String() string {
	switch s {
	case StateHandshake:
		return "HANDSHAKE"
	case StateAuth:
		return "AUTH"
	case StateCharSelect:
		return "CHAR_SELECT"
	case StateInWorld:
		return "IN_WORLD"
	case StateClosing:
		return "CLOSING"
	default:
		return "UNKNOWN"
	}
}

// Session holds the per-connection state for one client.
type Session struct {
	// ConnID is a monotonically increasing connection identifier.
	ConnID uint64

	// Network state (written only during handshake, then read-only).
	ServerNonce    []byte
	ClientNonce    []byte
	ClientChallenge []byte // challenge sent in SERVER_HELLO for client attestation
	SessionID      string
	SessionKey     []byte

	// Sequence counters (access from connection goroutine only).
	SendSeq uint32
	RecvSeq uint32

	// Auth tracking.
	FailedAttempts  int
	LockedUntil     time.Time
	AccountID       int64
	Username        string

	// Character (set on C_SELECT_CHAR success).
	CharName string
	CharData *db.CharData

	// Per-message rate limiter.
	RateLimiter *RateLimiter

	// Atomic state — readable from any goroutine.
	state atomic.Int32

	// LastActivity is updated on every received packet (for idle timeout).
	LastActivity atomic.Int64 // unix nanoseconds
}

// NewSession creates a new Session with the given connection ID.
func NewSession(connID uint64) *Session {
	s := &Session{
		ConnID:      connID,
		RateLimiter: NewRateLimiter(),
	}
	s.state.Store(int32(StateHandshake))
	s.LastActivity.Store(time.Now().UnixNano())
	return s
}

// GetState returns the current state atomically.
func (s *Session) GetState() State { return State(s.state.Load()) }

// SetState updates the state atomically.
func (s *Session) SetState(st State) { s.state.Store(int32(st)) }

// Touch updates the last-activity timestamp.
func (s *Session) Touch() { s.LastActivity.Store(time.Now().UnixNano()) }

// IdleFor returns how long the session has been idle.
func (s *Session) IdleFor() time.Duration {
	last := time.Unix(0, s.LastActivity.Load())
	return time.Since(last)
}

// IsLocked returns true if the session is in auth lockout.
func (s *Session) IsLocked() bool {
	return s.LockedUntil.After(time.Now())
}

// NextSendSeq increments and returns the next outbound sequence number.
func (s *Session) NextSendSeq() uint32 {
	seq := s.SendSeq
	s.SendSeq++
	return seq
}
