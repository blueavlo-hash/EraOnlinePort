class_name BankUI
extends CanvasLayer
## Era Online - Bank UI
## Opens when interacting with a banker NPC.
## Two sections: player inventory (left) and bank storage (right).
## Click inventory item → deposit; click bank item → withdraw.
## Gold deposit/withdraw via input field at bottom.

const C_BG     := Color(0.04, 0.03, 0.02, 1.0)
const C_BORDER := Color(0.40, 0.30, 0.12, 1.0)
const C_GOLD   := Color(0.85, 0.65, 0.15, 1.0)
const C_TEXT   := Color(0.90, 0.85, 0.72, 1.0)
const C_DIM    := Color(0.55, 0.50, 0.38, 1.0)
const C_BTN    := Color(0.14, 0.10, 0.04, 1.0)
const C_BTN_HV := Color(0.22, 0.16, 0.06, 1.0)
const C_GREEN  := Color(0.18, 0.36, 0.12, 1.0)
const C_GREEN_HV := Color(0.25, 0.50, 0.16, 1.0)
const C_RED    := Color(0.50, 0.10, 0.08, 1.0)

const WIN_W := 620
const WIN_H := 480
const SCR_W := 1280
const SCR_H := 720

var _npc_id: int = 0
var _bank_items: Array = []   # {slot, obj_index, amount}
var _bank_gold: int = 0

var _backdrop: Panel
var _panel: Panel
var _title_lbl: Label
var _inv_vbox: VBoxContainer
var _bank_vbox: VBoxContainer
var _status_lbl: Label
var _player_gold_lbl: Label
var _bank_gold_lbl: Label
var _gold_input: LineEdit
var _deposit_gold_btn: Button
var _withdraw_gold_btn: Button


func _ready() -> void:
	layer = 7
	visible = false
	_build_ui()
	Network.on_bank_contents.connect(_on_bank_contents)
	PlayerState.inventory_changed.connect(_refresh_inv)
	PlayerState.stats_changed.connect(_refresh_gold_labels)


func open(npc_id: int) -> void:
	_npc_id = npc_id
	visible = true
	_refresh_inv()
	Network.send_bank_open(npc_id)


func _build_ui() -> void:
	_backdrop = Panel.new()
	_backdrop.position = Vector2.ZERO
	_backdrop.size = Vector2(SCR_W, SCR_H)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	var bd_style := StyleBoxFlat.new()
	bd_style.bg_color = Color(0, 0, 0, 0.45)
	_backdrop.add_theme_stylebox_override("panel", bd_style)
	_backdrop.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_close())
	add_child(_backdrop)

	var px := int(SCR_W / 2.0 - WIN_W / 2.0)
	var py := int(SCR_H / 2.0 - WIN_H / 2.0)
	_panel = Panel.new()
	_panel.position = Vector2(px, py)
	_panel.size = Vector2(WIN_W, WIN_H)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _make_style(C_BG, C_BORDER, 2, 4))
	add_child(_panel)

	# Title bar
	var title_hb := HBoxContainer.new()
	title_hb.position = Vector2(0, 0)
	title_hb.size = Vector2(WIN_W, 36)
	_panel.add_child(title_hb)

	var sp := Control.new(); sp.custom_minimum_size = Vector2(12, 0); title_hb.add_child(sp)
	_title_lbl = Label.new()
	_title_lbl.text = "Bank of Andoria"
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_lbl.add_theme_color_override("font_color", C_GOLD)
	_title_lbl.add_theme_font_size_override("font_size", 18)
	title_hb.add_child(_title_lbl)

	var close_btn := Button.new()
	close_btn.text = "  X  "; close_btn.flat = true
	close_btn.add_theme_color_override("font_color", C_DIM)
	close_btn.pressed.connect(_close)
	title_hb.add_child(close_btn)

	# Separator
	var sep := Panel.new()
	sep.position = Vector2(0, 36); sep.size = Vector2(WIN_W, 2)
	sep.add_theme_stylebox_override("panel", _make_style(Color(0.40,0.30,0.10,0.6), Color(0,0,0,0), 0, 0))
	_panel.add_child(sep)

	# Column headers
	var col_w := (WIN_W - 32) / 2

	var inv_hdr := Label.new()
	inv_hdr.text = "YOUR INVENTORY"
	inv_hdr.position = Vector2(8, 42)
	inv_hdr.size = Vector2(col_w, 20)
	inv_hdr.add_theme_color_override("font_color", C_GOLD)
	inv_hdr.add_theme_font_size_override("font_size", 11)
	_panel.add_child(inv_hdr)

	var bank_hdr := Label.new()
	bank_hdr.text = "BANK STORAGE"
	bank_hdr.position = Vector2(col_w + 24, 42)
	bank_hdr.size = Vector2(col_w, 20)
	bank_hdr.add_theme_color_override("font_color", C_GOLD)
	bank_hdr.add_theme_font_size_override("font_size", 11)
	_panel.add_child(bank_hdr)

	# Inventory scroll
	var inv_scroll := ScrollContainer.new()
	inv_scroll.position = Vector2(8, 62)
	inv_scroll.size = Vector2(col_w, 320)
	inv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(inv_scroll)

	_inv_vbox = VBoxContainer.new()
	_inv_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_vbox.add_theme_constant_override("separation", 3)
	inv_scroll.add_child(_inv_vbox)

	# Bank scroll
	var bank_scroll := ScrollContainer.new()
	bank_scroll.position = Vector2(col_w + 24, 62)
	bank_scroll.size = Vector2(col_w, 320)
	bank_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(bank_scroll)

	_bank_vbox = VBoxContainer.new()
	_bank_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bank_vbox.add_theme_constant_override("separation", 3)
	bank_scroll.add_child(_bank_vbox)

	# Vertical divider
	var vdiv := Panel.new()
	vdiv.position = Vector2(col_w + 16, 40)
	vdiv.size = Vector2(2, 344)
	vdiv.add_theme_stylebox_override("panel", _make_style(Color(0.40,0.30,0.10,0.5), Color(0,0,0,0), 0, 0))
	_panel.add_child(vdiv)

	# Footer separator
	var fsep := Panel.new()
	fsep.position = Vector2(0, 392); fsep.size = Vector2(WIN_W, 2)
	fsep.add_theme_stylebox_override("panel", _make_style(Color(0.40,0.30,0.10,0.6), Color(0,0,0,0), 0, 0))
	_panel.add_child(fsep)

	# Footer
	var footer := HBoxContainer.new()
	footer.position = Vector2(8, 398)
	footer.size = Vector2(WIN_W - 16, 70)
	footer.add_theme_constant_override("separation", 8)
	_panel.add_child(footer)

	var gold_col := VBoxContainer.new()
	gold_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(gold_col)

	_player_gold_lbl = Label.new()
	_player_gold_lbl.add_theme_color_override("font_color", C_GOLD)
	_player_gold_lbl.add_theme_font_size_override("font_size", 12)
	gold_col.add_child(_player_gold_lbl)

	_bank_gold_lbl = Label.new()
	_bank_gold_lbl.add_theme_color_override("font_color", C_GOLD)
	_bank_gold_lbl.add_theme_font_size_override("font_size", 12)
	gold_col.add_child(_bank_gold_lbl)

	var gold_input_row := HBoxContainer.new()
	gold_input_row.add_theme_constant_override("separation", 4)
	gold_col.add_child(gold_input_row)

	_gold_input = LineEdit.new()
	_gold_input.placeholder_text = "Amount"
	_gold_input.custom_minimum_size = Vector2(80, 24)
	_gold_input.add_theme_font_size_override("font_size", 12)
	gold_input_row.add_child(_gold_input)

	_deposit_gold_btn = Button.new()
	_deposit_gold_btn.text = "Deposit Gold"
	_deposit_gold_btn.custom_minimum_size = Vector2(100, 24)
	_deposit_gold_btn.add_theme_stylebox_override("normal", _make_style(C_GREEN, C_BORDER, 1, 3))
	_deposit_gold_btn.add_theme_stylebox_override("hover", _make_style(C_GREEN_HV, C_GOLD, 1, 3))
	_deposit_gold_btn.add_theme_color_override("font_color", C_TEXT)
	_deposit_gold_btn.add_theme_font_size_override("font_size", 11)
	_deposit_gold_btn.pressed.connect(_on_deposit_gold)
	gold_input_row.add_child(_deposit_gold_btn)

	_withdraw_gold_btn = Button.new()
	_withdraw_gold_btn.text = "Withdraw Gold"
	_withdraw_gold_btn.custom_minimum_size = Vector2(100, 24)
	_withdraw_gold_btn.add_theme_stylebox_override("normal", _make_style(C_BTN, C_BORDER, 1, 3))
	_withdraw_gold_btn.add_theme_stylebox_override("hover", _make_style(C_BTN_HV, C_GOLD, 1, 3))
	_withdraw_gold_btn.add_theme_color_override("font_color", C_TEXT)
	_withdraw_gold_btn.add_theme_font_size_override("font_size", 11)
	_withdraw_gold_btn.pressed.connect(_on_withdraw_gold)
	gold_input_row.add_child(_withdraw_gold_btn)

	_status_lbl = Label.new()
	_status_lbl.add_theme_color_override("font_color", C_TEXT)
	_status_lbl.add_theme_font_size_override("font_size", 12)
	footer.add_child(_status_lbl)

	var close_footer := Button.new()
	close_footer.text = "Close"
	close_footer.custom_minimum_size = Vector2(70, 32)
	close_footer.add_theme_stylebox_override("normal", _make_style(C_BTN, C_BORDER, 1, 3))
	close_footer.add_theme_stylebox_override("hover", _make_style(C_BTN_HV, C_GOLD, 1, 3))
	close_footer.add_theme_color_override("font_color", C_TEXT)
	close_footer.pressed.connect(_close)
	footer.add_child(close_footer)


func _refresh_inv() -> void:
	if not is_instance_valid(_inv_vbox):
		return
	for c in _inv_vbox.get_children():
		c.queue_free()
	var inv: Array = PlayerState.inventory
	for i in inv.size():
		var item: Dictionary = inv[i] as Dictionary
		if item.is_empty() or item.get("equipped", false):
			continue
		var obj: Dictionary = GameData.get_object(item.get("obj_index", 0))
		var name_str: String = obj.get("name", "?")
		var amount: int = item.get("amount", 1)
		var row := _make_item_row("%s ×%d" % [name_str, amount], "Deposit →", C_GREEN, C_GREEN_HV,
				func(): Network.send_bank_deposit(i))
		_inv_vbox.add_child(row)


func _on_bank_contents(items: Array, gold: int) -> void:
	_bank_items = items
	_bank_gold = gold
	_refresh_bank()
	_refresh_gold_labels()


func _refresh_bank() -> void:
	if not is_instance_valid(_bank_vbox):
		return
	for c in _bank_vbox.get_children():
		c.queue_free()
	for item in _bank_items:
		var obj: Dictionary = GameData.get_object(item.get("obj_index", 0))
		var name_str: String = obj.get("name", "?")
		var amount: int = item.get("amount", 1)
		var bslot: int = item.get("slot", 0)
		var row := _make_bank_withdraw_row(name_str, amount, bslot)
		_bank_vbox.add_child(row)


func _refresh_gold_labels() -> void:
	if not is_instance_valid(_player_gold_lbl):
		return
	_player_gold_lbl.text = "Your gold: %d" % PlayerState.stats.get("gold", 0)
	_bank_gold_lbl.text   = "Bank gold: %d" % _bank_gold


func _on_deposit_gold() -> void:
	var amount: int = int(_gold_input.text) if _gold_input.text.is_valid_int() else 0
	if amount <= 0:
		return
	Network.send_bank_deposit_gold(amount)
	_gold_input.text = ""


func _on_withdraw_gold() -> void:
	var amount: int = int(_gold_input.text) if _gold_input.text.is_valid_int() else 0
	if amount <= 0:
		return
	Network.send_bank_withdraw_gold(amount)
	_gold_input.text = ""


func _make_bank_withdraw_row(name_str: String, max_amount: int, bslot: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl := Label.new()
	lbl.text = "%s ×%d" % [name_str, max_amount]
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", C_TEXT)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.clip_text = true
	row.add_child(lbl)

	var amt_field := LineEdit.new()
	amt_field.text = str(max_amount)
	amt_field.custom_minimum_size = Vector2(42, 22)
	amt_field.max_length = 5
	row.add_child(amt_field)

	var btn := Button.new()
	btn.text = "← Take"
	btn.custom_minimum_size = Vector2(60, 22)
	btn.add_theme_stylebox_override("normal", _make_style(C_BTN, C_BORDER, 1, 3))
	btn.add_theme_stylebox_override("hover", _make_style(C_BTN_HV, C_GOLD, 1, 3))
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(func():
		var req: int = int(amt_field.text) if amt_field.text.is_valid_int() else max_amount
		Network.send_bank_withdraw(bslot, clampi(req, 1, max_amount)))
	row.add_child(btn)
	return row


func _make_item_row(label_text: String, btn_text: String,
		btn_col: Color, btn_hv: Color, callback: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", C_TEXT)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.clip_text = true
	row.add_child(lbl)

	var btn := Button.new()
	btn.text = btn_text
	btn.custom_minimum_size = Vector2(72, 22)
	btn.add_theme_stylebox_override("normal", _make_style(btn_col, C_BORDER, 1, 3))
	btn.add_theme_stylebox_override("hover", _make_style(btn_hv, C_GOLD, 1, 3))
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(callback)
	row.add_child(btn)
	return row


func _close() -> void:
	visible = false


func _make_style(bg: Color, border: Color, bw: int, cr: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg; s.border_color = border
	s.set_border_width_all(bw)
	s.corner_radius_top_left = cr; s.corner_radius_top_right = cr
	s.corner_radius_bottom_left = cr; s.corner_radius_bottom_right = cr
	return s
