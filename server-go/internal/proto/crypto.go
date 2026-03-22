package proto

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"

	"golang.org/x/crypto/pbkdf2"
)

// RandomNonce generates a random nonce of the given size.
func RandomNonce(size int) ([]byte, error) {
	b := make([]byte, size)
	_, err := rand.Read(b)
	return b, err
}

// HMAC256 computes HMAC-SHA256 and returns the first outLen bytes.
func HMAC256(key, msg []byte, outLen int) []byte {
	h := hmac.New(sha256.New, key)
	h.Write(msg)
	full := h.Sum(nil)
	if outLen >= len(full) {
		return full
	}
	return full[:outLen]
}

// PBKDF2Hash derives a 32-byte key from the password using PBKDF2-HMAC-SHA256.
func PBKDF2Hash(password string, salt []byte) []byte {
	return pbkdf2.Key([]byte(password), salt, PBKDF2Iterations, 32, sha256.New)
}

// RandomSalt generates a random 16-byte password salt.
func RandomSalt() ([]byte, error) {
	return RandomNonce(16)
}

// DeriveSessionKey computes the 16-byte session HMAC key.
//
//	key = HMAC-SHA256(serverSecret, clientNonce || serverNonce || sessionID)[0:16]
func DeriveSessionKey(serverSecret, clientNonce, serverNonce []byte, sessionID string) []byte {
	msg := make([]byte, 0, len(clientNonce)+len(serverNonce)+len(sessionID))
	msg = append(msg, clientNonce...)
	msg = append(msg, serverNonce...)
	msg = append(msg, []byte(sessionID)...)
	return HMAC256(serverSecret, msg, HMACSize)
}

// SignPacket returns the HMACSize-byte tag for the given packet data.
func SignPacket(sessionKey, data []byte) []byte {
	return HMAC256(sessionKey, data, HMACSize)
}

// VerifyPacket performs a constant-time HMAC verification.
func VerifyPacket(sessionKey, data, tag []byte) bool {
	expected := SignPacket(sessionKey, data)
	return subtle.ConstantTimeCompare(expected, tag) == 1
}
