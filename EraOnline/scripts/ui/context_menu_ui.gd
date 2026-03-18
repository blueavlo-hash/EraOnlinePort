class_name ContextMenuUI
extends Node
## Era Online - Right-Click Context Menu
## Shows context-sensitive actions when the player right-clicks a world tile.

signal skill_requested(skill_id: int, tile: Vector2i)
signal examine_requested(char_id: int)
signal walk_requested(tile: Vector2i)
signal pickup_requested(item_id: int)
signal spell_cast_requested(spell_id: int, target_id: int)
signal trade_requested(char_id: int)
signal talk_requested(char_id: int)

## Skill IDs for gathering/crafting actions (matches spec slots 1-indexed)
const SKILL_MINING     := 21   # Mining
const SKILL_WOODCUT    := 5    # Lumberjacking
const SKILL_FISHING    := 20   # Fishing
const SKILL_BLACKSMITH := 9    # Blacksmithing / Smelting
const SKILL_COOKING    := 1    # Cooking
const SKILL_CARPENTING := 4    # Carpenting (planks / crafting)

var _popup: PopupMenu = null
## Maps popup item index → action dictionary
var _item_actions: Dictionary = {}


func _ready() -> void:
	_popup = PopupMenu.new()
	add_child(_popup)
	_popup.id_pressed.connect(_on_id_pressed)


func show_menu(screen_pos: Vector2, context: Dictionary) -> void:
	_popup.clear()
	_item_actions.clear()

	var tile: Vector2i = context.get("tile", Vector2i.ZERO)
	var npc_ids: Array = context.get("npc_ids", [])
	var ground_item: Dictionary = context.get("ground_item", {})
	var has_pickaxe: bool = context.get("has_pickaxe", false)
	var has_axe: bool = context.get("has_axe", false)
	var has_fishing_rod: bool = context.get("has_fishing_rod", false)
	var blueprint_label: String = context.get("blueprint_label", "")

	var idx := 0

	# Spell casting on nearby NPCs (SINGLE_ENEMY / SINGLE_ALLY spells)
	var target_spells: Array = context.get("target_spells", [])
	for char_id in npc_ids:
		var char_name: String = context.get("npc_names", {}).get(char_id, "NPC")
		for sp_entry in target_spells:
			_popup.add_item("Cast %s on %s" % [sp_entry["name"], char_name], idx)
			_item_actions[idx] = {"action": "cast_spell", "spell_id": sp_entry["id"], "target_id": char_id}
			idx += 1

	# Examine nearby characters
	for char_id in npc_ids:
		var char_name: String = context.get("npc_names", {}).get(char_id, "NPC")
		_popup.add_item("Examine " + char_name, idx)
		_item_actions[idx] = {"action": "examine", "char_id": char_id}
		idx += 1

	# Talk to server NPCs (quest / dialogue)
	for char_id in npc_ids:
		if char_id < 10001:
			continue  # Only server NPCs can be talked to
		var npc_talk_name: String = context.get("npc_names", {}).get(char_id, "NPC")
		_popup.add_item("Talk to " + npc_talk_name, idx)
		_item_actions[idx] = {"action": "talk", "char_id": char_id}
		idx += 1

	# Trade with nearby players (player IDs < 10001, not self)
	var local_id: int = context.get("local_char_id", -1)
	for char_id in npc_ids:
		if char_id >= 10001 or char_id == local_id:
			continue
		var char_name: String = context.get("npc_names", {}).get(char_id, "Player")
		_popup.add_item("Trade with " + char_name, idx)
		_item_actions[idx] = {"action": "trade", "char_id": char_id}
		idx += 1

	# Pick up ground item
	if not ground_item.is_empty():
		var item_name: String = ground_item.get("name", "Item")
		_popup.add_item("Pick Up " + item_name, idx)
		_item_actions[idx] = {"action": "pickup", "tile": tile, "item_id": ground_item.get("id", -1)}
		idx += 1

	# Tool-based gather skills
	if has_pickaxe:
		_popup.add_item("Mine", idx)
		_item_actions[idx] = {"action": "skill", "skill_id": SKILL_MINING, "tile": tile}
		idx += 1

	if has_axe:
		_popup.add_item("Chop Wood", idx)
		_item_actions[idx] = {"action": "skill", "skill_id": SKILL_WOODCUT, "tile": tile}
		idx += 1

	if has_fishing_rod:
		_popup.add_item("Fish", idx)
		_item_actions[idx] = {"action": "skill", "skill_id": SKILL_FISHING, "tile": tile}
		idx += 1

	if not blueprint_label.is_empty():
		_popup.add_item("Forge " + blueprint_label, idx)
		_item_actions[idx] = {"action": "skill", "skill_id": SKILL_BLACKSMITH, "tile": tile}
		idx += 1

	# Station crafting options (from right-clicking on a Forge, Anvil, or Stove)
	var smelt_option: bool = context.get("smelt_option", false)
	var forge_label: String = context.get("forge_label", "")
	var cook_items: Array = context.get("cook_items", [])
	var plank_option: bool = context.get("plank_option", false)

	if smelt_option:
		_popup.add_item("Smelt Ore", idx)
		_item_actions[idx] = {"action": "skill", "skill_id": SKILL_BLACKSMITH, "tile": tile}
		idx += 1

	if not forge_label.is_empty():
		_popup.add_item("Forge " + forge_label, idx)
		_item_actions[idx] = {"action": "skill", "skill_id": SKILL_BLACKSMITH, "tile": tile}
		idx += 1

	for cook_entry in cook_items:
		_popup.add_item("Cook " + cook_entry.get("name", "food"), idx)
		_item_actions[idx] = {"action": "skill", "skill_id": SKILL_COOKING, "tile": tile}
		idx += 1

	if plank_option:
		_popup.add_item("Cut Planks", idx)
		_item_actions[idx] = {"action": "skill", "skill_id": SKILL_CARPENTING, "tile": tile}
		idx += 1

	# Walk Here (always last)
	_popup.add_separator()
	_popup.add_item("Walk Here", idx)
	_item_actions[idx] = {"action": "walk", "tile": tile}

	_popup.popup(Rect2i(int(screen_pos.x), int(screen_pos.y), 0, 0))


func _on_id_pressed(id: int) -> void:
	if not _item_actions.has(id):
		return
	var action: Dictionary = _item_actions[id]
	match action.get("action", ""):
		"examine":
			examine_requested.emit(action["char_id"])
		"skill":
			var tile: Vector2i = action["tile"]
			skill_requested.emit(action["skill_id"], tile)
		"walk":
			walk_requested.emit(action["tile"])
		"pickup":
			pickup_requested.emit(action["item_id"])
		"cast_spell":
			spell_cast_requested.emit(action["spell_id"], action["target_id"])
		"trade":
			trade_requested.emit(action["char_id"])
		"talk":
			talk_requested.emit(action["char_id"])
