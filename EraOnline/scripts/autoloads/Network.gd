extends Node
## Era Online - Client Network Autoload
## Manages the single TLS-over-TCP connection to the game server.
## Replaces the original VB6 SocketWrench plain-TCP stub.
##
## State machine:
##   DISCONNECTED → CONNECTING → TLS_HANDSHAKE → PROTO_HANDSHAKE
##                → AUTHENTICATING → CONNECTED
##
## All game code talks to this autoload via signals and send_*() helpers.
## Never send raw bytes from outside — go through the public API.


# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal connected_to_server()
signal disconnected_from_server(reason: String)
signal connection_failed(reason: String)
signal authenticated(char_name: String)
signal auth_failed(reason: String)
signal latency_updated(ms: int)
signal char_list_received(chars: Array)
signal char_created(success: bool, reason: String)
signal char_deleted(success: bool, reason: String)

# Game-state signals (fired when authenticated packets arrive)
signal on_world_state(map_id: int, x: int, y: int)
signal on_move_char(char_id: int, x: int, y: int, heading: int)
signal on_set_char(char_id: int, body: int, head: int, weapon: int, shield: int,
		x: int, y: int, heading: int, hp: int, max_hp: int, char_name: String)
signal on_remove_char(char_id: int)
signal on_inventory(items: Array)
signal on_equip_change(slot: int, obj_index: int, amount: int)
signal on_stats(stats: Dictionary)
signal on_health(hp: int, mp: int, sta: int)
signal on_damage(char_id: int, damage: int, evaded: bool)
signal on_chat(char_id: int, chat_type: int, message: String)
signal on_map_change(map_id: int, x: int, y: int)
signal on_play_sound(sound_num: int)
signal on_kicked(reason: String)
signal on_server_msg(message: String)
signal on_death(killer_name: String)
signal shop_list_received(shop_name: String, items: Array)
signal buy_result(success: bool, reason: String)
signal rain_changed(is_raining: bool)
signal on_skills_received(skill_array: Array)  # Array[{level,xp,xp_needed}]
signal on_skill_raise(slot: int, value: int)
signal on_skill_xp(slot: int, current_xp: int, xp_needed: int)
signal on_skill_progress(skill_id: int, duration_ms: int)
signal on_ground_item_add(id: int, obj_index: int, amount: int, x: int, y: int)
signal on_ground_item_remove(id: int)
signal on_corpse(x: int, y: int, grh_index: int)
signal on_vitals(hunger: int, thirst: int)
signal on_spellbook(spell_ids: Array)
signal on_spell_unlock(spell_id: int)
signal on_spell_cast(caster_id: int, spell_id: int, target_id: int, tx: int, ty: int)
signal on_spell_hit(target_id: int, spell_id: int, damage: int, heal: int, mana_drain: int)
signal on_spell_chain(spell_id: int, target_ids: Array)
signal on_status_applied(char_id: int, status_id: int, duration_ms: int)
signal on_status_removed(char_id: int, status_id: int)
signal on_spell_shop(spells: Array)   # Array of {spell_id, price}
signal on_xp_gain(amount: int)
signal on_ability_list(ability_ids: Array)
signal on_hotbar(slots: Array)
signal on_ability_shop(abilities: Array)
signal on_ability_learned(ability_id: int)
signal on_level_up(new_level: int)
signal on_bank_contents(items: Array, gold: int)
signal sell_result(success: bool, reason: String)
signal on_trade_request(from_char_id: int, from_name: String)
signal on_trade_state(my_items: Array, their_items: Array, my_confirmed: bool, their_confirmed: bool)
signal on_trade_complete()
signal on_trade_cancelled(reason: String)
signal on_quest_offer(mode: int, quest_id: int, npc_name: String, quest_name: String, desc: String, objectives: Array, rewards: Dictionary)
signal on_quest_update(quest_id: int, progress: Dictionary)
signal on_quest_complete(quest_id: int, reward_gold: int, reward_xp: int)
signal on_quest_indicators(indicators: Dictionary)  # npc_instance_id (int) -> "!" or "?"
signal on_rare_drop(item_name: String, rarity: int, x: int, y: int)
signal on_achievement_unlock(achievement_id: int, name: String, desc: String, gold: int, xp: int)
signal on_bounty_update(char_id: int, char_name: String, bounty: int)
signal on_enchant_result(result: int, new_level: int, message: String)
signal on_leaderboard_data(type: int, entries: Array)
signal on_world_event_start(event_name: String, location: String)
signal on_world_event_end(event_name: String, result: String)
signal on_title_update(instance_id: int, title: String)
signal on_tourney_start(duration_sec: int, prize_desc: String)
signal on_tourney_end(results: Array)
signal on_tourney_scores(scores: Array)
signal on_login_reward(streak_day: int, gold: int, message: String)
signal on_time_of_day(hour: float)  # 0.0–24.0 in-game hours
signal on_projectile(caster_id: int, target_id: int, proj_type: int)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const DEFAULT_PORT      : int   = 6969
const PING_INTERVAL     : float = 5.0
const TIMEOUT_SECS      : float = 30.0
## Reconnect delays (seconds) for up to 3 automatic retries.
const RECONNECT_DELAYS  : Array = [1.0, 2.0, 4.0]
## Must match server.secret in server.yaml (used to derive session keys).
const SERVER_SECRET_STR : String = "edd8389eff853f4c924c06e2d7bd874f3c8b17ba3f53803da6130650cca2c808"
## Must match server.client_identity_secret in server.yaml.
## The server verifies this during the handshake — prevents non-official clients.
## Change this and update server.yaml whenever you release a new client binary.
const CLIENT_IDENTITY_SECRET : String = "1490c6bf1917f84d6bb0b31e95ea60fa"


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

enum State {
	DISCONNECTED,
	CONNECTING,
	TLS_HANDSHAKE,
	PROTO_HANDSHAKE,   # Waiting for SERVER_HELLO / CLIENT_HELLO exchange
	AUTHENTICATING,    # Waiting for AUTH_OK / AUTH_FAIL
	CHAR_SELECT,       # Auth OK — selecting or creating a character
	CONNECTED,         # In-world
}

## Official server — hardcoded, not user-configurable.
const SERVER_IP   : String = "5.78.207.11"
const SERVER_PORT : int    = 6969

var state           : State  = State.DISCONNECTED
var server_address  : String = SERVER_IP
var server_port     : int    = SERVER_PORT
var latency_ms      : int    = 0
## The local player's char_id as assigned by the server. 0 until authenticated.
var local_char_id   : int    = 0

## Launcher token — if set, sent via MsgAuthToken instead of username/password.
## Populated by load_launcher_token() or set directly before connect_to_server().
var launcher_token    : String = ""
## Username associated with the launcher token (used for display in SplashUI).
var launcher_username : String = ""

var _tcp            : StreamPeerTCP  = null
var _tls            : StreamPeerTLS  = null
var _recv_buf       : PackedByteArray = PackedByteArray()

var _session_key    : PackedByteArray = PackedByteArray()
var _server_nonce   : PackedByteArray = PackedByteArray()
var _client_nonce   : PackedByteArray = PackedByteArray()
var _session_id     : String = ""

var _send_seq       : int = 0
var _recv_seq       : int = 0
var _send_queue     : Array = []   # Array[PackedByteArray]

## Last world-state received from server; world_map reads this on _ready()
## to position the player when the scene loads after char select.
var last_world_state: Dictionary = {}   # {map_id, x, y}

var _ping_timer     : float = 0.0
var _ping_sent_at   : int   = 0

var _reconnect_attempt : int   = 0
var _reconnect_timer   : float = 0.0
var _reconnecting      : bool  = false

var _tls_connected_flag : bool = false  # Edge-detect: TLS just reached CONNECTED


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	set_process(false)


# ---------------------------------------------------------------------------
# Public API — connection
# ---------------------------------------------------------------------------

func connect_to_server(address: String = "127.0.0.1",
		port: int = DEFAULT_PORT) -> void:
	disconnect_from_server("Reconnecting")
	server_address = address
	server_port    = port
	_reconnect_attempt = 0
	_reconnecting      = false
	_start_connect()


func disconnect_from_server(reason: String = "Disconnected") -> void:
	if state != State.DISCONNECTED:
		_teardown(reason, false)


# ---------------------------------------------------------------------------
# Public API — authentication
# ---------------------------------------------------------------------------

func login(username: String, password: String) -> void:
	if state != State.PROTO_HANDSHAKE:
		push_warning("[Network] login() called in wrong state: %s" % State.keys()[state])
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_str(username)
	w.write_str(password)
	_send_preauth(NetProtocol.MsgType.AUTH_LOGIN, w.get_bytes())
	state = State.AUTHENTICATING


## Send a launcher pre-auth token instead of username/password.
## Called automatically if launcher_token is set when PROTO_HANDSHAKE is reached.
func login_with_token(token: String) -> void:
	if state != State.PROTO_HANDSHAKE:
		push_warning("[Network] login_with_token() called in wrong state: %s" % State.keys()[state])
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_str(token)
	_send_preauth(NetProtocol.MsgType.AUTH_TOKEN, w.get_bytes())
	state = State.AUTHENTICATING


## Load a launcher token from user://session.dat.
## File format (newline-separated):
##   line 1: token string (64 hex chars)
##   line 2: server host address (optional)
##   line 3: TCP game port (optional)
##   line 4: username (optional, for display)
## Returns true if a valid token was found.
## Also updates server_address, server_port, and launcher_username from the file.
func load_launcher_token() -> bool:
	launcher_token    = ""
	launcher_username = ""
	var f := FileAccess.open("user://session.dat", FileAccess.READ)
	if f == null:
		return false
	var token  := f.get_line().strip_edges()
	var addr   := f.get_line().strip_edges()
	var port_s := f.get_line().strip_edges()
	var uname  := f.get_line().strip_edges()
	f.close()
	if token.is_empty():
		return false
	launcher_token = token
	# Server address and port are hardcoded — ignore any saved values.
	server_address = SERVER_IP
	server_port    = SERVER_PORT
	if not uname.is_empty():
		launcher_username = uname
	return true


func register_account(username: String, password: String) -> void:
	if state != State.PROTO_HANDSHAKE:
		push_warning("[Network] register_account() called in wrong state")
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_str(username)
	w.write_str(password)
	_send_preauth(NetProtocol.MsgType.AUTH_REGISTER, w.get_bytes())
	state = State.AUTHENTICATING


# ---------------------------------------------------------------------------
# Public API — game actions
# ---------------------------------------------------------------------------

func send_move(direction: int) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(direction)
	_send_auth(NetProtocol.MsgType.C_MOVE, w.get_bytes())


func send_attack(target_id: int) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(target_id)
	_send_auth(NetProtocol.MsgType.C_ATTACK, w.get_bytes())


func send_pickup(ground_item_id: int) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_i16(ground_item_id)
	_send_auth(NetProtocol.MsgType.C_PICKUP, w.get_bytes())


func send_drop(slot: int, amount: int) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(slot)
	w.write_u16(amount)
	_send_auth(NetProtocol.MsgType.C_DROP, w.get_bytes())


func send_equip(slot: int) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(slot)
	_send_auth(NetProtocol.MsgType.C_EQUIP, w.get_bytes())


func send_unequip(slot: int) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(slot)
	_send_auth(NetProtocol.MsgType.C_UNEQUIP, w.get_bytes())


func send_use_item(slot: int) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(slot)
	_send_auth(NetProtocol.MsgType.C_USE_ITEM, w.get_bytes())


func send_cast_spell(spell_id: int, target_id: int, tx: int = 0, ty: int = 0) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(spell_id)
	w.write_i32(target_id)
	w.write_i16(tx)
	w.write_i16(ty)
	_send_auth(NetProtocol.MsgType.C_CAST_SPELL, w.get_bytes())


func send_buy_spell(npc_id: int, spell_id: int) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(npc_id)
	w.write_u8(spell_id)
	_send_auth(NetProtocol.MsgType.C_BUY_SPELL, w.get_bytes())


func send_chat(message: String) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_str(message)
	_send_auth(NetProtocol.MsgType.C_CHAT, w.get_bytes())


func send_hotbar(slots: Array) -> void:
	## Send unified hotbar state to server for persistence.
	## slots: Array of {type: "ability"|"spell", id: int} indexed 0-9 (null = empty)
	var w := NetProtocol.PacketWriter.new()
	var non_empty: Array = []
	for i in mini(slots.size(), 10):
		if slots[i] != null:
			non_empty.append({"slot": i, "type": slots[i].get("type", "ability"), "id": slots[i].get("id", 0)})
	w.write_u8(non_empty.size())
	for entry in non_empty:
		w.write_u8(entry["slot"])
		w.write_u8(0 if entry["type"] == "ability" else 1)
		w.write_u8(entry["id"])
	_send_auth(NetProtocol.MsgType.C_SAVE_HOTBAR, w.get_bytes())


func select_char(char_name: String) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_str(char_name)
	_send_auth(NetProtocol.MsgType.C_SELECT_CHAR, w.get_bytes())


func create_char(char_name: String, class_id: int, head: int, body: int = 0) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_str(char_name)
	w.write_u8(class_id)
	w.write_i16(head)
	w.write_i16(body)
	_send_auth(NetProtocol.MsgType.C_CREATE_CHAR, w.get_bytes())


func send_delete_char(char_name: String) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_str(char_name)
	_send_auth(NetProtocol.MsgType.C_DELETE_CHAR, w.get_bytes())


func send_shop_open(npc_id: int) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(npc_id)
	_send_auth(NetProtocol.MsgType.C_SHOP_OPEN, w.get_bytes())


func send_buy(npc_id: int, obj_index: int, amount: int) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(npc_id)
	w.write_i16(obj_index)
	w.write_u16(amount)
	_send_auth(NetProtocol.MsgType.C_BUY, w.get_bytes())


func send_use_skill(skill_id: int, tile_x: int, tile_y: int) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(skill_id)
	w.write_i16(tile_x)
	w.write_i16(tile_y)
	_send_auth(NetProtocol.MsgType.C_USE_SKILL, w.get_bytes())


func send_sell(npc_id: int, inv_slot: int) -> void:
	if state != State.CONNECTED:
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(npc_id)
	w.write_u8(inv_slot)
	_send_auth(NetProtocol.MsgType.C_SELL, w.get_bytes())

func send_bank_open(npc_id: int) -> void:
	if state != State.CONNECTED:
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(npc_id)
	_send_auth(NetProtocol.MsgType.C_BANK_OPEN, w.get_bytes())

func send_bank_deposit(inv_slot: int) -> void:
	if state != State.CONNECTED:
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(inv_slot)
	_send_auth(NetProtocol.MsgType.C_BANK_DEPOSIT, w.get_bytes())

func send_bank_withdraw(bank_slot: int, amount: int = 0) -> void:
	if state != State.CONNECTED:
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(bank_slot)
	w.write_i16(amount)
	_send_auth(NetProtocol.MsgType.C_BANK_WITHDRAW, w.get_bytes())

func send_bank_deposit_gold(amount: int) -> void:
	if state != State.CONNECTED:
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(amount)
	_send_auth(NetProtocol.MsgType.C_BANK_DEPOSIT_GOLD, w.get_bytes())

func send_bank_withdraw_gold(amount: int) -> void:
	if state != State.CONNECTED:
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(amount)
	_send_auth(NetProtocol.MsgType.C_BANK_WITHDRAW_GOLD, w.get_bytes())

func send_trade_request(target_id: int) -> void:
	if state != State.CONNECTED:
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(target_id)
	_send_auth(NetProtocol.MsgType.C_TRADE_REQUEST, w.get_bytes())

func send_trade_respond(accept: bool) -> void:
	if state != State.CONNECTED:
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(1 if accept else 0)
	_send_auth(NetProtocol.MsgType.C_TRADE_RESPOND, w.get_bytes())

func send_trade_offer(inv_slot: int) -> void:
	if state != State.CONNECTED:
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(inv_slot)
	_send_auth(NetProtocol.MsgType.C_TRADE_OFFER, w.get_bytes())

func send_trade_retract(offer_slot: int) -> void:
	if state != State.CONNECTED:
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(offer_slot)
	_send_auth(NetProtocol.MsgType.C_TRADE_RETRACT, w.get_bytes())

func send_trade_confirm() -> void:
	if state != State.CONNECTED:
		return
	_send_auth(NetProtocol.MsgType.C_TRADE_CONFIRM, PackedByteArray())

func send_trade_cancel() -> void:
	if state != State.CONNECTED:
		return
	_send_auth(NetProtocol.MsgType.C_TRADE_CANCEL, PackedByteArray())


func send_quest_talk(npc_id: int) -> void:
	if state != State.CONNECTED:
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(npc_id)
	_send_auth(NetProtocol.MsgType.C_QUEST_TALK, w.get_bytes())


func send_quest_accept(quest_id: int) -> void:
	if state != State.CONNECTED:
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_u16(quest_id)
	_send_auth(NetProtocol.MsgType.C_QUEST_ACCEPT, w.get_bytes())


func send_quest_turnin(quest_id: int) -> void:
	if state != State.CONNECTED:
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_u16(quest_id)
	_send_auth(NetProtocol.MsgType.C_QUEST_TURNIN, w.get_bytes())


func send_enchant(item_slot: int, material_slot: int) -> void:
	if state != State.CONNECTED:
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(item_slot)
	w.write_u8(material_slot)
	_send_auth(NetProtocol.MsgType.C_ENCHANT, w.get_bytes())


func send_leaderboard_request(type: int) -> void:
	if state != State.CONNECTED:
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(type)
	_send_auth(NetProtocol.MsgType.C_LEADERBOARD_REQUEST, w.get_bytes())


func send_learn_ability(ability_id: int) -> void:
	if state != State.CONNECTED:
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_u8(ability_id)
	_send_auth(NetProtocol.MsgType.C_LEARN_ABILITY, w.get_bytes())


# ---------------------------------------------------------------------------
# Per-frame processing
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	# --- Reconnect timer ---
	if _reconnecting:
		_reconnect_timer -= delta
		if _reconnect_timer <= 0.0:
			_reconnecting = false
			_start_connect()
		return

	if _tcp == null:
		return

	match state:
		State.CONNECTING:
			_poll_tcp_connecting()

		State.TLS_HANDSHAKE:
			_poll_tls_handshake()

		State.PROTO_HANDSHAKE, State.AUTHENTICATING, State.CHAR_SELECT, State.CONNECTED:
			_poll_tls_data(delta)


# ---------------------------------------------------------------------------
# Connection state polling
# ---------------------------------------------------------------------------

func _poll_tcp_connecting() -> void:
	_tcp.poll()
	match _tcp.get_status():
		StreamPeerTCP.STATUS_CONNECTING:
			pass  # Still connecting
		StreamPeerTCP.STATUS_CONNECTED:
			_tcp.set_no_delay(true)   # Must be set after socket is open
			# Wrap in TLS
			_tls = StreamPeerTLS.new()
			var err := _tls.connect_to_stream(_tcp, server_address,
					TLSOptions.client_unsafe())
			if err != OK:
				_teardown("TLS setup failed: %s" % error_string(err))
				return
			state = State.TLS_HANDSHAKE
			_tls_connected_flag = false
		StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
			_teardown("TCP connect failed")


func _poll_tls_handshake() -> void:
	_tls.poll()
	match _tls.get_status():
		StreamPeerTLS.STATUS_HANDSHAKING:
			pass  # Still shaking hands
		StreamPeerTLS.STATUS_CONNECTED:
			if not _tls_connected_flag:
				_tls_connected_flag = true
				state = State.PROTO_HANDSHAKE
				print("[Network] TLS connected — waiting for SERVER_HELLO")
				connected_to_server.emit()
		StreamPeerTLS.STATUS_ERROR, StreamPeerTLS.STATUS_DISCONNECTED:
			_teardown("TLS handshake failed")


func _poll_tls_data(delta: float) -> void:
	_tls.poll()
	match _tls.get_status():
		StreamPeerTLS.STATUS_ERROR, StreamPeerTLS.STATUS_DISCONNECTED:
			_teardown("Connection lost")
			return

	# Drain incoming bytes
	var available := _tls.get_available_bytes()
	if available > 0:
		var res := _tls.get_data(available)
		if res[0] == OK:
			_recv_buf.append_array(res[1] as PackedByteArray)

	# Parse packets from buffer
	if state == State.PROTO_HANDSHAKE or state == State.AUTHENTICATING:
		_parse_preauth_packets()
	elif state == State.CHAR_SELECT or state == State.CONNECTED:
		_parse_auth_packets()
		if state == State.CONNECTED:
			_ping_timer += delta
			if _ping_timer >= PING_INTERVAL:
				_ping_timer = 0.0
				_send_ping()

	# Flush outgoing queue
	_flush_send_queue()


# ---------------------------------------------------------------------------
# Packet parsing
# ---------------------------------------------------------------------------

func _parse_preauth_packets() -> void:
	while _recv_buf.size() >= NetProtocol.PREAUTH_HDR_SIZE:
		var r := NetProtocol.PacketReader.new(_recv_buf)
		var msg_type   := r.read_u16()
		var payload_len := r.read_u16()
		var total := NetProtocol.PREAUTH_HDR_SIZE + payload_len
		if _recv_buf.size() < total:
			break  # Incomplete packet — wait for more bytes
		var payload := r.read_bytes(payload_len)
		_recv_buf = _recv_buf.slice(total)
		if r.error:
			push_warning("[Network] Pre-auth read error on type 0x%04X" % msg_type)
			continue
		_dispatch_preauth(msg_type, payload)


func _parse_auth_packets() -> void:
	# Need at least the 8-byte header before we know total packet size
	while _recv_buf.size() >= NetProtocol.AUTH_HDR_SIZE:
		var r := NetProtocol.PacketReader.new(_recv_buf)
		var seq         := r.read_u32()
		var msg_type    := r.read_u16()
		var payload_len := r.read_u16()
		var total := NetProtocol.AUTH_HDR_SIZE + payload_len + NetProtocol.HMAC_SIZE
		if _recv_buf.size() < total:
			break  # Incomplete — wait for more bytes

		var header_plus_payload := _recv_buf.slice(0, NetProtocol.AUTH_HDR_SIZE + payload_len)
		var tag                 := _recv_buf.slice(
				NetProtocol.AUTH_HDR_SIZE + payload_len, total)
		_recv_buf = _recv_buf.slice(total)

		# Verify HMAC
		if not NetProtocol.verify_packet(_session_key, header_plus_payload, tag):
			push_warning("[Network] HMAC mismatch — dropping packet (possible injection)")
			_teardown("Security error: invalid packet signature")
			return

		# Verify sequence number
		if seq != _recv_seq:
			push_warning("[Network] Sequence mismatch: expected %d got %d" % [_recv_seq, seq])
			_teardown("Security error: sequence mismatch")
			return
		_recv_seq += 1

		var payload := header_plus_payload.slice(NetProtocol.AUTH_HDR_SIZE)
		_dispatch_auth(msg_type, payload)


# ---------------------------------------------------------------------------
# Message dispatch
# ---------------------------------------------------------------------------

func _dispatch_preauth(msg_type: int, payload: PackedByteArray) -> void:
	var r := NetProtocol.PacketReader.new(payload)
	match msg_type:
		NetProtocol.MsgType.SERVER_HELLO:
			var version := r.read_u16()
			_server_nonce = r.read_bytes(NetProtocol.NONCE_SIZE)
			# Read server's client attestation challenge (new in Go server protocol).
			var client_challenge := r.read_bytes(NetProtocol.NONCE_SIZE)
			print("[Network] SERVER_HELLO v%d — sending CLIENT_HELLO" % version)
			# Generate our nonce.
			_client_nonce = Crypto.new().generate_random_bytes(NetProtocol.NONCE_SIZE)
			# Compute client proof: HMAC-SHA256(CLIENT_IDENTITY_SECRET, challenge || server_nonce)[0:16]
			var secret_bytes := CLIENT_IDENTITY_SECRET.to_utf8_buffer()
			var msg := PackedByteArray()
			msg.append_array(client_challenge)
			msg.append_array(_server_nonce)
			var client_proof := NetProtocol.hmac(secret_bytes, msg, NetProtocol.HMAC_SIZE)
			var w := NetProtocol.PacketWriter.new()
			w.write_bytes(_client_nonce)
			w.write_bytes(client_proof)
			_send_preauth(NetProtocol.MsgType.CLIENT_HELLO, w.get_bytes())
			# If a launcher token is set, send it immediately after CLIENT_HELLO
			# so LoginUI never needs to display.
			if launcher_token != "":
				print("[Network] Launcher token present — sending AUTH_TOKEN automatically")
				login_with_token(launcher_token)

		NetProtocol.MsgType.AUTH_OK:
			_session_id   = r.read_str()
			local_char_id = r.read_i32()
			var char_name := r.read_str()
			# Derive session key — must match server derivation
			var secret := SERVER_SECRET_STR.to_utf8_buffer()
			_session_key = NetProtocol.derive_session_key(secret,
					_client_nonce, _server_nonce, _session_id)
			_send_seq = 0
			_recv_seq = 0
			state = State.CHAR_SELECT
			# Token consumed — clear it so reconnects don't reuse it
			launcher_token = ""
			print("[Network] Auth OK as '%s' char_id=%d — awaiting char list" % [
				char_name, local_char_id])

		NetProtocol.MsgType.AUTH_FAIL:
			var reason := r.read_str()
			push_warning("[Network] Auth failed: " + reason)
			state = State.PROTO_HANDSHAKE
			# If token was rejected, delete session.dat so next launch re-authenticates
			if launcher_token != "":
				launcher_token = ""
				DirAccess.remove_absolute(
					ProjectSettings.globalize_path("user://session.dat"))
			auth_failed.emit(reason)

		_:
			push_warning("[Network] Unexpected pre-auth msg 0x%04X" % msg_type)


func _dispatch_auth(msg_type: int, payload: PackedByteArray) -> void:
	var r := NetProtocol.PacketReader.new(payload)
	match msg_type:
		NetProtocol.MsgType.S_CHAR_LIST:
			var count := r.read_u8()
			var chars: Array = []
			for _i in count:
				chars.append({
					"name":     r.read_str(),
					"level":    r.read_u8(),
					"class_id": r.read_u8(),
					"body":     r.read_i16(),
					"head":     r.read_i16(),
				})
			char_list_received.emit(chars)

		NetProtocol.MsgType.S_CREATE_RESULT:
			char_created.emit(r.read_u8() != 0, r.read_str())

		NetProtocol.MsgType.S_DELETE_RESULT:
			var ok := r.read_u8() != 0
			var reason := r.read_str()
			char_deleted.emit(ok, reason)

		NetProtocol.MsgType.S_WORLD_STATE:
			if state == State.CHAR_SELECT:
				state = State.CONNECTED
				print("[Network] Entering world — state CONNECTED")
			var map_id := r.read_i32()
			var wx     := r.read_i16()
			var wy     := r.read_i16()
			last_world_state = {"map_id": map_id, "x": wx, "y": wy}
			on_world_state.emit(map_id, wx, wy)

		NetProtocol.MsgType.S_MOVE_CHAR:
			on_move_char.emit(r.read_i32(), r.read_i16(), r.read_i16(), r.read_u8())

		NetProtocol.MsgType.S_SET_CHAR:
			var cid     := r.read_i32()
			var body    := r.read_i16()
			var head    := r.read_i16()
			var weapon  := r.read_i16()
			var shield  := r.read_i16()
			var cx      := r.read_i16()
			var cy      := r.read_i16()
			var heading := r.read_u8()
			var hp      := r.read_i16()
			var max_hp  := r.read_i16()
			var cname   := r.read_str()
			on_set_char.emit(cid, body, head, weapon, shield, cx, cy, heading, hp, max_hp, cname)

		NetProtocol.MsgType.S_REMOVE_CHAR:
			on_remove_char.emit(r.read_i32())

		NetProtocol.MsgType.S_INVENTORY:
			var count := r.read_u8()
			var items : Array = []
			for _i in count:
				items.append({
					"slot":      r.read_u8(),
					"obj_index": r.read_i16(),
					"amount":    r.read_u16(),
					"equipped":  r.read_u8(),
				})
			on_inventory.emit(items)

		NetProtocol.MsgType.S_EQUIP_CHANGE:
			on_equip_change.emit(r.read_u8(), r.read_i16(), r.read_u16())

		NetProtocol.MsgType.S_STATS:
			on_stats.emit({
				"level":    r.read_u8(),
				"hp":       r.read_i16(), "max_hp":   r.read_i16(),
				"mp":       r.read_i16(), "max_mp":   r.read_i16(),
				"sta":      r.read_i16(), "max_sta":  r.read_i16(),
				"exp":      r.read_i32(), "next_exp": r.read_i32(),
				"gold":     r.read_i32(),
			})

		NetProtocol.MsgType.S_HEALTH:
			on_health.emit(r.read_i16(), r.read_i16(), r.read_i16())

		NetProtocol.MsgType.S_DAMAGE:
			on_damage.emit(r.read_i32(), r.read_i16(), r.read_u8() != 0)

		NetProtocol.MsgType.S_CHAT:
			on_chat.emit(r.read_i32(), r.read_u8(), r.read_str())

		NetProtocol.MsgType.S_MAP_CHANGE:
			on_map_change.emit(r.read_i32(), r.read_i16(), r.read_i16())

		NetProtocol.MsgType.S_SET_STATS:
			# Partial stat patch: count:u16 then count×(key:str, value:i32)
			var _ss_count: int = r.read_u16()
			var _ss_dict: Dictionary = {}
			for _ssi in _ss_count:
				var _k: String = r.read_str()
				var _v: int    = r.read_i32()
				_ss_dict[_k] = _v
			if not _ss_dict.is_empty():
				on_stats.emit(_ss_dict)

		NetProtocol.MsgType.S_REP_REFUSED:
			var _rf_faction: String = r.read_str()
			on_server_msg.emit("The merchant refuses to deal with you (faction: %s)." % _rf_faction)

		NetProtocol.MsgType.S_PLAY_SOUND:
			on_play_sound.emit(r.read_u8())

		NetProtocol.MsgType.S_PONG:
			var sent_at := r.read_i64()
			latency_ms = Time.get_ticks_msec() - sent_at
			latency_updated.emit(latency_ms)

		NetProtocol.MsgType.S_KICK:
			var reason := r.read_str()
			on_kicked.emit(reason)
			_teardown("Kicked: " + reason, false)

		NetProtocol.MsgType.S_SERVER_MSG:
			on_server_msg.emit(r.read_str())

		NetProtocol.MsgType.S_DEATH:
			on_death.emit(r.read_str())

		NetProtocol.MsgType.S_SHOP_LIST:
			var shop_name := r.read_str()
			var count := r.read_u8()
			var items: Array = []
			for _i in count:
				items.append({
					"obj_index": r.read_i16(),
					"price":     r.read_i32(),
					"name":      r.read_str(),
				})
			shop_list_received.emit(shop_name, items)

		NetProtocol.MsgType.S_BUY_RESULT:
			buy_result.emit(r.read_u8() != 0, r.read_str())

		NetProtocol.MsgType.S_RAIN_ON:
			rain_changed.emit(true)

		NetProtocol.MsgType.S_RAIN_OFF:
			rain_changed.emit(false)

		NetProtocol.MsgType.S_SKILLS:
			var count := r.read_u8()
			var skill_array: Array = []
			skill_array.resize(28)
			for k in 28:
				skill_array[k] = {"level": 0, "xp": 0, "xp_needed": 100}
			for _i in count:
				var slot      := r.read_u8()    # 1-based
				var lv        := r.read_i16()
				var xp        := r.read_i32()
				var xp_needed := r.read_i32()
				if slot >= 1 and slot <= 28:
					skill_array[slot - 1] = {"level": lv, "xp": xp, "xp_needed": xp_needed}
			on_skills_received.emit(skill_array)

		NetProtocol.MsgType.S_SKILL_RAISE:
			var slot  := r.read_u8()
			var value := r.read_i16()
			on_skill_raise.emit(slot, value)

		NetProtocol.MsgType.S_SKILL_XP:
			var slot      := r.read_u8()
			var cur_xp    := r.read_i32()
			var xp_needed := r.read_i32()
			on_skill_xp.emit(slot, cur_xp, xp_needed)

		NetProtocol.MsgType.S_SKILL_PROGRESS:
			var skill_id := r.read_u8()
			var duration_ms := r.read_u16()
			on_skill_progress.emit(skill_id, duration_ms)

		NetProtocol.MsgType.S_GROUND_ITEM_ADD:
			var id  := r.read_i16()
			var obj := r.read_i16()
			var amt := r.read_u16()
			var x   := r.read_i16()
			var y   := r.read_i16()
			on_ground_item_add.emit(id, obj, amt, x, y)

		NetProtocol.MsgType.S_GROUND_ITEM_REMOVE:
			on_ground_item_remove.emit(r.read_i16())

		NetProtocol.MsgType.S_CORPSE:
			var cx := r.read_i16()
			var cy := r.read_i16()
			var cg := r.read_i16()
			on_corpse.emit(cx, cy, cg)

		NetProtocol.MsgType.S_VITALS:
			on_vitals.emit(r.read_u8(), r.read_u8())

		NetProtocol.MsgType.S_SPELLBOOK:
			var count := r.read_u8()
			var ids: Array[int] = []
			for _i in count:
				ids.append(r.read_u8())
			on_spellbook.emit(ids)

		NetProtocol.MsgType.S_SPELL_UNLOCK:
			on_spell_unlock.emit(r.read_u8())

		NetProtocol.MsgType.S_SPELL_CAST:
			var cid   := r.read_i32()
			var sid   := r.read_u8()
			var tgt   := r.read_i32()
			var stx   := r.read_i16()
			var sty   := r.read_i16()
			on_spell_cast.emit(cid, sid, tgt, stx, sty)

		NetProtocol.MsgType.S_SPELL_HIT:
			var htgt  := r.read_i32()
			var hsid  := r.read_u8()
			var hdmg  := r.read_i16()
			var hheal := r.read_i16()
			var hmana := r.read_i16()
			on_spell_hit.emit(htgt, hsid, hdmg, hheal, hmana)

		NetProtocol.MsgType.S_SPELL_CHAIN:
			var csid  := r.read_u8()
			var ccnt  := r.read_u8()
			var ctgts: Array = []
			for _i in ccnt:
				ctgts.append(r.read_i32())
			on_spell_chain.emit(csid, ctgts)

		NetProtocol.MsgType.S_STATUS_APPLIED:
			on_status_applied.emit(r.read_i32(), r.read_u8(), r.read_u16())

		NetProtocol.MsgType.S_STATUS_REMOVED:
			on_status_removed.emit(r.read_i32(), r.read_u8())

		NetProtocol.MsgType.S_XP_GAIN:
			on_xp_gain.emit(r.read_i32())

		NetProtocol.MsgType.S_LEVEL_UP:
			on_level_up.emit(int(r.read_u8()))

		NetProtocol.MsgType.S_SPELL_SHOP:
			var sc := r.read_u8()
			var shopspells: Array = []
			for _i in sc:
				var ssid  := r.read_u8()
				var sprice := r.read_i16()
				shopspells.append({"spell_id": ssid, "price": sprice})
			on_spell_shop.emit(shopspells)

		NetProtocol.MsgType.S_BANK_CONTENTS:
			var bank_count := r.read_u8()
			var bank_items: Array = []
			for _i in bank_count:
				bank_items.append({
					"slot":      r.read_u8(),
					"obj_index": r.read_i16(),
					"amount":    r.read_u16(),
				})
			var bank_gold := r.read_i32()
			on_bank_contents.emit(bank_items, bank_gold)

		NetProtocol.MsgType.S_TRADE_REQUEST:
			var from_char_id := r.read_i32()
			var from_name := r.read_str()
			on_trade_request.emit(from_char_id, from_name)

		NetProtocol.MsgType.S_TRADE_STATE:
			var count_my := r.read_u8()
			var my_items: Array = []
			for _i in count_my:
				my_items.append({"obj_index": r.read_i16(), "amount": r.read_u16()})
			var count_their := r.read_u8()
			var their_items: Array = []
			for _i in count_their:
				their_items.append({"obj_index": r.read_i16(), "amount": r.read_u16()})
			var my_conf := r.read_u8() != 0
			var their_conf := r.read_u8() != 0
			on_trade_state.emit(my_items, their_items, my_conf, their_conf)

		NetProtocol.MsgType.S_TRADE_COMPLETE:
			on_trade_complete.emit()

		NetProtocol.MsgType.S_TRADE_CANCELLED:
			on_trade_cancelled.emit(r.read_str())

		NetProtocol.MsgType.S_QUEST_OFFER:
			var qmode      := r.read_u8()
			var qid        := r.read_u16()
			var qnpc_name  := r.read_str()
			var qname      := r.read_str()
			var qdesc      := r.read_str()
			var obj_count  := r.read_u8()
			var objectives: Array = []
			for _qi in obj_count:
				objectives.append({
					"label":    r.read_str(),
					"required": r.read_u16(),
					"type":     r.read_u8(),
				})
			var rgold := r.read_i32()
			var rxp   := r.read_i32()
			var item_count := r.read_u8()
			var ritems: Array = []
			for _ri in item_count:
				ritems.append({
					"obj_index": r.read_i16(),
					"amount":    r.read_u16(),
					"name":      r.read_str(),
				})
			on_quest_offer.emit(qmode, qid, qnpc_name, qname, qdesc, objectives,
					{"gold": rgold, "xp": rxp, "items": ritems})

		NetProtocol.MsgType.S_QUEST_UPDATE:
			var uqid       := r.read_u16()
			var obj_str    := r.read_str()
			on_quest_update.emit(uqid, {"objectives_str": obj_str})

		NetProtocol.MsgType.S_QUEST_COMPLETE:
			var cqid  := r.read_u16()
			var cgold := r.read_i32()
			var cxp   := r.read_i32()
			on_quest_complete.emit(cqid, cgold, cxp)

		NetProtocol.MsgType.S_QUEST_INDICATORS:
			var ind_count := r.read_u16()
			var indicators: Dictionary = {}
			for _ii in ind_count:
				var inst_id := r.read_i32()
				var ind     := r.read_str()
				indicators[inst_id] = ind
			on_quest_indicators.emit(indicators)

		NetProtocol.MsgType.S_RARE_DROP_NOTIFY:
			var rd_name   := r.read_str()
			var rd_rarity := r.read_u8()
			var rd_x      := r.read_i16()
			var rd_y      := r.read_i16()
			on_rare_drop.emit(rd_name, rd_rarity, rd_x, rd_y)

		NetProtocol.MsgType.S_ACHIEVEMENT_UNLOCK:
			var ach_id   := r.read_u16()
			var ach_name := r.read_str()
			var ach_desc := r.read_str()
			var ach_gold := r.read_i32()
			var ach_xp   := r.read_i32()
			on_achievement_unlock.emit(ach_id, ach_name, ach_desc, ach_gold, ach_xp)

		NetProtocol.MsgType.S_BOUNTY_UPDATE:
			var bnt_char_id := r.read_i32()
			var bnt_name    := r.read_str()
			var bnt_amount  := r.read_i32()
			on_bounty_update.emit(bnt_char_id, bnt_name, bnt_amount)

		NetProtocol.MsgType.S_ENCHANT_RESULT:
			var enc_result := r.read_u8()
			var enc_level  := r.read_u8()
			var enc_msg    := r.read_str()
			on_enchant_result.emit(enc_result, enc_level, enc_msg)

		NetProtocol.MsgType.S_LEADERBOARD_DATA:
			var lb_type  := r.read_u8()
			var lb_count := r.read_u8()
			var lb_entries: Array = []
			for _li in lb_count:
				lb_entries.append({
					"name":  r.read_str(),
					"score": r.read_i32(),
				})
			on_leaderboard_data.emit(lb_type, lb_entries)

		NetProtocol.MsgType.S_WORLD_EVENT_START:
			var we_name     := r.read_str()
			var we_location := r.read_str()
			on_world_event_start.emit(we_name, we_location)

		NetProtocol.MsgType.S_WORLD_EVENT_END:
			var wee_name   := r.read_str()
			var wee_result := r.read_str()
			on_world_event_end.emit(wee_name, wee_result)

		NetProtocol.MsgType.S_TITLE_UPDATE:
			var tu_instance_id := r.read_i32()
			var tu_title       := r.read_str()
			on_title_update.emit(tu_instance_id, tu_title)

		NetProtocol.MsgType.S_TOURNEY_START:
			var ts_duration := r.read_i32()
			var ts_prize    := r.read_str()
			on_tourney_start.emit(ts_duration, ts_prize)

		NetProtocol.MsgType.S_TOURNEY_END:
			var te_count := r.read_u8()
			var te_results: Array = []
			for _ti in te_count:
				te_results.append({
					"name":        r.read_str(),
					"score":       r.read_i32(),
					"gold_reward": r.read_i32(),
				})
			on_tourney_end.emit(te_results)

		NetProtocol.MsgType.S_TOURNEY_SCORES:
			var tsc_count := r.read_u8()
			var tsc_scores: Array = []
			for _tsi in tsc_count:
				tsc_scores.append({
					"name":  r.read_str(),
					"score": r.read_i32(),
				})
			on_tourney_scores.emit(tsc_scores)

		NetProtocol.MsgType.S_LOGIN_REWARD:
			var lr_streak := r.read_u8()
			var lr_gold   := r.read_i32()
			var lr_msg    := r.read_str()
			on_login_reward.emit(lr_streak, lr_gold, lr_msg)

		NetProtocol.MsgType.S_TIME_OF_DAY:
			on_time_of_day.emit(float(r.read_u16()) / 60.0)  # minutes → hours

		NetProtocol.MsgType.S_ABILITY_LIST:
			var al_count := r.read_u8()
			var al_ids: Array = []
			for _ali in al_count:
				al_ids.append(r.read_u8())
			on_ability_list.emit(al_ids)

		NetProtocol.MsgType.S_ABILITY_SHOP:
			var as_count := r.read_u8()
			var as_abilities: Array = []
			for _asi in as_count:
				as_abilities.append({
					"id":            r.read_u8(),
					"name":          r.read_str(),
					"gold_cost":     r.read_u16(),
					"req_level":     r.read_u8(),
					"req_skill_id":  r.read_u8(),
					"req_skill_val": r.read_u8(),
					"learned":       r.read_u8() != 0,
				})
			on_ability_shop.emit(as_abilities)

		NetProtocol.MsgType.S_ABILITY_LEARNED:
			on_ability_learned.emit(r.read_u8())

		NetProtocol.MsgType.S_ABILITY_FAIL:
			on_server_msg.emit(r.read_str())

		NetProtocol.MsgType.S_PROJECTILE:
			on_projectile.emit(r.read_i32(), r.read_i32(), r.read_u8())

		NetProtocol.MsgType.S_HOTBAR:
			var hb_count := r.read_u8()
			var hb_slots: Array = []
			for _hi in hb_count:
				var slot_idx := r.read_u8()
				var slot_type := r.read_u8()
				var slot_id   := r.read_u8()
				hb_slots.append({"slot": slot_idx, "type": "ability" if slot_type == 0 else "spell", "id": slot_id})
			on_hotbar.emit(hb_slots)

		_:
			push_warning("[Network] Unknown auth msg 0x%04X" % msg_type)


# ---------------------------------------------------------------------------
# Sending
# ---------------------------------------------------------------------------

func _send_preauth(msg_type: int, payload: PackedByteArray) -> void:
	var packet := NetProtocol.frame_preauth(msg_type, payload)
	_queue_packet(packet)


func _send_auth(msg_type: int, payload: PackedByteArray) -> void:
	if state != State.CONNECTED and state != State.CHAR_SELECT:
		push_warning("[Network] send_auth called in wrong state: %s" % State.keys()[state])
		return
	var packet := NetProtocol.frame_auth(msg_type, payload, _send_seq, _session_key)
	_send_seq += 1
	_queue_packet(packet)


func _queue_packet(packet: PackedByteArray) -> void:
	_send_queue.append(packet)


func _flush_send_queue() -> void:
	while not _send_queue.is_empty():
		if _tls == null or _tls.get_status() != StreamPeerTLS.STATUS_CONNECTED:
			break
		var packet: PackedByteArray = _send_queue[0]
		var err := _tls.put_data(packet)
		if err != OK:
			push_warning("[Network] put_data error: %s" % error_string(err))
			break
		_send_queue.remove_at(0)


func _send_ping() -> void:
	_ping_sent_at = Time.get_ticks_msec()
	var w := NetProtocol.PacketWriter.new()
	w.write_i64(_ping_sent_at)
	_send_auth(NetProtocol.MsgType.C_PING, w.get_bytes())


# ---------------------------------------------------------------------------
# Connection management
# ---------------------------------------------------------------------------

func _start_connect() -> void:
	_tcp = StreamPeerTCP.new()
	var err := _tcp.connect_to_host(server_address, server_port)
	if err != OK:
		_teardown("connect_to_host failed: %s" % error_string(err))
		return
	state      = State.CONNECTING
	_recv_buf  = PackedByteArray()
	_send_seq  = 0
	_recv_seq  = 0
	_send_queue.clear()
	set_process(true)
	print("[Network] Connecting to %s:%d..." % [server_address, server_port])


func _teardown(reason: String, try_reconnect: bool = true) -> void:
	var was_connected := (state == State.CONNECTED or state == State.CHAR_SELECT)

	if _tls != null:
		_tls.disconnect_from_stream()
		_tls = null
	if _tcp != null:
		_tcp.disconnect_from_host()
		_tcp = null

	_recv_buf.clear()
	_send_queue.clear()
	_session_key     = PackedByteArray()
	_session_id      = ""
	local_char_id    = 0
	last_world_state = {}
	_send_seq        = 0
	_recv_seq        = 0
	state            = State.DISCONNECTED

	if was_connected:
		disconnected_from_server.emit(reason)

	# Auto-reconnect for unexpected disconnects
	if try_reconnect and was_connected and _reconnect_attempt < RECONNECT_DELAYS.size():
		var delay: float = RECONNECT_DELAYS[_reconnect_attempt]
		_reconnect_attempt += 1
		_reconnecting      = true
		_reconnect_timer   = delay
		print("[Network] Reconnecting in %.1fs (attempt %d)..." % [
			delay, _reconnect_attempt])
	elif try_reconnect and _reconnect_attempt >= RECONNECT_DELAYS.size():
		set_process(false)
		connection_failed.emit("Could not reconnect to %s:%d" % [
			server_address, server_port])
	else:
		set_process(false)
