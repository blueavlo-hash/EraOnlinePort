class_name TradeUI
extends CanvasLayer
## Era Online - Player Trade UI
## Shows when a trade is active. Left = your offers, Right = their offers.
## Drag/click inventory items to offer them. Confirm button locks in.
## Both players must confirm to complete the trade.

const C_BG     := Color(0.04, 0.03, 0.02, 1.0)
const C_BORDER := Color(0.40, 0.30, 0.12, 1.0)
const C_GOLD   := Color(0.85, 0.65, 0.15, 1.0)
const C_TEXT   := Color(0.90, 0.85, 0.72, 1.0)
const C_DIM    := Color(0.55, 0.50, 0.38, 1.0)
const C_BTN    := Color(0.14, 0.10, 0.04, 1.0)
const C_BTN_HV := Color(0.22, 0.16, 0.06, 1.0)
const C_GREEN  := Color(0.18, 0.36, 0.12, 1.0)
const C_GREEN_HV := Color(0.25, 0.50, 0.16, 1.0)
const C_CONFIRM := Color(0.10, 0.35, 0.10, 1.0)
const C_CONFIRM_ACTIVE := Color(0.12, 0.55, 0.12, 1.0)

const WIN_W := 560
const WIN_H := 420
const SCR_W := 1280
const SCR_H := 720

var _panel: Panel
var _their_name_lbl: Label
var _my_vbox: VBoxContainer
var _their_vbox: VBoxContainer
var _status_lbl: Label
var _confirm_btn: Button
var _cancel_btn: Button

var _my_confirmed: bool = false
var _their_confirmed: bool = false


func _ready() -> void:
	layer = 8
	visible = false
	_build_ui()
	Network.on_trade_state.connect(_on_trade_state)
	Network.on_trade_complete.connect(_on_trade_complete)
	Network.on_trade_cancelled.connect(_on_trade_cancelled)
	Network.on_trade_request.connect(_on_trade_request)


func _build_ui() -> void:
	var px := int(SCR_W / 2.0 - WIN_W / 2.0)
	var py := int(SCR_H / 2.0 - WIN_H / 2.0)
	_panel = Panel.new()
	_panel.position = Vector2(px, py)
	_panel.size = Vector2(WIN_W, WIN_H)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _make_style(C_BG, C_BORDER, 2, 4))
	add_child(_panel)

	# Title
	var title_hb := HBoxContainer.new()
	title_hb.position = Vector2(0, 0)
	title_hb.size = Vector2(WIN_W, 36)
	_panel.add_child(title_hb)
	var sp := Control.new(); sp.custom_minimum_size = Vector2(12, 0); title_hb.add_child(sp)
	_their_name_lbl = Label.new()
	_their_name_lbl.text = "Trading with ?"
	_their_name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_their_name_lbl.add_theme_color_override("font_color", C_GOLD)
	_their_name_lbl.add_theme_font_size_override("font_size", 16)
	title_hb.add_child(_their_name_lbl)

	# Separator
	var sep := Panel.new()
	sep.position = Vector2(0, 36); sep.size = Vector2(WIN_W, 2)
	sep.add_theme_stylebox_override("panel", _make_style(Color(0.40,0.30,0.10,0.6),Color(0,0,0,0),0,0))
	_panel.add_child(sep)

	var col_w := (WIN_W - 32) / 2

	# Column headers
	var my_hdr := Label.new()
	my_hdr.text = "YOUR OFFER"; my_hdr.position = Vector2(8, 42)
	my_hdr.add_theme_color_override("font_color", C_GOLD)
	my_hdr.add_theme_font_size_override("font_size", 11)
	_panel.add_child(my_hdr)

	var their_hdr := Label.new()
	their_hdr.text = "THEIR OFFER"; their_hdr.position = Vector2(col_w + 24, 42)
	their_hdr.add_theme_color_override("font_color", C_GOLD)
	their_hdr.add_theme_font_size_override("font_size", 11)
	_panel.add_child(their_hdr)

	# My items scroll
	var my_scroll := ScrollContainer.new()
	my_scroll.position = Vector2(8, 60); my_scroll.size = Vector2(col_w, 280)
	my_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(my_scroll)
	_my_vbox = VBoxContainer.new()
	_my_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_my_vbox.add_theme_constant_override("separation", 3)
	my_scroll.add_child(_my_vbox)

	# Their items scroll
	var their_scroll := ScrollContainer.new()
	their_scroll.position = Vector2(col_w + 24, 60); their_scroll.size = Vector2(col_w, 280)
	their_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(their_scroll)
	_their_vbox = VBoxContainer.new()
	_their_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_their_vbox.add_theme_constant_override("separation", 3)
	their_scroll.add_child(_their_vbox)

	# Vertical divider
	var vdiv := Panel.new()
	vdiv.position = Vector2(col_w + 16, 40); vdiv.size = Vector2(2, 300)
	vdiv.add_theme_stylebox_override("panel", _make_style(Color(0.40,0.30,0.10,0.5),Color(0,0,0,0),0,0))
	_panel.add_child(vdiv)

	# "Add Item" helper label
	var add_hint := Label.new()
	add_hint.text = "Right-click inventory items to offer them in trade."
	add_hint.position = Vector2(8, 344); add_hint.size = Vector2(WIN_W - 16, 20)
	add_hint.add_theme_color_override("font_color", C_DIM)
	add_hint.add_theme_font_size_override("font_size", 10)
	_panel.add_child(add_hint)

	# Footer separator
	var fsep := Panel.new()
	fsep.position = Vector2(0, 364); fsep.size = Vector2(WIN_W, 2)
	fsep.add_theme_stylebox_override("panel", _make_style(Color(0.40,0.30,0.10,0.6),Color(0,0,0,0),0,0))
	_panel.add_child(fsep)

	# Footer buttons
	var footer := HBoxContainer.new()
	footer.position = Vector2(8, 372); footer.size = Vector2(WIN_W - 16, 40)
	footer.add_theme_constant_override("separation", 8)
	_panel.add_child(footer)

	_status_lbl = Label.new()
	_status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_lbl.add_theme_color_override("font_color", C_TEXT)
	_status_lbl.add_theme_font_size_override("font_size", 12)
	footer.add_child(_status_lbl)

	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm"
	_confirm_btn.custom_minimum_size = Vector2(90, 32)
	_confirm_btn.add_theme_stylebox_override("normal", _make_style(C_CONFIRM, C_BORDER, 1, 3))
	_confirm_btn.add_theme_stylebox_override("hover", _make_style(C_CONFIRM_ACTIVE, C_GOLD, 1, 3))
	_confirm_btn.add_theme_color_override("font_color", C_TEXT)
	_confirm_btn.pressed.connect(func(): Network.send_trade_confirm())
	footer.add_child(_confirm_btn)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.custom_minimum_size = Vector2(80, 32)
	_cancel_btn.add_theme_stylebox_override("normal", _make_style(C_BTN, C_BORDER, 1, 3))
	_cancel_btn.add_theme_stylebox_override("hover", _make_style(Color(0.5,0.1,0.1),C_BORDER, 1, 3))
	_cancel_btn.add_theme_color_override("font_color", C_TEXT)
	_cancel_btn.pressed.connect(func(): Network.send_trade_cancel())
	footer.add_child(_cancel_btn)


func _on_trade_request(from_id: int, from_name: String) -> void:
	# Show a confirmation prompt in the chat or as a popup
	# For now just show in the existing trade UI with accept/decline buttons
	_their_name_lbl.text = "Trade request from %s" % from_name
	visible = true
	_status_lbl.text = "Accept or decline?"
	_confirm_btn.text = "Accept"
	var _prev_conns := _confirm_btn.pressed.get_connections()
	for conn in _prev_conns:
		_confirm_btn.pressed.disconnect(conn["callable"])
	_confirm_btn.pressed.connect(func():
		Network.send_trade_respond(true)
		_their_name_lbl.text = "Trading with %s" % from_name
		_confirm_btn.text = "Confirm"
		var _c2 := _confirm_btn.pressed.get_connections()
		for c in _c2:
			_confirm_btn.pressed.disconnect(c["callable"])
		_confirm_btn.pressed.connect(func(): Network.send_trade_confirm()))
	var _prev_cancel := _cancel_btn.pressed.get_connections()
	for conn in _prev_cancel:
		_cancel_btn.pressed.disconnect(conn["callable"])
	_cancel_btn.pressed.connect(func():
		Network.send_trade_respond(false)
		visible = false)


func _on_trade_state(my_items: Array, their_items: Array, my_conf: bool, their_conf: bool) -> void:
	visible = true
	_my_confirmed = my_conf
	_their_confirmed = their_conf

	for c in _my_vbox.get_children(): c.queue_free()
	for item in my_items:
		var obj: Dictionary = GameData.get_object(item.get("obj_index", 0))
		var lbl := Label.new()
		lbl.text = "%s ×%d" % [obj.get("name","?"), item.get("amount",1)]
		lbl.add_theme_color_override("font_color", C_TEXT)
		lbl.add_theme_font_size_override("font_size", 12)
		_my_vbox.add_child(lbl)

	for c in _their_vbox.get_children(): c.queue_free()
	for item in their_items:
		var obj: Dictionary = GameData.get_object(item.get("obj_index", 0))
		var lbl := Label.new()
		lbl.text = "%s ×%d" % [obj.get("name","?"), item.get("amount",1)]
		lbl.add_theme_color_override("font_color", C_TEXT)
		lbl.add_theme_font_size_override("font_size", 12)
		_their_vbox.add_child(lbl)

	var conf_text := ""
	if my_conf: conf_text += " [You: OK]"
	if their_conf: conf_text += " [Them: OK]"
	_status_lbl.text = conf_text


func _on_trade_complete() -> void:
	_status_lbl.text = "Trade complete!"
	await get_tree().create_timer(1.5).timeout
	visible = false


func _on_trade_cancelled(reason: String) -> void:
	visible = false


func _make_style(bg: Color, border: Color, bw: int, cr: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.set_border_width_all(bw)
	s.corner_radius_top_left = cr; s.corner_radius_top_right = cr
	s.corner_radius_bottom_left = cr; s.corner_radius_bottom_right = cr
	return s
