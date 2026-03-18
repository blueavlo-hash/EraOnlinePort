class_name LeaderboardUI
extends CanvasLayer
## Era Online - Leaderboard UI
##
## Collapsible right-side panel (250×400px) with four tabs:
##   0=Kills  1=Crafts  2=Level  3=Fishing
## Toggle with L key (when chat input is not open).
## Connects to Network.on_leaderboard_data.
## "Refresh" button sends Network.send_leaderboard_request(current_tab).
## Auto-requests all four boards when first opened.

# ---------------------------------------------------------------------------
# Color palette
# ---------------------------------------------------------------------------
const C_BG       := Color(0.05, 0.04, 0.02, 0.94)
const C_BORDER   := Color(0.40, 0.30, 0.12, 1.0)
const C_GOLD     := Color(0.85, 0.65, 0.15, 1.0)
const C_SILVER   := Color(0.75, 0.78, 0.82, 1.0)
const C_BRONZE   := Color(0.72, 0.45, 0.20, 1.0)
const C_TEXT     := Color(0.90, 0.85, 0.72, 1.0)
const C_DIM      := Color(0.55, 0.50, 0.38, 1.0)
const C_BTN      := Color(0.14, 0.10, 0.04, 1.0)
const C_BTN_HV   := Color(0.22, 0.16, 0.06, 1.0)
const C_TAB_ACT  := Color(0.18, 0.14, 0.07, 1.0)
const C_TAB_IDLE := Color(0.08, 0.06, 0.03, 1.0)

const PANEL_W    : int = 250
const PANEL_H    : int = 400
const MARGIN_R   : int = 10
const MARGIN_T   : int = 10

# ---------------------------------------------------------------------------
# Nodes
# ---------------------------------------------------------------------------
var _panel:        Panel          = null
var _tab_bar:      HBoxContainer  = null
var _tab_btns:     Array          = []   # 4 Button nodes
var _list:         VBoxContainer  = null
var _scroll:       ScrollContainer = null
var _refresh_btn:  Button         = null
var _status_lbl:   Label          = null

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _visible_flag:  bool  = false
var _first_open:    bool  = true
var _current_tab:   int   = 0
var _boards:        Array = [[], [], [], []]   # kills, crafts, level, fishing
var _tab_names:     Array = ["Kills", "Crafts", "Level", "Fishing"]


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 9
	_build_ui()
	_panel.visible = false

	var net := get_node_or_null("/root/Network")
	if net != null and net.has_signal("on_leaderboard_data"):
		net.on_leaderboard_data.connect(_on_leaderboard_data)


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_panel = Panel.new()
	_panel.size         = Vector2(PANEL_W, PANEL_H)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _make_style(C_BG, C_BORDER, 2, 4))
	add_child(_panel)
	_reposition()

	# Title bar
	var title_bar := HBoxContainer.new()
	title_bar.position = Vector2(0, 0)
	title_bar.size     = Vector2(PANEL_W, 30)
	_panel.add_child(title_bar)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(10, 0)
	title_bar.add_child(spacer)

	var title_lbl := Label.new()
	title_lbl.text                  = "Leaderboard"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_color_override("font_color", C_GOLD)
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_bar.add_child(title_lbl)

	_refresh_btn = Button.new()
	_refresh_btn.text = "Refresh"
	_refresh_btn.flat = true
	_refresh_btn.add_theme_color_override("font_color", C_DIM)
	_refresh_btn.add_theme_stylebox_override("hover",
			_make_style(C_BTN_HV, C_GOLD, 1, 3))
	_refresh_btn.add_theme_font_size_override("font_size", 11)
	_refresh_btn.pressed.connect(_on_refresh_pressed)
	title_bar.add_child(_refresh_btn)

	var close_btn := Button.new()
	close_btn.text = " X "
	close_btn.flat = true
	close_btn.add_theme_color_override("font_color", C_DIM)
	close_btn.add_theme_stylebox_override("hover",
			_make_style(Color(0.20, 0.05, 0.04, 1.0),
					Color(0.75, 0.15, 0.10, 1.0), 1, 3))
	close_btn.pressed.connect(hide_panel)
	title_bar.add_child(close_btn)

	# Divider under title
	var sep1 := Panel.new()
	sep1.position = Vector2(0, 30)
	sep1.size     = Vector2(PANEL_W, 2)
	sep1.add_theme_stylebox_override("panel",
			_make_style(Color(0.40, 0.30, 0.10, 0.60),
					Color(0.40, 0.30, 0.10, 0.60), 0, 0))
	sep1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(sep1)

	# Tab bar
	_tab_bar = HBoxContainer.new()
	_tab_bar.position = Vector2(0, 34)
	_tab_bar.size     = Vector2(PANEL_W, 26)
	_tab_bar.add_theme_constant_override("separation", 2)
	_panel.add_child(_tab_bar)

	for i in _tab_names.size():
		var tab_btn := Button.new()
		tab_btn.text                = _tab_names[i]
		tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_btn.flat                = true
		tab_btn.pressed.connect(_on_tab_pressed.bind(i))
		_style_tab(tab_btn, i == 0)
		_tab_bar.add_child(tab_btn)
		_tab_btns.append(tab_btn)

	# Divider under tabs
	var sep2 := Panel.new()
	sep2.position = Vector2(0, 62)
	sep2.size     = Vector2(PANEL_W, 2)
	sep2.add_theme_stylebox_override("panel",
			_make_style(Color(0.40, 0.30, 0.10, 0.60),
					Color(0.40, 0.30, 0.10, 0.60), 0, 0))
	sep2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(sep2)

	# Scroll container for the list
	_scroll = ScrollContainer.new()
	_scroll.position                = Vector2(6, 66)
	_scroll.size                    = Vector2(PANEL_W - 12, PANEL_H - 96)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	_panel.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	_scroll.add_child(_list)

	# Status / last-updated label
	_status_lbl = Label.new()
	_status_lbl.position = Vector2(6, PANEL_H - 26)
	_status_lbl.size     = Vector2(PANEL_W - 12, 22)
	_status_lbl.text     = ""
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.add_theme_color_override("font_color", C_DIM)
	_status_lbl.add_theme_font_size_override("font_size", 10)
	_panel.add_child(_status_lbl)

	get_viewport().size_changed.connect(_reposition)


func _reposition() -> void:
	if _panel == null:
		return
	var vp_size := get_viewport().get_visible_rect().size
	_panel.position = Vector2(vp_size.x - PANEL_W - MARGIN_R, MARGIN_T)


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
	if _first_open:
		_first_open = false
		_request_all_boards()
	else:
		_refresh_list()


func hide_panel() -> void:
	_visible_flag  = false
	_panel.visible = false


# ---------------------------------------------------------------------------
# Tab handling
# ---------------------------------------------------------------------------

func _on_tab_pressed(idx: int) -> void:
	_current_tab = idx
	for i in _tab_btns.size():
		_style_tab(_tab_btns[i] as Button, i == idx)
	_refresh_list()
	# Auto-fetch if the board is empty
	if (_boards[idx] as Array).is_empty():
		_send_leaderboard_request(idx)


func _style_tab(btn: Button, active: bool) -> void:
	if active:
		btn.add_theme_color_override("font_color", C_GOLD)
		btn.add_theme_stylebox_override("normal",
				_make_style(C_TAB_ACT, C_GOLD, 1, 0))
	else:
		btn.add_theme_color_override("font_color", C_DIM)
		btn.add_theme_stylebox_override("normal",
				_make_style(C_TAB_IDLE, Color(0, 0, 0, 0), 0, 0))
	btn.add_theme_stylebox_override("hover",
			_make_style(C_BTN_HV, C_GOLD, 1, 0))
	btn.add_theme_stylebox_override("pressed",
			_make_style(C_TAB_ACT, C_GOLD, 1, 0))
	btn.add_theme_font_size_override("font_size", 11)


# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

func _on_refresh_pressed() -> void:
	_status_lbl.text = "Loading..."
	_send_leaderboard_request(_current_tab)


func _request_all_boards() -> void:
	for i in _boards.size():
		_send_leaderboard_request(i)


func _send_leaderboard_request(type: int) -> void:
	var net := get_node_or_null("/root/Network")
	if net == null:
		return
	if net.get("state") != null and net.state != Network.State.CONNECTED:
		_status_lbl.text = "Not connected."
		return
	Network.send_leaderboard_request(type)


func _on_leaderboard_data(type: int, entries: Array) -> void:
	if type < 0 or type >= _boards.size():
		return
	_boards[type] = entries
	if type == _current_tab:
		_status_lbl.text = "Updated"
		_refresh_list()


# ---------------------------------------------------------------------------
# List rebuild
# ---------------------------------------------------------------------------

func _refresh_list() -> void:
	for child in _list.get_children():
		child.queue_free()

	var board: Array = _boards[_current_tab] as Array

	if board.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No data — press Refresh."
		empty_lbl.add_theme_color_override("font_color", C_DIM)
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list.add_child(empty_lbl)
		return

	var limit: int = mini(board.size(), 10)
	for i in limit:
		var entry: Dictionary = board[i] as Dictionary
		var rank: int         = i + 1
		var row := _build_row(rank, entry.get("name", "Unknown") as String,
				entry.get("score", 0) as int)
		_list.add_child(row)


func _build_row(rank: int, player_name: String, score: int) -> Control:
	var row := Panel.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size   = Vector2(PANEL_W - 18, 28)
	var row_bg := Color(0.10, 0.08, 0.04, 0.55) if rank % 2 == 0 \
			else Color(0.07, 0.05, 0.02, 0.55)
	row.add_theme_stylebox_override("panel",
			_make_style(row_bg, Color(0, 0, 0, 0), 0, 2))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hb := HBoxContainer.new()
	hb.position = Vector2(4, 2)
	hb.size     = Vector2(PANEL_W - 26, 24)
	hb.add_theme_constant_override("separation", 4)
	row.add_child(hb)

	# Rank number
	var rank_col: Color
	match rank:
		1: rank_col = C_GOLD
		2: rank_col = C_SILVER
		3: rank_col = C_BRONZE
		_: rank_col = C_DIM

	var rank_lbl := Label.new()
	rank_lbl.text                    = "#%d" % rank
	rank_lbl.custom_minimum_size     = Vector2(28, 0)
	rank_lbl.horizontal_alignment    = HORIZONTAL_ALIGNMENT_RIGHT
	rank_lbl.vertical_alignment      = VERTICAL_ALIGNMENT_CENTER
	rank_lbl.add_theme_color_override("font_color", rank_col)
	rank_lbl.add_theme_font_size_override("font_size", 12)
	hb.add_child(rank_lbl)

	# Name
	var name_col: Color
	match rank:
		1: name_col = C_GOLD
		2: name_col = C_SILVER
		3: name_col = C_BRONZE
		_: name_col = C_TEXT

	var name_lbl := Label.new()
	name_lbl.text                  = player_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", name_col)
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.clip_text             = true
	hb.add_child(name_lbl)

	# Score
	var score_lbl := Label.new()
	score_lbl.text                   = _format_score(score)
	score_lbl.custom_minimum_size    = Vector2(50, 0)
	score_lbl.horizontal_alignment   = HORIZONTAL_ALIGNMENT_RIGHT
	score_lbl.vertical_alignment     = VERTICAL_ALIGNMENT_CENTER
	score_lbl.add_theme_color_override("font_color", name_col)
	score_lbl.add_theme_font_size_override("font_size", 12)
	hb.add_child(score_lbl)

	return row


func _format_score(score: int) -> String:
	if score >= 1000000:
		return "%.1fM" % (float(score) / 1000000.0)
	elif score >= 1000:
		return "%.1fk" % (float(score) / 1000.0)
	return str(score)


# ---------------------------------------------------------------------------
# Input — toggle with L key
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_L:
		var chat_ui := _find_chat_ui()
		if chat_ui != null and chat_ui.has_method("is_input_open") \
				and chat_ui.is_input_open():
			return
		if _visible_flag:
			hide_panel()
		else:
			show_panel()
		get_viewport().set_input_as_handled()


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
