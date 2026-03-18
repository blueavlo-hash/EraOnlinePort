class_name TrainerUI
extends CanvasLayer
## Era Online - Combat Ability Trainer UI
## Shows the ability shop for a trainer NPC (npc_type 4).
## Populated via Network.on_ability_shop signal.
## Call open() to show. Removes itself on close.

# ---------------------------------------------------------------------------
# Color palette (matches shop_ui.gd style)
# ---------------------------------------------------------------------------
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
const C_KNOWN    := Color(0.20, 0.65, 0.25, 1.0)
const C_LOCKED   := Color(0.40, 0.38, 0.30, 0.80)

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
const WIN_W  : int = 480
const WIN_H  : int = 420
const SCR_W  : int = 1280
const SCR_H  : int = 720

# ---------------------------------------------------------------------------
# Nodes
# ---------------------------------------------------------------------------
var _backdrop  : Panel
var _panel     : Panel
var _title_lbl : Label
var _scroll    : ScrollContainer
var _list_vbox : VBoxContainer
var _status_lbl: Label
var _gold_lbl  : Label
var _close_btn : Button

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _abilities  : Array = []   # Array of ability dicts from S_ABILITY_SHOP
var _learn_btns : Array = []   # parallel Button array


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func open() -> void:
	visible = true


func close() -> void:
	_disconnect_signals()
	queue_free()


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer   = 6
	visible = false
	_build_ui()
	_connect_signals()


func _build_ui() -> void:
	# Full-screen backdrop
	_backdrop = Panel.new()
	_backdrop.position     = Vector2.ZERO
	_backdrop.size         = Vector2(SCR_W, SCR_H)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.add_theme_stylebox_override("panel",
			_make_style(Color(0.0, 0.0, 0.0, 0.40), Color(0, 0, 0, 0), 0, 0))
	_backdrop.gui_input.connect(_on_backdrop_input)
	add_child(_backdrop)

	# Main panel
	var px := int(SCR_W / 2.0 - WIN_W / 2.0)
	var py := int(SCR_H / 2.0 - WIN_H / 2.0)
	_panel = Panel.new()
	_panel.position     = Vector2(px, py)
	_panel.size         = Vector2(WIN_W, WIN_H)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _make_style(C_BG, C_BORDER, 2, 4))
	add_child(_panel)

	# Title bar
	var title_bar := _make_hbox(_panel, Vector2(0, 0), Vector2(WIN_W, 36))
	var spc := Control.new()
	spc.custom_minimum_size = Vector2(12, 0)
	title_bar.add_child(spc)

	_title_lbl = Label.new()
	_title_lbl.text                  = "Combat Trainer"
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_color_override("font_color", C_GOLD)
	_title_lbl.add_theme_font_size_override("font_size", 20)
	title_bar.add_child(_title_lbl)

	_close_btn = Button.new()
	_close_btn.text = "  X  "
	_close_btn.flat = true
	_close_btn.add_theme_color_override("font_color", C_DIM)
	_close_btn.add_theme_stylebox_override("hover",
			_make_style(Color(0.20, 0.05, 0.04, 1), C_RED, 1, 3))
	_close_btn.pressed.connect(close)
	title_bar.add_child(_close_btn)

	# Divider
	_make_hsep(_panel, 36)

	# Column headers
	var hdr := _make_hbox(_panel, Vector2(12, 40), Vector2(WIN_W - 24, 20))
	_add_header_lbl(hdr, "Ability", true)
	_add_header_lbl(hdr, "STA", false)
	_add_header_lbl(hdr, "CD", false)
	_add_header_lbl(hdr, "Req Lv", false)
	_add_header_lbl(hdr, "Cost", false)
	var hdr_spacer := Control.new()
	hdr_spacer.custom_minimum_size = Vector2(70, 0)
	hdr.add_child(hdr_spacer)

	# Scroll area
	_scroll = ScrollContainer.new()
	_scroll.position               = Vector2(12, 62)
	_scroll.size                   = Vector2(WIN_W - 24, 254)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	_panel.add_child(_scroll)

	_list_vbox = VBoxContainer.new()
	_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_vbox.add_theme_constant_override("separation", 3)
	_scroll.add_child(_list_vbox)

	# Divider above footer
	_make_hsep(_panel, 326)

	# Footer
	var footer := _make_hbox(_panel, Vector2(12, 332), Vector2(WIN_W - 24, 80))
	footer.alignment = BoxContainer.ALIGNMENT_BEGIN

	var fcol := VBoxContainer.new()
	fcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(fcol)

	_status_lbl = Label.new()
	_status_lbl.text = ""
	_status_lbl.add_theme_color_override("font_color", C_TEXT)
	_status_lbl.add_theme_font_size_override("font_size", 12)
	fcol.add_child(_status_lbl)

	_gold_lbl = Label.new()
	_gold_lbl.text = ""
	_gold_lbl.add_theme_color_override("font_color", C_GOLD)
	_gold_lbl.add_theme_font_size_override("font_size", 12)
	fcol.add_child(_gold_lbl)

	var close_footer := Button.new()
	close_footer.text = "Close"
	close_footer.custom_minimum_size = Vector2(80, 32)
	close_footer.add_theme_stylebox_override("normal", _make_style(C_BTN, C_BORDER, 1, 3))
	close_footer.add_theme_stylebox_override("hover",  _make_style(C_BTN_HV, C_GOLD, 1, 3))
	close_footer.add_theme_color_override("font_color", C_TEXT)
	close_footer.pressed.connect(close)
	footer.add_child(close_footer)


# ---------------------------------------------------------------------------
# Signal wiring
# ---------------------------------------------------------------------------

func _connect_signals() -> void:
	var net := get_node_or_null("/root/Network")
	if net == null:
		return
	if not net.on_ability_shop.is_connected(_on_ability_shop):
		net.on_ability_shop.connect(_on_ability_shop)
	if not net.on_ability_learned.is_connected(_on_ability_learned):
		net.on_ability_learned.connect(_on_ability_learned)


func _disconnect_signals() -> void:
	var net := get_node_or_null("/root/Network")
	if net == null:
		return
	if net.on_ability_shop.is_connected(_on_ability_shop):
		net.on_ability_shop.disconnect(_on_ability_shop)
	if net.on_ability_learned.is_connected(_on_ability_learned):
		net.on_ability_learned.disconnect(_on_ability_learned)


# ---------------------------------------------------------------------------
# Population
# ---------------------------------------------------------------------------

func _on_ability_shop(abilities: Array) -> void:
	_abilities = abilities
	_populate()
	_update_gold_label()
	open()


func _on_ability_learned(_ability_id: int) -> void:
	# Refresh the list so the newly learned ability shows "Known"
	_populate()
	_update_gold_label()
	_set_status("Learned!", C_KNOWN)


func _populate() -> void:
	for child in _list_vbox.get_children():
		child.queue_free()
	_learn_btns.clear()

	for i in _abilities.size():
		var ab: Dictionary = _abilities[i]
		var row := _build_row(ab, i)
		_list_vbox.add_child(row)


func _build_row(ab: Dictionary, index: int) -> Control:
	var learned: bool  = ab.get("learned", false)
	var req_lv: int    = ab.get("req_level", 1)
	var req_sk_id: int = ab.get("req_skill_id", 16)
	var req_sk_val:int = ab.get("req_skill_val", 0)
	var gold_cost: int = ab.get("gold_cost", 0)
	var ab_name: String = ab.get("name", "?")
	# The network packet doesn't carry sta_cost/cooldown — look them up locally.
	var local_ab: Dictionary = GameData.get_ability(ab.get("id", 0))

	# Check if player meets requirements
	var ps := get_node_or_null("/root/PlayerState")
	var player_level: int = 1
	var player_skill: int = 0
	if ps != null:
		var s: Dictionary = ps.get("stats") if ps.get("stats") is Dictionary else {}
		player_level = s.get("level", 1)
		var skills: Array = ps.get("skills") if ps.get("skills") is Array else []
		var sk_idx := req_sk_id - 1
		if sk_idx >= 0 and sk_idx < skills.size():
			player_skill = int(skills[sk_idx])

	var meets_req: bool = (player_level >= req_lv) and (player_skill >= req_sk_val)

	var bg_col := Color(0.10, 0.08, 0.04, 0.60) if index % 2 == 0 else Color(0.07, 0.05, 0.02, 0.60)
	var wrapper := Panel.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.custom_minimum_size   = Vector2(WIN_W - 40, 30)
	wrapper.add_theme_stylebox_override("panel", _make_style(bg_col, Color(0, 0, 0, 0), 0, 2))
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.position = Vector2(4, 2)
	row.size = Vector2(WIN_W - 24, 26)   # explicit width so name label gets its share
	wrapper.add_child(row)

	# Name label (expands)
	var name_col := Color(C_LOCKED if not meets_req else C_TEXT)
	var name_lbl := Label.new()
	name_lbl.text                  = ab_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", name_col)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.clip_text             = true
	row.add_child(name_lbl)

	# STA cost and cooldown from local GameData (not sent in packet)
	var sta_cost: int = local_ab.get("sta_cost", 0)
	var cd: float     = local_ab.get("cooldown", 0.0)
	_add_row_lbl(row, "%d sta" % sta_cost, 46, C_TEXT)
	_add_row_lbl(row, "%.0fs" % cd if cd > 0.0 else "-", 36, C_DIM)
	# Req level
	_add_row_lbl(row, "Lv%d" % req_lv, 36,
			C_RED if player_level < req_lv else C_DIM)
	# Gold cost
	_add_row_lbl(row, "%d g" % gold_cost, 52, C_GOLD)

	# Action button or "Known" label
	if learned:
		var known_lbl := Label.new()
		known_lbl.text               = "Known"
		known_lbl.custom_minimum_size = Vector2(68, 26)
		known_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		known_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		known_lbl.add_theme_color_override("font_color", C_KNOWN)
		known_lbl.add_theme_font_size_override("font_size", 12)
		row.add_child(known_lbl)
		_learn_btns.append(null)
	else:
		var btn := Button.new()
		btn.text               = "Learn"
		btn.custom_minimum_size = Vector2(68, 26)
		btn.disabled           = not meets_req
		btn.add_theme_stylebox_override("normal",
				_make_style(C_GREEN, C_BORDER, 1, 3))
		btn.add_theme_stylebox_override("hover",
				_make_style(C_GREEN_HV, C_GOLD, 1, 3))
		btn.add_theme_stylebox_override("pressed",
				_make_style(C_BG, C_GOLD, 1, 3))
		btn.add_theme_stylebox_override("disabled",
				_make_style(Color(0.10, 0.10, 0.08, 0.60), C_DIM, 1, 3))
		btn.add_theme_color_override("font_color", C_TEXT)
		btn.add_theme_color_override("font_disabled_color", C_DIM)
		btn.add_theme_font_size_override("font_size", 12)
		var ability_id: int = ab.get("id", index)
		btn.pressed.connect(_on_learn_pressed.bind(ability_id))
		row.add_child(btn)
		_learn_btns.append(btn)

	return wrapper


# ---------------------------------------------------------------------------
# Input handlers
# ---------------------------------------------------------------------------

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			close()


func _on_learn_pressed(ability_id: int) -> void:
	var net := get_node_or_null("/root/Network")
	if net == null or not net.has_method("send_learn_ability"):
		_set_status("Not connected.", C_RED)
		return
	net.send_learn_ability(ability_id)
	_set_status("Requesting...", C_DIM)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _set_status(text: String, color: Color) -> void:
	if is_instance_valid(_status_lbl):
		_status_lbl.text = text
		_status_lbl.add_theme_color_override("font_color", color)


func _update_gold_label() -> void:
	if not is_instance_valid(_gold_lbl):
		return
	var ps := get_node_or_null("/root/PlayerState")
	var gold := 0
	if ps != null:
		var s: Dictionary = ps.get("stats") if ps.get("stats") is Dictionary else {}
		gold = s.get("gold", 0)
	_gold_lbl.text = "Gold: %d" % gold


func _add_row_lbl(parent: Control, text: String, min_w: int, color: Color) -> void:
	var lbl := Label.new()
	lbl.text                    = text
	lbl.custom_minimum_size     = Vector2(min_w, 0)
	lbl.horizontal_alignment    = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment      = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_font_size_override("font_size", 11)
	parent.add_child(lbl)


func _add_header_lbl(parent: Control, text: String, expand: bool) -> void:
	var lbl := Label.new()
	lbl.text                     = text
	lbl.vertical_alignment       = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", C_DIM)
	lbl.add_theme_font_size_override("font_size", 11)
	if expand:
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		lbl.custom_minimum_size = Vector2(48, 0)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parent.add_child(lbl)


func _make_style(bg: Color, border: Color, border_w: int, corner: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color                   = bg
	s.border_color               = border
	s.border_width_left          = border_w
	s.border_width_right         = border_w
	s.border_width_top           = border_w
	s.border_width_bottom        = border_w
	s.corner_radius_top_left     = corner
	s.corner_radius_top_right    = corner
	s.corner_radius_bottom_left  = corner
	s.corner_radius_bottom_right = corner
	return s


func _make_hbox(parent: Control, pos: Vector2, sz: Vector2) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.position = pos
	hb.size     = sz
	parent.add_child(hb)
	return hb


func _make_hsep(parent: Control, y: float) -> void:
	var sep := Panel.new()
	sep.position = Vector2(0, y)
	sep.size     = Vector2(WIN_W, 2)
	sep.add_theme_stylebox_override("panel",
			_make_style(Color(0.40, 0.30, 0.10, 0.60), Color(0.40, 0.30, 0.10, 0.60), 0, 0))
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sep)
