class_name ClientSession
## Era Online - Per-Client Session
## Wraps a single client's TLS connection. Handles:
##   - TLS stream polling and byte buffering
##   - Pre-auth and post-auth packet framing/parsing
##   - HMAC verification and sequence number enforcement
##   - Rate limiting via RateLimiter
##   - Auth attempt throttling and lockout
##
## ServerMain owns all ClientSession instances and calls poll() each frame.


enum State {
	HANDSHAKING,    # TLS not yet complete
	PROTO_HANDSHAKE,# TLS done, waiting for CLIENT_HELLO / AUTH
	AUTHENTICATING, # AUTH_LOGIN/REGISTER received, waiting for DB result
	CONNECTED,      # Fully authenticated game session
	DISCONNECTED,
}


# ---------------------------------------------------------------------------
# Identity & position
# ---------------------------------------------------------------------------

var session_id    : String  = ""
var account_id    : int     = 0
var char_id       : int     = 0   ## Unique per-map char identifier
var username      : String  = ""
var map_id        : int     = 3
var tile_x        : int     = 10
var tile_y        : int     = 10
var heading       : int     = 3


# ---------------------------------------------------------------------------
# Connection state
# ---------------------------------------------------------------------------

var state         : State   = State.HANDSHAKING
var last_activity : float   = 0.0   ## Unix time of last received data

## Callback set by ServerMain: (session, msg_type, reader) → void
var on_message    : Callable


# ---------------------------------------------------------------------------
# Security
# ---------------------------------------------------------------------------

var session_key   : PackedByteArray = PackedByteArray()
var server_nonce  : PackedByteArray = PackedByteArray()
var client_nonce  : PackedByteArray = PackedByteArray()

var _send_seq     : int = 0
var _recv_seq     : int = 0

var auth_attempts      : int   = 0
var auth_lockout_until : float = 0.0
var _last_auth_time    : float = 0.0


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

var _tcp          : StreamPeerTCP
var _tls          : StreamPeerTLS
var _tls_opts     : TLSOptions

var _recv_buf     : PackedByteArray = PackedByteArray()
var _send_queue   : Array           = []   # Array[PackedByteArray]
var _rate_limiter : RateLimiter
var _tls_ready    : bool = false


# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

func _init(sid: String, tcp: StreamPeerTCP, tls_opts: TLSOptions) -> void:
	session_id    = sid
	_tcp          = tcp
	_tls_opts     = tls_opts
	_rate_limiter = RateLimiter.new()
	last_activity = Time.get_ticks_msec() / 1000.0

	# Generate server nonce for this session
	server_nonce = Crypto.new().generate_random_bytes(NetProtocol.NONCE_SIZE)

	# Wrap TCP in TLS (server side)
	_tls = StreamPeerTLS.new()
	var err := _tls.accept_stream(_tcp, tls_opts)
	if err != OK:
		push_error("[Session %s] TLS accept failed: %s" % [sid, error_string(err)])
		state = State.DISCONNECTED


# ---------------------------------------------------------------------------
# Poll — called every frame by ServerMain
# ---------------------------------------------------------------------------

func poll() -> void:
	if state == State.DISCONNECTED or _tls == null:
		return

	_tls.poll()
	var tls_status := _tls.get_status()

	match tls_status:
		StreamPeerTLS.STATUS_HANDSHAKING:
			return  # Not ready yet

		StreamPeerTLS.STATUS_ERROR, StreamPeerTLS.STATUS_DISCONNECTED:
			_log("TLS error/disconnect")
			state = State.DISCONNECTED
			return

		StreamPeerTLS.STATUS_CONNECTED:
			if not _tls_ready:
				_tls_ready = true
				state      = State.PROTO_HANDSHAKE
				_send_server_hello()

	# Drain incoming bytes into buffer
	var available := _tls.get_available_bytes()
	if available > 0:
		var res := _tls.get_data(available)
		if res[0] == OK:
			_recv_buf.append_array(res[1] as PackedByteArray)
			last_activity = Time.get_ticks_msec() / 1000.0

	# Parse packets
	match state:
		State.PROTO_HANDSHAKE, State.AUTHENTICATING:
			_parse_preauth()
		State.CONNECTED:
			_parse_auth()

	# Flush outgoing queue
	_flush()


# ---------------------------------------------------------------------------
# Packet parsing — pre-auth
# ---------------------------------------------------------------------------

func _parse_preauth() -> void:
	while _recv_buf.size() >= NetProtocol.PREAUTH_HDR_SIZE:
		var r           := NetProtocol.PacketReader.new(_recv_buf)
		var msg_type    := r.read_u16()
		var payload_len := r.read_u16()
		var total       := NetProtocol.PREAUTH_HDR_SIZE + payload_len
		if _recv_buf.size() < total:
			break
		var payload  := r.read_bytes(payload_len)
		_recv_buf     = _recv_buf.slice(total)

		if r.error:
			_log_security("Pre-auth parse error on type 0x%04X" % msg_type)
			continue

		_handle_preauth_msg(msg_type, payload)


func _handle_preauth_msg(msg_type: int, payload: PackedByteArray) -> void:
	var r := NetProtocol.PacketReader.new(payload)

	match msg_type:
		NetProtocol.MsgType.CLIENT_HELLO:
			client_nonce = r.read_bytes(NetProtocol.NONCE_SIZE)
			if r.error or client_nonce.size() != NetProtocol.NONCE_SIZE:
				_log_security("Bad CLIENT_HELLO nonce")
				disconnect("Protocol error")
				return

		NetProtocol.MsgType.AUTH_LOGIN, NetProtocol.MsgType.AUTH_REGISTER:
			_handle_auth_msg(msg_type, r)

		_:
			_log_security("Unexpected pre-auth msg 0x%04X" % msg_type)


func _handle_auth_msg(msg_type: int, r: NetProtocol.PacketReader) -> void:
	var now := Time.get_ticks_msec() / 1000.0

	# Lockout check
	if now < auth_lockout_until:
		var w := NetProtocol.PacketWriter.new()
		w.write_str("Too many attempts. Try again later.")
		send_preauth(NetProtocol.MsgType.AUTH_FAIL, w.get_bytes())
		_log_security("Auth attempt while locked out")
		return

	# Rate limit between attempts
	if now - _last_auth_time < NetProtocol.AUTH_ATTEMPT_WINDOW:
		var w := NetProtocol.PacketWriter.new()
		w.write_str("Please wait before trying again.")
		send_preauth(NetProtocol.MsgType.AUTH_FAIL, w.get_bytes())
		return

	_last_auth_time = now
	auth_attempts += 1

	if auth_attempts > NetProtocol.AUTH_MAX_ATTEMPTS:
		auth_lockout_until = now + NetProtocol.AUTH_LOCKOUT_SECS
		_log_security("Auth locked out after %d attempts" % auth_attempts)
		var w := NetProtocol.PacketWriter.new()
		w.write_str("Too many failed attempts. Locked out for 60 seconds.")
		send_preauth(NetProtocol.MsgType.AUTH_FAIL, w.get_bytes())
		return

	state = State.AUTHENTICATING
	if on_message.is_valid():
		# Forward to ServerMain with a fresh reader for the original payload
		on_message.call(self, msg_type, r)


# ---------------------------------------------------------------------------
# Packet parsing — post-auth (with HMAC + sequence)
# ---------------------------------------------------------------------------

func _parse_auth() -> void:
	while _recv_buf.size() >= NetProtocol.FULL_PKT_OVERHEAD:
		var r           := NetProtocol.PacketReader.new(_recv_buf)
		var seq         := r.read_u32()
		var msg_type    := r.read_u16()
		var payload_len := r.read_u16()
		var total       := NetProtocol.AUTH_HDR_SIZE + payload_len + NetProtocol.HMAC_SIZE
		if _recv_buf.size() < total:
			break

		var header_and_payload := _recv_buf.slice(0, NetProtocol.AUTH_HDR_SIZE + payload_len)
		var tag                := _recv_buf.slice(
				NetProtocol.AUTH_HDR_SIZE + payload_len, total)
		_recv_buf = _recv_buf.slice(total)

		# Verify HMAC
		if not NetProtocol.verify_packet(session_key, header_and_payload, tag):
			_log_security("HMAC failure — possible packet injection")
			disconnect("Security violation")
			return

		# Verify sequence
		if seq != _recv_seq:
			_log_security("Seq mismatch: expected %d got %d" % [_recv_seq, seq])
			disconnect("Security violation")
			return
		_recv_seq += 1

		# Rate limit
		if not _rate_limiter.consume(msg_type):
			_log_security("Rate limit exceeded for msg 0x%04X" % msg_type)
			continue  # Drop — don't disconnect on first violation

		var payload  := header_and_payload.slice(NetProtocol.AUTH_HDR_SIZE)
		var pr       := NetProtocol.PacketReader.new(payload)
		if on_message.is_valid():
			on_message.call(self, msg_type, pr)


# ---------------------------------------------------------------------------
# Sending
# ---------------------------------------------------------------------------

func send_preauth(msg_type: int, payload: PackedByteArray) -> void:
	_queue(NetProtocol.frame_preauth(msg_type, payload))


func send(msg_type: int, payload: PackedByteArray) -> void:
	if state != State.CONNECTED:
		push_warning("[Session %s] send() in wrong state" % session_id)
		return
	_queue(NetProtocol.frame_auth(msg_type, payload, _send_seq, session_key))
	_send_seq += 1


func _queue(packet: PackedByteArray) -> void:
	_send_queue.append(packet)


func _flush() -> void:
	while not _send_queue.is_empty():
		if _tls == null or _tls.get_status() != StreamPeerTLS.STATUS_CONNECTED:
			break
		var err := _tls.put_data(_send_queue[0])
		if err != OK:
			push_warning("[Session %s] Flush error: %s" % [session_id, error_string(err)])
			break
		_send_queue.remove_at(0)


# ---------------------------------------------------------------------------
# Disconnect
# ---------------------------------------------------------------------------

func disconnect(reason: String = "Disconnected") -> void:
	if state == State.CONNECTED:
		var w := NetProtocol.PacketWriter.new()
		w.write_str(reason)
		# Best-effort kick packet before closing
		_queue(NetProtocol.frame_auth(NetProtocol.MsgType.S_KICK,
				w.get_bytes(), _send_seq, session_key))
		_flush()
	if _tls != null:
		_tls.disconnect_from_stream()
		_tls = null
	state = State.DISCONNECTED
	_log("Disconnected: " + reason)


func is_timed_out() -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	return (now - last_activity) > 30.0


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _send_server_hello() -> void:
	var w := NetProtocol.PacketWriter.new()
	w.write_u16(NetProtocol.PROTOCOL_VERSION)
	w.write_bytes(server_nonce)
	send_preauth(NetProtocol.MsgType.SERVER_HELLO, w.get_bytes())


func _log(msg: String) -> void:
	print("[Session %s] %s" % [session_id, msg])


func _log_security(msg: String) -> void:
	print("[SECURITY][Session %s] %s" % [session_id, msg])
