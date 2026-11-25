extends "res://tests/integration_play.gd"


func _play() -> void:
	Save.path = "/private/tmp/starfire-aid-play-%d.json" % OS.get_process_id()
	change_scene_to_file("res://scenes/title.tscn")
	await scene_changed
	if "--compact" in OS.get_cmdline_user_args():
		root.size = Vector2i(960, 640)
		await process_frame
	_click(_center(current_scene.start_button))
	await scene_changed
	var game := current_scene
	game.set_process(false)
	game.feedback.sound_enabled = false
	_run_job(game, "wreck", "salvage")
	_run_job(game, "ore", "mine")
	_run_job(game, "casualty", "rescue")
	_click(_center(game.crew_buttons["tech"]))
	_open_site(game, "shelter")
	_expect(game.context_buttons.has("camp_care") and game.context_buttons["camp_care"].disabled, "Nursing is visible but unavailable until actual water is gathered")
	_key(KEY_ESCAPE)
	_click(_center(game.crew_buttons["lead"]))
	_run_job(game, "ice", "extract")
	_click(_center(game.crew_buttons["tech"]))
	_open_site(game, "shelter")
	_click(_center(game.context_buttons["camp_care"]))
	_wait_finished(game, "tech", "camp_care")
	_expect(game.state.crew["tech"]["health"] == 100 and game.state.inventory["ice"] == 1, "Rescued worker uses supplies and recovers through the real shelter menu")
	_run_job(game, "greenhouse", "build")
	_click(_center(game.crew_buttons["lead"]))
	for cycle in range(4):
		_run_job(game, "ice", "extract")
	_click(_center(game.crew_buttons["tech"]))
	await _choose_order(game, "grow", 2, 18)
	_advance(game, 16)
	_expect(game.state.first_harvest, "Actual crop production unlocks cooperation")
	_click(_center(game.crew_buttons["lead"]))
	for cycle in range(2):
		_run_job(game, "ore", "mine")
	var components := "--components" in OS.get_cmdline_user_args()
	if components:
		_stock(game, "plate", 1)
		_stock(game, "scrap", 2)
	await _choose_order(game, "extract", 2, 8)
	_wait_offer(game, "water")
	_advance(game, 12)
	await create_timer(1.4).timeout
	_click(_center(game.aid_button))
	_expect(game.context_buttons.has("aid_water") and game.context_buttons.has("aid_repair") and game.paused, "Aid reminder opens both real delivery choices")
	_expect(game.goal_button.visible and game.goal_button.text != game.aid_button.text, "Active aid keeps the campaign objective reachable")
	var remaining: float = game.state.requests.remaining
	game._process(8)
	_expect(game.state.requests.remaining == remaining, "Comparing offers pauses their deadline")
	await process_frame
	_check_context(game)
	await _capture("aid_choices")
	_key(KEY_ESCAPE)
	await process_frame
	_expect(game.detail_body.position.y + game.detail_body.size.y <= game.action_button.position.y, "Aid briefing fits above the action buttons")
	await _capture("aid_request")
	_click(_center(game.aid_button))
	var first := "aid_repair" if components else "aid_water"
	_expect(not game.context_buttons[first].disabled, "Chosen aid route has collected supplies")
	_click(_center(game.context_buttons[first]))
	_wait_working(game, "lead", first)
	var paid: Dictionary = game.state.crew["lead"]["reserved"].duplicate()
	var circuits: int = game.state.inventory["circuit"]
	remaining = game.state.requests.remaining
	game = await _save_reload(game)
	_expect(is_equal_approx(game.state.requests.remaining, remaining) and game.state.crew["lead"]["reserved"] == paid, "Menu continue preserves the aid deadline and paid supplies")
	_wait_finished(game, "lead", first)
	_expect(game.state.requests.completed == 1 and game.state.inventory["circuit"] == circuits + (1 if components else 2), "Completing delivery pays its chosen route exactly once")
	_expect(game.state.crew["lead"]["job"] == "extract" and game.state.requests.care_health() == 45, "Aid resumes the former water duty and shares care knowledge")
	_open_site(game, "relay")
	_expect(not game.context_buttons.has("aid_water") and not game.context_buttons.has("aid_repair"), "The unchosen delivery closes too")
	_key(KEY_ESCAPE)
	_click(_center(game.scout_button))
	_click(_center(game.expedition_buttons["scout_ore"]))
	_finish_trip(game, "scout_ore")
	_expect(game.state.crew["lead"]["health"] < 90, "Risky exploration creates an injury to treat")
	_click(_center(game.crew_buttons["lead"]))
	await create_timer(1.4).timeout
	await _choose_order(game, "camp_care", 3, 1, "camp_nursing")
	_wait_finished(game, "lead", "camp_care")
	_expect(game.state.crew["lead"]["health"] == 100 and game.state.crew["lead"]["job"] == "extract", "Post-exploration nursing heals and returns the explorer to their duty")
	_wait_offer(game, "supplies")
	await _choose_order(game, "aid_food", 3, 1)
	var plates: int = game.state.inventory["plate"]
	_wait_finished(game, "lead", "aid_food")
	_expect(game.state.requests.completed == 2 and game.state.inventory["plate"] == plates + 2, "The next request uses real grown food to obtain building materials")
	_wait_offer(game, "samples")
	_advance(game, game.state.requests.remaining - 8)
	await _choose_order(game, "aid_samples", 3, 1)
	_wait_working(game, "lead", "aid_samples")
	var ore: int = game.state.inventory["ore"]
	circuits = game.state.inventory["circuit"]
	_advance(game, 10)
	_expect(game.state.requests.expired == 1 and game.state.requests.completed == 2 and game.state.inventory["ore"] == ore + 6 and game.state.inventory["circuit"] == circuits, "A real late delivery expires and returns reserved samples without a reward")
	_expect(game.state.crew["lead"]["job"] == "extract" and game.state.crew["lead"]["duty"]["target"] == 8, "After expiry, original stock work continues")
	await create_timer(1.4).timeout
	_click(_center(game.sites["relay"]))
	await _capture("aid_camp")
	_expect(game._save_game() and not Save.read_game().is_empty(), "Aid outcomes and stronger nursing persist")
	DirAccess.remove_absolute(Save.path)
	if failures == 0:
		print("PASS: fresh-menu nursing, actual supply production, both aid routes, planning pause, saved delivery, exclusive rewards, risky exploration care and deadline return to duty")
	quit(1 if failures else 0)


func _open_site(game: Control, site: String) -> void:
	var at := _center(game.sites[site])
	_motion(at)
	_mouse(at, MOUSE_BUTTON_RIGHT, true)
	_mouse(at, MOUSE_BUTTON_RIGHT, false)
	_expect(is_instance_valid(game.context_overlay), "Open actual right-click menu")


func _wait_finished(game: Control, id: String, recipe: String) -> void:
	_expect(game.state.crew[id]["job"] == recipe, "Task accepted: " + recipe)
	for step in range(1400):
		_advance(game, 0.05)
		if game.state.crew[id]["job"] != recipe:
			return
	_expect(false, "Task did not finish: " + recipe)


func _wait_working(game: Control, id: String, recipe: String) -> void:
	for step in range(300):
		_advance(game, 0.05)
		if game.state.crew[id]["job"] == recipe and game.state.crew[id]["phase"] == "working":
			return
	_expect(false, "Task did not reach work phase: " + recipe)


func _wait_offer(game: Control, offer: String) -> void:
	for step in range(4000):
		if game.state.requests.active == offer:
			return
		_advance(game, 0.05)
	_expect(false, "Expected offer did not arrive: " + offer)


func _check_context(game: Control) -> void:
	for node in game.context_overlay.find_children("*", "Label", true, false):
		var label := node as Label
		var parent := label.get_parent() as Control
		_expect(Rect2(Vector2.ZERO, parent.size).encloses(label.get_rect()), "Choice text fits its panel: " + label.text)
	for button in game.context_buttons.values():
		_expect(Rect2(Vector2.ZERO, game.SIZE).encloses(button.get_global_rect()), "Every choice is reachable on screen")
