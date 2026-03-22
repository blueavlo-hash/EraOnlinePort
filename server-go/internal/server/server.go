// Package server manages the TCP listener and connection lifecycle.
package server

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/pem"
	"fmt"
	"log/slog"
	"math/big"
	"net"
	"os"
	"sync"
	"sync/atomic"
	"time"

	"github.com/blueavlo-hash/eraonline-server/internal/config"
	"github.com/blueavlo-hash/eraonline-server/internal/db"
	"github.com/blueavlo-hash/eraonline-server/internal/proto"
	"github.com/blueavlo-hash/eraonline-server/internal/session"
	"github.com/blueavlo-hash/eraonline-server/internal/world"
)

// tokenEntry stores a single-use launcher auth token.
type tokenEntry struct {
	AccountID int64
	Username  string
	Expiry    time.Time
}

// Server accepts connections and manages their lifecycle.
type Server struct {
	cfg    *config.Config
	db     *db.DB
	world  *world.World
	log    *slog.Logger

	// serverSecret is the HMAC secret used for session key derivation (from config).
	serverSecret []byte
	// clientIdentitySecret is used to verify client attestation proofs.
	clientIdentitySecret []byte

	tlsCfg *tls.Config

	connsMu sync.Mutex
	conns   map[uint64]*Conn
	nextID  atomic.Uint64

	// Token store for launcher pre-auth tokens.
	tokensMu sync.RWMutex
	tokens   map[string]*tokenEntry
}

// New creates a Server.
func New(cfg *config.Config, database *db.DB, w *world.World, log *slog.Logger) (*Server, error) {
	tlsCfg, err := buildTLS(cfg)
	if err != nil {
		return nil, fmt.Errorf("server: TLS setup: %w", err)
	}

	s := &Server{
		cfg:                  cfg,
		db:                   database,
		world:                w,
		log:                  log,
		serverSecret:         []byte(cfg.Server.Secret),
		clientIdentitySecret: []byte(cfg.Server.ClientIdentitySecret),
		tlsCfg:               tlsCfg,
		conns:                make(map[uint64]*Conn),
		tokens:               make(map[string]*tokenEntry),
	}

	// Start background goroutine to expire old tokens every minute.
	go s.expireTokensLoop()

	return s, nil
}

// IssueToken generates a random 32-byte hex token for the given account and stores it
// with a 5-minute expiry. Returns the token string.
func (s *Server) IssueToken(accountID int64, username string) string {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		// Fallback: use proto random nonce repeated.
		n, _ := proto.RandomNonce(32)
		raw = n
	}
	token := hex.EncodeToString(raw)

	s.tokensMu.Lock()
	s.tokens[token] = &tokenEntry{
		AccountID: accountID,
		Username:  username,
		Expiry:    time.Now().Add(5 * time.Minute),
	}
	s.tokensMu.Unlock()
	return token
}

// ValidateToken looks up a token and returns its entry if valid and not expired.
// The token is NOT consumed here; call ConsumeToken to delete it after use.
func (s *Server) ValidateToken(token string) (*tokenEntry, bool) {
	s.tokensMu.RLock()
	entry, ok := s.tokens[token]
	s.tokensMu.RUnlock()
	if !ok || time.Now().After(entry.Expiry) {
		return nil, false
	}
	return entry, true
}

// ConsumeToken deletes a token so it cannot be reused (single-use).
func (s *Server) ConsumeToken(token string) {
	s.tokensMu.Lock()
	delete(s.tokens, token)
	s.tokensMu.Unlock()
}

// expireTokensLoop runs forever, pruning expired tokens every minute.
func (s *Server) expireTokensLoop() {
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()
	for range ticker.C {
		now := time.Now()
		s.tokensMu.Lock()
		for tok, entry := range s.tokens {
			if now.After(entry.Expiry) {
				delete(s.tokens, tok)
			}
		}
		s.tokensMu.Unlock()
	}
}

// ListenAndServe starts the game TCP listener. It blocks until ctx is cancelled.
func (s *Server) ListenAndServe(ctx context.Context) error {
	ln, err := tls.Listen("tcp", s.cfg.Server.GameAddr, s.tlsCfg)
	if err != nil {
		return fmt.Errorf("listen %s: %w", s.cfg.Server.GameAddr, err)
	}
	s.log.Info("game server listening", "addr", s.cfg.Server.GameAddr)

	go func() {
		<-ctx.Done()
		ln.Close()
	}()

	for {
		conn, err := ln.Accept()
		if err != nil {
			select {
			case <-ctx.Done():
				return nil
			default:
				s.log.Error("accept error", "err", err)
				time.Sleep(10 * time.Millisecond)
				continue
			}
		}

		if s.connCount() >= s.cfg.Server.MaxPlayers {
			conn.Close()
			s.log.Warn("rejected connection: server full")
			continue
		}

		id := s.nextID.Add(1)
		c := newConn(id, conn, s)
		s.addConn(c)
		go c.Run(ctx)
	}
}

func (s *Server) addConn(c *Conn) {
	s.connsMu.Lock()
	s.conns[c.id] = c
	s.connsMu.Unlock()
}

func (s *Server) removeConn(id uint64) {
	s.connsMu.Lock()
	delete(s.conns, id)
	s.connsMu.Unlock()
}

func (s *Server) connCount() int {
	s.connsMu.Lock()
	n := len(s.conns)
	s.connsMu.Unlock()
	return n
}

// KickAll disconnects all connections with the given reason (used for shutdown).
func (s *Server) KickAll(reason string) {
	s.connsMu.Lock()
	conns := make([]*Conn, 0, len(s.conns))
	for _, c := range s.conns {
		conns = append(conns, c)
	}
	s.connsMu.Unlock()

	for _, c := range conns {
		if c.sess.GetState() == session.StateInWorld {
			_ = c.sendAuth(proto.MsgSKick, buildStrPayload(reason))
		}
		c.raw.Close()
	}
}

// buildTLS creates a TLS config from cert/key files or generates a self-signed cert.
func buildTLS(cfg *config.Config) (*tls.Config, error) {
	if cfg.TLS.CertFile != "" && cfg.TLS.KeyFile != "" {
		cert, err := tls.LoadX509KeyPair(cfg.TLS.CertFile, cfg.TLS.KeyFile)
		if err != nil {
			return nil, err
		}
		return &tls.Config{Certificates: []tls.Certificate{cert}}, nil
	}

	// Auto-generate a self-signed certificate.
	return buildSelfSigned()
}

func buildSelfSigned() (*tls.Config, error) {
	const certPath = "server.crt"
	const keyPath  = "server.key"

	// Try to load existing self-signed cert.
	if _, err := os.Stat(certPath); err == nil {
		cert, err := tls.LoadX509KeyPair(certPath, keyPath)
		if err == nil {
			return &tls.Config{Certificates: []tls.Certificate{cert}}, nil
		}
	}

	// Generate new ECDSA P-256 self-signed cert.
	priv, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, err
	}

	serial, _ := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	tmpl := &x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: "EraOnline Server"},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(10 * 365 * 24 * time.Hour),
		KeyUsage:     x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		IPAddresses:  []net.IP{net.ParseIP("127.0.0.1")},
	}

	certDER, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &priv.PublicKey, priv)
	if err != nil {
		return nil, err
	}

	// Write to disk for reuse.
	if f, err := os.Create(certPath); err == nil {
		_ = pem.Encode(f, &pem.Block{Type: "CERTIFICATE", Bytes: certDER})
		f.Close()
	}
	privDER, _ := x509.MarshalECPrivateKey(priv)
	if f, err := os.Create(keyPath); err == nil {
		_ = pem.Encode(f, &pem.Block{Type: "EC PRIVATE KEY", Bytes: privDER})
		f.Close()
	}

	cert, err := tls.X509KeyPair(
		pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: certDER}),
		pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: privDER}),
	)
	if err != nil {
		return nil, err
	}
	return &tls.Config{Certificates: []tls.Certificate{cert}}, nil
}
