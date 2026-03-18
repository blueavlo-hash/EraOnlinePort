class_name MapEditor
extends Control
## Era Online — Professional Map Editor
## Full-featured in-game tile map editor. Launch with --editor command-line arg.
##
## Tools: Paint, Erase, Fill, Eyedropper, Blocked Toggle, Exit Link, NPC Place, Object Place
## Features: Undo/Redo, Pan/Zoom, Grid overlay, Blocked/Exit/NPC overlays,
##            Map+Tile properties panels, GRH browser, save/load JSON

# ── Constants ─────────────────────────────────────────────────────────────────
const TILE    := 32
const MAP_W   := 100
const MAP_H   := 100
const MIN_ZOOM := 0.15
const MAX_ZOOM := 5.0

# ── Enums ─────────────────────────────────────────────────────────────────────
enum Tool {
	PAINT,
	ERASE,
	FILL,
	EYEDROPPER,
	BLOCKED_TOGGLE,
	EXIT_LINK,
	NPC_PLACE,
	OBJECT_PLACE,
}

# ── Preloads ──────────────────────────────────────────────────────────────────
const TCClass         = preload("res://scripts/game/texture_cache.gd")
const GrhBrowserClass = preload("res://scripts/editor/grh_browser.gd")

# ── Map state ─────────────────────────────────────────────────────────────────
var _map_id:    int        = 0
var _map_dirty: bool       = false
var _map_meta:  Dictionary = {}   # name,music,start_pos,*_exit,pk_free
var _tiles:     Dictionary = {}   # "y,x" -> tile dict

# ── Camera state ──────────────────────────────────────────────────────────────
var _zoom:              float   = 1.5
var _tile_anim_acc:     float   = 0.0
var _tile_anim_tick:    int     = 0
var _pan_offset:        Vector2 = Vector2(16 * TILE, 8 * TILE)   # top-left world px
var _panning:           bool    = false
var _pan_start_screen:  Vector2 = Vector2.ZERO
var _pan_offset_start:  Vector2 = Vector2.ZERO
var _space_held:        bool    = false

# ── Tool state ────────────────────────────────────────────────────────────────
var _current_tool:  Tool = Tool.PAINT
var _active_layer:  int  = 1   # 0=L1, 1=L2, 2=L3
var _selected_grh:  int  = 1
var _selected_npc:  int  = 0
var _selected_obj:  int  = 0
var _hovered_tile:  Vector2i = Vector2i(1, 1)

var _painting:       bool       = false
var _painted_before: Dictionary = {}   # tile_key -> before snapshot
var _painted_after:  Dictionary = {}   # tile_key -> after snapshot

# Exit-link tool: two-click flow
var _exit_step:   int      = 0
var _exit_source: Vector2i = Vector2i(-1, -1)

# ── Overlay toggles ───────────────────────────────────────────────────────────
var _show_grid:    bool = true
var _show_blocked: bool = true
var _show_exits:   bool = true
var _show_npcs:    bool = true
var _show_objs:    bool = true

# NPC spawn file state
var _spawn_npcs:       Array        = []     # spawn dicts for current map
var _spawn_file:       Dictionary   = {}     # full npc_spawns.json contents
var _spawns_dirty:     bool         = false
var _drag_spawn_idx:   int          = -1     # index in _spawn_npcs being dragged, -1=none

# ── Systems ───────────────────────────────────────────────────────────────────
var _undo_redo: UndoRedo
var _tex_cache: RefCounted

# ── UI node references ────────────────────────────────────────────────────────
var _viewport_container: SubViewportContainer
var _viewport:           SubViewport
var _canvas:             Node2D
var _grh_browser:        GrhBrowser
var _status_label:       Label
var _coord_label:        Label
var _zoom_label:         Label
var _tool_btns:          Dictionary = {}   # Tool -> Button
var _layer_btns:         Array[Button] = []
# Left panel
var _sel_preview:      TextureRect
var _sel_grh_label:    Label
var _npc_spin:         SpinBox
var _npc_sel_label:    Label
var _obj_spin:         SpinBox
var _obj_amount_spin:  SpinBox
# Bottom tabs
var _tab_container:    TabContainer
# Map props fields
var _map_name_field:  LineEdit
var _map_music_field: LineEdit
var _map_pk_check:    CheckBox
var _map_start_x:     SpinBox
var _map_start_y:     SpinBox
var _exit_spins:      Dictionary = {}   # "north"/"south"/"west"/"east" -> SpinBox
# Tile props fields
var _tile_coord_label:   Label
var _tile_blocked_check: CheckBox
var _tile_npc_spin:      SpinBox
var _tile_obj_idx_spin:  SpinBox
var _tile_obj_amt_spin:  SpinBox
var _tile_exit_map_spin: SpinBox
var _tile_exit_x_spin:   SpinBox
var _tile_exit_y_spin:   SpinBox
# Minimap
var _minimap_image: Image
var _minimap_tex:   ImageTexture
var _minimap_rect:  TextureRect
var _minimap_dirty: bool = true


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_undo_redo = UndoRedo.new()
	_tex_cache = TCClass.new()
	_build_ui()
	_new_map()
	get_window().title = "Era Online — Map Editor"


func _process(delta: float) -> void:
	if not GameData.is_loaded:
		return
	# Arrow key panning (held down, 400 world-px/s, faster with Shift)
	var pan_speed := 600.0 / _zoom * delta
	if Input.is_key_pressed(KEY_SHIFT):
		pan_speed *= 3.0
	var moved := false
	if Input.is_key_pressed(KEY_LEFT)  or Input.is_key_pressed(KEY_A): _pan_offset.x -= pan_speed; moved = true
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): _pan_offset.x += pan_speed; moved = true
	if Input.is_key_pressed(KEY_UP)    or Input.is_key_pressed(KEY_W): _pan_offset.y -= pan_speed; moved = true
	if Input.is_key_pressed(KEY_DOWN)  or Input.is_key_pressed(KEY_S): _pan_offset.y += pan_speed; moved = true
	if moved:
		_clamp_pan()
		_update_canvas_transform()
	# Advance tile animation at ~30fps
	_tile_anim_acc += delta
	var ticks := int(_tile_anim_acc * 30.0)
	if ticks > 0:
		_tile_anim_acc -= float(ticks) / 30.0
		_tile_anim_tick += ticks
		_canvas.queue_redraw()
	# Keep SubViewport sized to its container
	var new_sz := Vector2i(_viewport_container.size)
	if new_sz.x > 0 and new_sz.y > 0 and new_sz != _viewport.size:
		_viewport.size = new_sz
	_update_canvas_transform()
	# Minimap refresh every ~60 frames
	if _minimap_dirty:
		_update_minimap()
		_minimap_dirty = false


# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey: return
	var k := event as InputEventKey
	if k.echo: return

	if not k.pressed:
		if k.keycode == KEY_SPACE: _space_held = false
		return

	# Space = pan mode while held
	if k.keycode == KEY_SPACE:
		_space_held = true
		return

	if k.ctrl_pressed:
		match k.keycode:
			KEY_Z: _undo_redo.undo(); _canvas.queue_redraw()
			KEY_Y: _undo_redo.redo(); _canvas.queue_redraw()
			KEY_S: _save_map()
			KEY_O: _open_map_dialog()
			KEY_N: _new_map()
		return

	match k.keycode:
		KEY_1: _set_tool(Tool.PAINT)
		KEY_2: _set_tool(Tool.ERASE)
		KEY_3: _set_tool(Tool.FILL)
		KEY_4: _set_tool(Tool.EYEDROPPER)
		KEY_5: _set_tool(Tool.BLOCKED_TOGGLE)
		KEY_6: _set_tool(Tool.EXIT_LINK)
		KEY_7: _set_tool(Tool.NPC_PLACE)
		KEY_8: _set_tool(Tool.OBJECT_PLACE)
		KEY_G: _show_grid = not _show_grid; _canvas.queue_redraw()
		KEY_B: _show_blocked = not _show_blocked; _canvas.queue_redraw()
		KEY_E: _show_exits = not _show_exits; _canvas.queue_redraw()
		KEY_EQUAL, KEY_KP_ADD:    _apply_zoom(1.2, Vector2(_viewport.size) * 0.5)
		KEY_MINUS, KEY_KP_SUBTRACT: _apply_zoom(1.0 / 1.2, Vector2(_viewport.size) * 0.5)
		KEY_0: _zoom = 1.5; _apply_zoom(1.0, Vector2(_viewport.size) * 0.5)
		KEY_ESCAPE:
			if _exit_step > 0:
				_exit_step = 0; _exit_source = Vector2i(-1,-1)
				_status_label.text = "Exit link cancelled."
				_canvas.queue_redraw()


func _on_viewport_gui_input(event: InputEvent) -> void:
	var local_pos := _viewport_container.get_local_mouse_position()
	var tile      := _screen_to_tile(local_pos)

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton

		match mb.button_index:
			MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					_panning = true
					_pan_start_screen  = local_pos
					_pan_offset_start  = _pan_offset
				else:
					_panning = false
				return

			MOUSE_BUTTON_WHEEL_UP:
				_apply_zoom(1.15, local_pos); return
			MOUSE_BUTTON_WHEEL_DOWN:
				_apply_zoom(1.0 / 1.15, local_pos); return

			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					if _space_held:
						_panning = true
						_pan_start_screen = local_pos
						_pan_offset_start = _pan_offset
					else:
						_on_tool_press(tile)
				else:
					_panning = false
					if _painting:
						_commit_batch_undo("Paint" if _current_tool == Tool.PAINT else "Erase")
					_painting = false
					if _drag_spawn_idx >= 0:
						_drag_spawn_idx = -1
						_spawns_dirty = true
						_canvas.queue_redraw()

			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					if _exit_step > 0:
						_exit_step = 0; _exit_source = Vector2i(-1,-1)
						_status_label.text = "Exit link cancelled."
						_canvas.queue_redraw()
					elif _current_tool == Tool.EXIT_LINK:
						_on_exit_link_right_click(tile)
					elif _current_tool == Tool.NPC_PLACE:
						_on_npc_tool_right_click(tile)
					else:
						_apply_eyedropper(tile)

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_hovered_tile = tile

		if _panning:
			var delta := local_pos - _pan_start_screen
			_pan_offset = _pan_offset_start - delta / _zoom
			_clamp_pan()
		elif _painting:
			_on_tool_drag(tile)

		_refresh_tile_props(tile)
		_update_status(tile)
		_canvas.queue_redraw()


# ── Tool dispatch ─────────────────────────────────────────────────────────────

func _on_tool_press(tile: Vector2i) -> void:
	match _current_tool:
		Tool.PAINT:
			_painting = true
			_painted_before.clear()
			_painted_after.clear()
			_apply_paint(tile)
		Tool.ERASE:
			_painting = true
			_painted_before.clear()
			_painted_after.clear()
			_apply_erase(tile)
		Tool.FILL:         _apply_fill(tile)
		Tool.EYEDROPPER:   _apply_eyedropper(tile)
		Tool.BLOCKED_TOGGLE: _apply_blocked_toggle(tile)
		Tool.EXIT_LINK:    _on_exit_link_click(tile)
		Tool.NPC_PLACE:    _on_npc_tool_press(tile)
		Tool.OBJECT_PLACE: _apply_object_place(tile)


func _on_tool_drag(tile: Vector2i) -> void:
	match _current_tool:
		Tool.PAINT: _apply_paint(tile)
		Tool.ERASE: _apply_erase(tile)
		Tool.NPC_PLACE:    _on_npc_tool_drag(tile)


# ── Individual tools ──────────────────────────────────────────────────────────

func _apply_paint(tile: Vector2i) -> void:
	if _selected_grh <= 0: return
	var key := _tile_key(tile.x, tile.y)
	if _painted_after.has(key): return
	var before: Dictionary = _tiles.get(key, {}).duplicate(true)
	var after: Dictionary  = before.duplicate(true)
	var layers: Array = after.get("layers", [0, 0, 0]).duplicate()
	while layers.size() < 3: layers.append(0)
	layers[_active_layer] = _selected_grh
	after["layers"] = layers
	_painted_before[key] = before
	_painted_after[key]  = after
	_tiles[key] = after
	_map_dirty = true
	_minimap_dirty = true
	_canvas.queue_redraw()


func _apply_erase(tile: Vector2i) -> void:
	var key := _tile_key(tile.x, tile.y)
	if _painted_after.has(key): return
	var before: Dictionary = _tiles.get(key, {}).duplicate(true)
	var after: Dictionary  = before.duplicate(true)
	var layers: Array = after.get("layers", [0, 0, 0]).duplicate()
	while layers.size() < 3: layers.append(0)
	layers[_active_layer] = 0
	after["layers"] = layers
	_painted_before[key] = before
	_painted_after[key]  = after
	_tiles[key] = after
	_map_dirty = true
	_minimap_dirty = true
	_canvas.queue_redraw()


func _apply_fill(start: Vector2i) -> void:
	var start_key    := _tile_key(start.x, start.y)
	var start_tile: Dictionary = _tiles.get(start_key, {})
	var start_layers: Array = start_tile.get("layers", [0, 0, 0])
	while start_layers.size() < 3: start_layers.append(0)
	var old_grh: int = start_layers[_active_layer]
	if old_grh == _selected_grh: return

	var affected := _flood_fill(start, old_grh)
	if affected.is_empty(): return

	var changes: Array = []
	for t in affected:
		var key    := _tile_key(t.x, t.y)
		var before: Dictionary = _tiles.get(key, {}).duplicate(true)
		var after: Dictionary  = before.duplicate(true)
		var layers: Array = after.get("layers", [0, 0, 0]).duplicate()
		while layers.size() < 3: layers.append(0)
		layers[_active_layer] = _selected_grh
		after["layers"] = layers
		changes.append({"key": key, "before": before, "after": after})

	_undo_redo.create_action("Fill %d tiles" % changes.size())
	_undo_redo.add_do_method(_apply_tile_changes.bind(changes, true))
	_undo_redo.add_undo_method(_apply_tile_changes.bind(changes, false))
	_undo_redo.commit_action()


func _flood_fill(start: Vector2i, old_grh: int) -> Array:
	var visited: Dictionary = {}
	var queue:   Array      = [start]
	var result:  Array      = []
	while queue.size() > 0:
		var t: Vector2i = queue.pop_front()
		if t.x < 1 or t.x > MAP_W or t.y < 1 or t.y > MAP_H: continue
		var k := _tile_key(t.x, t.y)
		if visited.has(k): continue
		visited[k] = true
		var tile: Dictionary = _tiles.get(k, {})
		var layers: Array = tile.get("layers", [0, 0, 0])
		var grh: int = layers[_active_layer] if _active_layer < layers.size() else 0
		if grh != old_grh: continue
		result.append(t)
		queue.append(Vector2i(t.x + 1, t.y))
		queue.append(Vector2i(t.x - 1, t.y))
		queue.append(Vector2i(t.x, t.y + 1))
		queue.append(Vector2i(t.x, t.y - 1))
	return result


func _apply_eyedropper(tile: Vector2i) -> void:
	var key    := _tile_key(tile.x, tile.y)
	var t: Dictionary = _tiles.get(key, {})
	var layers: Array = t.get("layers", [0, 0, 0])
	var grh: int = layers[_active_layer] if _active_layer < layers.size() else 0
	if grh > 0:
		_selected_grh = grh
		_refresh_selected_grh_preview()
		if _grh_browser: _grh_browser.highlight_grh(_selected_grh)
		_status_label.text = "Picked GRH #%d from layer %d" % [grh, _active_layer + 1]


func _apply_blocked_toggle(tile: Vector2i) -> void:
	var key    := _tile_key(tile.x, tile.y)
	var before: Dictionary = _tiles.get(key, {}).duplicate(true)
	var after: Dictionary  = before.duplicate(true)
	after["blocked"] = 0 if before.get("blocked", 0) != 0 else 1
	_undo_redo.create_action("Toggle Blocked (%d,%d)" % [tile.x, tile.y])
	_undo_redo.add_do_method(_apply_tile_changes.bind([{"key":key,"before":before,"after":after}], true))
	_undo_redo.add_undo_method(_apply_tile_changes.bind([{"key":key,"before":before,"after":after}], false))
	_undo_redo.commit_action()


func _on_exit_link_click(tile: Vector2i) -> void:
	if _exit_step == 0:
		_exit_source = tile
		_exit_step   = 1
		_status_label.text = "Exit Link: source set at (%d,%d) — now click destination or right-click to cancel" % [tile.x, tile.y]
		_canvas.queue_redraw()
	else:
		_show_exit_dest_dialog(tile)
		_exit_step = 0
		_canvas.queue_redraw()


func _on_exit_link_right_click(tile: Vector2i) -> void:
	## Right-click with EXIT_LINK tool: delete the exit on this tile if one exists.
	var key := _tile_key(tile.x, tile.y)
	var td: Dictionary = _tiles.get(key, {})
	if not td.has("exit"):
		_status_label.text = "No exit at (%d,%d)." % [tile.x, tile.y]
		return
	var before: Dictionary = td.duplicate(true)
	var after: Dictionary  = td.duplicate(true)
	after.erase("exit")
	_undo_redo.create_action("Delete Exit (%d,%d)" % [tile.x, tile.y])
	_undo_redo.add_do_method(_apply_tile_changes.bind([{"key": key, "before": before, "after": after}], true))
	_undo_redo.add_undo_method(_apply_tile_changes.bind([{"key": key, "before": before, "after": after}], false))
	_undo_redo.commit_action()
	_status_label.text = "Exit deleted at (%d,%d)." % [tile.x, tile.y]


func _apply_npc_place(tile: Vector2i) -> void:
	var key    := _tile_key(tile.x, tile.y)
	var before: Dictionary = _tiles.get(key, {}).duplicate(true)
	var after: Dictionary  = before.duplicate(true)
	if _selected_npc > 0:
		after["npc_index"] = _selected_npc
	else:
		after.erase("npc_index")
	_undo_redo.create_action("Place NPC")
	_undo_redo.add_do_method(_apply_tile_changes.bind([{"key":key,"before":before,"after":after}], true))
	_undo_redo.add_undo_method(_apply_tile_changes.bind([{"key":key,"before":before,"after":after}], false))
	_undo_redo.commit_action()


func _on_npc_tool_press(tile: Vector2i) -> void:
	## NPC tool left-click: drag existing spawn NPC, or place new one.
	## Right-click: delete spawn NPC at tile.
	var existing: int = _spawn_at_tile(tile.x, tile.y)
	if existing >= 0:
		_drag_spawn_idx = existing
		_painting = true   # enables mouse-motion → _on_tool_drag routing
		_canvas.queue_redraw()
		return
	if _selected_npc > 0:
		var entry: Dictionary = {"npc_index": _selected_npc, "x": tile.x, "y": tile.y}
		_spawn_npcs.append(entry)
		_spawns_dirty = true
		_canvas.queue_redraw()


func _on_npc_tool_drag(tile: Vector2i) -> void:
	## Moves the dragged spawn NPC to the hovered tile.
	if _drag_spawn_idx < 0 or _drag_spawn_idx >= _spawn_npcs.size():
		return
	var entry: Dictionary = _spawn_npcs[_drag_spawn_idx]
	if entry.get("x", -1) == tile.x and entry.get("y", -1) == tile.y:
		return
	entry["x"] = tile.x
	entry["y"] = tile.y
	_spawn_npcs[_drag_spawn_idx] = entry
	_canvas.queue_redraw()


func _on_npc_tool_right_click(tile: Vector2i) -> void:
	## Deletes spawn NPC at the clicked tile.
	var idx: int = _spawn_at_tile(tile.x, tile.y)
	if idx >= 0:
		_spawn_npcs.remove_at(idx)
		if _drag_spawn_idx == idx:
			_drag_spawn_idx = -1
		_spawns_dirty = true
		_canvas.queue_redraw()


func _apply_object_place(tile: Vector2i) -> void:
	var key    := _tile_key(tile.x, tile.y)
	var before: Dictionary = _tiles.get(key, {}).duplicate(true)
	var after: Dictionary  = before.duplicate(true)
	if _selected_obj > 0:
		after["obj"] = {"index": _selected_obj, "amount": int(_obj_amount_spin.value),
						"locked": 0, "sign": 0, "sign_owner": 0}
	else:
		after.erase("obj")
	_undo_redo.create_action("Place Object")
	_undo_redo.add_do_method(_apply_tile_changes.bind([{"key":key,"before":before,"after":after}], true))
	_undo_redo.add_undo_method(_apply_tile_changes.bind([{"key":key,"before":before,"after":after}], false))
	_undo_redo.commit_action()


# ── Batch undo commit (end of drag paint) ─────────────────────────────────────

func _commit_batch_undo(action_name: String) -> void:
	if _painted_before.is_empty(): return
	var changes: Array = []
	for key in _painted_before:
		changes.append({"key": key, "before": _painted_before[key],
						"after": _painted_after.get(key, {})})
	_undo_redo.create_action("%s %d tiles" % [action_name, changes.size()])
	_undo_redo.add_do_method(_apply_tile_changes.bind(changes, true))
	_undo_redo.add_undo_method(_apply_tile_changes.bind(changes, false))
	_undo_redo.commit_action()
	_painted_before.clear()
	_painted_after.clear()


func _apply_tile_changes(changes: Array, forward: bool) -> void:
	for c in changes:
		_tiles[c["key"]] = (c["after"] if forward else c["before"]).duplicate(true)
	_map_dirty = true
	_minimap_dirty = true
	_canvas.queue_redraw()
	_update_title()


# ── Camera helpers ────────────────────────────────────────────────────────────

func _screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var world := screen_pos / _zoom + _pan_offset
	return Vector2i(
		clampi(int(world.x / TILE) + 1, 1, MAP_W),
		clampi(int(world.y / TILE) + 1, 1, MAP_H)
	)


func _tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2((tile.x - 1) * TILE, (tile.y - 1) * TILE)


func _apply_zoom(factor: float, anchor_screen: Vector2) -> void:
	var world_before := anchor_screen / _zoom + _pan_offset
	_zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	_pan_offset = world_before - anchor_screen / _zoom
	_clamp_pan()
	if _zoom_label:
		_zoom_label.text = "%d%%" % int(_zoom * 100)
	_canvas.queue_redraw()


func _clamp_pan() -> void:
	var vp_world := Vector2(_viewport_container.size) / _zoom
	_pan_offset.x = clampf(_pan_offset.x, -vp_world.x * 0.5, MAP_W * TILE)
	_pan_offset.y = clampf(_pan_offset.y, -vp_world.y * 0.5, MAP_H * TILE)


func _update_canvas_transform() -> void:
	_canvas.scale    = Vector2(_zoom, _zoom)
	_canvas.position = -_pan_offset * _zoom


# ── Rendering ─────────────────────────────────────────────────────────────────

func _on_canvas_draw() -> void:
	# Black background
	_canvas.draw_rect(Rect2(0, 0, MAP_W * TILE, MAP_H * TILE), Color.BLACK)

	# Compute visible range
	var vp_sz  := Vector2(_viewport.size)
	var tl     := _pan_offset
	var br     := _pan_offset + vp_sz / _zoom
	var min_x  := clampi(int(tl.x / TILE),     0, MAP_W - 1)
	var max_x  := clampi(int(br.x / TILE) + 1, 0, MAP_W - 1)
	var min_y  := clampi(int(tl.y / TILE),     0, MAP_H - 1)
	var max_y  := clampi(int(br.y / TILE) + 1, 0, MAP_H - 1)

	# Pass 1: Layer 1 (opaque, no centering)
	for ty in range(min_y + 1, max_y + 2):
		for tx in range(min_x + 1, max_x + 2):
			var layers: Array = _tiles.get(_tile_key(tx, ty), {}).get("layers", [])
			if layers.size() > 0 and layers[0] > 0:
				_draw_grh(layers[0], (tx - 1) * TILE, (ty - 1) * TILE, false)

	# Pass 2: Layer 2 + objects + Layer 3 (transparent, centered)
	for ty in range(min_y + 1, max_y + 2):
		for tx in range(min_x + 1, max_x + 2):
			var key    := _tile_key(tx, ty)
			var t: Dictionary = _tiles.get(key, {})
			var layers: Array = t.get("layers", [])
			var wx := (tx - 1) * TILE
			var wy := (ty - 1) * TILE
			if layers.size() > 1 and layers[1] > 0:
				_draw_grh(layers[1], wx, wy, true)
			var obj: Dictionary = t.get("obj", {})
			if not obj.is_empty() and _show_objs:
				var og: int = GameData.get_object(obj.get("index", 0)).get("grh_index", 0)
				if og > 0: _draw_grh(og, wx, wy, true)
			if layers.size() > 2 and layers[2] > 0:
				_draw_grh(layers[2], wx, wy, true)

	# ── Overlays ────────────────────────────────────────────────────────────

	if _show_blocked:
		for ty in range(min_y + 1, max_y + 2):
			for tx in range(min_x + 1, max_x + 2):
				if _tiles.get(_tile_key(tx, ty), {}).get("blocked", 0) != 0:
					_canvas.draw_rect(Rect2((tx-1)*TILE, (ty-1)*TILE, TILE, TILE),
							Color(1, 0, 0, 0.38))

	if _show_exits:
		for ty in range(min_y + 1, max_y + 2):
			for tx in range(min_x + 1, max_x + 2):
				var ex: Dictionary = _tiles.get(_tile_key(tx, ty), {}).get("exit", {})
				if not ex.is_empty():
					_canvas.draw_rect(Rect2((tx-1)*TILE, (ty-1)*TILE, TILE, TILE),
							Color(0, 0.5, 1, 0.28))
					_canvas.draw_rect(Rect2((tx-1)*TILE, (ty-1)*TILE, TILE, TILE),
							Color(0.3, 0.8, 1, 0.9), false, 1.5)

	if _show_npcs:
		var font := ThemeDB.fallback_font
		# Tile-data NPCs (hostile monsters) — yellow dot
		for ty in range(min_y + 1, max_y + 2):
			for tx in range(min_x + 1, max_x + 2):
				var npc_idx: int = _tiles.get(_tile_key(tx, ty), {}).get("npc_index", 0)
				if npc_idx > 0:
					var cx := (tx - 1) * TILE + 16.0
					var cy := (ty - 1) * TILE + 16.0
					_canvas.draw_circle(Vector2(cx, cy), 7.0, Color(1, 0.8, 0, 0.9))
					var nd: Dictionary = GameData.get_npc(npc_idx)
					var label: String = nd.get("name", str(npc_idx))
					if label.length() > 5: label = label.substr(0, 5)
					_canvas.draw_string(font, Vector2(cx - 12, cy - 10), label,
							HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color.WHITE)
		# Spawn-file NPCs (shopkeepers, service) — cyan dot, full name
		for i in _spawn_npcs.size():
			var entry: Dictionary = _spawn_npcs[i]
			var tx: int = entry.get("x", -1)
			var ty: int = entry.get("y", -1)
			if tx < min_x or tx > max_x + 1 or ty < min_y or ty > max_y + 1:
				continue
			var cx := (tx - 1) * TILE + 16.0
			var cy := (ty - 1) * TILE + 16.0
			var col := Color(0, 1, 1, 0.95) if i != _drag_spawn_idx else Color(1, 1, 0, 1.0)
			_canvas.draw_circle(Vector2(cx, cy), 9.0, col)
			_canvas.draw_circle(Vector2(cx, cy), 9.0, Color.WHITE, false, 1.5)
			var lbl: String = _spawn_label(entry)
			_canvas.draw_string(font, Vector2(cx - 14, cy - 11), lbl,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.WHITE)

	# Grid
	if _show_grid:
		var gc := Color(0.4, 0.4, 0.4, 0.35 * clampf(_zoom, 0.5, 1.0))
		for tx in range(min_x + 1, max_x + 3):
			_canvas.draw_line(Vector2((tx-1)*float(TILE), min_y*float(TILE)),
					Vector2((tx-1)*float(TILE), (max_y+1)*float(TILE)), gc, 0.5)
		for ty in range(min_y + 1, max_y + 3):
			_canvas.draw_line(Vector2(min_x*float(TILE), (ty-1)*float(TILE)),
					Vector2((max_x+1)*float(TILE), (ty-1)*float(TILE)), gc, 0.5)

	# Map border (bright)
	_canvas.draw_rect(Rect2(0, 0, MAP_W * TILE, MAP_H * TILE),
			Color(0.8, 0.8, 0.2, 0.7), false, 2.0)

	# Hover cursor
	var ht := _hovered_tile
	_canvas.draw_rect(Rect2((ht.x-1)*TILE, (ht.y-1)*TILE, TILE, TILE),
			Color(1, 1, 1, 0.22))
	_canvas.draw_rect(Rect2((ht.x-1)*TILE, (ht.y-1)*TILE, TILE, TILE),
			Color(1, 1, 1, 0.85), false, 1.5)

	# Exit-link source highlight
	if _exit_step == 1 and _exit_source != Vector2i(-1, -1):
		var es := _exit_source
		_canvas.draw_rect(Rect2((es.x-1)*TILE, (es.y-1)*TILE, TILE, TILE),
				Color(1, 0.5, 0, 0.45))
		_canvas.draw_rect(Rect2((es.x-1)*TILE, (es.y-1)*TILE, TILE, TILE),
				Color(1, 0.7, 0, 1.0), false, 2.5)


func _draw_grh(grh_index: int, wx: float, wy: float, centered: bool) -> void:
	if grh_index <= 0: return
	var entry := GameData.get_grh(grh_index)
	if entry.is_empty(): return
	var frame := 0
	var num_frames: int = entry.get("num_frames", 1)
	if num_frames > 1:
		var speed: int = max(1, entry.get("speed", 1) + 1)
		frame = (_tile_anim_tick / speed) % num_frames
	var fd := GameData.get_grh_frame(grh_index, frame)
	if fd.is_empty(): return
	_blit(fd, wx, wy, centered)


func _blit(fd: Dictionary, wx: float, wy: float, centered: bool) -> void:
	var file_num: int = fd.get("file_num", 0)
	if file_num <= 0: return
	var tex: Texture2D = _tex_cache.get_texture(file_num)
	if tex == null: return
	var sx: int = fd.get("sx", 0); var sy: int = fd.get("sy", 0)
	var pw: int = fd.get("pixel_width", TILE); var ph: int = fd.get("pixel_height", TILE)
	var dx := wx; var dy := wy
	if centered:
		dx = wx - pw / 2.0 + 16.0
		dy = wy - ph + float(TILE)
	_canvas.draw_texture_rect_region(tex,
			Rect2(dx, dy, pw, ph), Rect2(sx, sy, pw, ph))


# ── Minimap ───────────────────────────────────────────────────────────────────

func _update_minimap() -> void:
	if _minimap_rect == null: return
	const SZ := 100
	if _minimap_image == null:
		_minimap_image = Image.create(SZ, SZ, false, Image.FORMAT_RGB8)
		_minimap_tex = ImageTexture.create_from_image(_minimap_image)
		_minimap_rect.texture = _minimap_tex

	_minimap_image.fill(Color(0.1, 0.1, 0.1))
	for ty in range(1, MAP_H + 1):
		for tx in range(1, MAP_W + 1):
			var t: Dictionary = _tiles.get(_tile_key(tx, ty), {})
			var col: Color
			if t.get("blocked", 0) != 0:
				col = Color(0.8, 0.2, 0.2)
			else:
				var layers: Array = t.get("layers", [])
				if layers.size() > 0 and layers[0] > 0:
					col = Color(0.45, 0.55, 0.35)
				else:
					col = Color(0.1, 0.1, 0.1)
			_minimap_image.set_pixel(tx - 1, ty - 1, col)
	_minimap_tex.update(_minimap_image)
	_minimap_rect.queue_redraw()


# ── Map I/O ───────────────────────────────────────────────────────────────────

func _new_map() -> void:
	_map_id   = 0
	_map_meta = {"name": "New Map", "music": "1",
				 "start_pos": {"map": 0, "x": 10, "y": 10},
				 "north_exit": 0, "south_exit": 0, "west_exit": 0, "east_exit": 0,
				 "pk_free": false}
	_tiles = {}
	_map_dirty = false
	_minimap_dirty = true
	_undo_redo.clear_history()
	_refresh_map_props()
	_canvas.queue_redraw()
	_update_title()
	_status_label.text = "New blank map created."


func _open_map_dialog() -> void:
	var d := AcceptDialog.new()
	d.title = "Open Map"
	var vb   := VBoxContainer.new()
	var lbl  := Label.new(); lbl.text = "Map ID (1–211):"
	var spin := SpinBox.new()
	spin.min_value = 1; spin.max_value = 999; spin.value = max(1, _map_id)
	vb.add_child(lbl); vb.add_child(spin)
	d.add_child(vb)
	d.confirmed.connect(func(): var id := int(spin.value); d.queue_free(); _load_map(id))
	d.canceled.connect(func(): d.queue_free())
	add_child(d)
	d.popup_centered(Vector2i(280, 130))


func _load_map(map_id: int) -> void:
	var data := GameData.get_map(map_id)
	if data.is_empty():
		_status_label.text = "Map %d not found. Have you run the pipeline?" % map_id
		return
	_map_id   = map_id
	_map_meta = {
		"name":       data.get("name", ""),
		"music":      str(data.get("music", "1")),
		"start_pos":  data.get("start_pos", {"map": map_id, "x": 10, "y": 10}),
		"north_exit": data.get("north_exit", 0),
		"south_exit": data.get("south_exit", 0),
		"west_exit":  data.get("west_exit", 0),
		"east_exit":  data.get("east_exit", 0),
		"pk_free":    data.get("pk_free_zone", false),
	}
	_tiles = {}
	for key in data.get("tiles", {}):
		_tiles[key] = (data["tiles"][key] as Dictionary).duplicate(true)
	_load_spawn_npcs()
	_map_dirty = false
	_minimap_dirty = true
	_undo_redo.clear_history()
	_refresh_map_props()
	_canvas.queue_redraw()
	_update_title()
	_status_label.text = "Loaded Map %d — %s  (%d tiles)" % [
			map_id, _map_meta["name"], _tiles.size()]


func _save_map() -> void:
	if _map_id <= 0:
		_save_map_as_dialog()
		return
	var path := ProjectSettings.globalize_path("res://data/maps/map_%d.json" % _map_id)
	var data := _serialize_map()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_status_label.text = "ERROR: Cannot write " + path
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	_save_spawn_npcs()
	_map_dirty = false
	_update_title()
	# Bust GameData cache so the game sees the change immediately
	GameData._map_cache.erase(_map_id)
	_status_label.text = "Saved → " + path


func _save_map_as_dialog() -> void:
	var d := AcceptDialog.new()
	d.title = "Save Map As"
	var vb   := VBoxContainer.new()
	var lbl  := Label.new(); lbl.text = "Map ID:"
	var spin := SpinBox.new()
	spin.min_value = 1; spin.max_value = 999; spin.value = max(1, _map_id)
	vb.add_child(lbl); vb.add_child(spin)
	d.add_child(vb)
	d.confirmed.connect(func(): _map_id = int(spin.value); d.queue_free(); _save_map())
	d.canceled.connect(func(): d.queue_free())
	add_child(d)
	d.popup_centered(Vector2i(280, 130))


func _serialize_map() -> Dictionary:
	var sp: Dictionary = _map_meta.get("start_pos", {"map": _map_id, "x": 10, "y": 10})
	var result := {
		"id": _map_id, "name": _map_meta.get("name", ""),
		"music": _map_meta.get("music", "1"), "start_pos": sp,
		"north_exit": _map_meta.get("north_exit", 0),
		"south_exit": _map_meta.get("south_exit", 0),
		"west_exit":  _map_meta.get("west_exit", 0),
		"east_exit":  _map_meta.get("east_exit", 0),
		"pk_free_zone": _map_meta.get("pk_free", false),
		"tile_count": MAP_W * MAP_H,
		"tiles": {}
	}
	for key in _tiles:
		var t: Dictionary = _tiles[key]
		var entry: Dictionary = {}
		var layers: Array = t.get("layers", [0, 0, 0])
		if layers.any(func(v): return v != 0): entry["layers"] = layers
		if t.get("blocked", 0) != 0: entry["blocked"] = t["blocked"]
		var ni: int = t.get("npc_index", 0)
		if ni > 0: entry["npc_index"] = ni
		var obj: Dictionary = t.get("obj", {})
		if not obj.is_empty(): entry["obj"] = obj
		var ex: Dictionary = t.get("exit", {})
		if not ex.is_empty(): entry["exit"] = ex
		if not entry.is_empty(): result["tiles"][key] = entry
	return result


func _load_spawn_npcs() -> void:
	## Loads npc_spawns.json and populates _spawn_npcs for the current map.
	_spawn_npcs = []
	_spawns_dirty = false
	var path := ProjectSettings.globalize_path("res://data/npc_spawns.json")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_spawn_file = parsed
		var arr = parsed.get(str(_map_id), [])
		if arr is Array:
			for entry in arr:
				_spawn_npcs.append((entry as Dictionary).duplicate(true))
	_canvas.queue_redraw()


func _save_spawn_npcs() -> void:
	## Writes current _spawn_npcs back to npc_spawns.json.
	if not _spawns_dirty:
		return
	_spawn_file[str(_map_id)] = _spawn_npcs.duplicate(true)
	var path := ProjectSettings.globalize_path("res://data/npc_spawns.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Cannot write " + path)
		return
	f.store_string(JSON.stringify(_spawn_file, "\t"))
	f.close()
	_spawns_dirty = false


func _spawn_label(entry: Dictionary) -> String:
	## Returns a short display name for a spawn entry.
	if entry.has("name"):
		return entry["name"]
	var ni: int = entry.get("npc_index", 0)
	if ni > 0:
		var nd: Dictionary = GameData.get_npc(ni)
		if not nd.is_empty():
			return nd.get("name", str(ni))
	return "NPC"


func _spawn_at_tile(tx: int, ty: int) -> int:
	## Returns index of spawn entry whose (x,y) matches tile, or -1.
	for i in _spawn_npcs.size():
		var e: Dictionary = _spawn_npcs[i]
		if e.get("x", -1) == tx and e.get("y", -1) == ty:
			return i
	return -1


# ── Exit-link destination dialog ──────────────────────────────────────────────

func _show_exit_dest_dialog(_unused_dest_tile: Vector2i) -> void:
	## Exit destination picker: visual map preview + click to pick tile.
	const PREVIEW_PX := 300   # preview canvas size in screen pixels
	const CELL       := 3     # screen pixels per map tile (100 tiles × 3 = 300)

	# ── Window ────────────────────────────────────────────────────────────────
	var win := Window.new()
	win.title  = "Set Exit Destination  —  Map %d  (%d,%d)" % [_map_id, _exit_source.x, _exit_source.y]
	win.size   = Vector2i(PREVIEW_PX + 220, PREVIEW_PX + 20)
	win.exclusive  = true
	win.unresizable = true

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	win.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	margin.add_child(hbox)

	# ── Left: clickable map preview ───────────────────────────────────────────
	var preview_wrap := Panel.new()
	preview_wrap.custom_minimum_size = Vector2(PREVIEW_PX, PREVIEW_PX)
	hbox.add_child(preview_wrap)

	var preview := Control.new()
	preview.custom_minimum_size = Vector2(PREVIEW_PX, PREVIEW_PX)
	preview.mouse_filter = Control.MOUSE_FILTER_STOP
	preview_wrap.add_child(preview)

	# Mutable state captured by lambdas
	var dest_map := [_map_id]        # [int]
	var sel      := [_exit_source.x, _exit_source.y]  # [x, y] — default to source tile
	var img_ref  : Array[Image]        = [null]
	var tex_ref  : Array[ImageTexture] = [null]

	# ── Right: controls ───────────────────────────────────────────────────────
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(vbox)

	var lbl_map := Label.new(); lbl_map.text = "Destination Map:"
	vbox.add_child(lbl_map)

	var spin_m := SpinBox.new()
	spin_m.min_value = 1; spin_m.max_value = 999; spin_m.value = _map_id
	vbox.add_child(spin_m)

	vbox.add_child(HSeparator.new())

	var lbl_sel := Label.new()
	lbl_sel.text = "Tile:  X=%d  Y=%d" % [sel[0], sel[1]]
	vbox.add_child(lbl_sel)

	var hint := Label.new()
	hint.text = "Click the preview to\npick the landing tile.\n\nGreen = walkable\nRed = blocked\nYellow = your selection"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hint)

	vbox.add_spacer(false)

	var btn_ok  := Button.new(); btn_ok.text  = "Confirm"
	var btn_can := Button.new(); btn_can.text = "Cancel"
	vbox.add_child(btn_ok)
	vbox.add_child(btn_can)

	# ── Build preview image for a given map id ────────────────────────────────
	var build_preview := func(mid: int) -> void:
		var img := Image.create(MAP_W, MAP_H, false, Image.FORMAT_RGB8)
		img.fill(Color(0.05, 0.05, 0.05))
		# Use live _tiles when previewing the map currently being edited.
		var tile_src: Dictionary = _tiles if mid == _map_id else \
				GameData.get_map(mid).get("tiles", {})
		for ty in range(1, MAP_H + 1):
			for tx in range(1, MAP_W + 1):
				var t: Dictionary = tile_src.get(_tile_key(tx, ty), {})
				var col: Color
				if t.get("blocked", 0) != 0:
					col = Color(0.75, 0.2, 0.2)
				elif t.get("exit") != null:
					col = Color(0.2, 0.5, 0.9)   # blue tint = existing exit
				else:
					var layers: Array = t.get("layers", [])
					col = Color(0.38, 0.50, 0.28) if (layers.size() > 0 and layers[0] > 0) \
						  else Color(0.08, 0.08, 0.08)
				img.set_pixel(tx - 1, ty - 1, col)
		img_ref[0] = img
		if tex_ref[0] == null:
			tex_ref[0] = ImageTexture.create_from_image(img)
		else:
			tex_ref[0].update(img)

	# ── Draw callback ─────────────────────────────────────────────────────────
	preview.draw.connect(func():
		if tex_ref[0] == null: return
		preview.draw_texture_rect(tex_ref[0],
				Rect2(Vector2.ZERO, Vector2(PREVIEW_PX, PREVIEW_PX)), false)
		# Crosshair at selected tile
		var cx: int = (int(sel[0]) - 1) * CELL
		var cy: int = (int(sel[1]) - 1) * CELL
		preview.draw_rect(Rect2(cx, cy, CELL, CELL), Color.YELLOW, false, 1.0)
		preview.draw_line(Vector2(cx + CELL * 0.5, 0),
				Vector2(cx + CELL * 0.5, PREVIEW_PX), Color(1, 1, 0, 0.35), 1)
		preview.draw_line(Vector2(0, cy + CELL * 0.5),
				Vector2(PREVIEW_PX, cy + CELL * 0.5), Color(1, 1, 0, 0.35), 1)
	)

	# ── Click on preview to pick tile ─────────────────────────────────────────
	preview.gui_input.connect(func(ev: InputEvent):
		if not (ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT):
			return
		var tx := clampi(int(ev.position.x / CELL) + 1, 1, MAP_W)
		var ty := clampi(int(ev.position.y / CELL) + 1, 1, MAP_H)
		sel[0] = tx; sel[1] = ty
		lbl_sel.text = "Tile:  X=%d  Y=%d" % [tx, ty]
		preview.queue_redraw()
	)

	# ── Map spinner → rebuild preview ─────────────────────────────────────────
	spin_m.value_changed.connect(func(v: float):
		dest_map[0] = int(v)
		build_preview.call(int(v))
		preview.queue_redraw()
	)

	# ── Confirm ───────────────────────────────────────────────────────────────
	btn_ok.pressed.connect(func():
		var src := _exit_source
		var key  := _tile_key(src.x, src.y)
		var before: Dictionary = _tiles.get(key, {}).duplicate(true)
		var after: Dictionary  = before.duplicate(true)
		after["exit"] = {"map": dest_map[0], "x": sel[0], "y": sel[1]}
		_undo_redo.create_action("Set Exit Link (%d,%d)" % [src.x, src.y])
		_undo_redo.add_do_method(_apply_tile_changes.bind(
				[{"key": key, "before": before, "after": after}], true))
		_undo_redo.add_undo_method(_apply_tile_changes.bind(
				[{"key": key, "before": before, "after": after}], false))
		_undo_redo.commit_action()
		_status_label.text = "Exit set: (%d,%d) → Map%d @ (%d,%d)" % [
				src.x, src.y, dest_map[0], sel[0], sel[1]]
		win.queue_free()
	)

	btn_can.pressed.connect(func(): win.queue_free())
	win.close_requested.connect(func(): win.queue_free())

	# ── Show ──────────────────────────────────────────────────────────────────
	build_preview.call(_map_id)
	add_child(win)
	win.popup_centered()


# ── UI helpers ────────────────────────────────────────────────────────────────

func _tile_key(tx: int, ty: int) -> String:
	return "%d,%d" % [ty, tx]


func _set_tool(tool: Tool) -> void:
	_current_tool = tool
	for t in _tool_btns:
		_tool_btns[t].button_pressed = (t == tool)
	if tool != Tool.EXIT_LINK:
		_exit_step = 0
		_exit_source = Vector2i(-1, -1)


func _set_layer(layer: int) -> void:
	_active_layer = layer
	for i in 3:
		_layer_btns[i].button_pressed = (i == layer)


func _on_grh_selected(grh_index: int) -> void:
	_selected_grh = grh_index
	_refresh_selected_grh_preview()
	# Switch to paint tool automatically when a GRH is picked
	if _current_tool == Tool.EYEDROPPER:
		_set_tool(Tool.PAINT)


func _refresh_selected_grh_preview() -> void:
	if _sel_grh_label: _sel_grh_label.text = "GRH #%d" % _selected_grh
	if _sel_preview == null or _selected_grh <= 0:
		if _sel_preview: _sel_preview.texture = null
		return
	var fd := GameData.get_grh_frame(_selected_grh, 0)
	if fd.is_empty(): return
	var tex: Texture2D = _tex_cache.get_texture(fd.get("file_num", 0))
	if tex == null: return
	var at := AtlasTexture.new()
	at.atlas  = tex
	at.region = Rect2(fd.get("sx",0), fd.get("sy",0),
					  fd.get("pixel_width",32), fd.get("pixel_height",32))
	_sel_preview.texture = at


func _refresh_tile_props(tile: Vector2i) -> void:
	if _tile_coord_label == null: return
	var key := _tile_key(tile.x, tile.y)
	var t: Dictionary = _tiles.get(key, {})
	_tile_coord_label.text = "(%d, %d)" % [tile.x, tile.y]

	_tile_blocked_check.set_block_signals(true)
	_tile_blocked_check.button_pressed = t.get("blocked", 0) != 0
	_tile_blocked_check.set_block_signals(false)

	_tile_npc_spin.set_block_signals(true)
	_tile_npc_spin.value = t.get("npc_index", 0)
	_tile_npc_spin.set_block_signals(false)

	var obj: Dictionary = t.get("obj", {})
	_tile_obj_idx_spin.set_block_signals(true); _tile_obj_idx_spin.value = obj.get("index", 0); _tile_obj_idx_spin.set_block_signals(false)
	_tile_obj_amt_spin.set_block_signals(true); _tile_obj_amt_spin.value = obj.get("amount", 1); _tile_obj_amt_spin.set_block_signals(false)

	var ex: Dictionary = t.get("exit", {})
	_tile_exit_map_spin.set_block_signals(true); _tile_exit_map_spin.value = ex.get("map", 0); _tile_exit_map_spin.set_block_signals(false)
	_tile_exit_x_spin.set_block_signals(true);   _tile_exit_x_spin.value = ex.get("x", 1);    _tile_exit_x_spin.set_block_signals(false)
	_tile_exit_y_spin.set_block_signals(true);   _tile_exit_y_spin.value = ex.get("y", 1);    _tile_exit_y_spin.set_block_signals(false)


func _apply_tile_props(tile: Vector2i) -> void:
	var key    := _tile_key(tile.x, tile.y)
	var before: Dictionary = _tiles.get(key, {}).duplicate(true)
	var after: Dictionary  = before.duplicate(true)
	after["blocked"] = 1 if _tile_blocked_check.button_pressed else 0
	var ni := int(_tile_npc_spin.value)
	if ni > 0:
		after["npc_index"] = ni
	else:
		after.erase("npc_index")
	var oi := int(_tile_obj_idx_spin.value)
	if oi > 0:
		after["obj"] = {"index": oi, "amount": int(_tile_obj_amt_spin.value),
						"locked": 0, "sign": 0, "sign_owner": 0}
	else: after.erase("obj")
	var em := int(_tile_exit_map_spin.value)
	if em > 0:
		after["exit"] = {"map": em, "x": int(_tile_exit_x_spin.value), "y": int(_tile_exit_y_spin.value)}
	else: after.erase("exit")
	_undo_redo.create_action("Apply Tile Props")
	_undo_redo.add_do_method(_apply_tile_changes.bind([{"key":key,"before":before,"after":after}], true))
	_undo_redo.add_undo_method(_apply_tile_changes.bind([{"key":key,"before":before,"after":after}], false))
	_undo_redo.commit_action()


func _refresh_map_props() -> void:
	if _map_name_field == null: return
	_map_name_field.set_block_signals(true);  _map_name_field.text = _map_meta.get("name", "");           _map_name_field.set_block_signals(false)
	_map_music_field.set_block_signals(true); _map_music_field.text = str(_map_meta.get("music", "1")); _map_music_field.set_block_signals(false)
	_map_pk_check.set_block_signals(true);    _map_pk_check.button_pressed = _map_meta.get("pk_free", false); _map_pk_check.set_block_signals(false)
	var sp: Dictionary = _map_meta.get("start_pos", {"x": 10, "y": 10})
	_map_start_x.set_block_signals(true); _map_start_x.value = sp.get("x", 10); _map_start_x.set_block_signals(false)
	_map_start_y.set_block_signals(true); _map_start_y.value = sp.get("y", 10); _map_start_y.set_block_signals(false)
	for dir in ["north", "south", "west", "east"]:
		_exit_spins[dir].set_block_signals(true)
		_exit_spins[dir].value = _map_meta.get(dir + "_exit", 0)
		_exit_spins[dir].set_block_signals(false)


func _update_status(tile: Vector2i) -> void:
	var key    := _tile_key(tile.x, tile.y)
	var t: Dictionary = _tiles.get(key, {})
	var layers: Array = t.get("layers", [0, 0, 0])
	var l1: int = layers[0] if layers.size() > 0 else 0
	var l2: int = layers[1] if layers.size() > 1 else 0
	var l3: int = layers[2] if layers.size() > 2 else 0
	_coord_label.text = "(%d, %d)  L1:%d  L2:%d  L3:%d  %s%s%s" % [
		tile.x, tile.y, l1, l2, l3,
		" [BLK]" if t.get("blocked",0) != 0 else "",
		" [NPC:%d]" % t["npc_index"] if t.get("npc_index",0) > 0 else "",
		" [EXIT→%d]" % t["exit"]["map"] if t.has("exit") and not t["exit"].is_empty() else ""
	]


func _update_title() -> void:
	var title := "Era Online — Map Editor"
	if _map_id > 0:      title += "  [Map %d]" % _map_id
	if _map_meta.get("name", "") != "": title += " %s" % _map_meta["name"]
	if _map_dirty:       title += "  *unsaved*"
	get_window().title = title


# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	var master := VBoxContainer.new()
	master.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	master.add_theme_constant_override("separation", 0)
	add_child(master)

	master.add_child(_build_menu_bar())
	master.add_child(_build_toolbar())

	var work := HBoxContainer.new()
	work.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	work.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	work.add_theme_constant_override("separation", 2)
	master.add_child(work)
	work.add_child(_build_left_panel())
	work.add_child(_build_center_column())
	work.add_child(_build_right_panel())

	master.add_child(_build_status_bar())


func _build_menu_bar() -> MenuBar:
	var mb := MenuBar.new()
	mb.custom_minimum_size.y = 24

	# File
	var file := PopupMenu.new(); file.name = "File"
	file.add_item("New Map",      0); file.set_item_shortcut(0, _shortcut(KEY_N, true))
	file.add_item("Open Map…",    1); file.set_item_shortcut(1, _shortcut(KEY_O, true))
	file.add_separator()
	file.add_item("Save",         2); file.set_item_shortcut(2, _shortcut(KEY_S, true))
	file.add_item("Save As…",     3)
	file.add_separator()
	file.add_item("Exit",         4)
	file.id_pressed.connect(_on_menu_file)
	mb.add_child(file)

	# Edit
	var edit := PopupMenu.new(); edit.name = "Edit"
	edit.add_item("Undo",         0); edit.set_item_shortcut(0, _shortcut(KEY_Z, true))
	edit.add_item("Redo",         1); edit.set_item_shortcut(1, _shortcut(KEY_Y, true))
	edit.add_separator()
	edit.add_item("Clear Layer",  2)
	edit.id_pressed.connect(_on_menu_edit)
	mb.add_child(edit)

	# View
	var view := PopupMenu.new(); view.name = "View"
	view.add_check_item("Grid (G)",         0); view.set_item_checked(0, _show_grid)
	view.add_check_item("Blocked (B)",      1); view.set_item_checked(1, _show_blocked)
	view.add_check_item("Exit tiles (E)",   2); view.set_item_checked(2, _show_exits)
	view.add_check_item("NPC markers (N)",  3); view.set_item_checked(3, _show_npcs)
	view.add_separator()
	view.add_item("Zoom In  (+)",           4)
	view.add_item("Zoom Out (-)",           5)
	view.add_item("Reset Zoom (0)",         6)
	view.id_pressed.connect(_on_menu_view.bind(view))
	mb.add_child(view)

	# Map
	var map_m := PopupMenu.new(); map_m.name = "Map"
	map_m.add_item("Jump to Map…",  0)
	map_m.add_item("Validate Exits", 1)
	map_m.add_separator()
	map_m.add_item("Place Rain (Layer 3)", 2)
	map_m.add_item("Clear Rain (Layer 3)", 3)
	map_m.id_pressed.connect(_on_menu_map)
	mb.add_child(map_m)

	return mb


func _build_toolbar() -> HBoxContainer:
	var tb := HBoxContainer.new()
	tb.custom_minimum_size.y = 36
	tb.add_theme_constant_override("separation", 2)

	var bg := ButtonGroup.new()

	var tool_defs := [
		[Tool.PAINT,        "✏ Paint",   "1"],
		[Tool.ERASE,        "⬜ Erase",  "2"],
		[Tool.FILL,         "🪣 Fill",   "3"],
		[Tool.EYEDROPPER,   "💧 Pick",   "4"],
		[Tool.BLOCKED_TOGGLE,"🚫 Block", "5"],
		[Tool.EXIT_LINK,    "🔗 Exit",   "6"],
		[Tool.NPC_PLACE,    "👾 NPC",    "7"],
		[Tool.OBJECT_PLACE, "📦 Object", "8"],
	]
	for def in tool_defs:
		var btn := Button.new()
		btn.text         = def[1]
		btn.tooltip_text = "%s  [%s]" % [def[1], def[2]]
		btn.toggle_mode  = true
		btn.button_group = bg
		btn.pressed.connect(_set_tool.bind(def[0]))
		_tool_btns[def[0]] = btn
		tb.add_child(btn)

	tb.add_child(VSeparator.new())
	var l_lbl := Label.new(); l_lbl.text = " Layer:"
	tb.add_child(l_lbl)

	var layer_bg := ButtonGroup.new()
	for i in 3:
		var lb := Button.new()
		lb.text         = "L%d" % (i + 1)
		lb.toggle_mode  = true
		lb.button_group = layer_bg
		lb.button_pressed = (i == _active_layer)
		lb.pressed.connect(_set_layer.bind(i))
		_layer_btns.append(lb)
		tb.add_child(lb)

	tb.add_child(VSeparator.new())

	var grid_btn := Button.new(); grid_btn.text = "Grid"; grid_btn.toggle_mode = true; grid_btn.button_pressed = _show_grid
	grid_btn.toggled.connect(func(v): _show_grid = v; _canvas.queue_redraw())
	tb.add_child(grid_btn)

	var blk_btn := Button.new(); blk_btn.text = "Blkd"; blk_btn.toggle_mode = true; blk_btn.button_pressed = _show_blocked
	blk_btn.toggled.connect(func(v): _show_blocked = v; _canvas.queue_redraw())
	tb.add_child(blk_btn)

	var exit_btn := Button.new(); exit_btn.text = "Exits"; exit_btn.toggle_mode = true; exit_btn.button_pressed = _show_exits
	exit_btn.toggled.connect(func(v): _show_exits = v; _canvas.queue_redraw())
	tb.add_child(exit_btn)

	tb.add_child(VSeparator.new())
	_zoom_label = Label.new(); _zoom_label.text = "%d%%" % int(_zoom * 100); _zoom_label.custom_minimum_size.x = 50
	tb.add_child(_zoom_label)

	_set_tool(Tool.PAINT)
	return tb


func _build_left_panel() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size.x = 185

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pc.add_child(scroll)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)

	# Selected GRH preview
	_make_section_label(vb, "Selected Sprite")
	_sel_preview = TextureRect.new()
	_sel_preview.custom_minimum_size = Vector2(80, 80)
	_sel_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sel_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sel_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vb.add_child(_sel_preview)
	_sel_grh_label = Label.new(); _sel_grh_label.text = "GRH #0"
	vb.add_child(_sel_grh_label)

	vb.add_child(HSeparator.new())

	# NPC/Object
	_make_section_label(vb, "NPC Placement")
	var npc_search := LineEdit.new()
	npc_search.placeholder_text = "Search NPC..."
	npc_search.custom_minimum_size = Vector2(140, 0)
	vb.add_child(npc_search)
	var npc_list := ItemList.new()
	npc_list.custom_minimum_size = Vector2(140, 130)
	npc_list.auto_height = false
	vb.add_child(npc_list)
	_npc_sel_label = Label.new()
	_npc_sel_label.text = "None selected"
	_npc_sel_label.add_theme_font_size_override("font_size", 9)
	_npc_sel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_npc_sel_label)
	var del_btn := Button.new()
	del_btn.text = "Delete Spawn NPC"
	del_btn.pressed.connect(func():
		_on_npc_tool_right_click(_hovered_tile))
	vb.add_child(del_btn)

	# Populate NPC list
	var _all_npc_entries: Array = []
	for idx_str in GameData.npcs:
		var nd: Dictionary = GameData.npcs[idx_str]
		_all_npc_entries.append({"idx": int(idx_str), "name": nd.get("name", idx_str)})
	_all_npc_entries.sort_custom(func(a, b): return a["name"] < b["name"])

	var _rebuild_npc_list := func(filter: String) -> void:
		npc_list.clear()
		for e in _all_npc_entries:
			if filter.is_empty() or (e["name"] as String).to_lower().contains(filter.to_lower()):
				npc_list.add_item("%s [%d]" % [e["name"], e["idx"]])
				npc_list.set_item_metadata(npc_list.item_count - 1, e["idx"])

	_rebuild_npc_list.call("")
	npc_search.text_changed.connect(func(t): _rebuild_npc_list.call(t))
	npc_list.item_selected.connect(func(i: int):
		_selected_npc = npc_list.get_item_metadata(i)
		_npc_sel_label.text = npc_list.get_item_text(i)
		_npc_spin.value = _selected_npc)

	var npc_row := HBoxContainer.new()
	npc_row.add_child(_make_label("NPC #:"))
	_npc_spin = _make_spinbox(0, 550, 1)
	_npc_spin.value_changed.connect(func(v): _selected_npc = int(v))
	npc_row.add_child(_npc_spin)
	vb.add_child(npc_row)

	_make_section_label(vb, "Object Placement")
	var obj_row := HBoxContainer.new()
	obj_row.add_child(_make_label("Obj #:"))
	_obj_spin = _make_spinbox(0, 305, 1)
	_obj_spin.value_changed.connect(func(v): _selected_obj = int(v))
	obj_row.add_child(_obj_spin)
	vb.add_child(obj_row)

	var amt_row := HBoxContainer.new()
	amt_row.add_child(_make_label("Amt:"))
	_obj_amount_spin = _make_spinbox(1, 9999, 1)
	amt_row.add_child(_obj_amount_spin)
	vb.add_child(amt_row)

	vb.add_child(HSeparator.new())

	# Mini-map
	_make_section_label(vb, "Mini-map")
	var mm_panel := Panel.new()
	mm_panel.custom_minimum_size = Vector2(100, 100)
	vb.add_child(mm_panel)
	_minimap_rect = TextureRect.new()
	_minimap_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_minimap_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_minimap_rect.stretch_mode = TextureRect.STRETCH_SCALE
	mm_panel.add_child(_minimap_rect)

	return pc


func _build_center_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)

	# SubViewport for the map canvas
	_viewport_container = SubViewportContainer.new()
	_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport_container.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport_container.gui_input.connect(_on_viewport_gui_input)
	col.add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.handle_input_locally = false
	_viewport.transparent_bg = false
	_viewport_container.add_child(_viewport)

	_canvas = Node2D.new()
	_canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_canvas.draw.connect(_on_canvas_draw)
	_viewport.add_child(_canvas)

	# Bottom tab container
	_tab_container = _build_bottom_tabs()
	_tab_container.custom_minimum_size.y = 165
	col.add_child(_tab_container)

	return col


func _build_bottom_tabs() -> TabContainer:
	var tc := TabContainer.new()

	# ── Tab 1: Map Properties ───────────────────────────────────────────────
	var map_tab := VBoxContainer.new()
	map_tab.name = "Map Properties"
	map_tab.add_theme_constant_override("separation", 4)
	tc.add_child(map_tab)

	var grid := GridContainer.new(); grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	map_tab.add_child(grid)

	grid.add_child(_make_label("Name:")); _map_name_field = LineEdit.new(); _map_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL; grid.add_child(_map_name_field)
	_map_name_field.text_changed.connect(func(t): _map_meta["name"] = t; _map_dirty = true; _update_title())

	grid.add_child(_make_label("Music:")); _map_music_field = LineEdit.new(); _map_music_field.custom_minimum_size.x = 60; grid.add_child(_map_music_field)
	_map_music_field.text_changed.connect(func(t): _map_meta["music"] = t; _map_dirty = true)

	grid.add_child(_make_label("PK Free:")); _map_pk_check = CheckBox.new(); grid.add_child(_map_pk_check)
	_map_pk_check.toggled.connect(func(v): _map_meta["pk_free"] = v; _map_dirty = true)

	grid.add_child(_make_label("Start X:")); _map_start_x = _make_spinbox(1, 100, 1); grid.add_child(_map_start_x)
	_map_start_x.value_changed.connect(func(v): _map_meta.get_or_add("start_pos", {})["x"] = int(v); _map_dirty = true)

	grid.add_child(_make_label("Start Y:")); _map_start_y = _make_spinbox(1, 100, 1); grid.add_child(_map_start_y)
	_map_start_y.value_changed.connect(func(v): _map_meta.get_or_add("start_pos", {})["y"] = int(v); _map_dirty = true)

	for dir in ["north", "south", "west", "east"]:
		var sp := _make_spinbox(0, 999, 1)
		_exit_spins[dir] = sp
		grid.add_child(_make_label(dir.capitalize() + " Exit:"))
		grid.add_child(sp)
		sp.value_changed.connect(func(v, d=dir): _map_meta[d + "_exit"] = int(v); _map_dirty = true)

	# ── Tab 2: Tile Properties ──────────────────────────────────────────────
	var tile_tab := VBoxContainer.new()
	tile_tab.name = "Tile Properties"
	tile_tab.add_theme_constant_override("separation", 4)
	tc.add_child(tile_tab)

	var tgrid := GridContainer.new(); tgrid.columns = 4
	tgrid.add_theme_constant_override("h_separation", 6)
	tgrid.add_theme_constant_override("v_separation", 4)
	tile_tab.add_child(tgrid)

	tgrid.add_child(_make_label("Tile:"))
	_tile_coord_label = Label.new(); _tile_coord_label.text = "(1,1)"; tgrid.add_child(_tile_coord_label)
	tgrid.add_child(_make_label("Blocked:"))
	_tile_blocked_check = CheckBox.new(); tgrid.add_child(_tile_blocked_check)

	tgrid.add_child(_make_label("NPC #:"));    _tile_npc_spin = _make_spinbox(0, 550, 1);   tgrid.add_child(_tile_npc_spin)
	tgrid.add_child(_make_label("Obj #:"));    _tile_obj_idx_spin = _make_spinbox(0, 305, 1); tgrid.add_child(_tile_obj_idx_spin)
	tgrid.add_child(_make_label("Obj Amt:")); _tile_obj_amt_spin = _make_spinbox(1, 9999, 1); tgrid.add_child(_tile_obj_amt_spin)
	tgrid.add_child(_make_label("Exit Map:")); _tile_exit_map_spin = _make_spinbox(0, 999, 1); tgrid.add_child(_tile_exit_map_spin)
	tgrid.add_child(_make_label("Exit X:"));  _tile_exit_x_spin = _make_spinbox(1, 100, 1);   tgrid.add_child(_tile_exit_x_spin)
	tgrid.add_child(_make_label("Exit Y:"));  _tile_exit_y_spin = _make_spinbox(1, 100, 1);   tgrid.add_child(_tile_exit_y_spin)

	var apply_btn := Button.new(); apply_btn.text = "Apply to Hovered Tile"
	apply_btn.pressed.connect(func(): _apply_tile_props(_hovered_tile))
	tile_tab.add_child(apply_btn)

	return tc


func _build_right_panel() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size.x = 270
	_grh_browser = GrhBrowserClass.new()
	_grh_browser.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_grh_browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grh_browser.grh_selected.connect(_on_grh_selected)
	pc.add_child(_grh_browser)
	return pc


func _build_status_bar() -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.custom_minimum_size.y = 22
	hb.add_theme_constant_override("separation", 8)

	_status_label = Label.new()
	_status_label.text = "Ready."
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(_status_label)

	_coord_label = Label.new()
	_coord_label.text = "(1, 1)"
	_coord_label.custom_minimum_size.x = 360
	_coord_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(_coord_label)

	return hb


# ── Menu handlers ─────────────────────────────────────────────────────────────

func _on_menu_file(id: int) -> void:
	match id:
		0: _new_map()
		1: _open_map_dialog()
		2: _save_map()
		3: _save_map_as_dialog()
		4: get_tree().quit()


func _on_menu_edit(id: int) -> void:
	match id:
		0: _undo_redo.undo(); _canvas.queue_redraw()
		1: _undo_redo.redo(); _canvas.queue_redraw()
		2:  # Clear active layer
			var changes: Array = []
			for key in _tiles:
				var t: Dictionary = _tiles[key]
				var layers: Array = t.get("layers", [0,0,0])
				if _active_layer < layers.size() and layers[_active_layer] != 0:
					var before: Dictionary = t.duplicate(true)
					var after: Dictionary  = t.duplicate(true)
					var al: Array = after["layers"].duplicate()
					al[_active_layer] = 0
					after["layers"] = al
					changes.append({"key": key, "before": before, "after": after})
			if changes.size() > 0:
				_undo_redo.create_action("Clear Layer %d" % (_active_layer + 1))
				_undo_redo.add_do_method(_apply_tile_changes.bind(changes, true))
				_undo_redo.add_undo_method(_apply_tile_changes.bind(changes, false))
				_undo_redo.commit_action()


func _on_menu_view(id: int, menu: PopupMenu) -> void:
	match id:
		0: _show_grid    = not _show_grid;    menu.set_item_checked(0, _show_grid)
		1: _show_blocked = not _show_blocked; menu.set_item_checked(1, _show_blocked)
		2: _show_exits   = not _show_exits;   menu.set_item_checked(2, _show_exits)
		3: _show_npcs    = not _show_npcs;    menu.set_item_checked(3, _show_npcs)
		4: _apply_zoom(1.2,  Vector2(_viewport.size) * 0.5)
		5: _apply_zoom(1.0 / 1.2, Vector2(_viewport.size) * 0.5)
		6: _zoom = 1.5;   _canvas.queue_redraw(); _zoom_label.text = "150%"
	_canvas.queue_redraw()


func _on_menu_map(id: int) -> void:
	match id:
		0: _open_map_dialog()
		1: _validate_exits()
		2: _place_rain()
		3: _clear_rain()


## Fill layer 3 with GRH 3501 (rain) in the VB6 PlaceRain() pattern:
## every 4 columns (x=1,5,9,...,97) × every 5 rows (y=1,6,11,...,96).
func _place_rain() -> void:
	const RAIN_GRH := 3501
	var changes: Array = []
	var y := 1
	while y <= MAP_H:
		var x := 1
		while x <= MAP_W:
			var key := _tile_key(x, y)
			var before: Dictionary = _tiles.get(key, {}).duplicate(true)
			var after: Dictionary  = before.duplicate(true)
			var layers: Array = after.get("layers", [0, 0, 0]).duplicate()
			while layers.size() < 3: layers.append(0)
			layers[2] = RAIN_GRH
			after["layers"] = layers
			changes.append({"key": key, "before": before, "after": after})
			x += 4
		y += 5
	_undo_redo.create_action("Place Rain")
	_undo_redo.add_do_method(_apply_tile_changes.bind(changes, true))
	_undo_redo.add_undo_method(_apply_tile_changes.bind(changes, false))
	_undo_redo.commit_action()
	_status_label.text = "Rain placed on layer 3 (%d tiles)" % changes.size()


## Remove GRH 3501 from all layer 3 tiles.
func _clear_rain() -> void:
	var changes: Array = []
	for key in _tiles:
		var t: Dictionary = _tiles[key]
		var layers: Array = t.get("layers", [])
		if layers.size() > 2 and layers[2] == 3501:
			var before: Dictionary = t.duplicate(true)
			var after: Dictionary  = before.duplicate(true)
			after["layers"] = after["layers"].duplicate()
			after["layers"][2] = 0
			changes.append({"key": key, "before": before, "after": after})
	if changes.is_empty():
		_status_label.text = "No rain tiles found on layer 3."
		return
	_undo_redo.create_action("Clear Rain")
	_undo_redo.add_do_method(_apply_tile_changes.bind(changes, true))
	_undo_redo.add_undo_method(_apply_tile_changes.bind(changes, false))
	_undo_redo.commit_action()
	_status_label.text = "Rain cleared from layer 3 (%d tiles)" % changes.size()


func _validate_exits() -> void:
	var issues: Array[String] = []
	for dir in ["north", "south", "west", "east"]:
		var dest: int = _map_meta.get(dir + "_exit", 0)
		if dest > 1:
			var dm := GameData.get_map(dest)
			if dm.is_empty():
				issues.append("%s exit → Map %d (NOT FOUND)" % [dir.capitalize(), dest])
	var msg := "No exit issues found." if issues.is_empty() else "\n".join(issues)
	_status_label.text = "Validate: " + msg


# ── Small UI helpers ──────────────────────────────────────────────────────────

func _make_label(text: String) -> Label:
	var l := Label.new(); l.text = text; return l


func _make_section_label(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	parent.add_child(l)


func _make_spinbox(min_v: float, max_v: float, step: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = min_v; sb.max_value = max_v; sb.step = step
	sb.custom_minimum_size.x = 70
	return sb


func _shortcut(keycode: Key, ctrl: bool = false) -> Shortcut:
	var sc := Shortcut.new()
	var ie := InputEventKey.new()
	ie.keycode       = keycode
	ie.ctrl_pressed  = ctrl
	sc.events        = [ie]
	return sc
