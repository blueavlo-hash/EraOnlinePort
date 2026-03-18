class_name OptionsUI
extends CanvasLayer
## Era Online - Options popup.
## Works from both splash menu and pause menu.
## Call open() to show, close() to hide.

signal closed

const C_PANEL  := Color(0.08, 0.06, 0.03, 0.96)
const C_BORDER := Color(0.40, 0.30, 0.12, 1.0)
const C_GOLD   := Color(0.85, 0.65, 0.15, 1.0)
const C_TEXT   := Color(0.90, 0.85, 0.72, 1.0)
const C_DIM    := Color(0.55, 0.50, 0.38, 1.0)
const C_BTN    := Color(0.14, 0.10, 0.04, 1.0)
const C_BTN_HV := Color(0.22, 0.16, 0.06, 1.0)
const C_RED    := Color(0.75, 0.15, 0.10, 1.0)

const PANEL_W := 550
const PANEL_H := 560

var _sfx_slider:   HSlider = null
var _music_slider: HSlider = null
var _key_btns:     Dictionary = {}   # action -> Button
var _listening_action: String = ""   # action currently waiting for a keypress
var _root: Control = null


func _ready() -> void:
	layer = 25
	visible = false
	_build()


func _build() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp == Vector2.ZERO:
		vp = Vector2(1280, 720)

	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Semi-transparent dim overlay
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(PANEL_W, PANEL_H)
	panel.position = Vector2((vp.x - PANEL_W) / 2.0, (vp.y - PANEL_H) / 2.0)
	panel.add_theme_stylebox_override("panel", _box(C_PANEL, C_BORDER, 2))
	_root.add_child(panel)

	var y := 20

	# Title
	var title := Label.new()
	title.text = "Options"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", C_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(PANEL_W - 20, 40)
	title.position = Vector2(10, y)
	panel.add_child(title)
	y += 50

	# Divider
	panel.add_child(_hdiv(y))
	y += 12

	# --- Audio section ---
	var audio_lbl := Label.new()
	audio_lbl.text = "Audio"
	audio_lbl.add_theme_font_size_override("font_size", 14)
	audio_lbl.add_theme_color_override("font_color", C_GOLD)
	audio_lbl.size = Vector2(PANEL_W - 20, 22)
	audio_lbl.position = Vector2(10, y)
	panel.add_child(audio_lbl)
	y += 26

	_add_slider_row(panel, "SFX Volume", y,
		GameSettings.sfx_volume,
		func(v: float): GameSettings.set_sfx_volume(v))
	_sfx_slider = _key_btns.get("__sfx__")  # stored via side-channel below
	y += 34

	_add_slider_row(panel, "Music Volume", y,
		GameSettings.music_volume,
		func(v: float): GameSettings.set_music_volume(v))
	y += 38

	# Divider
	panel.add_child(_hdiv(y))
	y += 12

	# --- Keybindings section ---
	var kb_lbl := Label.new()
	kb_lbl.text = "Keybindings"
	kb_lbl.add_theme_font_size_override("font_size", 14)
	kb_lbl.add_theme_color_override("font_color", C_GOLD)
	kb_lbl.size = Vector2(PANEL_W - 20, 22)
	kb_lbl.position = Vector2(10, y)
	panel.add_child(kb_lbl)
	y += 26

	# ScrollContainer for keybindings list
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(PANEL_W - 20, 200)
	scroll.position = Vector2(10, y)
	panel.add_child(scroll)
	y += 208

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	for action in GameSettings.ACTION_LABELS.keys():
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(row)

		var lbl := Label.new()
		lbl.text = GameSettings.ACTION_LABELS[action]
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", C_TEXT)
		lbl.custom_minimum_size = Vector2(200, 28)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var keycode: int = GameSettings.keybindings.get(action,
				GameSettings.DEFAULT_KEYS.get(action, KEY_NONE))
		var btn := _make_button(GameSettings.get_keycode_name(keycode), C_BTN, C_BTN_HV)
		btn.custom_minimum_size = Vector2(160, 28)
		var cap_action: String = action
		btn.pressed.connect(func(): _start_listen(cap_action))
		row.add_child(btn)
		_key_btns[action] = btn

	# Divider
	panel.add_child(_hdiv(y))
	y += 12

	# Close button
	var close_btn := _make_button("Close", C_BTN, C_BTN_HV)
	close_btn.size = Vector2(160, 40)
	close_btn.position = Vector2((PANEL_W - 160) / 2.0, y)
	close_btn.pressed.connect(close)
	panel.add_child(close_btn)


## Called each time the panel is opened; refreshes all values from GameSettings.
func open() -> void:
	_listening_action = ""
	_refresh()
	visible = true


func close() -> void:
	_listening_action = ""
	visible = false
	closed.emit()


func _refresh() -> void:
	if _sfx_slider != null:
		_sfx_slider.value = GameSettings.sfx_volume
	if _music_slider != null:
		_music_slider.value = GameSettings.music_volume
	for action in _key_btns.keys():
		var btn: Button = _key_btns[action]
		var keycode: int = GameSettings.keybindings.get(action,
				GameSettings.DEFAULT_KEYS.get(action, KEY_NONE))
		btn.text = GameSettings.get_keycode_name(keycode)


func _start_listen(action: String) -> void:
	_listening_action = action
	var btn: Button = _key_btns.get(action)
	if btn != null:
		btn.text = "Press a key..."


func _unhandled_key_input(event: InputEvent) -> void:
	if _listening_action.is_empty():
		return
	if not event is InputEventKey:
		return
	var kev := event as InputEventKey
	if not kev.pressed or kev.echo:
		return
	# Consume the event so nothing else processes it.
	get_viewport().set_input_as_handled()

	var keycode: int = kev.physical_keycode
	var action := _listening_action
	_listening_action = ""

	GameSettings.set_keybinding(action, keycode)

	var btn: Button = _key_btns.get(action)
	if btn != null:
		btn.text = GameSettings.get_keycode_name(keycode)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _add_slider_row(parent: Control, label_text: String, y: int,
		initial_value: float, on_changed: Callable) -> HSlider:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", C_TEXT)
	lbl.size = Vector2(160, 26)
	lbl.position = Vector2(10, y)
	parent.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step      = 0.01
	slider.value     = initial_value
	slider.size      = Vector2(330, 26)
	slider.position  = Vector2(180, y)
	slider.value_changed.connect(on_changed)
	parent.add_child(slider)

	# Store slider refs for refresh
	if label_text == "SFX Volume":
		_sfx_slider = slider
	elif label_text == "Music Volume":
		_music_slider = slider

	return slider


func _hdiv(y: int) -> ColorRect:
	var div := ColorRect.new()
	div.color    = C_BORDER
	div.size     = Vector2(PANEL_W - 40, 1)
	div.position = Vector2(20, y)
	return div


func _make_button(text: String, bg: Color, hover: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 14)
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
