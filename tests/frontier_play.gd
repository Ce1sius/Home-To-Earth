extends "res://tests/opening_flow.gd"


func _motion(at: Vector2, mask: int = 0) -> void:
	# Godot's root-window drop callback reads the system pointer, not push_input's
	# event position. Keep that pointer in sync while exercising normal GUI events.
	if DisplayServer.get_name() == "headless":
		var event := InputEventMouseMotion.new()
		event.position = root.get_screen_transform() * at
		event.global_position = event.position
		event.button_mask = mask
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	else:
		root.warp_mouse(at)
	super._motion(at, mask)


func _play() -> void:
	Save.path = "/private/tmp/starfire-frontier-%d.json" % OS.get_process_id()
	change_scene_to_file("res://scenes/title.tscn")
	await scene_changed
	_click(_center(current_scene.start_button))
	await scene_changed
	var game := current_scene
	game.set_process(false)
	game.feedback.sound_enabled = false
	_run_job(game, "wreck", "salvage")
	_run_job(game, "ore", "mine")
	_run_job(game, "casualty", "rescue")
	await create_timer(1.3).timeout
	_expect(not game.scout_button.visible, "First harvest gates field expeditions")
	var old: Vector2 = game.state.site_position("greenhouse")
	var target := Vector2(176, 288)
	_expect(game.state.layout.reason(game.state, "greenhouse", target).is_empty(), "Selected camp plot is legal: " + game.state.layout.reason(game.state, "greenhouse", target))
	var from := _center(game.sites["greenhouse"])
	var destination: Vector2 = game.MAP_POS + target
	_motion(from)
	_mouse(from, MOUSE_BUTTON_LEFT, true)
	_motion(from.lerp(destination, 0.2), MOUSE_BUTTON_MASK_LEFT)
	await process_frame
	_motion(destination, MOUSE_BUTTON_MASK_LEFT)
	await process_frame
	_expect(game._placement_valid and game.drag_hint.visible, "Real facility drag displays a legal placement preview: " + str(game._drag_payload) + " / " + game.drag_text.text + " / " + str(game._placement_point) + " field " + str(game.field.get_rect()))
	await _capture("facility_placement")
	_mouse(destination, MOUSE_BUTTON_LEFT, false)
	await process_frame
	_expect(game.state.site_position("greenhouse") == target and game.sites["greenhouse"].position == target - game.sites["greenhouse"].size / 2,
		"Dropping a facility moves the real worksite")
	await _drag(_center(game.sites["greenhouse"]), _center(game.sites["ore"]))
	_expect(game.state.site_position("greenhouse") == target, "Overlapping drop does not mutate the layout")
	_run_job(game, "greenhouse", "build")
	_expect(game.state.greenhouse_built and game.state.crew[game.selected_crew]["pos"].distance_to(target) < 250,
		"Crew reaches and builds at the moved worksite")
	for cycle in range(4):
		_run_job(game, "ice", "extract")
	await _drag(_center(game.crew_cards["tech"]), _center(game.sites["greenhouse"]))
	_advance(game, 22)
	_expect(game.state.first_harvest and game.scout_button.visible, "Food supply unlocks the exploration board")
	_expect(not game.sites["greenhouse"].relocatable and not game.state.layout.move_site(game.state, "greenhouse", old), "Occupied worksite cannot be moved out from under a worker")
	await create_timer(1.3).timeout
	_click(_center(game.crew_cards["lead"]))
	_click(_center(game.scout_button))
	_expect(game.paused and game.expedition_buttons.size() == 6, "Exploration presents six choices across three finite locations")
	await process_frame
	_check_exploration_layout(game)
	await _capture("exploration_choices")
	var fast := "--salvage" in OS.get_cmdline_user_args()
	var first := "scout_scrap" if fast else "scout_parts"
	_click(_center(game.expedition_buttons[first]))
	_advance_until_away(game)
	_advance(game, 3)
	_expect(game.state.crew_away("lead") and not game.crew_cards["lead"].visible, "Dispatched crew is absent from camp during the expedition")
	var transit_elapsed: float = game.state.crew["lead"]["elapsed"]
	var reserved: Dictionary = game.state.crew["lead"]["reserved"].duplicate()
	_expect(not reserved.is_empty() and game.state.expeditions.resolved.is_empty(), "Supplies are reserved before any exploration reward")
	game = await _save_reload(game)
	_expect(game.state.site_position("greenhouse") == target and game.state.crew["lead"]["reserved"] == reserved and is_equal_approx(game.state.crew["lead"]["elapsed"], transit_elapsed), "Save restores relocation and an in-flight expedition without charging twice")
	_click(_center(game.scout_button))
	await process_frame
	_check_exploration_layout(game)
	await _capture("expedition_in_progress")
	var before_recall: int = game.state.inventory["food"]
	_click(_center(game.expedition_recall))
	_expect(game.state.inventory["food"] == before_recall + reserved["food"] and not game.state.crew_away("lead") and game.state.expeditions.resolved.is_empty(), "Recall refunds only the pending trip and leaves the location unclaimed")
	_click(_center(game.scout_button))
	_click(_center(game.expedition_buttons[first]))
	_finish_trip(game, first)
	_expect(game.state.expeditions.resolved.get("cargo") == first, "One chosen cargo recovery resolves the location")
	var unchanged: Dictionary = game.state.inventory.duplicate()
	_expect(not game.state.assign("lead", "scout_scrap") and not game.state.assign("lead", "scout_parts") and game.state.inventory == unchanged, "Resolved locations cannot be farmed through either route")
	var second := "scout_ice" if fast else "scout_ore"
	_click(_center(game.scout_button))
	_click(_center(game.expedition_buttons[second]))
	_advance_until_away(game)
	var health: float = game.state.crew["lead"]["health"]
	_finish_trip(game, second)
	_expect(game.state.crew["lead"]["health"] <= health - 11.9 if not fast else game.state.crew["lead"]["health"] >= health,
		"Only the announced risky route causes health loss")
	var third := "scout_circuit" if fast else "scout_blueprint"
	_click(_center(game.scout_button))
	_click(_center(game.expedition_buttons[third]))
	_finish_trip(game, third)
	_expect(game.state.expeditions.resolved.size() == 3, "All three locations record their selected outcome")
	if not fast:
		_expect(game.state.expeditions.sampler_blueprint and not game.state.expeditions.sampler_built, "Finding technology still requires a prototype")
		_stock(game, "scrap", 2)
		_run_job(game, "relay", "trade_food")
		var at := _center(game.sites["lab"])
		_motion(at)
		_mouse(at, MOUSE_BUTTON_RIGHT, true)
		_mouse(at, MOUSE_BUTTON_RIGHT, false)
		_expect(game.context_buttons.has("trial_sampler") and not game.context_buttons["trial_sampler"].disabled, "Found blueprint exposes its prototype at the lab")
		_click(_center(game.context_buttons["trial_sampler"]))
		_advance(game, 24)
		_expect(game.state.expeditions.sampler_built, "Prototype consumes materials and enables the new tool")
		var ore: int = game.state.inventory["ore"]
		_run_job(game, "ore", "mine")
		_expect(game.state.inventory["ore"] == ore + 3, "Exploration technology changes actual gathering yield")
	await create_timer(1.5).timeout
	_click(_center(game.scout_button))
	await _capture("exploration_report")
	_key(KEY_ESCAPE)
	_expect(Save.write_game(game.state, "camp", "lead") and not Save.read_game().is_empty(), "Completed discoveries and upgrades survive saving")
	DirAccess.remove_absolute(Save.path)
	if failures == 0:
		print("PASS: facility drag placement, collision rejection, relocated work, three exploration choices, recall/refund, transit save, finite rewards, risk and prototype upgrade")
	quit(1 if failures else 0)


func _advance_until_away(game: Control) -> void:
	for step in range(250):
		_advance(game, 0.05)
		if game.state.crew_away("lead"):
			return
	_expect(false, "Expedition could not depart: " + game.log_line.text)


func _check_exploration_layout(game: Control) -> void:
	for node in game.exploration_overlay.find_children("*", "Label", true, false):
		var label := node as Label
		var parent := label.get_parent() as Control
		_expect(Rect2(Vector2.ZERO, parent.size).encloses(label.get_rect()), "Exploration text remains inside its card: " + label.text)


func _finish_trip(game: Control, recipe: String) -> void:
	for step in range(1200):
		_advance(game, 0.05)
		if game.state.expeditions.resolved.get(game.state.RECIPES[recipe]["expedition"]) == recipe:
			return
	_expect(false, "Expedition timed out: " + game.log_line.text)


func _save_reload(game: Control) -> Control:
	_key(KEY_ESCAPE)
	_click(_center(game.save_button))
	_click(_center(game.back_button))
	await scene_changed
	_click(_center(current_scene.continue_button))
	await scene_changed
	var resumed := current_scene
	resumed.set_process(false)
	resumed.feedback.sound_enabled = false
	return resumed
