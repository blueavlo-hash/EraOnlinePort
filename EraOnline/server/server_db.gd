class_name ServerDB
## Era Online - Server Database
## JSON-file-per-account storage under user://accounts/.
## Mirrors the interface a SQLite backend would expose — swap later with
## a GDExtension SQLite plugin without changing callers.
##
## Layout:
##   user://accounts/_counter.json   → {"next_id": int}
##   user://accounts/{username}.json → full account dict (see _empty_account)

const ACCOUNTS_DIR := "user://accounts"


func initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ACCOUNTS_DIR)
	# Create counter file if missing
	var counter_path := ACCOUNTS_DIR + "/_counter.json"
	if not FileAccess.file_exists(counter_path):
		_write_json(counter_path, {"next_id": 1})


# ---------------------------------------------------------------------------
# Account queries
# ---------------------------------------------------------------------------

func account_exists(username: String) -> bool:
	return FileAccess.file_exists(_account_path(username))


## Create a new account. Returns the new account_id, or -1 on failure.
func create_account(username: String, password_hash: String,
		password_salt: String) -> int:
	if account_exists(username):
		return -1
	var account_id := _next_account_id()
	var acc := _empty_account()
	acc["account_id"]    = account_id
	acc["username"]      = username
	acc["password_hash"] = password_hash
	acc["password_salt"] = password_salt
	acc["created_at"]    = Time.get_unix_time_from_system()
	acc["character"]["name"] = username  # Default char name = username
	_write_json(_account_path(username), acc)
	return account_id


## Load the full account dict. Returns {} if not found.
func get_account(username: String) -> Dictionary:
	return _read_json(_account_path(username))


func update_last_login(username: String) -> void:
	var acc := get_account(username)
	if acc.is_empty():
		return
	acc["last_login"] = Time.get_unix_time_from_system()
	_write_json(_account_path(username), acc)


func save_character(username: String, char_data: Dictionary) -> void:
	var acc := get_account(username)
	if acc.is_empty():
		push_warning("[ServerDB] save_character: account not found: " + username)
		return
	acc["character"] = char_data
	_write_json(_account_path(username), acc)


func is_banned(username: String) -> bool:
	var acc := get_account(username)
	return acc.get("banned", false)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _next_account_id() -> int:
	var path    := ACCOUNTS_DIR + "/_counter.json"
	var counter := _read_json(path)
	var id      := counter.get("next_id", 1) as int
	counter["next_id"] = id + 1
	_write_json(path, counter)
	return id


func _account_path(username: String) -> String:
	# Sanitize to prevent directory traversal
	var safe := username.to_lower().strip_edges()
	return ACCOUNTS_DIR + "/" + safe + ".json"


func _empty_account() -> Dictionary:
	return {
		"account_id":    0,
		"username":      "",
		"password_hash": "",
		"password_salt": "",
		"created_at":    0.0,
		"last_login":    0.0,
		"banned":        false,
		"ban_reason":    "",
		"character": {
			"name":      "",
			"body":      1,
			"head":      1,
			"map_id":    3,
			"x":         10,
			"y":         10,
			"heading":   3,
			"level":     1,
			"hp":        100, "max_hp":  100,
			"mp":        50,  "max_mp":  50,
			"sta":       100, "max_sta": 100,
			"exp":       0,
			"gold":      500,
			"inventory": [],
		}
	}


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[ServerDB] Cannot read: " + path)
		return {}
	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("[ServerDB] JSON parse error in: " + path)
		return {}
	var data = json.get_data()
	return data if data is Dictionary else {}


func _write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("[ServerDB] Cannot write: " + path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
