package server

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"net"
	"strings"
	"time"

	"github.com/blueavlo-hash/eraonline-server/internal/db"
	"github.com/blueavlo-hash/eraonline-server/internal/proto"
	"github.com/blueavlo-hash/eraonline-server/internal/session"
	"github.com/blueavlo-hash/eraonline-server/internal/world"
)

// Conn handles one client TCP connection. It runs in its own goroutine and
// communicates with the world goroutine exclusively via channels.
type Conn struct {
	id     uint64
	raw    net.Conn
	sess   *session.Session
	srv    *Server
	log    *slog.Logger
	sendCh chan []byte // buffered; world writes, this goroutine reads
	done   chan struct{}
}

func newConn(id uint64, raw net.Conn, srv *Server) *Conn {
	return &Conn{
		id:     id,
		raw:    raw,
		sess:   session.NewSession(id),
		srv:    srv,
		log:    srv.log.With("conn", id, "remote", raw.RemoteAddr()),
		sendCh: make(chan []byte, 256),
		done:   make(chan struct{}),
	}
}

// Run is the main connection goroutine: handshake → auth → read loop.
// The send pump runs concurrently.
func (c *Conn) Run(ctx context.Context) {
	defer func() {
		// Always clean up.
		close(c.done)
		c.raw.Close()
		c.srv.removeConn(c.id)

		// Notify world of departure (if in-world).
		if c.sess.GetState() == session.StateInWorld {
			c.srv.world.Inbox <- world.ClientMsg{ConnID: c.id, LeaveConn: true}
		}
	}()

	// Start the send pump.
	go c.sendPump()

	// Handshake phase.
	if err := c.doHandshake(); err != nil {
		if !isEOF(err) {
			c.log.Debug("handshake failed", "err", err)
		}
		return
	}

	// Auth phase.
	if err := c.doAuth(ctx); err != nil {
		if !isEOF(err) {
			c.log.Debug("auth failed", "err", err)
		}
		return
	}

	// Char select phase.
	if err := c.doCharSelect(ctx); err != nil {
		if !isEOF(err) {
			c.log.Debug("char select failed", "err", err)
		}
		return
	}

	// In-world read loop.
	c.readLoop(ctx)
}

// doHandshake performs the TLS + protocol handshake including client attestation.
//
// Flow:
//  1. Send SERVER_HELLO: version:u16, server_nonce[16], client_challenge[16]
//  2. Read CLIENT_HELLO: client_nonce[16], client_proof[16]
//  3. Verify client_proof = HMAC(clientIdentitySecret, clientChallenge || serverNonce)
//  4. Advance state to StateAuth
func (c *Conn) doHandshake() error {
	c.setDeadline(c.srv.cfg.Server.ReadTimeout)

	// Generate nonces.
	serverNonce, err := proto.RandomNonce(proto.NonceSize)
	if err != nil {
		return err
	}
	clientChallenge, err := proto.RandomNonce(proto.ChallengeSize)
	if err != nil {
		return err
	}
	c.sess.ServerNonce = serverNonce
	c.sess.ClientChallenge = clientChallenge

	// Send SERVER_HELLO.
	{
		w := proto.NewWriter(2 + proto.NonceSize + proto.ChallengeSize)
		w.WriteU16(proto.ProtocolVersion)
		w.WriteBytes(serverNonce)
		w.WriteBytes(clientChallenge)
		if err := c.writeRaw(proto.FramePreauth(proto.MsgServerHello, w.Bytes())); err != nil {
			return err
		}
	}

	// Read CLIENT_HELLO.
	msgType, payload, err := proto.ReadPreAuthPacket(c.raw)
	if err != nil {
		return err
	}
	if msgType != proto.MsgClientHello {
		return fmt.Errorf("expected CLIENT_HELLO (0x%04X), got 0x%04X", proto.MsgClientHello, msgType)
	}

	r := proto.NewReader(payload)
	clientNonce, err := r.ReadBytes(proto.NonceSize)
	if err != nil {
		return fmt.Errorf("CLIENT_HELLO: missing client_nonce")
	}
	clientProof, err := r.ReadBytes(proto.HMACSize)
	if err != nil {
		return fmt.Errorf("CLIENT_HELLO: missing client_proof")
	}

	// Verify client attestation.
	if !proto.VerifyClientProof(c.srv.clientIdentitySecret, clientChallenge, serverNonce, clientProof) {
		// Send a generic kick — don't reveal what failed.
		_ = c.writeRaw(proto.FramePreauth(proto.MsgAuthFail, buildStrPayload("Connection refused.")))
		return fmt.Errorf("client attestation failed (unrecognized client)")
	}

	c.sess.ClientNonce = clientNonce
	c.sess.SetState(session.StateAuth)
	c.log.Debug("handshake complete")
	return nil
}

// doAuth reads AUTH_LOGIN or AUTH_REGISTER and validates credentials.
func (c *Conn) doAuth(ctx context.Context) error {
	c.setDeadline(c.srv.cfg.Server.ReadTimeout)

	for {
		msgType, payload, err := proto.ReadPreAuthPacket(c.raw)
		if err != nil {
			return err
		}

		switch msgType {
		case proto.MsgAuthLogin:
			return c.handleAuthLogin(ctx, payload)
		case proto.MsgAuthRegister:
			return c.handleAuthRegister(ctx, payload)
		case proto.MsgAuthToken:
			return c.handleAuthToken(ctx, payload)
		default:
			return fmt.Errorf("expected AUTH_LOGIN/REGISTER/TOKEN, got 0x%04X", msgType)
		}
	}
}

func (c *Conn) handleAuthLogin(ctx context.Context, payload []byte) error {
	if c.sess.IsLocked() {
		return c.sendAuthFail("Too many failed attempts. Please wait.")
	}

	r := proto.NewReader(payload)
	username, err := r.ReadStr()
	if err != nil {
		return err
	}
	password, err := r.ReadStr()
	if err != nil {
		return err
	}
	if len(username) == 0 || len(username) > 32 {
		return c.sendAuthFail("Invalid username.")
	}

	account, err := c.srv.db.VerifyAccount(ctx, username, password)
	if err != nil {
		c.sess.FailedAttempts++
		if c.sess.FailedAttempts >= proto.AuthMaxAttempts {
			c.sess.LockedUntil = time.Now().Add(proto.AuthLockoutSeconds * time.Second)
		}
		c.log.Info("auth failed", "username", username, "attempts", c.sess.FailedAttempts)
		switch err {
		case db.ErrAccountBanned:
			return c.sendAuthFail("Account is banned.")
		default:
			return c.sendAuthFail("Invalid username or password.")
		}
	}

	return c.completeAuth(account)
}

func (c *Conn) handleAuthRegister(ctx context.Context, payload []byte) error {
	r := proto.NewReader(payload)
	username, err := r.ReadStr()
	if err != nil {
		return err
	}
	password, err := r.ReadStr()
	if err != nil {
		return err
	}

	if err := validateUsername(username); err != nil {
		return c.sendAuthFail(err.Error())
	}
	if len(password) < 6 {
		return c.sendAuthFail("Password must be at least 6 characters.")
	}

	if err := c.srv.db.CreateAccount(ctx, username, password); err != nil {
		switch err {
		case db.ErrUsernameTaken:
			return c.sendAuthFail("Username already taken.")
		default:
			c.log.Error("register error", "err", err)
			return c.sendAuthFail("Registration failed. Try again.")
		}
	}

	// Immediately log them in.
	account, err := c.srv.db.VerifyAccount(ctx, username, password)
	if err != nil {
		return c.sendAuthFail("Registration succeeded but login failed.")
	}
	return c.completeAuth(account)
}

func (c *Conn) handleAuthToken(ctx context.Context, payload []byte) error {
	r := proto.NewReader(payload)
	token, err := r.ReadStr()
	if err != nil || len(token) == 0 {
		return c.sendAuthFail("Invalid token.")
	}

	entry, ok := c.srv.ValidateToken(token)
	if !ok {
		c.log.Info("auth token invalid or expired")
		return c.sendAuthFail("Token invalid or expired. Please log in via the launcher again.")
	}

	// Consume the token — single use.
	c.srv.ConsumeToken(token)

	// Load the account by ID to get the full account struct.
	account, err := c.srv.db.GetAccountByID(ctx, entry.AccountID)
	if err != nil || account == nil {
		c.log.Error("token auth: account lookup failed", "account_id", entry.AccountID, "err", err)
		return c.sendAuthFail("Account not found.")
	}
	if account.Banned {
		return c.sendAuthFail("Account is banned.")
	}

	c.log.Info("token auth success", "username", account.Username)
	return c.completeAuth(account)
}

func (c *Conn) completeAuth(account *db.Account) error {
	c.sess.AccountID = account.ID
	c.sess.Username = account.Username

	// Generate session ID and derive session key.
	sessionID := generateSessionID()
	c.sess.SessionID = sessionID
	c.sess.SessionKey = proto.DeriveSessionKey(
		c.srv.serverSecret,
		c.sess.ClientNonce,
		c.sess.ServerNonce,
		sessionID,
	)

	c.sess.SetState(session.StateCharSelect)
	c.log.Info("authenticated", "username", account.Username)

	// Send AUTH_OK.
	w := proto.NewWriter(32)
	w.WriteStr(sessionID)
	w.WriteStr("") // char_name placeholder (unused at this stage)
	return c.writeRaw(proto.FramePreauth(proto.MsgAuthOK, w.Bytes()))
}

func (c *Conn) sendAuthFail(reason string) error {
	return c.writeRaw(proto.FramePreauth(proto.MsgAuthFail, buildStrPayload(reason)))
}

// doCharSelect handles the char select / create / delete loop until a char is selected.
func (c *Conn) doCharSelect(ctx context.Context) error {
	// Send char list.
	if err := c.sendCharList(ctx); err != nil {
		return err
	}

	for {
		c.setDeadline(c.srv.cfg.Server.IdleTimeout)
		seq, msgType, payload, err := proto.ReadAuthPacket(c.raw, c.sess.SessionKey, c.sess.RecvSeq)
		if err != nil {
			return err
		}
		c.sess.RecvSeq = seq + 1
		c.sess.Touch()

		switch msgType {
		case proto.MsgCSelectChar:
			return c.handleSelectChar(ctx, payload)

		case proto.MsgCCreateChar:
			if err := c.handleCreateChar(ctx, payload); err != nil {
				c.log.Debug("create char error", "err", err)
			}
			// Re-send updated list.
			if err := c.sendCharList(ctx); err != nil {
				return err
			}

		case proto.MsgCDeleteChar:
			if err := c.handleDeleteChar(ctx, payload); err != nil {
				c.log.Debug("delete char error", "err", err)
			}
			if err := c.sendCharList(ctx); err != nil {
				return err
			}
		}
	}
}

func (c *Conn) sendCharList(ctx context.Context) error {
	chars, err := c.srv.db.ListChars(ctx, c.sess.AccountID)
	if err != nil {
		return err
	}
	w := proto.NewWriter(64)
	w.WriteU8(uint8(len(chars)))
	for _, ch := range chars {
		w.WriteStr(ch.Name)
		w.WriteU8(uint8(ch.Level))
		w.WriteU8(uint8(ch.ClassID))
		w.WriteI16(int16(ch.Body))
		w.WriteI16(int16(ch.Head))
	}
	return c.sendAuth(proto.MsgSCharList, w.Bytes())
}

func (c *Conn) handleSelectChar(ctx context.Context, payload []byte) error {
	r := proto.NewReader(payload)
	name, err := r.ReadStr()
	if err != nil {
		return err
	}
	charData, err := c.srv.db.LoadChar(ctx, c.sess.AccountID, name)
	if err != nil {
		return c.sendAuth(proto.MsgSServerMsg, buildStrPayload("Character not found."))
	}

	c.sess.CharName = name
	c.sess.CharData = charData
	c.sess.SetState(session.StateInWorld)

	c.log.Info("entering world", "char", name)

	// Send player to world goroutine.
	c.srv.world.Inbox <- world.ClientMsg{
		ConnID: c.id,
		JoinInfo: &world.JoinInfo{
			AccountID:   c.sess.AccountID,
			Username:    c.sess.Username,
			CharData:    charData,
			SessionKey:  c.sess.SessionKey,
			SendCh:      c.sendCh,
			InitSendSeq: c.sess.SendSeq, // continue seq from char-select phase
		},
	}
	return nil
}

func (c *Conn) handleCreateChar(ctx context.Context, payload []byte) error {
	r := proto.NewReader(payload)
	name, err := r.ReadStr()
	if err != nil {
		return err
	}
	classID, _ := r.ReadU8()
	head, _ := r.ReadI16()
	body, _ := r.ReadI16()

	if err := validateCharName(name); err != nil {
		result := proto.NewWriter(32)
		result.WriteU8(0)
		result.WriteStr(err.Error())
		return c.sendAuth(proto.MsgSCreateResult, result.Bytes())
	}

	if err := c.srv.db.CreateChar(ctx, c.sess.AccountID, name, int(classID), int(head), int(body)); err != nil {
		msg := err.Error()
		switch err {
		case db.ErrCharNameTaken:
			msg = "Name already taken."
		case db.ErrTooManyChars:
			msg = "Maximum characters reached."
		}
		result := proto.NewWriter(32)
		result.WriteU8(0)
		result.WriteStr(msg)
		return c.sendAuth(proto.MsgSCreateResult, result.Bytes())
	}

	result := proto.NewWriter(4)
	result.WriteU8(1)
	result.WriteStr("")
	return c.sendAuth(proto.MsgSCreateResult, result.Bytes())
}

func (c *Conn) handleDeleteChar(ctx context.Context, payload []byte) error {
	r := proto.NewReader(payload)
	name, err := r.ReadStr()
	if err != nil {
		return err
	}
	if err := c.srv.db.DeleteChar(ctx, c.sess.AccountID, name); err != nil {
		result := proto.NewWriter(32)
		result.WriteU8(0)
		result.WriteStr("Delete failed.")
		return c.sendAuth(proto.MsgSDeleteResult, result.Bytes())
	}
	result := proto.NewWriter(4)
	result.WriteU8(1)
	result.WriteStr("")
	return c.sendAuth(proto.MsgSDeleteResult, result.Bytes())
}

// readLoop is the in-world receive loop. It reads authenticated packets and
// forwards them to the world goroutine.
func (c *Conn) readLoop(ctx context.Context) {
	for {
		if err := c.raw.SetDeadline(time.Now().Add(c.srv.cfg.Server.IdleTimeout)); err != nil {
			return
		}

		seq, msgType, payload, err := proto.ReadAuthPacket(c.raw, c.sess.SessionKey, c.sess.RecvSeq)
		if err != nil {
			if !isEOF(err) {
				c.log.Debug("read error", "err", err)
			}
			return
		}
		c.sess.RecvSeq = seq + 1
		c.sess.Touch()

		// Rate limit check.
		if !c.sess.RateLimiter.Allow(msgType) {
			c.log.Warn("rate limit exceeded", "msg_type", fmt.Sprintf("0x%04X", msgType))
			continue
		}

		c.srv.world.Inbox <- world.ClientMsg{
			ConnID:  c.id,
			MsgType: msgType,
			Payload: payload,
		}
	}
}

// sendPump drains the send channel and writes to the TLS connection.
func (c *Conn) sendPump() {
	defer func() {
		// Drain any remaining buffered packets so the world goroutine's non-blocking
		// sends don't silently stall the buffer after disconnect.
		for {
			select {
			case <-c.sendCh:
			default:
				return
			}
		}
	}()

	for {
		select {
		case pkt, ok := <-c.sendCh:
			if !ok {
				return
			}
			if err := c.raw.SetDeadline(time.Now().Add(c.srv.cfg.Server.WriteTimeout)); err != nil {
				return
			}
			if err := c.writeRaw(pkt); err != nil {
				return
			}
		case <-c.done:
			return
		}
	}
}

// sendAuth sends an authenticated packet via the send channel.
func (c *Conn) sendAuth(msgType uint16, payload []byte) error {
	seq := c.sess.NextSendSeq()
	pkt := proto.FrameAuth(msgType, payload, seq, c.sess.SessionKey)
	select {
	case c.sendCh <- pkt:
		return nil
	default:
		return fmt.Errorf("send buffer full")
	}
}

func (c *Conn) writeRaw(data []byte) error {
	_, err := c.raw.Write(data)
	return err
}

func (c *Conn) setDeadline(d time.Duration) {
	_ = c.raw.SetDeadline(time.Now().Add(d))
}

// isEOF returns true for normal disconnect errors.
func isEOF(err error) bool {
	if err == nil {
		return false
	}
	if err == io.EOF {
		return true
	}
	s := err.Error()
	return strings.Contains(s, "use of closed network connection") ||
		strings.Contains(s, "connection reset by peer") ||
		strings.Contains(s, "broken pipe")
}

// buildStrPayload builds a single-string pre-auth packet payload.
func buildStrPayload(s string) []byte {
	w := proto.NewWriter(4 + len(s))
	w.WriteStr(s)
	return w.Bytes()
}

// generateSessionID generates a random session identifier.
func generateSessionID() string {
	b, _ := proto.RandomNonce(16)
	return fmt.Sprintf("%x", b)
}

// validateUsername checks that a username is valid for registration.
func validateUsername(name string) error {
	if len(name) < 3 || len(name) > 32 {
		return fmt.Errorf("Username must be 3–32 characters.")
	}
	for _, r := range name {
		if !isAlphanumeric(r) && r != '_' {
			return fmt.Errorf("Username may only contain letters, numbers, and underscores.")
		}
	}
	return nil
}

// validateCharName checks that a character name is valid.
func validateCharName(name string) error {
	if len(name) < 2 || len(name) > 20 {
		return fmt.Errorf("Name must be 2–20 characters.")
	}
	for _, r := range name {
		if !isAlphanumeric(r) && r != ' ' {
			return fmt.Errorf("Name may only contain letters, numbers, and spaces.")
		}
	}
	return nil
}

func isAlphanumeric(r rune) bool {
	return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9')
}

