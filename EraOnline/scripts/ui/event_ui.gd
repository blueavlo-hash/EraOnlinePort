class_name EventUI
extends CanvasLayer
## Era Online - World Event / Tournament / Login Reward UI
##
## No persistent panel — animates transient banners and popups in response to
## Network signals:
##
##   on_world_event_start   → full-width top banner, 5s, red/orange
##   on_world_event_end     → full-width top banner, 3s, green
##   on_tourney_start       → full-width top banner, 5s, blue
##   on_tourney_end         → centred result panel, 8s
##   on_tourney_scores      → small live scoreboard top-right (hidden on end)
##   on_login_reward        → bottom-right popup, 4s

# ---------------------------------------------------------------------------
# Color palette
# ---------------------------------------------------------------------------
const C_BG           := Color(0.05, 0.04, 0.02, 0.96)
const C_BORDER_GOLD  := Color(0.85, 0.65, 0.15, 1.0)
const C_BORDER_RED   := Color(0.75, 0.18, 0.10, 1.0)
const C_BORDER_GREEN := Color(0.20, 0.65, 0.18, 1.0)
const C_BORDER_BLUE  := Color(0.20, 0.45, 0.80, 1.0)
const C_TEXT         := Color(1.00, 1.00, 1.00, 1.0)
const C_GOLD         := Color(0.85, 0.65, 0.15, 1.0)
const C_DIM          := Color(0.55, 0.50, 0.38, 1.0)
const C_SILVER       := Color(0.75, 0.78, 0.82, 1.0)
const C_BRONZE       := Color(0.72, 0.45, 0.20, 1.0)

# Banner gradient colours
const C_BANNER_RED_A   := Color(0.40, 0.06, 0.04, 0.95)
const C_BANNER_RED_B   := Color(0.55, 0.20, 0.04, 0.95)
const C_BANNER_GREEN_A := Color(0.04, 0.30, 0.06, 0.95)
const C_BANNER_GREEN_B := Color(0.06, 0.45, 0.10, 0.95)
const C_BANNER_BLUE_A  := Color(0.04, 0.12, 0.38, 0.95)
const C_BANNER_BLUE_B  := Color(0.06, 0.22, 0.52, 0.95)

const BANNER_H       : int   = 52
const SCORE_W        : int   = 200
const SCORE_ROW_H    : int   = 22
const LOGIN_W        : int   = 340
const LOGIN_H        : int   = 60
const RESULT_W       : int   = 440
const RESULT_H       : int   = 300

# ---------------------------------------------------------------------------
# Nodes
# ---------------------------------------------------------------------------
var _banner:         Panel         = null
var _banner_label:   Label         = null
var _banner_timer:   float         = 0.0

var _result_panel:   Panel         = null
var _result_title:   Label         = null
var _result_list:    VBoxContainer = null
var _result_timer:   float         = 0.0

var _score_panel:    Panel         = null
var _score_title:    Label         = null
var _score_list:     VBoxContainer = null
var _tourney_active: bool          = false

var _login_popup:    Panel         = null
var _login_label:    Label         = null
var _login_timer:    float         = 0.0


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 11   # Above HUD (10) so banners are always on top
	_build_banner()
	_build_result_panel()
	_build_score_panel()
	_build_login_popup()

	var net := get_node_or_null("/root/Network")
	if net == null:
		return
	if net.has_signal("on_world_event_start"):
		net.on_world_event_start.connect(_on_world_event_start)
	if net.has_signal("on_world_event_end"):
		net.on_world_event_end.connect(_on_world_event_end)
	if net.has_signal("on_tourney_start"):
		net.on_tourney_start.connect(_on_tourney_start)
	if net.has_signal("on_tourney_end"):
		net.on_tourney_end.connect(_on_tourney_end)
	if net.has_signal("on_tourney_scores"):
		net.on_tourney_scores.connect(_on_tourney_scores)
	if net.has_signal("on_login_reward"):
		net.on_login_reward.connect(_on_login_reward)

	get_viewport().size_changed.connect(_reposition_all)


# ---------------------------------------------------------------------------
# Build helpers
# ---------------------------------------------------------------------------

func _build_banner() -> void:
	_banner = Panel.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible      = false
	add_child(_banner)

	_banner_label = Label.new()
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_banner_label.add_theme_color_override("font_color", C_TEXT)
	_banner_label.add_theme_font_size_override("font_size", 20)
	_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_child(_banner_label)
	_reposition_banner()


func _build_result_panel() -> void:
	_result_panel = Panel.new()
	_result_panel.size         = Vector2(RESULT_W, RESULT_H)
	_result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_panel.visible      = false
	_result_panel.add_theme_stylebox_override("panel",
			_make_style(Color(0.06, 0.04, 0.02, 0.96), C_BORDER_GOLD, 2, 6))
	add_child(_result_panel)

	_result_title = Label.new()
	_result_title.position              = Vector2(0, 12)
	_result_title.size                  = Vector2(RESULT_W, 30)
	_result_title.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	_result_title.add_theme_color_override("font_color", C_GOLD)
	_result_title.add_theme_font_size_override("font_size", 18)
	_result_title.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	_result_panel.add_child(_result_title)

	var sep := Panel.new()
	sep.position = Vector2(0, 46)
	sep.size     = Vector2(RESULT_W, 2)
	sep.add_theme_stylebox_override("panel",
			_make_style(C_BORDER_GOLD, C_BORDER_GOLD, 0, 0))
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_result_panel.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.position                = Vector2(10, 52)
	scroll.size                    = Vector2(RESULT_W - 20, RESULT_H - 62)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter            = Control.MOUSE_FILTER_IGNORE
	_result_panel.add_child(scroll)

	_result_list = VBoxContainer.new()
	_result_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_list.add_theme_constant_override("separation", 4)
	_result_list.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(_result_list)

	_reposition_result()


func _build_score_panel() -> void:
	_score_panel = Panel.new()
	_score_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_panel.visible      = false
	_score_panel.add_theme_stylebox_override("panel",
			_make_style(Color(0.04, 0.08, 0.20, 0.90), C_BORDER_BLUE, 1, 4))
	add_child(_score_panel)

	_score_title = Label.new()
	_score_title.text = "Tournament"
	_score_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_title.add_theme_color_override("font_color", Color(0.50, 0.75, 1.0, 1.0))
	_score_title.add_theme_font_size_override("font_size", 11)
	_score_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_panel.add_child(_score_title)

	_score_list = VBoxContainer.new()
	_score_list.add_theme_constant_override("separation", 2)
	_score_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_panel.add_child(_score_list)

	_reposition_score()


func _build_login_popup() -> void:
	_login_popup = Panel.new()
	_login_popup.size         = Vector2(LOGIN_W, LOGIN_H)
	_login_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_login_popup.visible      = false
	_login_popup.add_theme_stylebox_override("panel",
			_make_style(Color(0.06, 0.04, 0.02, 0.96), C_BORDER_GOLD, 2, 6))
	add_child(_login_popup)

	_login_label = Label.new()
	_login_label.position              = Vector2(10, 0)
	_login_label.size                  = Vector2(LOGIN_W - 20, LOGIN_H)
	_login_label.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	_login_label.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	_login_label.autowrap_mode         = TextServer.AUTOWRAP_WORD_SMART
	_login_label.add_theme_color_override("font_color", C_GOLD)
	_login_label.add_theme_font_size_override("font_size", 13)
	_login_label.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	_login_popup.add_child(_login_label)

	_reposition_login()


# ---------------------------------------------------------------------------
# Repositioning
# ---------------------------------------------------------------------------

func _reposition_all() -> void:
	_reposition_banner()
	_reposition_result()
	_reposition_score()
	_reposition_login()


func _reposition_banner() -> void:
	if _banner == null:
		return
	var vp := get_viewport().get_visible_rect().size
	_banner.position = Vector2(0, 0)
	_banner.size     = Vector2(vp.x, BANNER_H)
	if _banner_label != null:
		_banner_label.position = Vector2(0, 0)
		_banner_label.size     = Vector2(vp.x, BANNER_H)


func _reposition_result() -> void:
	if _result_panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	_result_panel.position = Vector2(
		vp.x / 2.0 - RESULT_W / 2.0,
		vp.y / 2.0 - RESULT_H / 2.0
	)


func _reposition_score() -> void:
	if _score_panel == null:
		return
	var vp      := get_viewport().get_visible_rect().size
	var entries := _score_list.get_child_count() if _score_list != null else 0
	var h       := 20 + entries * SCORE_ROW_H + 6
	_score_panel.size     = Vector2(SCORE_W, maxi(h, 50))
	_score_panel.position = Vector2(vp.x - SCORE_W - 10, 10)
	if _score_title != null:
		_score_title.position = Vector2(0, 2)
		_score_title.size     = Vector2(SCORE_W, 18)
	if _score_list != null:
		_score_list.position = Vector2(6, 22)
		_score_list.size     = Vector2(SCORE_W - 12, h - 26)


func _reposition_login() -> void:
	if _login_popup == null:
		return
	var vp := get_viewport().get_visible_rect().size
	_login_popup.position = Vector2(vp.x - LOGIN_W - 10, vp.y - LOGIN_H - 90)


# ---------------------------------------------------------------------------
# Process — countdown timers
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _banner_timer > 0.0:
		_banner_timer -= delta
		if _banner_timer <= 0.0:
			_banner_timer   = 0.0
			_banner.visible = false

	if _result_timer > 0.0:
		_result_timer -= delta
		if _result_timer <= 0.0:
			_result_timer         = 0.0
			_result_panel.visible = false

	if _login_timer > 0.0:
		_login_timer -= delta
		if _login_timer <= 0.0:
			_login_timer          = 0.0
			_login_popup.visible  = false


# ---------------------------------------------------------------------------
# Network handlers
# ---------------------------------------------------------------------------

func _on_world_event_start(event_name: String, location: String) -> void:
	var text: String = "INVASION!  %s is under attack!" % location
	if event_name != "" and event_name != "invasion":
		text = "%s — %s is under attack!" % [event_name.to_upper(), location]
	_show_banner(text, C_BANNER_RED_A, C_BANNER_RED_B, C_BORDER_RED, 5.0)


func _on_world_event_end(event_name: String, result: String) -> void:
	var text: String = result if result != "" else "%s has ended." % event_name
	_show_banner(text, C_BANNER_GREEN_A, C_BANNER_GREEN_B, C_BORDER_GREEN, 3.0)


func _on_tourney_start(duration_sec: int, prize_desc: String) -> void:
	_tourney_active = true
	var mins: int = duration_sec / 60
	var text: String = "FISHING TOURNAMENT!  %s  (%dm)" % [prize_desc, mins]
	_show_banner(text, C_BANNER_BLUE_A, C_BANNER_BLUE_B, C_BORDER_BLUE, 5.0)


func _on_tourney_end(results: Array) -> void:
	_tourney_active     = false
	_score_panel.visible = false
	_show_tourney_result(results)


func _on_tourney_scores(scores: Array) -> void:
	_update_tourney_scores(scores)


func _on_login_reward(streak_day: int, gold: int, message: String) -> void:
	_show_login_popup(streak_day, gold, message)


# ---------------------------------------------------------------------------
# Show helpers
# ---------------------------------------------------------------------------

func _show_banner(text: String, bg_a: Color, bg_b: Color,
		border: Color, duration: float) -> void:
	_reposition_banner()

	# Gradient-style background using a two-stop linear fill approximated
	# by choosing a midpoint blend for the flat StyleBoxFlat
	var mid_bg := Color(
		(bg_a.r + bg_b.r) * 0.5,
		(bg_a.g + bg_b.g) * 0.5,
		(bg_a.b + bg_b.b) * 0.5,
		(bg_a.a + bg_b.a) * 0.5
	)
	var sty := _make_style(mid_bg, border, 2, 0)
	# Thicker bottom border for visual weight
	sty.border_width_bottom = 3
	_banner.add_theme_stylebox_override("panel", sty)

	_banner_label.text = text
	_banner.visible    = true
	_banner_timer      = duration


func _show_login_popup(streak_day: int, gold: int, msg: String) -> void:
	_reposition_login()
	var text: String
	if msg != "":
		text = "Welcome back!\nDay %d streak — %dg reward!\n%s" % [streak_day, gold, msg]
	else:
		text = "Welcome back!\nDay %d streak — %dg reward!" % [streak_day, gold]
	_login_label.text    = text
	_login_popup.visible = true
	_login_timer         = 4.0


func _show_tourney_result(results: Array) -> void:
	for child in _result_list.get_children():
		child.queue_free()

	_result_title.text = "Tournament Results"

	if results.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No results available."
		empty_lbl.add_theme_color_override("font_color", C_DIM)
		empty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_result_list.add_child(empty_lbl)
	else:
		# Header row
		var header := _make_result_row_header()
		_result_list.add_child(header)

		var limit: int = mini(results.size(), 10)
		for i in limit:
			var entry: Dictionary = results[i] as Dictionary
			var rank := i + 1
			var name_str: String  = entry.get("name", "Unknown") as String
			var score_val: int    = entry.get("score", 0) as int
			var gold_val: int     = entry.get("gold", 0) as int
			var row := _make_result_row(rank, name_str, score_val, gold_val)
			_result_list.add_child(row)

	_reposition_result()
	_result_panel.visible = true
	_result_timer         = 8.0


func _update_tourney_scores(scores: Array) -> void:
	for child in _score_list.get_children():
		child.queue_free()

	var limit: int = mini(scores.size(), 5)
	for i in limit:
		var entry: Dictionary = scores[i] as Dictionary
		var rank: int         = i + 1
		var row := _make_score_row(rank, entry.get("name", "?") as String,
				entry.get("score", 0) as int)
		_score_list.add_child(row)

	_reposition_score()
	if _tourney_active:
		_score_panel.visible = true


# ---------------------------------------------------------------------------
# Result row builders
# ---------------------------------------------------------------------------

func _make_result_row_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var rank_h := Label.new()
	rank_h.text                  = "#"
	rank_h.custom_minimum_size   = Vector2(24, 0)
	rank_h.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	rank_h.add_theme_color_override("font_color", C_DIM)
	rank_h.add_theme_font_size_override("font_size", 11)
	rank_h.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	row.add_child(rank_h)

	var name_h := Label.new()
	name_h.text                  = "Player"
	name_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_h.add_theme_color_override("font_color", C_DIM)
	name_h.add_theme_font_size_override("font_size", 11)
	name_h.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_h)

	var score_h := Label.new()
	score_h.text                 = "Score"
	score_h.custom_minimum_size  = Vector2(60, 0)
	score_h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_h.add_theme_color_override("font_color", C_DIM)
	score_h.add_theme_font_size_override("font_size", 11)
	score_h.mouse_filter         = Control.MOUSE_FILTER_IGNORE
	row.add_child(score_h)

	var gold_h := Label.new()
	gold_h.text                  = "Prize"
	gold_h.custom_minimum_size   = Vector2(60, 0)
	gold_h.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	gold_h.add_theme_color_override("font_color", C_DIM)
	gold_h.add_theme_font_size_override("font_size", 11)
	gold_h.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	row.add_child(gold_h)

	return row


func _make_result_row(rank: int, player_name: String,
		score: int, gold: int) -> Control:
	var bg := Panel.new()
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg.custom_minimum_size   = Vector2(RESULT_W - 24, 28)
	var row_bg := Color(0.10, 0.08, 0.04, 0.55) if rank % 2 == 0 \
			else Color(0.07, 0.05, 0.02, 0.55)
	bg.add_theme_stylebox_override("panel",
			_make_style(row_bg, Color(0, 0, 0, 0), 0, 2))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.position = Vector2(4, 2)
	row.size     = Vector2(RESULT_W - 32, 24)
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(row)

	var name_col := _rank_colour(rank)

	var rank_lbl := Label.new()
	rank_lbl.text                  = "#%d" % rank
	rank_lbl.custom_minimum_size   = Vector2(28, 0)
	rank_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_RIGHT
	rank_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	rank_lbl.add_theme_color_override("font_color", name_col)
	rank_lbl.add_theme_font_size_override("font_size", 13)
	rank_lbl.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	row.add_child(rank_lbl)

	var name_lbl := Label.new()
	name_lbl.text                  = player_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", name_col)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.clip_text             = true
	name_lbl.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	var score_lbl := Label.new()
	score_lbl.text                   = str(score)
	score_lbl.custom_minimum_size    = Vector2(60, 0)
	score_lbl.horizontal_alignment   = HORIZONTAL_ALIGNMENT_RIGHT
	score_lbl.vertical_alignment     = VERTICAL_ALIGNMENT_CENTER
	score_lbl.add_theme_color_override("font_color", C_TEXT)
	score_lbl.add_theme_font_size_override("font_size", 13)
	score_lbl.mouse_filter           = Control.MOUSE_FILTER_IGNORE
	row.add_child(score_lbl)

	var gold_lbl := Label.new()
	gold_lbl.text                    = "%dg" % gold
	gold_lbl.custom_minimum_size     = Vector2(60, 0)
	gold_lbl.horizontal_alignment    = HORIZONTAL_ALIGNMENT_RIGHT
	gold_lbl.vertical_alignment      = VERTICAL_ALIGNMENT_CENTER
	gold_lbl.add_theme_color_override("font_color", C_GOLD)
	gold_lbl.add_theme_font_size_override("font_size", 13)
	gold_lbl.mouse_filter            = Control.MOUSE_FILTER_IGNORE
	row.add_child(gold_lbl)

	return bg


func _make_score_row(rank: int, player_name: String, score: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.custom_minimum_size = Vector2(SCORE_W - 12, SCORE_ROW_H)
	row.mouse_filter        = Control.MOUSE_FILTER_IGNORE

	var rank_col := _rank_colour(rank)

	var rank_lbl := Label.new()
	rank_lbl.text                = "#%d" % rank
	rank_lbl.custom_minimum_size = Vector2(20, 0)
	rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rank_lbl.vertical_alignment  = VERTICAL_ALIGNMENT_CENTER
	rank_lbl.add_theme_color_override("font_color", rank_col)
	rank_lbl.add_theme_font_size_override("font_size", 11)
	rank_lbl.mouse_filter        = Control.MOUSE_FILTER_IGNORE
	row.add_child(rank_lbl)

	var name_lbl := Label.new()
	name_lbl.text                  = player_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", rank_col)
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.clip_text             = true
	name_lbl.mouse_filter          = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	var score_lbl := Label.new()
	score_lbl.text                   = str(score)
	score_lbl.custom_minimum_size    = Vector2(44, 0)
	score_lbl.horizontal_alignment   = HORIZONTAL_ALIGNMENT_RIGHT
	score_lbl.vertical_alignment     = VERTICAL_ALIGNMENT_CENTER
	score_lbl.add_theme_color_override("font_color", Color(0.80, 0.90, 1.0, 1.0))
	score_lbl.add_theme_font_size_override("font_size", 11)
	score_lbl.mouse_filter           = Control.MOUSE_FILTER_IGNORE
	row.add_child(score_lbl)

	return row


func _rank_colour(rank: int) -> Color:
	match rank:
		1: return C_GOLD
		2: return C_SILVER
		3: return C_BRONZE
		_: return C_TEXT


# ---------------------------------------------------------------------------
# Style helper
# ---------------------------------------------------------------------------

func _make_style(bg: Color, border: Color, border_w: int, corner: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color                   = bg
	s.border_color               = border
	s.border_width_left          = border_w
	s.border_width_right         = border_w
	s.border_width_top           = border_w
	s.border_width_bottom        = border_w
	s.corner_radius_top_left     = corner
	s.corner_radius_top_right    = corner
	s.corner_radius_bottom_left  = corner
	s.corner_radius_bottom_right = corner
	return s
