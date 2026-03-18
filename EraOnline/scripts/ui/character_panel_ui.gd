class_name CharacterPanelUI
extends CanvasLayer
## Era Online — Unified Character Panel (C key)
## Six tabs: Overview · Equipment · Skills · Abilities · Spells · Quests
## Single window replacing separate SkillsUI, SpellbookUI, and fragmented stat views.

# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------
const C_BG       := Color(0.07, 0.05, 0.02, 0.98)
const C_EDGE     := Color(0.52, 0.38, 0.12, 1.00)
const C_SECTION  := Color(0.11, 0.08, 0.03, 1.00)
const C_SEP      := Color(0.35, 0.25, 0.08, 0.55)
const C_GOLD     := Color(0.88, 0.68, 0.18, 1.00)
const C_GOLD_DIM := Color(0.60, 0.44, 0.12, 1.00)
const C_TEXT     := Color(0.92, 0.86, 0.70, 1.00)
const C_DIM      := Color(0.52, 0.46, 0.32, 1.00)
const C_LOCKED   := Color(0.40, 0.36, 0.25, 0.70)
const C_LEARNED  := Color(0.32, 0.82, 0.38, 1.00)
const C_TAB_ON   := Color(0.18, 0.13, 0.05, 1.00)
const C_TAB_OFF  := Color(0.09, 0.06, 0.02, 1.00)
const C_HP       := Color(0.82, 0.14, 0.10, 1.00); const C_HP_BG  := Color(0.22, 0.04, 0.03, 1.00)
const C_MP       := Color(0.16, 0.32, 0.85, 1.00); const C_MP_BG  := Color(0.04, 0.07, 0.22, 1.00)
const C_STA      := Color(0.18, 0.70, 0.22, 1.00); const C_STA_BG := Color(0.03, 0.16, 0.04, 1.00)
const C_XP       := Color(0.62, 0.28, 0.82, 1.00); const C_XP_BG  := Color(0.12, 0.04, 0.18, 1.00)

const SKILL_COLORS := {
	"Combat":    Color(0.90, 0.28, 0.20),
	"Gathering": Color(0.90, 0.58, 0.12),
	"Crafting":  Color(0.82, 0.68, 0.12),
	"Magic":     Color(0.30, 0.52, 0.95),
	"Thief":     Color(0.62, 0.28, 0.85),
	"Social":    Color(0.28, 0.78, 0.40),
	"Ranger":    Color(0.28, 0.72, 0.52),
}

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
const VW := 1280.0;  const VH := 720.0
const PW := 700;     const PH := 540
const TAB_H := 34;   const CONTENT_Y := TAB_H + 1

const TABS := ["Overview", "Equipment", "Skills", "Abilities", "Spells", "Quests", "Achieve"]

# Skill categories with their slot ranges (1-based)
const SKILL_CATEGORIES := [
	["Combat",    ["Swordsmanship","Tactics","Parrying","Archery"]],
	["Gathering", ["Mining","Lumberjacking","Fishing"]],
	["Crafting",  ["Blacksmithing","Carpenting","Tailoring","Cooking"]],
	["Magic",     ["Magery","Religion Lore","Healing","Meditating"]],
	["Thief",     ["Hiding","Stealth","Backstabbing","Pickpocketing","Lockpicking","Poisoning","Disguise"]],
	["Social",    ["Merchant","Musicianship","Etiquette","Streetwise"]],
	["Ranger",    ["Animal Taming","Surviving"]],
]

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _panel: Panel       = null
var _content: Control   = null   ## Swapped per tab
var _tab_btns: Array[Button] = []
var _current_tab: int   = 0

var _drag_active: bool   = false
var _drag_offset: Vector2 = Vector2.ZERO

## Assign-mode: user clicked "Assign" on an ability/spell; waiting for slot pick
var _assign_pending: Dictionary = {}  ## {type, id} or empty
var _assign_row: Control = null       ## The slot-picker row shown during assign

## Live references for refreshable widgets
var _ov_hp_fill: ColorRect = null; var _ov_mp_fill: ColorRect = null; var _ov_sta_fill: ColorRect = null
var _ov_hp_lbl: Label = null; var _ov_mp_lbl: Label = null; var _ov_sta_lbl: Label = null
var _ov_stat_labels: Dictionary = {}   ## "hp", "mp", "sta", "str", etc. → Label


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 15
	_build_panel()
	visible = false
	# Connect PlayerState signals for live refreshes
	PlayerState.stats_changed.connect(_on_stats_changed)
	PlayerState.equipment_changed.connect(func(): if visible and _current_tab == 1: _switch_tab(1))
	PlayerState.skills_changed.connect(func(_s,_v): if visible and _current_tab == 2: _switch_tab(2))
	PlayerState.spellbook_changed.connect(func(): if visible and _current_tab == 4: _switch_tab(4))
	Network.on_ability_shop.connect(func(_a): pass)  ## handled by trainer_ui
	set_process_unhandled_key_input(true)


func _unhandled_key_input(event: InputEvent) -> void:
	# ESC closes the panel; KEY_C toggle is handled by world_map to avoid double-fire.
	if not event is InputEventKey or not (event as InputEventKey).pressed:
		return
	if (event as InputEventKey).physical_keycode == KEY_ESCAPE and visible:
		hide()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func toggle() -> void:
	if visible:
		hide()
	else:
		_switch_tab(_current_tab)
		show()


func open_tab(tab_idx: int) -> void:
	_switch_tab(tab_idx)
	show()


# ---------------------------------------------------------------------------
# Build panel
# ---------------------------------------------------------------------------

func _build_panel() -> void:
	_panel = Panel.new()
	_panel.size     = Vector2(PW, PH)
	_panel.position = Vector2((VW - PW) / 2.0, (VH - PH) / 2.0)
	_panel.add_theme_stylebox_override("panel", _box(C_BG, C_EDGE, 2, 6))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_on_panel_input)
	add_child(_panel)

	# Title bar background
	var title_bg := ColorRect.new()
	title_bg.color    = Color(C_BG.r * 0.7, C_BG.g * 0.7, C_BG.b * 0.7, 1.0)
	title_bg.size     = Vector2(PW, TAB_H)
	title_bg.position = Vector2.ZERO
	title_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(title_bg)

	# Tab buttons
	var tab_w := PW / TABS.size()
	for i in TABS.size():
		var btn := Button.new()
		btn.text = TABS[i]
		btn.flat = true
		btn.size     = Vector2(tab_w - 1, TAB_H - 1)
		btn.position = Vector2(i * tab_w, 0)
		btn.add_theme_font_size_override("font_size", 12)
		btn.add_theme_color_override("font_color",        C_TEXT)
		btn.add_theme_color_override("font_color_hover",  C_GOLD)
		btn.add_theme_color_override("font_color_pressed",C_GOLD)
		btn.add_theme_stylebox_override("normal",   _box(C_TAB_OFF, Color(0,0,0,0), 0, 0))
		btn.add_theme_stylebox_override("hover",    _box(Color(C_TAB_ON.r*1.5, C_TAB_ON.g*1.5, C_TAB_ON.b*1.5, 1), Color(0,0,0,0), 0, 0))
		btn.add_theme_stylebox_override("pressed",  _box(C_TAB_ON,  C_EDGE, 1, 0))
		btn.add_theme_stylebox_override("focus",    _box(C_TAB_OFF, Color(0,0,0,0), 0, 0))
		btn.pressed.connect(_switch_tab.bind(i))
		_panel.add_child(btn)
		_tab_btns.append(btn)

	# Tab underline
	var tul := ColorRect.new()
	tul.color    = C_EDGE
	tul.size     = Vector2(PW, 1); tul.position = Vector2(0, TAB_H)
	tul.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(tul)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.size = Vector2(28, 28); close_btn.position = Vector2(PW - 30, 3)
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.add_theme_color_override("font_color",       C_DIM)
	close_btn.add_theme_color_override("font_color_hover", Color(0.95, 0.35, 0.25))
	close_btn.add_theme_stylebox_override("normal",  _box(Color(0,0,0,0), Color(0,0,0,0), 0, 0))
	close_btn.add_theme_stylebox_override("hover",   _box(Color(0,0,0,0), Color(0,0,0,0), 0, 0))
	close_btn.add_theme_stylebox_override("focus",   _box(Color(0,0,0,0), Color(0,0,0,0), 0, 0))
	close_btn.pressed.connect(hide)
	_panel.add_child(close_btn)

	# Content area placeholder
	_content = Control.new()
	_content.position = Vector2(0, CONTENT_Y)
	_content.size     = Vector2(PW, PH - CONTENT_Y)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_content)


# ---------------------------------------------------------------------------
# Tab switching
# ---------------------------------------------------------------------------

func _switch_tab(idx: int) -> void:
	_current_tab = idx
	for i in _tab_btns.size():
		_tab_btns[i].add_theme_stylebox_override("normal",
			_box(C_TAB_ON if i == idx else C_TAB_OFF,
			     C_EDGE   if i == idx else Color(0,0,0,0),
			     1 if i == idx else 0, 0))

	# Clear content and stale node refs
	_ov_hp_fill = null; _ov_mp_fill = null; _ov_sta_fill = null
	for ch in _content.get_children():
		ch.queue_free()
	_assign_pending = {}

	match idx:
		0: _build_overview()
		1: _build_equipment()
		2: _build_skills()
		3: _build_abilities()
		4: _build_spells()
		5: _build_quests()
		6: _build_achievements()


# ---------------------------------------------------------------------------
# Tab 0: Overview
# ---------------------------------------------------------------------------

func _build_overview() -> void:
	var s := PlayerState.stats
	var lvl: int = s.get("level", 1)

	# Left column: identity + bars
	var left := _add_container(_content, 12, 10, 280, PH - CONTENT_Y - 20)

	_add_label(left, "CHARACTER", 0, 0, 256, 20, C_GOLD, 13, true)
	_add_sep(left, 0, 22, 256)

	var name_lbl := _add_label(left, s.get("char_name", "Hero"), 0, 28, 256, 22, C_TEXT, 16, false)
	name_lbl.add_theme_color_override("font_color", C_GOLD)

	_add_label(left, "Level %d" % lvl, 0, 52, 256, 16, C_DIM, 11)

	_add_sep(left, 0, 72, 256)

	# HP/MP/STA bars
	_ov_hp_fill  = _add_bar_row(left,  78, "HP",  s.get("hp",0),  s.get("max_hp",1),  C_HP,  C_HP_BG,  256)
	_ov_mp_fill  = _add_bar_row(left,  98, "MP",  s.get("mp",0),  s.get("max_mp",1),  C_MP,  C_MP_BG,  256)
	_ov_sta_fill = _add_bar_row(left, 118, "STA", s.get("sta",0), s.get("max_sta",1), C_STA, C_STA_BG, 256)
	_add_bar_row(left, 140, "XP", s.get("exp",0), s.get("next_exp",300), C_XP, C_XP_BG, 256)

	_add_sep(left, 0, 162, 256)
	_add_label(left, "Gold:  %d" % s.get("gold", 0), 0, 167, 256, 16, C_GOLD_DIM, 12)

	# Right column: combat stats
	var right := _add_container(_content, 306, 10, 380, PH - CONTENT_Y - 20)
	_add_label(right, "COMBAT STATS", 0, 0, 360, 20, C_GOLD, 13, true)
	_add_sep(right, 0, 22, 360)

	var stat_rows := [
		["Strength",   "str",     "Agility",    "agi"],
		["Intellect",  "int_",    "Charisma",   "cha"],
		["Min. Hit",   "min_hit", "Max. Hit",   "max_hit"],
		["Defense",    "def",     "Night Sight","night_sight"],
	]
	var ry := 30
	for row in stat_rows:
		_add_stat_pair(right, ry, row[0], s.get(row[1], 0), row[2], s.get(row[3], 0), 360)
		ry += 24

	_add_sep(right, 0, ry + 4, 360)
	ry += 14
	_add_label(right, "HP Max:   %d    MP Max:   %d    STA Max:   %d" % [
		s.get("max_hp", 0), s.get("max_mp", 0), s.get("max_sta", 0)
	], 0, ry, 360, 16, C_DIM, 11)


func _add_bar_row(parent: Control, y: int, label: String, cur: int, mx: int,
		fill_c: Color, bg_c: Color, w: int) -> ColorRect:
	var lbl := _add_label(parent, label, 0, y, 28, 14, C_DIM, 9)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var bx := 32
	var bg := ColorRect.new(); bg.color = bg_c; bg.size = Vector2(w - bx, 14); bg.position = Vector2(bx, y); parent.add_child(bg)
	var fi := ColorRect.new(); fi.color = fill_c
	var frac := clampf(float(cur) / float(maxi(mx, 1)), 0.0, 1.0)
	fi.size = Vector2((w - bx) * frac, 14); fi.position = Vector2(bx, y); parent.add_child(fi)
	var vl := Label.new(); vl.text = "%d / %d" % [cur, mx]
	vl.add_theme_font_size_override("font_size", 9)
	vl.add_theme_color_override("font_color", Color(1,1,1,0.90))
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vl.size = Vector2(w - bx, 14); vl.position = Vector2(bx, y); parent.add_child(vl)
	return fi


func _add_stat_pair(parent: Control, y: int,
		lbl1: String, val1: int, lbl2: String, val2: int, w: int) -> void:
	var hw := w / 2
	_add_label(parent, lbl1,           0,  y, hw - 4, 16, C_DIM,  11)
	_add_label(parent, str(val1),   hw - 60, y, 56,     16, C_TEXT, 12)
	_add_label(parent, lbl2,          hw,  y, hw - 4, 16, C_DIM,  11)
	_add_label(parent, str(val2), hw * 2 - 60, y, 56,   16, C_TEXT, 12)


func _on_stats_changed() -> void:
	if not visible or _current_tab != 0:
		return
	var s := PlayerState.stats
	if is_instance_valid(_ov_hp_fill):  _ov_hp_fill.size.x  = 256 * clampf(float(s.get("hp",0))  / float(maxi(s.get("max_hp",1),1)),  0.0, 1.0)
	if is_instance_valid(_ov_mp_fill):  _ov_mp_fill.size.x  = 256 * clampf(float(s.get("mp",0))  / float(maxi(s.get("max_mp",1),1)),  0.0, 1.0)
	if is_instance_valid(_ov_sta_fill): _ov_sta_fill.size.x = 256 * clampf(float(s.get("sta",0)) / float(maxi(s.get("max_sta",1),1)), 0.0, 1.0)


# ---------------------------------------------------------------------------
# Tab 1: Equipment
# ---------------------------------------------------------------------------

func _build_equipment() -> void:
	const SLOTS := ["weapon", "shield", "armor", "helmet", "boots"]
	const SLOT_LABELS := {"weapon":"Weapon","shield":"Shield","armor":"Armor","helmet":"Helmet","boots":"Boots"}
	const SLOT_ICONS  := {"weapon":"⚔","shield":"🛡","armor":"🥋","helmet":"⛑","boots":"👢"}

	_add_label(_content, "EQUIPPED ITEMS", 12, 10, PW - 24, 20, C_GOLD, 13, true)
	_add_sep(_content, 12, 32, PW - 24)

	var ey := 40
	for slot_key in SLOTS:
		var obj_idx: int = PlayerState.equipment.get(slot_key, 0)
		var icon: String = SLOT_ICONS.get(slot_key, "·")
		var slot_lbl: String = SLOT_LABELS.get(slot_key, slot_key)
		var item_name: String = "Empty"
		var has_item := obj_idx > 0
		if has_item:
			var obj := GameData.get_object(obj_idx)
			item_name = obj.get("name", "Unknown")

		var row := _add_container(_content, 12, ey, PW - 24, 40)
		row.add_theme_stylebox_override("panel", _box(
			Color(0.11, 0.08, 0.03, 0.90) if has_item else Color(0.07, 0.05, 0.02, 0.70),
			C_EDGE if has_item else C_SEP, 1, 4))

		var icon_lbl := Label.new(); icon_lbl.text = icon
		icon_lbl.add_theme_font_size_override("font_size", 18)
		icon_lbl.size = Vector2(36, 36); icon_lbl.position = Vector2(6, 2)
		icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		row.add_child(icon_lbl)

		_add_label(row, slot_lbl,  46, 4,  80,  14, C_DIM,  10)
		_add_label(row, item_name, 46, 18, PW - 160, 18,
			C_TEXT if has_item else C_LOCKED, 13 if has_item else 12)

		if has_item:
			var obj := GameData.get_object(obj_idx)
			var detail := ""
			var ot: int = obj.get("obj_type", 0)
			match ot:
				2: detail = "Dmg: %d-%d" % [obj.get("min_hit",0), obj.get("max_hit",0)]
				3: detail = "Def: %d" % obj.get("def_bonus", obj.get("def", 0))
				4: detail = "Def: %d" % obj.get("def_bonus", obj.get("def", 0))
				13,14: detail = "Def: %d" % obj.get("def_bonus", obj.get("def", 0))
			if detail != "":
				_add_label(row, detail, PW - 190, 12, 130, 16, C_DIM, 11)

			var un_btn := Button.new(); un_btn.text = "Unequip"
			un_btn.size = Vector2(72, 26); un_btn.position = Vector2(PW - 100, 7)
			un_btn.add_theme_font_size_override("font_size", 10)
			un_btn.add_theme_stylebox_override("normal",   _box(Color(0.15,0.1,0.04,1), C_EDGE, 1, 3))
			un_btn.add_theme_stylebox_override("hover",    _box(Color(0.25,0.17,0.06,1), C_GOLD, 1, 3))
			un_btn.add_theme_stylebox_override("focus",    _box(Color(0.15,0.1,0.04,1), C_EDGE, 1, 3))
			un_btn.add_theme_color_override("font_color", C_TEXT)
			# Find inventory slot index for this equipped item to send to server
			var uneq_obj_idx: int = obj_idx
			un_btn.pressed.connect(func():
				if Network.state == Network.State.CONNECTED:
					# Find the inv slot that holds this equipped item
					for inv_i in PlayerState.inventory.size():
						var inv_slot = PlayerState.inventory[inv_i]
						if inv_slot is Dictionary and inv_slot.get("obj_index", inv_slot.get("obj_idx", 0)) == uneq_obj_idx:
							Network.send_unequip(inv_i)
							return
				else:
					PlayerState.unequip_slot(slot_key)
			)
			row.add_child(un_btn)

		ey += 46

	# Stats summary
	_add_sep(_content, 12, ey + 4, PW - 24)
	var s := PlayerState.stats
	_add_label(_content, "Attack: %d-%d   Defense: %d   Level: %d" % [
		s.get("min_hit",0), s.get("max_hit",0), s.get("def",0), s.get("level",1)
	], 12, ey + 14, PW - 24, 18, C_DIM, 12)


# ---------------------------------------------------------------------------
# Tab 2: Skills
# ---------------------------------------------------------------------------

func _build_skills() -> void:
	_add_label(_content, "SKILLS & PROGRESSION", 12, 10, PW - 24, 20, C_GOLD, 13, true)
	_add_sep(_content, 12, 32, PW - 24)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(6, 38); scroll.size = Vector2(PW - 12, PH - CONTENT_Y - 50)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	var skill_slot := 1  # 1-based skill slot counter

	for cat_entry in SKILL_CATEGORIES:
		var cat_name: String = cat_entry[0]
		var skill_names: Array = cat_entry[1]
		var cat_col: Color = SKILL_COLORS.get(cat_name, C_GOLD)

		# Category header
		var hdr := Panel.new()
		hdr.custom_minimum_size = Vector2(PW - 24, 22)
		hdr.add_theme_stylebox_override("panel", _box(Color(cat_col.r*0.18, cat_col.g*0.18, cat_col.b*0.18, 1.0), cat_col, 1, 3))
		vbox.add_child(hdr)
		var hl := Label.new(); hl.text = cat_name.to_upper()
		hl.add_theme_font_size_override("font_size", 11); hl.add_theme_color_override("font_color", cat_col)
		hl.size = Vector2(PW - 24, 22); hl.position = Vector2(8, 3)
		hl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hdr.add_child(hl)

		# Skills in 2-column grid
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 4)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(grid)

		for sn in skill_names:
			var level: int = PlayerState.get_skill(skill_slot)
			var xp:    int = PlayerState.skill_xp[skill_slot - 1]     if PlayerState.skill_xp.size() >= skill_slot else 0
			var xpn:   int = PlayerState.skill_xp_needed[skill_slot-1] if PlayerState.skill_xp_needed.size() >= skill_slot else 100

			var row := Panel.new()
			row.custom_minimum_size = Vector2(0, 28)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_theme_stylebox_override("panel", _box(Color(0.10,0.07,0.03,0.80), C_SEP, 1, 3))
			grid.add_child(row)

			_add_label(row, sn, 6, 4, 120, 14, C_TEXT, 11)
			_add_label(row, str(level), 130, 4, 30, 14, C_GOLD, 12)
			# XP bar
			var xp_bg := ColorRect.new(); xp_bg.color = Color(0.12,0.04,0.18,1)
			xp_bg.size = Vector2(110, 8); xp_bg.position = Vector2(168, 10); row.add_child(xp_bg)
			var xp_fi := ColorRect.new(); xp_fi.color = C_XP
			xp_fi.size = Vector2(110 * clampf(float(xp)/float(maxi(xpn,1)),0,1), 8)
			xp_fi.position = Vector2(168, 10); row.add_child(xp_fi)
			_add_label(row, "%d/%d" % [xp, xpn], 168, 2, 110, 12, Color(0.6,0.4,0.8,0.8), 8)

			skill_slot += 1


# ---------------------------------------------------------------------------
# Tab 3: Abilities
# ---------------------------------------------------------------------------

func _build_abilities() -> void:
	_add_label(_content, "COMBAT ABILITIES", 12, 10, PW - 320, 20, C_GOLD, 13, true)
	_add_label(_content, "Right-click slot to remove  ·  Drag: C → hotbar slot", PW - 310, 14, 300, 14, C_DIM, 10)
	_add_sep(_content, 12, 32, PW - 24)

	var list_h := PH - CONTENT_Y - 130

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(6, 38); scroll.size = Vector2(PW - 12, list_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	scroll.add_child(vbox)

	# Get all known abilities from GameData, split melee vs ranged
	var melee_abilities: Array = []
	var ranged_abilities: Array = []
	for i in 30:  # scan IDs 0-29
		var ab: Dictionary = GameData.get_ability(i)
		if not ab.is_empty():
			if ab.get("req_skill_id", 0) == 28:
				ranged_abilities.append(ab)
			else:
				melee_abilities.append(ab)

	# Section header helper
	var _hdr_col_melee := Color(0.90, 0.28, 0.20)
	var _hdr_col_range := Color(0.25, 0.72, 0.28)

	for section in [["MELEE & PHYSICAL", _hdr_col_melee, melee_abilities],
					["RANGED  (requires bow + arrows)", _hdr_col_range, ranged_abilities]]:
		var sec_label: String = section[0]
		var sec_col: Color    = section[1]
		var sec_abs: Array    = section[2]

		# Section header
		var hdr := Panel.new()
		hdr.custom_minimum_size = Vector2(PW - 24, 22)
		hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hdr.add_theme_stylebox_override("panel", _box(
			Color(sec_col.r * 0.18, sec_col.g * 0.18, sec_col.b * 0.18, 1.0), sec_col, 1, 3))
		vbox.add_child(hdr)
		var hl := Label.new(); hl.text = sec_label
		hl.add_theme_font_size_override("font_size", 11)
		hl.add_theme_color_override("font_color", sec_col)
		hl.size = Vector2(PW - 24, 22); hl.position = Vector2(8, 3)
		hl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hdr.add_child(hl)

		var plvl: int = PlayerState.stats.get("level", 1)
		for ab in sec_abs:
			var ab_id:  int  = ab.get("id", 0)
			var learned: bool = PlayerState.has_ability(ab_id)
			var req_lvl: int  = ab.get("req_level", 0)
			var req_sk:  int  = ab.get("req_skill_id", 0)
			var req_skv: int  = ab.get("req_skill_val", 0)
			var psk: int      = PlayerState.get_skill(req_sk) if req_sk > 0 else 0
			var meets: bool   = (plvl >= req_lvl) and (req_sk == 0 or psk >= req_skv)
			_build_action_row(vbox, ab_id, "ability", ab, learned, meets)

	# Description / assign area at bottom
	_add_sep(_content, 6, 38 + list_h + 4, PW - 12)
	_build_assign_area(_content, 38 + list_h + 10)


func _build_action_row(parent: VBoxContainer, entry_id: int, entry_type: String,
		data: Dictionary, learned: bool, meets_req: bool) -> void:
	var name_str: String = data.get("name", "???")
	var cost_str: String = ""
	var req_str:  String = ""

	if entry_type == "ability":
		var cost: int = data.get("sta_cost", 0)
		cost_str = "%dSTA" % cost if cost > 0 else ""
		var rl: int = data.get("req_level", 0)
		var rs: int = data.get("req_skill_id", 0); var rsv: int = data.get("req_skill_val", 0)
		if rl > 0 or rs > 0:
			req_str = "Req: "
			if rl > 0: req_str += "Lv%d" % rl
			if rs > 0: req_str += " Sk%d≥%d" % [rs, rsv]
	else:  # spell
		cost_str = "%dMP" % data.get("needs_mana", 0)
		# No extra req display for spells here

	var row := Panel.new()
	row.custom_minimum_size = Vector2(0, 32)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bg_col: Color
	if learned:     bg_col = Color(0.12, 0.09, 0.04, 0.90)
	elif meets_req: bg_col = Color(0.10, 0.07, 0.03, 0.80)
	else:           bg_col = Color(0.08, 0.06, 0.02, 0.60)
	row.add_theme_stylebox_override("panel", _box(bg_col, C_SEP, 1, 3))
	parent.add_child(row)

	# Learned indicator
	var ind := Label.new()
	ind.text = "✓" if learned else ("·" if meets_req else "✗")
	ind.add_theme_font_size_override("font_size", 14)
	ind.add_theme_color_override("font_color", C_LEARNED if learned else (C_DIM if meets_req else C_LOCKED))
	ind.size = Vector2(20, 30); ind.position = Vector2(4, 1)
	ind.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(ind)

	# Name
	_add_label(row, name_str, 26, 8, 160, 18, C_TEXT if (learned or meets_req) else C_LOCKED, 12)

	# Cost
	if cost_str != "":
		var c_col: Color = C_STA if entry_type == "ability" else C_MP
		_add_label(row, cost_str, 192, 8, 56, 16, c_col, 11)

	# Req / "Known" label
	if learned:
		_add_label(row, "Learned", 254, 8, 70, 16, C_LEARNED, 10)
	elif req_str != "":
		_add_label(row, req_str, 254, 8, 150, 16, C_LOCKED, 10)

	# Assign button
	if learned:
		var ab_btn := Button.new(); ab_btn.text = "Assign →"
		ab_btn.size = Vector2(74, 24); ab_btn.position = Vector2(PW - 100, 4)
		ab_btn.add_theme_font_size_override("font_size", 10)
		ab_btn.add_theme_stylebox_override("normal",  _box(Color(0.16,0.11,0.04,1), C_EDGE,1,3))
		ab_btn.add_theme_stylebox_override("hover",   _box(Color(0.28,0.20,0.07,1), C_GOLD,1,3))
		ab_btn.add_theme_stylebox_override("focus",   _box(Color(0.16,0.11,0.04,1), C_EDGE,1,3))
		ab_btn.add_theme_color_override("font_color", C_TEXT)
		ab_btn.pressed.connect(_on_assign_pressed.bind(entry_type, entry_id, data.get("name","?")))
		row.add_child(ab_btn)


# ---------------------------------------------------------------------------
# Tab 4: Spells
# ---------------------------------------------------------------------------

func _build_spells() -> void:
	_add_label(_content, "SPELLBOOK", 12, 10, PW - 24, 20, C_GOLD, 13, true)
	_add_sep(_content, 12, 32, PW - 24)

	var list_h := PH - CONTENT_Y - 130

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(6, 38); scroll.size = Vector2(PW - 12, list_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	scroll.add_child(vbox)

	const TARGET_LABELS := {0:"Self",1:"Enemy",2:"Ally",3:"Ground",4:"Area"}
	const TYPE_COLORS   := {0:Color(0.3,0.8,0.3),1:Color(1.0,0.3,0.3),2:Color(0.3,0.6,1.0),3:Color(1.0,0.7,0.2),4:Color(0.9,0.4,1.0)}

	# Get all known and available spells
	var all_spell_ids: Array[int] = []
	for sid in PlayerState.learned_spells:
		if not all_spell_ids.has(sid):
			all_spell_ids.append(sid)

	if all_spell_ids.is_empty():
		_add_label(vbox, "No spells learned yet. Visit an Arcane Vendor or spell trainer.", 8, 8, PW - 28, 32, C_DIM, 12)
	else:
		for sid in all_spell_ids:
			var sp: Dictionary = GameData.get_spell(sid)
			if sp.is_empty():
				continue
			var nm:   String = sp.get("name", "Spell")
			var mana: int    = sp.get("needs_mana", 0)
			var tt:   int    = sp.get("target_type", 0)
			var tl:   String = TARGET_LABELS.get(tt, "")
			var tc:   Color  = TYPE_COLORS.get(tt, C_DIM)

			var row := Panel.new()
			row.custom_minimum_size = Vector2(0, 32)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_theme_stylebox_override("panel", _box(Color(0.12,0.09,0.04,0.90), C_SEP, 1, 3))
			vbox.add_child(row)

			_add_label(row, "✓", 4, 8, 20, 18, C_LEARNED, 13)
			_add_label(row, nm, 26, 8, 180, 18, C_TEXT, 12)
			_add_label(row, "%dMP" % mana, 212, 8, 56, 16, C_MP, 11)
			_add_label(row, tl, 272, 8, 50, 16, tc, 11)

			var ab_btn := Button.new(); ab_btn.text = "Assign →"
			ab_btn.size = Vector2(74, 24); ab_btn.position = Vector2(PW - 100, 4)
			ab_btn.add_theme_font_size_override("font_size", 10)
			ab_btn.add_theme_stylebox_override("normal",  _box(Color(0.10,0.08,0.14,1), Color(0.28,0.45,1.00),1,3))
			ab_btn.add_theme_stylebox_override("hover",   _box(Color(0.18,0.14,0.28,1), C_GOLD,1,3))
			ab_btn.add_theme_stylebox_override("focus",   _box(Color(0.10,0.08,0.14,1), Color(0.28,0.45,1.00),1,3))
			ab_btn.add_theme_color_override("font_color", C_TEXT)
			ab_btn.pressed.connect(_on_assign_pressed.bind("spell", sid, nm))
			row.add_child(ab_btn)

	_add_sep(_content, 6, 38 + list_h + 4, PW - 12)
	_build_assign_area(_content, 38 + list_h + 10)


# ---------------------------------------------------------------------------
# Tab 5: Quests
# ---------------------------------------------------------------------------

func _build_quests() -> void:
	_add_label(_content, "ACTIVE QUESTS", 12, 10, PW - 24, 20, C_GOLD, 13, true)
	_add_sep(_content, 12, 32, PW - 24)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(6, 38); scroll.size = Vector2(PW - 12, PH - CONTENT_Y - 50)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	var quests: Dictionary = {}
	if "active_quests" in PlayerState:
		quests = PlayerState.active_quests

	if quests.is_empty():
		_add_label(vbox, "No active quests. Talk to NPCs with  !  markers to begin quests.", 8, 8, PW - 28, 32, C_DIM, 12)
	else:
		for qid in quests:
			var qd: Dictionary = quests[qid]
			var qname: String = qd.get("name", "Quest")
			var qdesc: String = qd.get("objectives_str", "")

			var qrow := Panel.new()
			qrow.custom_minimum_size = Vector2(0, 54)
			qrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			qrow.add_theme_stylebox_override("panel", _box(Color(0.12,0.09,0.04,0.90), C_SEP, 1, 4))
			vbox.add_child(qrow)

			_add_label(qrow, qname,  8, 6,  PW - 40, 18, C_GOLD, 13)
			_add_label(qrow, qdesc,  8, 26, PW - 40, 22, C_DIM,  11)


# ---------------------------------------------------------------------------
# Tab 6: Achievements
# ---------------------------------------------------------------------------

func _build_achievements() -> void:
	_add_label(_content, "ACHIEVEMENTS", 12, 10, PW - 24, 20, C_GOLD, 13, true)
	_add_sep(_content, 12, 32, PW - 24)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(6, 38); scroll.size = Vector2(PW - 12, PH - CONTENT_Y - 50)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	# Pull unlocked list from the AchievementUI node (sibling child of WorldMap)
	var unlocked: Array = []
	var par := get_parent()
	if par != null:
		var ach_ui := par.get_node_or_null("AchievementUI")
		if ach_ui != null:
			var v = ach_ui.get("_unlocked")
			if v is Array:
				unlocked = v

	if unlocked.is_empty():
		_add_label(vbox, "No achievements unlocked yet. Keep playing to earn them!", 8, 8, PW - 28, 32, C_DIM, 12)
	else:
		for ach in unlocked:
			var arow := Panel.new()
			arow.custom_minimum_size = Vector2(0, 52)
			arow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			arow.add_theme_stylebox_override("panel", _box(Color(0.14, 0.10, 0.04, 0.92), C_EDGE, 1, 4))
			vbox.add_child(arow)

			_add_label(arow, "★  " + ach.get("name", "?"), 8, 6, PW - 40, 18, C_GOLD, 13)
			_add_label(arow, ach.get("desc", ""), 8, 28, PW - 40, 18, C_DIM, 11)

	# Summary footer
	_add_sep(_content, 12, PH - CONTENT_Y - 46, PW - 24)
	_add_label(_content, "Unlocked: %d" % unlocked.size(), 12, PH - CONTENT_Y - 36, PW - 24, 18, C_GOLD_DIM, 12)


# ---------------------------------------------------------------------------
# Assign area (shared by Abilities and Spells tabs)
# ---------------------------------------------------------------------------

func _build_assign_area(parent: Control, y: int) -> void:
	var area_h := PH - CONTENT_Y - y - 8
	var lbl := _add_label(parent, "Assign to slot:", 12, y + 4, 110, 20, C_DIM, 11)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# 10 slot buttons [1][2]...[9][0]
	for i in 10:
		var sk := (i + 1) % 10
		var entry = PlayerState.get_unified_hotbar_slot(i)
		var occupied := entry != null
		var slot_btn := Button.new()
		slot_btn.text = str(sk)
		slot_btn.size = Vector2(36, 28)
		slot_btn.position = Vector2(126 + i * 40, y + 2)
		slot_btn.add_theme_font_size_override("font_size", 12)
		var bg_c := Color(0.22, 0.16, 0.07, 1) if occupied else Color(0.09, 0.06, 0.02, 1)
		var bd_c := C_GOLD_DIM if occupied else C_SEP
		slot_btn.add_theme_stylebox_override("normal",  _box(bg_c, bd_c, 1, 3))
		slot_btn.add_theme_stylebox_override("hover",   _box(Color(0.28,0.20,0.07,1), C_GOLD, 1, 3))
		slot_btn.add_theme_stylebox_override("focus",   _box(bg_c, bd_c, 1, 3))
		slot_btn.add_theme_color_override("font_color", C_GOLD if occupied else C_DIM)
		slot_btn.pressed.connect(_on_slot_pick.bind(i))
		parent.add_child(slot_btn)

	var hint := _add_label(parent, "Click Assign → on an ability/spell above, then pick a slot.", 12, y + 36, PW - 24, 16, C_DIM, 10)
	hint.name = "AssignHint"


func _on_assign_pressed(entry_type: String, entry_id: int, entry_name: String) -> void:
	_assign_pending = {"type": entry_type, "id": entry_id}
	# Flash hint label
	for child in _content.get_children():
		if child.name == "AssignHint":
			child.text = 'Assigning "%s" — click a slot number below.' % entry_name
			child.add_theme_color_override("font_color", C_GOLD)
			break


func _on_slot_pick(slot_idx: int) -> void:
	if _assign_pending.is_empty():
		return
	var stype: String = _assign_pending.get("type", "")
	var sid:   int    = _assign_pending.get("id", 0)
	PlayerState.set_unified_hotbar_slot(slot_idx, stype, sid)
	_assign_pending = {}
	# Rebuild the assign area to reflect new state
	if _current_tab == 3:
		_build_abilities()
	elif _current_tab == 4:
		_build_spells()


# ---------------------------------------------------------------------------
# Drag to move panel
# ---------------------------------------------------------------------------

func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and mb.position.y < TAB_H:
				_drag_active  = true
				_drag_offset  = mb.position
			else:
				_drag_active = false
	elif event is InputEventMouseMotion and _drag_active:
		_panel.position += (event as InputEventMouseMotion).relative


# ---------------------------------------------------------------------------
# Widget helpers
# ---------------------------------------------------------------------------

func _add_container(parent: Control, x: int, y: int, w: int, h: int) -> Panel:
	var p := Panel.new()
	p.position = Vector2(x, y); p.size = Vector2(w, h)
	p.add_theme_stylebox_override("panel", _box(C_SECTION, C_SEP, 1, 4))
	parent.add_child(p)
	return p


@warning_ignore("shadowed_variable")
func _add_label(parent: Control, text: String, x: int, y: int, w: int, h: int,
		color: Color = C_TEXT, font_size: int = 12, bold: bool = false) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.size     = Vector2(w, h)
	lbl.position = Vector2(x, y)
	lbl.clip_text = true
	parent.add_child(lbl)
	return lbl


func _add_sep(parent: Control, x: int, y: int, w: int) -> void:
	var sep := ColorRect.new()
	sep.color    = C_SEP
	sep.size     = Vector2(w, 1)
	sep.position = Vector2(x, y)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sep)


func _box(bg: Color, border: Color, bw: int, radius: int = 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.set_border_width_all(bw)
	s.corner_radius_top_left = radius; s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius; s.corner_radius_bottom_right = radius
	return s
