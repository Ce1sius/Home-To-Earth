extends "res://tests/frontier_play.gd"


func _play() -> void:
	var choose_cache := "--hull" not in OS.get_cmdline_user_args()
	var recipe := "recover_field_cache" if choose_cache else "salvage"
	Save.path = "/private/tmp/starfire-landing-salvage-%d.json" % OS.get_process_id()
	change_scene_to_file("res://scenes/title.tscn")
	await scene_changed
	_click(_center(current_scene.start_button))
	await scene_changed
	var game := current_scene
	game.set_process(false)
	game.feedback.sound_enabled = false
	_click(_center(game.speed_button))
	_expect(game.game_speed == 2, "Speed button selects double speed")
	_key(KEY_3)
	var start_time: float = game.state.clock
	game._process(0.25)
	_expect(is_equal_approx(game.state.clock - start_time, 1.0), "Four-speed advances one simulation second per quarter real second")
	var wreck := _center(game.sites["wreck"])
	_motion(wreck)
	_mouse(wreck, MOUSE_BUTTON_RIGHT, true)
	_mouse(wreck, MOUSE_BUTTON_RIGHT, false)
	var both_offered: bool = game.context_buttons.has("salvage") and game.context_buttons.has("recover_field_cache")
	_expect(both_offered, "Opening wreck offers both salvage plans by right click")
	if not both_offered:
		quit(1)
		return
	_expect(game.paused and game.state.inventory["food"] == 6, "Comparing plans preserves the simulation and starting supplies")
	var planning_time: float = game.state.clock
	game._process(0.25)
	_key(KEY_1)
	_expect(game.state.clock == planning_time and game.game_speed == 4, "Comparing salvage freezes simulation at fast speed")
	await _capture("landing_salvage_choice")
	_click(_center(game.context_buttons[recipe]))
	_key(KEY_1)
	_expect(game.game_speed == 1, "Normal speed can be restored after dispatch")
	for step in range(220):
		_advance(game, 0.05)
		if game.state.crew["lead"]["phase"] == "working":
			break
	_expect(game.state.crew["lead"]["phase"] == "working" and not game.state.recovered.has("wreck"), "Walking to the wreck and starting work grant no loot")
	_advance(game, 1)
	game = await _save_reload(game)
	_expect(game.state.crew["lead"]["job"] == recipe and game.state.inventory["scrap"] == 0, "Continue keeps the chosen salvage in progress")
	_advance(game, 10)
	var food := 10 if choose_cache else 6
	var scrap := 1 if choose_cache else 3
	_expect(game.state.inventory["food"] == food and game.state.inventory["scrap"] == scrap, "First salvage delivers exactly its displayed stock")
	_expect(game.state.survey_site_exhausted("wreck") and not game.state.assign("lead", "recover_field_cache") and not game.state.assign("lead", "salvage"), "Only one initial salvage can be collected")
	game = await _save_reload(game)
	_expect(game.state.inventory["food"] == food and game.state.inventory["scrap"] == scrap and not game.state.field_cache_available(), "Reload keeps the result and cannot reopen the sealed hold")
	_run_job(game, "ore", "mine")
	_run_job(game, "casualty", "rescue")
	_expect("recover_field_cache" not in game.state.order_actions("camp") and not game.state.assign("lead", "recover_field_cache"), "After rescue regular collection reopens, the first cache does not")
	_click(_center(game.crew_buttons["tech"]))
	_run_job(game, "greenhouse", "build")
	_click(_center(game.crew_buttons["lead"]))
	_run_job(game, "ice", "extract")
	_click(_center(game.crew_buttons["tech"]))
	_run_job(game, "greenhouse", "grow")
	_expect(game.state.first_harvest and game.scout_button.visible, "Both routes can build, feed the camp and unlock field expeditions")
	if choose_cache:
		_click(_center(game.crew_buttons["lead"]))
		_click(_center(game.scout_button))
		_click(_center(game.expedition_buttons["scout_parts"]))
		_finish_trip(game, "scout_parts")
		_expect(game.state.inventory["plate"] == 2, "Recovered rations can fund an actual field expedition")
	else:
		_run_job(game, "shelter", "expand_shelter")
		_expect(game.state.shelter_expanded, "Hull stock pays for both a greenhouse and a larger shelter")
	DirAccess.remove_absolute(Save.path)
	if failures == 0:
		print("PASS: first salvage choice, work-in-progress continue, one-time supplies, rescue, food production and chosen route payoff / " + recipe)
	quit(1 if failures else 0)
