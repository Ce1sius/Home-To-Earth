extends "res://tests/frontier_play.gd"


func _play() -> void:
	Save.path = "/private/tmp/starfire-board-play-%d.json" % OS.get_process_id()
	change_scene_to_file("res://scenes/title.tscn")
	await scene_changed
	_click(_center(current_scene.start_button))
	await scene_changed
	var game := current_scene
	game.set_process(false)
	game._settings_path = Save.path + ".cfg"
	game.feedback.sound_enabled = "--sound" in OS.get_cmdline_user_args()
	get_tree_watchdog()
	if "--force-fail" in OS.get_cmdline_user_args():
		_expect(false, "Intentional harness failure")
		_finish(game)
		return
	var before: Dictionary = game.state.inventory.duplicate()
	_open_menu(game, "wreck")
	_expect(game.paused and is_instance_valid(game.context_overlay), "Right click opens a planning menu")
	_expect(game.state.crew["lead"]["job"].is_empty() and game.state.inventory == before, "Inspecting actions never dispatches crew or spends materials")
	_expect(game.context_buttons.has("salvage") and game.context_duties.has("salvage"), "Menu offers a single batch and a persistent post")
	await _capture("action_menu")
	_key(KEY_ESCAPE)
	_expect(not game.paused and not is_instance_valid(game.context_overlay), "Dismiss restores the previous time state")
	_key(KEY_SPACE)
	_open_menu(game, "wreck")
	_key(KEY_ESCAPE)
	_expect(game.paused, "Closing a task menu preserves an existing planning pause")
	_key(KEY_SPACE)
	var from := _center(game.crew_cards["lead"])
	var target := _center(game.sites["wreck"])
	_motion(from)
	_mouse(from, MOUSE_BUTTON_LEFT, true)
	_motion(from.lerp(target, 0.2), MOUSE_BUTTON_MASK_LEFT)
	await process_frame
	_motion(target, MOUSE_BUTTON_MASK_LEFT)
	await process_frame
	_expect(game.sites["wreck"].drop_valid and game.drag_hint.visible and "残件" in game.drag_text.text, "Actual drag highlights a valid target and previews its output")
	await _capture("drag_preview")
	_mouse(target, MOUSE_BUTTON_LEFT, false)
	await process_frame
	_expect(not game.drag_hint.visible and not game.sites["wreck"].drop_active, "Drop removes all targeting highlights")
	_expect(game.state.crew["lead"]["job"] == "salvage", "Actual drop issues a working order")
	for step in range(250):
		_advance(game, 0.05)
		if game.state.inventory["scrap"] > 0:
			break
	_expect(game.state.inventory["scrap"] == 3 and not game.feedback.effects.is_empty(), "Completion adds exactly one yield and emits visible feedback")
	_expect(game.items["scrap"]._receipt_amount == 3 and game.items["scrap"]._receipt_left > 0, "The credited inventory slot shows the last earned batch")
	await _capture("harvest_feedback")
	var stable: Dictionary = game.state.inventory.duplicate()
	game.sites["wreck"].pop()
	await create_timer(0.03).timeout
	game.sites["wreck"].pop()
	await create_timer(1.6).timeout
	_expect(game.sites["wreck"].scale == Vector2.ONE and game.feedback.effects.is_empty(), "Retriggered feedback returns to rest and frees its visual effects")
	_expect(game.state.inventory == stable, "Visual playback never duplicates or consumes resources")
	await _drag(_center(game.items["food"]), _center(game.sites["ore"]))
	_expect(game.state.inventory == stable and game.state.crew["lead"]["job"].is_empty(), "Incompatible material drop cannot dispatch work or spend supplies")
	_run_job(game, "ore", "mine")
	_run_job(game, "casualty", "rescue")
	_expect(not game.state.survey_site_exhausted("wreck"), "Rescue reopens gathering without forcing the greenhouse first")
	_run_job(game, "wreck", "salvage")
	_expect(game.state.inventory["scrap"] == 6 and not game.state.first_harvest, "Player can stock materials before following the next suggested objective")
	_click(_center(game.crew_cards["tech"]))
	_run_job(game, "greenhouse", "build")
	var stock: Dictionary = game.state.inventory.duplicate()
	_open_menu(game, "greenhouse")
	_expect(game.context_buttons["grow"].disabled and not game.context_duties["grow"].disabled, "Missing ice prevents a one-off craft but permits a waiting post")
	_click(_center(game.context_duties["grow"]))
	_advance(game, 8)
	_expect(game.state.crew["tech"]["phase"] == "waiting" and game.state.inventory["food"] == stock["food"], "Waiting post produces nothing before supplies arrive")
	_click(_center(game.crew_cards["lead"]))
	_run_job(game, "ice", "extract")
	_advance(game, 18)
	_expect(game.state.first_harvest, "Real gather, deliver and grow loop completes")
	_run_job(game, "lab", "research")
	_run_job(game, "ore", "mine")
	await create_timer(1.5).timeout
	_open_menu(game, "bench")
	_expect(game.context_buttons.has("fabricate") and game.context_buttons.has("etch"), "All unlocked recipes are available at their physical worksite")
	await _capture("crafting_choices")
	_click(_center(game.context_buttons["fabricate"]))
	for step in range(300):
		_advance(game, 0.05)
		if game.state.crew["lead"]["phase"] == "working":
			break
	var bench_card: Control = game.sites["bench"]
	_expect(bench_card.worker_name == "领队" and bench_card.material_flow == "残件2 → 结构件1" and bench_card.work_recipe == "制造结构件",
		"The occupied worksite identifies the real worker, exactly paid materials and expected yield")
	await create_timer(1.25).timeout
	_advance(game, 2.0)
	_expect(bench_card.ratio > 0.1 and bench_card.ratio < 1, "Card progress follows ongoing work")
	await _capture("material_stack")
	var reserved: int = game.state.inventory["scrap"]
	game.state.stop_crew("lead")
	game._refresh()
	_expect(game.state.inventory["scrap"] == reserved + 2, "Canceling a visible stack refunds its reserved materials once")
	_expect(bench_card.worker_name.is_empty() and bench_card.material_flow.is_empty() and bench_card.ratio < 0,
		"An interrupted job immediately clears the on-card worker and planned yield")
	game._feedback_setting(true, "reduced_motion")
	game.sites["bench"].pop()
	_expect(game.sites["bench"].scale == Vector2.ONE, "Reduced motion suppresses card movement")
	_expect(Save.write_game(game.state, "camp", "lead") and not Save.read_game().is_empty(), "Reordered early gathering remains save-compatible")
	_finish(game)


func _open_menu(game: Control, site: String) -> void:
	var at := _center(game.sites[site])
	_motion(at)
	_mouse(at, MOUSE_BUTTON_RIGHT, true)
	_mouse(at, MOUSE_BUTTON_RIGHT, false)


func get_tree_watchdog() -> void:
	create_timer(45).timeout.connect(func():
		push_error("FAIL: board play timed out")
		quit(1))


func _finish(game: Control) -> void:
	game.feedback.effects.clear()
	DirAccess.remove_absolute(Save.path)
	DirAccess.remove_absolute(game._settings_path)
	if failures == 0:
		print("PASS: actual context choices, drag preview, output feedback, waiting supply loop, worksite recipes, material refund, reduced motion and save compatibility")
	quit(1 if failures else 0)
