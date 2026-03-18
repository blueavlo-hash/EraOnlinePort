class_name QuestUI
extends CanvasLayer
## Era Online - Quest Journal UI
##
## Collapsible right-side panel showing active and completed quests.
## Toggle with Q key (when chat input is not open).
## Positioned below the minimap at the right edge of the screen.

const PANEL_WIDTH  : int = 210
const PANEL_HEIGHT : int = 300
const MARGIN_RIGHT : int = 10
const MARGIN_TOP   : int = 240   # Below minimap (~200px tall + gap)

var _visible_flag: bool = false

var _panel:        PanelContainer = null
var _vbox:         VBoxContainer  = null
var _title_label:  Label          = null
var _scroll:       ScrollContainer = null
var _quest_list:   VBoxContainer  = null

## Local cache of quest state sent from server via on_quest_update / on_quest_complete.
## quest_id(int) → { name, desc, objectives_str, completed, reward_gold, reward_xp }
var _quests: Dictionary = {}


func _ready() -> void:
	layer = 6
	# Start hidden
	_visible_flag = false

	_panel = PanelContainer.new()
	add_child(_panel)
	_panel.visible = false
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)

	var style := StyleBoxFlat.new()
	style.bg_color         = Color(0.05, 0.05, 0.08, 0.92)
	style.border_width_top    = 1
	style.border_width_bottom = 1
	style.border_width_left   = 1
	style.border_width_right  = 1
	style.border_color     = Color(0.55, 0.45, 0.15, 1.0)
	style.corner_radius_top_left     = 4
	style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left  = 4
	style.corner_radius_bottom_right = 4
	_panel.add_theme_stylebox_override("panel", style)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(root_vbox)

	# Title bar
	var title_bar := HBoxContainer.new()
	root_vbox.add_child(title_bar)

	_title_label = Label.new()
	_title_label.text = "Quest Journal"
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(_title_label)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.flat = true
	close_btn.pressed.connect(_toggle_visible)
	title_bar.add_child(close_btn)

	# Separator
	var sep := HSeparator.new()
	root_vbox.add_child(sep)

	# Scrollable quest list
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(PANEL_WIDTH - 12, PANEL_HEIGHT - 60)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(_scroll)

	_quest_list = VBoxContainer.new()
	_quest_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quest_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_quest_list)

	_reposition()
	get_viewport().size_changed.connect(_reposition)

	# Wire network signals if available
	if Engine.has_singleton("Network") or has_node("/root/Network"):
		var net = get_node_or_null("/root/Network")
		if net:
			if net.has_signal("on_quest_offer"):
				net.on_quest_offer.connect(_on_net_quest_offer)
			if net.has_signal("on_quest_update"):
				net.on_quest_update.connect(_on_net_quest_update)
			if net.has_signal("on_quest_complete"):
				net.on_quest_complete.connect(_on_net_quest_complete)


func _reposition() -> void:
	if _panel == null:
		return
	var vp_size := get_viewport().get_visible_rect().size
	_panel.position = Vector2(
		vp_size.x - PANEL_WIDTH - MARGIN_RIGHT,
		MARGIN_TOP
	)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			# Only toggle if chat is not capturing input
			var chat_ui = get_node_or_null("/root/WorldMap/_ChatUI") if false else \
					_find_chat_ui()
			if chat_ui != null and chat_ui.has_method("is_input_open") \
					and chat_ui.is_input_open():
				return
			_toggle_visible()
			get_viewport().set_input_as_handled()


func _find_chat_ui() -> Node:
	# Walk scene tree to find ChatUI (avoids tight coupling)
	var root := get_tree().get_root()
	return _find_by_class_name(root, "ChatUI")


func _find_by_class_name(node: Node, cname: String) -> Node:
	if node.get_script() != null:
		var scr = node.get_script()
		if scr.has_method("get_global_name"):
			pass
		if node.get_class() == cname:
			return node
		# Check script class_name via resource path heuristic
		var path: String = scr.resource_path if scr != null else ""
		if path.get_file().get_basename().to_lower() == cname.to_lower():
			return node
	for child in node.get_children():
		var found := _find_by_class_name(child, cname)
		if found != null:
			return found
	return null


func _toggle_visible() -> void:
	_visible_flag = !_visible_flag
	_panel.visible = _visible_flag


## Called externally to show/hide the journal.
func set_journal_visible(v: bool) -> void:
	_visible_flag = v
	_panel.visible = v


## Add or update a quest entry. Called when the player accepts or makes progress.
func update_quest(quest_id: int, quest_name: String, objectives_str: String,
		completed: bool) -> void:
	_quests[quest_id] = {
		"name":           quest_name,
		"objectives_str": objectives_str,
		"completed":      completed,
	}
	_rebuild_list()


## Remove all quest data and rebuild the list.
func clear_quests() -> void:
	_quests.clear()
	_rebuild_list()


func _rebuild_list() -> void:
	# Remove existing children
	for child in _quest_list.get_children():
		child.queue_free()

	# Separate active vs completed
	var active_ids:    Array = []
	var completed_ids: Array = []
	for qid in _quests:
		var e: Dictionary = _quests[qid] as Dictionary
		if e.get("completed", false):
			completed_ids.append(qid)
		else:
			active_ids.append(qid)

	if active_ids.is_empty() and completed_ids.is_empty():
		var lbl := Label.new()
		lbl.text = "No active quests."
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		_quest_list.add_child(lbl)
		return

	# Active quests
	if not active_ids.is_empty():
		var sec := Label.new()
		sec.text = "Active"
		sec.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		_quest_list.add_child(sec)
		for qid in active_ids:
			_quest_list.add_child(_make_quest_entry(_quests[qid] as Dictionary, false))

	# Completed quests
	if not completed_ids.is_empty():
		var sep2 := HSeparator.new()
		_quest_list.add_child(sep2)
		var sec2 := Label.new()
		sec2.text = "Completed"
		sec2.add_theme_color_override("font_color", Color(0.5, 0.85, 0.5))
		_quest_list.add_child(sec2)
		for qid in completed_ids:
			_quest_list.add_child(_make_quest_entry(_quests[qid] as Dictionary, true))


func _make_quest_entry(entry: Dictionary, completed: bool) -> Control:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 2)

	var name_label := Label.new()
	name_label.text = entry.get("name", "Unknown Quest")
	name_label.add_theme_font_size_override("font_size", 11)
	if completed:
		name_label.add_theme_color_override("font_color", Color(0.5, 0.85, 0.5))
	else:
		name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	container.add_child(name_label)

	var obj_str: String = entry.get("objectives_str", "")
	if obj_str != "" and not completed:
		var obj_label := Label.new()
		obj_label.text = obj_str
		obj_label.add_theme_font_size_override("font_size", 10)
		obj_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		obj_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		container.add_child(obj_label)
	elif completed:
		var done_label := Label.new()
		done_label.text = "Complete!"
		done_label.add_theme_font_size_override("font_size", 10)
		done_label.add_theme_color_override("font_color", Color(0.5, 0.85, 0.5))
		container.add_child(done_label)

	return container


# ---------------------------------------------------------------------------
# Network signal handlers
# ---------------------------------------------------------------------------

func _on_net_quest_offer(_mode: int, quest_id: int, _npc_name: String, quest_name: String,
		_desc: String, objectives: Array, _rewards: Dictionary) -> void:
	# Build objectives string from array (only for offer mode — turnin has no new objectives)
	var obj_parts: Array = []
	for obj in objectives:
		var od: Dictionary = obj as Dictionary
		obj_parts.append(od.get("label", "") + ": 0/" + str(od.get("count", od.get("required", 1))))
	var obj_str: String = "\n".join(obj_parts)
	update_quest(quest_id, quest_name, obj_str, false)


func _on_net_quest_update(quest_id: int, progress: Dictionary) -> void:
	if not _quests.has(quest_id):
		return
	var entry: Dictionary = _quests[quest_id] as Dictionary
	var obj_str: String = progress.get("objectives_str", entry.get("objectives_str", ""))
	update_quest(quest_id, entry.get("name", ""), obj_str, false)


func _on_net_quest_complete(quest_id: int, _reward_gold: int, _reward_xp: int) -> void:
	if not _quests.has(quest_id):
		return
	var entry: Dictionary = _quests[quest_id] as Dictionary
	update_quest(quest_id, entry.get("name", ""), "", true)
