extends SceneTree

const Save := preload("res://scripts/campaign_save.gd")


func _initialize() -> void:
	_verify.call_deferred()


func _verify() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] == args[1] or FileAccess.file_exists(args[1]):
		_fail("Supply a fixture and a separate, unused temporary save path")
		return
	Save.path = args[1]
	if DirAccess.copy_absolute(args[0], Save.path) != OK:
		_fail("Could not copy the simulated 0.4.0 camp")
		return
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Save.path))
	if int(original.get("version", 0)) != 7 or change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene")) != OK:
		_fail("Expected a v7 fixture and a working title screen")
		return
	await scene_changed
	if not current_scene.continue_button.visible or current_scene.continue_button.disabled:
		_fail("The title menu cannot continue the old camp")
		return
	current_scene.continue_button.pressed.emit()
	await scene_changed
	var game := current_scene
	game.set_process(false)
	var state: RefCounted = game.state
	var old: Dictionary = original["state"]
	for item in old["inventory"]:
		if int(old["inventory"][item]) != state.inventory.get(item, -1):
			_fail("Inventory changed on load: " + item)
			return
	if state.crew.size() != 2 or state.expeditions.resolved != old["expeditions"]["resolved"] or game.viewed_region != original["region"]:
		_fail("The camp location, workers, or discoveries changed on load")
		return
	if game.viewed_region == "highlands":
		if not state.outpost_built or state.navigation_count() != 1 or not game.radar_button.visible or game.radar_button.disabled:
			_fail("The old outpost, navigation record, or radar controls are missing")
			return
		game.radar_button.pressed.emit()
		if not is_instance_valid(game.radar_board):
			_fail("Radar could not open in the old highlands")
			return
		game.radar_board.close_button.pressed.emit()
	elif state.expeditions.patrol_count != 2 or state.field_gear.equipped != "cooler" or state.field_gear.built.size() != 2:
		_fail("The old camp lost a patrol or equipment")
		return
	if not game._save_game():
		_fail("Could not write the migrated campaign")
		return
	var migrated: Variant = JSON.parse_string(FileAccess.get_file_as_string(Save.path))
	if migrated.get("version", 0) != Save.VERSION or Save.read_game().is_empty():
		_fail("The migrated campaign failed to reload")
		return
	print("PASS: exported game continues 0.4.0 fixture, preserves progress, saves and reloads ", game.viewed_region)
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
