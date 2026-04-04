extends Node
## Era Online - GameData Autoload
## Global data store. Loads all parsed JSON data files into memory.
## Access via GameData.objects, GameData.grh_data, etc.

const DATA_PATH := "res://data/"
const MAP_CACHE_LIMIT := 10

var grh_data: Dictionary = {}
var objects: Dictionary = {}
var npcs: Dictionary = {}
var spells: Dictionary = {}
var bodies: Dictionary = {}
var heads: Dictionary = {}
var weapon_anims: Dictionary = {}
var shield_anims: Dictionary = {}
var map_index: Array = []

var is_loaded: bool = false
var _map_cache: Dictionary = {}
var _map_cache_order: Array = []  # LRU tracking

func _ready() -> void:
	_load_all_data()

func _load_all_data() -> void:
	print("[GameData] Loading game data...")
	var start := Time.get_ticks_msec()

	grh_data    = _load_json("grh_data.json").get("entries", {})
	objects     = _load_json("objects.json").get("entries", {})
	npcs        = _load_json("npcs.json").get("entries", {})
	spells      = _load_json("spells.json").get("entries", {})
	bodies      = _load_json("bodies.json").get("entries", {})
	heads       = _load_json("heads.json").get("entries", {})
	weapon_anims = _load_json("weapon_anims.json").get("entries", {})
	shield_anims = _load_json("shield_anims.json").get("entries", {})

	var idx := _load_json("maps/map_index.json")
	map_index = idx.get("maps", [])

	is_loaded = true
	var elapsed := Time.get_ticks_msec() - start
	print("[GameData] Loaded in %dms | GRH:%d OBJ:%d NPC:%d SPL:%d Maps:%d" % [
		elapsed, grh_data.size(), objects.size(), npcs.size(), spells.size(), map_index.size()
	])

# --- Map access (with LRU cache) ---

func get_map(map_id: int) -> Dictionary:
	if map_id in _map_cache:
		# Move to front of LRU
		_map_cache_order.erase(map_id)
		_map_cache_order.append(map_id)
		return _map_cache[map_id]

	var data := _load_json("maps/map_%d.json" % map_id)
	if data.is_empty():
		push_warning("[GameData] Map %d not found" % map_id)
		return {}

	if _map_cache.size() >= MAP_CACHE_LIMIT:
		var oldest: int = _map_cache_order.pop_front()
		_map_cache.erase(oldest)

	_map_cache[map_id] = data
	_map_cache_order.append(map_id)
	return data

func get_map_tile(map_id: int, x: int, y: int) -> Dictionary:
	var map := get_map(map_id)
	if map.is_empty():
		return {}
	return map.get("tiles", {}).get("%d,%d" % [y, x], {})

# --- Entity lookups ---

func get_grh(grh_index: int) -> Dictionary:
	return grh_data.get(str(grh_index), {})

func get_object(obj_index: int) -> Dictionary:
	return objects.get(str(obj_index), {})

func get_npc(npc_index: int) -> Dictionary:
	return npcs.get(str(npc_index), {})

func get_spell(spell_index: int) -> Dictionary:
	return spells.get(str(spell_index), {})

func get_body(body_index: int) -> Dictionary:
	return bodies.get(str(body_index), {})

func get_head(head_index: int) -> Dictionary:
	return heads.get(str(head_index), {})

func get_weapon_anim(anim_index: int) -> Dictionary:
	return weapon_anims.get(str(anim_index), {})

func get_shield_anim(anim_index: int) -> Dictionary:
	return shield_anims.get(str(anim_index), {})

# --- GRH helpers ---

## Returns the resolved static GrhData for a given index and animation frame.
func get_grh_frame(grh_index: int, frame: int = 0) -> Dictionary:
	var entry := get_grh(grh_index)
	if entry.is_empty():
		return {}
	var num_frames: int = entry.get("num_frames", 1)
	if num_frames <= 1:
		return entry
	var frames: Array = entry.get("frames", [])
	if frames.is_empty():
		return entry
	var resolved: int = frames[frame % frames.size()]
	if resolved == grh_index:
		return entry
	return get_grh(resolved)

## Returns the source rect (in the bitmap) for a grh entry.
func get_grh_rect(grh_index: int, frame: int = 0) -> Rect2i:
	var entry := get_grh_frame(grh_index, frame)
	if entry.is_empty():
		return Rect2i.ZERO
	return Rect2i(
		entry.get("sx", 0),
		entry.get("sy", 0),
		entry.get("pixel_width", 32),
		entry.get("pixel_height", 32)
	)

## Returns the bitmap file number for a grh entry.
func get_grh_file_num(grh_index: int, frame: int = 0) -> int:
	return get_grh_frame(grh_index, frame).get("file_num", 0)

## Returns the walk animation GRH indices for a body+direction.
## direction: 0=North, 1=East, 2=South, 3=West
func get_body_walk_grh(body_index: int, direction: int) -> int:
	var body := get_body(body_index)
	if body.is_empty():
		return 0
	var walk: Array = body.get("walk", [0, 0, 0, 0])
	if direction < walk.size():
		return walk[direction]
	return 0

func get_head_grh(head_index: int, direction: int) -> int:
	var head := get_head(head_index)
	if head.is_empty():
		return 0
	var dirs: Array = head.get("head", [0, 0, 0, 0])
	if direction < dirs.size():
		return dirs[direction]
	return 0

func get_weapon_walk_grh(anim_index: int, direction: int) -> int:
	var anim := get_weapon_anim(anim_index)
	if anim.is_empty():
		return 0
	var walk: Array = anim.get("walk", [0, 0, 0, 0])
	if direction < walk.size():
		return walk[direction]
	return 0

func get_shield_walk_grh(anim_index: int, direction: int) -> int:
	var anim := get_shield_anim(anim_index)
	if anim.is_empty():
		return 0
	var walk: Array = anim.get("walk", [0, 0, 0, 0])
	if direction < walk.size():
		return walk[direction]
	return 0

# --- Internal ---

func _load_json(relative_path: String) -> Dictionary:
	var full_path := DATA_PATH + relative_path
	var file := FileAccess.open(full_path, FileAccess.READ)
	if file == null:
		push_warning("[GameData] Cannot open: " + full_path)
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("[GameData] JSON error in %s: %s" % [full_path, json.get_error_message()])
		return {}
	var data = json.get_data()
	if data is Dictionary:
		return data
	return {}
