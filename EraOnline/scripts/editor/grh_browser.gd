class_name GrhBrowser
extends PanelContainer
## Era Online Map Editor — GRH Browser
## Paginated sprite browser. Emits grh_selected(grh_index) when user picks a tile.

signal grh_selected(grh_index: int)

const THUMB_SIZE  := 52   # px per cell (includes padding)
const THUMB_PAD   := 4
const COLS        := 4
const PAGE_SIZE   := COLS * 10  # 40 thumbnails per page

var _tex_cache: RefCounted  # TextureCache

var _all_indices:      Array[int] = []
var _filtered_indices: Array[int] = []
var _current_page:     int = 0
var _total_pages:      int = 0
var _selected_grh:     int = 0
var _search_text:      String = ""
var _filter_type:      int = 0   # 0=All 1=Static 2=Animated

# UI refs
var _search_field:   LineEdit
var _filter_option:  OptionButton
var _page_label:     Label
var _prev_btn:       Button
var _next_btn:       Button
var _grid:           GridContainer
var _thumb_panels:   Array[Panel] = []
var _large_preview:  TextureRect
var _sel_label:      Label

# Which GRH index is assigned to each visible thumb slot (-1 = empty)
var _slot_grh: Array[int] = []


func _ready() -> void:
	const TCClass = preload("res://scripts/game/texture_cache.gd")
	_tex_cache = TCClass.new()
	_build_ui()
	_rebuild_filtered_list()
	_refresh_page()


func _build_ui() -> void:
	custom_minimum_size = Vector2(270, 400)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	add_child(root)

	# ── Search + filter row ────────────────────────────────────────────────
	var search_row := HBoxContainer.new()
	root.add_child(search_row)

	_search_field = LineEdit.new()
	_search_field.placeholder_text = "GRH # or file#"
	_search_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_field.text_changed.connect(_on_search_changed)
	search_row.add_child(_search_field)

	_filter_option = OptionButton.new()
	_filter_option.add_item("All")
	_filter_option.add_item("Static")
	_filter_option.add_item("Animated")
	_filter_option.item_selected.connect(_on_filter_changed)
	search_row.add_child(_filter_option)

	# ── Thumbnail grid ────────────────────────────────────────────────────
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	# Pre-create reusable thumb panels
	_slot_grh.resize(PAGE_SIZE)
	_slot_grh.fill(-1)

	for i in PAGE_SIZE:
		var panel := Panel.new()
		panel.custom_minimum_size = Vector2(THUMB_SIZE, THUMB_SIZE)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		# Store slot index so draw callback can look up which GRH to show
		panel.set_meta("slot", i)
		panel.draw.connect(_on_thumb_draw.bind(panel))
		panel.gui_input.connect(_on_thumb_input.bind(i))
		_thumb_panels.append(panel)
		_grid.add_child(panel)

	# ── Pagination bar ───────────────────────────────────────────────────
	var page_row := HBoxContainer.new()
	root.add_child(page_row)

	_prev_btn = Button.new()
	_prev_btn.text = "◀"
	_prev_btn.pressed.connect(_on_prev_page)
	page_row.add_child(_prev_btn)

	_page_label = Label.new()
	_page_label.text = "0 / 0"
	_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_row.add_child(_page_label)

	_next_btn = Button.new()
	_next_btn.text = "▶"
	_next_btn.pressed.connect(_on_next_page)
	page_row.add_child(_next_btn)

	# ── Large preview + info ─────────────────────────────────────────────
	root.add_child(HSeparator.new())

	var preview_row := HBoxContainer.new()
	root.add_child(preview_row)

	_large_preview = TextureRect.new()
	_large_preview.custom_minimum_size = Vector2(80, 80)
	_large_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_large_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_large_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_row.add_child(_large_preview)

	_sel_label = Label.new()
	_sel_label.text = "No selection"
	_sel_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_row.add_child(_sel_label)


# ── Public API ──────────────────────────────────────────────────────────────

func highlight_grh(grh_index: int) -> void:
	_selected_grh = grh_index
	_update_large_preview()
	# Navigate to the page that contains this grh
	var pos := _filtered_indices.find(grh_index)
	if pos >= 0:
		var target_page := pos / PAGE_SIZE
		if target_page != _current_page:
			_current_page = target_page
			_refresh_page()
		else:
			for panel in _thumb_panels:
				panel.queue_redraw()


func get_selected_grh() -> int:
	return _selected_grh


# ── Internal ────────────────────────────────────────────────────────────────

func _rebuild_filtered_list() -> void:
	_filtered_indices.clear()
	var search_num := int(_search_text) if _search_text.is_valid_int() else -1

	for key in GameData.grh_data:
		var idx := int(key)
		if idx <= 0:
			continue
		var entry: Dictionary = GameData.grh_data[key]
		var animated: bool = entry.get("num_frames", 1) > 1

		if _filter_type == 1 and animated:
			continue
		if _filter_type == 2 and not animated:
			continue
		if _search_text != "":
			if search_num >= 0:
				if idx != search_num:
					# Also allow file_num match
					if entry.get("file_num", 0) != search_num:
						continue
			else:
				continue

		_filtered_indices.append(idx)

	_filtered_indices.sort()
	_total_pages = max(1, ceili(float(_filtered_indices.size()) / float(PAGE_SIZE)))
	_current_page = clampi(_current_page, 0, _total_pages - 1)


func _refresh_page() -> void:
	var start := _current_page * PAGE_SIZE
	_page_label.text = "%d / %d  (%d GRHs)" % [_current_page + 1, _total_pages, _filtered_indices.size()]
	_prev_btn.disabled = (_current_page == 0)
	_next_btn.disabled = (_current_page >= _total_pages - 1)

	for i in PAGE_SIZE:
		var idx := start + i
		_slot_grh[i] = _filtered_indices[idx] if idx < _filtered_indices.size() else -1
		_thumb_panels[i].visible = (_slot_grh[i] >= 0)
		_thumb_panels[i].queue_redraw()


func _on_thumb_draw(panel: Panel) -> void:
	var slot: int = panel.get_meta("slot", -1)
	if slot < 0 or slot >= _slot_grh.size():
		return
	var grh_index: int = _slot_grh[slot]
	if grh_index < 0:
		return

	var selected := (grh_index == _selected_grh)

	# Background
	var bg_col := Color(0.25, 0.25, 0.25) if not selected else Color(0.2, 0.45, 0.75)
	panel.draw_rect(Rect2(0, 0, THUMB_SIZE, THUMB_SIZE), bg_col)

	# Draw the GRH sprite
	var fd := GameData.get_grh_frame(grh_index, 0)
	if not fd.is_empty():
		var tex: Texture2D = _tex_cache.get_texture(fd.get("file_num", 0))
		if tex != null:
			var src := Rect2(fd.get("sx", 0), fd.get("sy", 0),
							 fd.get("pixel_width", 32), fd.get("pixel_height", 32))
			var avail := float(THUMB_SIZE - THUMB_PAD * 2)
			var scale := minf(avail / maxf(src.size.x, 1.0), avail / maxf(src.size.y, 1.0))
			var dw := src.size.x * scale
			var dh := src.size.y * scale
			var dx := (THUMB_SIZE - dw) * 0.5
			var dy := (THUMB_SIZE - dh) * 0.5
			panel.draw_texture_rect_region(tex, Rect2(dx, dy, dw, dh), src)

	# Index label
	var font := ThemeDB.fallback_font
	panel.draw_string(font, Vector2(2, THUMB_SIZE - 3),
			str(grh_index), HORIZONTAL_ALIGNMENT_LEFT, -1, 8,
			Color(1, 1, 1, 0.85) if not selected else Color(1, 1, 0.3))

	# Selection border
	if selected:
		panel.draw_rect(Rect2(0, 0, THUMB_SIZE, THUMB_SIZE), Color(0.4, 0.8, 1.0), false, 2.0)


func _on_thumb_input(event: InputEvent, slot: int) -> void:
	if slot < 0 or slot >= _slot_grh.size():
		return
	var grh_index: int = _slot_grh[slot]
	if grh_index < 0:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_selected_grh = grh_index
			_update_large_preview()
			grh_selected.emit(grh_index)
			for panel in _thumb_panels:
				panel.queue_redraw()


func _update_large_preview() -> void:
	if _selected_grh <= 0:
		_large_preview.texture = null
		_sel_label.text = "No selection"
		return

	var fd := GameData.get_grh_frame(_selected_grh, 0)
	if fd.is_empty():
		_sel_label.text = "GRH #%d (no frame data)" % _selected_grh
		return

	var tex: Texture2D = _tex_cache.get_texture(fd.get("file_num", 0))
	if tex != null:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(fd.get("sx", 0), fd.get("sy", 0),
						  fd.get("pixel_width", 32), fd.get("pixel_height", 32))
		_large_preview.texture = at

	var entry := GameData.get_grh(_selected_grh)
	var animated: bool = entry.get("num_frames", 1) > 1
	_sel_label.text = "GRH #%d\nFile: %d  Sz: %dx%d\n%s" % [
		_selected_grh,
		fd.get("file_num", 0),
		fd.get("pixel_width", 32), fd.get("pixel_height", 32),
		"Animated (%d frames)" % entry.get("num_frames", 1) if animated else "Static"
	]


func _on_search_changed(text: String) -> void:
	_search_text = text.strip_edges()
	_current_page = 0
	_rebuild_filtered_list()
	_refresh_page()


func _on_filter_changed(idx: int) -> void:
	_filter_type = idx
	_current_page = 0
	_rebuild_filtered_list()
	_refresh_page()


func _on_prev_page() -> void:
	if _current_page > 0:
		_current_page -= 1
		_refresh_page()


func _on_next_page() -> void:
	if _current_page < _total_pages - 1:
		_current_page += 1
		_refresh_page()
