class_name HudUI
extends CanvasLayer
## Era Online - HUD UI (Unified Overhaul)
## Bottom bar: XP strip → stat bars (left), 10-slot action hotbar (centre), info (right).
## Unified hotbar handles melee abilities, magic spells, and ranged abilities on keys 1-0.

signal slot_activated(slot_idx: int)    ## Fired when a hotbar slot key is pressed or clicked.

# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------
const C_PANEL_BG    := Color(0.06, 0.04, 0.02, 0.96)
const C_PANEL_EDGE  := Color(0.50, 0.37, 0.12, 1.00)
const C_SECTION_BG  := Color(0.10, 0.07, 0.03, 1.00)
const C_SECTION_EDG := Color(0.35, 0.25, 0.08, 1.00)
const C_GOLD        := Color(0.88, 0.68, 0.18, 1.00)
const C_GOLD_DIM    := Color(0.60, 0.45, 0.12, 1.00)
const C_TEXT        := Color(0.92, 0.86, 0.70, 1.00)
const C_TEXT_DIM    := Color(0.50, 0.44, 0.30, 1.00)

const C_HP_FILL  := Color(0.82, 0.14, 0.10, 1.00); const C_HP_SHINE  := Color(1.00, 0.45, 0.40, 0.22); const C_HP_BG  := Color(0.22, 0.04, 0.03, 1.00)
const C_MP_FILL  := Color(0.16, 0.32, 0.85, 1.00); const C_MP_SHINE  := Color(0.50, 0.65, 1.00, 0.22); const C_MP_BG  := Color(0.04, 0.07, 0.22, 1.00)
const C_STA_FILL := Color(0.18, 0.70, 0.22, 1.00); const C_STA_SHINE := Color(0.55, 1.00, 0.60, 0.22); const C_STA_BG := Color(0.03, 0.16, 0.04, 1.00)
const C_HNG_FILL := Color(0.85, 0.46, 0.10, 1.00); const C_HNG_BG   := Color(0.20, 0.09, 0.02, 1.00)
const C_THR_FILL := Color(0.14, 0.60, 0.92, 1.00); const C_THR_BG   := Color(0.02, 0.08, 0.20, 1.00)
const C_XP_FILL  := Color(0.62, 0.28, 0.82, 1.00); const C_XP_BG    := Color(0.12, 0.04, 0.18, 1.00)
const C_CD_FILL  := Color(0.06, 0.06, 0.06, 0.88)

## Hotbar slot border colours by content type
const C_SLOT_EMPTY    := Color(0.22, 0.16, 0.07, 1.00)
const C_SLOT_ABILITY  := Color(0.90, 0.55, 0.12, 1.00)   # orange-gold: melee/physical
const C_SLOT_SPELL    := Color(0.28, 0.45, 1.00, 1.00)   # blue: magic
const C_SLOT_RANGED   := Color(0.25, 0.72, 0.28, 1.00)   # green: ranged
const C_SLOT_ITEM     := Color(0.75, 0.72, 0.22, 1.00)   # yellow: item
const C_SLOT_BG_FULL  := Color(0.14, 0.10, 0.04, 1.00)   # slot bg when filled
const C_SLOT_BG_EMPTY := Color(0.09, 0.06, 0.02, 1.00)   # slot bg when empty
const C_SLOT_CD_BG    := Color(0.06, 0.06, 0.06, 0.70)   # cooldown overlay

## Aim mode
const C_AIM_TEXT  := Color(1.00, 0.82, 0.22, 1.00)
const C_AIM_BG    := Color(0.08, 0.06, 0.02, 0.90)

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
const VW        := 1280.0
const VH        := 720.0
const HUD_H     := 82
const XP_H      := 5
const INNER_Y   := XP_H + 1

const BAR_LBL_W := 32; const BAR_W := 188; const BAR_H := 18; const BAR_GAP := 22
const LEFT_W    := 240

const SLOT_W    := 48; const SLOT_H := 62; const SLOT_GAP := 3
const SLOT_COUNT := 10

const MINI_W := 134; const MINI_H := 13
const RIGHT_W := 200

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _hp_fill: ColorRect;  var _hp_label: Label
var _mp_fill: ColorRect;  var _mp_label: Label
var _sta_fill: ColorRect; var _sta_label: Label
var _xp_fill: ColorRect;  var _xp_label: Label

var _gold_label:   Label
var _level_label:  Label
var _hunger_fill:  ColorRect; var _hunger_label: Label; var _hunger_lbl_left: Label
var _thirst_fill:  ColorRect; var _thirst_label: Label; var _thirst_lbl_left: Label

## Per-slot display nodes
var _slot_panels:    Array[Panel]     = []
var _slot_name_lbls: Array[Label]     = []
var _slot_cost_lbls: Array[Label]     = []
var _slot_cd_overs:  Array[ColorRect] = []
var _slot_cd_lbls:   Array[Label]     = []

## Aim mode label (shown above hotbar during spell targeting)
var _aim_label: Label = null

## Floating damage numbers
var _dmg_labels: Array[Node] = []

## Tooltip
var _tooltip: Panel        = null
var _tooltip_timer: float  = 0.0
var _tooltip_slot: int     = -1
const TOOLTIP_DELAY := 0.55


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 10
	_build_hud()
	PlayerState.stats_changed.connect(_refresh_bars)
	PlayerState.vitals_changed.connect(_refresh_vitals)
	PlayerState.unified_hotbar_changed.connect(_refresh_all_slots)
	PlayerState.spellbook_changed.connect(_refresh_all_slots)
	CombatSystem.damage_dealt.connect(_on_damage_dealt)
	CombatSystem.target_died.connect(_on_target_died)
	_refresh_bars()
	_refresh_vitals()
	_refresh_all_slots()
	set_process(true)


func _process(delta: float) -> void:
	_update_cooldowns()
	_tick_damage_labels(delta)
	_tick_tooltip(delta)


# ---------------------------------------------------------------------------
# Key input — 1-9 = slots 0-8, 0 = slot 9
# ---------------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not (event as InputEventKey).pressed or (event as InputEventKey).echo:
		return
	var kc: int = (event as InputEventKey).physical_keycode
	var slot: int = -1
	match kc:
		KEY_1: slot = 0
		KEY_2: slot = 1
		KEY_3: slot = 2
		KEY_4: slot = 3
		KEY_5: slot = 4
		KEY_6: slot = 5
		KEY_7: slot = 6
		KEY_8: slot = 7
		KEY_9: slot = 8
		KEY_0: slot = 9
	if slot >= 0:
		_activate_slot(slot)


func _activate_slot(idx: int) -> void:
	slot_activated.emit(idx)


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build_hud() -> void:
	var hud := Panel.new()
	hud.size     = Vector2(VW, HUD_H)
	hud.position = Vector2(0, VH - HUD_H)
	hud.add_theme_stylebox_override("panel", _box(C_PANEL_BG, C_PANEL_EDGE, 2, 0))
	add_child(hud)

	# XP bar
	var xp_bg := ColorRect.new(); xp_bg.color = C_XP_BG
	xp_bg.size = Vector2(VW, XP_H); xp_bg.position = Vector2(0, 0)
	hud.add_child(xp_bg)
	_xp_fill = ColorRect.new(); _xp_fill.color = C_XP_FILL
	_xp_fill.size = Vector2(0, XP_H); _xp_fill.position = Vector2(0, 0)
	hud.add_child(_xp_fill)
	_xp_label = Label.new(); _xp_label.text = "XP: 0 / 300"
	_xp_label.add_theme_font_size_override("font_size", 9)
	_xp_label.add_theme_color_override("font_color", Color(0.80, 0.65, 1.0, 0.85))
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_xp_label.size = Vector2(240, XP_H); _xp_label.position = Vector2(VW - 244, 0)
	hud.add_child(_xp_label)
	var sep := ColorRect.new(); sep.color = Color(C_PANEL_EDGE.r, C_PANEL_EDGE.g, C_PANEL_EDGE.b, 0.40)
	sep.size = Vector2(VW, 1); sep.position = Vector2(0, XP_H)
	hud.add_child(sep)

	var sy := INNER_Y + 3
	var sh := HUD_H - sy - 3

	# Left: vitals
	var left := _section(hud, 8, sy, LEFT_W, sh)
	_build_stat_bar(left, 6, 6,                "HP",  C_HP_FILL,  C_HP_SHINE,  C_HP_BG)
	_build_stat_bar(left, 6, 6 + BAR_GAP,     "MP",  C_MP_FILL,  C_MP_SHINE,  C_MP_BG)
	_build_stat_bar(left, 6, 6 + BAR_GAP * 2, "STA", C_STA_FILL, C_STA_SHINE, C_STA_BG)

	# Centre: unified hotbar
	var total_bar_w := SLOT_COUNT * SLOT_W + (SLOT_COUNT - 1) * SLOT_GAP
	var hb_x0       := int((VW - total_bar_w) / 2.0)
	var hb_y        := INNER_Y + int((HUD_H - INNER_Y - SLOT_H) / 2.0)
	_build_hotbar(hud, hb_x0, hb_y)

	# Aim mode label above hotbar (hidden by default)
	_aim_label = Label.new()
	_aim_label.text = ""
	_aim_label.visible = false
	_aim_label.add_theme_color_override("font_color", C_AIM_TEXT)
	_aim_label.add_theme_font_size_override("font_size", 12)
	_aim_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aim_label.size     = Vector2(total_bar_w, 18)
	_aim_label.position = Vector2(hb_x0, VH - HUD_H - 22)
	add_child(_aim_label)

	# Right: level / gold / vitals
	var rx    := int(VW) - RIGHT_W - 8
	var right := _section(hud, rx, sy, RIGHT_W, sh)

	_level_label = Label.new(); _level_label.text = "Level  1"
	_level_label.add_theme_font_size_override("font_size", 14)
	_level_label.add_theme_color_override("font_color", C_GOLD)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.size = Vector2(RIGHT_W - 12, 18); _level_label.position = Vector2(6, 5)
	right.add_child(_level_label)

	_gold_label = Label.new(); _gold_label.text = "Gold:  500"
	_gold_label.add_theme_font_size_override("font_size", 11)
	_gold_label.add_theme_color_override("font_color", C_GOLD_DIM)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gold_label.size = Vector2(RIGHT_W - 12, 14); _gold_label.position = Vector2(6, 25)
	right.add_child(_gold_label)

	var div := ColorRect.new(); div.color = C_SECTION_EDG
	div.size = Vector2(RIGHT_W - 20, 1); div.position = Vector2(10, 42)
	right.add_child(div)

	_build_vital_bar(right, 6, 43,  "Food",  C_HNG_FILL, C_HNG_BG)
	_build_vital_bar(right, 6, 57,  "Water", C_THR_FILL, C_THR_BG)

	# Tooltip panel (hidden until hover)
	_tooltip = Panel.new()
	_tooltip.add_theme_stylebox_override("panel", _box(Color(0.08, 0.06, 0.03, 0.97), C_PANEL_EDGE, 1, 4))
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tooltip)


func _build_hotbar(parent: Control, x0: int, y0: int) -> void:
	for i in SLOT_COUNT:
		var sx := x0 + i * (SLOT_W + SLOT_GAP)
		var slot := Panel.new()
		slot.size     = Vector2(SLOT_W, SLOT_H)
		slot.position = Vector2(sx, y0)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.add_theme_stylebox_override("panel", _box(C_SLOT_BG_EMPTY, C_SLOT_EMPTY, 1, 3))
		parent.add_child(slot)
		_slot_panels.append(slot)

		# Key number (top-left)
		var kn := Label.new()
		kn.text = str((i + 1) % 10)  # 1-9 then 0
		kn.add_theme_font_size_override("font_size", 9)
		kn.add_theme_color_override("font_color", C_GOLD_DIM)
		kn.size = Vector2(16, 12); kn.position = Vector2(2, 2)
		kn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(kn)

		# Name label (center)
		var nl := Label.new(); nl.text = "—"
		nl.add_theme_font_size_override("font_size", 10)
		nl.add_theme_color_override("font_color", C_TEXT_DIM)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.clip_text = true
		nl.size = Vector2(SLOT_W - 2, SLOT_H - 24); nl.position = Vector2(1, 14)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(nl)
		_slot_name_lbls.append(nl)

		# Cost label (bottom)
		var cl := Label.new(); cl.text = ""
		cl.add_theme_font_size_override("font_size", 9)
		cl.add_theme_color_override("font_color", C_MP_FILL)
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.size = Vector2(SLOT_W - 2, 12); cl.position = Vector2(1, SLOT_H - 13)
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(cl)
		_slot_cost_lbls.append(cl)

		# Cooldown overlay
		var cd_over := ColorRect.new()
		cd_over.color = C_SLOT_CD_BG
		cd_over.size  = Vector2(SLOT_W, 0); cd_over.position = Vector2(0, 0)
		cd_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(cd_over)
		_slot_cd_overs.append(cd_over)

		# Cooldown label
		var cd_lbl := Label.new(); cd_lbl.text = ""
		cd_lbl.add_theme_font_size_override("font_size", 11)
		cd_lbl.add_theme_color_override("font_color", Color.WHITE)
		cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		cd_lbl.size = Vector2(SLOT_W, SLOT_H); cd_lbl.position = Vector2(0, 0)
		cd_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(cd_lbl)
		_slot_cd_lbls.append(cd_lbl)

		# Click handler
		slot.gui_input.connect(_on_slot_input.bind(i))


func _section(parent: Control, x: int, y: int, w: int, h: int) -> Panel:
	var p := Panel.new()
	p.position = Vector2(x, y); p.size = Vector2(w, h)
	p.add_theme_stylebox_override("panel", _box(C_SECTION_BG, C_SECTION_EDG, 1, 3))
	parent.add_child(p)
	return p


func _build_stat_bar(parent: Control, x: int, y: int, lbl_text: String,
		fill_c: Color, shine_c: Color, bg_c: Color) -> void:
	var lbl := Label.new(); lbl.text = lbl_text
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	lbl.size = Vector2(BAR_LBL_W, BAR_H); lbl.position = Vector2(x, y)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(lbl)
	var bx := x + BAR_LBL_W
	var bg_r := ColorRect.new(); bg_r.color = bg_c; bg_r.size = Vector2(BAR_W, BAR_H); bg_r.position = Vector2(bx, y); parent.add_child(bg_r)
	var fi_r := ColorRect.new(); fi_r.color = fill_c; fi_r.size = Vector2(BAR_W, BAR_H); fi_r.position = Vector2(bx, y); parent.add_child(fi_r)
	var sh_r := ColorRect.new(); sh_r.color = shine_c; sh_r.size = Vector2(BAR_W, int(BAR_H * 0.45)); sh_r.position = Vector2(bx, y); parent.add_child(sh_r)
	var bd := Panel.new(); bd.size = Vector2(BAR_W, BAR_H); bd.position = Vector2(bx, y)
	bd.add_theme_stylebox_override("panel", _box(Color(0,0,0,0), C_SECTION_EDG, 1, 2)); parent.add_child(bd)
	var vl := Label.new(); vl.text = "0 / 0"; vl.add_theme_font_size_override("font_size", 10)
	vl.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; vl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vl.size = Vector2(BAR_W, BAR_H); vl.position = Vector2(bx, y); parent.add_child(vl)
	match lbl_text:
		"HP":  _hp_fill  = fi_r; _hp_label  = vl
		"MP":  _mp_fill  = fi_r; _mp_label  = vl
		"STA": _sta_fill = fi_r; _sta_label = vl


func _build_vital_bar(parent: Control, x: int, y: int, lbl_text: String,
		fill_c: Color, bg_c: Color) -> void:
	var lbl := Label.new(); lbl.text = lbl_text
	lbl.add_theme_font_size_override("font_size", 9); lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	lbl.size = Vector2(28, MINI_H); lbl.position = Vector2(x, y); lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(lbl)
	var bx := x + 30
	var bg_r := ColorRect.new(); bg_r.color = bg_c; bg_r.size = Vector2(MINI_W, MINI_H); bg_r.position = Vector2(bx, y); parent.add_child(bg_r)
	var fi_r := ColorRect.new(); fi_r.color = fill_c; fi_r.size = Vector2(MINI_W, MINI_H); fi_r.position = Vector2(bx, y); parent.add_child(fi_r)
	var bd := Panel.new(); bd.size = Vector2(MINI_W, MINI_H); bd.position = Vector2(bx, y)
	bd.add_theme_stylebox_override("panel", _box(Color(0,0,0,0), C_SECTION_EDG, 1, 2)); parent.add_child(bd)
	var pct := Label.new(); pct.text = "100%"; pct.add_theme_font_size_override("font_size", 9)
	pct.add_theme_color_override("font_color", Color(1, 1, 1, 0.80))
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pct.size = Vector2(MINI_W - 2, MINI_H); pct.position = Vector2(bx, y); parent.add_child(pct)
	match lbl_text:
		"Food":  _hunger_fill = fi_r; _hunger_label = pct; _hunger_lbl_left = lbl
		"Water": _thirst_fill = fi_r; _thirst_label = pct; _thirst_lbl_left = lbl


# ---------------------------------------------------------------------------
# Slot display
# ---------------------------------------------------------------------------

func _refresh_all_slots() -> void:
	for i in SLOT_COUNT:
		_refresh_slot(i)


func _refresh_slot(i: int) -> void:
	var entry = PlayerState.get_unified_hotbar_slot(i)
	if entry == null:
		_slot_name_lbls[i].text = "—"
		_slot_name_lbls[i].add_theme_color_override("font_color", C_TEXT_DIM)
		_slot_cost_lbls[i].text = ""
		_slot_panels[i].add_theme_stylebox_override("panel", _box(C_SLOT_BG_EMPTY, C_SLOT_EMPTY, 1, 3))
		return

	var stype: String = entry.get("type", "")
	var sid:   int    = entry.get("id", 0)

	match stype:
		"ability":
			var ab: Dictionary = GameData.get_ability(sid)
			var nm: String = ab.get("name", "Ability")
			_slot_name_lbls[i].text = nm.substr(0, 9) if nm.length() > 9 else nm
			_slot_name_lbls[i].add_theme_color_override("font_color", C_TEXT)
			var cost: int = ab.get("sta_cost", 0)
			if cost > 0:
				_slot_cost_lbls[i].text = "%dSTA" % cost
				_slot_cost_lbls[i].add_theme_color_override("font_color", C_STA_FILL)
			else:
				_slot_cost_lbls[i].text = ""
			# Border color: ranged ability vs melee
			var border_c: Color = C_SLOT_RANGED if ab.get("req_skill_id", 0) == 28 else C_SLOT_ABILITY
			_slot_panels[i].add_theme_stylebox_override("panel", _box(C_SLOT_BG_FULL, border_c, 2, 3))

		"spell":
			var sp: Dictionary = GameData.get_spell(sid)
			var nm: String = sp.get("name", "Spell")
			_slot_name_lbls[i].text = nm.substr(0, 9) if nm.length() > 9 else nm
			_slot_name_lbls[i].add_theme_color_override("font_color", C_TEXT)
			var cost: int = sp.get("needs_mana", 0)
			if cost > 0:
				_slot_cost_lbls[i].text = "%dMP" % cost
				_slot_cost_lbls[i].add_theme_color_override("font_color", C_MP_FILL)
			else:
				_slot_cost_lbls[i].text = ""
			_slot_panels[i].add_theme_stylebox_override("panel", _box(C_SLOT_BG_FULL, C_SLOT_SPELL, 2, 3))

		_:
			_slot_name_lbls[i].text = "—"
			_slot_name_lbls[i].add_theme_color_override("font_color", C_TEXT_DIM)
			_slot_cost_lbls[i].text = ""
			_slot_panels[i].add_theme_stylebox_override("panel", _box(C_SLOT_BG_EMPTY, C_SLOT_EMPTY, 1, 3))


# ---------------------------------------------------------------------------
# Cooldown updates
# ---------------------------------------------------------------------------

func _update_cooldowns() -> void:
	for i in SLOT_COUNT:
		var entry = PlayerState.get_unified_hotbar_slot(i)
		if entry == null:
			_set_cd_overlay(i, 0.0, "")
			continue

		var stype: String = entry.get("type", "")
		var sid:   int    = entry.get("id", 0)
		match stype:
			"ability":
				if CombatSystem.is_on_cooldown(sid):
					var frac  := CombatSystem.get_cooldown_fraction(sid)
					var rem_s := maxf(0.0, float(CombatSystem._cooldowns.get(sid, 0) - Time.get_ticks_msec()) / 1000.0)
					_set_cd_overlay(i, frac, "%.1f" % rem_s)
				else:
					_set_cd_overlay(i, 0.0, "")
			"spell":
				var rem := PlayerState.get_cooldown_remaining(sid)
				if rem > 0.0:
					var sp: Dictionary = GameData.get_spell(sid)
					var total: float = maxf(0.01, sp.get("cooldown", 1.0))
					_set_cd_overlay(i, minf(rem / total, 1.0), "%.1f" % rem)
				else:
					_set_cd_overlay(i, 0.0, "")
			_:
				_set_cd_overlay(i, 0.0, "")


func _set_cd_overlay(i: int, frac: float, txt: String) -> void:
	var over := _slot_cd_overs[i]
	var lbl  := _slot_cd_lbls[i]
	if frac <= 0.0:
		over.size.y = 0.0
		lbl.text    = ""
	else:
		over.size.y     = SLOT_H * frac
		over.position.y = 0.0
		lbl.text = txt


# ---------------------------------------------------------------------------
# Slot click
# ---------------------------------------------------------------------------

func _on_slot_input(event: InputEvent, slot_idx: int) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_activate_slot(slot_idx)
	elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		_hide_tooltip()
		PlayerState.clear_unified_hotbar_slot(slot_idx)


# ---------------------------------------------------------------------------
# Aim mode indicator (called by world_map)
# ---------------------------------------------------------------------------

func show_aim_mode(text: String) -> void:
	if _aim_label != null:
		_aim_label.text = text
		_aim_label.visible = true


func hide_aim_mode() -> void:
	if _aim_label != null:
		_aim_label.visible = false


# ---------------------------------------------------------------------------
# Stat bar refresh
# ---------------------------------------------------------------------------

func _refresh_bars() -> void:
	var s := PlayerState.stats
	_set_bar(_hp_fill,  _hp_label,  s.get("hp",  0), s.get("max_hp",  1), BAR_W)
	_set_bar(_mp_fill,  _mp_label,  s.get("mp",  0), s.get("max_mp",  1), BAR_W)
	_set_bar(_sta_fill, _sta_label, s.get("sta", 0), s.get("max_sta", 1), BAR_W)
	_level_label.text = "Level  " + str(s.get("level", 1))
	_gold_label.text  = "Gold:  " + str(s.get("gold", 0))
	var xp: int = s.get("exp", 0); var need: int = s.get("next_exp", 300)
	if need > 0:
		_xp_fill.size.x = VW * clampf(float(xp) / float(need), 0.0, 1.0)
	_xp_label.text = "XP: %d / %d" % [xp, need]


func _refresh_vitals() -> void:
	if _hunger_fill == null or _thirst_fill == null:
		return
	var h: int = PlayerState.hunger; var t: int = PlayerState.thirst
	_hunger_fill.size.x = MINI_W * float(h) / 100.0; _hunger_label.text = str(h) + "%"
	_thirst_fill.size.x = MINI_W * float(t) / 100.0; _thirst_label.text = str(t) + "%"
	_hunger_fill.color = _vital_color(h); _thirst_fill.color = _vital_color(t)
	var hc := h < 30; var tc := t < 30
	_hunger_lbl_left.add_theme_color_override("font_color", Color(0.85, 0.2, 0.2) if hc else C_TEXT_DIM)
	_thirst_lbl_left.add_theme_color_override("font_color", Color(0.85, 0.2, 0.2) if tc else C_TEXT_DIM)


func _set_bar(fill: ColorRect, lbl: Label, cur: int, mx: int, w: float) -> void:
	if mx <= 0: return
	fill.size.x = w * clampf(float(cur) / float(mx), 0.0, 1.0)
	lbl.text    = "%d / %d" % [cur, mx]


# ---------------------------------------------------------------------------
# Tooltip
# ---------------------------------------------------------------------------

func _tick_tooltip(delta: float) -> void:
	var mp := get_viewport().get_mouse_position()
	var hud_y := VH - HUD_H
	if mp.y < hud_y:
		_hide_tooltip()
		_tooltip_slot = -1
		_tooltip_timer = 0.0
		return

	# Which slot is the mouse over?
	var hovered := -1
	for i in SLOT_COUNT:
		if not is_instance_valid(_slot_panels[i]):
			continue
		var gp: Vector2 = _slot_panels[i].get_global_rect().position
		var gs: Vector2 = _slot_panels[i].size
		var rect := Rect2(gp, gs)
		if rect.has_point(mp):
			hovered = i
			break

	if hovered < 0:
		_hide_tooltip()
		_tooltip_slot = -1
		_tooltip_timer = 0.0
		return

	if hovered != _tooltip_slot:
		_hide_tooltip()
		_tooltip_slot = hovered
		_tooltip_timer = 0.0

	_tooltip_timer += delta
	if _tooltip_timer >= TOOLTIP_DELAY:
		_show_tooltip(hovered, mp)


func _show_tooltip(idx: int, mouse_pos: Vector2) -> void:
	if _tooltip == null:
		return
	var entry = PlayerState.get_unified_hotbar_slot(idx)
	if entry == null:
		_hide_tooltip()
		return

	var stype: String = entry.get("type", "")
	var sid:   int    = entry.get("id", 0)
	var lines: Array[String] = []

	match stype:
		"ability":
			var ab: Dictionary = GameData.get_ability(sid)
			lines.append(ab.get("name", "Ability"))
			lines.append(ab.get("desc", ""))
			var cost: int = ab.get("sta_cost", 0)
			var cd:   float = ab.get("cooldown", 0.0)
			if cost > 0:
				lines.append("Stamina: %d" % cost)
			if cd > 0.0:
				lines.append("Cooldown: %.1fs" % cd)
		"spell":
			var sp: Dictionary = GameData.get_spell(sid)
			lines.append(sp.get("name", "Spell"))
			lines.append(sp.get("description", ""))
			lines.append("Mana: %d" % sp.get("needs_mana", 0))
			var cd: float = sp.get("cooldown", 0.0)
			if cd > 0.0:
				lines.append("Cooldown: %.1fs" % cd)

	# Build tooltip panel content
	for ch in _tooltip.get_children():
		ch.queue_free()

	var max_w := 0.0
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(8, 6)
	vbox.add_theme_constant_override("separation", 2)
	_tooltip.add_child(vbox)

	for li in lines.size():
		var lbl := Label.new()
		lbl.text = lines[li]
		lbl.add_theme_font_size_override("font_size", 11 if li == 0 else 10)
		lbl.add_theme_color_override("font_color", C_GOLD if li == 0 else C_TEXT_DIM)
		vbox.add_child(lbl)
		# Estimate width
		var w: float = float(lines[li].length()) * 6.8 + 16.0
		if w > max_w:
			max_w = w

	var panel_h := float(lines.size()) * 16.0 + 12.0
	_tooltip.size = Vector2(max_w, panel_h)
	var tx := clampf(mouse_pos.x - max_w / 2.0, 4.0, VW - max_w - 4.0)
	var ty := mouse_pos.y - panel_h - 10.0
	if ty < 4.0:
		ty = mouse_pos.y + 22.0
	_tooltip.position = Vector2(tx, ty)
	_tooltip.visible  = true


func _hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.visible = false


# ---------------------------------------------------------------------------
# Floating damage numbers
# ---------------------------------------------------------------------------

func _on_damage_dealt(target_id: int, amount: int, evaded: bool) -> void:
	var vp := get_viewport().get_visible_rect().size
	_spawn_dmg_label(Vector2(vp.x * 0.5, vp.y * 0.4), amount, evaded, target_id == -1)


func _on_target_died(_target_id: int) -> void:
	var vp := get_viewport().get_visible_rect().size
	_spawn_dmg_label(Vector2(vp.x * 0.5, vp.y * 0.38), 0, false, true, true)


func _spawn_dmg_label(pos: Vector2, amount: int, evaded: bool,
		_is_dummy: bool, died: bool = false) -> void:
	var lbl := Label.new()
	if died:
		lbl.text = "DEAD"
		lbl.add_theme_color_override("font_color", Color(1.0, 0.30, 0.10))
		lbl.add_theme_font_size_override("font_size", 22)
	elif evaded:
		lbl.text = "Miss"
		lbl.add_theme_color_override("font_color", Color(0.80, 0.80, 0.40))
		lbl.add_theme_font_size_override("font_size", 16)
	else:
		lbl.text = "-%d" % amount
		var bright := minf(1.0, 0.5 + amount / 20.0)
		lbl.add_theme_color_override("font_color", Color(1.0, bright * 0.4, 0.1))
		lbl.add_theme_font_size_override("font_size", 18 + mini(amount / 4 as int, 10))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size     = Vector2(120, 32)
	lbl.position = pos + Vector2(randf_range(-28, 28), randf_range(-10, 10)) - Vector2(60, 16)
	add_child(lbl)
	_dmg_labels.append(lbl)


func _tick_damage_labels(delta: float) -> void:
	for child in _dmg_labels.duplicate():
		if not is_instance_valid(child):
			_dmg_labels.erase(child)
			continue
		child.position.y -= 42.0 * delta
		child.modulate.a  -= 1.1 * delta
		if child.modulate.a <= 0.0:
			child.queue_free()
			_dmg_labels.erase(child)


# ---------------------------------------------------------------------------
# Style helpers
# ---------------------------------------------------------------------------

func _vital_color(value: int) -> Color:
	if value > 60: return Color(0.3, 0.75, 0.3)
	elif value >= 30: return Color(0.85, 0.75, 0.1)
	else: return Color(0.85, 0.2, 0.2)


func _box(bg: Color, border: Color, bw: int, radius: int = 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.set_border_width_all(bw)
	s.corner_radius_top_left = radius; s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius; s.corner_radius_bottom_right = radius
	return s
