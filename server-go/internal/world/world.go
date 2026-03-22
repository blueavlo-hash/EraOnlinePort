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
	"sync/atomic"
	"time"

	"github.com/blueavlo-hash/eraonline-server/internal/db"
	"github.com/blueavlo-hash/eraonline-server/internal/gamedata"
	"github.com/blueavlo-hash/eraonline-server/internal/proto"
)

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

	// Pending trade requests: target_instance_id → requester_instance_id.
	pendingTrades map[int32]int32

	// playerCount is updated atomically so the HTTP API can read it safely.
	playerCount atomic.Int32
}

// GroundItem is a dropped item lying on the ground.
type GroundItem struct {
	ID       int16
	MapID    int
	X, Y     int
	ObjIndex int
	Amount   int
	Timeout  int // world ticks until auto-despawn
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
		pendingTrades: make(map[int32]int32),
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
		wr := proto.NewWriter(8)
		wr.WriteI32(int32(p.MapID))
		wr.WriteI16(int16(p.X))
		wr.WriteI16(int16(p.Y))
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

	// Player vitals, regen, combat cooldown, and poison.
	for _, p := range w.players {
		// Decrement combat cooldown and clear InCombat when it reaches 0.
		if p.CombatCooldown > 0 {
			p.CombatCooldown--
			if p.CombatCooldown == 0 {
				p.InCombat = false
			}
		}
		w.tickVitals(p)
		w.tickPlayerRegen(p)
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
}

// tickNPC runs one AI step for an NPC.
func (w *World) tickNPC(npc *NPC, combatTicksPerAttack int) {
	if npc.Dead {
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
			if dx*dx+dy*dy <= 9 { // aggro range = 3 tiles
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
			if dx*dx+dy*dy <= 4 { // attack range = 2 tiles
				w.npcAttackPlayer(npc, target)
				npc.CombatCooldown = combatTicksPerAttack
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

	// Notify old map of removal BEFORE updating position.
	w.broadcastMap(oldMapID, proto.MsgSRemoveChar, buildRemoveChar(p.InstanceID), p.InstanceID)

	// Respawn at spawn point.
	p.MapID = w.cfg.SpawnMap
	p.X = w.cfg.SpawnX
	p.Y = w.cfg.SpawnY
	p.HP = imax(1, p.MaxHP/2)
	p.MP = imax(1, p.MaxMP/2)
	p.InCombat = false
	p.CombatCooldown = 0
	p.Target = 0

	// Send world state + new char position.
	{
		wr2 := proto.NewWriter(8)
		wr2.WriteI32(int32(p.MapID))
		wr2.WriteI16(int16(p.X))
		wr2.WriteI16(int16(p.Y))
		w.sendTo(p, proto.MsgSWorldState, wr2.Bytes())
	}
	w.sendTo(p, proto.MsgSStats, p.BuildStats())

	// Announce arrival on new map.
	w.broadcastMap(p.MapID, proto.MsgSSetChar, p.BuildSetChar(), p.InstanceID)
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
