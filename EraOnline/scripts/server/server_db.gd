## Era Online - Server-side account & character persistence.
## Stores JSON files under user://server_data/accounts/<username>.json
## Replaceable with SQLite later without changing the public API.

const SAVE_DIR    := "user://server_data/accounts/"
const MAX_CHARS   := 3

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(SAVE_DIR))


# ---------------------------------------------------------------------------
# Account helpers
# ---------------------------------------------------------------------------

func account_exists(username: String) -> bool:
	return FileAccess.file_exists(_path(username))


## Load account dict or {} if not found.
func load_account(username: String) -> Dictionary:
	var path := _path(username)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var result: Variant = JSON.parse_string(text)
	if result == null or not result is Dictionary:
		return {}
	return result


func save_account(username: String, data: Dictionary) -> void:
	var path := _path(username)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[ServerDB] Cannot write %s" % path)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


## Create a new account.  Returns {ok:bool, reason:String}.
func create_account(username: String, password: String) -> Dictionary:
	if username.length() < 3 or username.length() > 20:
		return {"ok": false, "reason": "Username must be 3-20 characters."}
	if not username.is_valid_identifier():
		return {"ok": false, "reason": "Username may only contain letters, digits and underscores."}
	if password.length() < 4:
		return {"ok": false, "reason": "Password must be at least 4 characters."}
	if account_exists(username):
		return {"ok": false, "reason": "Username already taken."}

	var salt := Crypto.new().generate_random_bytes(16)
	var hash := NetProtocol.pbkdf2(password, salt)
	var data := {
		"username":   username,
		"pw_hash":    hash.hex_encode(),
		"pw_salt":    salt.hex_encode(),
		"characters": [],
	}
	save_account(username, data)
	return {"ok": true, "reason": ""}


## Returns true if password matches stored hash.
func verify_password(username: String, password: String) -> bool:
	var data := load_account(username)
	if data.is_empty():
		return false
	var salt_hex: String = data.get("pw_salt", "")
	var hash_hex: String = data.get("pw_hash", "")
	if salt_hex.is_empty() or hash_hex.is_empty():
		return false
	var salt := salt_hex.hex_decode()
	var computed := NetProtocol.pbkdf2(password, salt)
	return computed.hex_encode() == hash_hex


# ---------------------------------------------------------------------------
# Character helpers
# ---------------------------------------------------------------------------

## Return the character dict matching name, or {} if not found.
func get_char(username: String, char_name: String) -> Dictionary:
	var data := load_account(username)
	for c in data.get("characters", []):
		if (c as Dictionary).get("name", "").to_lower() == char_name.to_lower():
			return c
	return {}


## Return all characters for an account.
func get_chars(username: String) -> Array:
	return load_account(username).get("characters", [])


## Add a new character to the account.  Returns {ok, reason}.
func add_char(username: String, char_dict: Dictionary) -> Dictionary:
	var data := load_account(username)
	if data.is_empty():
		return {"ok": false, "reason": "Account not found."}
	var chars: Array = data.get("characters", [])
	if chars.size() >= MAX_CHARS:
		return {"ok": false, "reason": "Maximum characters reached."}
	var name_str: String = char_dict.get("name", "")
	if name_str.length() < 3 or name_str.length() > 16:
		return {"ok": false, "reason": "Name must be 3-16 characters."}
	# Check name uniqueness across ALL accounts is hard with file storage —
	# skip for now; server will handle collision on login.
	for c in chars:
		if (c as Dictionary).get("name", "").to_lower() == name_str.to_lower():
			return {"ok": false, "reason": "You already have a character with that name."}
	chars.append(char_dict)
	data["characters"] = chars
	save_account(username, data)
	return {"ok": true, "reason": ""}


## Remove a character from the account by name.
func delete_char(username: String, char_name: String) -> void:
	var data := load_account(username)
	if data.is_empty():
		return
	var chars: Array = data.get("characters", [])
	for i in chars.size():
		if (chars[i] as Dictionary).get("name", "") == char_name:
			chars.remove_at(i)
			data["characters"] = chars
			save_account(username, data)
			return


## Save a mutated character dict back to disk.
## char_dict must be the same Dictionary reference stored in memory
## (or supply username+name to locate and overwrite).
func save_char(username: String, char_dict: Dictionary) -> void:
	var data := load_account(username)
	if data.is_empty():
		return
	var chars: Array = data.get("characters", [])
	var name_str: String = char_dict.get("name", "")
	for i in chars.size():
		if (chars[i] as Dictionary).get("name", "") == name_str:
			# Strip runtime-only keys (underscore prefix) before persisting.
			var clean: Dictionary = {}
			for k in char_dict:
				if not (k as String).begins_with("_"):
					clean[k] = char_dict[k]
			chars[i] = clean
			data["characters"] = chars
			save_account(username, data)
			return


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

func is_banned(username: String) -> bool:
	return load_account(username).get("banned", false)


func get_ban_reason(username: String) -> String:
	return load_account(username).get("ban_reason", "Banned.")


func set_role(username: String, role: int) -> void:
	var data := load_account(username)
	if data.is_empty():
		return
	data["role"] = role
	save_account(username, data)


func _path(username: String) -> String:
	return SAVE_DIR + username.to_lower() + ".json"
