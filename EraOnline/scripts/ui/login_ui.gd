class_name LoginUI
extends CanvasLayer
## Era Online - Login / Register screen.
## Shown after the player picks a server address on SplashUI.

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

var _is_login_tab: bool   = true
var _user_field:   LineEdit = null
var _pass_field:   LineEdit = null
var _pass2_field:  LineEdit = null
var _pass2_row:    Control  = null
var _remember_check: CheckBox = null
var _status_lbl:   Label    = null
var _submit_btn:   Button   = null
var _toggle_btn:   Button   = null


func _ready() -> void:
	layer = 5
	_build()
	_connect_signals()
	# Prefill saved credentials
	if GameSettings.remember_me:
		_user_field.text = GameSettings.saved_username
		_pass_field.text = GameSettings.saved_password
		_remember_check.button_pressed = true


func _build() -> void:
	var vp := Vector2(1280, 720)

	var bg := ColorRect.new()
	bg.color = C_BG
	bg.size  = vp
	add_child(bg)

	var panel := Panel.new()
	panel.size     = Vector2(480, 360)
	panel.position = Vector2((vp.x - 480) / 2.0, (vp.y - 360) / 2.0)
	panel.add_theme_stylebox_override("panel", _box(C_PANEL, C_BORDER, 2))
	add_child(panel)

	# Title
	var title := Label.new()
	title.text = "Era Online"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", C_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(460, 44); title.position = Vector2(10, 14)
	panel.add_child(title)

	# Username
	var u_lbl := Label.new()
	u_lbl.text = "Username"
	u_lbl.add_theme_font_size_override("font_size", 13)
	u_lbl.add_theme_color_override("font_color", C_TEXT)
	u_lbl.size = Vector2(460, 20); u_lbl.position = Vector2(10, 68)
	panel.add_child(u_lbl)

	_user_field = LineEdit.new()
	_user_field.size = Vector2(460, 34); _user_field.position = Vector2(10, 90)
	_user_field.placeholder_text = "Enter username"
	panel.add_child(_user_field)

	# Password
	var p_lbl := Label.new()
	p_lbl.text = "Password"
	p_lbl.add_theme_font_size_override("font_size", 13)
	p_lbl.add_theme_color_override("font_color", C_TEXT)
	p_lbl.size = Vector2(460, 20); p_lbl.position = Vector2(10, 136)
	panel.add_child(p_lbl)

	_pass_field = LineEdit.new()
	_pass_field.secret = true
	_pass_field.size = Vector2(460, 34); _pass_field.position = Vector2(10, 158)
	_pass_field.placeholder_text = "Enter password"
	panel.add_child(_pass_field)

	# Remember Me checkbox (login only)
	_remember_check = CheckBox.new()
	_remember_check.text = "Remember Me"
	_remember_check.add_theme_font_size_override("font_size", 13)
	_remember_check.add_theme_color_override("font_color", C_DIM)
	_remember_check.size = Vector2(200, 28); _remember_check.position = Vector2(10, 200)
	panel.add_child(_remember_check)

	# Confirm Password row (register only)
	_pass2_row = Control.new()
	_pass2_row.size = Vector2(460, 58); _pass2_row.position = Vector2(10, 200)
	_pass2_row.visible = false
	panel.add_child(_pass2_row)

	var p2_lbl := Label.new()
	p2_lbl.text = "Confirm Password"
	p2_lbl.add_theme_font_size_override("font_size", 13)
	p2_lbl.add_theme_color_override("font_color", C_TEXT)
	p2_lbl.size = Vector2(460, 20); p2_lbl.position = Vector2(0, 0)
	_pass2_row.add_child(p2_lbl)

	_pass2_field = LineEdit.new()
	_pass2_field.secret = true
	_pass2_field.size = Vector2(460, 34); _pass2_field.position = Vector2(0, 22)
	_pass2_field.placeholder_text = "Confirm password"
	_pass2_row.add_child(_pass2_field)

	# Status label
	_status_lbl = Label.new()
	_status_lbl.text = "Connecting to server..."
	_status_lbl.add_theme_font_size_override("font_size", 12)
	_status_lbl.add_theme_color_override("font_color", C_DIM)
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.size = Vector2(460, 20); _status_lbl.position = Vector2(10, 272)
	panel.add_child(_status_lbl)

	# Submit button
	_submit_btn = _make_button("Login", C_GREEN, C_GREEN_HV)
	_submit_btn.size = Vector2(460, 46); _submit_btn.position = Vector2(10, 296)
	_submit_btn.disabled = true
	_submit_btn.pressed.connect(_on_submit)
	panel.add_child(_submit_btn)

	# Toggle link — switches between Login and Register modes
	_toggle_btn = Button.new()
	_toggle_btn.text = "New player? Register here"
	_toggle_btn.add_theme_font_size_override("font_size", 12)
	_toggle_btn.add_theme_color_override("font_color", C_DIM)
	_toggle_btn.add_theme_color_override("font_hover_color", C_GOLD)
	var _flat := StyleBoxEmpty.new()
	_toggle_btn.add_theme_stylebox_override("normal",  _flat)
	_toggle_btn.add_theme_stylebox_override("hover",   _flat)
	_toggle_btn.add_theme_stylebox_override("pressed", _flat)
	_toggle_btn.add_theme_stylebox_override("focus",   _flat)
	_toggle_btn.size = Vector2(460, 22); _toggle_btn.position = Vector2(10, 332)
	_toggle_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toggle_btn.pressed.connect(func(): _switch_tab(not _is_login_tab))
	panel.add_child(_toggle_btn)

	_switch_tab(true)


func _connect_signals() -> void:
	Network.connected_to_server.connect(_on_connected)
	Network.connection_failed.connect(_on_connection_failed)
	Network.disconnected_from_server.connect(_on_disconnected)
	Network.auth_failed.connect(_on_auth_failed)
	Network.char_list_received.connect(_on_char_list)


func _switch_tab(login: bool) -> void:
	_is_login_tab = login
	_pass2_row.visible = not login
	_remember_check.visible = login
	_submit_btn.text = "Login" if login else "Register"
	_toggle_btn.text = "New player? Register here" if login else "Already have an account? Login"


func _on_submit() -> void:
	var user  := _user_field.text.strip_edges()
	var pass_ := _pass_field.text
	if user.is_empty():
		_set_status("Please enter a username.", C_RED)
		return
	if pass_.is_empty():
		_set_status("Please enter a password.", C_RED)
		return
	if not _is_login_tab:
		if _pass_field.text != _pass2_field.text:
			_set_status("Passwords do not match.", C_RED)
			return
		_set_status("Registering...", C_DIM)
		_submit_btn.disabled = true
		Network.register_account(user, pass_)
	else:
		GameSettings.set_credentials(user, pass_, _remember_check.button_pressed)
		_set_status("Logging in...", C_DIM)
		_submit_btn.disabled = true
		Network.login(user, pass_)


func _on_connected() -> void:
	_set_status("Connected. Please log in.", C_TEXT)
	_submit_btn.disabled = false


func _on_connection_failed(reason: String) -> void:
	_set_status("Connection failed: " + reason, C_RED)


func _on_disconnected(_reason: String) -> void:
	_set_status("Disconnected.", C_RED)
	_submit_btn.disabled = true


func _on_auth_failed(reason: String) -> void:
	_set_status(reason, C_RED)
	_submit_btn.disabled = false


func _on_char_list(_chars: Array) -> void:
	visible = false  # CharSelectUI takes over


func _set_status(msg: String, color: Color) -> void:
	_status_lbl.text = msg
	_status_lbl.add_theme_color_override("font_color", color)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_button(text: String, bg: Color, hover: Color) -> Button:
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
