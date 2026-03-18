class_name LevelUpUI
extends CanvasLayer
## Era Online - Level Up Fanfare UI
## Shows a brief animated panel when the player gains a level.
## Call show_level_up(new_level) to display it; auto-dismisses after SHOW_DURATION.

const SHOW_DURATION := 3.0

var _panel: PanelContainer = null
var _title_label: Label = null
var _sub_label: Label = null
var _timer: float = 0.0


func _ready() -> void:
	layer = 18
	_build()
	visible = false


func _build() -> void:
	# Root control fills the viewport so we can anchor the panel to the centre.
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(320.0, 120.0)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH

	var style := StyleBoxFlat.new()
	style.bg_color                   = Color(0.06, 0.04, 0.02, 0.93)
	style.border_width_top           = 2
	style.border_width_bottom        = 2
	style.border_width_left          = 2
	style.border_width_right         = 2
	style.border_color               = Color(0.95, 0.78, 0.10, 1.0)
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	_panel.add_theme_stylebox_override("panel", style)

	root.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300.0, 100.0)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "LEVEL UP!"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.10, 1.0))
	_title_label.add_theme_font_size_override("font_size", 28)
	vbox.add_child(_title_label)

	_sub_label = Label.new()
	_sub_label.text = ""
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72, 1.0))
	_sub_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(_sub_label)


func show_level_up(new_level: int) -> void:
	_sub_label.text = "You are now level %d!" % new_level
	_timer = SHOW_DURATION
	visible = true


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		visible = false
