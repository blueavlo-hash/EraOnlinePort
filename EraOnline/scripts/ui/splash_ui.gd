class_name SplashUI
extends CanvasLayer
## Era Online - Splash / main menu screen.
## Shows game title and lets the player choose Online or Offline.

signal online_requested(address: String, port: int)

const C_PANEL  := Color(0.08, 0.06, 0.03, 0.96)
const C_BORDER := Color(0.40, 0.30, 0.12, 1.0)
const C_GOLD   := Color(0.85, 0.65, 0.15, 1.0)
const C_TEXT   := Color(0.90, 0.85, 0.72, 1.0)
const C_DIM    := Color(0.55, 0.50, 0.38, 1.0)
const C_BTN    := Color(0.14, 0.10, 0.04, 0.80)
const C_BTN_HV := Color(0.22, 0.16, 0.06, 0.88)
const C_RED    := Color(0.42, 0.12, 0.10, 0.80)

var _ip_panel:    Control  = null
var _ip_field:    LineEdit = null
var _port_field:  LineEdit = null
var _status_lbl:  Label    = null
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

	var panel_size := Vector2(600, 460)
	var panel_pos := Vector2((vp.x - panel_size.x) / 2.0, (vp.y - panel_size.y) / 2.0)
	var panel_anchor_left := panel_pos.x / vp.x
	var panel_anchor_top := panel_pos.y / vp.y
	var panel_anchor_right := (panel_pos.x + panel_size.x) / vp.x
	var panel_anchor_bottom := (panel_pos.y + panel_size.y) / vp.y

	var panel := Panel.new()
	panel.anchor_left = panel_anchor_left
	panel.anchor_top = panel_anchor_top
	panel.anchor_right = panel_anchor_right
	panel.anchor_bottom = panel_anchor_bottom
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.draw_center = false
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)

	# "Play Online" button
	var btn_online := _make_button("Play Online", Color(0.14, 0.28, 0.10, 0.80),
		Color(0.20, 0.38, 0.13, 0.88))
	btn_online.size     = Vector2(380, 70)
	btn_online.position = Vector2(110, 165)
	panel.add_child(btn_online)
	btn_online.pressed.connect(_on_online_pressed)

	# "Options" button
	var btn_options := _make_button("Options", C_BTN, C_BTN_HV)
	btn_options.size     = Vector2(380, 52)
	btn_options.position = Vector2(110, 254)
	panel.add_child(btn_options)
	btn_options.pressed.connect(_on_options_pressed)

	# "Quit" button
	var btn_quit := _make_button("Quit", C_RED, Color(C_RED.r + 0.1, C_RED.g, C_RED.b, 1.0))
	btn_quit.size     = Vector2(380, 40)
	btn_quit.position = Vector2(110, 316)
	panel.add_child(btn_quit)
	btn_quit.pressed.connect(func(): get_tree().quit())

	# IP entry sub-panel (hidden until "Play Online")
	_ip_panel = _build_ip_panel(panel)
	_ip_panel.visible = false

	# Status label at bottom (shifted down ~60px)
	_status_lbl = Label.new()
	_status_lbl.text = ""
	_status_lbl.add_theme_font_size_override("font_size", 12)
	_status_lbl.add_theme_color_override("font_color", C_RED)
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.size     = Vector2(580, 20)
	_status_lbl.position = Vector2(10, 366)
	panel.add_child(_status_lbl)

	var ver := Label.new()
	ver.text = "v0.5.0-alpha"
	ver.add_theme_font_size_override("font_size", 10)
	ver.add_theme_color_override("font_color", C_DIM)
	ver.size     = Vector2(580, 16)
	ver.position = Vector2(10, 382)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	panel.add_child(ver)


func _build_ip_panel(parent: Control) -> Control:
	var p := Panel.new()
	p.size     = Vector2(400, 180)
	p.position = Vector2(100, 155)
	p.add_theme_stylebox_override("panel", _box(Color(0.06, 0.05, 0.02, 0.98), C_BORDER, 1))
	parent.add_child(p)

	var lbl := Label.new()
	lbl.text = "Server Address"
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", C_TEXT)
	lbl.size = Vector2(380, 20); lbl.position = Vector2(10, 12)
	p.add_child(lbl)

	_ip_field = LineEdit.new()
	_ip_field.text        = "127.0.0.1"
	_ip_field.size        = Vector2(280, 32)
	_ip_field.position    = Vector2(10, 36)
	_ip_field.placeholder_text = "Server IP"
	p.add_child(_ip_field)

	var port_lbl := Label.new()
	port_lbl.text = "Port"
	port_lbl.add_theme_font_size_override("font_size", 13)
	port_lbl.add_theme_color_override("font_color", C_TEXT)
	port_lbl.size = Vector2(80, 20); port_lbl.position = Vector2(300, 12)
	p.add_child(port_lbl)

	_port_field = LineEdit.new()
	_port_field.text     = "6969"
	_port_field.size     = Vector2(80, 32)
	_port_field.position = Vector2(300, 36)
	p.add_child(_port_field)

	var confirm := _make_button("Connect", Color(0.14, 0.28, 0.10, 0.80),
		Color(0.20, 0.38, 0.13, 0.88))
	confirm.size     = Vector2(180, 44)
	confirm.position = Vector2(10, 88)
	p.add_child(confirm)
	confirm.pressed.connect(_on_connect_confirm)

	var cancel := _make_button("Cancel", C_BTN, C_BTN_HV)
	cancel.size     = Vector2(180, 44)
	cancel.position = Vector2(210, 88)
	p.add_child(cancel)
	cancel.pressed.connect(func(): _ip_panel.visible = false)

	return p


func _on_options_pressed() -> void:
	if _options_ui == null:
		_options_ui = _OptionsUIClass.new()
		add_child(_options_ui)
	_options_ui.open()


func _on_online_pressed() -> void:
	_ip_panel.visible = true
	_ip_field.grab_focus()


func _on_connect_confirm() -> void:
	var addr := _ip_field.text.strip_edges()
	var port_str := _port_field.text.strip_edges()
	if addr.is_empty():
		_status_lbl.text = "Please enter a server address."
		return
	var port := int(port_str)
	if port <= 0 or port > 65535:
		_status_lbl.text = "Invalid port number."
		return
	_ip_panel.visible = false
	online_requested.emit(addr, port)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_button(text: String, bg: Color, hover: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 20)
	btn.add_theme_color_override("font_color", C_TEXT)
	var normal := _box(bg, C_BORDER, 1)
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
