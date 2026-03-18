class_name CharSelectUI
extends CanvasLayer
## Era Online - Character Select / Create screen.
## Call populate(chars) with the server's char list to activate.
## Emits no signals; hands off by calling Network.select_char / create_char.
## Main scene loads World.tscn in response to Network.on_world_state.

const C_BG       := Color(0.04, 0.03, 0.02, 1.0)
const C_PANEL    := Color(0.08, 0.06, 0.03, 0.96)
const C_BORDER   := Color(0.40, 0.30, 0.12, 1.0)
const C_GOLD     := Color(0.85, 0.65, 0.15, 1.0)
const C_TEXT     := Color(0.90, 0.85, 0.72, 1.0)
const C_DIM      := Color(0.55, 0.50, 0.38, 1.0)
const C_BTN      := Color(0.14, 0.10, 0.04, 1.0)
const C_BTN_HV   := Color(0.22, 0.16, 0.06, 1.0)
const C_RED      := Color(0.75, 0.15, 0.10, 1.0)
const C_GREEN    := Color(0.18, 0.36, 0.12, 1.0)
const C_GREEN_HV := Color(0.25, 0.50, 0.16, 1.0)
const C_SLOT     := Color(0.06, 0.05, 0.02, 0.98)
const C_SLOT_SEL := Color(0.14, 0.11, 0.04, 1.0)

const MAX_CHARS   := 3
const CLASS_NAMES := ["Warrior", "Mage", "Rogue", "Archer"]
const CLASS_STATS := [
	"HP: 150  MP: 30\nSTR: 18  AGI: 10",
	"HP: 80   MP: 120\nINT: 18  AGI: 10",
	"HP: 100  MP: 60\nSTR: 14  AGI: 18",
	"HP: 100  MP: 80\nSTR: 12  AGI: 16",
]
## Body index per class (matches ServerCombat.base_stats)
const CLASS_BODY  := [1, 2, 3, 4]

var _chars: Array = []          # char dicts from server (up to 3)
var _selected_slot: int = -1    # which slot card is currently selected

var _create_class: int = 0
var _create_head:  int = 1
var _create_body:  int = 1
var _head_keys:    Array = []   # sorted available head indices
var _body_keys:    Array = []   # sorted available body indices (with valid GRH)

var _tex_cache: TextureCache = null

# --- UI node refs ---
var _slot_cards:        Array = []   # Array[Panel] x MAX_CHARS
var _slot_previews:     Array = []   # Array[_CharPreview] x MAX_CHARS
var _slot_name_lbls:    Array = []
var _slot_info_lbls:    Array = []
var _slot_delete_btns:  Array = []   # Array[Button] x MAX_CHARS
var _enter_btn:         Button  = null
var _new_btn:           Button  = null
var _status_lbl:        Label   = null
var _pending_delete_name: String = ""

# Creation overlay
var _create_panel:     Control  = null
var _name_field:       LineEdit = null
var _class_btns:       Array    = []
var _class_stat_lbl:   Label    = null
var _create_preview:   Control  = null
var _head_lbl:         Label    = null
var _body_lbl:         Label    = null
var _create_status:    Label    = null
var _create_submit:    Button   = null


# ---------------------------------------------------------------------------
# Inner class: sprite preview rendered inside a Control using _draw()
# ---------------------------------------------------------------------------

class _CharPreview:
	extends Control

	var body_idx: int = 1
	var head_idx: int = 1
	var _tc: TextureCache = null

	func setup(body: int, head: int, tc: TextureCache) -> void:
		body_idx = body
		head_idx = head
		_tc = tc
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		queue_redraw()

	func update_body(b: int) -> void:
		body_idx = b
		queue_redraw()

	func update_head(h: int) -> void:
		head_idx = h
		queue_redraw()

	func _draw() -> void:
		if _tc == null or not GameData.is_loaded:
			return
		# Anchor: matches VB6 tile bottom anchor.
		# ay = size.y - 32 so that body bottom (ay+32) aligns to control bottom.
		var ax := int(size.x / 2) - 16
		var ay := int(size.y) - 32
		var dir := 2  # South-facing (index 2 = heading 3 in VB6)

		# Draw body (first frame of south walk animation)
		var body_grh := GameData.get_body_walk_grh(body_idx, dir)
		_blit(body_grh, ax, ay)

		# Draw head (with body head-offset)
		var body_data := GameData.get_body(body_idx)
		var hox: int = body_data.get("head_offset_x", 0)
		var hoy: int = body_data.get("head_offset_y", 0)
		var head_grh := GameData.get_head_grh(head_idx, dir)
		_blit(head_grh, ax + hox, ay + hoy)

	func _blit(grh_idx: int, wx: int, wy: int) -> void:
		if grh_idx <= 0 or _tc == null:
			return
		var fd := GameData.get_grh_frame(grh_idx, 0)
		if fd.is_empty():
			return
		var file_num: int = fd.get("file_num", 0)
		if file_num <= 0:
			return
		var tex := _tc.get_texture(file_num)
		if tex == null:
			return
		var sx: int = fd.get("sx", 0)
		var sy: int = fd.get("sy", 0)
		var pw: int = fd.get("pixel_width",  32)
		var ph: int = fd.get("pixel_height", 32)
		# VB6 centering formula (same as WorldMap._blit)
		var dx := wx - pw / 2 + 16
		var dy := wy - ph + 32
		draw_texture_rect_region(tex,
			Rect2(float(dx), float(dy), float(pw), float(ph)),
			Rect2(float(sx), float(sy), float(pw), float(ph)))


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 5
	_tex_cache = TextureCache.new()
	_collect_head_keys()
	_collect_body_keys()
	_build_ui()
	Network.char_created.connect(_on_char_created)
	Network.char_deleted.connect(_on_char_deleted)


func _collect_head_keys() -> void:
	_head_keys = []
	for k in GameData.heads.keys():
		_head_keys.append(int(k))
	_head_keys.sort()
	if _head_keys.is_empty():
		_head_keys = [1]
	_create_head = _head_keys[0]


func _collect_body_keys() -> void:
	_body_keys = []
	for k in GameData.bodies.keys():
		var body_idx := int(k)
		# Only include bodies that have a valid south-facing walk GRH
		var south_grh := GameData.get_body_walk_grh(body_idx, 2)
		if south_grh > 0:
			_body_keys.append(body_idx)
	_body_keys.sort()
	if _body_keys.is_empty():
		_body_keys = [1]
	_create_body = _body_keys[0]


# ---------------------------------------------------------------------------
# Public API — called by main.gd
# ---------------------------------------------------------------------------

## Populate with the server's character list and become visible.
func populate(chars: Array) -> void:
	_chars = chars.duplicate()
	_refresh_slots()
	visible = true


# ---------------------------------------------------------------------------
# UI Construction
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var vp := Vector2(1280, 720)

	var bg := ColorRect.new()
	bg.color = C_BG
	bg.size  = vp
	add_child(bg)

	var panel := Panel.new()
	panel.size     = Vector2(860, 540)
	panel.position = Vector2((vp.x - 860) / 2.0, (vp.y - 540) / 2.0)
	panel.add_theme_stylebox_override("panel", _box(C_PANEL, C_BORDER, 2))
	add_child(panel)

	# Title
	var title := Label.new()
	title.text = "Select Character"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", C_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(840, 40); title.position = Vector2(10, 12)
	panel.add_child(title)

	var div := ColorRect.new()
	div.color = C_BORDER; div.size = Vector2(820, 1); div.position = Vector2(20, 58)
	panel.add_child(div)

	# Slot cards — 3 x 240×320, evenly spaced
	for i in MAX_CHARS:
		var cx := 30 + i * (240 + 30)
		var card := _build_slot_card(panel, cx, 68)
		_slot_cards.append(card)
		var idx := i  # capture
		card.gui_input.connect(func(ev): _on_slot_input(ev, idx))

	# Bottom status
	_status_lbl = Label.new()
	_status_lbl.add_theme_font_size_override("font_size", 12)
	_status_lbl.add_theme_color_override("font_color", C_DIM)
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.size = Vector2(840, 20); _status_lbl.position = Vector2(10, 412)
	panel.add_child(_status_lbl)

	# Bottom buttons
	_enter_btn = _make_button("Enter World", C_GREEN, C_GREEN_HV)
	_enter_btn.size = Vector2(380, 48); _enter_btn.position = Vector2(30, 440)
	_enter_btn.disabled = true
	_enter_btn.pressed.connect(_on_enter_pressed)
	panel.add_child(_enter_btn)

	_new_btn = _make_button("New Character", C_BTN, C_BTN_HV)
	_new_btn.size = Vector2(380, 48); _new_btn.position = Vector2(450, 440)
	_new_btn.pressed.connect(_on_new_char_pressed)
	panel.add_child(_new_btn)

	# Creation overlay (hidden until needed)
	_create_panel = _build_create_panel(panel)
	_create_panel.visible = false


func _build_slot_card(parent: Control, cx: int, cy: int) -> Panel:
	var card := Panel.new()
	card.size = Vector2(240, 330)
	card.position = Vector2(cx, cy)
	card.add_theme_stylebox_override("panel", _box(C_SLOT, C_BORDER, 1))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(card)

	# Character preview (will be populated by _refresh_slots)
	var prev := _CharPreview.new()
	prev.size = Vector2(140, 160)
	prev.position = Vector2(50, 12)
	card.add_child(prev)
	_slot_previews.append(prev)

	var name_lbl := Label.new()
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", C_DIM)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size = Vector2(220, 26); name_lbl.position = Vector2(10, 180)
	card.add_child(name_lbl)
	_slot_name_lbls.append(name_lbl)

	var info_lbl := Label.new()
	info_lbl.add_theme_font_size_override("font_size", 12)
	info_lbl.add_theme_color_override("font_color", C_DIM)
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.size = Vector2(220, 22); info_lbl.position = Vector2(10, 208)
	card.add_child(info_lbl)
	_slot_info_lbls.append(info_lbl)

	# Delete button — visible only when slot has a character
	var del_btn := _make_button("Delete", C_RED, Color(C_RED.r + 0.1, C_RED.g, C_RED.b, 1.0))
	del_btn.size     = Vector2(220, 32)
	del_btn.position = Vector2(10, 290)
	del_btn.visible  = false
	var slot_index := _slot_delete_btns.size()  # capture before append
	del_btn.pressed.connect(func(): _on_delete_pressed(slot_index))
	card.add_child(del_btn)
	_slot_delete_btns.append(del_btn)

	return card


func _build_create_panel(parent: Control) -> Control:
	var p := Panel.new()
	p.size = Vector2(640, 470)
	p.position = Vector2((860 - 640) / 2, (540 - 470) / 2)
	p.add_theme_stylebox_override("panel", _box(Color(0.05, 0.04, 0.01, 0.99), C_GOLD, 1))
	parent.add_child(p)

	var title := Label.new()
	title.text = "Create Character"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", C_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(620, 32); title.position = Vector2(10, 10)
	p.add_child(title)

	# Name field
	var n_lbl := Label.new()
	n_lbl.text = "Character Name"
	n_lbl.add_theme_font_size_override("font_size", 13)
	n_lbl.add_theme_color_override("font_color", C_TEXT)
	n_lbl.size = Vector2(620, 20); n_lbl.position = Vector2(10, 52)
	p.add_child(n_lbl)

	_name_field = LineEdit.new()
	_name_field.size = Vector2(400, 34); _name_field.position = Vector2(10, 74)
	_name_field.placeholder_text = "Enter name (3-16 chars)"
	p.add_child(_name_field)

	# Class buttons row
	var cl_lbl := Label.new()
	cl_lbl.text = "Class"
	cl_lbl.add_theme_font_size_override("font_size", 13)
	cl_lbl.add_theme_color_override("font_color", C_TEXT)
	cl_lbl.size = Vector2(620, 20); cl_lbl.position = Vector2(10, 120)
	p.add_child(cl_lbl)

	for i in CLASS_NAMES.size():
		var cbtn := _make_button(CLASS_NAMES[i], C_BTN, C_BTN_HV)
		cbtn.size = Vector2(140, 38); cbtn.position = Vector2(10 + i * 150, 142)
		var ci := i
		cbtn.pressed.connect(func(): _select_class(ci))
		p.add_child(cbtn)
		_class_btns.append(cbtn)

	# Class stat preview
	_class_stat_lbl = Label.new()
	_class_stat_lbl.add_theme_font_size_override("font_size", 12)
	_class_stat_lbl.add_theme_color_override("font_color", C_TEXT)
	_class_stat_lbl.size = Vector2(400, 40); _class_stat_lbl.position = Vector2(10, 188)
	p.add_child(_class_stat_lbl)

	# Appearance section label
	var app_lbl := Label.new()
	app_lbl.text = "Appearance"
	app_lbl.add_theme_font_size_override("font_size", 13)
	app_lbl.add_theme_color_override("font_color", C_TEXT)
	app_lbl.size = Vector2(620, 20); app_lbl.position = Vector2(10, 236)
	p.add_child(app_lbl)

	# Character preview — larger so head + body both fit
	_create_preview = _CharPreview.new()
	_create_preview.size = Vector2(130, 180)
	_create_preview.position = Vector2(10, 258)
	p.add_child(_create_preview)

	# --- Head picker (right of preview) ---
	var head_section_lbl := Label.new()
	head_section_lbl.text = "Head"
	head_section_lbl.add_theme_font_size_override("font_size", 12)
	head_section_lbl.add_theme_color_override("font_color", C_DIM)
	head_section_lbl.size = Vector2(200, 20); head_section_lbl.position = Vector2(155, 260)
	p.add_child(head_section_lbl)

	var prev_head := _make_button("<", C_BTN, C_BTN_HV)
	prev_head.size = Vector2(34, 32); prev_head.position = Vector2(155, 282)
	prev_head.pressed.connect(_head_prev)
	p.add_child(prev_head)

	_head_lbl = Label.new()
	_head_lbl.add_theme_font_size_override("font_size", 12)
	_head_lbl.add_theme_color_override("font_color", C_TEXT)
	_head_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_head_lbl.size = Vector2(160, 32); _head_lbl.position = Vector2(193, 282)
	p.add_child(_head_lbl)

	var next_head := _make_button(">", C_BTN, C_BTN_HV)
	next_head.size = Vector2(34, 32); next_head.position = Vector2(357, 282)
	next_head.pressed.connect(_head_next)
	p.add_child(next_head)

	# --- Body picker (right of preview, below head) ---
	var body_section_lbl := Label.new()
	body_section_lbl.text = "Shirt / Pants"
	body_section_lbl.add_theme_font_size_override("font_size", 12)
	body_section_lbl.add_theme_color_override("font_color", C_DIM)
	body_section_lbl.size = Vector2(200, 20); body_section_lbl.position = Vector2(155, 330)
	p.add_child(body_section_lbl)

	var prev_body := _make_button("<", C_BTN, C_BTN_HV)
	prev_body.size = Vector2(34, 32); prev_body.position = Vector2(155, 352)
	prev_body.pressed.connect(_body_prev)
	p.add_child(prev_body)

	_body_lbl = Label.new()
	_body_lbl.add_theme_font_size_override("font_size", 12)
	_body_lbl.add_theme_color_override("font_color", C_TEXT)
	_body_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_lbl.size = Vector2(160, 32); _body_lbl.position = Vector2(193, 352)
	p.add_child(_body_lbl)

	var next_body := _make_button(">", C_BTN, C_BTN_HV)
	next_body.size = Vector2(34, 32); next_body.position = Vector2(357, 352)
	next_body.pressed.connect(_body_next)
	p.add_child(next_body)

	# Status + buttons
	_create_status = Label.new()
	_create_status.add_theme_font_size_override("font_size", 12)
	_create_status.add_theme_color_override("font_color", C_DIM)
	_create_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_create_status.size = Vector2(620, 20); _create_status.position = Vector2(10, 422)
	p.add_child(_create_status)

	_create_submit = _make_button("Create", C_GREEN, C_GREEN_HV)
	_create_submit.size = Vector2(295, 40); _create_submit.position = Vector2(10, 422)
	_create_submit.pressed.connect(_on_create_pressed)
	p.add_child(_create_submit)

	var cancel_btn := _make_button("Cancel", C_BTN, C_BTN_HV)
	cancel_btn.size = Vector2(295, 40); cancel_btn.position = Vector2(335, 422)
	cancel_btn.pressed.connect(func(): _create_panel.visible = false)
	p.add_child(cancel_btn)

	_update_create_preview()
	return p


# ---------------------------------------------------------------------------
# Slot refresh
# ---------------------------------------------------------------------------

func _refresh_slots() -> void:
	for i in MAX_CHARS:
		var has_char := i < _chars.size()
		var card: Panel = _slot_cards[i]
		var prev: _CharPreview = _slot_previews[i]
		var name_lbl: Label = _slot_name_lbls[i]
		var info_lbl: Label = _slot_info_lbls[i]
		var del_btn: Button = _slot_delete_btns[i]

		if has_char:
			var cd: Dictionary = _chars[i]
			var body_idx: int = cd.get("body", 1)
			var head_idx: int = cd.get("head", 1)
			var level: int = cd.get("level", 1)
			var class_id: int = cd.get("class_id", 0)
			prev.setup(body_idx, head_idx, _tex_cache)
			name_lbl.text = cd.get("name", "?")
			name_lbl.add_theme_color_override("font_color", C_TEXT)
			info_lbl.text = "Lv.%d %s" % [level, CLASS_NAMES[clampi(class_id, 0, 3)]]
			info_lbl.add_theme_color_override("font_color", C_DIM)
			del_btn.visible = true
		else:
			prev.setup(1, 1, null)  # blank preview
			name_lbl.text = "— Empty Slot —"
			name_lbl.add_theme_color_override("font_color", C_DIM)
			info_lbl.text = "Click to create"
			info_lbl.add_theme_color_override("font_color", C_DIM)
			del_btn.visible = false

		_update_slot_style(i, false)

	# Disable "New Character" if all 3 slots filled
	_new_btn.disabled = _chars.size() >= MAX_CHARS


# ---------------------------------------------------------------------------
# Slot interaction
# ---------------------------------------------------------------------------

func _on_slot_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and \
			(event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and \
			(event as InputEventMouseButton).pressed:
		if idx < _chars.size():
			_select_slot(idx)
		else:
			_on_new_char_pressed()


func _select_slot(idx: int) -> void:
	_selected_slot = idx
	for i in MAX_CHARS:
		_update_slot_style(i, i == idx)
	_enter_btn.disabled = false
	_set_status("")


func _update_slot_style(idx: int, selected: bool) -> void:
	var card: Panel = _slot_cards[idx]
	var border := C_GOLD if selected else C_BORDER
	var bg     := C_SLOT_SEL if selected else C_SLOT
	card.add_theme_stylebox_override("panel", _box(bg, border, 1 if not selected else 2))


# ---------------------------------------------------------------------------
# Enter world
# ---------------------------------------------------------------------------

func _on_enter_pressed() -> void:
	if _selected_slot < 0 or _selected_slot >= _chars.size():
		return
	var char_name: String = _chars[_selected_slot].get("name", "")
	_set_status("Entering world...")
	_enter_btn.disabled = true
	Network.select_char(char_name)


# ---------------------------------------------------------------------------
# Create character
# ---------------------------------------------------------------------------

func _on_new_char_pressed() -> void:
	if _chars.size() >= MAX_CHARS:
		return
	_name_field.text = ""
	_select_class(0)
	_create_status.text = ""
	_create_submit.disabled = false
	_create_panel.visible = true
	_name_field.grab_focus()


func _select_class(class_id: int) -> void:
	_create_class = class_id
	_class_stat_lbl.text = CLASS_STATS[class_id]
	for i in _class_btns.size():
		var btn: Button = _class_btns[i]
		var sel := (i == class_id)
		btn.add_theme_stylebox_override("normal",
				_box(Color(0.18, 0.14, 0.05, 1.0) if sel else C_BTN,
					C_GOLD if sel else C_BORDER, 1))
	_update_create_preview()


func _head_prev() -> void:
	var cur_pos := _head_keys.find(_create_head)
	cur_pos = (cur_pos - 1 + _head_keys.size()) % _head_keys.size()
	_create_head = _head_keys[cur_pos]
	_update_create_preview()


func _head_next() -> void:
	var cur_pos := _head_keys.find(_create_head)
	cur_pos = (cur_pos + 1) % _head_keys.size()
	_create_head = _head_keys[cur_pos]
	_update_create_preview()


func _body_prev() -> void:
	var cur_pos := _body_keys.find(_create_body)
	cur_pos = (cur_pos - 1 + _body_keys.size()) % _body_keys.size()
	_create_body = _body_keys[cur_pos]
	_update_create_preview()


func _body_next() -> void:
	var cur_pos := _body_keys.find(_create_body)
	cur_pos = (cur_pos + 1) % _body_keys.size()
	_create_body = _body_keys[cur_pos]
	_update_create_preview()


func _update_create_preview() -> void:
	(_create_preview as _CharPreview).setup(_create_body, _create_head, _tex_cache)
	if _head_lbl:
		var cur_pos := _head_keys.find(_create_head) + 1
		_head_lbl.text = "%d / %d" % [cur_pos, _head_keys.size()]
	if _body_lbl:
		var cur_pos := _body_keys.find(_create_body) + 1
		_body_lbl.text = "%d / %d" % [cur_pos, _body_keys.size()]


func _on_create_pressed() -> void:
	var name_str := _name_field.text.strip_edges()
	if name_str.length() < 3 or name_str.length() > 16:
		_create_status.text = "Name must be 3-16 characters."
		_create_status.add_theme_color_override("font_color", Color(0.75, 0.15, 0.10))
		return
	_create_status.text = "Creating..."
	_create_status.add_theme_color_override("font_color", C_DIM)
	_create_submit.disabled = true
	Network.create_char(name_str, _create_class, _create_head, _create_body)


func _on_char_created(success: bool, reason: String) -> void:
	_create_submit.disabled = false
	if success:
		# Server will send S_CHAR_LIST to refresh; hide panel for now
		_create_panel.visible = false
		_set_status("Character created! Entering world...")
	else:
		_create_status.text = reason
		_create_status.add_theme_color_override("font_color", Color(0.75, 0.15, 0.10))


func _on_delete_pressed(slot_idx: int) -> void:
	if slot_idx >= _chars.size():
		return
	var char_name: String = _chars[slot_idx].get("name", "")
	if char_name.is_empty():
		return

	var dlg := ConfirmationDialog.new()
	dlg.title = "Delete Character"
	dlg.dialog_text = "Delete %s? This cannot be undone." % char_name
	add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(func():
		_pending_delete_name = char_name
		Network.send_delete_char(char_name)
		dlg.queue_free()
	)
	dlg.canceled.connect(func(): dlg.queue_free())


func _on_char_deleted(success: bool, reason: String) -> void:
	if success:
		for i in _chars.size():
			if (_chars[i] as Dictionary).get("name", "") == _pending_delete_name:
				_chars.remove_at(i)
				break
		_pending_delete_name = ""
		_selected_slot = -1
		_enter_btn.disabled = true
		_refresh_slots()
		_set_status("")
	else:
		_pending_delete_name = ""
		_set_status("Delete failed: " + reason)


func _set_status(msg: String) -> void:
	_status_lbl.text = msg


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_button(text: String, bg: Color, hover: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 16)
	btn.add_theme_color_override("font_color", C_TEXT)
	var normal  := _box(bg,    C_BORDER, 1)
	var hovered := _box(hover, C_GOLD,   1)
	btn.add_theme_stylebox_override("normal",  normal)
	btn.add_theme_stylebox_override("hover",   hovered)
	btn.add_theme_stylebox_override("pressed", hovered)
	btn.add_theme_stylebox_override("focus",   normal)
	return btn


func _box(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color     = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.corner_radius_top_left     = 4
	s.corner_radius_top_right    = 4
	s.corner_radius_bottom_left  = 4
	s.corner_radius_bottom_right = 4
	return s
