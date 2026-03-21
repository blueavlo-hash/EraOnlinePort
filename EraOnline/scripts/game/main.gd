extends Node
## Era Online - Main Scene Entry Point
## Detects --server flag to run headless, otherwise shows splash → login → char select → world.

const WORLD_SCENE := "res://scenes/game/World.tscn"

var _prefill_user:  String = ""
var _prefill_token: String = ""


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
		_prefill_user  = _get_arg(args, "--username")
		_prefill_token = _get_arg(args, "--token")
		var addr := _get_arg(args, "--server-address", "127.0.0.1")
		var port := int(_get_arg(args, "--server-port", "6969"))
		_show_splash(addr, port)


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
	# Server runs indefinitely; keep main alive as the scene root.


func _start_editor() -> void:
	print("[Main] Starting Map Editor...")
	var packed := load("res://scenes/editor/MapEditor.tscn") as PackedScene
	if packed == null:
		push_error("[Main] Could not load MapEditor.tscn")
		return
	get_tree().root.add_child(packed.instantiate())
	queue_free()


func _show_splash(addr: String = "127.0.0.1", port: int = 6969) -> void:
	var splash := preload("res://scripts/ui/splash_ui.gd").new()
	splash.name = "SplashUI"
	if _prefill_user != "":
		splash._launcher_user = _prefill_user
		splash._launcher_addr = addr
		splash._launcher_port = port
	add_child(splash)
	splash.online_requested.connect(
		func(a: String, p: int): _on_online_requested(a, p, _prefill_user, _prefill_token)
	)


# ---------------------------------------------------------------------------
# Online flow
# ---------------------------------------------------------------------------

func _on_online_requested(address: String, port: int, prefill_user: String = "", prefill_token: String = "") -> void:
	var splash := get_node_or_null("SplashUI")
	if splash:
		splash.queue_free()

	# Login UI (visible immediately — shows "Connecting…" until TLS ready)
	var login_ui := preload("res://scripts/ui/login_ui.gd").new()
	login_ui.name = "LoginUI"
	add_child(login_ui)
	if prefill_user != "" and prefill_token != "":
		login_ui.set_auto_login(prefill_user, prefill_token)

	# Char select UI (hidden until char_list_received)
	var char_ui := preload("res://scripts/ui/char_select_ui.gd").new()
	char_ui.name    = "CharSelectUI"
	char_ui.visible = false
	add_child(char_ui)

	# Wire: auth success → hide login, show char select
	Network.char_list_received.connect(
		func(chars: Array):
			if is_instance_valid(login_ui):
				login_ui.queue_free()
			if is_instance_valid(char_ui):
				char_ui.populate(chars)
	, CONNECT_ONE_SHOT)

	# Wire: entering world → load world scene
	Network.on_world_state.connect(_on_enter_world, CONNECT_ONE_SHOT)

	# Start the connection
	Network.connect_to_server(address, port)


# ---------------------------------------------------------------------------
# World entry (online)
# ---------------------------------------------------------------------------

func _on_enter_world(_map_id: int, _x: int, _y: int) -> void:
	var char_ui := get_node_or_null("CharSelectUI")
	if char_ui:
		char_ui.queue_free()
	_load_world()


# ---------------------------------------------------------------------------
# Shared world loader
# ---------------------------------------------------------------------------

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
