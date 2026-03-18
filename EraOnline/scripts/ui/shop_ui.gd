class_name ShopUI
extends CanvasLayer
## Era Online - Shop / Vendor UI
## Instantiated dynamically when Network.shop_list_received fires.
## Call open(shop_name, items, npc_id) to populate and show the panel.
## The UI removes itself via queue_free() on close.

# ---------------------------------------------------------------------------
# Color palette — dark medieval fantasy (matches project-wide style)
# ---------------------------------------------------------------------------
const C_BG       := Color(0.04, 0.03, 0.02, 1.0)
const C_PANEL    := Color(0.08, 0.06, 0.03, 0.96)
const C_BORDER   := Color(0.40, 0.30, 0.12, 1.0)
const C_GOLD     := Color(0.85, 0.65, 0.15, 1.0)
const C_TEXT     := Color(0.90, 0.85, 0.72, 1.0)
const C_DIM      := Color(0.55, 0.50, 0.38, 1.0)
const C_BTN      := Color(0.14, 0.10, 0.04, 1.0)
const C_BTN_HV   := Color(0.22, 0.16, 0.06, 1.0)
const C_RED      := Color(0.75, 0.15, 0.10, 1.0)
const C_GREEN    := Color(0.18, 0.36, 0.12, 1.0)
const C_GREEN_HV := Color(0.25, 0.50, 0.16, 1.0)

# ---------------------------------------------------------------------------
# Layout constants
# ---------------------------------------------------------------------------
const WIN_W    : int = 520
const WIN_H    : int = 440
const SCREE_W  : int = 1280
const SCREE_H  : int = 720

# ---------------------------------------------------------------------------
# Nodes
# ---------------------------------------------------------------------------
var _backdrop   : Panel          # Full-screen dim layer — click to close
var _panel      : Panel          # Main window
var _title_lbl  : Label
var _scroll     : ScrollContainer
var _item_vbox  : VBoxContainer
var _status_lbl : Label
var _gold_lbl   : Label
var _close_btn  : Button

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _npc_id       : int   = 0
var _items        : Array = []   # Array of {obj_index, price, name}
var _buy_buttons  : Array = []   # Parallel array of Button nodes, one per item row
var _busy         : bool  = false
var _sell_mode    : bool  = false


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Open the shop with the given data.
## items: Array of {obj_index: int, price: int, name: String}
func open(shop_name: String, items: Array, npc_id: int) -> void:
	_npc_id = npc_id
	_items  = items
	_title_lbl.text = shop_name
	_populate_items()
	_update_gold_label()
	visible = true


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer   = 6
	visible = false
	_build_ui()
	_connect_network_signals()


func _build_ui() -> void:
	# --- Full-screen semi-transparent backdrop ---
	_backdrop = Panel.new()
	_backdrop.position     = Vector2.ZERO
	_backdrop.size         = Vector2(SCREE_W, SCREE_H)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.add_theme_stylebox_override("panel",
			_make_style(Color(0.0, 0.0, 0.0, 0.40), Color(0, 0, 0, 0), 0, 0))
	_backdrop.gui_input.connect(_on_backdrop_input)
	add_child(_backdrop)

	# --- Main panel ---
	var px := int(SCREE_W / 2.0 - WIN_W / 2.0)
	var py := int(SCREE_H / 2.0 - WIN_H / 2.0)
	_panel = Panel.new()
	_panel.position     = Vector2(px, py)
	_panel.size         = Vector2(WIN_W, WIN_H)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _make_style(C_BG, C_BORDER, 2, 4))
	add_child(_panel)

	# --- Title bar ---
	var title_bar := _make_hbox(_panel, Vector2(0, 0), Vector2(WIN_W, 36))
	_title_lbl = Label.new()
	_title_lbl.text                     = "Shop"
	_title_lbl.size_flags_horizontal    = Control.SIZE_EXPAND_FILL
	_title_lbl.vertical_alignment       = VERTICAL_ALIGNMENT_CENTER
	_title_lbl.add_theme_color_override("font_color", C_GOLD)
	_title_lbl.add_theme_font_size_override("font_size", 22)
	# Left padding via a spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(12, 0)
	title_bar.add_child(spacer)
	title_bar.add_child(_title_lbl)

	_close_btn = Button.new()
	_close_btn.text  = "  X  "
	_close_btn.flat  = true
	_close_btn.add_theme_color_override("font_color", C_DIM)
	_close_btn.add_theme_stylebox_override("hover",
			_make_style(Color(0.20, 0.05, 0.04, 1), C_RED, 1, 3))
	_close_btn.pressed.connect(_on_close)
	title_bar.add_child(_close_btn)

	# --- Divider under title ---
	_make_hsep(_panel, 36)

	# --- Tab row: Buy / Sell ---
	var tab_row := HBoxContainer.new()
	tab_row.position = Vector2(12, 40)
	tab_row.size = Vector2(WIN_W - 24, 28)
	tab_row.add_theme_constant_override("separation", 2)
	_panel.add_child(tab_row)

	var buy_tab := Button.new()
	buy_tab.text = "Buy"
	buy_tab.custom_minimum_size = Vector2(80, 26)
	buy_tab.add_theme_stylebox_override("normal", _make_style(C_GREEN, C_BORDER, 1, 3))
	buy_tab.add_theme_stylebox_override("hover", _make_style(C_GREEN_HV, C_GOLD, 1, 3))
	buy_tab.add_theme_color_override("font_color", C_TEXT)
	buy_tab.add_theme_font_size_override("font_size", 12)
	buy_tab.pressed.connect(func(): _set_sell_mode(false))
	tab_row.add_child(buy_tab)

	var sell_tab := Button.new()
	sell_tab.text = "Sell"
	sell_tab.custom_minimum_size = Vector2(80, 26)
	sell_tab.add_theme_stylebox_override("normal", _make_style(C_BTN, C_BORDER, 1, 3))
	sell_tab.add_theme_stylebox_override("hover", _make_style(C_BTN_HV, C_GOLD, 1, 3))
	sell_tab.add_theme_color_override("font_color", C_TEXT)
	sell_tab.add_theme_font_size_override("font_size", 12)
	sell_tab.pressed.connect(func(): _set_sell_mode(true))
	tab_row.add_child(sell_tab)

	# --- ScrollContainer for item list ---
	_scroll = ScrollContainer.new()
	_scroll.position                          = Vector2(12, 74)
	_scroll.size                              = Vector2(WIN_W - 24, 256)
	_scroll.horizontal_scroll_mode           = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode             = ScrollContainer.SCROLL_MODE_AUTO
	_panel.add_child(_scroll)

	_item_vbox = VBoxContainer.new()
	_item_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_vbox.add_theme_constant_override("separation", 4)
	_scroll.add_child(_item_vbox)

	# --- Divider above footer ---
	_make_hsep(_panel, 340)

	# --- Footer row: status label + gold label + close button ---
	var footer := _make_hbox(_panel, Vector2(12, 348), Vector2(WIN_W - 24, 80))
	footer.alignment = BoxContainer.ALIGNMENT_BEGIN

	var footer_col := VBoxContainer.new()
	footer_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(footer_col)

	_status_lbl = Label.new()
	_status_lbl.text = ""
	_status_lbl.add_theme_color_override("font_color", C_TEXT)
	_status_lbl.add_theme_font_size_override("font_size", 13)
	footer_col.add_child(_status_lbl)

	_gold_lbl = Label.new()
	_gold_lbl.text = ""
	_gold_lbl.add_theme_color_override("font_color", C_GOLD)
	_gold_lbl.add_theme_font_size_override("font_size", 13)
	footer_col.add_child(_gold_lbl)

	var close_footer := Button.new()
	close_footer.text                    = "Close"
	close_footer.custom_minimum_size     = Vector2(80, 32)
	close_footer.add_theme_stylebox_override("normal",
			_make_style(C_BTN, C_BORDER, 1, 3))
	close_footer.add_theme_stylebox_override("hover",
			_make_style(C_BTN_HV, C_GOLD, 1, 3))
	close_footer.add_theme_stylebox_override("pressed",
			_make_style(C_BG, C_GOLD, 1, 3))
	close_footer.add_theme_color_override("font_color", C_TEXT)
	close_footer.pressed.connect(_on_close)
	footer.add_child(close_footer)


func _connect_network_signals() -> void:
	if not _has_network():
		return
	# buy_result may fire after the shop is already closed; guard with is_instance_valid
	if not Network.buy_result.is_connected(_on_buy_result):
		Network.buy_result.connect(_on_buy_result)


# ---------------------------------------------------------------------------
# Item list population
# ---------------------------------------------------------------------------

func _populate_items() -> void:
	# Clear previous contents
	for child in _item_vbox.get_children():
		child.queue_free()
	_buy_buttons.clear()

	for i in _items.size():
		var item: Dictionary = _items[i]
		var row := _build_item_row(item, i)
		_item_vbox.add_child(row)


func _build_item_row(item: Dictionary, index: int) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size   = Vector2(WIN_W - 40, 32)
	row.add_theme_constant_override("separation", 6)

	# Subtle alternating-row background via a Panel behind the HBox
	var row_bg := Panel.new()
	var bg_col := Color(0.10, 0.08, 0.04, 0.60) if index % 2 == 0 else Color(0.07, 0.05, 0.02, 0.60)
	row_bg.add_theme_stylebox_override("panel", _make_style(bg_col, Color(0, 0, 0, 0), 0, 2))
	row_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# We add row_bg as the first child so it sits behind — but HBoxContainer stacks
	# children side-by-side, not Z-layered. Use a Container trick: wrap in a Control.
	# Simpler: just tint the HBox itself via a theme stylebox on a Panel wrapper.
	var wrapper := Panel.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.custom_minimum_size   = Vector2(WIN_W - 40, 32)
	wrapper.add_theme_stylebox_override("panel", _make_style(bg_col, Color(0, 0, 0, 0), 0, 2))
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Item name label — expands to fill remaining space
	var name_lbl := Label.new()
	name_lbl.text                     = item.get("name", "Unknown")
	name_lbl.size_flags_horizontal    = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment       = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.clip_text                = true
	row.add_child(name_lbl)

	# Price label — fixed width ~80px, right-aligned, gold colour
	var price_lbl := Label.new()
	price_lbl.text                       = "%d gp" % item.get("price", 0)
	price_lbl.custom_minimum_size        = Vector2(80, 0)
	price_lbl.horizontal_alignment       = HORIZONTAL_ALIGNMENT_RIGHT
	price_lbl.vertical_alignment         = VERTICAL_ALIGNMENT_CENTER
	price_lbl.add_theme_color_override("font_color", C_GOLD)
	price_lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(price_lbl)

	# Buy button — green, 60×28
	var buy_btn := Button.new()
	buy_btn.text               = "Buy"
	buy_btn.custom_minimum_size = Vector2(60, 28)
	buy_btn.add_theme_stylebox_override("normal",
			_make_style(C_GREEN, C_BORDER, 1, 3))
	buy_btn.add_theme_stylebox_override("hover",
			_make_style(C_GREEN_HV, C_GOLD, 1, 3))
	buy_btn.add_theme_stylebox_override("pressed",
			_make_style(C_BG, C_GOLD, 1, 3))
	buy_btn.add_theme_stylebox_override("disabled",
			_make_style(Color(0.10, 0.10, 0.08, 0.60), C_DIM, 1, 3))
	buy_btn.add_theme_color_override("font_color", C_TEXT)
	buy_btn.add_theme_color_override("font_disabled_color", C_DIM)
	buy_btn.pressed.connect(_on_buy_pressed.bind(index))
	row.add_child(buy_btn)
	_buy_buttons.append(buy_btn)

	# Put the HBox inside the styled wrapper
	row.position = Vector2(4, 2)
	wrapper.add_child(row)
	return wrapper


# ---------------------------------------------------------------------------
# Input handlers
# ---------------------------------------------------------------------------

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_on_close()


func _on_close() -> void:
	_disconnect_network_signals()
	queue_free()


func _on_buy_pressed(index: int) -> void:
	if index < 0 or index >= _items.size():
		return
	if not _has_network():
		_set_status("Not connected to server.", C_RED)
		return

	var item: Dictionary = _items[index]
	var obj_index: int   = item.get("obj_index", 0)

	# Disable the tapped button immediately to prevent double-sends
	if index < _buy_buttons.size():
		_buy_buttons[index].disabled = true

	_set_status("Buying...", C_DIM)
	_busy = true
	Network.send_buy(_npc_id, obj_index, 1)


func _on_buy_result(success: bool, reason: String) -> void:
	if not is_instance_valid(self):
		return
	_busy = false

	# Re-enable all buy buttons
	for btn in _buy_buttons:
		if is_instance_valid(btn):
			btn.disabled = false

	if success:
		_set_status("Purchase successful!", C_GOLD)
		_update_gold_label()
	else:
		_set_status("Failed: " + reason, C_RED)

	if _sell_mode:
		_populate_sell_items()


func _set_sell_mode(sell: bool) -> void:
	_sell_mode = sell
	if sell:
		_populate_sell_items()
	else:
		_populate_items()


func _populate_sell_items() -> void:
	for child in _item_vbox.get_children():
		child.queue_free()
	_buy_buttons.clear()

	var ps_node := get_node_or_null("/root/PlayerState")
	if ps_node == null:
		return
	var inv: Array = ps_node.get("inventory") if ps_node.get("inventory") is Array else []
	for i in inv.size():
		var item: Dictionary = inv[i] as Dictionary
		if item.is_empty() or item.get("equipped", false):
			continue
		var obj: Dictionary = GameData.get_object(item.get("obj_index", 0))
		if obj.get("value", 0) <= 0:
			continue
		var sell_price: int = maxi(1, int(float(obj.get("value", 0)) * 0.3))
		var row_item := {
			"name": "%s ×%d" % [obj.get("name", "?"), item.get("amount", 1)],
			"price": sell_price,
			"obj_index": item.get("obj_index", 0),
			"inv_slot": i,
		}
		var row := _build_sell_row(row_item)
		_item_vbox.add_child(row)


func _build_sell_row(item: Dictionary) -> Control:
	var wrapper := Panel.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.custom_minimum_size = Vector2(WIN_W - 40, 32)
	wrapper.add_theme_stylebox_override("panel",
			_make_style(Color(0.10, 0.08, 0.04, 0.60), Color(0, 0, 0, 0), 0, 2))
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.position = Vector2(4, 2)
	wrapper.add_child(row)

	var name_lbl := Label.new()
	name_lbl.text = item.get("name", "?")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.clip_text = true
	row.add_child(name_lbl)

	var price_lbl := Label.new()
	price_lbl.text = "%d gp" % item.get("price", 0)
	price_lbl.custom_minimum_size = Vector2(80, 0)
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_lbl.add_theme_color_override("font_color", C_GOLD)
	price_lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(price_lbl)

	var sell_btn := Button.new()
	sell_btn.text = "Sell"
	sell_btn.custom_minimum_size = Vector2(60, 28)
	sell_btn.add_theme_stylebox_override("normal", _make_style(Color(0.5,0.1,0.05), C_BORDER, 1, 3))
	sell_btn.add_theme_stylebox_override("hover", _make_style(Color(0.7,0.15,0.08), C_GOLD, 1, 3))
	sell_btn.add_theme_color_override("font_color", C_TEXT)
	sell_btn.add_theme_font_size_override("font_size", 13)
	var inv_slot: int = item.get("inv_slot", 0)
	sell_btn.pressed.connect(func(): _on_sell_pressed(inv_slot))
	row.add_child(sell_btn)
	_buy_buttons.append(sell_btn)

	return wrapper


func _on_sell_pressed(inv_slot: int) -> void:
	if not _has_network():
		_set_status("Not connected to server.", C_RED)
		return
	_set_status("Selling...", C_DIM)
	Network.send_sell(_npc_id, inv_slot)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _has_network() -> bool:
	return Engine.has_singleton("Network") or (get_tree() != null and get_node_or_null("/root/Network") != null)


func _set_status(text: String, color: Color) -> void:
	if is_instance_valid(_status_lbl):
		_status_lbl.text = text
		_status_lbl.add_theme_color_override("font_color", color)


func _update_gold_label() -> void:
	if not is_instance_valid(_gold_lbl):
		return
	# Read gold from PlayerState if available; fall back gracefully
	var gold := 0
	if ClassDB.class_exists("PlayerState") or (Engine.has_singleton("PlayerState")):
		pass  # Will be wired when PlayerState autoload is available
	var ps_node := get_node_or_null("/root/PlayerState")
	if ps_node != null and ps_node.has_method("get") :
		var s: Dictionary = ps_node.get("stats") if ps_node.get("stats") is Dictionary else {}
		gold = s.get("gold", 0)
	_gold_lbl.text = "Gold: %d" % gold


func _disconnect_network_signals() -> void:
	if not _has_network():
		return
	var net := get_node_or_null("/root/Network")
	if net == null:
		return
	if net.buy_result.is_connected(_on_buy_result):
		net.buy_result.disconnect(_on_buy_result)


# ---------------------------------------------------------------------------
# Style helpers (mirrors inventory_ui.gd)
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


func _make_hbox(parent: Control, pos: Vector2, sz: Vector2) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.position = pos
	hb.size     = sz
	parent.add_child(hb)
	return hb


func _make_hsep(parent: Control, y: float) -> void:
	var sep := Panel.new()
	sep.position = Vector2(0, y)
	sep.size     = Vector2(WIN_W, 2)
	sep.add_theme_stylebox_override("panel",
			_make_style(Color(0.40, 0.30, 0.10, 0.60), Color(0.40, 0.30, 0.10, 0.60), 0, 0))
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sep)
