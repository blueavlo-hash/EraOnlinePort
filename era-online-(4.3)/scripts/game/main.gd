extends Node
## Era Online - Main Scene Entry Point
## Verifies data is loaded then launches the game world.

const WORLD_SCENE := "res://scenes/game/World.tscn"

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
	_load_world()


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


func _load_world() -> void:
	var packed := load(WORLD_SCENE)
	if packed == null:
		push_error("[Main] Could not load World scene: " + WORLD_SCENE)
		return
	var world := packed.instantiate()
	get_tree().root.add_child(world)
	# Remove this placeholder node - world is now running
	queue_free()
