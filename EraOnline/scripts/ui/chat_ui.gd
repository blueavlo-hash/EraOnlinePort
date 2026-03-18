class_name ChatUI
extends CanvasLayer
## Era Online - Chat Box UI
## Scrollable chat history panel (bottom-left) with an optional input field.
## Layer 8 — sits below HUD (layer 10) so it never occludes stat bars or skill icons.
##
## Layout (1280×720 viewport, HUD_H = 80px):
##   History panel : x=8, y=452, w=520, h=180  (sits just above the 80px HUD)
##   Input row     : x=8, y=634, w=520, h=28    (hidden by default)
##
## Input flow:
##   Enter (closed)              → open input, grab focus
##   Enter (open, text present)  → send via Network.send_chat(), close input
##   Enter (open, empty)         → cancel / close input
##   Escape (open)               → cancel / close input

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const C_BG_TRANS := Color(0.04, 0.03, 0.02, 0.80)
const C_BORDER   := Color(0.40, 0.30, 0.12, 1.0)
const C_GOLD     := Color(0.85, 0.65, 0.15, 1.0)
const C_TEXT     := Color(0.90, 0.85, 0.72, 1.0)
const C_DIM      := Color(0.55, 0.50, 0.38, 1.0)
const C_INPUT_BG := Color(0.10, 0.08, 0.03, 0.95)
const C_BTN      := Color(0.14, 0.10, 0.04, 1.0)
const C_BTN_HV   := Color(0.22, 0.16, 0.06, 1.0)

const MAX_MESSAGES := 50

const PANEL_X  := 8
const PANEL_Y  := 452    # 640 - 8 - 180 (HUD at 80, viewport 720, panel 180 tall)
const PANEL_W  := 520
const PANEL_H  := 180
const INPUT_Y  := PANEL_Y + PANEL_H + 2   # 634
const INPUT_H  := 28
const BTN_W    := 30

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------

var _history_panel: Panel        = null
var _scroll:        ScrollContainer = null
var _vbox:          VBoxContainer = null

var _input_row:  Panel    = null
var _line_edit:  LineEdit = null
var _send_btn:   Button   = null

var _input_open:    bool = false
var _chat_expanded: bool = true
var _toggle_btn:    Button = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 8
	_build_ui()

	# Network signal connections — safe even in offline mode (signals just
	# never fire, so no null-check needed on Network itself).
	Network.on_chat.connect(_on_net_chat)
	Network.on_server_msg.connect(_on_server_msg)


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# ---- History panel ----
	_history_panel = Panel.new()
	_history_panel.size = Vector2(PANEL_W, PANEL_H)
	_history_panel.position = Vector2(PANEL_X, PANEL_Y)
	_history_panel.add_theme_stylebox_override("panel",
			_make_box(C_BG_TRANS, C_BORDER, 1))
	# Non-interactive by default — doesn't block game clicks.
	_history_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_history_panel)

	# Collapse/expand toggle button (top-right corner of history panel)
	_toggle_btn = Button.new()
	_toggle_btn.text = "−"
	_toggle_btn.size = Vector2(18, 14)
	_toggle_btn.position = Vector2(PANEL_W - 20, 2)
	_toggle_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	_toggle_btn.add_theme_font_size_override("font_size", 10)
	_toggle_btn.add_theme_stylebox_override("normal",
			_make_box(Color(0.10, 0.08, 0.03, 0.85), C_BORDER, 1))
	_toggle_btn.add_theme_stylebox_override("hover",
			_make_box(Color(0.20, 0.15, 0.05, 0.95), C_GOLD, 1))
	_toggle_btn.add_theme_stylebox_override("pressed",
			_make_box(Color(0.06, 0.04, 0.01, 0.95), C_BORDER, 1))
	_toggle_btn.add_theme_color_override("font_color", C_DIM)
	_toggle_btn.pressed.connect(_on_chat_toggle)

	# Scroll container inside history panel
	_scroll = ScrollContainer.new()
	_scroll.size = Vector2(PANEL_W - 4, PANEL_H - 4)
	_scroll.position = Vector2(2, 2)
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Hide the scrollbar so it doesn't eat clicks when panel is passive
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_history_panel.add_child(_scroll)
	_history_panel.add_child(_toggle_btn)

	# VBox for message labels
	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.size_flags_vertical   = Control.SIZE_SHRINK_END
	# Set minimum width so labels wrap correctly
	_vbox.custom_minimum_size = Vector2(PANEL_W - 12, 0)
	_scroll.add_child(_vbox)

	# ---- Input row (hidden by default) ----
	_input_row = Panel.new()
	_input_row.size = Vector2(PANEL_W, INPUT_H)
	_input_row.position = Vector2(PANEL_X, INPUT_Y)
	_input_row.add_theme_stylebox_override("panel",
			_make_box(C_INPUT_BG, C_BORDER, 1))
	_input_row.visible = false
	add_child(_input_row)

	# LineEdit inside input row
	_line_edit = LineEdit.new()
	_line_edit.size = Vector2(PANEL_W - BTN_W - 4, INPUT_H - 2)
	_line_edit.position = Vector2(1, 1)
	_line_edit.placeholder_text = "Type a message..."
	_line_edit.add_theme_stylebox_override("normal",
			_make_box(C_INPUT_BG, Color(0, 0, 0, 0), 0))
	_line_edit.add_theme_stylebox_override("focus",
			_make_box(C_INPUT_BG, C_GOLD, 1))
	_line_edit.add_theme_color_override("font_color", C_TEXT)
	_line_edit.add_theme_color_override("font_placeholder_color", C_DIM)
	_line_edit.add_theme_font_size_override("font_size", 12)
	_line_edit.text_submitted.connect(_on_line_submitted)
	_input_row.add_child(_line_edit)

	# Send button
	_send_btn = Button.new()
	_send_btn.text = ">"
	_send_btn.size = Vector2(BTN_W, INPUT_H - 2)
	_send_btn.position = Vector2(PANEL_W - BTN_W - 1, 1)
	_send_btn.add_theme_stylebox_override("normal",
			_make_box(C_BTN, C_BORDER, 1))
	_send_btn.add_theme_stylebox_override("hover",
			_make_box(C_BTN_HV, C_GOLD, 1))
	_send_btn.add_theme_stylebox_override("pressed",
			_make_box(C_BTN_HV, C_GOLD, 1))
	_send_btn.add_theme_color_override("font_color", C_GOLD)
	_send_btn.add_theme_font_size_override("font_size", 14)
	_send_btn.pressed.connect(_on_send_pressed)
	_input_row.add_child(_send_btn)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Returns true when the input field is currently open.
## Called from world_map.gd to suppress movement/action hotkeys.
func is_input_open() -> bool:
	return _input_open


## Add a chat message to the history.
## chat_type: 0 = normal, 1 = system/gold, 2 = combat orange-red
func add_message(text: String, chat_type: int = 0) -> void:
	var col: Color
	match chat_type:
		1:  col = C_GOLD
		2:  col = Color(0.9, 0.4, 0.2, 1.0)
		_:  col = C_TEXT

	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(lbl)

	# Trim oldest messages if over limit
	while _vbox.get_child_count() > MAX_MESSAGES:
		var oldest := _vbox.get_child(0)
		_vbox.remove_child(oldest)
		oldest.queue_free()

	# Scroll to bottom deferred (layout must be updated first)
	_scroll_to_bottom.call_deferred()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return

	if _input_open:
		if key.physical_keycode == KEY_ESCAPE:
			_close_input()
			get_viewport().set_input_as_handled()
		elif key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_KP_ENTER:
			# text_submitted signal from LineEdit handles Enter — but consume
			# the raw key here so the game doesn't also react to it.
			get_viewport().set_input_as_handled()
	else:
		if key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_KP_ENTER:
			_open_input()
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Input open / close helpers
# ---------------------------------------------------------------------------

func _on_chat_toggle() -> void:
	_chat_expanded = not _chat_expanded
	_scroll.visible       = _chat_expanded
	_toggle_btn.text      = "−" if _chat_expanded else "+"
	if _chat_expanded:
		_history_panel.size = Vector2(PANEL_W, PANEL_H)
		_history_panel.position = Vector2(PANEL_X, PANEL_Y)
	else:
		# Collapsed: shrink to just the toggle button row
		_history_panel.size = Vector2(PANEL_W, 18)
		_history_panel.position = Vector2(PANEL_X, PANEL_Y + PANEL_H - 18)
		if _input_open:
			_close_input()


func _open_input() -> void:
	# Auto-expand chat when typing
	if not _chat_expanded:
		_on_chat_toggle()

	_input_open = true
	_input_row.visible = true
	_line_edit.text = ""
	_line_edit.grab_focus()

	# History panel becomes opaque and interactive when input is open
	_history_panel.add_theme_stylebox_override("panel",
			_make_box(Color(C_BG_TRANS.r, C_BG_TRANS.g, C_BG_TRANS.b, 0.95),
					C_BORDER, 1))
	_history_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll_to_bottom.call_deferred()


func _close_input() -> void:
	_input_open = false
	_input_row.visible = false
	_line_edit.text = ""
	_line_edit.release_focus()

	# Restore translucent / non-interactive state
	_history_panel.add_theme_stylebox_override("panel",
			_make_box(C_BG_TRANS, C_BORDER, 1))
	_history_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER


func _send_message() -> void:
	var txt := _line_edit.text.strip_edges()
	if txt.is_empty():
		_close_input()
		return
	# Play a soft click to confirm the message was sent
	AudioManager.play_sound(58)  # snd58 = CLICK (VB6 SOUND_CLICK)
	if Network.state == Network.State.CONNECTED:
		Network.send_chat(txt)
	else:
		# Offline: echo locally so the chat box is testable without a server.
		add_message("[You]: " + txt, 0)
	_close_input()


# ---------------------------------------------------------------------------
# Signal callbacks
# ---------------------------------------------------------------------------

func _on_line_submitted(text: String) -> void:
	# LineEdit fires this on Enter — mirror the _send_message logic.
	if text.strip_edges().is_empty():
		_close_input()
	else:
		_send_message()


func _on_send_pressed() -> void:
	_send_message()


func _on_net_chat(char_id: int, chat_type: int, message: String) -> void:
	var prefix: String
	if char_id == Network.local_char_id:
		prefix = "[You]: "
	else:
		prefix = "[%d]: " % char_id
	add_message(prefix + message, chat_type)


func _on_server_msg(message: String) -> void:
	add_message("* " + message, 1)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _scroll_to_bottom() -> void:
	# Setting scroll_vertical to a very large value clamps to the actual max.
	_scroll.scroll_vertical = 999999


func _make_box(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.corner_radius_top_left     = 3
	s.corner_radius_top_right    = 3
	s.corner_radius_bottom_left  = 3
	s.corner_radius_bottom_right = 3
	return s
