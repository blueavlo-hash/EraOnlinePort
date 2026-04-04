-- Era Online - SQLite Character Database Schema
-- Replaces the original VB6 .chr text files (GetPrivateProfileString format)
-- Run once: sqlite3 era_online.db < db_schema.sql

PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;

-- ============================================================
-- ACCOUNTS
-- ============================================================
CREATE TABLE IF NOT EXISTS accounts (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    username     TEXT    UNIQUE NOT NULL COLLATE NOCASE,
    password_hash TEXT   NOT NULL,  -- bcrypt hash, NEVER plaintext
    email        TEXT    DEFAULT '',
    created_at   DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_login   DATETIME,
    banned       INTEGER DEFAULT 0,
    ban_reason   TEXT    DEFAULT ''
);

-- ============================================================
-- CHARACTERS
-- (one account can have multiple characters)
-- ============================================================
CREATE TABLE IF NOT EXISTS characters (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    account_id      INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    name            TEXT    UNIQUE NOT NULL COLLATE NOCASE,

    -- Appearance (mirrors VB6 Char struct)
    race            TEXT    DEFAULT '',
    gender          TEXT    DEFAULT '',
    class           TEXT    DEFAULT '',
    magic_school    TEXT    DEFAULT '',
    body            INTEGER DEFAULT 1,
    head            INTEGER DEFAULT 1,
    heading         INTEGER DEFAULT 3,   -- 3 = SOUTH (facing player)
    weapon_anim     INTEGER DEFAULT 2,
    shield_anim     INTEGER DEFAULT 2,
    desc            TEXT    DEFAULT '',

    -- World position
    pos_map         INTEGER DEFAULT 1,
    pos_x           INTEGER DEFAULT 12,
    pos_y           INTEGER DEFAULT 12,

    -- Core stats (HP, Stamina, Mana, Hit, Defense)
    max_hp          INTEGER DEFAULT 15,
    min_hp          INTEGER DEFAULT 15,
    max_sta         INTEGER DEFAULT 15,
    min_sta         INTEGER DEFAULT 15,
    max_man         INTEGER DEFAULT 15,
    min_man         INTEGER DEFAULT 15,
    max_hit         INTEGER DEFAULT 3,
    min_hit         INTEGER DEFAULT 1,
    def             INTEGER DEFAULT 0,
    met             INTEGER DEFAULT 0,   -- Meditation training
    fit             INTEGER DEFAULT 0,   -- Fitness/stamina training

    -- Economy
    gold            INTEGER DEFAULT 100,
    bank_gold       INTEGER DEFAULT 0,
    food            INTEGER DEFAULT 5,
    drink           INTEGER DEFAULT 5,

    -- Progression
    exp             INTEGER DEFAULT 0,
    elv             INTEGER DEFAULT 1,   -- Current level (ELV)
    elu             INTEGER DEFAULT 1000, -- Exp to next level (ELU)
    practice_points INTEGER DEFAULT 0,

    -- Guild / Clan
    clan            TEXT    DEFAULT '',
    clan_rank       TEXT    DEFAULT '',
    clan_member     INTEGER DEFAULT 0,

    -- Status flags (mirrors VB6 UserFlags)
    criminal        INTEGER DEFAULT 0,
    criminal_count  INTEGER DEFAULT 0,
    status          INTEGER DEFAULT 0,
    locks           INTEGER DEFAULT 0,

    -- Special starting skills
    spec_skill1     TEXT    DEFAULT '',
    spec_skill2     TEXT    DEFAULT '',
    spec_skill3     TEXT    DEFAULT '',

    -- Pet ownership
    animal_index    INTEGER DEFAULT 0,

    -- Misc
    last_pray       TEXT    DEFAULT '',
    your_id         INTEGER DEFAULT 0,
    start_head      INTEGER DEFAULT 0,
    start_name      TEXT    DEFAULT '',
    last_ip         TEXT    DEFAULT '',
    is_gm           INTEGER DEFAULT 0,

    created_at      DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_online     DATETIME
);

-- ============================================================
-- CHARACTER SKILLS  (28 skills, Skill1-Skill28)
-- ============================================================
CREATE TABLE IF NOT EXISTS character_skills (
    character_id    INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    skill_num       INTEGER NOT NULL CHECK (skill_num BETWEEN 1 AND 28),
    skill_value     INTEGER DEFAULT 0,
    PRIMARY KEY (character_id, skill_num)
);

-- ============================================================
-- CHARACTER INVENTORY  (20 slots)
-- ============================================================
CREATE TABLE IF NOT EXISTS character_inventory (
    character_id    INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    slot            INTEGER NOT NULL CHECK (slot BETWEEN 1 AND 20),
    obj_index       INTEGER DEFAULT 0,
    amount          INTEGER DEFAULT 0,
    equipped        INTEGER DEFAULT 0,
    PRIMARY KEY (character_id, slot)
);

-- ============================================================
-- EQUIPMENT SLOTS  (mirrors VB6 Weapon/Armour/Clothing/Head/Shield EqpSlot)
-- ============================================================
CREATE TABLE IF NOT EXISTS character_equipment (
    character_id    INTEGER PRIMARY KEY REFERENCES characters(id) ON DELETE CASCADE,
    weapon_slot     INTEGER DEFAULT 0,   -- Inventory slot holding weapon
    armour_slot     INTEGER DEFAULT 0,
    clothing_slot   INTEGER DEFAULT 0,
    head_slot       INTEGER DEFAULT 0,
    shield_slot     INTEGER DEFAULT 0
);

-- ============================================================
-- CHARACTER SPELLBOOK  (50 slots)
-- ============================================================
CREATE TABLE IF NOT EXISTS character_spells (
    character_id    INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    slot            INTEGER NOT NULL CHECK (slot BETWEEN 1 AND 50),
    spell_index     INTEGER DEFAULT 0,
    PRIMARY KEY (character_id, slot)
);

-- ============================================================
-- FACTION REPUTATION  (8 factions)
-- ============================================================
CREATE TABLE IF NOT EXISTS character_reputation (
    character_id    INTEGER NOT NULL REFERENCES characters(id) ON DELETE CASCADE,
    faction         TEXT    NOT NULL CHECK (faction IN (
                        'noble','under','common','bendarr',
                        'veega','zeendic','griigo','hyliios'
                    )),
    rep_value       INTEGER DEFAULT 0,
    PRIMARY KEY (character_id, faction)
);

CREATE TABLE IF NOT EXISTS character_reputation_summary (
    character_id    INTEGER PRIMARY KEY REFERENCES characters(id) ON DELETE CASCADE,
    overall_rep     INTEGER DEFAULT 0,
    rep_rank        TEXT    DEFAULT ''
);

-- ============================================================
-- CLANS / GUILDS
-- ============================================================
CREATE TABLE IF NOT EXISTS clans (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT    UNIQUE NOT NULL COLLATE NOCASE,
    leader      TEXT    DEFAULT '',
    description TEXT    DEFAULT '',
    created_at  DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- MESSAGE BOARD
-- ============================================================
CREATE TABLE IF NOT EXISTS message_board (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    author      TEXT    NOT NULL,
    title       TEXT    DEFAULT '',
    body        TEXT    DEFAULT '',
    posted_at   DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- GM HELP QUEUE
-- ============================================================
CREATE TABLE IF NOT EXISTS gm_queue (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    player       TEXT    NOT NULL,
    message      TEXT    DEFAULT '',
    map_num      INTEGER DEFAULT 0,
    pos_x        INTEGER DEFAULT 0,
    pos_y        INTEGER DEFAULT 0,
    submitted_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    resolved     INTEGER DEFAULT 0,
    resolved_by  TEXT    DEFAULT '',
    resolved_at  DATETIME
);

-- ============================================================
-- WORLD STATE (persistent map objects - replaces SaveWorld)
-- ============================================================
CREATE TABLE IF NOT EXISTS world_objects (
    map_num     INTEGER NOT NULL,
    tile_x      INTEGER NOT NULL CHECK (tile_x BETWEEN 1 AND 100),
    tile_y      INTEGER NOT NULL CHECK (tile_y BETWEEN 1 AND 100),
    obj_index   INTEGER DEFAULT 0,
    amount      INTEGER DEFAULT 0,
    locked      INTEGER DEFAULT 0,
    sign        INTEGER DEFAULT 0,
    sign_owner  TEXT    DEFAULT '',
    updated_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (map_num, tile_x, tile_y)
);

-- ============================================================
-- GOSSIP LOG
-- ============================================================
CREATE TABLE IF NOT EXISTS gossip (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    author      TEXT    NOT NULL,
    message     TEXT    NOT NULL,
    posted_at   DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- BAN LIST (replaces banned.txt)
-- ============================================================
CREATE TABLE IF NOT EXISTS ip_bans (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    ip_address  TEXT    UNIQUE NOT NULL,
    reason      TEXT    DEFAULT '',
    banned_by   TEXT    DEFAULT '',
    banned_at   DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_chars_account   ON characters(account_id);
CREATE INDEX IF NOT EXISTS idx_chars_name      ON characters(name);
CREATE INDEX IF NOT EXISTS idx_chars_pos       ON characters(pos_map, pos_x, pos_y);
CREATE INDEX IF NOT EXISTS idx_inv_char        ON character_inventory(character_id);
CREATE INDEX IF NOT EXISTS idx_skills_char     ON character_skills(character_id);
CREATE INDEX IF NOT EXISTS idx_spells_char     ON character_spells(character_id);
CREATE INDEX IF NOT EXISTS idx_rep_char        ON character_reputation(character_id);
CREATE INDEX IF NOT EXISTS idx_world_map       ON world_objects(map_num);
CREATE INDEX IF NOT EXISTS idx_board_posted    ON message_board(posted_at DESC);
CREATE INDEX IF NOT EXISTS idx_gmq_resolved    ON gm_queue(resolved, submitted_at);
