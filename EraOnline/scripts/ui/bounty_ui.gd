class_name BountyUI
extends Node
## Era Online - Bounty System UI Helper
##
## Not a visual panel.  Listens for Network.on_bounty_update and maintains a
## local dictionary of wanted players.  Exposes get_bounty() / is_wanted() /
## get_wanted_list() so world_map.gd can draw bounty icons above criminals.
##
## Also routes a notification message to ChatUI whenever a bounty changes.

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## char_id (int) → { "name": String, "bounty": int }
var _wanted: Dictionary = {}


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	var net := get_node_or_null("/root/Network")
	if net != null and net.has_signal("on_bounty_update"):
		net.on_bounty_update.connect(_on_bounty_update)


# ---------------------------------------------------------------------------
# Network handler
# ---------------------------------------------------------------------------

func _on_bounty_update(char_id: int, char_name: String, bounty: int) -> void:
	if bounty > 0:
		var was_wanted: bool  = _wanted.has(char_id)
		var old_bounty: int   = int((_wanted.get(char_id, {}) as Dictionary).get("bounty", 0))
		_wanted[char_id]      = {"name": char_name, "bounty": bounty}
		_notify_chat(char_name, bounty, was_wanted, old_bounty)
	else:
		if _wanted.has(char_id):
			_notify_chat_cleared(char_name)
		_wanted.erase(char_id)


# ---------------------------------------------------------------------------
# Chat notifications
# ---------------------------------------------------------------------------

func _notify_chat(char_name: String, bounty: int,
		was_wanted: bool, old_bounty: int) -> void:
	var chat_ui := _find_chat_ui()
	if chat_ui == null or not chat_ui.has_method("add_message"):
		return
	if not was_wanted:
		chat_ui.add_message(
			"[BOUNTY] %s is now WANTED — %d gold reward!" % [char_name, bounty], 1)
	elif bounty != old_bounty:
		chat_ui.add_message(
			"[BOUNTY] %s bounty updated to %d gold." % [char_name, bounty], 1)


func _notify_chat_cleared(char_name: String) -> void:
	var chat_ui := _find_chat_ui()
	if chat_ui != null and chat_ui.has_method("add_message"):
		chat_ui.add_message("[BOUNTY] %s is no longer wanted." % char_name, 1)


# ---------------------------------------------------------------------------
# Public API — used by world_map.gd
# ---------------------------------------------------------------------------

## Returns the bounty amount for char_id, or 0 if not wanted.
func get_bounty(char_id: int) -> int:
	return int((_wanted.get(char_id, {}) as Dictionary).get("bounty", 0))


## Returns true when the given char_id is on the wanted list.
func is_wanted(char_id: int) -> bool:
	return _wanted.has(char_id)


## Returns an Array of { "name": String, "bounty": int }, sorted by bounty descending.
func get_wanted_list() -> Array:
	var result: Array = []
	for cid in _wanted:
		result.append(_wanted[cid])
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["bounty"]) > int(b["bounty"])
	)
	return result


## Returns the display name for a wanted char, or "" if not wanted.
func get_wanted_name(char_id: int) -> String:
	return (_wanted.get(char_id, {}) as Dictionary).get("name", "") as String


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _find_chat_ui() -> Node:
	var root := get_tree().get_root()
	return _find_by_script_basename(root, "chat_ui")


func _find_by_script_basename(node: Node, basename: String) -> Node:
	var scr: Script = node.get_script() as Script
	if scr != null:
		var path: String = (scr as Script).resource_path
		if path.get_file().get_basename().to_lower() == basename:
			return node
	for child in node.get_children():
		var found := _find_by_script_basename(child, basename)
		if found != null:
			return found
	return null
