package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/blueavlo-hash/eraonline-server/internal/proto"
)

// ErrUsernameTaken is returned when a registration uses a duplicate username.
var ErrUsernameTaken = errors.New("username already taken")

// ErrInvalidCredentials is returned for wrong password.
var ErrInvalidCredentials = errors.New("invalid credentials")

// ErrAccountBanned is returned for banned accounts.
var ErrAccountBanned = errors.New("account is banned")

// Account is a hydrated account row.
type Account struct {
	ID        int64
	Username  string
	PwHash    []byte
	PwSalt    []byte
	Banned    bool
	BanReason string
}

// CreateAccount registers a new account. Returns ErrUsernameTaken if duplicate.
func (db *DB) CreateAccount(ctx context.Context, username, password string) error {
	salt, err := proto.RandomSalt()
	if err != nil {
		return fmt.Errorf("create account: generate salt: %w", err)
	}
	hash := proto.PBKDF2Hash(password, salt)

	_, err = db.sql.ExecContext(ctx,
		`INSERT INTO accounts (username, pw_hash, pw_salt) VALUES (?, ?, ?)`,
		username, hash, salt,
	)
	if err != nil {
		// SQLite UNIQUE constraint violation → username taken
		if isConstraintErr(err) {
			return ErrUsernameTaken
		}
		return fmt.Errorf("create account: insert: %w", err)
	}
	return nil
}

// VerifyAccount checks credentials and returns the account on success.
// Returns ErrInvalidCredentials or ErrAccountBanned on failure.
func (db *DB) VerifyAccount(ctx context.Context, username, password string) (*Account, error) {
	var a Account
	var banReason sql.NullString

	err := db.sql.QueryRowContext(ctx,
		`SELECT id, username, pw_hash, pw_salt, banned, ban_reason FROM accounts WHERE username = ? COLLATE NOCASE`,
		username,
	).Scan(&a.ID, &a.Username, &a.PwHash, &a.PwSalt, &a.Banned, &banReason)

	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrInvalidCredentials
	}
	if err != nil {
		return nil, fmt.Errorf("verify account: query: %w", err)
	}

	if a.Banned {
		a.BanReason = banReason.String
		return nil, ErrAccountBanned
	}

	expected := proto.PBKDF2Hash(password, a.PwSalt)
	// Constant-time compare to prevent timing attacks.
	if !constantTimeEqual(expected, a.PwHash) {
		return nil, ErrInvalidCredentials
	}

	// Update last_login timestamp.
	_, _ = db.sql.ExecContext(ctx,
		`UPDATE accounts SET last_login = ? WHERE id = ?`,
		time.Now().Unix(), a.ID,
	)

	return &a, nil
}

// GetAccountByID returns an account by primary key.
func (db *DB) GetAccountByID(ctx context.Context, id int64) (*Account, error) {
	var a Account
	err := db.sql.QueryRowContext(ctx,
		`SELECT id, username, pw_hash, pw_salt, banned, COALESCE(ban_reason,'') FROM accounts WHERE id = ?`, id,
	).Scan(&a.ID, &a.Username, &a.PwHash, &a.PwSalt, &a.Banned, &a.BanReason)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return &a, err
}

// BanAccount sets the banned flag on an account.
func (db *DB) BanAccount(ctx context.Context, username, reason string) error {
	res, err := db.sql.ExecContext(ctx,
		`UPDATE accounts SET banned = 1, ban_reason = ? WHERE username = ? COLLATE NOCASE`,
		reason, username,
	)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return fmt.Errorf("account not found: %s", username)
	}
	return nil
}

// UnbanAccount clears the banned flag.
func (db *DB) UnbanAccount(ctx context.Context, username string) error {
	_, err := db.sql.ExecContext(ctx,
		`UPDATE accounts SET banned = 0, ban_reason = NULL WHERE username = ? COLLATE NOCASE`,
		username,
	)
	return err
}

// constantTimeEqual compares two byte slices in constant time.
func constantTimeEqual(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	var diff byte
	for i := range a {
		diff |= a[i] ^ b[i]
	}
	return diff == 0
}

// isConstraintErr returns true for SQLite UNIQUE constraint errors.
func isConstraintErr(err error) bool {
	if err == nil {
		return false
	}
	// modernc.org/sqlite error strings contain "UNIQUE constraint failed"
	return containsStr(err.Error(), "UNIQUE constraint failed") ||
		containsStr(err.Error(), "constraint failed")
}

func containsStr(s, sub string) bool {
	return len(s) >= len(sub) && (s == sub || len(s) > 0 && searchStr(s, sub))
}

func searchStr(s, sub string) bool {
	for i := 0; i <= len(s)-len(sub); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
