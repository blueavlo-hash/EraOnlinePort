class_name MinimapUI
extends CanvasLayer
## Era Online — Minimap (top-right, collapsible).
##
## Layout (1280×720 viewport):
##   Collapsed : 210 × 22 px  — header bar only, "Map" label + expand button
##   Expanded  : 210 × 228 px — header + 200×200 map image + entity dots
##
## World-map wires this up:
##   _minimap = MinimapUI.new()
##   add_child(_minimap)
##   _minimap.set_world(self)        ← gives us a reference for per-frame reads
##   _minimap.update_map(_tiles)     ← called after every _load_map()

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const VIEWPORT_W   := 1280
const MAP_PX       := 200       # display size of the map image in pixels
const MAP_IMG      := 200       # baked image size (2 px per tile → sharper paths)
const HEADER_H     := 22
const PANEL_W      := MAP_PX + 10
const PANEL_H_FULL := HEADER_H + MAP_PX + 4
const MARGIN       := 8

const C_PANEL  := Color(0.06, 0.05, 0.03, 0.88)
const C_BORDER := Color(0.40, 0.30, 0.12, 1.0)
const C_HEADER := Color(0.10, 0.08, 0.04, 1.0)
const C_OPEN   := Color(0.18, 0.26, 0.14, 1.0)
const C_BLOCK  := Color(0.10, 0.09, 0.08, 1.0)
const C_WATER  := Color(0.12, 0.18, 0.28, 1.0)
const C_PLAYER := Color(1.00, 0.95, 0.25, 1.0)
const C_ALLY   := Color(0.35, 0.65, 1.00, 1.0)
const C_ENEMY  := Color(1.00, 0.25, 0.25, 1.0)
const C_NPC    := Color(0.40, 0.90, 0.40, 1.0)

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _world:    WorldMap        = null
var _expanded: bool            = true
var _map_tex:  ImageTexture    = null

var _panel:         Panel        = null
var _dots_layer:    Control      = null   # redraws entity dots every frame
var _map_rect:      TextureRect  = null
var _toggle_btn:    Button       = null
var _name_label:    Label        = null
var _night_overlay: ColorRect    = null   # tints minimap at night

## GRH index → averaged Color. Persists across map loads since GRH data is global.
var _grh_color_cache: Dictionary = {}

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 9
	_build_ui()


func set_world(world: WorldMap) -> void:
	_world = world


func set_darkness(darkness: float) -> void:
	## Called by world_map each time lighting updates. Tints the minimap navy at night.
	if _night_overlay == null:
		return
	_night_overlay.color = Color(0.0, 0.0, 0.05, darkness * 0.72)


func update_map(tiles: Dictionary, map_name: String = "") -> void:
	## Called by world_map after loading tile data. Bakes the static map image.
	## Averages a 3×3 pixel grid from each tile's GRH region and composites
	## layer2 on top so terrain, trees, and buildings all show through.
	if not map_name.is_empty():
		_name_label.text = map_name

	# 2 pixels per tile → paths that are 1 tile wide become 2px lines
	var img := Image.create(MAP_IMG, MAP_IMG, false, Image.FORMAT_RGB8)
	var px_per_tile: int = MAP_IMG / 100   # = 2

	# Per-call image cache: file_num → Image
	var img_cache: Dictionary = {}

	for y in range(1, 101):
		for x in range(1, 101):
			var tile: Dictionary = tiles.get("%d,%d" % [y, x], {})
			var blocked: bool    = tile.get("blocked", 0) != 0
			var col: Color       = C_BLOCK if blocked else C_OPEN

			if _world != null:
				var layers: Array = tile.get("layers", [])
				var grh1: int = layers[0] if layers.size() > 0 else 0
				var grh2: int = layers[1] if layers.size() > 1 else 0

				# Layer 1 — ground/base terrain
				if grh1 > 0:
					var c1 := _sample_grh(grh1, img_cache)
					if c1.a > 0.05:
						col = Color(c1.r, c1.g, c1.b, 1.0)

				# Layer 2 — objects on the ground (trees, buildings, etc.)
				# Only blend when layer2 has dense coverage (alpha = filled ratio).
				# Keep the blend mild so layer1 terrain still reads through.
				if grh2 > 0:
					var c2 := _sample_grh(grh2, img_cache)
					if c2.a > 0.5:
						col = col.lerp(Color(c2.r, c2.g, c2.b, 1.0), 0.45)

			# Darken blocked tiles so walls read clearly over any sampled colour.
			if blocked:
				col = col.darkened(0.45)

			# Write a px_per_tile × px_per_tile block for this tile.
			var bx: int = (x - 1) * px_per_tile
			var by: int = (y - 1) * px_per_tile
			for dy in px_per_tile:
				for dx in px_per_tile:
					img.set_pixel(bx + dx, by + dy, col)

	_map_tex = ImageTexture.create_from_image(img)
	_map_rect.texture = _map_tex
	_dots_layer.queue_redraw()


func _sample_grh(grh_index: int, img_cache: Dictionary) -> Color:
	## Returns the true average colour of a GRH tile region by summing every
	## non-transparent pixel.  Result is cached per grh_index so each unique
	## tile type is only computed once regardless of how many tiles share it.
	if _grh_color_cache.has(grh_index):
		return _grh_color_cache[grh_index]

	var fd: Dictionary = GameData.get_grh_frame(grh_index, 0)
	if fd.is_empty():
		_grh_color_cache[grh_index] = Color.TRANSPARENT
		return Color.TRANSPARENT
	var file_num: int = fd.get("file_num", 0)
	if file_num <= 0:
		_grh_color_cache[grh_index] = Color.TRANSPARENT
		return Color.TRANSPARENT

	if not img_cache.has(file_num):
		var tex: Texture2D = _world.tex_cache.get_texture(file_num)
		img_cache[file_num] = tex.get_image() if tex != null else null

	var src: Image = img_cache.get(file_num)
	if src == null:
		_grh_color_cache[grh_index] = Color.TRANSPARENT
		return Color.TRANSPARENT

	var sx: int = fd.get("sx", 0)
	var sy: int = fd.get("sy", 0)
	var pw: int = fd.get("pixel_width",  32)
	var ph: int = fd.get("pixel_height", 32)
	var iw: int = src.get_width()
	var ih: int = src.get_height()

	# Sum every pixel in the tile region — full average, not a sparse sample.
	var r := 0.0; var g := 0.0; var b := 0.0; var n := 0
	for py in range(sy, mini(sy + ph, ih)):
		for px in range(sx, mini(sx + pw, iw)):
			var c := src.get_pixel(px, py)
			if c.a > 0.05:
				r += c.r; g += c.g; b += c.b; n += 1

	var col := Color(r / n, g / n, b / n, float(n) / float(pw * ph)) if n > 0 else Color.TRANSPARENT
	_grh_color_cache[grh_index] = col
	return col


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var panel_x := VIEWPORT_W - PANEL_W - MARGIN

	# ── Outer panel ──────────────────────────────────────────────────────────
	_panel = Panel.new()
	_panel.position = Vector2(panel_x, MARGIN)
	_panel.size     = Vector2(PANEL_W, PANEL_H_FULL)
	_panel.add_theme_stylebox_override("panel", _make_box(C_PANEL, C_BORDER, 1))
	add_child(_panel)

	# ── Header bar ───────────────────────────────────────────────────────────
	var header := Panel.new()
	header.position = Vector2(0, 0)
	header.size     = Vector2(PANEL_W, HEADER_H)
	header.add_theme_stylebox_override("panel", _make_box(C_HEADER, C_BORDER, 1))
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(header)

	_name_label = Label.new()
	_name_label.text = "Map"
	_name_label.add_theme_font_size_override("font_size", 11)
	_name_label.add_theme_color_override("font_color", Color(0.85, 0.65, 0.15, 1.0))
	_name_label.position = Vector2(6, 3)
	_name_label.size     = Vector2(PANEL_W - 28, HEADER_H - 4)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_name_label)

	_toggle_btn = Button.new()
	_toggle_btn.text = "−"
	_toggle_btn.position = Vector2(PANEL_W - 22, 2)
	_toggle_btn.size     = Vector2(18, 18)
	_toggle_btn.add_theme_font_size_override("font_size", 12)
	_toggle_btn.add_theme_stylebox_override("normal",
			_make_box(Color(0.14, 0.10, 0.04, 1.0), C_BORDER, 1))
	_toggle_btn.add_theme_stylebox_override("hover",
			_make_box(Color(0.24, 0.18, 0.06, 1.0), Color(0.85, 0.65, 0.15, 1.0), 1))
	_toggle_btn.add_theme_stylebox_override("pressed",
			_make_box(Color(0.08, 0.06, 0.02, 1.0), C_BORDER, 1))
	_toggle_btn.add_theme_color_override("font_color", Color(0.85, 0.65, 0.15, 1.0))
	_toggle_btn.pressed.connect(_on_toggle)
	header.add_child(_toggle_btn)

	# ── Map texture rect ──────────────────────────────────────────────────────
	_map_rect = TextureRect.new()
	_map_rect.position             = Vector2(5, HEADER_H + 2)
	_map_rect.size                 = Vector2(MAP_PX, MAP_PX)
	_map_rect.expand_mode          = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_map_rect.stretch_mode         = TextureRect.STRETCH_SCALE
	_map_rect.texture_filter       = CanvasItem.TEXTURE_FILTER_LINEAR
	_map_rect.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_map_rect)

	# ── Entity dot overlay (redraws every frame via _MinimapDots inner node) ──
	_dots_layer = _MinimapDots.new(self)
	_dots_layer.position     = Vector2(5, HEADER_H + 2)
	_dots_layer.size         = Vector2(MAP_PX, MAP_PX)
	_dots_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_dots_layer)

	# ── Night darkness overlay ────────────────────────────────────────────────
	_night_overlay = ColorRect.new()
	_night_overlay.position     = Vector2(5, HEADER_H + 2)
	_night_overlay.size         = Vector2(MAP_PX, MAP_PX)
	_night_overlay.color        = Color(0.0, 0.0, 0.05, 0.0)
	_night_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_night_overlay)


# ---------------------------------------------------------------------------
# Per-frame dot drawing
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _expanded and _world != null:
		_dots_layer.queue_redraw()


func _draw_dots() -> void:
	## Called from _MinimapDots._draw() — drawing commands execute on that node's canvas.
	if _world == null:
		return
	var chars: Dictionary = _world._chars
	var player_idx: int   = _world._player_idx
	var scale := float(MAP_PX) / 100.0

	for cid in chars:
		var c = chars[cid]
		if not c.active:
			continue
		var tp: Vector2i = c.tile_pos
		var px := (tp.x - 1) * scale
		var py := (tp.y - 1) * scale

		var col: Color
		var dot_size: float
		if cid == player_idx:
			col      = C_PLAYER
			dot_size = 3.5
		elif cid >= 10001:
			# Server NPC instance IDs start at 10001
			col      = C_ENEMY
			dot_size = 2.0
		else:
			# Other players
			col      = C_ALLY
			dot_size = 2.5

		_dots_layer.draw_rect(
			Rect2(px - dot_size * 0.5, py - dot_size * 0.5, dot_size, dot_size),
			col
		)


# ---------------------------------------------------------------------------
# Collapse / expand
# ---------------------------------------------------------------------------

func _on_toggle() -> void:
	_expanded = not _expanded
	_map_rect.visible      = _expanded
	_dots_layer.visible    = _expanded
	_toggle_btn.text       = "−" if _expanded else "+"
	_panel.size            = Vector2(PANEL_W,
			PANEL_H_FULL if _expanded else HEADER_H)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_box(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color     = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.corner_radius_top_left     = 3
	s.corner_radius_top_right    = 3
	s.corner_radius_bottom_left  = 3
	s.corner_radius_bottom_right = 3
	return s


# ---------------------------------------------------------------------------
# Inner class — draws entity dots via _draw() override
# ---------------------------------------------------------------------------

class _MinimapDots extends Control:
	var _minimap: MinimapUI

	func _init(owner: MinimapUI) -> void:
		_minimap = owner

	func _draw() -> void:
		_minimap._draw_dots()
