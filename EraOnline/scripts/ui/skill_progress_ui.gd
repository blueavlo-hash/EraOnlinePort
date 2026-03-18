class_name SkillProgressUI
extends CanvasLayer
## Era Online - Skill Progress Bar UI
## Shows a countdown bar while the player is performing a timed skill action
## (Mining, Lumberjacking, Fishing, etc.).
##
## Call start_progress(skill_id, duration_ms) to begin.
## Call cancel() to hide immediately.
## The bar hides itself automatically when duration elapses.

## Skill names indexed 1-28 (index 0 is unused placeholder).
const SKILL_NAMES: Array = [
	"",              # 0 — unused
	"Cooking",       # 1
	"Musicianship",  # 2
	"Tailoring",     # 3
	"Carpenting",    # 4
	"Lumberjacking", # 5
	"Tactics",       # 6
	"Disguise",      # 7
	"Merchant",      # 8
	"Blacksmithing", # 9
	"Hiding",        # 10
	"Magery",        # 11
	"Lockpicking",   # 12
	"Pickpocketing", # 13
	"Stealth",       # 14
	"Poisoning",     # 15
	"Swordsmanship", # 16
	"Parrying",      # 17
	"Animal Taming", # 18
	"Religion Lore", # 19
	"Fishing",       # 20
	"Mining",        # 21
	"Backstabbing",  # 22
	"Healing",       # 23
	"Surviving",     # 24
	"Etiquette",     # 25
	"Streetwise",    # 26
	"Meditating",    # 27
	"Archery",       # 28
]

var _panel:    PanelContainer = null
var _label:    Label          = null
var _bar:      ProgressBar    = null

var _total_time: float = 0.0
var _elapsed:    float = 0.0


func _ready() -> void:
	layer = 11

	_panel = PanelContainer.new()
	add_child(_panel)

	# Style the panel with a dark background
	var style := StyleBoxFlat.new()
	style.bg_color         = Color(0.08, 0.08, 0.16, 0.92)
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_color     = Color(0.3, 0.5, 0.9, 1.0)
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300.0, 52.0)
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0, 1.0))
	_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(_label)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(280.0, 18.0)
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value     = 100.0
	_bar.fill_mode = ProgressBar.FILL_BEGIN_TO_END   # left → right fill
	_bar.show_percentage = false

	# Blue fill style
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(0.25, 0.55, 0.95, 1.0)
	fill_style.corner_radius_top_left     = 2
	fill_style.corner_radius_top_right    = 2
	fill_style.corner_radius_bottom_left  = 2
	fill_style.corner_radius_bottom_right = 2
	_bar.add_theme_stylebox_override("fill", fill_style)

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.1, 0.2, 1.0)
	_bar.add_theme_stylebox_override("background", bg_style)

	vbox.add_child(_bar)

	# Start hidden
	_panel.visible = false


func _process(delta: float) -> void:
	if not _panel.visible:
		return
	if _total_time <= 0.0:
		return

	_elapsed += delta
	var frac: float = 1.0 - _elapsed / _total_time
	_bar.value = clampf(frac * 100.0, 0.0, 100.0)

	if _elapsed >= _total_time:
		_panel.visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_reposition()


## Show and start the countdown progress bar.
## duration_ms == 0 means cancel/hide immediately.
func start_progress(skill_id: int, duration_ms: int) -> void:
	if duration_ms <= 0:
		_panel.visible = false
		return

	var skill_name: String = "Skill"
	if skill_id >= 1 and skill_id < SKILL_NAMES.size():
		skill_name = SKILL_NAMES[skill_id]
	_label.text  = skill_name + "..."
	_bar.value   = 100.0
	_total_time  = float(duration_ms) / 1000.0
	_elapsed     = 0.0

	_panel.visible = true
	_reposition()


## Hide the bar immediately (e.g. cancelled by server or player movement).
func cancel() -> void:
	_panel.visible = false


## Centre the panel horizontally at 70% of the viewport height.
func _reposition() -> void:
	if _panel == null:
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var p_size:  Vector2 = _panel.size
	_panel.position = Vector2(
		(vp_size.x - p_size.x) * 0.5,
		vp_size.y * 0.70
	)
