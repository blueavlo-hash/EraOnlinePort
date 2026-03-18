class_name SpellbookUI
extends CanvasLayer
## Era Online - Spellbook UI
## Toggle with 'B'. Tabbed spell list by category + description/assign panel below.
## Built entirely in GDScript for portability (no .tscn dependency).

# ---------------------------------------------------------------------------
# Color palette — dark medieval fantasy (matches skills_ui / inventory_ui)
# ---------------------------------------------------------------------------
const C_BG     := Color(0.06, 0.04, 0.02, 0.97)
const C_BORDER := Color(0.55, 0.40, 0.12, 1.00)
const C_TITLE  := Color(0.88, 0.70, 0.22, 1.00)
const C_TEXT   := Color(0.92, 0.84, 0.64, 1.00)
const C_DIM    := Color(0.52, 0.45, 0.28, 1.00)
const C_MANA   := Color(0.22, 0.42, 0.95, 1.00)
const C_SEP    := Color(0.40, 0.28, 0.08, 0.50)
const C_KNOWN  := Color(0.35, 0.65, 0.35, 1.00)
const C_HOVER  := Color(0.18, 0.14, 0.06, 0.80)
const C_SELECT := Color(0.28, 0.20, 0.06, 1.00)
const C_SPELL_BG := Color(0.10, 0.08, 0.04, 1.00)
const C_TEXT_DIM := Color(0.55, 0.47, 0.30, 1.00)
const C_BUTTON   := Color(0.18, 0.13, 0.05, 1.00)
const C_TAB_ACT  := Color(0.28, 0.20, 0.06, 1.00)   # active tab bg
const C_TAB_IDLE := Color(0.10, 0.07, 0.02, 1.00)   # inactive tab bg

# Layout
const SCR_W    := 1280.0
const SCR_H    := 720.0
const PANEL_W  := 480
const PANEL_H  := 520   # slightly taller to fit tabs
const ROW_H    := 38

# Tab categories (order = display order)
const CATEGORIES := ["ALL", "SELF", "ENEMY", "ALLY", "AOE", "SUMMON"]
const CAT_LABELS := {
	"ALL":    "All",
	"SELF":   "Self",
	"ENEMY":  "Enemy",
	"ALLY":   "Ally",
	"AOE":    "AoE",
	"SUMMON": "Summon",
}
const CAT_COLORS := {
	"ALL":    Color(0.88, 0.70, 0.22, 1.0),  # gold
	"SELF":   Color(0.3,  0.8,  0.3,  1.0),  # green
	"ENEMY":  Color(1.0,  0.3,  0.3,  1.0),  # red
	"ALLY":   Color(0.3,  0.6,  1.0,  1.0),  # blue
	"AOE":    Color(0.9,  0.4,  1.0,  1.0),  # purple
	"SUMMON": Color(1.0,  0.75, 0.2,  1.0),  # amber
}

# Target type colors (for badge in list rows)
const TARGET_COLORS := {
	0: Color(0.3,  0.8,  0.3,  1.0),
	1: Color(1.0,  0.3,  0.3,  1.0),
	2: Color(0.3,  0.6,  1.0,  1.0),
	3: Color(1.0,  0.7,  0.2,  1.0),
	4: Color(0.9,  0.4,  1.0,  1.0),
}

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _panel: Panel                = null
var _visible: bool               = false
var _selected_spell_id: int      = 0
var _active_category: String     = "ALL"

# Tab buttons  category → Button
var _cat_btns: Dictionary        = {}

# List area
var _vbox: VBoxContainer         = null
var _spell_rows: Dictionary      = {}   # spell_id → Panel (row)
var _empty_lbl: Label            = null

# Description area
var _desc_name:  Label           = null
var _desc_text:  Label           = null
var _desc_stats: Label           = null
var _desc_dmg:   Label           = null

# Hotbar assign row
var _assign_container: HBoxContainer = null
var _assign_btns: Array[Button]      = []
var _assign_flash_timer: float       = 0.0
var _assign_flash_btn:   Button      = null

# Drag
var _dragging:    bool    = false
var _drag_offset: Vector2 = Vector2.ZERO


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 9
	_build_panel()
	_panel.visible = false

	PlayerState.spellbook_changed.connect(_rebuild_list)
	if Network.has_signal("on_spellbook"):
		Network.on_spellbook.connect(func(_ids: Array) -> void: _rebuild_list())
	if Network.has_signal("on_spell_unlock"):
		Network.on_spell_unlock.connect(_on_spell_unlock)


func _process(delta: float) -> void:
	if _assign_flash_timer > 0.0:
		_assign_flash_timer -= delta
		if _assign_flash_timer <= 0.0 and _assign_flash_btn != null:
			_assign_flash_btn.text = _assign_flash_btn.get_meta("slot_label", _assign_flash_btn.text)
			_assign_flash_btn.add_theme_color_override("font_color", C_TEXT)
			_assign_flash_btn = null
	if _panel.visible and _selected_spell_id > 0:
		_update_cooldown_hint()


func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
		_rebuild_list()


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build_panel() -> void:
	_panel = Panel.new()
	_panel.position   = Vector2(SCR_W / 2.0 - PANEL_W / 2.0, SCR_H / 2.0 - PANEL_H / 2.0)
	_panel.size       = Vector2(PANEL_W, PANEL_H)
	_panel.add_theme_stylebox_override("panel", _make_style(C_BG, C_BORDER, 2, 4))
	_panel.gui_input.connect(_on_panel_input)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	# --- Title bar ---
	var title_bar := HBoxContainer.new()
	title_bar.position = Vector2(0, 0)
	title_bar.size     = Vector2(PANEL_W, 34)
	_panel.add_child(title_bar)

	var title_lbl := Label.new()
	title_lbl.text = "   SPELLBOOK"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_color_override("font_color", C_TITLE)
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_bar.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "  ✕  "
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", C_DIM)
	close_btn.pressed.connect(func(): _panel.visible = false)
	title_bar.add_child(close_btn)

	_hsep(_panel, 34)

	# --- Category tab strip ---
	_build_tabs()

	_hsep(_panel, 64)

	# --- Scrollable spell list ---
	const LIST_TOP    := 66
	const LIST_BOTTOM := 308
	var scroll := ScrollContainer.new()
	scroll.position             = Vector2(6, LIST_TOP)
	scroll.size                 = Vector2(PANEL_W - 12, LIST_BOTTOM - LIST_TOP)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(_vbox)

	_empty_lbl = Label.new()
	_empty_lbl.text           = "No spells in this category.\nVisit the Arcane Vendor!"
	_empty_lbl.position       = Vector2(6, LIST_TOP + 40)
	_empty_lbl.size           = Vector2(PANEL_W - 12, 60)
	_empty_lbl.autowrap_mode  = TextServer.AUTOWRAP_WORD_SMART
	_empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_lbl.add_theme_color_override("font_color", C_DIM)
	_empty_lbl.add_theme_font_size_override("font_size", 11)
	_empty_lbl.visible = false
	_panel.add_child(_empty_lbl)

	_hsep(_panel, LIST_BOTTOM)

	# --- Description panel ---
	_build_desc_panel(LIST_BOTTOM + 2)


func _build_tabs() -> void:
	# Six tabs equally spaced across the panel width
	const TAB_Y    := 36.0
	const TAB_H    := 28.0
	var tab_w: float = float(PANEL_W) / float(CATEGORIES.size())

	for i in CATEGORIES.size():
		var cat: String = CATEGORIES[i]
		var btn := Button.new()
		btn.text = CAT_LABELS[cat]
		btn.position = Vector2(i * tab_w, TAB_Y)
		btn.size     = Vector2(tab_w, TAB_H)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_style_tab(btn, cat == _active_category, cat)
		btn.pressed.connect(_on_tab_pressed.bind(cat))
		_panel.add_child(btn)
		_cat_btns[cat] = btn


func _style_tab(btn: Button, active: bool, cat: String) -> void:
	var col: Color = CAT_COLORS.get(cat, C_TITLE)
	var bg := _make_style(
		C_TAB_ACT if active else C_TAB_IDLE,
		col if active else Color(col.r, col.g, col.b, 0.35),
		1 if active else 1,
		2
	)
	var bg_hover := _make_style(Color(0.20, 0.15, 0.05, 1.0), col, 1, 2)
	btn.add_theme_stylebox_override("normal",  bg)
	btn.add_theme_stylebox_override("hover",   bg_hover)
	btn.add_theme_stylebox_override("pressed", bg)
	btn.add_theme_color_override("font_color",
		col if active else Color(col.r, col.g, col.b, 0.6))
	btn.add_theme_font_size_override("font_size", 11)


func _build_desc_panel(top_y: float) -> void:
	_desc_name = Label.new()
	_desc_name.text     = ""
	_desc_name.position = Vector2(8, top_y + 4)
	_desc_name.size     = Vector2(PANEL_W - 16, 22)
	_desc_name.add_theme_color_override("font_color", C_TITLE)
	_desc_name.add_theme_font_size_override("font_size", 14)
	_panel.add_child(_desc_name)

	_desc_text = Label.new()
	_desc_text.text          = ""
	_desc_text.position      = Vector2(8, top_y + 28)
	_desc_text.size          = Vector2(PANEL_W - 16, 48)
	_desc_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_text.add_theme_color_override("font_color", C_TEXT)
	_desc_text.add_theme_font_size_override("font_size", 11)
	_panel.add_child(_desc_text)

	_desc_stats = Label.new()
	_desc_stats.text          = ""
	_desc_stats.position      = Vector2(8, top_y + 80)
	_desc_stats.size          = Vector2(PANEL_W - 16, 52)
	_desc_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_stats.add_theme_color_override("font_color", C_DIM)
	_desc_stats.add_theme_font_size_override("font_size", 11)
	_panel.add_child(_desc_stats)

	_desc_dmg = Label.new()
	_desc_dmg.text     = ""
	_desc_dmg.position = Vector2(8, top_y + 136)
	_desc_dmg.size     = Vector2(PANEL_W - 16, 20)
	_desc_dmg.add_theme_color_override("font_color", C_TEXT)
	_desc_dmg.add_theme_font_size_override("font_size", 12)
	_panel.add_child(_desc_dmg)

	var cd_hint := Label.new()
	cd_hint.name     = "CdHint"
	cd_hint.text     = ""
	cd_hint.position = Vector2(8, top_y + 158)
	cd_hint.size     = Vector2(PANEL_W - 16, 16)
	cd_hint.add_theme_color_override("font_color", C_DIM)
	cd_hint.add_theme_font_size_override("font_size", 10)
	_panel.add_child(cd_hint)

	_hsep(_panel, top_y + 178)

	var assign_lbl := Label.new()
	assign_lbl.text     = "Assign to hotbar:"
	assign_lbl.position = Vector2(8, top_y + 184)
	assign_lbl.size     = Vector2(140, 18)
	assign_lbl.add_theme_color_override("font_color", C_DIM)
	assign_lbl.add_theme_font_size_override("font_size", 11)
	_panel.add_child(assign_lbl)

	_assign_container = HBoxContainer.new()
	_assign_container.position = Vector2(152, top_y + 182)
	_assign_container.size     = Vector2(PANEL_W - 160, 26)
	_assign_container.add_theme_constant_override("separation", 6)
	_panel.add_child(_assign_container)

	for i in 5:
		var slot_key := i + 4
		var btn := Button.new()
		btn.text = str(slot_key)
		btn.custom_minimum_size = Vector2(36, 26)
		btn.add_theme_stylebox_override("normal",  _make_style(C_BUTTON, C_BORDER, 1, 3))
		btn.add_theme_stylebox_override("hover",   _make_style(Color(0.26, 0.20, 0.07, 1), C_TITLE, 1, 3))
		btn.add_theme_stylebox_override("pressed", _make_style(Color(0.14, 0.10, 0.04, 1), C_BORDER, 1, 3))
		btn.add_theme_color_override("font_color", C_TEXT)
		btn.add_theme_font_size_override("font_size", 12)
		btn.set_meta("slot_label", str(slot_key))
		btn.pressed.connect(_on_assign.bind(i))
		_assign_container.add_child(btn)
		_assign_btns.append(btn)


# ---------------------------------------------------------------------------
# Category helpers
# ---------------------------------------------------------------------------

func _get_spell_category(spell_data: Dictionary) -> String:
	if int(spell_data.get("summon_creature", 0)) > 0:
		return "SUMMON"
	var tt := int(spell_data.get("target_type", 0))
	if tt == 0:   return "SELF"
	if tt == 1:   return "ENEMY"
	if tt == 2:   return "ALLY"
	if tt == 3 or tt == 4: return "AOE"
	return "SELF"


func _on_tab_pressed(cat: String) -> void:
	_active_category = cat
	for c in _cat_btns:
		_style_tab(_cat_btns[c], c == cat, c)
	_rebuild_list()


# ---------------------------------------------------------------------------
# Rebuild list
# ---------------------------------------------------------------------------

func _rebuild_list() -> void:
	for child in _vbox.get_children():
		child.queue_free()
	_spell_rows.clear()

	var spells: Array = PlayerState.learned_spells
	var visible_spells: Array = []
	var seen_ids: Dictionary = {}
	for spell_id in spells:
		var sid := int(spell_id)
		if seen_ids.has(sid):
			continue
		seen_ids[sid] = true
		var spell_data: Dictionary = GameData.get_spell(sid)
		# Skip empty/placeholder spells
		if spell_data.get("name", "") in ["", "(Empty)"]:
			continue
		if _active_category == "ALL" or _get_spell_category(spell_data) == _active_category:
			visible_spells.append(sid)

	_empty_lbl.visible = visible_spells.is_empty()

	for spell_id_v in visible_spells:
		var spell_id: int          = int(spell_id_v)
		var spell_data: Dictionary = GameData.get_spell(spell_id)
		var spell_name: String     = spell_data.get("name", "Spell %d" % spell_id)
		var mana_cost: int         = spell_data.get("needs_mana", 0)
		var cat: String            = _get_spell_category(spell_data)

		var row_panel := Panel.new()
		row_panel.custom_minimum_size = Vector2(PANEL_W - 14, ROW_H)
		var is_sel: bool           = (spell_id == _selected_spell_id)
		row_panel.add_theme_stylebox_override("panel", _make_style(
			C_SELECT if is_sel else C_SPELL_BG,
			C_BORDER if is_sel else Color(0, 0, 0, 0),
			1 if is_sel else 0, 3))
		row_panel.gui_input.connect(_on_row_input.bind(spell_id, row_panel))
		row_panel.mouse_filter = Control.MOUSE_FILTER_STOP

		# Category badge
		var badge_lbl := Label.new()
		badge_lbl.text     = "[%s]" % CAT_LABELS.get(cat, cat)
		badge_lbl.position = Vector2(6, (ROW_H - 14) / 2.0)
		badge_lbl.size     = Vector2(62, 14)
		badge_lbl.add_theme_color_override("font_color", CAT_COLORS.get(cat, C_DIM))
		badge_lbl.add_theme_font_size_override("font_size", 9)
		badge_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_panel.add_child(badge_lbl)

		# Spell name
		var name_lbl := Label.new()
		name_lbl.text     = spell_name
		name_lbl.position = Vector2(72, (ROW_H - 16) / 2.0)
		name_lbl.size     = Vector2(PANEL_W - 150, 16)
		name_lbl.add_theme_color_override("font_color", C_TEXT)
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_panel.add_child(name_lbl)

		# Mana cost
		var mana_lbl := Label.new()
		mana_lbl.text     = "%d MP" % mana_cost if mana_cost > 0 else ""
		mana_lbl.position = Vector2(PANEL_W - 76, (ROW_H - 14) / 2.0)
		mana_lbl.size     = Vector2(62, 14)
		mana_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		mana_lbl.add_theme_color_override("font_color", C_MANA)
		mana_lbl.add_theme_font_size_override("font_size", 10)
		mana_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_panel.add_child(mana_lbl)

		_vbox.add_child(row_panel)
		_spell_rows[spell_id] = row_panel

	if _selected_spell_id > 0 and PlayerState.has_spell(_selected_spell_id):
		_show_detail(_selected_spell_id)
	else:
		_selected_spell_id = 0
		_clear_detail()


func _on_spell_unlock(_spell_id: int) -> void:
	_rebuild_list()


# ---------------------------------------------------------------------------
# Row input
# ---------------------------------------------------------------------------

func _on_row_input(event: InputEvent, spell_id: int, row_panel: Panel) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_spell(spell_id)
	elif event is InputEventMouseMotion:
		if spell_id != _selected_spell_id:
			row_panel.add_theme_stylebox_override("panel",
				_make_style(C_HOVER, Color(0, 0, 0, 0), 0, 3))
	if event is InputEventMouseMotion and not row_panel.get_global_rect().has_point(
			row_panel.get_global_transform().origin + event.position):
		if spell_id != _selected_spell_id:
			row_panel.add_theme_stylebox_override("panel",
				_make_style(C_SPELL_BG, Color(0, 0, 0, 0), 0, 3))


func _select_spell(spell_id: int) -> void:
	_selected_spell_id = spell_id
	for sid_v in _spell_rows:
		var sid: int  = int(sid_v)
		var panel: Panel = _spell_rows[sid_v]
		var is_sel: bool = (sid == spell_id)
		panel.add_theme_stylebox_override("panel", _make_style(
			C_SELECT if is_sel else C_SPELL_BG,
			C_BORDER if is_sel else Color(0, 0, 0, 0),
			1 if is_sel else 0, 3))
	_show_detail(spell_id)


# ---------------------------------------------------------------------------
# Detail panel
# ---------------------------------------------------------------------------

func _show_detail(spell_id: int) -> void:
	var spell_data: Dictionary = GameData.get_spell(spell_id)
	if spell_data.is_empty():
		_clear_detail()
		return

	_desc_name.text = spell_data.get("name", "Unknown Spell")
	_desc_text.text = spell_data.get("desc", "")

	var mana:    int   = spell_data.get("needs_mana", 0)
	var range_v: int   = spell_data.get("range", 0)
	var cd:      float = spell_data.get("cooldown", 0.0)
	var cat:     String = _get_spell_category(spell_data)
	var stats_str := "Mana: %d   Range: %d tiles   Cooldown: %.1fs   Type: %s" % [
		mana, range_v, cd, CAT_LABELS.get(cat, cat)
	]
	_desc_stats.text = stats_str

	var dmg:       int = spell_data.get("damage_hp", 0)
	var heal:      int = spell_data.get("heal_hp", 0)
	var give_food: int = spell_data.get("give_food", 0)
	var give_drink:int = spell_data.get("give_drink", 0)
	var give_gold: int = spell_data.get("give_money", 0)
	var summon:    int = spell_data.get("summon_creature", 0)

	if dmg > 0:
		_desc_dmg.text = "Damage: %d HP" % dmg
		_desc_dmg.add_theme_color_override("font_color", Color(0.90, 0.25, 0.20, 1.0))
	elif heal > 0:
		_desc_dmg.text = "Heals: %d HP" % heal
		_desc_dmg.add_theme_color_override("font_color", Color(0.25, 0.82, 0.35, 1.0))
	elif give_food > 0 or give_drink > 0:
		_desc_dmg.text = "Food +%d  Drink +%d" % [give_food, give_drink]
		_desc_dmg.add_theme_color_override("font_color", Color(0.70, 0.90, 0.30, 1.0))
	elif give_gold > 0:
		_desc_dmg.text = "Grants: %d gold" % give_gold
		_desc_dmg.add_theme_color_override("font_color", Color(0.88, 0.70, 0.22, 1.0))
	elif summon > 0:
		var sname: String = spell_data.get("summon_name", "Creature")
		var scount: int   = spell_data.get("summon_count", 1)
		var sdur: float   = spell_data.get("status_dur", 0.0)
		_desc_dmg.text = "Summons: %d × %s  (%.0fs)" % [scount, sname, sdur]
		_desc_dmg.add_theme_color_override("font_color", Color(1.0, 0.75, 0.2, 1.0))
	else:
		_desc_dmg.text = ""

	_update_cooldown_hint()


func _update_cooldown_hint() -> void:
	var cd_hint := _panel.get_node_or_null("CdHint") as Label
	if cd_hint == null or _selected_spell_id <= 0:
		return
	if not PlayerState.is_spell_ready(_selected_spell_id):
		var rem := PlayerState.get_cooldown_remaining(_selected_spell_id)
		cd_hint.text = "On cooldown: %.1fs" % rem
		cd_hint.add_theme_color_override("font_color", C_DIM)
	else:
		cd_hint.text = "Ready"
		cd_hint.add_theme_color_override("font_color", Color(0.25, 0.80, 0.30, 1.0))


func _clear_detail() -> void:
	_desc_name.text  = ""
	_desc_text.text  = ""
	_desc_stats.text = ""
	_desc_dmg.text   = ""
	var cd_hint := _panel.get_node_or_null("CdHint") as Label
	if cd_hint:
		cd_hint.text = ""


# ---------------------------------------------------------------------------
# Hotbar assignment
# ---------------------------------------------------------------------------

func _on_assign(slot_idx: int) -> void:
	if _selected_spell_id <= 0:
		return
	PlayerState.assign_hotbar(slot_idx, _selected_spell_id)
	var btn: Button = _assign_btns[slot_idx]
	btn.text = "✓"
	btn.add_theme_color_override("font_color", Color(0.25, 0.82, 0.30, 1.0))
	_assign_flash_btn   = btn
	_assign_flash_timer = 1.2


# ---------------------------------------------------------------------------
# Window dragging
# ---------------------------------------------------------------------------

func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging    = event.pressed and event.position.y <= 34.0
			_drag_offset = event.position
	elif event is InputEventMouseMotion and _dragging:
		_panel.position += event.relative


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


func _hsep(parent: Node, y: float) -> void:
	var sep := ColorRect.new()
	sep.color    = C_SEP
	sep.position = Vector2(0, y)
	sep.size     = Vector2(PANEL_W, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sep)
