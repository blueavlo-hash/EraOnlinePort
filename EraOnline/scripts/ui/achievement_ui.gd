class_name AchievementUI
extends CanvasLayer
## Era Online - Achievement UI
##
## Collapsible panel (top-left, 280px wide) showing all unlocked achievements.
## Toggle with A key when chat input is not open.
## When Network.on_achievement_unlock fires, adds the entry and shows a gold-
## bordered toast at the bottom-centre of the screen for 4 seconds.

signal close_requested

# ---------------------------------------------------------------------------
# Color palette
# ---------------------------------------------------------------------------
const C_BG       := Color(0.05, 0.04, 0.02, 0.94)
const C_BORDER   := Color(0.40, 0.30, 0.12, 1.0)
const C_GOLD     := Color(0.85, 0.65, 0.15, 1.0)
const C_TEXT     := Color(0.90, 0.85, 0.72, 1.0)
const C_DIM      := Color(0.55, 0.50, 0.38, 1.0)
const C_GREY     := Color(0.60, 0.58, 0.52, 1.0)
const C_BTN      := Color(0.14, 0.10, 0.04, 1.0)
const C_BTN_HV   := Color(0.22, 0.16, 0.06, 1.0)
const C_TOAST_BG := Color(0.08, 0.06, 0.02, 0.97)
const C_TOAST_BD := Color(0.75, 0.58, 0.15, 1.0)  # thick gold border for toast

const PANEL_W    : int = 280
const PANEL_H    : int = 360
const MARGIN_L   : int = 10
const MARGIN_T   : int = 10
const TOAST_W    : int = 560
const TOAST_H    : int = 64
const TOAST_DUR  : float = 4.0

# ---------------------------------------------------------------------------
# Nodes
# ---------------------------------------------------------------------------
var _panel:       Panel           = null
var _scroll:      ScrollContainer = null
var _list:        VBoxContainer   = null
var _close_btn:   Button          = null

var _toast:       Panel           = null
var _toast_label: Label           = null
var _toast_timer: float           = 0.0

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _visible_flag: bool  = false
var _unlocked:     Array = []   # Array of {id, name, desc, gold, xp}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 9
	_build_ui()
	_panel.visible = false
	_toast.visible = false

	# Connect Network signal safely
	var net := get_node_or_null("/root/Network")
	if net != null and net.has_signal("on_achievement_unlock"):
		net.on_achievement_unlock.connect(_on_achievement_unlock)


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var vp_size := Vector2(1280, 720)   # default; reposition uses get_visible_rect

	# --- Main panel ---
	_panel = Panel.new()
	_panel.position     = Vector2(MARGIN_L, MARGIN_T)
	_panel.size         = Vector2(PANEL_W, PANEL_H)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _make_style(C_BG, C_BORDER, 2, 4))
	add_child(_panel)

	# --- Title bar ---
	var title_bar := HBoxContainer.new()
	title_bar.position = Vector2(0, 0)
	title_bar.size     = Vector2(PANEL_W, 32)
	_panel.add_child(title_bar)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(10, 0)
	title_bar.add_child(spacer)

	var title_lbl := Label.new()
	title_lbl.text                  = "Achievements"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_color_override("font_color", C_GOLD)
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_bar.add_child(title_lbl)

	_close_btn = Button.new()
	_close_btn.text = " X "
	_close_btn.flat = true
	_close_btn.add_theme_color_override("font_color", C_DIM)
	_close_btn.add_theme_stylebox_override("hover",
			_make_style(Color(0.20, 0.05, 0.04, 1.0), Color(0.75, 0.15, 0.10, 1.0), 1, 3))
	_close_btn.pressed.connect(hide_panel)
	title_bar.add_child(_close_btn)

	# Divider
	var sep := Panel.new()
	sep.position = Vector2(0, 32)
	sep.size     = Vector2(PANEL_W, 2)
	sep.add_theme_stylebox_override("panel",
			_make_style(Color(0.40, 0.30, 0.10, 0.60), Color(0.40, 0.30, 0.10, 0.60), 0, 0))
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(sep)

	# Unlocked count label
	var count_lbl := Label.new()
	count_lbl.name     = "CountLabel"
	count_lbl.position = Vector2(10, 38)
	count_lbl.size     = Vector2(PANEL_W - 20, 18)
	count_lbl.text     = "0 unlocked"
	count_lbl.add_theme_color_override("font_color", C_DIM)
	count_lbl.add_theme_font_size_override("font_size", 11)
	_panel.add_child(count_lbl)

	# Scroll container
	_scroll = ScrollContainer.new()
	_scroll.position                = Vector2(6, 60)
	_scroll.size                    = Vector2(PANEL_W - 12, PANEL_H - 68)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	_panel.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)

	# --- Toast popup (bottom-centre, hidden by default) ---
	_toast = Panel.new()
	_toast.size         = Vector2(TOAST_W, TOAST_H)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_theme_stylebox_override("panel",
			_make_style(C_TOAST_BG, C_TOAST_BD, 2, 6))
	add_child(_toast)
	_reposition_toast()

	_toast_label = Label.new()
	_toast_label.position                = Vector2(10, 0)
	_toast_label.size                    = Vector2(TOAST_W - 20, TOAST_H)
	_toast_label.vertical_alignment      = VERTICAL_ALIGNMENT_CENTER
	_toast_label.horizontal_alignment    = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.autowrap_mode           = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.add_theme_color_override("font_color", C_TEXT)
	_toast_label.add_theme_font_size_override("font_size", 14)
	_toast_label.mouse_filter            = Control.MOUSE_FILTER_IGNORE
	_toast.add_child(_toast_label)

	get_viewport().size_changed.connect(_reposition_toast)


func _reposition_toast() -> void:
	if _toast == null:
		return
	var vp_size := get_viewport().get_visible_rect().size
	_toast.position = Vector2(
		vp_size.x / 2.0 - TOAST_W / 2.0,
		vp_size.y - TOAST_H - 100
	)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func toggle() -> void:
	if visible:
		hide_panel()
	else:
		show_panel()

func show_panel() -> void:
	_visible_flag  = true
	_panel.visible = true
	_refresh_list()


func hide_panel() -> void:
	_visible_flag  = false
	_panel.visible = false
	emit_signal("close_requested")


# ---------------------------------------------------------------------------
# Network handler
# ---------------------------------------------------------------------------

func _on_achievement_unlock(id: int, ach_name: String, desc: String,
		gold: int, xp: int) -> void:
	# Avoid duplicate entries
	for entry in _unlocked:
		if (entry as Dictionary).get("id", -1) == id:
			return

	_unlocked.append({"id": id, "name": ach_name, "desc": desc,
			"gold": gold, "xp": xp})

	if _visible_flag:
		_refresh_list()

	_show_toast(ach_name, desc, gold, xp)


# ---------------------------------------------------------------------------
# Process — toast countdown
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast_timer   = 0.0
			_toast.visible = false


# ---------------------------------------------------------------------------
# Toast
# ---------------------------------------------------------------------------

func _show_toast(ach_name: String, desc: String, gold: int, xp: int) -> void:
	_toast_label.text = (
		"[Achievement] %s  —  %s\n+%dg  +%d xp" % [ach_name, desc, gold, xp]
	)
	_toast.visible = true
	_toast_timer   = TOAST_DUR
	_reposition_toast()


# ---------------------------------------------------------------------------
# List rebuild
# ---------------------------------------------------------------------------

func _refresh_list() -> void:
	for child in _list.get_children():
		child.queue_free()

	var count_lbl := _panel.get_node_or_null("CountLabel") as Label
	if count_lbl != null:
		count_lbl.text = "%d unlocked" % _unlocked.size()

	if _unlocked.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No achievements unlocked yet."
		empty_lbl.add_theme_color_override("font_color", C_DIM)
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty_lbl)
		return

	var section_lbl := Label.new()
	section_lbl.text = "Unlocked"
	section_lbl.add_theme_color_override("font_color", C_GOLD)
	section_lbl.add_theme_font_size_override("font_size", 12)
	_list.add_child(section_lbl)

	for raw in _unlocked:
		var entry: Dictionary = raw as Dictionary
		var row := _build_row(entry)
		_list.add_child(row)


func _build_row(entry: Dictionary) -> Control:
	var bg := Panel.new()
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg.custom_minimum_size   = Vector2(PANEL_W - 24, 56)
	bg.add_theme_stylebox_override("panel",
			_make_style(Color(0.10, 0.08, 0.04, 0.60), C_BORDER, 1, 3))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vb := VBoxContainer.new()
	vb.position = Vector2(8, 4)
	vb.size     = Vector2(PANEL_W - 40, 50)
	vb.add_theme_constant_override("separation", 2)
	bg.add_child(vb)

	var name_lbl := Label.new()
	name_lbl.text = entry.get("name", "Unknown")
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.clip_text = true
	vb.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = entry.get("desc", "")
	desc_lbl.add_theme_color_override("font_color", C_GREY)
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(desc_lbl)

	var reward_lbl := Label.new()
	var g: int = entry.get("gold", 0)
	var x: int = entry.get("xp", 0)
	reward_lbl.text = "+%dg  +%dxp" % [g, x]
	reward_lbl.add_theme_color_override("font_color", C_GOLD)
	reward_lbl.add_theme_font_size_override("font_size", 10)
	vb.add_child(reward_lbl)

	return bg


# ---------------------------------------------------------------------------
# Input — toggle with A key
# ---------------------------------------------------------------------------

func _input(_event: InputEvent) -> void:
	pass  # Achievements accessed via C → Achieve tab


func _find_chat_ui() -> Node:
	var root := get_tree().get_root()
	return _find_by_script_basename(root, "chat_ui")


func _find_by_script_basename(node: Node, basename: String) -> Node:
	var scr: Script = node.get_script() as Script
	if scr != null:
		var path: String = (scr as Script).resource_path
		if path.get_file().get_basename().to_lower() == basename:
			return node
	for child in node.get_children():
		var found := _find_by_script_basename(child, basename)
		if found != null:
			return found
	return null


# ---------------------------------------------------------------------------
# Style helper
# ---------------------------------------------------------------------------

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
