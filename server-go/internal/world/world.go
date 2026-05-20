// Package world implements the single-goroutine game world loop.
//
// All mutable game state lives here. Player conn goroutines communicate via
// the Inbox channel — no mutexes needed for game state access.
package world

import (
	"context"
	"fmt"
	"log/slog"
	"math/rand"
	"sort"
	"sync/atomic"
	"time"

	"github.com/blueavlo-hash/eraonline-server/internal/db"
	"github.com/blueavlo-hash/eraonline-server/internal/gamedata"
	"github.com/blueavlo-hash/eraonline-server/internal/proto"
)

// ---------------------------------------------------------------------------
// Addiction loop definitions
// ---------------------------------------------------------------------------

type bossDef struct {
	MapID         int
	NPCIndex      int
	Name          string
	SpawnInterval float64 // seconds between spawns
}

var bossDefs = []bossDef{
	{3,   47, "The Dark Stalker",   3600},
	{18,  53, "The Alpha Wolf",     4500},
	{80,  55, "The Iron Golem",     5400},
	{115, 45, "The Serpent Queen",  6300},
	{140, 51, "The Gremlin Warlord",7200},
}

// worldEventWaves maps map IDs to NPC indices that spawn during an invasion.
var worldEventWaves = map[int][]int{
	3:  {47, 47, 48, 48},
	18: {53, 53, 47, 48},
	80: {51, 51, 55, 47},
}

type tourneyScore struct {
	Name      string
	BestCatch int
}

const (
	worldEventInterval = 3600.0 // seconds between world events
	worldEventDuration = 300.0  // seconds an event lasts
	tourneyInterval    = 7200.0 // seconds between tournaments
	tourneyDuration    = 600.0  // seconds a tournament lasts
)

var tourneyPrizes = [3]int{1000, 500, 250}

// ClientMsg is a message from a connection goroutine to the world goroutine.
type ClientMsg struct {
	ConnID  uint64
	MsgType uint16
	Payload []byte
	// PlayerKey is non-nil only for the JoinMsg / LeaveMsg meta-messages.
	JoinInfo  *JoinInfo
	LeaveConn bool
}

// JoinInfo carries all the data needed to bring a player into the world.
type JoinInfo struct {
	AccountID   int64
	Username    string
	CharData    *db.CharData
	SessionKey  []byte
	SendCh      chan []byte
	InitSendSeq uint32 // seq counter value after char-select phase; world continues from here
}

// Config holds world-level tunables.
type Config struct {
	TickRateMS       int
	CombatTickMS     int
	SpawnMap         int
	SpawnX, SpawnY   int
	NightBrightness  float64
	DayLengthSeconds int
	AutosaveInterval time.Duration
}

// World is the single-goroutine world state machine.
type World struct {
	cfg        Config
	db         *db.DB
	gameData   *gamedata.GameData
	log        *slog.Logger

	// Inbox receives messages from all conn goroutines.
	Inbox chan ClientMsg

	// players: instanceID → *Player (only alive, in-world players)
	players map[int32]*Player
	// connToInstance: connID → instanceID (for fast lookup on disconnect)
	connToInstance map[uint64]int32

	// NPCs: instanceID → *NPC
	npcs         map[int32]*NPC
	nextNPCID    int32

	// Next player instance ID (1–9999, wraps).
	nextPlayerID int32

	// Ground items.
	groundItems   map[int16]*GroundItem
	nextGroundID  int16

	// Day/night: minutes elapsed (0–1439) in the current in-game day.
	gameMinutes float64

	// Weather.
	raining      bool
	weatherTicks int

	// regenTicks counts world ticks; regen fires every 20 ticks (5 seconds).
	regenTicks int

	// tipTicks fires a gameplay tip every ~10 minutes (2400 ticks at 250ms/tick).
	tipTicks int

	// Pending trade requests: target_instance_id → requester_instance_id.
	pendingTrades map[int32]int32

	// playerCount is updated atomically so the HTTP API can read it safely.
	playerCount atomic.Int32

	// Social / sandbox systems.
	duels            map[int32]*DuelState  // challengerID → active duel
	pendingDuels     map[int32]int32       // challengerID → targetID
	signs            map[string]*WorldSign // "mapid:x:y" → sign
	pendingMarriages map[int32]int32       // proposerID → targetID

	// Boss spawn state: mapID → seconds until next spawn / current instance ID.
	bossTimers    map[int]float64
	bossInstances map[int]int32 // 0 = not spawned

	// World event state.
	worldEventActive bool
	worldEventMapID  int
	worldEventNPCs   []int32
	worldEventEndAt  float64 // unix seconds
	worldEventAcc    float64 // accumulator in seconds

	// Fishing tournament state.
	tourneyActive bool
	tourneyScores map[int32]tourneyScore // instanceID → best catch
	tourneyEndAt  float64
	tourneyAcc    float64
}

// GroundItem is a dropped item lying on the ground.
type GroundItem struct {
	ID       int16
	MapID    int
	X, Y     int
	ObjIndex int
	Amount   int
	Timeout  int // world ticks until auto-despawn
	Enchant  int // pre-applied enchant level (0 = none); set on NPC rare drops
}

// New creates a new World. Call Run() to start the game loop.
func New(cfg Config, database *db.DB, gd *gamedata.GameData, log *slog.Logger) *World {
	return &World{
		cfg:            cfg,
		db:             database,
		gameData:       gd,
		log:            log,
		Inbox:          make(chan ClientMsg, 4096),
		players:        make(map[int32]*Player),
		connToInstance: make(map[uint64]int32),
		npcs:           make(map[int32]*NPC),
		nextNPCID:      npcInstanceBase,
		nextPlayerID:  1,
		groundItems:   make(map[int16]*GroundItem),
		pendingTrades:    make(map[int32]int32),
		duels:            make(map[int32]*DuelState),
		pendingDuels:     make(map[int32]int32),
		signs:            make(map[string]*WorldSign),
		pendingMarriages: make(map[int32]int32),
		gameMinutes:      480, // start at 8:00 AM so players don't spawn into darkness
		bossTimers:    make(map[int]float64),
		bossInstances: make(map[int]int32),
		tourneyScores: make(map[int32]tourneyScore),
	}
}

// Run starts the world loop. It blocks until ctx is cancelled and returns nil.
func (w *World) Run(ctx context.Context) error {
	tickDur := time.Duration(w.cfg.TickRateMS) * time.Millisecond
	ticker := time.NewTicker(tickDur)
	defer ticker.Stop()

	autosave := time.NewTicker(w.cfg.AutosaveInterval)
	defer autosave.Stop()

	combatTicksPerAttack := w.cfg.CombatTickMS / w.cfg.TickRateMS
	timeIncPerTick := 1440.0 / float64(w.cfg.DayLengthSeconds*1000/w.cfg.TickRateMS)

	w.log.Info("world loop started", "tick_ms", w.cfg.TickRateMS)
	w.spawnAllNPCs()
	w.spawnHardcodedNPCs()
	w.initBossTimers()

	for {
		select {
		case <-ctx.Done():
			w.log.Info("world loop shutting down — saving all players")
			w.saveAll(context.Background())
			return nil

		case msg := <-w.Inbox:
			w.handleMsg(msg)

		// Drain inbox before ticking — keeps latency low.
		case <-ticker.C:
			w.drainInbox()
			w.tick(timeIncPerTick, combatTicksPerAttack)

		case <-autosave.C:
			w.saveAll(ctx)
		}
	}
}

// drainInbox processes all pending messages without blocking.
func (w *World) drainInbox() {
	for {
		select {
		case msg := <-w.Inbox:
			w.handleMsg(msg)
		default:
			return
		}
	}
}

// handleMsg dispatches one client message.
func (w *World) handleMsg(msg ClientMsg) {
	// Meta messages: join/leave.
	if msg.JoinInfo != nil {
		w.handleJoin(msg.ConnID, msg.JoinInfo)
		return
	}
	if msg.LeaveConn {
		w.handleLeave(msg.ConnID)
		return
	}

	// Game messages — look up player.
	instanceID, ok := w.connToInstance[msg.ConnID]
	if !ok {
		return // player already left
	}
	p, ok := w.players[instanceID]
	if !ok {
		return
	}

	switch msg.MsgType {
	case proto.MsgCMove:
		w.handleMove(p, msg.Payload)
	case proto.MsgCAttack:
		w.handleAttack(p, msg.Payload)
	case proto.MsgCFlee:
		w.handleFlee(p)
	case proto.MsgCUnstuck:
		w.handleUnstuck(p)
	case proto.MsgCChat:
		w.handleChat(p, msg.Payload)
	case proto.MsgCPickup:
		w.handlePickup(p, msg.Payload)
	case proto.MsgCDrop:
		w.handleDrop(p, msg.Payload)
	case proto.MsgCEquip:
		w.handleEquip(p, msg.Payload)
	case proto.MsgCUnequip:
		w.handleUnequip(p, msg.Payload)
	case proto.MsgCUseItem:
		w.handleUseItem(p, msg.Payload)
	case proto.MsgCShopOpen:
		w.handleShopOpen(p, msg.Payload)
	case proto.MsgCBuy:
		w.handleBuy(p, msg.Payload)
	case proto.MsgCSell:
		w.handleSell(p, msg.Payload)
	case proto.MsgCBankOpen:
		w.handleBankOpen(p, msg.Payload)
	case proto.MsgCBankDeposit:
		w.handleBankDeposit(p, msg.Payload)
	case proto.MsgCBankWithdraw:
		w.handleBankWithdraw(p, msg.Payload)
	case proto.MsgCBankDepositGold:
		w.handleBankDepositGold(p, msg.Payload)
	case proto.MsgCBankWithdrawGold:
		w.handleBankWithdrawGold(p, msg.Payload)
	case proto.MsgCCastSpell:
		w.handleCastSpell(p, msg.Payload)
	case proto.MsgCUseSkill:
		w.handleUseSkill(p, msg.Payload)
	case proto.MsgCTradeRequest:
		w.handleTradeRequest(p, msg.Payload)
	case proto.MsgCTradeRespond:
		w.handleTradeRespond(p, msg.Payload)
	case proto.MsgCTradeOffer:
		w.handleTradeOffer(p, msg.Payload)
	case proto.MsgCTradeRetract:
		w.handleTradeRetract(p, msg.Payload)
	case proto.MsgCTradeConfirm:
		w.handleTradeConfirm(p, msg.Payload)
	case proto.MsgCTradeCancel:
		w.handleTradeCancel(p, msg.Payload)
	case proto.MsgCQuestTalk:
		w.handleQuestTalk(p, msg.Payload)
	case proto.MsgCQuestAccept:
		w.handleQuestAccept(p, msg.Payload)
	case proto.MsgCQuestTurnin:
		w.handleQuestTurnin(p, msg.Payload)
	case proto.MsgCEnchant:
		w.handleEnchant(p, msg.Payload)
	case proto.MsgCLeaderboardReq:
		w.handleLeaderboardReq(p, msg.Payload)
	case proto.MsgCBuySpell:
		w.handleBuySpell(p, msg.Payload)
	case proto.MsgCLearnAbility:
		w.handleLearnAbility(p, msg.Payload)
	case proto.MsgCSaveHotbar:
		w.handleSaveHotbar(p, msg.Payload)
	case proto.MsgCPing:
		// Echo pong.
		w.sendTo(p, proto.MsgSPong, msg.Payload)
	case proto.MsgCPenance:
		w.handlePenance(p, msg.Payload)
	// Social / sandbox
	case proto.MsgCDuelRequest:
		w.handleDuelRequest(p, msg.Payload)
	case proto.MsgCDuelRespond:
		w.handleDuelRespond(p, msg.Payload)
	case proto.MsgCDuelBet:
		w.handleDuelBet(p, msg.Payload)
	case proto.MsgCCarryRequest:
		w.handleCarryRequest(p, msg.Payload)
	case proto.MsgCThrow:
		w.handleThrow(p)
	case proto.MsgCDropCarried:
		w.handleDropCarried(p)
	case proto.MsgCBountyPost:
		w.handleBountyPost(p, msg.Payload)
	case proto.MsgCBountyList:
		w.handleBountyList(p)
	case proto.MsgCPickpocket:
		w.handlePickpocket(p, msg.Payload)
	case proto.MsgCPlaceSign:
		w.handlePlaceSign(p, msg.Payload)
	case proto.MsgCReadSign:
		w.handleReadSign(p, msg.Payload)
	case proto.MsgCMarryPropose:
		w.handleMarryPropose(p, msg.Payload)
	case proto.MsgCMarryRespond:
		w.handleMarryRespond(p, msg.Payload)
	}
}

// handleJoin adds a new player to the world and sends them world state.
func (w *World) handleJoin(connID uint64, info *JoinInfo) {
	cd := info.CharData

	// Guard: redirect to spawn if saved map is empty.
	m := w.gameData.GetMap(cd.MapID)
	if m == nil || !m.HasGroundTiles() {
		w.log.Warn("redirecting player to spawn (empty map)",
			"char", cd.Name, "map", cd.MapID)
		cd.MapID = w.cfg.SpawnMap
		cd.PosX = w.cfg.SpawnX
		cd.PosY = w.cfg.SpawnY
	}

	instanceID := w.allocPlayerID()
	p := &Player{
		sendKey: info.SessionKey,
		SendSeq: info.InitSendSeq,
	}
	p.FromCharData(cd, connID, instanceID, info.SendCh)

	w.players[instanceID] = p
	w.connToInstance[connID] = instanceID
	w.playerCount.Store(int32(len(w.players)))

	w.log.Info("player joined world", "char", p.CharName, "map", cd.MapID, "instance", instanceID)

	// Send world state to the new player.
	{
		wr := proto.NewWriter(12)
		wr.WriteI32(int32(p.MapID))
		wr.WriteI16(int16(p.X))
		wr.WriteI16(int16(p.Y))
		wr.WriteI32(instanceID)
		w.sendTo(p, proto.MsgSWorldState, wr.Bytes())
	}

	// Send their full stat set.
	w.sendTo(p, proto.MsgSStats, p.BuildStats())

	// Send inventory.
	w.sendTo(p, proto.MsgSInventory, p.BuildInventory())

	// Send skills.
	if skills := p.BuildSkills(); skills != nil {
		w.sendTo(p, proto.MsgSSkills, skills)
	}

	// Send spellbook.
	w.sendTo(p, proto.MsgSSpellbook, p.BuildSpellbook())

	// Send abilities.
	w.sendTo(p, proto.MsgSAbilityList, p.BuildAbilityList())

	// Send saved hotbar.
	if hotbarSlots, err := w.db.LoadHotbar(context.Background(), p.charDBID); err == nil && len(hotbarSlots) > 0 {
		wr := proto.NewWriter(4 + len(hotbarSlots)*3)
		wr.WriteU8(uint8(len(hotbarSlots)))
		for _, s := range hotbarSlots {
			wr.WriteU8(uint8(s.Slot))
			wr.WriteU8(uint8(s.ItemType))
			wr.WriteU8(uint8(s.ItemID))
		}
		w.sendTo(p, proto.MsgSHotbar, wr.Bytes())
	}

	// Send initial vitals (hunger/thirst).
	{
		wr := proto.NewWriter(2)
		wr.WriteU8(uint8(p.Hunger))
		wr.WriteU8(uint8(p.Thirst))
		w.sendTo(p, proto.MsgSVitals, wr.Bytes())
	}

	// Send time of day.
	{
		wr := proto.NewWriter(2)
		wr.WriteU16(uint16(w.gameMinutes))
		w.sendTo(p, proto.MsgSTimeOfDay, wr.Bytes())
	}

	// Send rain state if applicable.
	if m != nil && m.Rain {
		w.sendTo(p, proto.MsgSRainOn, nil)
	}

	// Announce arrival to everyone on map.
	setCharPayload := p.BuildSetChar()
	w.broadcastMap(p.MapID, proto.MsgSSetChar, setCharPayload, instanceID)

	// Send all existing chars on map to new player.
	for _, other := range w.players {
		if other.InstanceID == instanceID || other.MapID != p.MapID {
			continue
		}
		w.sendTo(p, proto.MsgSSetChar, other.BuildSetChar())
	}
	for _, npc := range w.npcs {
		if npc.MapID == p.MapID && !npc.Dead {
			w.sendTo(p, proto.MsgSSetChar, npc.BuildSetChar())
		}
	}
	// Send existing ground items.
	for _, gi := range w.groundItems {
		if gi.MapID == p.MapID {
			wr := proto.NewWriter(12)
			wr.WriteI16(gi.ID)
			wr.WriteI16(int16(gi.ObjIndex))
			wr.WriteU16(uint16(gi.Amount))
			wr.WriteI16(int16(gi.X))
			wr.WriteI16(int16(gi.Y))
			w.sendTo(p, proto.MsgSGroundItemAdd, wr.Bytes())
		}
	}

	// Send quest indicators for NPCs on this map.
	w.sendQuestIndicators(p)

	// Send karma state.
	w.sendKarmaUpdate(p)

	// Send sign positions on this map.
	w.sendSignsForMap(p)

	// Daily login streak.
	w.checkDailyLogin(p)

	// Onboarding messages for new characters (level 1 entering for the first time).
	if p.Level == 1 {
		welcomeMsgs := []string{
			"Welcome to Era Online! You are " + p.CharName + ".",
			"Controls: Arrow keys or WASD to move. Click to attack. Press C for character stats, I for inventory.",
			"Survival: Keep your hunger and thirst above 0 or you will starve. Eat food and drink water you find.",
			"Tip: Press F1 if you ever get stuck on a tile.",
			"Explore the world and slay enemies to gain experience and level up. Good luck!",
		}
		for _, msg := range welcomeMsgs {
			w.sendTo(p, proto.MsgSServerMsg, buildServerMsg(msg))
		}
	}
}

// handleLeave removes a player from the world and persists their state.
func (w *World) handleLeave(connID uint64) {
	instanceID, ok := w.connToInstance[connID]
	if !ok {
		return
	}
	p, ok := w.players[instanceID]
	if !ok {
		return
	}

	w.log.Info("player left world", "char", p.CharName)

	// Clean up social state.
	w.cancelDuel(p)
	w.releaseCarry(p)
	// Remove any pending challenge or proposal from this player.
	delete(w.pendingDuels, p.InstanceID)
	delete(w.pendingMarriages, p.InstanceID)

	// Persist.
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := w.savePlayer(ctx, p); err != nil {
		w.log.Error("failed to save player on leave", "char", p.CharName, "err", err)
	}

	// Broadcast removal.
	w.broadcastMap(p.MapID, proto.MsgSRemoveChar, buildRemoveChar(instanceID), instanceID)

	delete(w.players, instanceID)
	delete(w.connToInstance, connID)
	w.playerCount.Store(int32(len(w.players)))
}

// tick runs one world tick: NPC AI, regen, day/night.
func (w *World) tick(timeIncPerTick float64, combatTicksPerAttack int) {
	w.gameMinutes += timeIncPerTick
	if w.gameMinutes >= 1440 {
		w.gameMinutes -= 1440
	}

	// Broadcast time of day every minute of game time (approximately).
	// We send every tick for simplicity — clients can interpolate.
	{
		wr := proto.NewWriter(2)
		wr.WriteU16(uint16(w.gameMinutes))
		w.broadcastAll(proto.MsgSTimeOfDay, wr.Bytes())
	}

	// NPC AI tick.
	for _, npc := range w.npcs {
		w.tickNPC(npc, combatTicksPerAttack)
	}

	// Periodic gameplay tips (~10 min real time = 2400 ticks at 250ms/tick).
	w.tipTicks++
	if w.tipTicks%2400 == 0 {
		tips := []string{
			"Stuck somewhere? Press F1 to teleport to the nearest walkable tile.",
			"Tip: Press F1 if you ever get stuck on a tile.",
			"Remember: F1 unstucks you if you're trapped anywhere on the map.",
		}
		tip := tips[(w.tipTicks/2400)%len(tips)]
		w.broadcastAll(proto.MsgSServerMsg, buildServerMsg(tip))
	}

	// Player vitals, regen, combat cooldown, status effects, and poison.
	w.regenTicks++
	runRegen := w.regenTicks%20 == 0 // Gap 9: regen fires every 20 ticks (5 seconds)
	deltaSec := float64(w.cfg.TickRateMS) / 1000.0
	for _, p := range w.players {
		// Decrement combat cooldown; notify player when swing is ready.
		if p.CombatCooldown > 0 {
			p.CombatCooldown--
			if p.CombatCooldown == 0 {
				p.InCombat = false
				w.sendTo(p, proto.MsgSSwingReady, nil)
				w.sendCombatState(p)
			}
		}
		w.tickStatusEffects(p, deltaSec)
		w.tickVitals(p)
		if runRegen {
			w.tickPlayerRegen(p)
		}
	}
	w.tickPoison()

	// Skill action timers.
	w.tickSkillActions()

	// Ground item despawn.
	for id, gi := range w.groundItems {
		gi.Timeout--
		if gi.Timeout <= 0 {
			wr := proto.NewWriter(2)
			wr.WriteI16(gi.ID)
			w.broadcastMap(gi.MapID, proto.MsgSGroundItemRemove, wr.Bytes(), -1)
			delete(w.groundItems, id)
		}
	}

	// Weather check (every WeatherCheckTicks ticks).
	w.weatherTicks++
	if w.weatherTicks >= WeatherCheckTicks {
		w.weatherTicks = 0
		w.tickWeather()
	}

	// Addiction loop timed systems.
	w.tickBosses(deltaSec)
	w.tickWorldEvent(deltaSec)
	w.tickTourney(deltaSec)

	// Social systems.
	w.tickDuels(deltaSec)
}

// tickNPC runs one AI step for an NPC.
func (w *World) tickNPC(npc *NPC, combatTicksPerAttack int) {
	if npc.Dead {
		if npc.RespawnTicks < 0 {
			return // boss/event NPC — managed externally
		}
		npc.RespawnTicks--
		if npc.RespawnTicks <= 0 {
			w.respawnNPC(npc)
		}
		return
	}

	if npc.CombatCooldown > 0 {
		npc.CombatCooldown--
	}

	// Hostile NPCs: find nearby players.
	if npc.Def.Hostile && npc.Target == 0 {
		for _, p := range w.players {
			if p.MapID != npc.MapID {
				continue
			}
			dx := p.X - npc.X
			dy := p.Y - npc.Y
			// Gap 13: aggro range = 8 tiles (Chebyshev distance).
			if iabs(dx) <= 8 && iabs(dy) <= 8 {
				npc.Target = p.InstanceID
				break
			}
		}
	}

	// Attack target if in range.
	if npc.Target != 0 && npc.CombatCooldown == 0 {
		target, ok := w.players[npc.Target]
		if !ok || target.MapID != npc.MapID {
			npc.Target = 0
		} else {
			dx := target.X - npc.X
			dy := target.Y - npc.Y
			// Attack range = 1 tile (Chebyshev).
			if iabs(dx) <= 1 && iabs(dy) <= 1 {
				w.npcAttackPlayer(npc, target)
				// Gap 14: NPC attack cooldown = 6 ticks (1.5 seconds at 4 TPS).
				npc.CombatCooldown = 6
			} else {
				// Chase target.
				w.moveNPCToward(npc, target.X, target.Y)
			}
		}
	} else if npc.Def.Movement == 1 { // wandering movement
		npc.WanderTimer--
		if npc.WanderTimer <= 0 {
			npc.WanderTimer = 20 + rand.Intn(40)
			dir := wanderDirections[rand.Intn(4)]
			dx, dy := wanderDelta(dir)
			nx, ny := npc.X+dx, npc.Y+dy
			if w.isTileWalkable(npc.MapID, nx, ny) {
				npc.X = nx
				npc.Y = ny
				npc.Heading = dir
				w.broadcastMap(npc.MapID, proto.MsgSMoveChar,
					buildMoveChar(npc.InstanceID, npc.X, npc.Y, npc.Heading), -1)
			}
		}
	}
}

func (w *World) npcAttackPlayer(npc *NPC, p *Player) {
	pDef := getObjDef(w, p.ShieldSlot) + getObjDef(w, p.ArmorSlot)
	dmg, evaded := resolveAttack(npc.Def.MinDmg, npc.Def.MaxDmg, 0, 1, pDef, p.Level)
	if !evaded {
		p.HP -= dmg
		if p.HP < 0 {
			p.HP = 0
		}
	}
	w.broadcastMap(p.MapID, proto.MsgSDamage,
		buildDamage(p.InstanceID, int16(dmg), evaded), -1)

	// Send health update.
	{
		wr := proto.NewWriter(6)
		wr.WriteI16(int16(p.HP))
		wr.WriteI16(int16(p.MP))
		wr.WriteI16(int16(p.Stamina))
		w.sendTo(p, proto.MsgSHealth, wr.Bytes())
	}

	if p.HP == 0 {
		w.playerDied(p, npc.Def.Name)
		// Gap 19: track death for the player.
		w.checkAchievements(p, "deaths", 1)
	}
}

func (w *World) playerDied(p *Player, killerName string) {
	w.log.Info("player died", "char", p.CharName, "killer", killerName)

	// Send death packet.
	wr := proto.NewWriter(4 + len(killerName))
	wr.WriteStr(killerName)
	w.sendTo(p, proto.MsgSDeath, wr.Bytes())

	// Capture old map BEFORE changing MapID.
	oldMapID := p.MapID

	// Gap 10: Drop ALL gold as a ground item at death location.
	// Item 31 = Gold Coin in EO3 data.
	if p.Gold > 0 {
		w.spawnGroundItem(oldMapID, p.X, p.Y, 31 /* Gold Coin obj_index */, p.Gold)
		p.Gold = 0
	}

	// Gap 10: Drop up to 3 random unequipped inventory items at death location.
	var unequippedSlots []int
	for i, slot := range p.Inventory {
		if slot != nil && slot.ObjIndex > 0 && !slot.Equipped {
			unequippedSlots = append(unequippedSlots, i)
		}
	}
	// Shuffle to pick random items.
	for i := len(unequippedSlots) - 1; i > 0; i-- {
		j := rand.Intn(i + 1)
		unequippedSlots[i], unequippedSlots[j] = unequippedSlots[j], unequippedSlots[i]
	}
	dropCount := 3
	if len(unequippedSlots) < dropCount {
		dropCount = len(unequippedSlots)
	}
	for i := 0; i < dropCount; i++ {
		si := unequippedSlots[i]
		slot := p.Inventory[si]
		w.spawnGroundItem(oldMapID, p.X, p.Y, slot.ObjIndex, slot.Amount)
		p.Inventory[si] = nil
	}

	// Notify old map of removal BEFORE updating position.
	w.broadcastMap(oldMapID, proto.MsgSRemoveChar, buildRemoveChar(p.InstanceID), p.InstanceID)

	// Respawn at spawn point.
	p.MapID = w.cfg.SpawnMap
	p.X = w.cfg.SpawnX
	p.Y = w.cfg.SpawnY
	// Gap 11: Respawn with FULL HP/MP/STA (not MaxHP/2).
	p.HP = p.MaxHP
	p.MP = p.MaxMP
	p.Stamina = p.MaxStamina
	p.InCombat = false
	p.CombatCooldown = 0
	p.Target = 0

	// Send world state + new char position.
	{
		wr2 := proto.NewWriter(12)
		wr2.WriteI32(int32(p.MapID))
		wr2.WriteI16(int16(p.X))
		wr2.WriteI16(int16(p.Y))
		wr2.WriteI32(p.InstanceID)
		w.sendTo(p, proto.MsgSWorldState, wr2.Bytes())
	}
	w.sendTo(p, proto.MsgSStats, p.BuildStats())
	w.sendTo(p, proto.MsgSInventory, p.BuildInventory())

	// Announce arrival on new map.
	w.broadcastMap(p.MapID, proto.MsgSSetChar, p.BuildSetChar(), p.InstanceID)

	// Send all existing players and NPCs on the spawn map to the respawning player.
	for _, other := range w.players {
		if other.InstanceID == p.InstanceID || other.MapID != p.MapID {
			continue
		}
		w.sendTo(p, proto.MsgSSetChar, other.BuildSetChar())
	}
	for _, npc := range w.npcs {
		if npc.MapID == p.MapID && !npc.Dead {
			w.sendTo(p, proto.MsgSSetChar, npc.BuildSetChar())
		}
	}
}

func (w *World) respawnNPC(npc *NPC) {
	hp := npc.Def.MinHP + rand.Intn(max(1, npc.Def.MaxHP-npc.Def.MinHP+1))
	npc.HP = hp
	npc.MaxHP = hp
	npc.X = npc.SpawnX
	npc.Y = npc.SpawnY
	npc.MapID = npc.SpawnMapID
	npc.Dead = false
	npc.Target = 0
	npc.RespawnTicks = 0

	w.broadcastMap(npc.MapID, proto.MsgSSetChar, npc.BuildSetChar(), -1)
}

func (w *World) moveNPCToward(npc *NPC, tx, ty int) {
	dx := tx - npc.X
	dy := ty - npc.Y
	var dir uint8
	var nx, ny int
	if iabs(dx) >= iabs(dy) {
		if dx > 0 {
			dir, nx, ny = 2, npc.X+1, npc.Y
		} else {
			dir, nx, ny = 4, npc.X-1, npc.Y
		}
	} else {
		if dy > 0 {
			dir, nx, ny = 3, npc.X, npc.Y+1
		} else {
			dir, nx, ny = 1, npc.X, npc.Y-1
		}
	}
	if !w.isTileWalkable(npc.MapID, nx, ny) {
		return
	}
	npc.X = nx
	npc.Y = ny
	npc.Heading = dir
	w.broadcastMap(npc.MapID, proto.MsgSMoveChar,
		buildMoveChar(npc.InstanceID, nx, ny, dir), -1)
}

func (w *World) spawnAllNPCs() {
	for _, mapData := range w.gameData.Maps {
		for key, tile := range mapData.Tiles {
			if tile.NPCIndex == 0 {
				continue
			}
			npcDef := w.gameData.GetNPC(tile.NPCIndex)
			if npcDef == nil {
				continue
			}
			// Parse "y,x" key (pipeline stores tiles as "y,x" to match VB6 loop order).
			var x, y int
			fmt.Sscanf(key, "%d,%d", &y, &x)
			npc := NewNPC(w.nextNPCID, npcDef, mapData.ID, x, y)
			w.npcs[w.nextNPCID] = npc
			w.nextNPCID++
		}
	}
	w.log.Info("spawned NPCs", "count", len(w.npcs))
}

func (w *World) spawnHardcodedNPCs() {
	count := 0
	for mapID, spawns := range w.gameData.HardcodedSpawns {
		for _, s := range spawns {
			var def *gamedata.NPCData
			if s.Def != nil {
				def = s.Def
			} else if s.NpcIndex > 0 {
				def = w.gameData.GetNPC(s.NpcIndex)
			}
			if def == nil {
				continue
			}
			npc := NewNPC(w.nextNPCID, def, mapID, s.X, s.Y)
			w.npcs[w.nextNPCID] = npc
			w.nextNPCID++
			count++
		}
	}
	w.log.Info("spawned hardcoded NPCs", "count", count)
}

func (w *World) isTileWalkable(mapID, x, y int) bool {
	if x < 1 || x > 100 || y < 1 || y > 100 {
		return false
	}
	m := w.gameData.GetMap(mapID)
	if m == nil {
		return false
	}
	tile, ok := m.Tiles[fmt.Sprintf("%d,%d", y, x)]
	if !ok {
		return true // no tile data = walkable
	}
	return !tile.Blocked
}

func (w *World) allocPlayerID() int32 {
	for {
		id := w.nextPlayerID
		w.nextPlayerID++
		if w.nextPlayerID >= 9999 {
			w.nextPlayerID = 1
		}
		if _, used := w.players[id]; !used {
			return id
		}
	}
}

func (w *World) allocGroundID() int16 {
	id := w.nextGroundID
	w.nextGroundID++
	if w.nextGroundID <= 0 {
		w.nextGroundID = 1
	}
	return id
}

func (w *World) savePlayer(ctx context.Context, p *Player) error {
	cd := p.ToCharData()
	cd.ID = p.charDBID
	return w.db.SaveChar(ctx, cd)
}

func (w *World) saveAll(ctx context.Context) {
	for _, p := range w.players {
		if err := w.savePlayer(ctx, p); err != nil {
			w.log.Error("autosave failed", "char", p.CharName, "err", err)
		}
	}
}

// PlayerCount returns the current number of players in the world.
// Safe to call from any goroutine.
func (w *World) PlayerCount() int32 {
	return w.playerCount.Load()
}

// ---------------------------------------------------------------------------
// Boss spawns
// ---------------------------------------------------------------------------

func (w *World) initBossTimers() {
	for _, bd := range bossDefs {
		// Stagger initial spawns at 30–70% of interval.
		delay := bd.SpawnInterval*0.3 + rand.Float64()*(bd.SpawnInterval*0.4)
		w.bossTimers[bd.MapID] = delay
		w.bossInstances[bd.MapID] = 0
	}
}

func (w *World) tickBosses(delta float64) {
	for _, bd := range bossDefs {
		if w.bossInstances[bd.MapID] != 0 {
			continue // already spawned
		}
		w.bossTimers[bd.MapID] -= delta
		if w.bossTimers[bd.MapID] <= 0 {
			w.trySpawnBoss(bd)
		}
	}
}

func (w *World) trySpawnBoss(bd bossDef) {
	npcDef := w.gameData.GetNPC(bd.NPCIndex)
	if npcDef == nil {
		w.bossTimers[bd.MapID] = bd.SpawnInterval
		return
	}
	// Pick a walkable spawn tile near map centre.
	spawnX, spawnY := 50, 50
	npc := NewNPC(w.nextNPCID, npcDef, bd.MapID, spawnX, spawnY)
	npc.IsBoss = true
	w.npcs[w.nextNPCID] = npc
	w.bossInstances[bd.MapID] = w.nextNPCID
	w.nextNPCID++

	wr := proto.NewWriter(64)
	wr.WriteStr(fmt.Sprintf("A powerful %s has appeared on map %d!", bd.Name, bd.MapID))
	w.broadcastAll(proto.MsgSServerMsg, wr.Bytes())
	w.broadcastMap(bd.MapID, proto.MsgSSetChar, npc.BuildSetChar(), -1)
}

// clearBossInstance checks if a dying NPC is a boss and resets its slot.
// Returns true if it was a boss.
func (w *World) clearBossInstance(instanceID int32) bool {
	for mapID, nid := range w.bossInstances {
		if nid == instanceID {
			delete(w.bossInstances, mapID)
			// Reset the timer for the next spawn.
			for _, bd := range bossDefs {
				if bd.MapID == mapID {
					w.bossTimers[mapID] = bd.SpawnInterval
					break
				}
			}
			return true
		}
	}
	return false
}

// ---------------------------------------------------------------------------
// World events / invasions
// ---------------------------------------------------------------------------

func (w *World) tickWorldEvent(delta float64) {
	if w.worldEventActive {
		if time.Now().Unix() >= int64(w.worldEventEndAt) {
			msg := "The invasion has been repelled!"
			if len(w.worldEventNPCs) > 0 {
				msg = "The monsters retreated into the darkness."
			}
			w.endWorldEvent(msg)
		}
		return
	}
	w.worldEventAcc += delta
	if w.worldEventAcc >= worldEventInterval {
		w.worldEventAcc = 0
		w.startWorldEvent()
	}
}

func (w *World) startWorldEvent() {
	towns := []int{3, 18, 80}
	mapID := towns[rand.Intn(len(towns))]
	wave := worldEventWaves[mapID]
	if len(wave) == 0 {
		return
	}

	w.worldEventNPCs = w.worldEventNPCs[:0]
	for _, npcIdx := range wave {
		def := w.gameData.GetNPC(npcIdx)
		if def == nil {
			continue
		}
		spawnX := 40 + rand.Intn(20)
		spawnY := 40 + rand.Intn(20)
		npc := NewNPC(w.nextNPCID, def, mapID, spawnX, spawnY)
		npc.IsEventNPC = true
		w.npcs[w.nextNPCID] = npc
		w.worldEventNPCs = append(w.worldEventNPCs, w.nextNPCID)
		w.nextNPCID++
		w.broadcastMap(mapID, proto.MsgSSetChar, npc.BuildSetChar(), -1)
	}

	w.worldEventActive = true
	w.worldEventMapID = mapID
	w.worldEventEndAt = float64(time.Now().Unix()) + worldEventDuration

	wr := proto.NewWriter(32)
	wr.WriteStr("Invasion!")
	wr.WriteStr(fmt.Sprintf("Map %d", mapID))
	w.broadcastAll(proto.MsgSWorldEventStart, wr.Bytes())

	msg := proto.NewWriter(64)
	msg.WriteStr(fmt.Sprintf("INVASION! Monsters are attacking on map %d! Defend the town!", mapID))
	w.broadcastAll(proto.MsgSServerMsg, msg.Bytes())
	w.log.Info("world event started", "map", mapID, "npcs", len(w.worldEventNPCs))
}

func (w *World) endWorldEvent(result string) {
	// Remove any surviving event NPCs.
	for _, nid := range w.worldEventNPCs {
		npc, ok := w.npcs[nid]
		if !ok {
			continue
		}
		w.broadcastMap(npc.MapID, proto.MsgSRemoveChar, buildRemoveChar(nid), -1)
		delete(w.npcs, nid)
	}
	w.worldEventNPCs = w.worldEventNPCs[:0]
	w.worldEventActive = false

	wr := proto.NewWriter(32)
	wr.WriteStr("Invasion")
	wr.WriteStr(result)
	w.broadcastAll(proto.MsgSWorldEventEnd, wr.Bytes())

	msg := proto.NewWriter(64)
	msg.WriteStr(result)
	w.broadcastAll(proto.MsgSServerMsg, msg.Bytes())
	w.log.Info("world event ended", "result", result)
}

// onEventNPCDied removes an event NPC from the tracking slice and ends the
// event early if all event NPCs have been killed.
func (w *World) onEventNPCDied(instanceID int32) {
	for i, nid := range w.worldEventNPCs {
		if nid == instanceID {
			w.worldEventNPCs = append(w.worldEventNPCs[:i], w.worldEventNPCs[i+1:]...)
			break
		}
	}
	if len(w.worldEventNPCs) == 0 && w.worldEventActive {
		w.endWorldEvent("The town defenders were victorious! All monsters slain!")
	}
}

// ---------------------------------------------------------------------------
// Fishing tournament
// ---------------------------------------------------------------------------

func (w *World) tickTourney(delta float64) {
	if w.tourneyActive {
		if time.Now().Unix() >= int64(w.tourneyEndAt) {
			w.endFishingTourney()
		}
		return
	}
	w.tourneyAcc += delta
	if w.tourneyAcc >= tourneyInterval {
		w.tourneyAcc = 0
		w.startFishingTourney()
	}
}

func (w *World) startFishingTourney() {
	w.tourneyActive = true
	w.tourneyScores = make(map[int32]tourneyScore)
	w.tourneyEndAt = float64(time.Now().Unix()) + tourneyDuration

	wr := proto.NewWriter(16)
	wr.WriteI32(int32(tourneyDuration))
	wr.WriteStr(fmt.Sprintf("Grand Fishing Trophy + %d gold!", tourneyPrizes[0]))
	w.broadcastAll(proto.MsgSTourneyStart, wr.Bytes())

	msg := proto.NewWriter(64)
	msg.WriteStr(fmt.Sprintf("FISHING TOURNAMENT STARTED! Best catch in 10 minutes wins %d gold!", tourneyPrizes[0]))
	w.broadcastAll(proto.MsgSServerMsg, msg.Bytes())
	w.log.Info("fishing tournament started")
}

func (w *World) recordTourneyCatch(p *Player, catchSize int) {
	if !w.tourneyActive {
		return
	}
	entry := w.tourneyScores[p.InstanceID]
	if catchSize > entry.BestCatch {
		entry.BestCatch = catchSize
		entry.Name = p.CharName
		w.tourneyScores[p.InstanceID] = entry
	}
	w.broadcastTourneyScores()
}

func (w *World) broadcastTourneyScores() {
	type pair struct {
		name  string
		score int
	}
	var scores []pair
	for _, e := range w.tourneyScores {
		scores = append(scores, pair{e.Name, e.BestCatch})
	}
	sort.Slice(scores, func(i, j int) bool { return scores[i].score > scores[j].score })
	top := 5
	if len(scores) < top {
		top = len(scores)
	}
	wr := proto.NewWriter(64)
	wr.WriteU8(uint8(top))
	for i := 0; i < top; i++ {
		wr.WriteStr(scores[i].name)
		wr.WriteI32(int32(scores[i].score))
	}
	w.broadcastAll(proto.MsgSTourneyScores, wr.Bytes())
}

func (w *World) endFishingTourney() {
	w.tourneyActive = false

	type entry struct {
		instanceID int32
		name       string
		score      int
	}
	var scores []entry
	for iid, e := range w.tourneyScores {
		scores = append(scores, entry{iid, e.Name, e.BestCatch})
	}
	sort.Slice(scores, func(i, j int) bool { return scores[i].score > scores[j].score })

	awardCount := len(tourneyPrizes)
	if len(scores) < awardCount {
		awardCount = len(scores)
	}

	wr := proto.NewWriter(64)
	wr.WriteU8(uint8(awardCount))
	var winnerMsgs []string
	places := []string{"1st", "2nd", "3rd"}
	for i := 0; i < awardCount; i++ {
		e := scores[i]
		prize := tourneyPrizes[i]
		wr.WriteStr(e.name)
		wr.WriteI32(int32(e.score))
		wr.WriteI32(int32(prize))
		winnerMsgs = append(winnerMsgs, fmt.Sprintf("%s: %s (%d)", places[i], e.name, e.score))
		// Award gold to online winner.
		if p, ok := w.players[e.instanceID]; ok {
			p.Gold += prize
			w.sendTo(p, proto.MsgSStats, p.BuildStats())
			w.sendTo(p, proto.MsgSServerMsg,
				buildServerMsg(fmt.Sprintf("You placed %s in the Fishing Tournament! Prize: %d gold!", places[i], prize)))
		}
	}
	w.broadcastAll(proto.MsgSTourneyEnd, wr.Bytes())

	result := "Fishing Tournament Over!"
	if len(winnerMsgs) > 0 {
		result += " " + winnerMsgs[0]
		for _, m := range winnerMsgs[1:] {
			result += ", " + m
		}
	} else {
		result += " No participants."
	}
	msg := proto.NewWriter(64)
	msg.WriteStr(result)
	w.broadcastAll(proto.MsgSServerMsg, msg.Bytes())

	w.tourneyScores = make(map[int32]tourneyScore)
	w.log.Info("fishing tournament ended")
}

// ---------------------------------------------------------------------------
// Daily login streak
// ---------------------------------------------------------------------------

func (w *World) checkDailyLogin(p *Player) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	today := time.Now().UTC().Format("2006-01-02")
	streak, lastDate, err := w.db.GetLoginStreak(ctx, p.AccountID)
	if err != nil {
		w.log.Warn("failed to load login streak", "char", p.CharName, "err", err)
		return
	}
	if lastDate == today {
		return // already rewarded today
	}

	yesterday := time.Now().UTC().AddDate(0, 0, -1).Format("2006-01-02")
	if lastDate != yesterday {
		streak = 0 // streak broken
	}
	streak++
	if streak > 7 {
		streak = 7
	}

	rewards := [7]struct {
		gold int
		msg  string
	}{
		{50, "Day 1 login bonus: 50 gold!"},
		{75, "Day 2 streak: 75 gold!"},
		{100, "Day 3 streak: 100 gold!"},
		{125, "Day 4 streak: 125 gold!"},
		{150, "Day 5 streak: 150 gold!"},
		{200, "Day 6 streak: 200 gold!"},
		{500, "7-DAY STREAK! 500 gold reward! Keep it up!"},
	}
	r := rewards[streak-1]
	p.Gold += r.gold

	wr := proto.NewWriter(32)
	wr.WriteU8(uint8(streak))
	wr.WriteI32(int32(r.gold))
	wr.WriteStr(r.msg)
	w.sendTo(p, proto.MsgSLoginReward, wr.Bytes())
	w.sendTo(p, proto.MsgSStats, p.BuildStats())

	if err := w.db.SetLoginStreak(ctx, p.AccountID, streak, today); err != nil {
		w.log.Warn("failed to save login streak", "char", p.CharName, "err", err)
	}
}
