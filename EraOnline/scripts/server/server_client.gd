## Era Online - Per-connection state on the game server.
## Wraps one TCP→TLS connection, handles framing, rate limiting, and auth state.

enum State {
	HANDSHAKE,      # TCP/TLS connecting, waiting to send SERVER_HELLO
	PROTO_WAIT,     # Sent SERVER_HELLO, waiting for CLIENT_HELLO
	AUTHENTICATING, # Received CLIENT_HELLO, waiting for AUTH_LOGIN/REGISTER
	CHAR_SELECT,    # Auth OK, waiting for C_SELECT_CHAR / C_CREATE_CHAR
	CONNECTED,      # In-world
	CLOSING,        # Queued for removal
}

var peer_id:    int            = 0
var tcp:        StreamPeerTCP  = null
var tls:        StreamPeerTLS  = null
var state:      State          = State.HANDSHAKE

var username:   String         = ""
## Live character dict — mutable reference into the DB-loaded account data.
var char:       Dictionary     = {}

# Framing buffers
var recv_buf:   PackedByteArray = PackedByteArray()
var send_queue: Array           = []   # Array[PackedByteArray]

# Sequence counters (post-auth)
var send_seq:   int             = 0
var recv_seq:   int             = 0
var session_key: PackedByteArray = PackedByteArray()

# Nonces for session key derivation
var server_nonce: PackedByteArray = PackedByteArray()
var client_nonce: PackedByteArray = PackedByteArray()

# Auth rate limiting
var auth_attempts:  int   = 0
var last_auth_time: float = 0.0
var locked_until:   float = 0.0

# Per-message token bucket rate limiters: msg_type → [tokens:float, last_tick:float]
var _rate_buckets: Dictionary = {}

# Time since last position update (server-side movement throttle)
var last_move_time: float = 0.0


func _init(id: int, tcp_peer: StreamPeerTCP,
		tls_options: TLSOptions, time_now: float) -> void:
	peer_id = id
	tcp     = tcp_peer
	tls     = StreamPeerTLS.new()
	var err := tls.accept_stream(tcp, tls_options)
	if err != OK:
		push_error("[ServerClient %d] TLS accept failed: %s" % [id, error_string(err)])
		state = State.CLOSING
		return
	last_auth_time = time_now
	# Initialise rate buckets from protocol constants
	for msg_type in NetProtocol.RATE_LIMITS:
		var limits: Array = NetProtocol.RATE_LIMITS[msg_type]
		_rate_buckets[msg_type] = [float(limits[1]), time_now]  # start full


# ---------------------------------------------------------------------------
# Per-frame tick — returns array of {type:int, payload:PackedByteArray}
# ---------------------------------------------------------------------------

func tick(delta: float) -> Array:
	if state == State.CLOSING:
		return []

	tls.poll()
	var tls_status := tls.get_status()
	if tls_status == StreamPeerTLS.STATUS_ERROR or \
			tls_status == StreamPeerTLS.STATUS_DISCONNECTED:
		state = State.CLOSING
		return []

	# Drain incoming bytes
	var avail := tls.get_available_bytes()
	if avail > 0:
		var res := tls.get_data(avail)
		if res[0] == OK:
			recv_buf.append_array(res[1] as PackedByteArray)

	# Parse packets
	var messages: Array = []
	if state == State.PROTO_WAIT or state == State.AUTHENTICATING:
		messages = _parse_preauth()
	elif state == State.CHAR_SELECT or state == State.CONNECTED:
		messages = _parse_auth()

	flush()
	return messages


# ---------------------------------------------------------------------------
# Sending
# ---------------------------------------------------------------------------

func send_preauth(msg_type: int, payload: PackedByteArray) -> void:
	send_queue.append(NetProtocol.frame_preauth(msg_type, payload))


func send_auth(msg_type: int, payload: PackedByteArray) -> void:
	var pkt := NetProtocol.frame_auth(msg_type, payload, send_seq, session_key)
	send_seq += 1
	send_queue.append(pkt)


func flush() -> void:
	while not send_queue.is_empty():
		if tls == null or tls.get_status() != StreamPeerTLS.STATUS_CONNECTED:
			break
		var pkt: PackedByteArray = send_queue[0]
		if tls.put_data(pkt) != OK:
			break
		send_queue.remove_at(0)


func close(reason: String = "") -> void:
	if reason.length() > 0 and \
			(state == State.CHAR_SELECT or state == State.CONNECTED):
		var w := NetProtocol.PacketWriter.new()
		w.write_str(reason)
		send_auth(NetProtocol.MsgType.S_KICK, w.get_bytes())
		flush()
	state = State.CLOSING
	if tls != null:
		tls.disconnect_from_stream()
		tls = null
	if tcp != null:
		tcp.disconnect_from_host()
		tcp = null


# ---------------------------------------------------------------------------
# Rate limiting (token bucket)
# ---------------------------------------------------------------------------

## Returns true if the message is allowed; deducts a token.
func check_rate(msg_type: int, time_now: float) -> bool:
	if not _rate_buckets.has(msg_type):
		return true  # Not rate-limited
	var limits: Array = NetProtocol.RATE_LIMITS[msg_type]
	var rate: float   = float(limits[0])
	var cap: float    = float(limits[1])
	var bucket: Array = _rate_buckets[msg_type]
	var tokens: float = bucket[0]
	var last:   float = bucket[1]
	# Refill
	tokens = minf(cap, tokens + rate * (time_now - last))
	bucket[1] = time_now
	if tokens < 1.0:
		bucket[0] = tokens
		return false
	bucket[0] = tokens - 1.0
	return true


# ---------------------------------------------------------------------------
# Packet parsing
# ---------------------------------------------------------------------------

func _parse_preauth() -> Array:
	var out: Array = []
	while recv_buf.size() >= NetProtocol.PREAUTH_HDR_SIZE:
		var r := NetProtocol.PacketReader.new(recv_buf)
		var msg_type    := r.read_u16()
		var payload_len := r.read_u16()
		var total := NetProtocol.PREAUTH_HDR_SIZE + payload_len
		if recv_buf.size() < total:
			break
		var payload := r.read_bytes(payload_len)
		recv_buf = recv_buf.slice(total)
		if not r.error:
			out.append({"type": msg_type, "payload": payload})
	return out


func _parse_auth() -> Array:
	var out: Array = []
	while recv_buf.size() >= NetProtocol.AUTH_HDR_SIZE:
		var r := NetProtocol.PacketReader.new(recv_buf)
		var seq         := r.read_u32()
		var msg_type    := r.read_u16()
		var payload_len := r.read_u16()
		var total := NetProtocol.AUTH_HDR_SIZE + payload_len + NetProtocol.HMAC_SIZE
		if recv_buf.size() < total:
			break
		var header_payload := recv_buf.slice(0, NetProtocol.AUTH_HDR_SIZE + payload_len)
		var tag            := recv_buf.slice(
				NetProtocol.AUTH_HDR_SIZE + payload_len, total)
		recv_buf = recv_buf.slice(total)

		if not NetProtocol.verify_packet(session_key, header_payload, tag):
			push_warning("[ServerClient %d] HMAC mismatch — closing" % peer_id)
			state = State.CLOSING
			return out
		if seq != recv_seq:
			push_warning("[ServerClient %d] Sequence mismatch" % peer_id)
			state = State.CLOSING
			return out
		recv_seq += 1

		var payload := header_payload.slice(NetProtocol.AUTH_HDR_SIZE)
		out.append({"type": msg_type, "payload": payload})
	return out
