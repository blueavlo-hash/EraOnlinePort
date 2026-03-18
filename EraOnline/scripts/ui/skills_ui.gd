class_name SkillsUI
extends CanvasLayer
## Era Online - Skills Panel
## Press K to toggle. Dark medieval theme, grouped by category.

# ---------------------------------------------------------------------------
# Palette (matches inventory_ui)
# ---------------------------------------------------------------------------
const C_BG       := Color(0.07, 0.05, 0.03, 0.97)
const C_BORDER   := Color(0.55, 0.40, 0.12, 1.00)
const C_TITLE    := Color(0.85, 0.68, 0.22, 1.00)
const C_TEXT     := Color(0.90, 0.82, 0.62, 1.00)
const C_TEXT_DIM := Color(0.55, 0.47, 0.30, 1.00)
const C_SEP      := Color(0.40, 0.28, 0.08, 0.55)

# Category accent colours
const CAT_COLORS: Dictionary = {
	"Combat":    Color(0.85, 0.18, 0.12),
	"Gathering": Color(0.62, 0.40, 0.10),
	"Crafting":  Color(0.80, 0.62, 0.08),
	"Magic":     Color(0.28, 0.42, 0.92),
	"Thief":     Color(0.48, 0.10, 0.62),
	"Social":    Color(0.15, 0.65, 0.22),
	"Ranger":    Color(0.18, 0.52, 0.22),
}

# ---------------------------------------------------------------------------
# Skill definitions: [slot_1based, name, category]
# Grouped so we can draw section headers.
# ---------------------------------------------------------------------------
const CATEGORIES: Array = [
	["Combat",    [
		[16, "Swordsmanship"],
		[6,  "Tactics"],
		[17, "Parrying"],
		[28, "Archery"],
	]],
	["Gathering", [
		[21, "Mining"],
		[5,  "Lumberjacking"],
		[20, "Fishing"],
	]],
	["Crafting",  [
		[9,  "Blacksmithing"],
		[4,  "Carpenting"],
		[3,  "Tailoring"],
		[1,  "Cooking"],
	]],
	["Magic",     [
		[11, "Magery"],
		[19, "Religion Lore"],
		[23, "Healing"],
		[27, "Meditating"],
	]],
	["Thief",     [
		[10, "Hiding"],
		[14, "Stealth"],
		[22, "Backstabbing"],
		[13, "Pickpocketing"],
		[12, "Lockpicking"],
		[15, "Poisoning"],
		[7,  "Disguise"],
	]],
	["Social",    [
		[8,  "Merchant"],
		[2,  "Musicianship"],
		[25, "Etiquette"],
		[26, "Streetwise"],
	]],
	["Ranger",    [
		[18, "Animal Taming"],
		[24, "Surviving"],
	]],
]

const WIN_W  := 580
const WIN_H  := 580
const SCR_W  := 1280.0
const SCR_H  := 720.0

var _window:       Panel  = null
var _value_labels: Dictionary = {}   # slot → Label (shows skill level)
var _bar_fills:    Dictionary = {}   # slot → ColorRect (XP progress within current level)
var _xp_labels:    Dictionary = {}   # slot → Label (shows "XP / XP_needed")


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 9
	_build_window()
	_window.visible = false
	PlayerState.skills_changed.connect(_on_skill_changed)
	_refresh_all()


func toggle() -> void:
	_window.visible = not _window.visible
	if _window.visible:
		_refresh_all()


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build_window() -> void:
	_window = Panel.new()
	_window.position = Vector2(SCR_W / 2.0 - WIN_W / 2.0, SCR_H / 2.0 - WIN_H / 2.0)
	_window.size     = Vector2(WIN_W, WIN_H)
	_window.add_theme_stylebox_override("panel", _make_panel_style())
	add_child(_window)

	# --- Title bar ---
	var title_bar := _hbox(_window, Vector2(0, 0), Vector2(WIN_W, 34))

	var title_lbl := Label.new()
	title_lbl.text = "   SKILLS"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_color_override("font_color", C_TITLE)
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_bar.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "  ✕  "
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", C_TEXT_DIM)
	close_btn.pressed.connect(func(): _window.visible = false)
	title_bar.add_child(close_btn)

	_hsep(_window, 34)

	# --- Two-column layout ---
	# Left column: Combat, Gathering, Crafting   Right: Magic, Thief, Social, Ranger
	var left_cats  := ["Combat", "Gathering", "Crafting"]
	var right_cats := ["Magic", "Thief", "Social", "Ranger"]

	var col_w: float = (WIN_W - 24.0) / 2.0   # 12px padding each side
	var left_col  := _vbox(_window, Vector2(8, 42),   Vector2(col_w, WIN_H - 50))
	var right_col := _vbox(_window, Vector2(col_w + 16, 42), Vector2(col_w, WIN_H - 50))

	for cat_entry in CATEGORIES:
		var cat_name: String = cat_entry[0]
		var skills: Array    = cat_entry[1]
		var col: VBoxContainer = left_col if cat_name in left_cats else right_col
		_build_category(col, cat_name, skills)


func _build_category(col: VBoxContainer, cat_name: String, skills: Array) -> void:
	var accent: Color = CAT_COLORS.get(cat_name, C_BORDER)

	# Category header
	var hdr := Label.new()
	hdr.text = cat_name.to_upper()
	hdr.add_theme_color_override("font_color", accent)
	hdr.add_theme_font_size_override("font_size", 11)
	col.add_child(hdr)

	# Skill rows
	for entry in skills:
		var slot: int       = entry[0]
		var skill_name: String = entry[1]
		_build_skill_row(col, slot, skill_name, accent)

	# Spacer between categories
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	col.add_child(spacer)


func _build_skill_row(col: VBoxContainer, slot: int, skill_name: String, accent: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	col.add_child(row)

	# Skill name
	var name_lbl := Label.new()
	name_lbl.text = skill_name
	name_lbl.custom_minimum_size = Vector2(100, 0)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	name_lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(name_lbl)

	# Level label (e.g. "42")
	var val_lbl := Label.new()
	val_lbl.text = "0"
	val_lbl.custom_minimum_size = Vector2(22, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_color_override("font_color", C_TITLE)
	val_lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(val_lbl)
	_value_labels[slot] = val_lbl

	# XP label (e.g. "230/739")
	var xp_lbl := Label.new()
	xp_lbl.text = ""
	xp_lbl.custom_minimum_size = Vector2(72, 0)
	xp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	xp_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	xp_lbl.add_theme_font_size_override("font_size", 9)
	row.add_child(xp_lbl)
	_xp_labels[slot] = xp_lbl

	# XP progress bar (track + fill)
	var bar_bg := Panel.new()
	bar_bg.custom_minimum_size = Vector2(52, 8)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.06, 0.03, 1.0)
	bg_style.border_width_top    = 1
	bg_style.border_width_bottom = 1
	bg_style.border_width_left   = 1
	bg_style.border_width_right  = 1
	bg_style.border_color = Color(accent.r * 0.4, accent.g * 0.4, accent.b * 0.4, 0.7)
	bg_style.corner_radius_top_left     = 2
	bg_style.corner_radius_top_right    = 2
	bg_style.corner_radius_bottom_left  = 2
	bg_style.corner_radius_bottom_right = 2
	bar_bg.add_theme_stylebox_override("panel", bg_style)
	row.add_child(bar_bg)

	var fill := ColorRect.new()
	fill.color    = Color(accent.r, accent.g, accent.b, 0.80)
	fill.position = Vector2(1, 1)
	fill.size     = Vector2(0, 6)   # width set dynamically in _update_slot
	bar_bg.add_child(fill)
	_bar_fills[slot] = fill


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func _refresh_all() -> void:
	for slot in _value_labels:
		_update_slot(slot, PlayerState.get_skill(slot))


func _on_skill_changed(slot: int, value: int) -> void:
	if slot == -1:
		_refresh_all()
	elif _value_labels.has(slot):
		_update_slot(slot, value)


func _update_slot(slot: int, _value: int) -> void:
	var idx: int       = slot - 1
	var lv:  int       = PlayerState.skills[idx]          if idx < PlayerState.skills.size()          else 0
	var xp:  int       = PlayerState.skill_xp[idx]        if idx < PlayerState.skill_xp.size()        else 0
	var needed: int    = PlayerState.skill_xp_needed[idx] if idx < PlayerState.skill_xp_needed.size() else 100

	if _value_labels.has(slot):
		_value_labels[slot].text = str(lv)

	if _xp_labels.has(slot):
		if lv >= 100:
			_xp_labels[slot].text = "MAX"
		else:
			_xp_labels[slot].text = "%d/%d" % [xp, needed]

	if _bar_fills.has(slot):
		var fill: ColorRect = _bar_fills[slot]
		var bar_bg: Panel = fill.get_parent() as Panel
		if bar_bg != null:
			var max_w: float = bar_bg.size.x - 2.0
			var frac: float  = float(xp) / float(needed) if needed > 0 else 1.0
			fill.size = Vector2(max_w * clampf(frac, 0.0, 1.0), 6.0)


# ---------------------------------------------------------------------------
# Style helpers
# ---------------------------------------------------------------------------

func _make_panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = C_BG
	s.border_width_top    = 2
	s.border_width_bottom = 2
	s.border_width_left   = 2
	s.border_width_right  = 2
	s.border_color = C_BORDER
	s.corner_radius_top_left     = 4
	s.corner_radius_top_right    = 4
	s.corner_radius_bottom_left  = 4
	s.corner_radius_bottom_right = 4
	return s


func _hbox(parent: Node, pos: Vector2, sz: Vector2) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.position = pos
	hb.size = sz
	parent.add_child(hb)
	return hb


func _vbox(parent: Node, pos: Vector2, sz: Vector2) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.position = pos
	vb.size = sz
	vb.add_theme_constant_override("separation", 2)
	parent.add_child(vb)
	return vb


func _hsep(parent: Node, y: float) -> void:
	var sep := ColorRect.new()
	sep.color    = C_SEP
	sep.position = Vector2(0, y)
	sep.size     = Vector2(WIN_W, 1)
	parent.add_child(sep)
