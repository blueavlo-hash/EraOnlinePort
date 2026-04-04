extends Node
## Era Online - Network Autoload
## Client TCP networking. Replaces the VB6 SocketWrench (CSWSK32.OCX) control.
##
## Protocol: text messages with 3-char prefix + comma-separated fields + newline
## Examples: "SUP12,34\n", "MAC1,10,10,3,1,1,2,2\n", "@Hello world\n"

signal connected_to_server()
signal disconnected_from_server()
signal connection_failed(reason: String)
signal message_received(prefix: String, data: String)

const DEFAULT_PORT    := 7777
const MSG_PREFIX_LEN  := 3

var server_address: String = "127.0.0.1"
var server_port: int       = DEFAULT_PORT
var is_connected: bool     = false

var _peer: StreamPeerTCP = null
var _buffer: String = ""

func _ready() -> void:
	set_process(false)

# --- Public API ---

func connect_to_server(address: String, port: int = DEFAULT_PORT) -> void:
	disconnect_from_server()
	server_address = address
	server_port    = port
	_peer = StreamPeerTCP.new()
	var err := _peer.connect_to_host(address, port)
	if err != OK:
		connection_failed.emit("connect_to_host failed: %s" % error_string(err))
		return
	set_process(true)
	print("[Network] Connecting to %s:%d..." % [address, port])

func disconnect_from_server() -> void:
	if _peer:
		_peer.disconnect_from_host()
		_peer = null
	is_connected = false
	_buffer = ""
	set_process(false)

## Send a raw string to the server (appends newline automatically).
func send(message: String) -> void:
	if not is_connected or _peer == null:
		push_warning("[Network] send() called while not connected")
		return
	_peer.put_data((message + "\n").to_utf8_buffer())

## Send a structured message: 3-char prefix + optional comma-separated fields.
func send_msg(prefix: String, fields: Array = []) -> void:
	var msg := prefix
	if not fields.is_empty():
		var parts: PackedStringArray = []
		for f in fields:
			parts.append(str(f))
		msg += ",".join(parts)
	send(msg)

## Parse comma-separated field string into array.
static func split_fields(data: String) -> PackedStringArray:
	return data.split(",")

# --- Internal ---

func _process(_delta: float) -> void:
	if _peer == null:
		return

	match _peer.get_status():
		StreamPeerTCP.STATUS_CONNECTING:
			pass

		StreamPeerTCP.STATUS_CONNECTED:
			if not is_connected:
				is_connected = true
				print("[Network] Connected.")
				connected_to_server.emit()
			_receive()

		StreamPeerTCP.STATUS_NONE, StreamPeerTCP.STATUS_ERROR:
			if is_connected:
				is_connected = false
				print("[Network] Disconnected.")
				disconnected_from_server.emit()
			else:
				connection_failed.emit("Could not connect to %s:%d" % [server_address, server_port])
			set_process(false)
			_peer = null

func _receive() -> void:
	var available := _peer.get_available_bytes()
	if available <= 0:
		return
	var res := _peer.get_data(available)
	if res[0] != OK:
		return
	_buffer += (res[1] as PackedByteArray).get_string_from_utf8()
	_process_buffer()

func _process_buffer() -> void:
	# Messages are newline-delimited
	while true:
		var nl := _buffer.find("\n")
		if nl < 0:
			break
		var line := _buffer.left(nl).strip_edges()
		_buffer = _buffer.substr(nl + 1)
		if line.length() < MSG_PREFIX_LEN:
			continue
		var prefix := line.left(MSG_PREFIX_LEN)
		var data   := line.substr(MSG_PREFIX_LEN)
		message_received.emit(prefix, data)
