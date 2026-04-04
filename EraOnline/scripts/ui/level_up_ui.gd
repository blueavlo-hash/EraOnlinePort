class_name LevelUpUI
extends CanvasLayer
## Era Online - Level Up Fanfare UI
## Shows an animated panel when the player gains a level.
## Call show_level_up(new_level) to display it; auto-dismisses after SHOW_DURATION.

const SHOW_DURATION := 3.0
const FADE_IN_DUR   := 0.4
const FADE_OUT_DUR  := 0.5
const HOLD_DUR      := SHOW_DURATION - FADE_IN_DUR - FADE_OUT_DUR

const C_GOLD       := Color(0.95, 0.78, 0.10, 1.0)
const C_GOLD_DIM   := Color(0.75, 0.55, 0.08, 1.0)
const C_BG         := Color(0.06, 0.04, 0.02, 0.93)
const C_TEXT       := Color(0.92, 0.88, 0.72, 1.0)

var _root: Control = null
var _panel: PanelContainer = null
var _title_label: Label = null
var _sub_label: Label = null
var _tween: Tween = null
var _border_style: StyleBoxFlat = null


func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(340.0, 130.0)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH

	_border_style = StyleBoxFlat.new()
	_border_style.bg_color                   = C_BG
	_border_style.border_width_top           = 2
	_border_style.border_width_bottom        = 2
	_border_style.border_width_left          = 2
	_border_style.border_width_right         = 2
	_border_style.border_color               = C_GOLD
	_border_style.corner_radius_top_left     = 6
	_border_style.corner_radius_top_right    = 6
	_border_style.corner_radius_bottom_left  = 6
	_border_style.corner_radius_bottom_right = 6
	_panel.add_theme_stylebox_override("panel", _border_style)

	_root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(320.0, 110.0)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "LEVEL UP!"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_color_override("font_color", C_GOLD)
	_title_label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(_title_label)

	_sub_label = Label.new()
	_sub_label.text = ""
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.add_theme_color_override("font_color", C_TEXT)
	_sub_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_sub_label)


func show_level_up(new_level: int) -> void:
	_sub_label.text = "You are now level %d!" % new_level
	visible = true

	# Kill any existing tween
	if _tween != null:
		_tween.kill()

	# Reset state
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.7, 0.7)
	_panel.pivot_offset = _panel.size * 0.5

	# Play sound (snd 58 = click, snd 62 = level-up chime in VB6 — use whichever exists)
	AudioManager.play_sound(62)

	# Animate in
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_panel, "modulate:a", 1.0, FADE_IN_DUR) \
		.set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "scale", Vector2(1.0, 1.0), FADE_IN_DUR) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Gold border pulse during hold
	_tween.chain().tween_method(_pulse_border, 0.0, 1.0, HOLD_DUR)

	# Animate out
	_tween.chain().set_parallel(true)
	_tween.tween_property(_panel, "modulate:a", 0.0, FADE_OUT_DUR) \
		.set_ease(Tween.EASE_IN)
	_tween.tween_property(_panel, "scale", Vector2(0.92, 0.92), FADE_OUT_DUR) \
		.set_ease(Tween.EASE_IN)

	_tween.chain().tween_callback(_on_done)


func _pulse_border(t: float) -> void:
	## Oscillates border brightness during the hold phase.
	var pulse: float = 0.5 + 0.5 * sin(t * TAU * 2.5)
	_border_style.border_color = C_GOLD_DIM.lerp(C_GOLD, pulse)


func _on_done() -> void:
	visible = false
