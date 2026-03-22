extends Node
## Era Online - Main Scene Entry Point
##
## Launcher path:  token in session.dat → connect immediately in background →
##                 SplashUI shows "Connecting…" → Play enables on char list →
##                 CharSelectUI → World.
##
## Direct path:    no token → show in-game LauncherUI (login/register).
##
## CLI flags:
##   --server               Run as headless game server.
##   --editor               Open the map editor.
##   --skip-launcher        Dev shortcut: bypass launcher UI, uses --token if supplied.
##   --username <name>      Pre-fill display name on SplashUI.
##   --token <tok>          Pre-fill auth token (used with --skip-launcher).

const WORLD_SCENE := "res://scenes/game/World.tscn"

var _prefill_user:  String = ""
var _pending_chars: Array  = []


func _ready() -> void:
	print("============================================")
	print("  Era Online - Godot 4 Port")
	print("============================================")

	# Wait one frame to ensure autoloads are fully initialized
	await get_tree().process_frame

	if not GameData.is_loaded:
		push_error("[Main] GameData failed to load! Run tools/run_pipeline.py first.")
		return

	_print_summary()

	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if "--server" in args:
		_start_server()
	elif "--editor" in args:
		_start_editor()
	else:
		var tok := _get_arg(args, "--token")
		if tok != "":
			# Launched from official launcher — token passed as CLI arg.
			Network.launcher_token = tok
			_prefill_user = _get_arg(args, "--username")
			_show_splash()
		elif "--skip-launcher" in args:
			# Dev shortcut — no token, show splash with direct Play button.
			_prefill_user = _get_arg(args, "--username")
			_show_splash()
		elif Network.load_launcher_token():
			# Legacy: token stored in session.dat.
			print("[Main] Launcher token loaded — connecting in background")
			_prefill_user = Network.launcher_username
			_show_splash()
		else:
			_show_launcher()


func _get_arg(args: PackedStringArray, key: String, default_val: String = "") -> String:
	var idx := args.find(key)
	if idx >= 0 and idx + 1 < args.size():
		return args[idx + 1]
	return default_val


func _start_server() -> void:
	print("[Main] Starting in server mode...")
	var ServerScript = load("res://scripts/server/game_server.gd")
	if ServerScript == null:
		push_error("[Main] Could not load game_server.gd")
		return
	var srv = ServerScript.new()
	srv.name = "GameServer"
	add_child(srv)


func _start_editor() -> void:
	print("[Main] Starting Map Editor...")
	var packed := load("res://scenes/editor/MapEditor.tscn") as PackedScene
	if packed == null:
		push_error("[Main] Could not load MapEditor.tscn")
		return
	get_tree().root.add_child(packed.instantiate())
	queue_free()


func _show_launcher() -> void:
	var packed := load("res://scenes/ui/LauncherUI.tscn") as PackedScene
	if packed == null:
		push_error("[Main] Could not load LauncherUI.tscn")
		return
	var launcher := packed.instantiate()
	launcher.name = "LauncherUI"
	get_tree().root.add_child(launcher)
	queue_free()


# ---------------------------------------------------------------------------
# Splash / main menu
# ---------------------------------------------------------------------------

func _show_splash() -> void:
	var splash := preload("res://scripts/ui/splash_ui.gd").new()
	splash.name = "SplashUI"
	if _prefill_user != "":
		splash._launcher_user = _prefill_user
	add_child(splash)
	splash.play_pressed.connect(_on_play_pressed)

	if Network.launcher_token != "":
		# Token present — connect immediately while the menu is visible.
		# SplashUI starts with Play disabled ("Connecting…"); we enable it
		# once the server sends the char list.
		Network.char_list_received.connect(_on_char_list_received, CONNECT_ONE_SHOT)
		Network.connection_failed.connect(_on_connect_failed, CONNECT_ONE_SHOT)
		Network.auth_failed.connect(_on_auth_failed, CONNECT_ONE_SHOT)
		Network.on_world_state.connect(_on_enter_world, CONNECT_ONE_SHOT)
		Network.connect_to_server(Network.SERVER_IP, Network.SERVER_PORT)
	else:
		# No token (dev --skip-launcher without --token) — enable Play immediately;
		# clicking it will connect and show login UI.
		splash.set_ready([])


func _on_char_list_received(chars: Array) -> void:
	_pending_chars = chars
	var splash := get_node_or_null("SplashUI")
	if is_instance_valid(splash):
		splash.set_ready(chars)


func _on_connect_failed(reason: String) -> void:
	var splash := get_node_or_null("SplashUI")
	if is_instance_valid(splash):
		splash.set_error("Could not connect to server.\n" + reason)


func _on_auth_failed(reason: String) -> void:
	var splash := get_node_or_null("SplashUI")
	if is_instance_valid(splash):
		splash.set_error("Login failed — please reopen the launcher.\n(" + reason + ")")


# ---------------------------------------------------------------------------
# Play pressed on main menu
# ---------------------------------------------------------------------------

func _on_play_pressed() -> void:
	var splash := get_node_or_null("SplashUI")
	if is_instance_valid(splash):
		splash.queue_free()

	if not _pending_chars.is_empty() or Network.state >= Network.State.CHAR_SELECT:
		# Already authenticated — go straight to char select.
		_show_char_select(_pending_chars)
	else:
		# No token / dev path — need to connect and login first.
		var login_ui := preload("res://scripts/ui/login_ui.gd").new()
		login_ui.name = "LoginUI"
		add_child(login_ui)
		Network.char_list_received.connect(
			func(chars: Array):
				if is_instance_valid(login_ui):
					login_ui.queue_free()
				_show_char_select(chars)
		, CONNECT_ONE_SHOT)
		if not (Network.state >= Network.State.CHAR_SELECT):
			Network.on_world_state.connect(_on_enter_world, CONNECT_ONE_SHOT)
			Network.connect_to_server(Network.SERVER_IP, Network.SERVER_PORT)


func _show_char_select(chars: Array) -> void:
	var char_ui := preload("res://scripts/ui/char_select_ui.gd").new()
	char_ui.name = "CharSelectUI"
	add_child(char_ui)
	char_ui.populate(chars)


# ---------------------------------------------------------------------------
# World entry
# ---------------------------------------------------------------------------

func _on_enter_world(_map_id: int, _x: int, _y: int) -> void:
	var char_ui := get_node_or_null("CharSelectUI")
	if char_ui:
		char_ui.queue_free()
	_load_world()


func _load_world() -> void:
	AudioManager.stop_music()
	var packed := load(WORLD_SCENE) as PackedScene
	if packed == null:
		push_error("[Main] Could not load World scene: " + WORLD_SCENE)
		return
	var world := packed.instantiate()
	get_tree().root.add_child(world)
	queue_free()


func _print_summary() -> void:
	print("")
	print("=== Data Summary ===")
	print("  GRH entries:   %d" % GameData.grh_data.size())
	print("  Objects:       %d" % GameData.objects.size())
	print("  NPCs:          %d" % GameData.npcs.size())
	print("  Spells:        %d" % GameData.spells.size())
	print("  Body anims:    %d" % GameData.bodies.size())
	print("  Head anims:    %d" % GameData.heads.size())
	print("  Weapon anims:  %d" % GameData.weapon_anims.size())
	print("  Shield anims:  %d" % GameData.shield_anims.size())
	print("  Maps:          %d" % GameData.map_index.size())
	print("")
