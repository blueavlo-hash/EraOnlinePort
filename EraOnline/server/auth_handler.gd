class_name AuthHandler
## Era Online - Authentication Handler
## Manages login and registration using PBKDF2-HMAC-SHA256 password hashing.
## Called by ServerMain; never touches the network directly.

var _db: ServerDB


func _init(db: ServerDB) -> void:
	_db = db


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Attempt login. Returns:
##   {ok:true,  account_id:int, char_name:str, error:""}
##   {ok:false, account_id:0,   char_name:"",  error:"<reason>"}
func login(username: String, password_plain: String) -> Dictionary:
	if not is_valid_username(username):
		return _fail("Invalid username or password")

	var acc := _db.get_account(username)
	if acc.is_empty():
		# Don't leak whether the username exists
		return _fail("Invalid username or password")

	if acc.get("banned", false):
		var reason: String = acc.get("ban_reason", "No reason given")
		return _fail("Account banned: " + reason)

	# Verify password
	var salt_hex: String = acc.get("password_salt", "")
	var stored_hash_hex: String = acc.get("password_hash", "")
	if salt_hex.is_empty() or stored_hash_hex.is_empty():
		return _fail("Invalid username or password")

	var salt          := salt_hex.hex_decode()
	var computed_hash := NetProtocol.pbkdf2(password_plain, salt)
	var stored_hash   := stored_hash_hex.hex_decode()

	if not _constant_time_compare(computed_hash, stored_hash):
		return _fail("Invalid username or password")

	_db.update_last_login(username)

	var char_name: String = acc.get("character", {}).get("name", username)
	return {
		"ok":         true,
		"account_id": acc.get("account_id", 0) as int,
		"char_name":  char_name,
		"error":      "",
	}


## Attempt registration. Returns:
##   {ok:true,  error:""}
##   {ok:false, error:"<reason>"}
func register(username: String, password_plain: String) -> Dictionary:
	if not is_valid_username(username):
		return _fail_reg("Username must be 3-20 characters (letters, numbers, underscore)")

	if not is_valid_password(password_plain):
		return _fail_reg("Password must be 6-64 characters")

	if _db.account_exists(username):
		return _fail_reg("Username already taken")

	var salt          := Crypto.new().generate_random_bytes(16)
	var password_hash := NetProtocol.pbkdf2(password_plain, salt)
	var account_id    := _db.create_account(username, password_hash.hex_encode(), salt.hex_encode())

	if account_id < 0:
		return _fail_reg("Registration failed — please try again")

	return {"ok": true, "error": ""}


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

static func is_valid_username(s: String) -> bool:
	if s.length() < 3 or s.length() > 20:
		return false
	for ch in s:
		var code := ch.unicode_at(0)
		var is_alpha := (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		var is_digit := (code >= 48 and code <= 57)
		var is_underscore := (code == 95)
		if not (is_alpha or is_digit or is_underscore):
			return false
	return true


static func is_valid_password(s: String) -> bool:
	return s.length() >= 6 and s.length() <= 64


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

## Constant-time byte comparison to prevent timing attacks.
func _constant_time_compare(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var diff := 0
	for i in a.size():
		diff |= a[i] ^ b[i]
	return diff == 0


func _fail(reason: String) -> Dictionary:
	return {"ok": false, "account_id": 0, "char_name": "", "error": reason}


func _fail_reg(reason: String) -> Dictionary:
	return {"ok": false, "error": reason}
