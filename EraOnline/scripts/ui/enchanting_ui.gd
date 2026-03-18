class_name EnchantingUI
extends CanvasLayer
## Era Online - Enchanting UI
##
## Modal panel (centre-screen, 320×280px) opened programmatically via open().
## Call open(item_slot, item_name, enchant_level) from inventory right-click.
## Connects to Network.on_enchant_result for result display.
## Dismiss with the Close button or ESC key.

# ---------------------------------------------------------------------------
# Color palette
# ---------------------------------------------------------------------------
const C_BG       := Color(0.05, 0.04, 0.02, 0.96)
const C_BORDER   := Color(0.40, 0.30, 0.12, 1.0)
const C_GOLD     := Color(0.85, 0.65, 0.15, 1.0)
const C_TEXT     := Color(0.90, 0.85, 0.72, 1.0)
const C_DIM      := Color(0.55, 0.50, 0.38, 1.0)
const C_BTN      := Color(0.14, 0.10, 0.04, 1.0)
const C_BTN_HV   := Color(0.22, 0.16, 0.06, 1.0)
const C_GREEN    := Color(0.18, 0.36, 0.12, 1.0)
const C_GREEN_HV := Color(0.25, 0.50, 0.16, 1.0)
const C_RED      := Color(0.75, 0.15, 0.10, 1.0)
const C_SUCCESS  := Color(0.20, 0.90, 0.25, 1.0)
const C_FAIL     := Color(0.90, 0.25, 0.20, 1.0)

const WIN_W : int = 320
const WIN_H : int = 280

# Success rates by current enchant level (0→+1, 1→+2, 2→+3, 3→+4)
const SUCCESS_RATES : Array = [90, 70, 45, 20]
const MAX_ENCHANT   : int   = 4

# ---------------------------------------------------------------------------
# Nodes
# ---------------------------------------------------------------------------
var _layer:         CanvasLayer   = null   # self IS the layer; kept for clarity
var _backdrop:      Panel         = null
var _panel:         Panel         = null
var _item_label:    Label         = null
var _level_label:   Label         = null
var _success_label: Label         = null
var _material_label: Label        = null
var _mat_list:      VBoxContainer = null
var _mat_scroll:    ScrollContainer = null
var _result_label:  Label         = null
var _enchant_btn:   Button        = null
var _close_btn:     Button        = null

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _item_slot:    int    = -1
var _mat_slot:     int    = -1
var _enchant_lvl:  int    = 0
var _item_name:    String = ""
var _mat_buttons:  Array  = []   # parallel array of Button nodes


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer   = 8
	visible = false
	_build_ui()

	var net := get_node_or_null("/root/Network")
	if net != null and net.has_signal("on_enchant_result"):
		net.on_enchant_result.connect(_on_enchant_result)


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Full-screen backdrop
	_backdrop = Panel.new()
	_backdrop.position     = Vector2.ZERO
	_backdrop.size         = Vector2(1280, 720)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.add_theme_stylebox_override("panel",
			_make_style(Color(0.0, 0.0, 0.0, 0.55), Color(0, 0, 0, 0), 0, 0))
	_backdrop.gui_input.connect(_on_backdrop_input)
	add_child(_backdrop)

	# Main panel — centred
	var px := int(1280 / 2.0 - WIN_W / 2.0)
	var py := int(720  / 2.0 - WIN_H / 2.0)
	_panel = Panel.new()
	_panel.position     = Vector2(px, py)
	_panel.size         = Vector2(WIN_W, WIN_H)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _make_style(C_BG, C_BORDER, 2, 4))
	add_child(_panel)

	# Title bar
	var title_bar := HBoxContainer.new()
	title_bar.position = Vector2(0, 0)
	title_bar.size     = Vector2(WIN_W, 32)
	_panel.add_child(title_bar)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(10, 0)
	title_bar.add_child(spacer)

	var title_lbl := Label.new()
	title_lbl.text                  = "Enchanting"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	title_lbl.add_theme_color_override("font_color", C_GOLD)
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_bar.add_child(title_lbl)

	_close_btn = Button.new()
	_close_btn.text = " X "
	_close_btn.flat = true
	_close_btn.add_theme_color_override("font_color", C_DIM)
	_close_btn.add_theme_stylebox_override("hover",
			_make_style(Color(0.20, 0.05, 0.04, 1.0), C_RED, 1, 3))
	_close_btn.pressed.connect(close)
	title_bar.add_child(_close_btn)

	_make_hsep(2, 32)

	# Item name row
	_item_label = Label.new()
	_item_label.position = Vector2(12, 40)
	_item_label.size     = Vector2(WIN_W - 24, 22)
	_item_label.text     = "Item: —"
	_item_label.add_theme_color_override("font_color", C_TEXT)
	_item_label.add_theme_font_size_override("font_size", 13)
	_item_label.clip_text = true
	_panel.add_child(_item_label)

	# Current level row
	_level_label = Label.new()
	_level_label.position = Vector2(12, 62)
	_level_label.size     = Vector2(WIN_W - 24, 20)
	_level_label.text     = "Enchant Level: +0"
	_level_label.add_theme_color_override("font_color", C_GOLD)
	_level_label.add_theme_font_size_override("font_size", 12)
	_panel.add_child(_level_label)

	# Success rate
	_success_label = Label.new()
	_success_label.position = Vector2(12, 82)
	_success_label.size     = Vector2(WIN_W - 24, 20)
	_success_label.text     = "Success rate: —"
	_success_label.add_theme_color_override("font_color", C_DIM)
	_success_label.add_theme_font_size_override("font_size", 11)
	_panel.add_child(_success_label)

	_make_hsep(2, 104)

	# Material section heading
	_material_label = Label.new()
	_material_label.position = Vector2(12, 110)
	_material_label.size     = Vector2(WIN_W - 24, 18)
	_material_label.text     = "Select material:"
	_material_label.add_theme_color_override("font_color", C_TEXT)
	_material_label.add_theme_font_size_override("font_size", 12)
	_panel.add_child(_material_label)

	# Scrollable material list
	_mat_scroll = ScrollContainer.new()
	_mat_scroll.position                = Vector2(8, 130)
	_mat_scroll.size                    = Vector2(WIN_W - 16, 96)
	_mat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_mat_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	_panel.add_child(_mat_scroll)

	_mat_list = VBoxContainer.new()
	_mat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mat_list.add_theme_constant_override("separation", 3)
	_mat_scroll.add_child(_mat_list)

	_make_hsep(2, 232)

	# Result label
	_result_label = Label.new()
	_result_label.position        = Vector2(12, 238)
	_result_label.size            = Vector2(WIN_W - 24, 20)
	_result_label.text            = ""
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 12)
	_panel.add_child(_result_label)

	# Enchant button
	_enchant_btn = Button.new()
	_enchant_btn.text                = "Enchant"
	_enchant_btn.position            = Vector2(WIN_W / 2.0 - 70, 256)
	_enchant_btn.size                = Vector2(140, 30)
	_enchant_btn.add_theme_stylebox_override("normal",
			_make_style(C_GREEN, C_BORDER, 1, 4))
	_enchant_btn.add_theme_stylebox_override("hover",
			_make_style(C_GREEN_HV, C_GOLD, 1, 4))
	_enchant_btn.add_theme_stylebox_override("pressed",
			_make_style(C_BG, C_GOLD, 1, 4))
	_enchant_btn.add_theme_stylebox_override("disabled",
			_make_style(Color(0.10, 0.10, 0.08, 0.60), C_DIM, 1, 4))
	_enchant_btn.add_theme_color_override("font_color", C_TEXT)
	_enchant_btn.add_theme_color_override("font_disabled_color", C_DIM)
	_enchant_btn.pressed.connect(_on_enchant_pressed)
	_panel.add_child(_enchant_btn)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func open(item_slot: int, item_name: String, enchant_level: int) -> void:
	_item_slot   = item_slot
	_item_name   = item_name
	_enchant_lvl = enchant_level
	_mat_slot    = -1
	_result_label.text = ""

	_item_label.text  = "Item: %s" % item_name
	_level_label.text = "Enchant Level: +%d" % enchant_level

	if enchant_level >= MAX_ENCHANT:
		_success_label.text = "Maximum enchant level reached."
		_enchant_btn.disabled = true
	else:
		var rate: int = SUCCESS_RATES[enchant_level]
		_success_label.text   = "Success rate: %d%%" % rate
		_enchant_btn.disabled = false

	_populate_materials()
	visible = true


func close() -> void:
	visible    = false
	_item_slot = -1
	_mat_slot  = -1
	_result_label.text = ""


# ---------------------------------------------------------------------------
# Material list
# ---------------------------------------------------------------------------

func _populate_materials() -> void:
	for child in _mat_list.get_children():
		child.queue_free()
	_mat_buttons.clear()

	var ps := get_node_or_null("/root/PlayerState")
	if ps == null:
		var lbl := Label.new()
		lbl.text = "(PlayerState unavailable)"
		lbl.add_theme_color_override("font_color", C_DIM)
		lbl.add_theme_font_size_override("font_size", 11)
		_mat_list.add_child(lbl)
		return

	var inv: Array = []
	if ps.get("inventory") is Array:
		inv = ps.get("inventory") as Array

	var any_valid := false
	for i in inv.size():
		var item: Dictionary = inv[i] as Dictionary
		if item.is_empty():
			continue
		# Get object data — look for items that are valid enchant materials.
		# Convention: obj type "Material" or "EnchantStone" used as materials.
		var obj_data: Dictionary = {}
		if ClassDB.class_exists("GameData") or has_node("/root/GameData"):
			var gd := get_node_or_null("/root/GameData")
			if gd != null and gd.has_method("get_object"):
				obj_data = gd.get_object(item.get("obj_index", 0)) as Dictionary
		var obj_type: String = obj_data.get("obj_type", "").to_lower()
		if obj_type != "material" and obj_type != "enchantstone" and obj_type != "stone":
			continue
		any_valid = true
		var mat_name: String = obj_data.get("name", "Material #%d" % i)
		var amount: int = item.get("amount", 1)
		_add_material_button(i, mat_name, amount)

	if not any_valid:
		var lbl := Label.new()
		lbl.text = "No enchant materials in inventory."
		lbl.add_theme_color_override("font_color", C_DIM)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_mat_list.add_child(lbl)
		_enchant_btn.disabled = true


func _add_material_button(slot_idx: int, mat_name: String, amount: int) -> void:
	var btn := Button.new()
	btn.text                = "%s  ×%d" % [mat_name, amount]
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(WIN_W - 32, 26)
	btn.toggle_mode         = true
	btn.add_theme_stylebox_override("normal",
			_make_style(C_BTN, C_BORDER, 1, 3))
	btn.add_theme_stylebox_override("hover",
			_make_style(C_BTN_HV, C_GOLD, 1, 3))
	btn.add_theme_stylebox_override("pressed",
			_make_style(Color(0.20, 0.16, 0.05, 1.0), C_GOLD, 2, 3))
	btn.add_theme_color_override("font_color", C_TEXT)
	btn.add_theme_font_size_override("font_size", 12)
	btn.pressed.connect(_on_mat_selected.bind(slot_idx, btn))
	_mat_list.add_child(btn)
	_mat_buttons.append(btn)


func _on_mat_selected(slot_idx: int, pressed_btn: Button) -> void:
	_mat_slot = slot_idx
	# Deselect all other buttons
	for btn in _mat_buttons:
		var b := btn as Button
		if b != pressed_btn:
			b.button_pressed = false
	pressed_btn.button_pressed = true
	_material_label.text = "Material selected."
	_material_label.add_theme_color_override("font_color", C_GOLD)
	if _enchant_lvl < MAX_ENCHANT:
		_enchant_btn.disabled = false


# ---------------------------------------------------------------------------
# Enchant action
# ---------------------------------------------------------------------------

func _on_enchant_pressed() -> void:
	if _item_slot < 0 or _mat_slot < 0:
		_result_label.text = "Select an item and material first."
		_result_label.add_theme_color_override("font_color", C_FAIL)
		return
	var net := get_node_or_null("/root/Network")
	if net == null:
		return
	# Guard: only send when connected
	if net.get("state") != null:
		var connected_state = net.get_script().get_constant("State") if false else null
		# Use integer comparison to avoid hard dependency on State enum
		# Network.State.CONNECTED is checked via property access pattern used in other UI files
		if net.state != Network.State.CONNECTED:
			_result_label.text = "Not connected to server."
			_result_label.add_theme_color_override("font_color", C_FAIL)
			return
	_enchant_btn.disabled = true
	_result_label.text    = "Enchanting..."
	_result_label.add_theme_color_override("font_color", C_DIM)
	Network.send_enchant(_item_slot, _mat_slot)


# ---------------------------------------------------------------------------
# Network handler
# ---------------------------------------------------------------------------

func _on_enchant_result(result: int, new_level: int, message: String) -> void:
	if not is_instance_valid(self):
		return

	_enchant_btn.disabled = false

	match result:
		0:  # Failure — item degraded or unchanged
			_result_label.add_theme_color_override("font_color", C_FAIL)
		1:  # Success
			_enchant_lvl = new_level
			_level_label.text = "Enchant Level: +%d" % new_level
			if new_level < MAX_ENCHANT:
				var rate: int = SUCCESS_RATES[new_level]
				_success_label.text   = "Success rate: %d%%" % rate
				_enchant_btn.disabled = false
			else:
				_success_label.text   = "Maximum enchant level reached."
				_enchant_btn.disabled = true
			_result_label.add_theme_color_override("font_color", C_SUCCESS)
		2:  # Destroyed
			_result_label.add_theme_color_override("font_color", C_FAIL)
			_result_label.text = message
			# Brief delay then close so player can read the message
			await get_tree().create_timer(2.0).timeout
			if is_instance_valid(self):
				close()
			return
		_:
			_result_label.add_theme_color_override("font_color", C_DIM)

	_result_label.text = message
	# Refresh material list since the material was consumed
	_populate_materials()


# ---------------------------------------------------------------------------
# Input — ESC to close
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Backdrop click to close
# ---------------------------------------------------------------------------

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			close()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _make_hsep(border_w: int, y: float) -> void:
	var sep := Panel.new()
	sep.position = Vector2(0, y)
	sep.size     = Vector2(WIN_W, 2)
	sep.add_theme_stylebox_override("panel",
			_make_style(Color(0.40, 0.30, 0.10, 0.60),
					Color(0.40, 0.30, 0.10, 0.60), border_w, 0))
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(sep)


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
