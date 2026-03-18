class_name WorldMap
extends Node2D
## WorldMap - Core tile map renderer and character movement system.
## Mirrors VB6 Graphics.bas RenderScreen() and General.bas movement logic.
##
## Rendering passes (matches VB6 order):
##   Pass 1: Layer 1 - opaque ground tiles (no transparency, no centering)
##   Pass 2: Layer 2 (transparent, centered), Map Objects, Layer 3 (rain only),
##            Characters (head, body, shield, weapon in that order)
##
## Movement: Camera-lag style.
##   cam_tile  = current logical player tile (1..100)
##   cam_offset = pixel offset from cam_tile (starts at -dir*32, slides to 0)
##   Camera2D position = cam_tile*32 + cam_offset  (slides from old to new tile)

const TILE      := 32        # World-space pixels per tile
const VIEW_W    := 20        # Viewport width in tiles (original client)
const VIEW_H    := 11        # Viewport height in tiles (original client)
const MOVE_STEP := 8         # Pixels advanced per frame during smooth movement

@onready var _camera: Camera2D = $Camera2D

## Player's current logical tile position (center of view)
var cam_tile: Vector2i = Vector2i(10, 10)
## Sub-tile pixel offset for smooth camera scroll (goes from -dir*32 to zero)
var cam_offset: Vector2i = Vector2i.ZERO
## Direction currently being animated (zero when idle)
var pending_move: Vector2i = Vector2i.ZERO

var cur_map_id: int = 1
## Sparse tile dictionary: "y,x" -> {layers, blocked, obj, exit, npc_index, ...}
var _tiles: Dictionary = {}
## Characters: char_index -> CharData
var _chars: Dictionary = {}
## Local player's char index (0 = player)
var _player_idx: int = 0

var raining: bool = false
var tex_cache: TextureCache

var _anim_acc: float = 0.0


## Holds per-character animation state (mirrors VB6 Char type).
class CharData:
	var active: bool = true
	var heading: int = 3        # SOUTH (VB6: NORTH=1 EAST=2 SOUTH=3 WEST=4)
	var tile_pos: Vector2i
	var move_offset: Vector2i = Vector2i.ZERO
	var moving: bool = false
	var body_idx: int = 1
	var head_idx: int = 1
	var weapon_idx: int = 0
	var shield_idx: int = 0
	var body_anims: Array = []    # 4 x GrhAnimator  [N, E, S, W]
	var weapon_anims: Array = []  # 4 x GrhAnimator
	var shield_anims: Array = []  # 4 x GrhAnimator


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex_cache = TextureCache.new()
	_camera.zoom = Vector2(2.0, 2.0)
	if GameData.is_loaded:
		_load_map(cur_map_id)


func load_map(map_id: int) -> void:
	_load_map(map_id)


func _load_map(map_id: int) -> void:
	cur_map_id = map_id
	var map := GameData.get_map(map_id)
	if map.is_empty():
		push_error("[WorldMap] Map %d not found - run tools/run_pipeline.py first" % map_id)
		return

	_tiles = map.get("tiles", {})
	var sp: Dictionary = map.get("start_pos", {"x": 10, "y": 10})
	cam_tile   = Vector2i(sp.get("x", 10), sp.get("y", 10))
	cam_offset = Vector2i.ZERO
	pending_move = Vector2i.ZERO
	_chars.clear()

	# Spawn demo player (body=1, head=1, no weapon/shield, facing south)
	_chars[_player_idx] = _make_char(1, 1, 0, 0, cam_tile, 3)
	print("[WorldMap] Map %d loaded: %d tiles, start %s" % [map_id, _tiles.size(), cam_tile])


# ---------------------------------------------------------------------------
# Character factory
# ---------------------------------------------------------------------------

func _make_char(body: int, head: int, weapon: int, shield: int,
		tile: Vector2i, heading: int) -> CharData:
	var c := CharData.new()
	c.body_idx   = body
	c.head_idx   = head
	c.weapon_idx = weapon
	c.shield_idx = shield
	c.tile_pos   = tile
	c.heading    = heading
	_build_anims(c)
	return c


func _build_anims(c: CharData) -> void:
	c.body_anims.clear()
	c.weapon_anims.clear()
	c.shield_anims.clear()

	var bw: Array = GameData.get_body(c.body_idx).get("walk", [0, 0, 0, 0])
	var ww: Array = GameData.get_weapon_anim(c.weapon_idx).get("walk", [0, 0, 0, 0])
	var sw: Array = GameData.get_shield_anim(c.shield_idx).get("walk", [0, 0, 0, 0])

	for i in 4:
		var ba := GrhAnimator.new()
		ba.init(bw[i] if i < bw.size() else 0)
		var wa := GrhAnimator.new()
		wa.init(ww[i] if i < ww.size() else 0)
		var sa := GrhAnimator.new()
		sa.init(sw[i] if i < sw.size() else 0)
		c.body_anims.append(ba)
		c.weapon_anims.append(wa)
		c.shield_anims.append(sa)


# ---------------------------------------------------------------------------
# Public API (called by Network.gd in Phase 3+)
# ---------------------------------------------------------------------------

## Add or update a character received from the server (MAC/CHC message).
func set_char(c_idx: int, body: int, head: int, weapon: int, shield: int,
		tile: Vector2i, heading: int) -> void:
	_chars[c_idx] = _make_char(body, head, weapon, shield, tile, heading)


## Remove a character (ERC message).
func remove_char(c_idx: int) -> void:
	_chars.erase(c_idx)


## Smoothly move a character to a new tile (MOC message).
func move_char_to(c_idx: int, new_tile: Vector2i) -> void:
	if not _chars.has(c_idx):
		return
	var c: CharData = _chars[c_idx]
	var delta := new_tile - c.tile_pos
	if delta == Vector2i.ZERO:
		return
	c.move_offset = -delta * TILE
	c.moving      = true
	c.tile_pos    = new_tile
	# Set heading from movement direction
	if   delta.x > 0: c.heading = 2   # EAST
	elif delta.x < 0: c.heading = 4   # WEST
	elif delta.y < 0: c.heading = 1   # NORTH
	else:             c.heading = 3   # SOUTH
	# Start walk animation
	var di := _hidx(c.heading)
	for anims in [c.body_anims, c.weapon_anims, c.shield_anims]:
		if di < anims.size():
			(anims[di] as GrhAnimator).started = true


# ---------------------------------------------------------------------------
# Per-frame update
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not GameData.is_loaded:
		return

	_handle_input()
	_advance_cam()
	_advance_char_offsets()

	# Tick walk animations at ~30fps (original VB6 rate)
	_anim_acc += delta
	var ticks := int(_anim_acc * 30.0)
	if ticks > 0:
		_anim_acc -= float(ticks) / 30.0
		for _i in ticks:
			_tick_anims()

	_camera.position = Vector2(cam_tile * TILE) + Vector2(cam_offset)
	queue_redraw()


func _hidx(heading: int) -> int:
	## Convert VB6 heading (1-4) to array index (0-3).
	return clampi(heading - 1, 0, 3)


func _tick_anims() -> void:
	for c_idx in _chars:
		var c: CharData = _chars[c_idx]
		if not c.moving:
			continue
		var di := _hidx(c.heading)
		for anims in [c.body_anims, c.weapon_anims, c.shield_anims]:
			if di < anims.size():
				(anims[di] as GrhAnimator).tick()


## Advance camera offset 8px per frame toward zero (player movement).
func _advance_cam() -> void:
	if cam_offset == Vector2i.ZERO:
		return
	var sx := MOVE_STEP * signi(cam_offset.x) if cam_offset.x != 0 else 0
	var sy := MOVE_STEP * signi(cam_offset.y) if cam_offset.y != 0 else 0
	if absi(cam_offset.x) <= MOVE_STEP and absi(cam_offset.y) <= MOVE_STEP:
		cam_offset   = Vector2i.ZERO
		pending_move = Vector2i.ZERO
		_finish_player_move()
	else:
		cam_offset -= Vector2i(sx, sy)


func _finish_player_move() -> void:
	var p: CharData = _chars.get(_player_idx, null)
	if p == null:
		return
	p.moving = false
	var di := _hidx(p.heading)
	for anims in [p.body_anims, p.weapon_anims, p.shield_anims]:
		if di < anims.size():
			var a: GrhAnimator = anims[di]
			a.frame_counter = 1
			a.started = false


## Advance MoveOffset for non-player characters 8px per frame toward zero.
func _advance_char_offsets() -> void:
	for c_idx in _chars:
		if c_idx == _player_idx:
			continue
		var c: CharData = _chars[c_idx]
		if c.move_offset == Vector2i.ZERO:
			continue
		var sx := MOVE_STEP * signi(c.move_offset.x) if c.move_offset.x != 0 else 0
		var sy := MOVE_STEP * signi(c.move_offset.y) if c.move_offset.y != 0 else 0
		if absi(c.move_offset.x) <= MOVE_STEP and absi(c.move_offset.y) <= MOVE_STEP:
			c.move_offset = Vector2i.ZERO
			c.moving      = false
			var di := _hidx(c.heading)
			for anims in [c.body_anims, c.weapon_anims, c.shield_anims]:
				if di < anims.size():
					var a: GrhAnimator = anims[di]
					a.frame_counter = 1
					a.started = false
		else:
			c.move_offset -= Vector2i(sx, sy)


# ---------------------------------------------------------------------------
# Input (local player only - Phase 2 demo)
# ---------------------------------------------------------------------------

func _handle_input() -> void:
	if pending_move != Vector2i.ZERO:
		return  # Still animating previous step

	var dir := Vector2i.ZERO
	var heading := 0
	if   Input.is_action_pressed("move_north"): dir = Vector2i(0, -1); heading = 1
	elif Input.is_action_pressed("move_south"): dir = Vector2i(0,  1); heading = 3
	elif Input.is_action_pressed("move_east"):  dir = Vector2i(1,  0); heading = 2
	elif Input.is_action_pressed("move_west"):  dir = Vector2i(-1, 0); heading = 4

	if dir == Vector2i.ZERO:
		return

	var new_tile := cam_tile + dir
	if not _walkable(new_tile):
		return

	# Commit movement
	cam_tile     = new_tile
	pending_move = dir
	cam_offset   = -dir * TILE  # Camera starts one tile behind, slides forward

	var p: CharData = _chars.get(_player_idx, null)
	if p == null:
		return
	p.tile_pos = new_tile
	p.heading  = heading
	p.moving   = true
	var di := _hidx(heading)
	for anims in [p.body_anims, p.weapon_anims, p.shield_anims]:
		if di < anims.size():
			(anims[di] as GrhAnimator).started = true


func _walkable(tile: Vector2i) -> bool:
	if tile.x < 1 or tile.x > 100 or tile.y < 1 or tile.y > 100:
		return false
	return _tiles.get("%d,%d" % [tile.y, tile.x], {}).get("blocked", 0) == 0


# ---------------------------------------------------------------------------
# Rendering  (_draw is called by queue_redraw each frame)
# ---------------------------------------------------------------------------

func _draw() -> void:
	var cx := cam_tile.x
	var cy := cam_tile.y

	# +2 tile margin: covers cam_offset travel (up to 32px = 1 tile)
	var min_x := clampi(cx - 12, 1, 100)
	var max_x := clampi(cx + 12, 1, 100)
	var min_y := clampi(cy - 8,  1, 100)
	var max_y := clampi(cy + 8,  1, 100)

	# --- Pass 1: Layer 1 (opaque ground, no centering) ---
	for ty in range(min_y, max_y + 1):
		for tx in range(min_x, max_x + 1):
			var t: Dictionary = _tiles.get("%d,%d" % [ty, tx], {})
			var layers: Array = t.get("layers", [])
			if layers.size() > 0 and layers[0] > 0:
				_draw_grh(layers[0], tx * TILE, ty * TILE, false)

	# --- Pass 2: Transparent layers + objects + characters ---
	for ty in range(min_y, max_y + 1):
		for tx in range(min_x, max_x + 1):
			var t: Dictionary = _tiles.get("%d,%d" % [ty, tx], {})
			var layers: Array = t.get("layers", [])
			var wx := tx * TILE
			var wy := ty * TILE

			# Layer 2 (walls/objects above floor, transparent, centered)
			if layers.size() > 1 and layers[1] > 0:
				_draw_grh(layers[1], wx, wy, true)

			# Object on this tile (dropped items, furniture)
			var obj: Dictionary = t.get("obj", {})
			if not obj.is_empty():
				var obj_grh: int = GameData.get_object(obj.get("index", 0)).get("grh_index", 0)
				if obj_grh > 0:
					_draw_grh(obj_grh, wx, wy, true)

			# Layer 3: only rendered during rain (weather/atmosphere overlay)
			if raining and layers.size() > 2 and layers[2] > 0:
				_draw_grh(layers[2], wx, wy, true)

			# Characters at this tile (head, body, shield, weapon)
			_draw_chars_at(Vector2i(tx, ty), wx, wy)


func _draw_chars_at(map_tile: Vector2i, wx: int, wy: int) -> void:
	for c_idx in _chars:
		var c: CharData = _chars[c_idx]
		if not c.active or c.tile_pos != map_tile:
			continue

		# Player has no MoveOffset (camera moves instead); others do.
		var dx := wx + (0 if c_idx == _player_idx else c.move_offset.x)
		var dy := wy + (0 if c_idx == _player_idx else c.move_offset.y)
		var di := _hidx(c.heading)

		# Head position includes body's head offset (in pixels)
		var body_d := GameData.get_body(c.body_idx)
		var hox: int = body_d.get("head_offset_x", 0)
		var hoy: int = body_d.get("head_offset_y", 0)

		# VB6 draw order: Head (Animate=0), Body, Shield, Weapon
		var hgrh := GameData.get_head_grh(c.head_idx, di)
		if hgrh > 0:
			_draw_grh(hgrh, dx + hox, dy + hoy, true)

		if di < c.body_anims.size():
			_draw_animator(c.body_anims[di] as GrhAnimator, dx, dy)
		if di < c.shield_anims.size():
			_draw_animator(c.shield_anims[di] as GrhAnimator, dx, dy)
		if di < c.weapon_anims.size():
			_draw_animator(c.weapon_anims[di] as GrhAnimator, dx, dy)


# ---------------------------------------------------------------------------
# Low-level draw helpers
# ---------------------------------------------------------------------------

## Draw a static GRH at world position (wx, wy).
## centered=true offsets the sprite so it is centered on the tile (VB6 style).
func _draw_grh(grh_index: int, wx: int, wy: int, centered: bool) -> void:
	if grh_index <= 0:
		return
	var fd := GameData.get_grh_frame(grh_index, 0)
	if fd.is_empty():
		return
	_blit(fd, wx, wy, centered)


## Draw the current frame of a GrhAnimator.
func _draw_animator(anim: GrhAnimator, wx: int, wy: int) -> void:
	if anim == null or anim.grh_index <= 0:
		return
	var fd := anim.get_frame_data()
	if fd.is_empty():
		return
	_blit(fd, wx, wy, true)


## Core blit: draw a GRH frame dict at (wx, wy) in world space.
## VB6 centering formula:
##   x_offset = -pixel_width/2  + 16   (centers multi-tile-wide sprites on tile)
##   y_offset = -pixel_height   + 32   (aligns bottom of sprite to tile bottom)
func _blit(fd: Dictionary, wx: int, wy: int, centered: bool) -> void:
	var file_num: int = fd.get("file_num", 0)
	if file_num <= 0:
		return
	var tex := tex_cache.get_texture(file_num)
	if tex == null:
		return

	var sx: int = fd.get("sx", 0)
	var sy: int = fd.get("sy", 0)
	var pw: int = fd.get("pixel_width",  TILE)
	var ph: int = fd.get("pixel_height", TILE)

	var dx := wx
	var dy := wy
	if centered:
		# VB6: x = x - Int(tileWidth*16) + 16  where tileWidth = pw/32
		#       → x - pw/2 + 16
		#      y = y - Int(tileHeight*32) + 32 where tileHeight = ph/32
		#       → y - ph + 32
		dx = wx - pw / 2 + 16
		dy = wy - ph + TILE

	draw_texture_rect_region(tex,
		Rect2(float(dx), float(dy), float(pw), float(ph)),
		Rect2(float(sx), float(sy), float(pw), float(ph)))
