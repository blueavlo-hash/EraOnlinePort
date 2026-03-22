package db

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
)

// ErrCharNameTaken is returned when a character name is already in use.
var ErrCharNameTaken = errors.New("character name already taken")

// ErrCharNotFound is returned when the requested character doesn't exist.
var ErrCharNotFound = errors.New("character not found")

// ErrTooManyChars is returned when an account already has 3 characters.
var ErrTooManyChars = errors.New("character limit reached (max 3)")

// CharSummary is used for the character list screen.
type CharSummary struct {
	Name    string
	Level   int
	ClassID int
	Body    int
	Head    int
}

// CharData is the full character state loaded on world entry.
type CharData struct {
	ID         int64
	AccountID  int64
	Name       string
	ClassID    int
	Level      int
	Exp        int
	MapID      int
	PosX       int
	PosY       int
	Heading    int
	HP         int
	MaxHP      int
	MP         int
	MaxMP      int
	Stamina    int
	MaxStamina int
	Gold       int
	HeadIndex  int
	BodyIndex  int
	WeaponSlot int
	ShieldSlot int
	HelmetSlot int
	ArmorSlot  int
	Hunger     int
	Thirst     int

	Inventory [20]*InventorySlot
	Skills    [29]*SkillSlot // index 0 unused; skills are 1-28
	Spells    []int
	Abilities []int

	// Bank
	BankItems [40]*InventorySlot
	BankGold  int

	// Quests
	QuestActive    map[int]map[int]int // quest_id → {obj_idx → progress}
	QuestCompleted map[int]bool

	// Achievements
	AchievementIDs []int
}

// InventorySlot represents one character inventory entry.
type InventorySlot struct {
	Slot     int
	ObjIndex int
	Amount   int
	Equipped bool
	Enchant  int // enchantment level (0 = unenchanted)
}

// SkillSlot represents one skill entry.
type SkillSlot struct {
	SkillID int
	Level   int
	XP      int
}

// ListChars returns character summaries for an account (for the char select screen).
func (db *DB) ListChars(ctx context.Context, accountID int64) ([]CharSummary, error) {
	rows, err := db.sql.QueryContext(ctx,
		`SELECT name, level, class_id, body_index, head_index
		 FROM characters WHERE account_id = ? ORDER BY id`,
		accountID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var chars []CharSummary
	for rows.Next() {
		var c CharSummary
		if err := rows.Scan(&c.Name, &c.Level, &c.ClassID, &c.Body, &c.Head); err != nil {
			return nil, err
		}
		chars = append(chars, c)
	}
	return chars, rows.Err()
}

// CreateChar creates a new character for the given account.
func (db *DB) CreateChar(ctx context.Context, accountID int64, name string, classID, head, body int) error {
	// Enforce 3-char limit.
	var count int
	err := db.sql.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM characters WHERE account_id = ?`, accountID,
	).Scan(&count)
	if err != nil {
		return err
	}
	if count >= 3 {
		return ErrTooManyChars
	}

	_, err = db.sql.ExecContext(ctx,
		`INSERT INTO characters (account_id, name, class_id, head_index, body_index)
		 VALUES (?, ?, ?, ?, ?)`,
		accountID, name, classID, head, body,
	)
	if err != nil {
		if isConstraintErr(err) {
			return ErrCharNameTaken
		}
		return fmt.Errorf("create char: %w", err)
	}
	return nil
}

// LoadChar loads a full character by name, verifying it belongs to accountID.
func (db *DB) LoadChar(ctx context.Context, accountID int64, name string) (*CharData, error) {
	var c CharData
	err := db.sql.QueryRowContext(ctx, `
		SELECT id, account_id, name, class_id, level, exp,
		       map_id, pos_x, pos_y, heading,
		       hp, max_hp, mp, max_mp, stamina, max_stamina,
		       gold, head_index, body_index,
		       weapon_slot, shield_slot, helmet_slot, armor_slot,
		       hunger, thirst
		FROM characters
		WHERE name = ? COLLATE NOCASE AND account_id = ?`,
		name, accountID,
	).Scan(
		&c.ID, &c.AccountID, &c.Name, &c.ClassID, &c.Level, &c.Exp,
		&c.MapID, &c.PosX, &c.PosY, &c.Heading,
		&c.HP, &c.MaxHP, &c.MP, &c.MaxMP, &c.Stamina, &c.MaxStamina,
		&c.Gold, &c.HeadIndex, &c.BodyIndex,
		&c.WeaponSlot, &c.ShieldSlot, &c.HelmetSlot, &c.ArmorSlot,
		&c.Hunger, &c.Thirst,
	)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrCharNotFound
	}
	if err != nil {
		return nil, err
	}

	// Load inventory.
	if err := db.loadInventory(ctx, &c); err != nil {
		return nil, err
	}
	// Load skills.
	if err := db.loadSkills(ctx, &c); err != nil {
		return nil, err
	}
	// Load spells.
	if err := db.loadSpells(ctx, &c); err != nil {
		return nil, err
	}
	// Load abilities.
	if err := db.loadAbilities(ctx, &c); err != nil {
		return nil, err
	}
	// Load bank.
	if err := db.loadBank(ctx, &c); err != nil {
		return nil, err
	}
	// Load quests.
	if err := db.loadQuests(ctx, &c); err != nil {
		return nil, err
	}
	// Load achievements.
	if err := db.loadAchievements(ctx, &c); err != nil {
		return nil, err
	}

	return &c, nil
}

func (db *DB) loadInventory(ctx context.Context, c *CharData) error {
	rows, err := db.sql.QueryContext(ctx,
		`SELECT slot, obj_index, amount, equipped, enchant FROM inventory WHERE character_id = ?`, c.ID)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var s InventorySlot
		var eq int
		if err := rows.Scan(&s.Slot, &s.ObjIndex, &s.Amount, &eq, &s.Enchant); err != nil {
			return err
		}
		s.Equipped = eq != 0
		if s.Slot >= 0 && s.Slot < 20 {
			c.Inventory[s.Slot] = &s
		}
	}
	return rows.Err()
}

func (db *DB) loadSkills(ctx context.Context, c *CharData) error {
	rows, err := db.sql.QueryContext(ctx,
		`SELECT skill_id, level, xp FROM skills WHERE character_id = ?`, c.ID)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var s SkillSlot
		if err := rows.Scan(&s.SkillID, &s.Level, &s.XP); err != nil {
			return err
		}
		if s.SkillID >= 1 && s.SkillID <= 28 {
			c.Skills[s.SkillID] = &s
		}
	}
	return rows.Err()
}

func (db *DB) loadSpells(ctx context.Context, c *CharData) error {
	rows, err := db.sql.QueryContext(ctx,
		`SELECT spell_id FROM spells WHERE character_id = ?`, c.ID)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			return err
		}
		c.Spells = append(c.Spells, id)
	}
	return rows.Err()
}

func (db *DB) loadAbilities(ctx context.Context, c *CharData) error {
	rows, err := db.sql.QueryContext(ctx,
		`SELECT ability_id FROM abilities WHERE character_id = ?`, c.ID)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			return err
		}
		c.Abilities = append(c.Abilities, id)
	}
	return rows.Err()
}

func (db *DB) loadBank(ctx context.Context, c *CharData) error {
	rows, err := db.sql.QueryContext(ctx,
		`SELECT slot, obj_index, amount FROM bank WHERE character_id = ?`, c.ID)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var s InventorySlot
		if err := rows.Scan(&s.Slot, &s.ObjIndex, &s.Amount); err != nil {
			return err
		}
		if s.Slot >= 0 && s.Slot < 40 {
			c.BankItems[s.Slot] = &s
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	// Bank gold.
	err = db.sql.QueryRowContext(ctx,
		`SELECT gold FROM bank_gold WHERE character_id = ?`, c.ID).Scan(&c.BankGold)
	if errors.Is(err, sql.ErrNoRows) {
		c.BankGold = 0
		return nil
	}
	return err
}

func (db *DB) loadQuests(ctx context.Context, c *CharData) error {
	c.QuestActive = make(map[int]map[int]int)
	c.QuestCompleted = make(map[int]bool)
	rows, err := db.sql.QueryContext(ctx,
		`SELECT quest_id, state, progress FROM quests WHERE character_id = ?`, c.ID)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var questID, state int
		var progJSON string
		if err := rows.Scan(&questID, &state, &progJSON); err != nil {
			return err
		}
		if state == 1 {
			c.QuestCompleted[questID] = true
		} else {
			var objMap map[int]int
			if err := json.Unmarshal([]byte(progJSON), &objMap); err != nil {
				objMap = make(map[int]int)
			}
			c.QuestActive[questID] = objMap
		}
	}
	return rows.Err()
}

func (db *DB) loadAchievements(ctx context.Context, c *CharData) error {
	rows, err := db.sql.QueryContext(ctx,
		`SELECT achievement_id FROM achievements WHERE character_id = ?`, c.ID)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			return err
		}
		c.AchievementIDs = append(c.AchievementIDs, id)
	}
	return rows.Err()
}

// SaveChar persists a character's mutable state. Called on logout and periodic autosave.
func (db *DB) SaveChar(ctx context.Context, c *CharData) error {
	tx, err := db.sql.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck

	_, err = tx.ExecContext(ctx, `
		UPDATE characters SET
		    level=?, exp=?, map_id=?, pos_x=?, pos_y=?, heading=?,
		    hp=?, max_hp=?, mp=?, max_mp=?, stamina=?, max_stamina=?,
		    gold=?, weapon_slot=?, shield_slot=?, helmet_slot=?, armor_slot=?,
		    hunger=?, thirst=?, last_saved=unixepoch()
		WHERE id=?`,
		c.Level, c.Exp, c.MapID, c.PosX, c.PosY, c.Heading,
		c.HP, c.MaxHP, c.MP, c.MaxMP, c.Stamina, c.MaxStamina,
		c.Gold, c.WeaponSlot, c.ShieldSlot, c.HelmetSlot, c.ArmorSlot,
		c.Hunger, c.Thirst, c.ID,
	)
	if err != nil {
		return err
	}

	// Re-save inventory (delete + insert approach for simplicity).
	if _, err := tx.ExecContext(ctx, `DELETE FROM inventory WHERE character_id=?`, c.ID); err != nil {
		return err
	}
	for _, slot := range c.Inventory {
		if slot == nil || slot.ObjIndex == 0 {
			continue
		}
		eq := 0
		if slot.Equipped {
			eq = 1
		}
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO inventory (character_id, slot, obj_index, amount, equipped, enchant) VALUES (?,?,?,?,?,?)`,
			c.ID, slot.Slot, slot.ObjIndex, slot.Amount, eq, slot.Enchant,
		); err != nil {
			return err
		}
	}

	// Re-save skills.
	if _, err := tx.ExecContext(ctx, `DELETE FROM skills WHERE character_id=?`, c.ID); err != nil {
		return err
	}
	for i, sk := range c.Skills {
		if sk == nil || i == 0 {
			continue
		}
		if _, err := tx.ExecContext(ctx,
			`INSERT OR REPLACE INTO skills (character_id, skill_id, level, xp) VALUES (?,?,?,?)`,
			c.ID, sk.SkillID, sk.Level, sk.XP,
		); err != nil {
			return err
		}
	}

	// Re-save bank items.
	if _, err := tx.ExecContext(ctx, `DELETE FROM bank WHERE character_id=?`, c.ID); err != nil {
		return err
	}
	for _, slot := range c.BankItems {
		if slot == nil || slot.ObjIndex == 0 {
			continue
		}
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO bank (character_id, slot, obj_index, amount) VALUES (?,?,?,?)`,
			c.ID, slot.Slot, slot.ObjIndex, slot.Amount,
		); err != nil {
			return err
		}
	}

	// Bank gold (upsert).
	if _, err := tx.ExecContext(ctx,
		`INSERT OR REPLACE INTO bank_gold (character_id, gold) VALUES (?,?)`,
		c.ID, c.BankGold,
	); err != nil {
		return err
	}

	// Re-save quests.
	if _, err := tx.ExecContext(ctx, `DELETE FROM quests WHERE character_id=?`, c.ID); err != nil {
		return err
	}
	// Insert completed quests first.
	for questID := range c.QuestCompleted {
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO quests (character_id, quest_id, state, progress) VALUES (?,?,1,'{}')`,
			c.ID, questID,
		); err != nil {
			return err
		}
	}
	// Insert active quests, skipping any that are also in QuestCompleted (completed takes precedence).
	for questID, objMap := range c.QuestActive {
		if c.QuestCompleted[questID] {
			continue // already saved as completed above
		}
		progJSON, _ := json.Marshal(objMap)
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO quests (character_id, quest_id, state, progress) VALUES (?,?,0,?)`,
			c.ID, questID, string(progJSON),
		); err != nil {
			return err
		}
	}

	// Re-save achievements.
	if _, err := tx.ExecContext(ctx, `DELETE FROM achievements WHERE character_id=?`, c.ID); err != nil {
		return err
	}
	for _, achID := range c.AchievementIDs {
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO achievements (character_id, achievement_id) VALUES (?,?)`,
			c.ID, achID,
		); err != nil {
			return err
		}
	}

	return tx.Commit()
}

// LeaderboardEntry is one row in a leaderboard response.
type LeaderboardEntry struct {
	Name  string
	Score int
}

// GetLeaderboard returns the top characters sorted by level then exp.
func (db *DB) GetLeaderboard(ctx context.Context, limit int) ([]LeaderboardEntry, error) {
	rows, err := db.sql.QueryContext(ctx,
		`SELECT name, level FROM characters ORDER BY level DESC, exp DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []LeaderboardEntry
	for rows.Next() {
		var e LeaderboardEntry
		if err := rows.Scan(&e.Name, &e.Score); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// HotbarSlot is one slot in the hotbar.
type HotbarSlot struct {
	Slot     int
	ItemType int // 0=ability, 1=spell
	ItemID   int
}

// SaveHotbar replaces all hotbar slots for a character.
func (db *DB) SaveHotbar(ctx context.Context, charID int64, slots []HotbarSlot) error {
	tx, err := db.sql.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback() //nolint:errcheck

	if _, err := tx.ExecContext(ctx, `DELETE FROM hotbar WHERE character_id=?`, charID); err != nil {
		return err
	}
	for _, s := range slots {
		if s.Slot < 0 || s.Slot > 9 {
			continue
		}
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO hotbar (character_id, slot, item_type, item_id) VALUES (?,?,?,?)`,
			charID, s.Slot, s.ItemType, s.ItemID,
		); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// LearnAbility persists a newly learned ability for a character.
func (db *DB) LearnAbility(ctx context.Context, charID int64, abilityID int) error {
	_, err := db.sql.ExecContext(ctx,
		`INSERT OR IGNORE INTO abilities (character_id, ability_id) VALUES (?,?)`,
		charID, abilityID,
	)
	return err
}

// DeleteChar removes a character by name, verifying ownership.
func (db *DB) DeleteChar(ctx context.Context, accountID int64, name string) error {
	res, err := db.sql.ExecContext(ctx,
		`DELETE FROM characters WHERE name = ? COLLATE NOCASE AND account_id = ?`,
		name, accountID,
	)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrCharNotFound
	}
	return nil
}
