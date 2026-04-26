class_name DuelUI
extends CanvasLayer
## Era Online - Duel UI
## Challenge popup, active duel HUD (opponent HP + timer), spectator betting panel.

const C_BG      := Color(0.04, 0.03, 0.02, 1.0)
const C_BORDER  := Color(0.50, 0.35, 0.10, 1.0)
const C_GOLD    := Color(0.88, 0.68, 0.18, 1.0)
const C_TEXT    := Color(0.90, 0.85, 0.72, 1.0)
const C_DIM     := Color(0.55, 0.50, 0.38, 1.0)
const C_BTN     := Color(0.14, 0.10, 0.04, 1.0)
const C_BTN_HV  := Color(0.22, 0.16, 0.06, 1.0)
const C_RED     := Color(0.82, 0.14, 0.10, 1.0)
const C_GREEN   := Color(0.18, 0.55, 0.14, 1.0)
const C_GREEN_H := Color(0.25, 0.70, 0.18, 1.0)
const C_RED_H   := Color(0.60, 0.10, 0.08, 1.0)
const C_HP_FILL := Color(0.82, 0.14, 0.10, 1.0)
const C_HP_BG   := Color(0.22, 0.04, 0.03, 1.0)

const VW := 1280.0
const VH := 720.0

# ---------------------------------------------------------------------------
# Challenge popup
# ---------------------------------------------------------------------------
var _challenge_panel: Panel       = null
var _challenge_lbl:   Label       = null
var _challenger_id:   int         = 0

# ---------------------------------------------------------------------------
# Active duel HUD (shown while in a duel)
# ---------------------------------------------------------------------------
var _duel_hud:        Panel       = null
var _duel_opp_lbl:    Label       = null
var _duel_opp_hp_bg:  ColorRect   = null
var _duel_opp_hp_fill: ColorRect  = null
var _duel_timer_lbl:  Label       = null

var _in_duel:         bool        = false
var _opp_hp:          int         = 100
var _opp_max_hp:      int         = 100
var _duel_timer_sec:  float       = 300.0

# ---------------------------------------------------------------------------
# Spectator betting panel
# ---------------------------------------------------------------------------
var _bet_panel:       Panel       = null
var _bet_ch_lbl:      Label       = null
var _bet_tg_lbl:      Label       = null
var _bet_input:       LineEdit    = null
var _bet_ch_btn:      Button      = null
var _bet_tg_btn:      Button      = null
var _bet_result_lbl:  Label       = null

var _active_challenger_id: int    = 0
var _active_target_id:     int    = 0


func _ready() -> void:
	layer = 9
	_build_challenge_popup()
	_build_duel_hud()
	_build_bet_panel()

	Network.on_duel_challenge.connect(_on_duel_challenge)
	Network.on_duel_start.connect(_on_duel_start)
	Network.on_duel_end.connect(_on_duel_end)
	Network.on_duel_bet_ack.connect(_on_duel_bet_ack)
	Network.on_health.connect(_on_health)


func _process(delta: float) -> void:
	if _in_duel:
		_duel_timer_sec = maxf(0.0, _duel_timer_sec - delta)
		var m := int(_duel_timer_sec) / 60
		var s := int(_duel_timer_sec) % 60
		_duel_timer_lbl.text = "DUEL  %d:%02d" % [m, s]


# ---------------------------------------------------------------------------
# Challenge popup
# ---------------------------------------------------------------------------

func _build_challenge_popup() -> void:
	_challenge_panel = Panel.new()
	_challenge_panel.size     = Vector2(300, 110)
	_challenge_panel.position = Vector2(VW / 2.0 - 150, VH / 2.0 - 130)
	_challenge_panel.add_theme_stylebox_override("panel", _box(C_BG, C_BORDER, 2, 4))
	_challenge_panel.visible = false
	add_child(_challenge_panel)

	var title := Label.new()
	title.text = "⚔  DUEL CHALLENGE"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", C_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(300, 22); title.position = Vector2(0, 8)
	_challenge_panel.add_child(title)

	_challenge_lbl = Label.new()
	_challenge_lbl.text = "Someone challenges you to a duel!"
	_challenge_lbl.add_theme_font_size_override("font_size", 11)
	_challenge_lbl.add_theme_color_override("font_color", C_TEXT)
	_challenge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_challenge_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	_challenge_lbl.size = Vector2(280, 36); _challenge_lbl.position = Vector2(10, 34)
	_challenge_panel.add_child(_challenge_lbl)

	var acc := _make_btn("Accept", C_GREEN, C_GREEN_H)
	acc.size = Vector2(120, 28); acc.position = Vector2(16, 74)
	acc.pressed.connect(_on_accept_duel)
	_challenge_panel.add_child(acc)

	var dec := _make_btn("Decline", C_RED, C_RED_H)
	dec.size = Vector2(120, 28); dec.position = Vector2(164, 74)
	dec.pressed.connect(_on_decline_duel)
	_challenge_panel.add_child(dec)


func _on_duel_challenge(challenger_id: int, challenger_name: String) -> void:
	_challenger_id = challenger_id
	_challenge_lbl.text = "%s challenges you to a duel!\nPlacing bets will open to spectators." % challenger_name
	_challenge_panel.visible = true


func _on_accept_duel() -> void:
	_challenge_panel.visible = false
	Network.send_duel_respond(true)


func _on_decline_duel() -> void:
	_challenge_panel.visible = false
	Network.send_duel_respond(false)


# ---------------------------------------------------------------------------
# Active duel HUD
# ---------------------------------------------------------------------------

func _build_duel_hud() -> void:
	_duel_hud = Panel.new()
	_duel_hud.size     = Vector2(280, 52)
	_duel_hud.position = Vector2(VW / 2.0 - 140, 8)
	_duel_hud.add_theme_stylebox_override("panel", _box(C_BG, C_BORDER, 2, 4))
	_duel_hud.visible = false
	add_child(_duel_hud)

	_duel_timer_lbl = Label.new()
	_duel_timer_lbl.text = "DUEL  5:00"
	_duel_timer_lbl.add_theme_font_size_override("font_size", 13)
	_duel_timer_lbl.add_theme_color_override("font_color", C_GOLD)
	_duel_timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_duel_timer_lbl.size = Vector2(280, 18); _duel_timer_lbl.position = Vector2(0, 4)
	_duel_hud.add_child(_duel_timer_lbl)

	_duel_opp_lbl = Label.new()
	_duel_opp_lbl.text = "Opponent"
	_duel_opp_lbl.add_theme_font_size_override("font_size", 10)
	_duel_opp_lbl.add_theme_color_override("font_color", C_DIM)
	_duel_opp_lbl.size = Vector2(60, 14); _duel_opp_lbl.position = Vector2(8, 26)
	_duel_hud.add_child(_duel_opp_lbl)

	_duel_opp_hp_bg = ColorRect.new()
	_duel_opp_hp_bg.color = C_HP_BG
	_duel_opp_hp_bg.size  = Vector2(200, 14); _duel_opp_hp_bg.position = Vector2(72, 26)
	_duel_hud.add_child(_duel_opp_hp_bg)

	_duel_opp_hp_fill = ColorRect.new()
	_duel_opp_hp_fill.color = C_HP_FILL
	_duel_opp_hp_fill.size  = Vector2(200, 14); _duel_opp_hp_fill.position = Vector2(72, 26)
	_duel_hud.add_child(_duel_opp_hp_fill)


func _on_duel_start(opponent_id: int, opponent_name: String) -> void:
	_in_duel = true
	_duel_timer_sec = 300.0
	_duel_opp_lbl.text = opponent_name
	_active_challenger_id = Network.local_char_id  # for bet panel reference
	_active_target_id = opponent_id
	_duel_hud.visible = true
	# Show spectator betting panel for others watching — close for participants.
	_bet_panel.visible = false


func _on_health(hp: int, _mp: int, _sta: int) -> void:
	# We only update the opponent HP bar from S_SET_CHAR / S_DAMAGE in world_map.
	# This signal is the local player's HP. Nothing to do here for duel HUD.
	pass


func _refresh_opp_hp(hp: int, max_hp: int) -> void:
	_opp_hp = hp; _opp_max_hp = max_hp
	var frac := clampf(float(hp) / float(max(max_hp, 1)), 0.0, 1.0)
	_duel_opp_hp_fill.size.x = 200.0 * frac


# Called externally by world_map.gd when it receives S_SET_CHAR for the duel opponent.
func update_opponent_hp(hp: int, max_hp: int) -> void:
	if _in_duel:
		_refresh_opp_hp(hp, max_hp)


func _on_duel_end(result: int) -> void:
	_in_duel = false
	_duel_hud.visible = false
	_bet_panel.visible = false
	_challenge_panel.visible = false
	# result: 0=lost, 1=won, 2=cancelled — message shown via on_server_msg


# ---------------------------------------------------------------------------
# Spectator betting panel
# ---------------------------------------------------------------------------

func _build_bet_panel() -> void:
	_bet_panel = Panel.new()
	_bet_panel.size     = Vector2(280, 130)
	_bet_panel.position = Vector2(VW - 296, VH / 2.0 - 65)
	_bet_panel.add_theme_stylebox_override("panel", _box(C_BG, C_BORDER, 2, 4))
	_bet_panel.visible = false
	add_child(_bet_panel)

	var title := Label.new()
	title.text = "⚔  DUEL BETS"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", C_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(280, 20); title.position = Vector2(0, 6)
	_bet_panel.add_child(title)

	_bet_ch_lbl = Label.new()
	_bet_ch_lbl.text = "Challenger"
	_bet_ch_lbl.add_theme_font_size_override("font_size", 10)
	_bet_ch_lbl.add_theme_color_override("font_color", C_TEXT)
	_bet_ch_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bet_ch_lbl.size = Vector2(120, 16); _bet_ch_lbl.position = Vector2(8, 30)
	_bet_panel.add_child(_bet_ch_lbl)

	_bet_tg_lbl = Label.new()
	_bet_tg_lbl.text = "Opponent"
	_bet_tg_lbl.add_theme_font_size_override("font_size", 10)
	_bet_tg_lbl.add_theme_color_override("font_color", C_TEXT)
	_bet_tg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bet_tg_lbl.size = Vector2(120, 16); _bet_tg_lbl.position = Vector2(148, 30)
	_bet_panel.add_child(_bet_tg_lbl)

	var amt_lbl := Label.new()
	amt_lbl.text = "Bet (gold):"
	amt_lbl.add_theme_font_size_override("font_size", 10)
	amt_lbl.add_theme_color_override("font_color", C_DIM)
	amt_lbl.size = Vector2(80, 18); amt_lbl.position = Vector2(8, 52)
	_bet_panel.add_child(amt_lbl)

	_bet_input = LineEdit.new()
	_bet_input.placeholder_text = "amount"
	_bet_input.size = Vector2(180, 22); _bet_input.position = Vector2(92, 50)
	_bet_input.add_theme_font_size_override("font_size", 11)
	_bet_panel.add_child(_bet_input)

	_bet_ch_btn = _make_btn("Bet Challenger", C_BTN, C_BTN_HV)
	_bet_ch_btn.size = Vector2(126, 26); _bet_ch_btn.position = Vector2(8, 78)
	_bet_ch_btn.pressed.connect(_on_bet_challenger)
	_bet_panel.add_child(_bet_ch_btn)

	_bet_tg_btn = _make_btn("Bet Opponent", C_BTN, C_BTN_HV)
	_bet_tg_btn.size = Vector2(126, 26); _bet_tg_btn.position = Vector2(146, 78)
	_bet_tg_btn.pressed.connect(_on_bet_target)
	_bet_panel.add_child(_bet_tg_btn)

	_bet_result_lbl = Label.new()
	_bet_result_lbl.text = ""
	_bet_result_lbl.add_theme_font_size_override("font_size", 10)
	_bet_result_lbl.add_theme_color_override("font_color", C_DIM)
	_bet_result_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bet_result_lbl.size = Vector2(280, 16); _bet_result_lbl.position = Vector2(0, 110)
	_bet_panel.add_child(_bet_result_lbl)


# Called externally (e.g. from chat/world_map) to show the betting panel for a duel.
func show_duel_betting(challenger_id: int, challenger_name: String,
		target_id: int, target_name: String) -> void:
	if _in_duel:
		return  # participants don't see the bet panel
	_active_challenger_id = challenger_id
	_active_target_id     = target_id
	_bet_ch_lbl.text      = challenger_name
	_bet_tg_lbl.text      = target_name
	_bet_result_lbl.text  = ""
	_bet_panel.visible    = true


func _on_bet_challenger() -> void:
	var gold := int(_bet_input.text)
	if gold <= 0:
		return
	Network.send_duel_bet(_active_challenger_id, 0, gold)  # side 0 = challenger


func _on_bet_target() -> void:
	var gold := int(_bet_input.text)
	if gold <= 0:
		return
	Network.send_duel_bet(_active_challenger_id, 1, gold)  # side 1 = target


func _on_duel_bet_ack(success: bool, reason: String) -> void:
	if success:
		_bet_result_lbl.add_theme_color_override("font_color", C_GREEN)
		_bet_result_lbl.text = "Bet placed!"
		_bet_input.text = ""
	else:
		_bet_result_lbl.add_theme_color_override("font_color", C_RED)
		_bet_result_lbl.text = reason if reason != "" else "Bet failed."


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_btn(txt: String, bg: Color, hv: Color) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", 11)
	var n := StyleBoxFlat.new(); n.bg_color = bg; n.set_border_width_all(1); n.border_color = C_BORDER; n.corner_radius_top_left = 3; n.corner_radius_top_right = 3; n.corner_radius_bottom_left = 3; n.corner_radius_bottom_right = 3
	var h := StyleBoxFlat.new(); h.bg_color = hv; h.set_border_width_all(1); h.border_color = C_GOLD;   h.corner_radius_top_left = 3; h.corner_radius_top_right = 3; h.corner_radius_bottom_left = 3; h.corner_radius_bottom_right = 3
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", h)
	b.add_theme_color_override("font_color", Color(0.92, 0.86, 0.70, 1.0))
	return b


func _box(bg: Color, border: Color, bw: int, radius: int = 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.set_border_width_all(bw)
	s.corner_radius_top_left = radius; s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius; s.corner_radius_bottom_right = radius
	return s
