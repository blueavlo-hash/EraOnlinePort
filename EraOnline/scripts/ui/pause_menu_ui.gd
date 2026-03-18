class_name PauseMenuUI
extends CanvasLayer

## ESC pause menu — Resume / Quit to Menu / Quit Game.
## Opens when ESC is pressed and no aim-mode is active.
## Blocks all _unhandled_key_input below it via CanvasLayer.

signal resume_requested
signal quit_to_menu_requested

const W := 240
const H := 310
const BTN_W := 180
const BTN_H := 38
const BTN_GAP := 14

var _panel: Panel = null
var _dim: ColorRect = null
var _visible_flag: bool = false
var _options_ui: Node = null

func _ready() -> void:
	layer = 20  # Above everything
	process_mode = Node.PROCESS_MODE_ALWAYS

	_panel = Panel.new()
	_panel.visible = false
	add_child(_panel)

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.06, 0.10, 0.95)
	bg.border_color = Color(0.55, 0.45, 0.20, 1.0)
	bg.set_border_width_all(2)
	bg.corner_radius_top_left    = 6
	bg.corner_radius_top_right   = 6
	bg.corner_radius_bottom_left = 6
	bg.corner_radius_bottom_right = 6
	_panel.add_theme_stylebox_override("panel", bg)

	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	_panel.position = Vector2((vp_size.x - W) * 0.5, (vp_size.y - H) * 0.5)
	_panel.size = Vector2(W, H)

	var title := Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.2, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 18)
	title.size = Vector2(W, 28)
	_panel.add_child(title)

	var sep := ColorRect.new()
	sep.color = Color(0.55, 0.45, 0.20, 0.6)
	sep.position = Vector2(20, 52)
	sep.size = Vector2(W - 40, 1)
	_panel.add_child(sep)

	_add_button("Resume",       0, _on_resume)
	_add_button("Options",      1, _on_options)
	_add_button("Quit to Menu", 2, _on_quit_menu)
	_add_button("Quit Game",    3, _on_quit_game)

	# Dim overlay behind the panel
	_dim = ColorRect.new()
	_dim.color = Color(0.0, 0.0, 0.0, 0.45)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.z_index = -1
	add_child(_dim)
	_dim.visible = false


func _add_button(label: String, index: int, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.size = Vector2(BTN_W, BTN_H)
	var bx := (W - BTN_W) * 0.5
	var by := 68 + index * (BTN_H + BTN_GAP)
	btn.position = Vector2(bx, by)
	btn.add_theme_font_size_override("font_size", 14)

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.15, 0.13, 0.10, 1.0)
	normal.border_color = Color(0.45, 0.38, 0.15, 1.0)
	normal.set_border_width_all(1)
	normal.corner_radius_top_left     = 4
	normal.corner_radius_top_right    = 4
	normal.corner_radius_bottom_left  = 4
	normal.corner_radius_bottom_right = 4

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.25, 0.22, 0.14, 1.0)
	hover.border_color = Color(0.75, 0.60, 0.20, 1.0)
	hover.set_border_width_all(1)
	hover.corner_radius_top_left     = 4
	hover.corner_radius_top_right    = 4
	hover.corner_radius_bottom_left  = 4
	hover.corner_radius_bottom_right = 4

	var pressed_sb := StyleBoxFlat.new()
	pressed_sb.bg_color = Color(0.10, 0.09, 0.06, 1.0)
	pressed_sb.border_color = Color(0.55, 0.45, 0.18, 1.0)
	pressed_sb.set_border_width_all(1)
	pressed_sb.corner_radius_top_left     = 4
	pressed_sb.corner_radius_top_right    = 4
	pressed_sb.corner_radius_bottom_left  = 4
	pressed_sb.corner_radius_bottom_right = 4

	btn.add_theme_stylebox_override("normal",   normal)
	btn.add_theme_stylebox_override("hover",    hover)
	btn.add_theme_stylebox_override("pressed",  pressed_sb)
	btn.add_theme_color_override("font_color",         Color(0.85, 0.80, 0.65, 1.0))
	btn.add_theme_color_override("font_hover_color",   Color(1.0,  0.95, 0.70, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.70, 0.65, 0.50, 1.0))

	# Quit Game gets a slightly red tint
	if label == "Quit Game":
		normal.border_color = Color(0.50, 0.20, 0.18, 1.0)
		hover.bg_color      = Color(0.28, 0.10, 0.10, 1.0)
		hover.border_color  = Color(0.80, 0.30, 0.25, 1.0)
		btn.add_theme_color_override("font_color",       Color(0.90, 0.65, 0.60, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(1.0,  0.75, 0.70, 1.0))

	btn.pressed.connect(callback)
	_panel.add_child(btn)


func open() -> void:
	if _visible_flag:
		return
	_visible_flag = true
	_panel.visible = true
	_dim.visible = true
	get_viewport().set_input_as_handled()


func close() -> void:
	if not _visible_flag:
		return
	_visible_flag = false
	_panel.visible = false
	_dim.visible = false


func is_open() -> bool:
	return _visible_flag


func _unhandled_key_input(event: InputEvent) -> void:
	if not _visible_flag:
		return
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
		close()
		resume_requested.emit()
		get_viewport().set_input_as_handled()


# ── Button callbacks ──────────────────────────────────────────────────────────

func _on_resume() -> void:
	close()
	resume_requested.emit()


func _on_options() -> void:
	if _options_ui == null:
		_options_ui = preload("res://scripts/ui/options_ui.gd").new()
		add_child(_options_ui)
	_options_ui.open()


func _on_quit_menu() -> void:
	close()
	quit_to_menu_requested.emit()


func _on_quit_game() -> void:
	get_tree().quit()
