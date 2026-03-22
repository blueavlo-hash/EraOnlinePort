// Package proto defines the Era Online binary network protocol.
//
// Pre-auth packet format (handshake only, TLS provides integrity):
//
//	[uint16 type][uint16 payload_len][payload bytes]  — overhead: 4 bytes
//
// Authenticated packet format (post-login):
//
//	[uint32 seq][uint16 type][uint16 payload_len][payload bytes][16-byte HMAC]  — overhead: 24 bytes
//
// All integers big-endian. Strings: uint16 byte-length + UTF-8 bytes.
package proto

// MsgType constants (all protocol message IDs).
const (
	// Handshake (pre-auth)
	//
	// Client attestation flow (runs before AUTH_LOGIN/REGISTER):
	//   1. Server sends SERVER_HELLO: version:u16, server_nonce[16], client_challenge[16]
	//   2. Client sends CLIENT_HELLO: client_nonce[16], client_proof[16]
	//      client_proof = HMAC-SHA256(CLIENT_IDENTITY_SECRET, client_challenge || server_nonce)[0:16]
	//   3. Server verifies client_proof — if wrong, kicks with "client not recognized"
	//   4. (Then AUTH_LOGIN/REGISTER proceeds as before)
	//
	// This rejects any client that doesn't embed the CLIENT_IDENTITY_SECRET,
	// making generic bots and packet injectors unable to reach the auth layer.
	MsgServerHello  uint16 = 0x0001 // S→C: version:u16, server_nonce:bytes[16], client_challenge:bytes[16]
	MsgClientHello  uint16 = 0x0002 // C→S: client_nonce:bytes[16], client_proof:bytes[16]
	MsgAuthLogin    uint16 = 0x0010 // C→S: username:str, password:str
	MsgAuthRegister uint16 = 0x0011 // C→S: username:str, password:str
	MsgAuthOK       uint16 = 0x0012 // S→C: session_id:str, char_name:str (empty)
	MsgAuthFail     uint16 = 0x0013 // S→C: reason:str
	MsgAuthToken    uint16 = 0x0015 // C→S: token:str (launcher pre-auth token, replaces AUTH_LOGIN)

	// Client → Server (authenticated)
	MsgCMove         uint16 = 0x0100 // direction:u8 (1=N 2=E 3=S 4=W)
	MsgCAttack       uint16 = 0x0101 // target_id:i32
	MsgCPickup       uint16 = 0x0102 // ground_item_id:i16
	MsgCDrop         uint16 = 0x0103 // slot:u8, amount:u16
	MsgCEquip        uint16 = 0x0104 // slot:u8
	MsgCUnequip      uint16 = 0x0105 // slot:u8
	MsgCUseItem      uint16 = 0x0106 // slot:u8
	MsgCCastSpell    uint16 = 0x0107 // u8 spell_id, i32 target_id, i16 tx, i16 ty
	MsgCChat         uint16 = 0x0108 // message:str
	MsgCUseSkill     uint16 = 0x0109 // u8 skill_id (1-28), i16 tile_x, i16 tile_y
	MsgCBuySpell     uint16 = 0x010A // i32 npc_id, u8 spell_id
	MsgCLearnAbility uint16 = 0x0142 // u8 ability_id
	MsgCSaveHotbar   uint16 = 0x0147 // u8 count (≤10), count×(u8 slot, u8 type, u8 id)
	MsgCPing         uint16 = 0x01FF // timestamp_ms:i64

	// Server → Client (authenticated)
	MsgSWorldState  uint16 = 0x0200 // map_id:i32, x:i16, y:i16
	MsgSMoveChar    uint16 = 0x0201 // char_id:i32, x:i16, y:i16, heading:u8
	MsgSSetChar     uint16 = 0x0202 // char_id:i32, body:i16, head:i16, weapon:i16, shield:i16, x:i16, y:i16, heading:u8, hp:i16, max_hp:i16, name:str
	MsgSRemoveChar  uint16 = 0x0203 // char_id:i32
	MsgSInventory   uint16 = 0x0204 // count:u8, count×(slot:u8, obj_index:i16, amount:u16, equipped:u8)
	MsgSEquipChange uint16 = 0x0205 // slot:u8, obj_index:i16, amount:u16
	MsgSStats       uint16 = 0x0206 // level:u8, hp:i16, max_hp:i16, mp:i16, max_mp:i16, sta:i16, max_sta:i16, exp:i32, next_exp:i32, gold:i32
	MsgSHealth      uint16 = 0x0207 // hp:i16, mp:i16, sta:i16
	MsgSDamage      uint16 = 0x0208 // char_id:i32, damage:i16, evaded:u8
	MsgSChat        uint16 = 0x0209 // char_id:i32, chat_type:u8, message:str
	MsgSMapChange   uint16 = 0x020A // map_id:i32, x:i16, y:i16
	MsgSPlaySound   uint16 = 0x020B // sound_num:u8
	MsgSSetStats    uint16 = 0x020C // count:u16, count×(key:str, value:i32)
	MsgSPong        uint16 = 0x02FF // timestamp_ms:i64
	MsgSKick        uint16 = 0x0F00 // reason:str
	MsgSServerMsg   uint16 = 0x0F01 // message:str
	MsgSDeath       uint16 = 0x0F02 // killer_name:str

	// Character management
	MsgSCharList      uint16 = 0x0020 // count:u8, count×(name:str, level:u8, class_id:u8, body:i16, head:i16)
	MsgCSelectChar    uint16 = 0x0021 // name:str
	MsgCCreateChar    uint16 = 0x0022 // name:str, class_id:u8, head:i16, body:i16
	MsgSCreateResult  uint16 = 0x0023 // success:u8, reason:str
	MsgCDeleteChar    uint16 = 0x0024 // name:str
	MsgSDeleteResult  uint16 = 0x0025 // success:u8, reason:str

	// Shop / vendor
	MsgCShopOpen  uint16 = 0x0030 // i32 npc_instance_id
	MsgSShopList  uint16 = 0x0031 // str shop_name, u8 count, count×(i16 obj_index, i32 price, str name)
	MsgCBuy       uint16 = 0x0032 // i32 npc_instance_id, i16 obj_index, u16 amount
	MsgSBuyResult uint16 = 0x0033 // u8 success, str reason
	MsgCSell      uint16 = 0x0034 // i32 npc_instance_id, u8 inv_slot

	// Weather
	MsgSRainOn  uint16 = 0x0040 // (no payload)
	MsgSRainOff uint16 = 0x0041 // (no payload)

	// Ground items
	MsgSGroundItemAdd    uint16 = 0x0043 // id:i16, obj_index:i16, amount:u16, x:i16, y:i16
	MsgSGroundItemRemove uint16 = 0x0044 // id:i16
	MsgSCorpse           uint16 = 0x0045 // i16 x, i16 y, i16 grh_index

	// Bank
	MsgCBankOpen         uint16 = 0x0050 // i32 npc_instance_id
	MsgSBankContents     uint16 = 0x0051 // u8 count, count×(u8 slot, i16 obj_index, u16 amount), i32 gold
	MsgCBankDeposit      uint16 = 0x0052 // u8 inv_slot
	MsgCBankWithdraw     uint16 = 0x0053 // u8 bank_slot
	MsgCBankDepositGold  uint16 = 0x0054 // i32 amount
	MsgCBankWithdrawGold uint16 = 0x0055 // i32 amount

	// Trade
	MsgCTradeRequest  uint16 = 0x0060 // i32 target_char_id
	MsgSTrade         uint16 = 0x0061 // i32 from_char_id, str from_name
	MsgCTradeRespond  uint16 = 0x0062 // u8 accept
	MsgCTradeOffer    uint16 = 0x0063 // u8 inv_slot
	MsgCTradeRetract  uint16 = 0x0064 // u8 offer_slot
	MsgCTradeConfirm  uint16 = 0x0065 // (no payload)
	MsgCTradeCancel   uint16 = 0x0066 // (no payload)
	MsgSTradeState    uint16 = 0x0067 // u8 my_count, my×(i16,u16), u8 their_count, their×(i16,u16), u8 my_confirmed, u8 their_confirmed
	MsgSTradeComplete uint16 = 0x0068 // (no payload)
	MsgSTradeCancelled uint16 = 0x0069 // str reason

	// Quests
	MsgCQuestTalk     uint16 = 0x0070 // i32 npc_instance_id
	MsgSQuestOffer    uint16 = 0x0071 // see proto comment
	MsgCQuestAccept   uint16 = 0x0072 // u16 quest_id
	MsgCQuestTurnin   uint16 = 0x0073 // u16 quest_id
	MsgSQuestUpdate   uint16 = 0x0074 // u16 quest_id, str objectives_str
	MsgSQuestComplete uint16 = 0x0075 // u16 quest_id, i32 reward_gold, i32 reward_xp
	MsgSQuestIndicators uint16 = 0x0076 // u16 count, count×(i32 npc_instance_id, str indicator)

	// Misc S→C
	MsgSRareDropNotify   uint16 = 0x0080 // str item_name, u8 rarity, i16 x, i16 y
	MsgSAchievementUnlock uint16 = 0x0081 // u16 achievement_id, str name, str desc, i32 gold, i32 xp
	MsgSBountyUpdate     uint16 = 0x0090 // i32 target_char_id, str target_name, i32 bounty_amount
	MsgCEnchant          uint16 = 0x00A0 // u8 item_slot, u8 material_slot
	MsgSEnchantResult    uint16 = 0x00A1 // u8 result, u8 new_level, str message
	MsgCLeaderboardReq   uint16 = 0x00B0 // u8 type
	MsgSLeaderboardData  uint16 = 0x00B1 // u8 type, u8 count, count×(str name, i32 score)
	MsgSWorldEventStart  uint16 = 0x00C0 // str event_name, str location_hint
	MsgSWorldEventEnd    uint16 = 0x00C1 // str event_name, str result_msg
	MsgSTitleUpdate      uint16 = 0x00D0 // i32 instance_id, str title
	MsgSTourneyStart     uint16 = 0x00E0 // i32 duration_sec, str prize_desc
	MsgSTourneyEnd       uint16 = 0x00E1 // u8 count, count×(str name, i32 score, i32 gold)
	MsgSTourneyScores    uint16 = 0x00E2 // u8 count, count×(str name, i32 score)
	MsgSLoginReward      uint16 = 0x00F0 // u8 streak_day, i32 gold_reward, str bonus_msg

	// Day/night
	MsgSTimeOfDay uint16 = 0x0100 // u16 minutes (0-1439)

	// Faction
	MsgCPenance    uint16 = 0x0110 // str faction_name
	MsgSRepRefused uint16 = 0x0111 // str faction_name

	// Skills
	MsgSSkills        uint16 = 0x0210 // u8 count, count×(u8 slot, i16 level, i32 xp, i32 xp_needed)
	MsgSSkillRaise    uint16 = 0x0211 // u8 slot_1based, i16 new_level
	MsgSSkillProgress uint16 = 0x0212 // u8 skill_id, u16 duration_ms
	MsgSVitals        uint16 = 0x0213 // hunger:u8, thirst:u8
	MsgSSkillXP       uint16 = 0x0214 // u8 slot_1based, i32 current_xp, i32 xp_needed
	MsgSXPGain        uint16 = 0x0215 // i32 xp_gained
	MsgSLevelUp       uint16 = 0x0216 // u8 new_level

	// Magic
	MsgSSpellCast     uint16 = 0x0300 // i32 caster_id, u8 spell_id, i32 target_id, i16 tx, i16 ty
	MsgSSpellHit      uint16 = 0x0301 // i32 target_id, u8 spell_id, i16 damage, i16 heal, i16 mana_drain
	MsgSSpellChain    uint16 = 0x0302 // u8 spell_id, u8 count, count×i32 target_id
	MsgSStatusApplied uint16 = 0x0303 // i32 char_id, u8 status_id, u16 duration_ms
	MsgSStatusRemoved uint16 = 0x0304 // i32 char_id, u8 status_id
	MsgSSpellbook     uint16 = 0x0305 // u8 count, count×u8 spell_id
	MsgSSpellUnlock   uint16 = 0x0306 // u8 spell_id
	MsgSSpellShop     uint16 = 0x0307 // u8 count, count×(u8 spell_id, i16 price)

	// Abilities
	MsgSAbilityList    uint16 = 0x0140 // u8 count, count×u8 ability_id
	MsgSAbilityShop    uint16 = 0x0141 // u8 count, count×(u8 id, str name, u16 gold_cost, u8 req_level, u8 req_skill_id, u8 req_skill_val, u8 learned)
	MsgSAbilityLearned uint16 = 0x0143 // u8 ability_id
	MsgSAbilityFail    uint16 = 0x0144 // str reason
	MsgSProjectile     uint16 = 0x0145 // i32 caster_id, i32 target_id, u8 proj_type
	MsgSHotbar         uint16 = 0x0146 // u8 count, count×(u8 slot, u8 type, u8 id)
)

// Protocol framing constants.
const (
	ProtocolVersion  = 1
	NonceSize        = 16
	ChallengeSize    = 16 // Client attestation challenge size
	HMACSize         = 16   // Truncated HMAC-SHA256 (128-bit tag)
	PreAuthHdrSize   = 4    // u16 type + u16 len
	AuthHdrSize      = 8    // u32 seq + u16 type + u16 len
	FullPktOverhead  = 24   // AuthHdrSize + HMACSize
	MaxPayloadSize   = 65535
	PBKDF2Iterations = 1000

	// Auth limits
	AuthMaxAttempts    = 5
	AuthLockoutSeconds = 60
)

// RateLimit describes [tokens_per_sec, burst_capacity] for a message type.
type RateLimit struct {
	TokensPerSec float64
	Burst        float64
}

// RateLimits maps message type to its rate limit configuration.
var RateLimits = map[uint16]RateLimit{
	MsgCMove:         {15, 20},
	MsgCAttack:       {2, 4},
	MsgCPickup:       {5, 10},
	MsgCDrop:         {5, 10},
	MsgCEquip:        {5, 10},
	MsgCUnequip:      {5, 10},
	MsgCUseItem:      {5, 10},
	MsgCCastSpell:    {2, 4},
	MsgCChat:         {2, 5},
	MsgCUseSkill:     {2, 4},
	MsgCBuySpell:     {1, 2},
	MsgCLearnAbility: {1, 2},
	MsgCPing:         {1, 2},
}

// ChatType values for MsgSChat.
const (
	ChatNormal  uint8 = 0
	ChatSystem  uint8 = 1
	ChatGlobal  uint8 = 2
	ChatWhisper uint8 = 3
	ChatGM      uint8 = 4
)
