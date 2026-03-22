// Package db manages the Era Online SQLite database.
package db

import (
	"context"
	"database/sql"
	"fmt"

	_ "modernc.org/sqlite" // pure-Go SQLite driver (no CGO)
)

// DB wraps the sql.DB connection pool.
type DB struct {
	sql *sql.DB
}

// Open opens (or creates) the SQLite database at the given path
// and runs schema migrations.
func Open(path string, maxConns int) (*DB, error) {
	// Use URI query params to enable WAL journal mode and foreign keys.
	dsn := fmt.Sprintf("file:%s?_journal_mode=WAL&_foreign_keys=on&_busy_timeout=5000", path)
	sqlDB, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("db: open %s: %w", path, err)
	}
	sqlDB.SetMaxOpenConns(maxConns)

	db := &DB{sql: sqlDB}
	if err := db.migrate(); err != nil {
		sqlDB.Close()
		return nil, fmt.Errorf("db: migrate: %w", err)
	}
	return db, nil
}

// Close closes the underlying connection pool.
func (db *DB) Close() error { return db.sql.Close() }

// Ping checks connectivity.
func (db *DB) Ping(ctx context.Context) error { return db.sql.PingContext(ctx) }

// migrate creates tables if they don't exist and applies additive column migrations.
func (db *DB) migrate() error {
	if _, err := db.sql.Exec(schema); err != nil {
		return err
	}
	// Additive column migrations (ignored if column already exists).
	_, _ = db.sql.Exec(`ALTER TABLE inventory ADD COLUMN enchant INTEGER NOT NULL DEFAULT 0`)
	return nil
}

const schema = `
-- Accounts table: one row per registered user.
CREATE TABLE IF NOT EXISTS accounts (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    username    TEXT    NOT NULL UNIQUE COLLATE NOCASE,
    pw_hash     BLOB    NOT NULL,  -- PBKDF2-HMAC-SHA256 output (32 bytes)
    pw_salt     BLOB    NOT NULL,  -- random 16-byte salt
    created_at  INTEGER NOT NULL DEFAULT (unixepoch()),
    last_login  INTEGER,
    banned      INTEGER NOT NULL DEFAULT 0,
    ban_reason  TEXT
);

-- Characters table: one row per character slot (max 3 per account).
CREATE TABLE IF NOT EXISTS characters (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id  INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    name        TEXT    NOT NULL UNIQUE COLLATE NOCASE,
    class_id    INTEGER NOT NULL DEFAULT 1,
    level       INTEGER NOT NULL DEFAULT 1,
    exp         INTEGER NOT NULL DEFAULT 0,
    map_id      INTEGER NOT NULL DEFAULT 3,
    pos_x       INTEGER NOT NULL DEFAULT 50,
    pos_y       INTEGER NOT NULL DEFAULT 50,
    heading     INTEGER NOT NULL DEFAULT 3,  -- 1=N 2=E 3=S 4=W
    hp          INTEGER NOT NULL DEFAULT 100,
    max_hp      INTEGER NOT NULL DEFAULT 100,
    mp          INTEGER NOT NULL DEFAULT 50,
    max_mp      INTEGER NOT NULL DEFAULT 50,
    stamina     INTEGER NOT NULL DEFAULT 100,
    max_stamina INTEGER NOT NULL DEFAULT 100,
    gold        INTEGER NOT NULL DEFAULT 0,
    head_index  INTEGER NOT NULL DEFAULT 1,
    body_index  INTEGER NOT NULL DEFAULT 1,
    weapon_slot INTEGER NOT NULL DEFAULT 0,  -- obj_index of equipped weapon (0=none)
    shield_slot INTEGER NOT NULL DEFAULT 0,
    helmet_slot INTEGER NOT NULL DEFAULT 0,
    armor_slot  INTEGER NOT NULL DEFAULT 0,
    hunger      INTEGER NOT NULL DEFAULT 100,
    thirst      INTEGER NOT NULL DEFAULT 100,
    created_at  INTEGER NOT NULL DEFAULT (unixepoch()),
    last_saved  INTEGER NOT NULL DEFAULT (unixepoch())
);

-- Inventory: up to 20 slots per character.
CREATE TABLE IF NOT EXISTS inventory (
    character_id INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    slot         INTEGER NOT NULL CHECK (slot BETWEEN 0 AND 19),
    obj_index    INTEGER NOT NULL,
    amount       INTEGER NOT NULL DEFAULT 1,
    equipped     INTEGER NOT NULL DEFAULT 0,
    enchant      INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (character_id, slot)
);

-- Bank storage: up to 40 slots per character.
CREATE TABLE IF NOT EXISTS bank (
    character_id INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    slot         INTEGER NOT NULL CHECK (slot BETWEEN 0 AND 39),
    obj_index    INTEGER NOT NULL,
    amount       INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (character_id, slot)
);

-- Bank gold: separate from inventory gold.
CREATE TABLE IF NOT EXISTS bank_gold (
    character_id INTEGER PRIMARY KEY REFERENCES characters(id) ON DELETE CASCADE,
    gold         INTEGER NOT NULL DEFAULT 0
);

-- Skills: one row per skill per character.
CREATE TABLE IF NOT EXISTS skills (
    character_id INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    skill_id     INTEGER NOT NULL CHECK (skill_id BETWEEN 1 AND 28),
    level        INTEGER NOT NULL DEFAULT 0,
    xp           INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (character_id, skill_id)
);

-- Spells: unlocked spell IDs per character.
CREATE TABLE IF NOT EXISTS spells (
    character_id INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    spell_id     INTEGER NOT NULL,
    PRIMARY KEY (character_id, spell_id)
);

-- Abilities: learned ability IDs per character.
CREATE TABLE IF NOT EXISTS abilities (
    character_id INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    ability_id   INTEGER NOT NULL,
    PRIMARY KEY (character_id, ability_id)
);

-- Hotbar: up to 10 slots per character.
CREATE TABLE IF NOT EXISTS hotbar (
    character_id INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    slot         INTEGER NOT NULL CHECK (slot BETWEEN 0 AND 9),
    item_type    INTEGER NOT NULL,  -- 0=ability, 1=spell
    item_id      INTEGER NOT NULL,
    PRIMARY KEY (character_id, slot)
);

-- Quest progress.
CREATE TABLE IF NOT EXISTS quests (
    character_id INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    quest_id     INTEGER NOT NULL,
    state        INTEGER NOT NULL DEFAULT 0,  -- 0=active, 1=complete
    progress     TEXT    NOT NULL DEFAULT '{}',  -- JSON objectives
    PRIMARY KEY (character_id, quest_id)
);

-- Achievements.
CREATE TABLE IF NOT EXISTS achievements (
    character_id    INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    achievement_id  INTEGER NOT NULL,
    unlocked_at     INTEGER NOT NULL DEFAULT (unixepoch()),
    PRIMARY KEY (character_id, achievement_id)
);

-- Faction reputation.
CREATE TABLE IF NOT EXISTS reputation (
    character_id INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    faction      TEXT    NOT NULL,
    rep          INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (character_id, faction)
);

-- Login streak tracking.
CREATE TABLE IF NOT EXISTS login_streaks (
    account_id  INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    streak      INTEGER NOT NULL DEFAULT 0,
    last_reward INTEGER NOT NULL DEFAULT 0  -- unix date of last reward
);

-- Indexes for common lookups.
CREATE INDEX IF NOT EXISTS idx_chars_account ON characters(account_id);
CREATE INDEX IF NOT EXISTS idx_inventory_char ON inventory(character_id);
CREATE INDEX IF NOT EXISTS idx_skills_char    ON skills(character_id);
`
