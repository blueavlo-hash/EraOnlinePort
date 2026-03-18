class_name InventoryUI
extends CanvasLayer
## Era Online - Inventory & Equipment UI
## Toggle with 'I'. Two tabs: Inventory grid and Equipment paper-doll.
## Built entirely in GDScript for portability (no .tscn dependency).

signal enchant_requested(slot: int, item_name: String, enchant_level: int)

# ---------------------------------------------------------------------------
# Color palette — dark medieval fantasy
# ---------------------------------------------------------------------------
const C_BG          := Color(0.07, 0.05, 0.03, 0.96)
const C_PANEL       := Color(0.11, 0.08, 0.05, 1.00)
const C_GOLD        := Color(0.75, 0.58, 0.18, 1.00)
const C_GOLD_DIM    := Color(0.45, 0.34, 0.11, 1.00)
const C_SLOT        := Color(0.05, 0.04, 0.02, 1.00)
const C_SLOT_HOVER  := Color(0.20, 0.15, 0.06, 1.00)
const C_SLOT_EQUIP  := Color(0.28, 0.22, 0.05, 1.00)
const C_TEXT        := Color(0.94, 0.84, 0.58, 1.00)
const C_TEXT_DIM    := Color(0.58, 0.47, 0.28, 1.00)
const C_RED         := Color(0.85, 0.15, 0.10, 1.00)
const C_BLUE        := Color(0.15, 0.35, 0.85, 1.00)
const C_GREEN       := Color(0.15, 0.72, 0.25, 1.00)
const C_SEPARATOR   := Color(0.40, 0.30, 0.10, 0.60)

const SLOT_SIZE := 56
const SLOT_PAD  := 4
const INV_COLS  := 4
const INV_ROWS  := 5
const WIN_W     := 460
const WIN_H     := 480

var _window      : Panel
var _tab_btns    : Array        = []
var _inv_panel   : Control
var _equip_panel : Control
var _slot_panels : Array        = []   # 20 inventory slot controls
var _equip_slots : Dictionary   = {}   # slot_name → Control
var _tooltip     : Panel
var _tooltip_lbl : Label
var _cur_tab     : int = 0
var _drag_slot   : int = -1

var _tex_cache : TextureCache

var _slot_popup : PopupMenu = null
var _popup_slot : int = -1

# Category sort order for the Sort button
const _CAT_ORDER := ["Weapon", "Shield", "Armor", "Helmet", "Boots"]


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 20
	_tex_cache = TextureCache.new()
	_build_window()
	_window.visible = false   # Hide the window panel, not the layer

	PlayerState.inventory_changed.connect(_refresh_inventory)
	PlayerState.equipment_changed.connect(_refresh_equipment)


func _build_window() -> void:
	var scr := Vector2(1280, 720)
	var pos  := Vector2(scr.x / 2.0 - WIN_W / 2.0, scr.y / 2.0 - WIN_H / 2.0)

	_window = Panel.new()
	_window.position = pos
	_window.size     = Vector2(WIN_W, WIN_H)
	_window.add_theme_stylebox_override("panel", _make_style(C_BG, C_GOLD, 2, 4))
	add_child(_window)

	# --- Title bar ---
	var title_bar := _make_hbox(_window, Vector2(0, 0), Vector2(WIN_W, 32))
	var title_lbl := Label.new()
	title_lbl.text              = "   CHARACTER"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_color_override("font_color", C_GOLD)
	title_bar.add_child(title_lbl)
	var sort_btn := Button.new()
	sort_btn.text = " Sort "
	sort_btn.flat = true
	sort_btn.add_theme_color_override("font_color", C_GOLD_DIM)
	sort_btn.add_theme_stylebox_override("hover",
			_make_style(Color(0.20, 0.15, 0.06, 1), C_GOLD, 1, 3))
	sort_btn.pressed.connect(_sort_inventory)
	title_bar.add_child(sort_btn)

	var close_btn := Button.new()
	close_btn.text         = "  ✕  "
	close_btn.flat         = true
	close_btn.add_theme_color_override("font_color", C_TEXT_DIM)
	close_btn.pressed.connect(func(): _window.visible = false)
	title_bar.add_child(close_btn)

	_make_separator(_window, 32)

	# --- Tab buttons ---
	var tab_row := _make_hbox(_window, Vector2(0, 36), Vector2(WIN_W, 30))
	for i in ["Inventory", "Equipment"]:
		var btn := Button.new()
		btn.text              = i
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.flat              = true
		var idx := _tab_btns.size()
		btn.pressed.connect(_switch_tab.bind(idx))
		_style_tab_btn(btn, idx == 0)
		tab_row.add_child(btn)
		_tab_btns.append(btn)

	_make_separator(_window, 68)

	# --- Content area ---
	_inv_panel   = _build_inventory_panel()
	_equip_panel = _build_equipment_panel()
	_equip_panel.visible = false

	# --- Tooltip (rendered last so it appears on top) ---
	_tooltip = Panel.new()
	_tooltip.add_theme_stylebox_override("panel", _make_style(
			Color(0.04, 0.03, 0.01, 0.97), C_GOLD_DIM, 1, 3))
	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_lbl = Label.new()
	_tooltip_lbl.position = Vector2(8, 6)
	_tooltip_lbl.add_theme_color_override("font_color", C_TEXT)
	_tooltip.add_child(_tooltip_lbl)
	_window.add_child(_tooltip)

	# Inventory slot right-click popup
	_slot_popup = PopupMenu.new()
	_slot_popup.add_item("Equip",          0)
	_slot_popup.add_item("Unequip",        1)
	_slot_popup.add_separator()
	_slot_popup.add_item("Use",            2)
	_slot_popup.add_separator()
	_slot_popup.add_item("Offer in Trade", 4)
	_slot_popup.add_item("Enchant",        5)
	_slot_popup.add_separator()
	_slot_popup.add_item("Discard",        3)
	_slot_popup.id_pressed.connect(_on_slot_popup_id)
	add_child(_slot_popup)

	# Make window draggable
	_window.gui_input.connect(_on_window_input)
	_window.mouse_filter = Control.MOUSE_FILTER_STOP


func _build_inventory_panel() -> Control:
	var panel := Control.new()
	panel.position = Vector2(8, 74)
	panel.size     = Vector2(WIN_W - 16, WIN_H - 90)
	_window.add_child(panel)

	var grid_x := int((WIN_W - 16) / 2.0 - (INV_COLS * (SLOT_SIZE + SLOT_PAD)) / 2.0)

	for row in INV_ROWS:
		for col in INV_COLS:
			var slot_idx := row * INV_COLS + col
			var sp := _make_item_slot(panel, slot_idx,
					Vector2(grid_x + col * (SLOT_SIZE + SLOT_PAD),
							8 + row * (SLOT_SIZE + SLOT_PAD)))
			_slot_panels.append(sp)

	return panel


func _make_item_slot(parent: Control, slot_idx: int, pos: Vector2) -> Control:
	var sp := Panel.new()
	sp.position = pos
	sp.size     = Vector2(SLOT_SIZE, SLOT_SIZE)
	sp.add_theme_stylebox_override("panel", _make_style(C_SLOT, C_GOLD_DIM, 1, 2))
	sp.mouse_filter = Control.MOUSE_FILTER_STOP

	var icon := TextureRect.new()
	icon.name               = "Icon"
	icon.position           = Vector2(4, 4)
	icon.size               = Vector2(SLOT_SIZE - 8, SLOT_SIZE - 8)
	icon.expand_mode        = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode       = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sp.add_child(icon)

	var qty_lbl := Label.new()
	qty_lbl.name     = "Qty"
	qty_lbl.position = Vector2(2, SLOT_SIZE - 18)
	qty_lbl.size     = Vector2(SLOT_SIZE - 4, 16)
	qty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qty_lbl.add_theme_color_override("font_color", C_TEXT)
	qty_lbl.add_theme_font_size_override("font_size", 11)
	sp.add_child(qty_lbl)

	sp.gui_input.connect(_on_slot_input.bind(slot_idx))
	sp.mouse_entered.connect(_on_slot_hover.bind(slot_idx, sp))
	sp.mouse_exited.connect(_on_slot_exit.bind(sp))
	parent.add_child(sp)
	return sp


func _build_equipment_panel() -> Control:
	var panel := Control.new()
	panel.position = Vector2(8, 74)
	panel.size     = Vector2(WIN_W - 16, WIN_H - 90)
	panel.visible  = false
	_window.add_child(panel)

	# Equipment slot layout (name, label, position)
	var layout := [
		["helmet", "Helmet",  Vector2(WIN_W / 2.0 - 38, 10)],
		["armor",  "Armor",   Vector2(WIN_W / 2.0 - 38, 100)],
		["boots",  "Boots",   Vector2(WIN_W / 2.0 - 38, 190)],
		["weapon", "Weapon",  Vector2(WIN_W / 2.0 - 38 - 90, 100)],
		["shield", "Shield",  Vector2(WIN_W / 2.0 - 38 + 90, 100)],
	]

	for entry in layout:
		var slot_name: String = entry[0]
		var slot_label: String = entry[1]
		var slot_pos: Vector2  = entry[2]
		var eq_slot := _make_equip_slot(panel, slot_name, slot_label, slot_pos)
		_equip_slots[slot_name] = eq_slot

	# Stats area at bottom
	var stats_lbl := Label.new()
	stats_lbl.name     = "StatsLabel"
	stats_lbl.position = Vector2(16, 300)
	stats_lbl.size     = Vector2(WIN_W - 32, 150)
	stats_lbl.add_theme_color_override("font_color", C_TEXT)
	stats_lbl.add_theme_font_size_override("font_size", 13)
	panel.add_child(stats_lbl)

	return panel


func _make_equip_slot(parent: Control, slot_name: String,
		label_text: String, pos: Vector2) -> Control:
	var container := Control.new()
	container.position = pos
	container.size     = Vector2(76, 90)
	parent.add_child(container)

	var lbl := Label.new()
	lbl.text     = label_text
	lbl.size     = Vector2(76, 16)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	lbl.add_theme_font_size_override("font_size", 11)
	container.add_child(lbl)

	var sp := Panel.new()
	sp.position = Vector2(8, 18)
	sp.size     = Vector2(60, 60)
	sp.add_theme_stylebox_override("panel", _make_style(C_SLOT, C_GOLD_DIM, 1, 3))
	sp.mouse_filter = Control.MOUSE_FILTER_STOP

	var icon := TextureRect.new()
	icon.name        = "Icon"
	icon.position    = Vector2(4, 4)
	icon.size        = Vector2(52, 52)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sp.add_child(icon)

	var slot_lbl := Label.new()
	slot_lbl.name     = "SlotName"
	slot_lbl.text     = slot_name[0].to_upper()
	slot_lbl.position = Vector2(0, 20)
	slot_lbl.size     = Vector2(60, 20)
	slot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot_lbl.add_theme_color_override("font_color", C_GOLD_DIM)
	slot_lbl.add_theme_font_size_override("font_size", 11)
	sp.add_child(slot_lbl)

	sp.gui_input.connect(_on_equip_slot_input.bind(slot_name))
	sp.mouse_entered.connect(_on_equip_hover.bind(slot_name, sp))
	sp.mouse_exited.connect(_on_slot_exit.bind(sp))
	container.add_child(sp)
	return sp


# ---------------------------------------------------------------------------
# Refresh display
# ---------------------------------------------------------------------------

func _refresh_inventory() -> void:
	for i in PlayerState.MAX_SLOTS:
		var slot_panel := _slot_panels[i] as Panel
		var item: Dictionary = PlayerState.inventory[i]
		var icon       := slot_panel.get_node("Icon") as TextureRect
		var qty        := slot_panel.get_node("Qty") as Label

		# Equipped items are shown only in the Equipment tab — hide them here.
		var is_equipped: bool = not item.is_empty() and item.get("equipped", false)
		if item.is_empty() or is_equipped:
			icon.texture = null
			qty.text     = ""
			slot_panel.add_theme_stylebox_override("panel",
					_make_style(C_SLOT, C_GOLD_DIM, 1, 2))
		else:
			var obj := GameData.get_object(item["obj_index"])
			var grh_idx: int = obj.get("grh_index", 0)
			if grh_idx > 0:
				var fd := GameData.get_grh_frame(grh_idx)
				if not fd.is_empty():
					var file_num: int = fd.get("file_num", 0)
					if file_num > 0:
						icon.texture = _tex_cache.get_texture(file_num)
			qty.text = "" if item["amount"] <= 1 else str(item["amount"])
			slot_panel.add_theme_stylebox_override("panel", _make_style(C_SLOT, C_GOLD_DIM, 1, 2))


func _refresh_equipment() -> void:
	for slot_name in _equip_slots:
		var panel: Panel   = _equip_slots[slot_name] as Panel
		var icon: TextureRect = panel.get_node("Icon") as TextureRect
		var lbl: Label        = panel.get_node("SlotName") as Label
		var obj_idx: int      = PlayerState.equipment.get(slot_name, 0)

		if obj_idx <= 0:
			icon.texture = null
			lbl.text     = slot_name[0].to_upper()
			panel.add_theme_stylebox_override("panel", _make_style(C_SLOT, C_GOLD_DIM, 1, 3))
		else:
			var obj := GameData.get_object(obj_idx)
			lbl.text = obj.get("name", slot_name)
			lbl.add_theme_font_size_override("font_size", 9)
			var grh_idx: int = obj.get("grh_index", 0)
			if grh_idx > 0:
				var fd := GameData.get_grh_frame(grh_idx)
				if not fd.is_empty():
					icon.texture = _tex_cache.get_texture(fd.get("file_num", 0))
			panel.add_theme_stylebox_override("panel", _make_style(C_SLOT_EQUIP, C_GOLD, 2, 3))

	# Update stats label
	var stats_lbl := _equip_panel.get_node("StatsLabel") as Label
	if stats_lbl:
		var s: Dictionary = PlayerState.stats
		stats_lbl.text = (
			"Level %d   HP %d/%d   MP %d/%d\n" % [
				s["level"], s["hp"], s["max_hp"], s["mp"], s["max_mp"]] +
			"STR %d   AGI %d   INT %d\n" % [s["str"], s["agi"], s["int_"]] +
			"Damage: %d – %d     Defense: %d\n" % [
				s["min_hit"], s["max_hit"], s["def"]] +
			"EXP %d / %d   Gold: %d" % [s["exp"], s["next_exp"], s["gold"]]
		)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_slot_input(event: InputEvent, slot_idx: int) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	var item: Dictionary = PlayerState.inventory[slot_idx]
	# Equipped items are hidden in this tab; treat their slots as empty.
	if item.is_empty() or item.get("equipped", false):
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		PlayerState.equip_item(slot_idx)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_popup_slot = slot_idx
		var obj_data: Dictionary = GameData.get_object(item.get("obj_index", 0))
		var can_equip: bool = not PlayerState._get_equip_slot(obj_data).is_empty()
		_slot_popup.set_item_disabled(0, not can_equip)  # Equip
		_slot_popup.set_item_disabled(1, true)           # Unequip (not visible here)
		# "Offer in Trade" (id=4) — enabled only when online and trade is active
		var trade_active: bool = Network.state == Network.State.CONNECTED
		_slot_popup.set_item_disabled(_slot_popup.get_item_index(4), not trade_active)
		_slot_popup.popup(Rect2i(int(event.global_position.x), int(event.global_position.y), 0, 0))


func _on_equip_slot_input(event: InputEvent, slot_name: String) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			PlayerState.unequip_slot(slot_name)


func _on_slot_hover(slot_idx: int, sp: Panel) -> void:
	var item: Dictionary = PlayerState.inventory[slot_idx]
	# Equipped items are hidden in this tab — don't highlight or show tooltip.
	if not item.is_empty() and not item.get("equipped", false):
		sp.add_theme_stylebox_override("panel", _make_style(C_SLOT_HOVER, C_GOLD, 1, 2))
	if item.is_empty() or item.get("equipped", false):
		_tooltip.visible = false
		return
	var obj := GameData.get_object(item["obj_index"])
	var tip := _build_tooltip_text(obj, false)
	_show_tooltip_at_cursor(tip)


func _on_equip_hover(slot_name: String, sp: Panel) -> void:
	sp.add_theme_stylebox_override("panel", _make_style(C_SLOT_HOVER, C_GOLD, 2, 3))
	var obj_idx: int = PlayerState.equipment.get(slot_name, 0)
	if obj_idx <= 0:
		_tooltip.visible = false
		return
	var obj := GameData.get_object(obj_idx)
	var tip := _build_tooltip_text(obj, true)
	tip += "\n[Left-click to unequip]"
	_show_tooltip_at_cursor(tip)


func _build_tooltip_text(obj: Dictionary, equipped: bool) -> String:
	var name_str: String = obj.get("name", "Unknown")
	var cat: String      = obj.get("category", "")
	var mn: int          = int(obj.get("min_hit", 0))
	var mx: int          = int(obj.get("max_hit", 0))
	var df: int          = int(obj.get("def", 0))
	var val: int         = int(obj.get("value", 0))
	var tip: String      = name_str
	if cat != "":         tip += "\n" + cat
	if mn > 0 or mx > 0: tip += "\nDamage: %d – %d" % [mn, mx]
	if df > 0:            tip += "\nDefense: +%d" % df
	if val > 0:           tip += "\nValue: %d gold" % val
	if equipped:          tip += "\n[Equipped]"
	return tip


func _show_tooltip_at_cursor(tip: String) -> void:
	_tooltip_lbl.text = tip
	_tooltip_lbl.size = _tooltip_lbl.get_minimum_size()
	_tooltip.size     = _tooltip_lbl.size + Vector2(16, 12)

	# Position near cursor, keeping tooltip within window bounds
	var mouse_in_win := get_viewport().get_mouse_position() - _window.global_position
	var tip_w: float  = _tooltip.size.x
	var tip_h: float  = _tooltip.size.y
	var offset_x: float = 14.0
	var offset_y: float = -tip_h - 4.0

	var tx: float = mouse_in_win.x + offset_x
	var ty: float = mouse_in_win.y + offset_y

	# Clamp so tooltip doesn't spill outside the window
	tx = clampf(tx, 4.0, WIN_W  - tip_w  - 4.0)
	ty = clampf(ty, 4.0, WIN_H  - tip_h  - 4.0)

	_tooltip.position = Vector2(tx, ty)
	_tooltip.visible  = true


func _on_slot_exit(sp: Panel) -> void:
	_tooltip.visible = false
	_refresh_slot_style(sp)


func _on_slot_popup_id(id: int) -> void:
	if _popup_slot < 0:
		return
	var item: Dictionary = PlayerState.inventory[_popup_slot]
	if item.is_empty():
		_popup_slot = -1
		return
	match id:
		0:  # Equip
			if Network.state == Network.State.CONNECTED:
				Network.send_equip(_popup_slot)
			else:
				PlayerState.equip_item(_popup_slot)
		1:  # Unequip
			if Network.state == Network.State.CONNECTED:
				Network.send_unequip(_popup_slot)
			else:
				var obj := GameData.get_object(item["obj_index"])
				PlayerState.unequip_slot(PlayerState._get_equip_slot(obj))
		2:  # Use
			if Network.state == Network.State.CONNECTED:
				Network.send_use_item(_popup_slot)
			else:
				pass  # offline use handled locally
		3:  # Discard
			var amount: int = item.get("amount", 1)
			if Network.state == Network.State.CONNECTED:
				Network.send_drop(_popup_slot, amount)
			else:
				PlayerState.remove_item(_popup_slot)
		4:  # Offer in Trade
			if Network.state == Network.State.CONNECTED:
				Network.send_trade_offer(_popup_slot)
		5:  # Enchant
			if Network.state == Network.State.CONNECTED:
				var item_name: String = item.get("name", "Item")
				var enchant_level: int = int(item.get("enchant_level", 0))
				enchant_requested.emit(_popup_slot, item_name, enchant_level)
	_popup_slot = -1


func _sort_inventory() -> void:
	# Partition into filled and empty slots
	var filled: Array = []
	var empty: Array  = []
	for item in PlayerState.inventory:
		if item.is_empty():
			empty.append(item)
		else:
			filled.append(item)

	# Sort filled items: by category order first, then alphabetically by name
	filled.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var obj_a := GameData.get_object(a.get("obj_index", 0))
		var obj_b := GameData.get_object(b.get("obj_index", 0))
		var cat_a: String  = obj_a.get("category", "")
		var cat_b: String  = obj_b.get("category", "")
		var name_a: String = obj_a.get("name", "")
		var name_b: String = obj_b.get("name", "")

		var ord_a: int = _CAT_ORDER.find(cat_a)
		var ord_b: int = _CAT_ORDER.find(cat_b)
		# Unknown categories (-1) sort after known ones
		if ord_a == -1: ord_a = _CAT_ORDER.size()
		if ord_b == -1: ord_b = _CAT_ORDER.size()

		if ord_a != ord_b:
			return ord_a < ord_b
		# Same category bucket — sort by category name (groups unknowns), then item name
		if cat_a != cat_b:
			return cat_a < cat_b
		return name_a < name_b
	)

	# Write sorted result back in-place (keeps the same Array reference)
	var idx := 0
	for item in filled:
		PlayerState.inventory[idx] = item
		idx += 1
	for item in empty:
		PlayerState.inventory[idx] = item
		idx += 1

	PlayerState.inventory_changed.emit()


func _refresh_slot_style(sp: Panel) -> void:
	# Equipped items are hidden in the inventory tab — always use the plain slot style.
	sp.add_theme_stylebox_override("panel", _make_style(C_SLOT, C_GOLD_DIM, 1, 2))


# Dragging the window
var _drag_offset := Vector2.ZERO
var _dragging    := false

func _on_window_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging    = event.pressed
			_drag_offset = event.position
	elif event is InputEventMouseMotion and _dragging:
		_window.position += event.relative


# ---------------------------------------------------------------------------
# Tab switching
# ---------------------------------------------------------------------------

func _switch_tab(idx: int) -> void:
	_cur_tab         = idx
	_inv_panel.visible   = (idx == 0)
	_equip_panel.visible = (idx == 1)
	for i in _tab_btns.size():
		_style_tab_btn(_tab_btns[i], i == idx)
	if idx == 1:
		_refresh_equipment()


func _style_tab_btn(btn: Button, active: bool) -> void:
	if active:
		btn.add_theme_color_override("font_color", C_GOLD)
		btn.add_theme_stylebox_override("normal",
				_make_style(Color(0.18, 0.14, 0.07, 1), C_GOLD, 1, 0))
	else:
		btn.add_theme_color_override("font_color", C_TEXT_DIM)
		btn.add_theme_stylebox_override("normal",
				_make_style(Color(0.08, 0.06, 0.03, 1), C_GOLD_DIM, 0, 0))
	btn.add_theme_stylebox_override("hover",
			_make_style(Color(0.22, 0.17, 0.07, 1), C_GOLD, 1, 0))
	btn.add_theme_stylebox_override("pressed",
			_make_style(Color(0.18, 0.14, 0.07, 1), C_GOLD, 1, 0))


# ---------------------------------------------------------------------------
# Toggle
# ---------------------------------------------------------------------------

func toggle() -> void:
	_window.visible = not _window.visible
	if _window.visible:
		_refresh_inventory()
		_refresh_equipment()


# ---------------------------------------------------------------------------
# Style helpers
# ---------------------------------------------------------------------------

func _make_style(bg: Color, border: Color, border_w: int, corner: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color               = bg
	s.border_color           = border
	s.border_width_left      = border_w
	s.border_width_right     = border_w
	s.border_width_top       = border_w
	s.border_width_bottom    = border_w
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


func _make_separator(parent: Control, y: float) -> void:
	var sep := Panel.new()
	sep.position = Vector2(0, y)
	sep.size     = Vector2(WIN_W, 2)
	sep.add_theme_stylebox_override("panel", _make_style(C_SEPARATOR, C_SEPARATOR, 0, 0))
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(sep)
