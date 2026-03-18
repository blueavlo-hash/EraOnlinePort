extends Node
## Era Online - GameSettings autoload
## Manages keybindings and volume settings, persisted to user://settings.json.

const SETTINGS_PATH := "user://settings.json"

const DEFAULT_KEYS := {
	"move_north":    KEY_W,
	"move_south":    KEY_S,
	"move_east":     KEY_D,
	"move_west":     KEY_A,
	"ui_char":       KEY_C,
	"ui_inventory":  KEY_I,
	"ui_interact":   KEY_E,
	"ui_pickup":     KEY_F,
	"ui_leaderboard": KEY_L,
}

const ACTION_LABELS := {
	"move_north":    "Move North",
	"move_south":    "Move South",
	"move_east":     "Move East",
	"move_west":     "Move West",
	"ui_char":       "Character Panel",
	"ui_inventory":  "Inventory",
	"ui_interact":   "Interact / Shop",
	"ui_pickup":     "Pick Up Item",
	"ui_leaderboard":"Leaderboard",
}

var sfx_volume: float = 1.0
var music_volume: float = 0.7
var keybindings: Dictionary = {}  # action -> physical_keycode int

var remember_me: bool = false
var saved_username: String = ""
var saved_password: String = ""


func _ready() -> void:
	_ensure_actions()
	load_settings()
	apply_keybindings()


func _ensure_actions() -> void:
	for action in ACTION_LABELS.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		# Ensure it's in keybindings dict if not already set
		if not keybindings.has(action):
			keybindings[action] = DEFAULT_KEYS[action]


func load_settings() -> void:
	# Start from defaults
	for action in DEFAULT_KEYS.keys():
		keybindings[action] = DEFAULT_KEYS[action]

	if not FileAccess.file_exists(SETTINGS_PATH):
		# Apply default volumes to AudioManager
		AudioManager.set_sfx_volume(sfx_volume)
		AudioManager.set_music_volume(music_volume)
		return

	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		return
	var data := parsed as Dictionary

	if data.has("sfx_volume"):
		sfx_volume = clampf(float(data["sfx_volume"]), 0.0, 1.0)
	if data.has("music_volume"):
		music_volume = clampf(float(data["music_volume"]), 0.0, 1.0)
	if data.has("keybindings") and data["keybindings"] is Dictionary:
		var kb := data["keybindings"] as Dictionary
		for action in DEFAULT_KEYS.keys():
			if kb.has(action):
				keybindings[action] = int(kb[action])
	if data.has("remember_me"):
		remember_me = bool(data["remember_me"])
	if data.has("saved_username"):
		saved_username = str(data["saved_username"])
	if data.has("saved_password"):
		saved_password = str(data["saved_password"])

	AudioManager.set_sfx_volume(sfx_volume)
	AudioManager.set_music_volume(music_volume)


func set_credentials(username: String, password: String, remember: bool) -> void:
	remember_me = remember
	saved_username = username if remember else ""
	saved_password = password if remember else ""
	save_settings()


func save_settings() -> void:
	var data := {
		"sfx_volume":     sfx_volume,
		"music_volume":   music_volume,
		"keybindings":    keybindings.duplicate(),
		"remember_me":    remember_me,
		"saved_username": saved_username,
		"saved_password": saved_password,
	}
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[GameSettings] Cannot write %s" % SETTINGS_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


func apply_keybindings() -> void:
	for action in keybindings.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = keybindings[action]
		InputMap.action_add_event(action, ev)


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	AudioManager.set_sfx_volume(sfx_volume)
	save_settings()


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	AudioManager.set_music_volume(music_volume)
	save_settings()


func set_keybinding(action: String, keycode: int) -> void:
	keybindings[action] = keycode
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)
	save_settings()


func get_keycode_name(keycode: int) -> String:
	var name := OS.get_keycode_string(keycode)
	if name.is_empty():
		return "?"
	return name
