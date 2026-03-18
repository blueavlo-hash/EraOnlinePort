class_name ServerMain
extends Node
## Era Online - Headless Game Server
## Run with: godot --headless --script server/server_main.gd
##
## Startup sequence:
##   1. Load or generate TLS key + self-signed certificate
##   2. Load or generate 32-byte server secret (for session key derivation)
##   3. Bind TCPServer on configured port
##   4. Accept connections each frame, create ClientSession per client
##   5. Poll all sessions, route messages to GameHandler
##
## Config via command-line args:
##   --port 7777      Override listen port
##   --max-clients 200

## Must match Network.gd SERVER_SECRET_STR — override by loading from file.
const SERVER_SECRET_STR : String = "EraOnlineSecret2025ChangeInProd!"

const DEFAULT_PORT       : int = 7777
const DEFAULT_MAX_CLIENTS: int = 200
const CERT_KEY_PATH      : String = "user://server_key.pem"
const CERT_PATH          : String = "user://server_cert.pem"
const SECRET_PATH        : String = "user://server_secret.bin"

var _port        : int = DEFAULT_PORT
var _max_clients : int = DEFAULT_MAX_CLIENTS

var _server      : TCPServer = TCPServer.new()
var _tls_opts    : TLSOptions
var _server_secret : PackedByteArray

## Active sessions: session_id (String) → ClientSession
var _sessions    : Dictionary = {}
var _session_counter : int = 0
var _char_id_counter : int = 1

var _db          : ServerDB
var _auth        : AuthHandler
var _game        : GameHandler


# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------

func _ready() -> void:
	_parse_args()
	_setup_database()
	_load_or_generate_secret()
	_load_or_generate_tls()
	_bind_server()
	_log("Era Online Server started on port %d (max %d clients)" % [
		_port, _max_clients])


func _parse_args() -> void:
	var args := OS.get_cmdline_args()
	for i in args.size():
		match args[i]:
			"--port":
				if i + 1 < args.size():
					_port = int(args[i + 1])
			"--max-clients":
				if i + 1 < args.size():
					_max_clients = int(args[i + 1])


func _setup_database() -> void:
	_db   = ServerDB.new()
	_db.initialize()
	_auth = AuthHandler.new(_db)
	_game = GameHandler.new(_sessions, _db)
	_log("Database initialized")


func _load_or_generate_secret() -> void:
	if FileAccess.file_exists(SECRET_PATH):
		var f := FileAccess.open(SECRET_PATH, FileAccess.READ)
		_server_secret = f.get_buffer(32)
		f.close()
		_log("Server secret loaded")
	else:
		_server_secret = Crypto.new().generate_random_bytes(32)
		var f := FileAccess.open(SECRET_PATH, FileAccess.WRITE)
		f.store_buffer(_server_secret)
		f.close()
		_log("Server secret generated and saved to " + SECRET_PATH)
		_log_security("WARNING: Deploy with a fixed server secret in production!")


func _load_or_generate_tls() -> void:
	var key  : CryptoKey
	var cert : X509Certificate

	if FileAccess.file_exists(CERT_KEY_PATH) and FileAccess.file_exists(CERT_PATH):
		key  = CryptoKey.new()
		cert = X509Certificate.new()
		var key_err  := key.load(CERT_KEY_PATH)
		var cert_err := cert.load(CERT_PATH)
		if key_err == OK and cert_err == OK:
			_log("TLS certificate loaded from disk")
		else:
			push_warning("[Server] Failed to load cert/key — regenerating")
			key  = null
			cert = null

	if key == null or cert == null:
		var crypto := Crypto.new()
		key  = crypto.generate_rsa(2048)
		cert = crypto.generate_self_signed_certificate(key,
				"CN=EraOnlineServer,O=EraOnline,C=AU",
				"20250101000000", "20350101000000")
		key.save(CERT_KEY_PATH)
		cert.save(CERT_PATH)
		_log("Self-signed TLS certificate generated and saved")

	_tls_opts = TLSOptions.server(key, cert)


func _bind_server() -> void:
	var err := _server.listen(_port)
	if err != OK:
		push_error("[Server] Failed to bind port %d: %s" % [_port, error_string(err)])
		get_tree().quit(1)
		return
	set_process(true)


# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	_accept_connections()
	_poll_sessions()
	_cleanup_sessions()


func _accept_connections() -> void:
	while _server.is_connection_available():
		if _sessions.size() >= _max_clients:
			# Accept and immediately close to send TCP RST
			var tcp := _server.take_connection()
			tcp.disconnect_from_host()
			_log_security("Connection refused — server full (%d/%d)" % [
				_sessions.size(), _max_clients])
			return

		var tcp := _server.take_connection()
		var sid := _new_session_id()
		var session := ClientSession.new(sid, tcp, _tls_opts)
		session.on_message = _on_message
		_sessions[sid] = session
		_log("New connection: %s from %s:%d" % [
			sid, tcp.get_connected_host(), tcp.get_connected_port()])


func _poll_sessions() -> void:
	for sid in _sessions:
		(_sessions[sid] as ClientSession).poll()


func _cleanup_sessions() -> void:
	var to_remove : Array = []
	for sid in _sessions:
		var s : ClientSession = _sessions[sid]
		if s.state == ClientSession.State.DISCONNECTED or s.is_timed_out():
			to_remove.append(sid)

	for sid in to_remove:
		var s : ClientSession = _sessions[sid]
		if s.state != ClientSession.State.DISCONNECTED:
			s.disconnect("Timed out")
		if s.char_id > 0:
			_broadcast_to_map(s.map_id, NetProtocol.MsgType.S_REMOVE_CHAR,
					_make_remove_char_payload(s.char_id), sid)
		_sessions.erase(sid)
		_log("Session removed: %s (%s)" % [sid, s.username if s.username else "unauthenticated"])


# ---------------------------------------------------------------------------
# Message routing
# ---------------------------------------------------------------------------

func _on_message(session: ClientSession, msg_type: int,
		reader: NetProtocol.PacketReader) -> void:
	match msg_type:
		NetProtocol.MsgType.AUTH_LOGIN:
			_handle_auth(session, false, reader)
		NetProtocol.MsgType.AUTH_REGISTER:
			_handle_auth(session, true, reader)
		_:
			if session.state == ClientSession.State.CONNECTED:
				_game.handle(session, msg_type, reader)
			else:
				_log_security("Game msg 0x%04X from unauthenticated session %s" % [
					msg_type, session.session_id])


# ---------------------------------------------------------------------------
# Auth handler
# ---------------------------------------------------------------------------

func _handle_auth(session: ClientSession, is_register: bool,
		reader: NetProtocol.PacketReader) -> void:
	var username := reader.read_str()
	var password := reader.read_str()

	if reader.error:
		_send_auth_fail(session, "Malformed auth packet")
		return

	# Basic username validation before hitting the DB
	if not AuthHandler.is_valid_username(username):
		_send_auth_fail(session, "Invalid username or password")
		_log_security("Bad username format from %s" % session.session_id)
		return

	var result : Dictionary
	if is_register:
		result = _auth.register(username, password)
		if not result["ok"]:
			_send_auth_fail(session, result["error"])
			_log("Register failed for '%s': %s" % [username, result["error"]])
			return
		# Auto-login after successful registration
		result = _auth.login(username, password)

	else:
		result = _auth.login(username, password)

	if not result["ok"]:
		_send_auth_fail(session, result["error"])
		_log_security("Login failed for '%s'" % username)
		return

	# --- Auth success ---
	session.username   = username
	session.account_id = result["account_id"]
	session.char_id    = _next_char_id()

	# Load saved character position
	var acc  := _db.get_account(username)
	var char_data: Dictionary = acc.get("character", {})
	session.map_id  = char_data.get("map_id", 3)
	session.tile_x  = char_data.get("x", 10)
	session.tile_y  = char_data.get("y", 10)
	session.heading = char_data.get("heading", 3)

	# Derive session key (must match client derivation)
	session.session_key = NetProtocol.derive_session_key(
			_server_secret,
			session.client_nonce,
			session.server_nonce,
			session.session_id)

	session.state = ClientSession.State.CONNECTED

	# Send AUTH_OK — session_id, char_id, char_name
	var w := NetProtocol.PacketWriter.new()
	w.write_str(session.session_id)
	w.write_i32(session.char_id)
	w.write_str(char_data.get("name", username))
	session.send_preauth(NetProtocol.MsgType.AUTH_OK, w.get_bytes())

	_log("Login OK: '%s' (char_id %d) → map %d @ %d,%d" % [
		username, session.char_id, session.map_id, session.tile_x, session.tile_y])

	# Announce this character to others on the same map
	_broadcast_to_map(session.map_id,
			NetProtocol.MsgType.S_SET_CHAR,
			_make_set_char_payload(session, char_data),
			session.session_id)


func _send_auth_fail(session: ClientSession, reason: String) -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_str(reason)
	session.send_preauth(NetProtocol.MsgType.AUTH_FAIL, w.get_bytes())
	session.state = ClientSession.State.PROTO_HANDSHAKE


# ---------------------------------------------------------------------------
# Broadcast helpers
# ---------------------------------------------------------------------------

func _broadcast_to_map(map_id: int, msg_type: int, payload: PackedByteArray,
		exclude_sid: String = "") -> void:
	for sid in _sessions:
		if sid == exclude_sid:
			continue
		var s : ClientSession = _sessions[sid]
		if s.state == ClientSession.State.CONNECTED and s.map_id == map_id:
			s.send(msg_type, payload)


func _make_set_char_payload(session: ClientSession,
		char_data: Dictionary) -> PackedByteArray:
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(session.char_id)
	w.write_i16(char_data.get("body",   1))
	w.write_i16(char_data.get("head",   1))
	w.write_i16(char_data.get("weapon_anim", 0))
	w.write_i16(char_data.get("shield_anim", 0))
	w.write_i16(session.tile_x)
	w.write_i16(session.tile_y)
	w.write_u8(session.heading)
	w.write_str(char_data.get("name", session.username))
	return w.get_bytes()


func _make_remove_char_payload(char_id: int) -> PackedByteArray:
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(char_id)
	return w.get_bytes()


# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

func _new_session_id() -> String:
	_session_counter += 1
	return "S%08X" % _session_counter


func _next_char_id() -> int:
	var id := _char_id_counter
	_char_id_counter += 1
	return id


func _log(msg: String) -> void:
	var t := Time.get_datetime_string_from_system()
	print("[SERVER %s] %s" % [t, msg])


func _log_security(msg: String) -> void:
	var t := Time.get_datetime_string_from_system()
	print("[SECURITY %s] %s" % [t, msg])
