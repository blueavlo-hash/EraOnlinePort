class_name SplashUI
extends CanvasLayer
## Era Online - Splash / main menu screen.
## When launched from the official launcher, shows "Logged in as [user]" + Play.
## When launched directly (no credentials), shows Play Online with IP entry.

signal play_pressed

const C_PANEL  := Color(0.08, 0.06, 0.03, 0.96)
const C_BORDER := Color(0.40, 0.30, 0.12, 1.0)
const C_GOLD   := Color(0.85, 0.65, 0.15, 1.0)
const C_TEXT   := Color(0.90, 0.85, 0.72, 1.0)
const C_DIM    := Color(0.55, 0.50, 0.38, 1.0)
const C_BTN    := Color(0.14, 0.10, 0.04, 0.80)
const C_BTN_HV := Color(0.22, 0.16, 0.06, 0.88)
const C_RED    := Color(0.42, 0.12, 0.10, 0.80)
const C_GREEN  := Color(0.12, 0.28, 0.08, 0.80)
const C_GREEN_HV := Color(0.18, 0.40, 0.12, 0.88)

## Set before add_child() when launching from the official launcher.
var _launcher_user: String = ""

var _status_lbl:  Label    = null
var _play_btn:    Button   = null
const _OptionsUIClass = preload("res://scripts/ui/options_ui.gd")
var _options_ui: Node = null


func _ready() -> void:
	layer = 5
	_build()
	# Play title music if the file exists
	var stream := load("res://assets/sounds/titlemusic.mp3") as AudioStream
	if stream != null:
		AudioManager._music_player.stream = stream
		AudioManager._music_player.volume_db = linear_to_db(AudioManager.music_volume)
		AudioManager._music_player.play()
		AudioManager._current_music_num = -1  # sentinel: custom file playing


func _build() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp == Vector2.ZERO:
		vp = Vector2(1280, 720)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var bg := TextureRect.new()
	bg.texture = _load_menu_background()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	root.add_child(bg)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.015, 0.01, 0.28)
	root.add_child(shade)

	var panel_size := Vector2(600, 420)
	var panel_pos := Vector2((vp.x - panel_size.x) / 2.0, (vp.y - panel_size.y) / 2.0)
	var panel_anchor_left   := panel_pos.x / vp.x
	var panel_anchor_top    := panel_pos.y / vp.y
	var panel_anchor_right  := (panel_pos.x + panel_size.x) / vp.x
	var panel_anchor_bottom := (panel_pos.y + panel_size.y) / vp.y

	var panel := Panel.new()
	panel.anchor_left   = panel_anchor_left
	panel.anchor_top    = panel_anchor_top
	panel.anchor_right  = panel_anchor_right
	panel.anchor_bottom = panel_anchor_bottom
	panel.offset_left   = 0; panel.offset_top    = 0
	panel.offset_right  = 0; panel.offset_bottom = 0
	var sb := StyleBoxFlat.new()
	sb.bg_color    = Color(0, 0, 0, 0)
	sb.draw_center = false
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)

	if _launcher_user != "":
		_build_launcher_panel(panel)
	else:
		_build_direct_panel(panel)  # dev/skip-launcher mode only

	# Version label (bottom-right of panel)
	var ver := Label.new()
	ver.text = "v0.5.4-alpha"
	ver.add_theme_font_size_override("font_size", 10)
	ver.add_theme_color_override("font_color", C_DIM)
	ver.size     = Vector2(580, 16)
	ver.position = Vector2(10, 354)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(ver)


## Layout when launched from official launcher — credentials already provided.
## Play starts disabled ("Connecting…"); main.gd calls set_ready() once auth'd.
func _build_launcher_panel(panel: Control) -> void:
	# "Logged in as [user]" label
	var login_lbl := Label.new()
	login_lbl.text = "Logged in as  %s" % _launcher_user
	login_lbl.add_theme_font_size_override("font_size", 14)
	login_lbl.add_theme_color_override("font_color", C_GOLD)
	login_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	login_lbl.size     = Vector2(580, 28)
	login_lbl.position = Vector2(10, 110)
	panel.add_child(login_lbl)

	# Status label (shows "Connecting…" / errors)
	_status_lbl = Label.new()
	_status_lbl.text = "Connecting to server…"
	_status_lbl.add_theme_font_size_override("font_size", 12)
	_status_lbl.add_theme_color_override("font_color", C_DIM)
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.size     = Vector2(580, 36)
	_status_lbl.position = Vector2(10, 144)
	panel.add_child(_status_lbl)

	# "Play" button — disabled until set_ready() is called
	_play_btn = _make_button("Play", C_GREEN, C_GREEN_HV)
	_play_btn.size     = Vector2(380, 56)
	_play_btn.position = Vector2(110, 186)
	_play_btn.disabled = true
	panel.add_child(_play_btn)
	_play_btn.pressed.connect(func(): play_pressed.emit())

	# "Options" button
	var btn_options := _make_button("Options", C_BTN, C_BTN_HV)
	btn_options.size     = Vector2(380, 40)
	btn_options.position = Vector2(110, 254)
	panel.add_child(btn_options)
	btn_options.pressed.connect(_on_options_pressed)

	# "Exit" button
	var btn_quit := _make_button("Exit", C_RED, Color(C_RED.r + 0.1, C_RED.g, C_RED.b, 1.0))
	btn_quit.size     = Vector2(380, 36)
	btn_quit.position = Vector2(110, 306)
	panel.add_child(btn_quit)
	btn_quit.pressed.connect(func(): get_tree().quit())


## Called by main.gd once the server has sent the char list — enables Play.
func set_ready(_chars: Array = []) -> void:
	if _status_lbl != null:
		_status_lbl.text = ""
	if _play_btn != null:
		_play_btn.disabled = false


## Called by main.gd on connection or auth failure.
func set_error(msg: String) -> void:
	if _status_lbl != null:
		_status_lbl.add_theme_color_override("font_color", C_RED)
		_status_lbl.text = msg
	if _play_btn != null:
		_play_btn.disabled = true


## Layout when launched directly (dev --skip-launcher mode only).
func _build_direct_panel(panel: Control) -> void:
	var btn_online := _make_button("Play Online", Color(0.14, 0.28, 0.10, 0.80),
		Color(0.20, 0.38, 0.13, 0.88))
	btn_online.size     = Vector2(380, 52)
	btn_online.position = Vector2(110, 150)
	panel.add_child(btn_online)
	btn_online.pressed.connect(func(): play_pressed.emit())

	var btn_options := _make_button("Options", C_BTN, C_BTN_HV)
	btn_options.size     = Vector2(380, 40)
	btn_options.position = Vector2(110, 214)
	panel.add_child(btn_options)
	btn_options.pressed.connect(_on_options_pressed)

	var btn_quit := _make_button("Exit", C_RED, Color(C_RED.r + 0.1, C_RED.g, C_RED.b, 1.0))
	btn_quit.size     = Vector2(380, 36)
	btn_quit.position = Vector2(110, 264)
	panel.add_child(btn_quit)
	btn_quit.pressed.connect(func(): get_tree().quit())


func _on_options_pressed() -> void:
	if _options_ui == null:
		_options_ui = _OptionsUIClass.new()
		add_child(_options_ui)
	_options_ui.open()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_button(text: String, bg: Color, hover: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", C_TEXT)
	var normal  := _box(bg, C_BORDER, 1)
	var hovered := _box(hover, C_GOLD, 1)
	btn.add_theme_stylebox_override("normal",   normal)
	btn.add_theme_stylebox_override("hover",    hovered)
	btn.add_theme_stylebox_override("pressed",  hovered)
	btn.add_theme_stylebox_override("focus",    normal)
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


func _load_menu_background() -> Texture2D:
	var tex := load("res://assets/graphics/mainmenu.png") as Texture2D
	if tex == null:
		push_warning("SplashUI: failed to load res://assets/graphics/mainmenu.png")
	return tex
