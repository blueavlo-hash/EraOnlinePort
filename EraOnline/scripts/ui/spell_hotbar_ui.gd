class_name SpellHotbarUI
extends CanvasLayer
## Era Online - Spell Hotbar UI
## 5-slot spell hotbar above the main HUD, keyboard shortcuts 4-8.
## Also hosts the Spell Shop panel shown when interacting with an Arcane Vendor.
## Built entirely in GDScript for portability (no .tscn dependency).

# ---------------------------------------------------------------------------
# Color palette — dark medieval fantasy (matches skills_ui / inventory_ui)
# ---------------------------------------------------------------------------
const C_BG        := Color(0.07, 0.05, 0.03, 0.97)
const C_BORDER    := Color(0.55, 0.40, 0.12, 1.00)
const C_TITLE     := Color(0.85, 0.68, 0.22, 1.00)
const C_TEXT      := Color(0.90, 0.82, 0.62, 1.00)
const C_TEXT_DIM  := Color(0.55, 0.47, 0.30, 1.00)
const C_BUTTON    := Color(0.18, 0.13, 0.05, 1.00)
const C_MANA      := Color(0.16, 0.32, 0.85, 1.00)
const C_SPELL_BG  := Color(0.10, 0.08, 0.04, 1.00)
const C_SEP       := Color(0.40, 0.28, 0.08, 0.55)
const C_CD_OVER   := Color(0.0,  0.0,  0.0,  0.60)
const C_SLOT_RDY  := Color(0.55, 0.40, 0.12, 1.00)   # gold when ready
const C_SLOT_CD   := Color(0.28, 0.22, 0.12, 0.70)   # dimmed when on cd
const C_SLOT_EMPTY:= Color(0.20, 0.15, 0.08, 0.50)

# Layout constants
const SCR_W    := 1280.0
const SCR_H    := 720.0
const HUD_H    := 96
const HOTBAR_H := 62
const SLOT_SZ  := 54
const GAP      := 6
const NUM_SLOTS := 5

# Spell shop layout
const SHOP_W := 400
const SHOP_H := 380

# Target type icon map (for slot corner badges)
const TARGET_ICONS := {
	0: "⊙",   # self
	1: "✦",   # enemy
	2: "✧",   # ally
	3: "⊕",   # ground
	4: "◎",   # area
}
const TARGET_ICON_COLORS := {
	0: Color(0.3,  0.8,  0.3,  1.0),
	1: Color(1.0,  0.3,  0.3,  1.0),
	2: Color(0.3,  0.6,  1.0,  1.0),
	3: Color(1.0,  0.7,  0.2,  1.0),
	4: Color(0.9,  0.4,  1.0,  1.0),
}

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal spell_cast_requested(spell_id: int, target_id: int, tx: int, ty: int)
signal aoe_aim_requested(spell_id: int)    # GROUND_AOE: world_map enters aim mode
signal single_aim_requested(spell_id: int) # SINGLE_ENEMY/ALLY: world_map enters target mode

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _current_vendor_npc_id: int = 0
var _shop_panel: Panel          = null

var _slot_panels:    Array[Panel]     = []
var _slot_name_lbls: Array[Label]     = []
var _slot_mana_lbls: Array[Label]     = []
var _slot_cd_overs:  Array[ColorRect] = []
var _slot_cd_lbls:   Array[Label]     = []
var _slot_type_lbls: Array[Label]     = []   # target type icon (top-right corner)

# Hotbar root panel (positioned above HUD)
var _hotbar_panel: Panel = null

# Aim mode indicator label (shown above hotbar during target selection)
var _aim_mode_label: Label = null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 11   # above HUD (10) but below shop (12)
	_build_hotbar()
	# Visual hotbar hidden — superseded by unified HudUI hotbar.
	# This node is kept alive only to host the spell shop panel.
	if _hotbar_panel != null:
		_hotbar_panel.visible = false
	if _aim_mode_label != null:
		_aim_mode_label.visible = false
	PlayerState.hotbar_changed.connect(_on_hotbar_changed)
	Network.on_spell_shop.connect(_on_network_spell_shop)
	if PlayerState.has_signal("spell_cast_started"):
		PlayerState.spell_cast_started.connect(func(_sid): hide_aim_mode())
	_refresh_slots()


func _process(_delta: float) -> void:
	for i in NUM_SLOTS:
		var spell_id: int      = PlayerState.get_hotbar_spell(i)
		var cd_over: ColorRect = _slot_cd_overs[i]
		var cd_lbl:  Label     = _slot_cd_lbls[i]
		if spell_id == 0:
			cd_over.size.y = 0.0
			cd_lbl.text    = ""
			continue
		var rem := PlayerState.get_cooldown_remaining(spell_id)
		if rem <= 0.0:
			cd_over.size.y = 0.0
			cd_lbl.text    = ""
			_set_slot_border(i, true)
		else:
			var spell_data := GameData.get_spell(spell_id)
			var total_cd: float = spell_data.get("cooldown", 1.0)
			var frac: float     = minf(rem / total_cd, 1.0)
			cd_over.size.y = SLOT_SZ * frac
			cd_lbl.text    = "%.1fs" % rem
			_set_slot_border(i, false)


## Key handling removed — unified HudUI handles keys 1-0 for all hotbar slots.


# ---------------------------------------------------------------------------
# Build hotbar
# ---------------------------------------------------------------------------

func _build_hotbar() -> void:
	var total_w := NUM_SLOTS * SLOT_SZ + (NUM_SLOTS - 1) * GAP
	var bar_x   := SCR_W / 2.0 - total_w / 2.0
	var bar_y   := SCR_H - HUD_H - HOTBAR_H - 4.0

	_hotbar_panel = Panel.new()
	_hotbar_panel.position    = Vector2(bar_x - 6, bar_y - 4)
	_hotbar_panel.size        = Vector2(total_w + 12, HOTBAR_H + 8)
	_hotbar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hotbar_panel.add_theme_stylebox_override("panel", _make_style(
		Color(C_BG.r, C_BG.g, C_BG.b, 0.80), C_BORDER, 1, 4))
	add_child(_hotbar_panel)

	for i in NUM_SLOTS:
		var slot_x := 6.0 + i * (SLOT_SZ + GAP)
		var slot_y := 4.0
		_build_slot(i, slot_x, slot_y)

	# Aim mode label — positioned directly above the hotbar panel
	_aim_mode_label = Label.new()
	_aim_mode_label.text = "◎ CLICK TARGET"
	_aim_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aim_mode_label.visible  = false
	_aim_mode_label.position = Vector2(_hotbar_panel.position.x, _hotbar_panel.position.y - 22)
	_aim_mode_label.size     = Vector2(_hotbar_panel.size.x, 20)
	_aim_mode_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	_aim_mode_label.add_theme_font_size_override("font_size", 13)
	add_child(_aim_mode_label)


func _build_slot(i: int, local_x: float, local_y: float) -> void:
	var slot := Panel.new()
	slot.position    = Vector2(local_x, local_y)
	slot.size        = Vector2(SLOT_SZ, SLOT_SZ)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.add_theme_stylebox_override("panel", _make_style(C_SPELL_BG, C_SLOT_EMPTY, 1, 3))
	_hotbar_panel.add_child(slot)
	_slot_panels.append(slot)

	# Slot number label (top-left, tiny, keyboard shortcut hint)
	var num_lbl := Label.new()
	num_lbl.text     = str(i + 4)   # keys 4-8
	num_lbl.position = Vector2(3, 2)
	num_lbl.size     = Vector2(14, 12)
	num_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	num_lbl.add_theme_font_size_override("font_size", 9)
	num_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(num_lbl)

	# Spell name label (center)
	var name_lbl := Label.new()
	name_lbl.name     = "NameLbl"
	name_lbl.text     = "—"
	name_lbl.position = Vector2(2, 16)
	name_lbl.size     = Vector2(SLOT_SZ - 4, 20)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.clip_text   = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(name_lbl)
	_slot_name_lbls.append(name_lbl)

	# Mana cost label (bottom, blue)
	var mana_lbl := Label.new()
	mana_lbl.name     = "ManaLbl"
	mana_lbl.text     = ""
	mana_lbl.position = Vector2(2, SLOT_SZ - 16)
	mana_lbl.size     = Vector2(SLOT_SZ - 4, 14)
	mana_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mana_lbl.add_theme_color_override("font_color", C_MANA)
	mana_lbl.add_theme_font_size_override("font_size", 9)
	mana_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(mana_lbl)
	_slot_mana_lbls.append(mana_lbl)

	# Cooldown overlay (dark fill from top, height animated in _process)
	var cd_over := ColorRect.new()
	cd_over.color    = C_CD_OVER
	cd_over.position = Vector2(0, 0)
	cd_over.size     = Vector2(SLOT_SZ, 0.0)
	cd_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(cd_over)
	_slot_cd_overs.append(cd_over)

	# Cooldown countdown label (centered over overlay)
	var cd_lbl := Label.new()
	cd_lbl.text     = ""
	cd_lbl.position = Vector2(0, SLOT_SZ / 2.0 - 8)
	cd_lbl.size     = Vector2(SLOT_SZ, 16)
	cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	cd_lbl.add_theme_font_size_override("font_size", 11)
	cd_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(cd_lbl)
	_slot_cd_lbls.append(cd_lbl)

	# Target type icon (top-right corner, tiny)
	var type_lbl := Label.new()
	type_lbl.text     = ""
	type_lbl.position = Vector2(SLOT_SZ - 14, 2)
	type_lbl.size     = Vector2(12, 12)
	type_lbl.add_theme_font_size_override("font_size", 9)
	type_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(type_lbl)
	_slot_type_lbls.append(type_lbl)

	# Click to cast
	slot.gui_input.connect(_on_slot_clicked.bind(i))


# ---------------------------------------------------------------------------
# Slot refresh
# ---------------------------------------------------------------------------

func _refresh_slots() -> void:
	for i in NUM_SLOTS:
		var spell_id: int = PlayerState.get_hotbar_spell(i)
		if spell_id == 0:
			_slot_name_lbls[i].text = "—"
			_slot_name_lbls[i].add_theme_color_override("font_color", C_TEXT_DIM)
			_slot_mana_lbls[i].text = ""
			_slot_type_lbls[i].text = ""
			_set_slot_border(i, false)
		else:
			var spell_data: Dictionary = GameData.get_spell(spell_id)
			var raw_name: String = spell_data.get("name", "Spell")
			# Truncate to 8 chars for display
			_slot_name_lbls[i].text = raw_name.substr(0, 8) if raw_name.length() > 8 else raw_name
			_slot_name_lbls[i].add_theme_color_override("font_color", C_TEXT)
			var mana: int = spell_data.get("needs_mana", 0)
			_slot_mana_lbls[i].text = "%dMP" % mana if mana > 0 else ""
			_set_slot_border(i, PlayerState.is_spell_ready(spell_id))

			# Target type icon in top-right corner
			var tt: int = spell_data.get("target_type", -1)
			if TARGET_ICONS.has(tt):
				_slot_type_lbls[i].text = TARGET_ICONS[tt]
				_slot_type_lbls[i].add_theme_color_override("font_color",
					TARGET_ICON_COLORS.get(tt, C_TEXT_DIM))
			else:
				_slot_type_lbls[i].text = ""


func _on_hotbar_changed() -> void:
	_refresh_slots()


func _set_slot_border(slot_idx: int, ready: bool) -> void:
	var spell_id: int = PlayerState.get_hotbar_spell(slot_idx)
	if spell_id == 0:
		_slot_panels[slot_idx].add_theme_stylebox_override("panel",
			_make_style(C_SPELL_BG, C_SLOT_EMPTY, 1, 3))
	elif ready:
		_slot_panels[slot_idx].add_theme_stylebox_override("panel",
			_make_style(C_SPELL_BG, C_SLOT_RDY, 2, 3))
	else:
		_slot_panels[slot_idx].add_theme_stylebox_override("panel",
			_make_style(Color(0.07, 0.05, 0.03, 0.85), C_SLOT_CD, 1, 3))


# ---------------------------------------------------------------------------
# Slot click handling
# ---------------------------------------------------------------------------

func _on_slot_clicked(event: InputEvent, slot_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		try_cast_hotbar_slot(slot_idx)


# ---------------------------------------------------------------------------
# Cast
# ---------------------------------------------------------------------------

func try_cast_hotbar_slot(slot: int) -> void:
	var spell_id: int = PlayerState.get_hotbar_spell(slot)
	if spell_id == 0:
		return
	if not PlayerState.is_spell_ready(spell_id):
		return
	var sp: Dictionary   = GameData.get_spell(spell_id)
	var target_type: int = sp.get("target_type", 0)
	match target_type:
		0, 4:  # SELF / SELF_AOE — cast immediately on self
			emit_signal("spell_cast_requested", spell_id, -1, 0, 0)
		1, 2:  # SINGLE_ENEMY / SINGLE_ALLY — left-click an NPC to cast
			var spell_name: String = sp.get("name", "Spell")
			show_aim_mode(spell_name, "target")
			emit_signal("single_aim_requested", spell_id)
		3:     # GROUND_AOE — enter aim mode, right-click fires it
			var spell_name: String = sp.get("name", "Spell")
			show_aim_mode(spell_name, "ground")
			emit_signal("aoe_aim_requested", spell_id)


# ---------------------------------------------------------------------------
# Aim mode indicator
# ---------------------------------------------------------------------------

func show_aim_mode(spell_name: String, mode: String) -> void:
	if _aim_mode_label == null:
		return
	match mode:
		"ground": _aim_mode_label.text = "◎ CLICK GROUND: " + spell_name
		"target": _aim_mode_label.text = "✦ CLICK ENEMY: "  + spell_name
		_:        _aim_mode_label.text = "◎ " + spell_name
	_aim_mode_label.visible = true


func hide_aim_mode() -> void:
	if _aim_mode_label != null:
		_aim_mode_label.visible = false


# ---------------------------------------------------------------------------
# Spell Shop
# ---------------------------------------------------------------------------

func _on_network_spell_shop(spells: Array) -> void:
	open_spell_shop(_current_vendor_npc_id, spells)


func open_spell_shop(npc_id: int, spells: Array) -> void:
	_current_vendor_npc_id = npc_id

	# Remove old shop panel if it exists
	if _shop_panel != null and is_instance_valid(_shop_panel):
		_shop_panel.queue_free()
		_shop_panel = null

	_shop_panel = _build_shop_panel(spells)
	add_child(_shop_panel)


func _build_shop_panel(spells: Array) -> Panel:
	var panel := Panel.new()
	panel.position    = Vector2(SCR_W / 2.0 - SHOP_W / 2.0, SCR_H / 2.0 - SHOP_H / 2.0)
	panel.size        = Vector2(SHOP_W, SHOP_H)
	panel.add_theme_stylebox_override("panel", _make_style(C_BG, C_BORDER, 2, 4))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	# Dragging support
	panel.gui_input.connect(_on_shop_input.bind(panel))

	# Title bar
	var title_bar := HBoxContainer.new()
	title_bar.position = Vector2(0, 0)
	title_bar.size     = Vector2(SHOP_W, 34)
	panel.add_child(title_bar)

	var title_lbl := Label.new()
	title_lbl.text = "   ARCANE VENDOR"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_color_override("font_color", C_TITLE)
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_bar.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "  ✕  "
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", C_TEXT_DIM)
	close_btn.pressed.connect(func():
		if is_instance_valid(panel):
			panel.queue_free()
			_shop_panel = null
	)
	title_bar.add_child(close_btn)

	# Separator
	var sep := ColorRect.new()
	sep.color    = C_SEP
	sep.position = Vector2(0, 34)
	sep.size     = Vector2(SHOP_W, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(sep)

	# Column headers
	var header_row := HBoxContainer.new()
	header_row.position = Vector2(8, 38)
	header_row.size     = Vector2(SHOP_W - 16, 18)
	header_row.add_theme_constant_override("separation", 4)
	panel.add_child(header_row)

	for col_text: String in ["Spell", "Mana", "Price", ""]:
		var h := Label.new()
		h.text = col_text
		h.add_theme_color_override("font_color", C_TEXT_DIM)
		h.add_theme_font_size_override("font_size", 10)
		if col_text == "Spell":
			h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		else:
			h.custom_minimum_size = Vector2(52, 0)
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		header_row.add_child(h)

	# Separator under headers
	var sep2 := ColorRect.new()
	sep2.color    = C_SEP
	sep2.position = Vector2(0, 58)
	sep2.size     = Vector2(SHOP_W, 1)
	sep2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(sep2)

	# Scrollable spell list
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(6, 62)
	scroll.size     = Vector2(SHOP_W - 12, SHOP_H - 70)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	scroll.add_child(vbox)

	if spells.is_empty():
		var no_spells := Label.new()
		no_spells.text = "No spells available."
		no_spells.add_theme_color_override("font_color", C_TEXT_DIM)
		no_spells.add_theme_font_size_override("font_size", 12)
		vbox.add_child(no_spells)
	else:
		for entry in spells:
			var spell_id: int  = entry.get("spell_id", 0)
			var price:    int  = entry.get("price", 0)
			if spell_id == 0:
				continue
			_build_shop_row(vbox, spell_id, price)

	return panel


func _build_shop_row(parent: VBoxContainer, spell_id: int, price: int) -> void:
	var spell_data: Dictionary = GameData.get_spell(spell_id)
	var spell_name: String     = spell_data.get("name", "Spell %d" % spell_id)
	var mana:       int        = spell_data.get("needs_mana", 0)
	var known:      bool       = PlayerState.has_spell(spell_id)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.custom_minimum_size = Vector2(0, 28)
	parent.add_child(row)

	# Background tint
	var row_bg := Panel.new()
	row_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row_bg.add_theme_stylebox_override("panel",
		_make_style(Color(0.08, 0.06, 0.03, 0.70), Color(0, 0, 0, 0), 0, 2))
	row_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(row_bg)

	# Spell name
	var name_lbl := Label.new()
	name_lbl.text = spell_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_color_override("font_color", C_TEXT_DIM if known else C_TEXT)
	name_lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(name_lbl)

	# Mana cost
	var mana_lbl := Label.new()
	mana_lbl.text = "%d" % mana
	mana_lbl.custom_minimum_size = Vector2(52, 0)
	mana_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mana_lbl.add_theme_color_override("font_color", C_MANA)
	mana_lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(mana_lbl)

	# Price
	var price_lbl := Label.new()
	price_lbl.text = "%dg" % price
	price_lbl.custom_minimum_size = Vector2(52, 0)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_lbl.add_theme_color_override("font_color", C_TITLE)
	price_lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(price_lbl)

	# Buy button or "Known" label
	if known:
		var known_lbl := Label.new()
		known_lbl.text = "Known"
		known_lbl.custom_minimum_size = Vector2(64, 0)
		known_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		known_lbl.add_theme_color_override("font_color", Color(0.35, 0.65, 0.35, 1.0))
		known_lbl.add_theme_font_size_override("font_size", 11)
		row.add_child(known_lbl)
	else:
		var buy_btn := Button.new()
		buy_btn.name = "BuyBtn_%d" % spell_id
		buy_btn.text = "Buy"
		buy_btn.custom_minimum_size = Vector2(64, 24)
		buy_btn.add_theme_stylebox_override("normal",
			_make_style(C_BUTTON, C_BORDER, 1, 3))
		buy_btn.add_theme_stylebox_override("hover",
			_make_style(Color(0.26, 0.20, 0.07, 1), C_TITLE, 1, 3))
		buy_btn.add_theme_stylebox_override("pressed",
			_make_style(Color(0.14, 0.10, 0.04, 1), C_BORDER, 1, 3))
		buy_btn.add_theme_stylebox_override("disabled",
			_make_style(Color(0.10, 0.08, 0.04, 0.7), C_TEXT_DIM, 1, 3))
		buy_btn.add_theme_color_override("font_color", C_TEXT)
		buy_btn.add_theme_font_size_override("font_size", 11)
		buy_btn.pressed.connect(_on_buy_pressed.bind(spell_id, buy_btn))
		row.add_child(buy_btn)


func _on_buy_pressed(spell_id: int, btn: Button) -> void:
	btn.disabled = true
	btn.text = "..."
	Network.send_buy_spell(_current_vendor_npc_id, spell_id)


# ---------------------------------------------------------------------------
# Shop window dragging
# ---------------------------------------------------------------------------

var _shop_dragging:    bool    = false
var _shop_drag_offset: Vector2 = Vector2.ZERO

func _on_shop_input(event: InputEvent, panel: Panel) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_shop_dragging    = event.pressed
			_shop_drag_offset = event.position
	elif event is InputEventMouseMotion and _shop_dragging:
		panel.position += event.relative


# ---------------------------------------------------------------------------
# Style helpers
# ---------------------------------------------------------------------------

func _make_style(bg: Color, border: Color, border_w: int, corner: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color               = bg
	s.border_color           = border
	s.border_width_left      = border_w
	s.border_width_right     = border_w
	s.border_width_top       = border_w
	s.border_width_bottom    = border_w
	s.corner_radius_top_left     = corner
	s.corner_radius_top_right    = corner
	s.corner_radius_bottom_left  = corner
	s.corner_radius_bottom_right = corner
	return s
