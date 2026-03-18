class_name NetProtocol
## Era Online - Shared Network Protocol
## Used by both client (Network.gd) and server (ServerMain.gd).
##
## Connection handshake:
##   1. TCP connect → TLS handshake (server cert)
##   2. S→C: SERVER_HELLO  (version, server_nonce[16])
##   3. C→S: CLIENT_HELLO  (client_nonce[16])
##   4. C→S: AUTH_LOGIN or AUTH_REGISTER (username, password plaintext over TLS)
##   5. S→C: AUTH_OK (session_id) or AUTH_FAIL (reason)
##   6. Both sides derive session_key = HMAC-SHA256(server_secret,
##          client_nonce + server_nonce + session_id_bytes)[0:16]
##   7. All subsequent packets use the authenticated packet format + HMAC.
##
## Pre-auth packet format (handshake only, TLS provides integrity):
##   [uint16 type][uint16 payload_len][payload bytes]
##   Overhead: 4 bytes
##
## Authenticated packet format (post-login):
##   [uint32 seq][uint16 type][uint16 payload_len][payload bytes][16-byte HMAC]
##   Overhead: 24 bytes
##   HMAC covers all preceding bytes in the packet.
##
## All integers big-endian. Strings: uint16 byte-length + UTF-8 bytes.


# ---------------------------------------------------------------------------
# Message types
# ---------------------------------------------------------------------------

enum MsgType {
	## Handshake (pre-auth, no HMAC required — TLS handles integrity)
	SERVER_HELLO   = 0x0001,  # S→C: version:u16, server_nonce:bytes[16]
	CLIENT_HELLO   = 0x0002,  # C→S: client_nonce:bytes[16]
	AUTH_LOGIN     = 0x0010,  # C→S: username:str, password:str
	AUTH_REGISTER  = 0x0011,  # C→S: username:str, password:str
	AUTH_OK        = 0x0012,  # S→C: session_id:str, char_name:str
	AUTH_FAIL      = 0x0013,  # S→C: reason:str

	## Client → Server (authenticated, HMAC-protected)
	C_MOVE         = 0x0100,  # direction:u8 (1=N 2=E 3=S 4=W)
	C_ATTACK       = 0x0101,  # target_id:i32
	C_PICKUP       = 0x0102,  # ground_item_id:i16
	C_DROP         = 0x0103,  # slot:u8, amount:u16
	C_EQUIP        = 0x0104,  # slot:u8
	C_UNEQUIP      = 0x0105,  # slot:u8
	C_USE_ITEM     = 0x0106,  # slot:u8
	C_CAST_SPELL   = 0x0107,  # u8 spell_id, i32 target_id (0=ground,-1=self), i16 target_x, i16 target_y
	C_CHAT         = 0x0108,  # message:str
	C_PING         = 0x01FF,  # timestamp_ms:i64

	## Server → Client (authenticated, HMAC-protected)
	S_WORLD_STATE  = 0x0200,  # map_id:i32, x:i16, y:i16
	S_MOVE_CHAR    = 0x0201,  # char_id:i32, x:i16, y:i16, heading:u8
	S_SET_CHAR     = 0x0202,  # char_id:i32, body:i16, head:i16, weapon:i16, shield:i16, x:i16, y:i16, heading:u8, hp:i16, max_hp:i16, name:str
	S_REMOVE_CHAR  = 0x0203,  # char_id:i32
	S_INVENTORY    = 0x0204,  # count:u8, then count×(slot:u8, obj_index:i16, amount:u16, equipped:u8)
	S_EQUIP_CHANGE = 0x0205,  # slot:u8, obj_index:i16, amount:u16
	S_STATS        = 0x0206,  # level:u8, hp:i16, max_hp:i16, mp:i16, max_mp:i16, sta:i16, max_sta:i16, exp:i32, next_exp:i32, gold:i32
	S_HEALTH       = 0x0207,  # hp:i16, mp:i16, sta:i16
	S_DAMAGE       = 0x0208,  # char_id:i32, damage:i16, evaded:u8
	S_CHAT         = 0x0209,  # char_id:i32, chat_type:u8, message:str
	S_MAP_CHANGE   = 0x020A,  # map_id:i32, x:i16, y:i16
	S_PLAY_SOUND   = 0x020B,  # sound_num:u8
	S_SET_STATS    = 0x020C,  # count:u16, then count×(key:str, value:i32) — partial stat patch
	S_PONG         = 0x02FF,  # timestamp_ms:i64
	S_KICK         = 0x0F00,  # reason:str
	S_SERVER_MSG   = 0x0F01,  # message:str
	S_DEATH        = 0x0F02,  # killer_name:str (empty string if starvation/env)

	## Character management (authenticated, sent right after AUTH_OK)
	S_CHAR_LIST    = 0x0020,  # count:u8, then count×(name:str, level:u8, class_id:u8, body:i16, head:i16)
	C_SELECT_CHAR  = 0x0021,  # name:str
	C_CREATE_CHAR  = 0x0022,  # name:str, class_id:u8, head:i16, body:i16
	S_CREATE_RESULT = 0x0023, # success:u8, reason:str
	C_DELETE_CHAR   = 0x0024, # name:str
	S_DELETE_RESULT = 0x0025, # success:u8, reason:str

	## Shop / vendor (authenticated)
	C_SHOP_OPEN    = 0x0030,  # i32 npc_instance_id
	S_SHOP_LIST    = 0x0031,  # str shop_name, u8 count, then count×(i16 obj_index, i32 price, str name)
	C_BUY          = 0x0032,  # i32 npc_instance_id, i16 obj_index, u16 amount
	S_BUY_RESULT   = 0x0033,  # u8 success, str reason

	## Weather
	S_RAIN_ON      = 0x0040,  # (no payload) — start rain
	S_RAIN_OFF     = 0x0041,  # (no payload) — stop rain

	## Ground items
	S_GROUND_ITEM_ADD    = 0x0043,  # id:i16, obj_index:i16, amount:u16, x:i16, y:i16
	S_GROUND_ITEM_REMOVE = 0x0044,  # id:i16

	## Skills
	C_USE_SKILL      = 0x0109,  # u8 skill_id (1-28), i16 tile_x, i16 tile_y
	S_SKILLS         = 0x0210,  # u8 count, then count×(u8 slot, i16 level, i32 xp, i32 xp_needed)
	S_SKILL_RAISE    = 0x0211,  # u8 slot_1based, i16 new_level  (xp resets to 0 on client)
	S_SKILL_PROGRESS = 0x0212,  # u8 skill_id, u16 duration_ms (0=cancel/done)
	S_VITALS         = 0x0213,  # hunger:u8, thirst:u8
	S_SKILL_XP       = 0x0214,  # u8 slot_1based, i32 current_xp, i32 xp_needed
	S_XP_GAIN        = 0x0215,  # i32 xp_gained
	S_LEVEL_UP       = 0x0216,  # u8 new_level

	## Magic — server → client
	S_SPELL_CAST    = 0x0300,  # i32 caster_id, u8 spell_id, i32 target_id, i16 tx, i16 ty
	S_SPELL_HIT     = 0x0301,  # i32 target_id, u8 spell_id, i16 damage, i16 heal, i16 mana_drain
	S_SPELL_CHAIN   = 0x0302,  # u8 spell_id, u8 count, then count×i32 target_id
	S_STATUS_APPLIED = 0x0303, # i32 char_id, u8 status_id, u16 duration_ms
	S_STATUS_REMOVED = 0x0304, # i32 char_id, u8 status_id
	S_SPELLBOOK     = 0x0305,  # u8 count, then count×u8 spell_id
	S_SPELL_UNLOCK  = 0x0306,  # u8 spell_id
	S_SPELL_SHOP    = 0x0307,  # u8 count, then count×(u8 spell_id, i16 price)
	## Magic — client → server
	C_BUY_SPELL     = 0x010A,  # i32 npc_id, u8 spell_id

	# Bank
	C_BANK_OPEN    = 0x0050,  # i32 npc_instance_id
	S_BANK_CONTENTS = 0x0051, # u8 count, count×(u8 slot, i16 obj_index, u16 amount), i32 gold
	C_BANK_DEPOSIT  = 0x0052, # u8 inv_slot
	C_BANK_WITHDRAW = 0x0053, # u8 bank_slot
	C_BANK_DEPOSIT_GOLD  = 0x0054, # i32 amount
	C_BANK_WITHDRAW_GOLD = 0x0055, # i32 amount

	# Sell
	C_SELL         = 0x0034,  # i32 npc_instance_id, u8 inv_slot

	# Trade
	C_TRADE_REQUEST  = 0x0060,  # i32 target_char_id
	S_TRADE_REQUEST  = 0x0061,  # i32 from_char_id, str from_name
	C_TRADE_RESPOND  = 0x0062,  # u8 accept (1=yes 0=no)
	C_TRADE_OFFER    = 0x0063,  # u8 inv_slot
	C_TRADE_RETRACT  = 0x0064,  # u8 offer_slot
	C_TRADE_CONFIRM  = 0x0065,  # (no payload)
	C_TRADE_CANCEL   = 0x0066,  # (no payload)
	S_TRADE_STATE    = 0x0067,  # u8 count_my, count_my×(i16 obj_index,u16 amount), u8 count_their, count_their×(i16 obj_index,u16 amount), u8 my_confirmed, u8 their_confirmed
	S_TRADE_COMPLETE = 0x0068,  # (no payload)
	S_TRADE_CANCELLED = 0x0069, # str reason

	## Quests
	C_QUEST_TALK    = 0x0070,  # i32 npc_instance_id
	S_QUEST_OFFER   = 0x0071,  # u8 mode (0=offer,1=turnin), u16 quest_id, str npc_name,
	                            #   str quest_name, str desc,
	                            #   u8 obj_count, obj_count×(str label, u16 required, u8 type),
	                            #   i32 reward_gold, i32 reward_xp,
	                            #   u8 item_count, item_count×(i16 obj_index, u16 amount, str name)
	C_QUEST_ACCEPT  = 0x0072,  # u16 quest_id
	C_QUEST_TURNIN  = 0x0073,  # u16 quest_id
	S_QUEST_UPDATE  = 0x0074,  # u16 quest_id, str objectives_str
	S_QUEST_COMPLETE = 0x0075, # u16 quest_id, i32 reward_gold, i32 reward_xp
	S_QUEST_INDICATORS = 0x0076, # u16 count, then count×(i32 npc_instance_id, str indicator)

	## Corpse visual (sent on player/NPC death — client renders lying body, despawns after timer)
	S_CORPSE             = 0x0045,  # i16 x, i16 y, i16 grh_index

	## Loot rarity notification (sent after S_GROUND_ITEM_ADD for uncommon+ items)
	S_RARE_DROP_NOTIFY   = 0x0080,  # str item_name, u8 rarity(1=uncommon,2=rare,3=legendary), i16 x, i16 y

	## Achievements
	S_ACHIEVEMENT_UNLOCK = 0x0081,  # u16 achievement_id, str name, str desc, i32 reward_gold, i32 reward_xp

	## Bounty system
	S_BOUNTY_UPDATE      = 0x0090,  # i32 target_char_id, str target_name, i32 bounty_amount (0=cleared)

	## Enchanting
	C_ENCHANT            = 0x00A0,  # u8 item_slot, u8 material_slot
	S_ENCHANT_RESULT     = 0x00A1,  # u8 result(0=fail,1=success,2=destroyed), u8 new_enchant_level, str message

	## Leaderboard
	C_LEADERBOARD_REQUEST = 0x00B0,  # u8 type(0=kills,1=crafts,2=level,3=fishing)
	S_LEADERBOARD_DATA    = 0x00B1,  # u8 type, u8 count, count×(str name, i32 score)

	## World events / invasions
	S_WORLD_EVENT_START  = 0x00C0,  # str event_name, str location_hint
	S_WORLD_EVENT_END    = 0x00C1,  # str event_name, str result_msg

	## Player titles
	S_TITLE_UPDATE       = 0x00D0,  # i32 instance_id, str title  (instance_id matches S_SET_CHAR)

	## Fishing tournament
	S_TOURNEY_START      = 0x00E0,  # i32 duration_sec, str prize_desc
	S_TOURNEY_END        = 0x00E1,  # u8 count, count×(str name, i32 score, i32 gold_reward)
	S_TOURNEY_SCORES     = 0x00E2,  # u8 count, count×(str name, i32 score)

	## Daily login reward
	S_LOGIN_REWARD       = 0x00F0,  # u8 streak_day, i32 gold_reward, str bonus_msg

	# Day/night cycle
	S_TIME_OF_DAY        = 0x0100,  # u16 minutes (0-1439, 0.0-23.98 in-game hours)

	# Faction reputation
	C_PENANCE            = 0x0110,  # str faction_name — spend gold to repair rep
	S_REP_REFUSED        = 0x0111,  # str faction_name — vendor refused (hated)

	## Combat abilities / trainer system
	S_ABILITY_LIST    = 0x0140,  # u8 count, [u8 ability_id] × count — full learned list on login
	S_ABILITY_SHOP    = 0x0141,  # u8 count, [u8 id, str name, u16 gold_cost, u8 req_level, u8 req_skill_id, u8 req_skill_val, u8 learned] × count
	C_LEARN_ABILITY   = 0x0142,  # u8 ability_id — client requests to learn
	S_ABILITY_LEARNED = 0x0143,  # u8 ability_id — server confirms learned
	S_ABILITY_FAIL    = 0x0144,  # str reason — server rejects learn attempt
	S_PROJECTILE      = 0x0145,  # i32 caster_id, i32 target_id, u8 proj_type (0=arrow,1=bolt)
	S_HOTBAR          = 0x0146,  # u8 count (≤10), count×(u8 slot, u8 type, u8 id) — type: 0=ability,1=spell
	C_SAVE_HOTBAR     = 0x0147,  # u8 count (≤10), count×(u8 slot, u8 type, u8 id)
}


# ---------------------------------------------------------------------------
# Protocol constants
# ---------------------------------------------------------------------------

const PROTOCOL_VERSION  : int = 1
const NONCE_SIZE        : int = 16
const HMAC_SIZE         : int = 16    # Truncated HMAC-SHA256 (128-bit tag)
const PREAUTH_HDR_SIZE  : int = 4     # u16 type + u16 len
const AUTH_HDR_SIZE     : int = 8     # u32 seq + u16 type + u16 len
const FULL_PKT_OVERHEAD : int = AUTH_HDR_SIZE + HMAC_SIZE  # 24 bytes
const MAX_PAYLOAD_SIZE  : int = 65535

## PBKDF2 iterations for password hashing (server-side only).
const PBKDF2_ITERATIONS : int = 1000

## Minimum seconds between auth attempts (per connection).
const AUTH_ATTEMPT_WINDOW : float = 2.0
## Max failed attempts before connection is locked out.
const AUTH_MAX_ATTEMPTS   : int   = 5
## Lockout duration in seconds.
const AUTH_LOCKOUT_SECS   : float = 60.0

## Rate limits per message type: msg_type → [tokens_per_sec, burst_capacity]
const RATE_LIMITS : Dictionary = {
	0x0100: [15, 20],  # C_MOVE
	0x0101: [2,  4],   # C_ATTACK
	0x0102: [5,  10],  # C_PICKUP
	0x0103: [5,  10],  # C_DROP
	0x0104: [5,  10],  # C_EQUIP
	0x0105: [5,  10],  # C_UNEQUIP
	0x0106: [5,  10],  # C_USE_ITEM
	0x0107: [2,  4],   # C_CAST_SPELL
	0x0108: [2,  5],   # C_CHAT
	0x0109: [2,  4],   # C_USE_SKILL
	0x010A: [1,  2],   # C_BUY_SPELL — 1/sec, burst 2
	0x0142: [1,  2],   # C_LEARN_ABILITY — 1/sec, burst 2
	0x01FF: [1,  2],   # C_PING
}


# ---------------------------------------------------------------------------
# PacketWriter — builds binary payloads (big-endian)
# ---------------------------------------------------------------------------

class PacketWriter:
	var _buf: PackedByteArray = []

	func write_u8(v: int) -> void:
		_buf.append(v & 0xFF)

	func write_u16(v: int) -> void:
		_buf.append((v >> 8) & 0xFF)
		_buf.append(v & 0xFF)

	func write_u32(v: int) -> void:
		_buf.append((v >> 24) & 0xFF)
		_buf.append((v >> 16) & 0xFF)
		_buf.append((v >> 8)  & 0xFF)
		_buf.append(v & 0xFF)

	func write_i8(v: int)  -> void: write_u8(v & 0xFF)
	func write_i16(v: int) -> void: write_u16(v & 0xFFFF)
	func write_i32(v: int) -> void: write_u32(v & 0xFFFFFFFF)

	func write_i64(v: int) -> void:
		write_u32((v >> 32) & 0xFFFFFFFF)
		write_u32(v & 0xFFFFFFFF)

	func write_str(s: String) -> void:
		var b := s.to_utf8_buffer()
		write_u16(b.size())
		_buf.append_array(b)

	func write_bytes(b: PackedByteArray) -> void:
		_buf.append_array(b)

	func get_bytes() -> PackedByteArray:
		return _buf

	func size() -> int:
		return _buf.size()


# ---------------------------------------------------------------------------
# PacketReader — reads binary payloads (big-endian)
# ---------------------------------------------------------------------------

class PacketReader:
	var _buf: PackedByteArray
	var _pos: int = 0
	var error: bool = false

	func _init(data: PackedByteArray) -> void:
		_buf = data

	func _need(n: int) -> bool:
		if _pos + n > _buf.size():
			error = true
			return false
		return true

	func read_u8() -> int:
		if not _need(1): return 0
		var v := _buf[_pos]; _pos += 1; return v

	func read_u16() -> int:
		if not _need(2): return 0
		var v := (_buf[_pos] << 8) | _buf[_pos + 1]
		_pos += 2; return v

	func read_u32() -> int:
		if not _need(4): return 0
		var v := (_buf[_pos] << 24) | (_buf[_pos+1] << 16) | (_buf[_pos+2] << 8) | _buf[_pos+3]
		_pos += 4; return v

	func read_i8() -> int:
		var v := read_u8()
		return v if v < 128 else v - 256

	func read_i16() -> int:
		var v := read_u16()
		return v if v < 32768 else v - 65536

	func read_i32() -> int:
		var v := read_u32()
		return v if v < 2147483648 else v - 4294967296

	func read_i64() -> int:
		var hi := read_u32()
		var lo := read_u32()
		return (hi << 32) | lo

	func read_str() -> String:
		var n := read_u16()
		if not _need(n): return ""
		var b := _buf.slice(_pos, _pos + n)
		_pos += n
		return b.get_string_from_utf8()

	func read_bytes(n: int) -> PackedByteArray:
		if not _need(n): return PackedByteArray()
		var b := _buf.slice(_pos, _pos + n)
		_pos += n; return b

	func remaining() -> int:
		return _buf.size() - _pos


# ---------------------------------------------------------------------------
# Crypto helpers
# ---------------------------------------------------------------------------

## HMAC-SHA256. Returns first `out_len` bytes (default: full 32).
static func hmac(key: PackedByteArray, msg: PackedByteArray, out_len: int = 32) -> PackedByteArray:
	var full := Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key, msg)
	return full if out_len >= 32 else full.slice(0, out_len)


## PBKDF2-HMAC-SHA256 (single 32-byte block).
## password: plaintext string, salt: random bytes, iterations: stretch factor.
static func pbkdf2(password: String, salt: PackedByteArray,
		iterations: int = PBKDF2_ITERATIONS) -> PackedByteArray:
	var pw  := password.to_utf8_buffer()
	var c   := Crypto.new()
	var blk := salt.duplicate()
	blk.append_array(PackedByteArray([0, 0, 0, 1]))  # block index INT(1) big-endian
	var u := c.hmac_digest(HashingContext.HASH_SHA256, pw, blk)
	var t := u.duplicate()
	for _i in range(1, iterations):
		u = c.hmac_digest(HashingContext.HASH_SHA256, pw, u)
		for j in t.size():
			t[j] ^= u[j]
	return t  # 32 bytes


## Derive a 16-byte session key from the handshake nonces and server secret.
## Both client and server compute this independently — result must match.
static func derive_session_key(server_secret: PackedByteArray,
		client_nonce: PackedByteArray, server_nonce: PackedByteArray,
		session_id: String) -> PackedByteArray:
	var msg := client_nonce.duplicate()
	msg.append_array(server_nonce)
	msg.append_array(session_id.to_utf8_buffer())
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, server_secret, msg).slice(0, HMAC_SIZE)


## Compute the 16-byte HMAC tag for a packet.
static func sign_packet(session_key: PackedByteArray, data: PackedByteArray) -> PackedByteArray:
	return hmac(session_key, data, HMAC_SIZE)


## Constant-time HMAC verification. Returns true if tag is valid.
static func verify_packet(session_key: PackedByteArray,
		data: PackedByteArray, tag: PackedByteArray) -> bool:
	var expected := sign_packet(session_key, data)
	if expected.size() != tag.size():
		return false
	var diff := 0
	for i in expected.size():
		diff |= expected[i] ^ tag[i]
	return diff == 0


# ---------------------------------------------------------------------------
# Packet framing
# ---------------------------------------------------------------------------

## Frame a pre-auth packet (no HMAC). Used during handshake only.
static func frame_preauth(msg_type: int, payload: PackedByteArray) -> PackedByteArray:
	var w := PacketWriter.new()
	w.write_u16(msg_type)
	w.write_u16(payload.size())
	w.write_bytes(payload)
	return w.get_bytes()


## Frame an authenticated packet with sequence number and HMAC.
static func frame_auth(msg_type: int, payload: PackedByteArray,
		seq: int, session_key: PackedByteArray) -> PackedByteArray:
	var w := PacketWriter.new()
	w.write_u32(seq)
	w.write_u16(msg_type)
	w.write_u16(payload.size())
	w.write_bytes(payload)
	var header_plus_payload := w.get_bytes()
	var tag := sign_packet(session_key, header_plus_payload)
	header_plus_payload.append_array(tag)
	return header_plus_payload
