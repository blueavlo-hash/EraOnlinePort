package proto

// ComputeClientProof computes the client attestation proof.
//
//	proof = HMAC-SHA256(clientIdentitySecret, clientChallenge || serverNonce)[0:16]
//
// Both the official client and the server must share the same clientIdentitySecret.
// This value is compiled into the game client binary and the server config.
// It prevents non-official clients (bots, injectors) from reaching the auth layer
// without first extracting the secret from the client binary.
func ComputeClientProof(clientIdentitySecret, clientChallenge, serverNonce []byte) []byte {
	msg := make([]byte, 0, len(clientChallenge)+len(serverNonce))
	msg = append(msg, clientChallenge...)
	msg = append(msg, serverNonce...)
	return HMAC256(clientIdentitySecret, msg, HMACSize)
}

// VerifyClientProof verifies the proof sent in CLIENT_HELLO.
func VerifyClientProof(clientIdentitySecret, clientChallenge, serverNonce, proof []byte) bool {
	expected := ComputeClientProof(clientIdentitySecret, clientChallenge, serverNonce)
	if len(expected) != len(proof) {
		return false
	}
	var diff byte
	for i := range expected {
		diff |= expected[i] ^ proof[i]
	}
	return diff == 0
}
