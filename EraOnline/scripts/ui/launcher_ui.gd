class_name LauncherUI
extends CanvasLayer
## Era Online - Launcher UI
##
## Shown as the startup screen when the game is run normally.
## Handles HTTP-based login/registration against the Go server's REST API,
## issues a launcher token, saves it to user://session.dat, then
## switches to the main game scene.
##
## The session.dat format (newline-separated):
##   line 1: launcher token (64 hex chars)
##   line 2: server host address
##   line 3: TCP game port (default 6969)

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
const C_BG       := Color(0.05, 0.04, 0.02, 1.0)
const C_PANEL    := Color(0.09, 0.07, 0.03, 0.97)
const C_BORDER   := Color(0.40, 0.30, 0.12, 1.0)
const C_GOLD     := Color(0.85, 0.65, 0.15, 1.0)
const C_TEXT     := Color(0.90, 0.85, 0.72, 1.0)
const C_DIM      := Color(0.55, 0.50, 0.38, 1.0)
const C_BTN      := Color(0.14, 0.10, 0.04, 1.0)
const C_BTN_HV   := Color(0.22, 0.16, 0.06, 1.0)
const C_RED      := Color(0.75, 0.15, 0.10, 1.0)
const C_GREEN    := Color(0.18, 0.36, 0.12, 1.0)
const C_GREEN_HV := Color(0.25, 0.50, 0.16, 1.0)

# Server connection constants — not user-configurable.
const SERVER_IP         : String = "5.78.207.11"
const DEFAULT_HTTP_PORT : int    = 6970
const DEFAULT_GAME_PORT : int    = 6969

# ---------------------------------------------------------------------------
# Widgets (populated in _build)
# ---------------------------------------------------------------------------
var _server_field    : LineEdit = null
var _tabs            : TabContainer = null

# Login tab
var _login_user      : LineEdit = null
var _login_pass      : LineEdit = null
var _login_btn       : Button   = null

# Register tab
var _reg_user        : LineEdit = null
var _reg_pass        : LineEdit = null
var _reg_pass2       : LineEdit = null
var _reg_btn         : Button   = null

# Bottom area
var _status_lbl      : Label    = null
var _play_btn        : Button   = null
var _player_count_lbl : Label   = null

var _http            : HTTPRequest = null

# State
var _logged_in       : bool   = false
var _saved_token     : String = ""


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 5
	_build()
	_fetch_status()


# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------

func _build() -> void:
	var vp := Vector2(1280, 720)

	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# HTTPRequest node for all server communication.
	_http = HTTPRequest.new()
	_http.use_threads = true
	add_child(_http)
	_http.request_completed.connect(_on_http_response)

	var panel := Panel.new()
	panel.size     = Vector2(520, 430)
	panel.position = Vector2((vp.x - 520) / 2.0, (vp.y - 430) / 2.0)
	panel.add_theme_stylebox_override("panel", _box(C_PANEL, C_BORDER, 2))
	add_child(panel)

	# Title
	var title := Label.new()
	title.text = "Era Online"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", C_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(500, 48); title.position = Vector2(10, 12)
	panel.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Launcher"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", C_DIM)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.size = Vector2(500, 20); subtitle.position = Vector2(10, 56)
	panel.add_child(subtitle)

	# Server status (right-aligned, shows online count)
	_player_count_lbl = Label.new()
	_player_count_lbl.text = "checking..."
	_player_count_lbl.add_theme_font_size_override("font_size", 12)
	_player_count_lbl.add_theme_color_override("font_color", C_DIM)
	_player_count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_player_count_lbl.size = Vector2(500, 20); _player_count_lbl.position = Vector2(10, 82)
	panel.add_child(_player_count_lbl)

	# Tab container for Login / Register
	_tabs = TabContainer.new()
	_tabs.size = Vector2(500, 222)
	_tabs.position = Vector2(10, 108)
	panel.add_child(_tabs)

	_build_login_tab()
	_build_register_tab()

	# Status label
	_status_lbl = Label.new()
	_status_lbl.text = ""
	_status_lbl.add_theme_font_size_override("font_size", 12)
	_status_lbl.add_theme_color_override("font_color", C_DIM)
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.size = Vector2(500, 36); _status_lbl.position = Vector2(10, 336)
	panel.add_child(_status_lbl)

	# Play button (hidden until logged in)
	_play_btn = _make_btn("Play", C_GREEN, C_GREEN_HV)
	_play_btn.size = Vector2(500, 52); _play_btn.position = Vector2(10, 374)
	_play_btn.visible = false
	_play_btn.pressed.connect(_on_play_pressed)
	panel.add_child(_play_btn)

	# Version
	var ver := Label.new()
	ver.text = "v0.5.2-alpha"
	ver.add_theme_font_size_override("font_size", 10)
	ver.add_theme_color_override("font_color", C_DIM)
	ver.size = Vector2(500, 16); ver.position = Vector2(10, 412)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(ver)


func _build_login_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Login"
	_tabs.add_child(tab)
	tab.add_theme_constant_override("separation", 6)

	var u_lbl := Label.new()
	u_lbl.text = "Username"
	u_lbl.add_theme_color_override("font_color", C_TEXT)
	tab.add_child(u_lbl)

	_login_user = LineEdit.new()
	_login_user.placeholder_text = "Enter username"
	_login_user.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(_login_user)

	var p_lbl := Label.new()
	p_lbl.text = "Password"
	p_lbl.add_theme_color_override("font_color", C_TEXT)
	tab.add_child(p_lbl)

	_login_pass = LineEdit.new()
	_login_pass.secret = true
	_login_pass.placeholder_text = "Enter password"
	_login_pass.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_login_pass.text_submitted.connect(func(_t): _on_login_pressed())
	tab.add_child(_login_pass)

	_login_btn = _make_btn("Login", C_GREEN, C_GREEN_HV)
	_login_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_login_btn.pressed.connect(_on_login_pressed)
	tab.add_child(_login_btn)


func _build_register_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Register"
	_tabs.add_child(tab)
	tab.add_theme_constant_override("separation", 4)

	var u_lbl := Label.new()
	u_lbl.text = "Username"
	u_lbl.add_theme_color_override("font_color", C_TEXT)
	tab.add_child(u_lbl)

	_reg_user = LineEdit.new()
	_reg_user.placeholder_text = "Choose username (3-32 chars)"
	_reg_user.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(_reg_user)

	var p_lbl := Label.new()
	p_lbl.text = "Password"
	p_lbl.add_theme_color_override("font_color", C_TEXT)
	tab.add_child(p_lbl)

	_reg_pass = LineEdit.new()
	_reg_pass.secret = true
	_reg_pass.placeholder_text = "Choose password (min 6 chars)"
	_reg_pass.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(_reg_pass)

	var p2_lbl := Label.new()
	p2_lbl.text = "Confirm Password"
	p2_lbl.add_theme_color_override("font_color", C_TEXT)
	tab.add_child(p2_lbl)

	_reg_pass2 = LineEdit.new()
	_reg_pass2.secret = true
	_reg_pass2.placeholder_text = "Confirm password"
	_reg_pass2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.add_child(_reg_pass2)

	_reg_btn = _make_btn("Register", C_BTN, C_BTN_HV)
	_reg_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reg_btn.pressed.connect(_on_register_pressed)
	tab.add_child(_reg_btn)


# ---------------------------------------------------------------------------
# Server status fetch
# ---------------------------------------------------------------------------

func _fetch_status() -> void:
	var url := "http://%s:%d/status" % [SERVER_IP, DEFAULT_HTTP_PORT]
	var err := _http.request(url, [], HTTPClient.METHOD_GET)
	if err != OK:
		_player_count_lbl.text = "offline"


# ---------------------------------------------------------------------------
# Login
# ---------------------------------------------------------------------------

func _on_login_pressed() -> void:
	if _logged_in:
		return
	var user := _login_user.text.strip_edges()
	var pass_ := _login_pass.text
	if user.is_empty():
		_set_status("Please enter a username.", C_RED)
		return
	if pass_.is_empty():
		_set_status("Please enter a password.", C_RED)
		return
	_set_status("Logging in...", C_DIM)
	_login_btn.disabled = true
	_do_token_login(user, pass_)


func _do_token_login(username: String, password: String) -> void:
	var url := "http://%s:%d/api/auth/token" % [SERVER_IP, DEFAULT_HTTP_PORT]
	var body := JSON.stringify({"username": username, "password": password})
	var headers := ["Content-Type: application/json"]
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_login_btn.disabled = false
		_set_status("Could not reach server. Is it running?", C_RED)


# ---------------------------------------------------------------------------
# Register
# ---------------------------------------------------------------------------

func _on_register_pressed() -> void:
	var user := _reg_user.text.strip_edges()
	var pass_ := _reg_pass.text
	var pass2 := _reg_pass2.text
	if user.is_empty():
		_set_status("Please enter a username.", C_RED)
		return
	if pass_.is_empty():
		_set_status("Please enter a password.", C_RED)
		return
	if pass_ != pass2:
		_set_status("Passwords do not match.", C_RED)
		return
	_set_status("Registering...", C_DIM)
	_reg_btn.disabled = true
	var url := "http://%s:%d/api/register" % [SERVER_IP, DEFAULT_HTTP_PORT]
	var body := JSON.stringify({"username": user, "password": pass_})
	var headers := ["Content-Type: application/json"]
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_reg_btn.disabled = false
		_set_status("Could not reach server. Is it running?", C_RED)


# ---------------------------------------------------------------------------
# HTTP response handler (all requests route here)
# ---------------------------------------------------------------------------

func _on_http_response(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray) -> void:

	# Re-enable all submit buttons regardless of outcome.
	if _login_btn != null:
		_login_btn.disabled = false
	if _reg_btn != null:
		_reg_btn.disabled = false

	# Network error (result != OK means the request itself failed).
	if result != HTTPRequest.RESULT_SUCCESS:
		# Check if this was the status fetch (background, silent failure).
		_player_count_lbl.text = "offline"
		# Only show error if user was actively trying to log in / register.
		if not _status_lbl.text.is_empty() and \
				(_status_lbl.text.begins_with("Logging") or
				 _status_lbl.text.begins_with("Registering")):
			_set_status("Server unreachable. Check the address and ensure the server is running.", C_RED)
		return

	var text := body.get_string_from_utf8()
	var data: Variant = null
	var parse_err := JSON.parse_string(text)
	if parse_err != null:
		data = parse_err

	# /status  → just update player count label
	if response_code == 200 and data is Dictionary and data.has("online") and \
			not data.has("token"):
		var count := int(data.get("online", 0))
		_player_count_lbl.text = "%d online" % count
		return

	# /api/register
	if _tabs.get_current_tab() == 1:  # Register tab
		if response_code == 200 and data is Dictionary and data.get("ok", false):
			# Registration succeeded — switch to login tab with the username pre-filled.
			_login_user.text = _reg_user.text
			_reg_pass.text = ""
			_reg_pass2.text = ""
			_tabs.current_tab = 0
			_set_status("Registered! Now log in.", C_TEXT)
		else:
			var msg := _extract_error(data, response_code)
			_set_status(msg, C_RED)
		return

	# /api/auth/token  (Login tab)
	if response_code == 200 and data is Dictionary and data.has("token"):
		var token := str(data.get("token", ""))
		if token.is_empty():
			_set_status("Server returned empty token.", C_RED)
			return
		var username := _login_user.text.strip_edges()
		_save_session(token, username)
		_logged_in = true
		_saved_token = token
		_set_status("Logged in! Click Play to enter the world.", C_TEXT)
		_play_btn.visible = true
	else:
		var msg := _extract_error(data, response_code)
		_set_status(msg, C_RED)


func _extract_error(data: Variant, response_code: int) -> String:
	if data is Dictionary:
		var e := str(data.get("error", ""))
		if not e.is_empty():
			return e
	match response_code:
		0:      return "Could not connect to server."
		401:    return "Incorrect username or password."
		403:    return "Account is banned."
		404:    return "Server endpoint not found — server may be outdated."
		409:    return "Username already taken."
		429:    return "Too many requests. Please wait a moment."
		500:    return "Server error. Please try again later."
		_:      return "Unexpected response (HTTP %d)." % response_code


# ---------------------------------------------------------------------------
# session.dat persistence
# ---------------------------------------------------------------------------

func _save_session(token: String, username: String) -> void:
	var f := FileAccess.open("user://session.dat", FileAccess.WRITE)
	if f == null:
		push_warning("[LauncherUI] Could not write user://session.dat")
		return
	f.store_line(token)
	f.store_line("")         # server addr slot — ignored, hardcoded in Network
	f.store_line("")         # port slot — ignored, hardcoded in Network
	f.store_line(username)
	f.close()


# ---------------------------------------------------------------------------
# Play / Offline buttons
# ---------------------------------------------------------------------------

func _on_play_pressed() -> void:
	if not _logged_in or _saved_token.is_empty():
		_set_status("Please log in first.", C_RED)
		return
	Network.launcher_token = _saved_token
	Network.server_address = SERVER_IP
	Network.server_port    = DEFAULT_GAME_PORT
	var err := get_tree().change_scene_to_file("res://scenes/main/Main.tscn")
	if err != OK:
		_set_status("Failed to load game scene (%s)." % error_string(err), C_RED)




# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _set_status(msg: String, color: Color) -> void:
	_status_lbl.text  = msg
	_status_lbl.add_theme_color_override("font_color", color)


func _make_btn(text: String, bg: Color, hover: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 18)
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
