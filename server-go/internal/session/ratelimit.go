// Package session manages per-connection state and rate limiting.
package session

import (
	"sync"
	"time"

	"github.com/blueavlo-hash/eraonline-server/internal/proto"
)

// Bucket is a token-bucket rate limiter for a single message type.
type Bucket struct {
	tokens    float64
	maxTokens float64
	rate      float64 // tokens per nanosecond
	lastFill  time.Time
	mu        sync.Mutex
}

func newBucket(rl proto.RateLimit) *Bucket {
	return &Bucket{
		tokens:    rl.Burst,
		maxTokens: rl.Burst,
		rate:      rl.TokensPerSec / float64(time.Second),
		lastFill:  time.Now(),
	}
}

// Allow returns true and consumes one token if available.
func (b *Bucket) Allow() bool {
	b.mu.Lock()
	defer b.mu.Unlock()

	now := time.Now()
	elapsed := float64(now.Sub(b.lastFill))
	b.tokens += elapsed * b.rate
	if b.tokens > b.maxTokens {
		b.tokens = b.maxTokens
	}
	b.lastFill = now

	if b.tokens < 1.0 {
		return false
	}
	b.tokens--
	return true
}

// RateLimiter holds per-message-type token buckets for one connection.
type RateLimiter struct {
	buckets map[uint16]*Bucket
}

// NewRateLimiter creates a RateLimiter pre-populated from the protocol rate limit table.
func NewRateLimiter() *RateLimiter {
	rl := &RateLimiter{buckets: make(map[uint16]*Bucket, len(proto.RateLimits))}
	for msgType, limit := range proto.RateLimits {
		rl.buckets[msgType] = newBucket(limit)
	}
	return rl
}

// Allow returns true if the message type is within its rate limit.
// Message types not in the rate limit table are always allowed.
func (rl *RateLimiter) Allow(msgType uint16) bool {
	b, ok := rl.buckets[msgType]
	if !ok {
		return true
	}
	return b.Allow()
}
