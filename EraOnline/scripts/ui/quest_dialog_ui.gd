class_name QuestDialogUI
extends CanvasLayer
## Era Online - Quest Offer / Turn-In Dialog
##
## Modal dialog shown when the player talks to a quest NPC.
## Shows quest name, description, objectives, and rewards.
## "Accept" sends C_QUEST_ACCEPT; "Decline" dismisses silently.
## For turn-in mode: "Turn In" sends C_QUEST_TURNIN; "Cancel" dismisses.
##
## Layer 12 — above all other UI.

signal accepted(quest_id: int)
signal turned_in(quest_id: int)
signal declined()

var _quest_id:   int    = 0
var _mode:       String = "offer"   # "offer" or "turnin"

var _bg_dim:     ColorRect      = null
var _panel:      PanelContainer = null
var _npc_label:  Label          = null
var _quest_label: Label         = null
var _desc_label: RichTextLabel  = null
var _obj_label:  Label          = null
var _reward_label: Label        = null
var _accept_btn: Button         = null
var _decline_btn: Button        = null


func _ready() -> void:
	layer = 12

	# Dim overlay
	_bg_dim = ColorRect.new()
	_bg_dim.color = Color(0, 0, 0, 0.55)
	_bg_dim.anchors_preset = Control.PRESET_FULL_RECT
	_bg_dim.visible = false
	add_child(_bg_dim)

	# Panel
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(380, 0)
	_panel.visible = false
	add_child(_panel)

	var style := StyleBoxFlat.new()
	style.bg_color     = Color(0.08, 0.07, 0.05, 0.97)
	style.border_color = Color(0.65, 0.52, 0.18, 1.0)
	style.border_width_top    = 2
	style.border_width_bottom = 2
	style.border_width_left   = 2
	style.border_width_right  = 2
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	_panel.add_child(vbox)

	# NPC name (header)
	_npc_label = Label.new()
	_npc_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_npc_label.add_theme_font_size_override("font_size", 13)
	_npc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_npc_label)

	var sep1 := HSeparator.new()
	vbox.add_child(sep1)

	# Quest name
	_quest_label = Label.new()
	_quest_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.75))
	_quest_label.add_theme_font_size_override("font_size", 12)
	_quest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_quest_label)

	# Description (NPC dialogue)
	_desc_label = RichTextLabel.new()
	_desc_label.bbcode_enabled = false
	_desc_label.custom_minimum_size = Vector2(360, 70)
	_desc_label.scroll_active = false
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.add_theme_color_override("default_color", Color(0.9, 0.9, 0.9))
	_desc_label.add_theme_font_size_override("normal_font_size", 11)
	vbox.add_child(_desc_label)

	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# Objectives
	var obj_header := Label.new()
	obj_header.text = "Objectives:"
	obj_header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5))
	obj_header.add_theme_font_size_override("font_size", 11)
	vbox.add_child(obj_header)

	_obj_label = Label.new()
	_obj_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82))
	_obj_label.add_theme_font_size_override("font_size", 11)
	_obj_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_obj_label)

	var sep3 := HSeparator.new()
	vbox.add_child(sep3)

	# Rewards
	var rew_header := Label.new()
	rew_header.text = "Rewards:"
	rew_header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5))
	rew_header.add_theme_font_size_override("font_size", 11)
	vbox.add_child(rew_header)

	_reward_label = Label.new()
	_reward_label.add_theme_color_override("font_color", Color(0.7, 0.95, 0.7))
	_reward_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(_reward_label)

	var sep4 := HSeparator.new()
	vbox.add_child(sep4)

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	_accept_btn = Button.new()
	_accept_btn.text = "Accept"
	_accept_btn.custom_minimum_size = Vector2(100, 28)
	_accept_btn.pressed.connect(_on_accept_pressed)
	btn_row.add_child(_accept_btn)

	_decline_btn = Button.new()
	_decline_btn.text = "Decline"
	_decline_btn.custom_minimum_size = Vector2(100, 28)
	_decline_btn.pressed.connect(_on_decline_pressed)
	btn_row.add_child(_decline_btn)

	_center_panel()
	get_viewport().size_changed.connect(_center_panel)


func _center_panel() -> void:
	if _panel == null:
		return
	var vp := get_viewport().get_visible_rect().size
	_panel.position = Vector2(
		(vp.x - _panel.custom_minimum_size.x) / 2.0,
		(vp.y - 300.0) / 2.0
	)


## Show an offer dialog for a quest the player can accept.
func show_offer(npc_name: String, quest_id: int, quest_name: String,
		desc: String, objectives: Array, rewards: Dictionary) -> void:
	_quest_id = quest_id
	_mode = "offer"
	_npc_label.text = npc_name
	_quest_label.text = quest_name
	_desc_label.text = desc
	_obj_label.text = _objectives_text(objectives)
	_reward_label.text = _reward_text(rewards)
	_accept_btn.text = "Accept"
	_decline_btn.text = "Decline"
	_panel.visible = true
	_bg_dim.visible = true
	_center_panel()


## Show a turn-in dialog when objectives are completed.
func show_turnin(npc_name: String, quest_id: int, quest_name: String,
		rewards: Dictionary) -> void:
	_quest_id = quest_id
	_mode = "turnin"
	_npc_label.text = npc_name
	_quest_label.text = quest_name
	_desc_label.text = "You have completed the quest! Shall I give you your reward?"
	_obj_label.text = "All objectives complete."
	_reward_label.text = _reward_text(rewards)
	_accept_btn.text = "Turn In"
	_decline_btn.text = "Cancel"
	_panel.visible = true
	_bg_dim.visible = true
	_center_panel()


func hide_dialog() -> void:
	_panel.visible = false
	_bg_dim.visible = false


func _objectives_text(objectives: Array) -> String:
	var lines: Array = []
	for obj in objectives:
		var od: Dictionary = obj as Dictionary
		lines.append("- " + od.get("label", "???") + \
				" (0/%d)" % int(od.get("required", 1)))
	return "\n".join(lines)


func _reward_text(rewards: Dictionary) -> String:
	var parts: Array = []
	var gold: int = int(rewards.get("gold", 0))
	var xp:   int = int(rewards.get("xp", 0))
	if gold > 0:
		parts.append("%d Gold" % gold)
	if xp > 0:
		parts.append("%d XP" % xp)
	var items: Array = rewards.get("items", [])
	for it in items:
		var id: Dictionary = it as Dictionary
		var amt: int = int(id.get("amount", 1))
		var name: String = id.get("name", "Item")
		parts.append("%dx %s" % [amt, name])
	if parts.is_empty():
		return "None"
	return ", ".join(parts)


func _on_accept_pressed() -> void:
	hide_dialog()
	if _mode == "offer":
		accepted.emit(_quest_id)
	else:
		turned_in.emit(_quest_id)


func _on_decline_pressed() -> void:
	hide_dialog()
	declined.emit()


func _input(event: InputEvent) -> void:
	if not _panel.visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide_dialog()
		declined.emit()
		get_viewport().set_input_as_handled()
