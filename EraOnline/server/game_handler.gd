class_name GameHandler
extends RefCounted
## Era Online - Game Message Handler
## Processes validated, authenticated C_* messages from ClientSession.
## All game logic is server-authoritative: validate before mutating state.
##
## Called by ServerMain.on_message() for every post-auth packet.

const MOVE_MIN_INTERVAL_MS : int = 250  # Min ms between moves (anti-speed-hack)

var _sessions: Dictionary  # session_id (String) → ClientSession
var _db: ServerDB


func _init(sessions: Dictionary, db: ServerDB) -> void:
	_sessions = sessions
	_db       = db


# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

func handle(session: ClientSession, msg_type: int,
		reader: NetProtocol.PacketReader) -> void:
	match msg_type:
		NetProtocol.MsgType.C_MOVE:
			_handle_move(session, reader)
		NetProtocol.MsgType.C_ATTACK:
			_handle_attack(session, reader)
		NetProtocol.MsgType.C_CHAT:
			_handle_chat(session, reader)
		NetProtocol.MsgType.C_PICKUP:
			_handle_pickup(session, reader)
		NetProtocol.MsgType.C_DROP:
			_handle_drop(session, reader)
		NetProtocol.MsgType.C_EQUIP:
			_handle_equip(session, reader)
		NetProtocol.MsgType.C_UNEQUIP:
			_handle_unequip(session, reader)
		NetProtocol.MsgType.C_USE_ITEM:
			_handle_use_item(session, reader)
		NetProtocol.MsgType.C_CAST_SPELL:
			_handle_cast_spell(session, reader)
		NetProtocol.MsgType.C_PING:
			_handle_ping(session, reader)
		_:
			push_warning("[GameHandler] Unknown msg 0x%04X from %s" % [
				msg_type, session.session_id])


# ---------------------------------------------------------------------------
# Handlers
# ---------------------------------------------------------------------------

func _handle_move(session: ClientSession, reader: NetProtocol.PacketReader) -> void:
	var direction := reader.read_u8()
	if reader.error or direction < 1 or direction > 4:
		push_warning("[GameHandler] Bad C_MOVE direction from %s" % session.session_id)
		return

	# Rate-limit: prevent speed hacks
	var now_ms  := Time.get_ticks_msec()
	var last_ms := session.get_meta("last_move_ms", 0) as int
	if now_ms - last_ms < MOVE_MIN_INTERVAL_MS:
		return  # Silently drop — could be lag burst, not necessarily cheating
	session.set_meta("last_move_ms", now_ms)

	# Compute destination
	var dx := 0; var dy := 0
	match direction:
		1: dy = -1  # North
		2: dx =  1  # East
		3: dy =  1  # South
		4: dx = -1  # West

	var new_x := session.tile_x + dx
	var new_y := session.tile_y + dy

	# Bounds check
	if new_x < 1 or new_x > 100 or new_y < 1 or new_y > 100:
		# TODO Phase 5: check cardinal exits
		return

	# Walkable check (Phase 5: load map tile data)
	if not _is_tile_walkable(session.map_id, new_x, new_y):
		return

	# Commit move
	session.tile_x  = new_x
	session.tile_y  = new_y
	session.heading = direction

	# Broadcast S_MOVE_CHAR to everyone on the map (including the mover — confirms the move)
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(session.char_id)
	w.write_i16(new_x)
	w.write_i16(new_y)
	w.write_u8(direction)
	_broadcast_to_map(session.map_id, NetProtocol.MsgType.S_MOVE_CHAR, w.get_bytes())


func _handle_attack(session: ClientSession, reader: NetProtocol.PacketReader) -> void:
	var target_id := reader.read_i32()
	if reader.error:
		return
	# Phase 4 stub: log and send 0-damage response
	_log("[%s] attacks char_id %d (stub)" % [session.username, target_id])
	var w := NetProtocol.PacketWriter.new()
	w.write_i32(target_id)
	w.write_i16(0)   # damage
	w.write_u8(1)    # evaded = true (stub)
	session.send(NetProtocol.MsgType.S_DAMAGE, w.get_bytes())


func _handle_chat(session: ClientSession, reader: NetProtocol.PacketReader) -> void:
	var message := reader.read_str()
	if reader.error:
		return

	# Validate length
	message = message.strip_edges()
	if message.is_empty() or message.length() > 128:
		return

	# Strip control characters
	var clean := ""
	for ch in message:
		var code := ch.unicode_at(0)
		if code >= 32:  # Keep printable chars only
			clean += ch
	if clean.is_empty():
		return

	var w := NetProtocol.PacketWriter.new()
	w.write_i32(session.char_id)
	w.write_u8(0)          # chat_type 0 = normal
	w.write_str(clean)
	_broadcast_to_map(session.map_id, NetProtocol.MsgType.S_CHAT, w.get_bytes())


func _handle_pickup(session: ClientSession, _reader: NetProtocol.PacketReader) -> void:
	_log("[%s] pickup (Phase 4 stub)" % session.username)


func _handle_drop(session: ClientSession, reader: NetProtocol.PacketReader) -> void:
	var slot   := reader.read_u8()
	var amount := reader.read_u16()
	if reader.error:
		return
	_log("[%s] drop slot=%d amount=%d (Phase 4 stub)" % [session.username, slot, amount])


func _handle_equip(session: ClientSession, reader: NetProtocol.PacketReader) -> void:
	var slot := reader.read_u8()
	if reader.error:
		return
	_log("[%s] equip slot=%d (Phase 4 stub)" % [session.username, slot])


func _handle_unequip(session: ClientSession, reader: NetProtocol.PacketReader) -> void:
	var slot := reader.read_u8()
	if reader.error:
		return
	_log("[%s] unequip slot=%d (Phase 4 stub)" % [session.username, slot])


func _handle_use_item(session: ClientSession, reader: NetProtocol.PacketReader) -> void:
	var slot := reader.read_u8()
	if reader.error:
		return
	_log("[%s] use_item slot=%d (Phase 4 stub)" % [session.username, slot])


func _handle_cast_spell(session: ClientSession, reader: NetProtocol.PacketReader) -> void:
	var spell_slot := reader.read_u8()
	var target_id  := reader.read_i32()
	if reader.error:
		return
	_log("[%s] cast spell=%d target=%d (Phase 4 stub)" % [
		session.username, spell_slot, target_id])


func _handle_ping(session: ClientSession, reader: NetProtocol.PacketReader) -> void:
	var timestamp := reader.read_i64()
	if reader.error:
		return
	var w := NetProtocol.PacketWriter.new()
	w.write_i64(timestamp)
	session.send(NetProtocol.MsgType.S_PONG, w.get_bytes())


# ---------------------------------------------------------------------------
# Map / tile helpers
# ---------------------------------------------------------------------------

## Phase 5: load real tile data. For now, all tiles are walkable.
func _is_tile_walkable(_map_id: int, _x: int, _y: int) -> bool:
	return true


# ---------------------------------------------------------------------------
# Broadcast helpers
# ---------------------------------------------------------------------------

func _broadcast_to_map(map_id: int, msg_type: int, payload: PackedByteArray,
		exclude_session_id: String = "") -> void:
	for sid in _sessions:
		var s: ClientSession = _sessions[sid]
		if s.state != ClientSession.State.CONNECTED:
			continue
		if s.map_id != map_id:
			continue
		if sid == exclude_session_id:
			continue
		s.send(msg_type, payload)


func _send_to(session: ClientSession, msg_type: int, payload: PackedByteArray) -> void:
	session.send(msg_type, payload)


# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

func _log(msg: String) -> void:
	var t := Time.get_datetime_string_from_system()
	print("[GameHandler %s] %s" % [t, msg])
