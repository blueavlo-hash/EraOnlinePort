package world

import (
	"math/rand"
	"time"
)

// randSource is a package-level random source seeded at startup.
var randSource = rand.New(rand.NewSource(time.Now().UnixNano()))

func init() {
	// Also seed the default source used by math/rand functions.
	rand.Seed(time.Now().UnixNano())
}
