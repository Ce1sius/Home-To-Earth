extends SceneTree

const Save := preload("res://scripts/campaign_save.gd")

var failures := 0
var pointer := Vector2.ZERO


func _initialize() -> void:
	_start_watchdog.call_deferred()
	_play.call_deferred()


func _start_watchdog() -> void:
	create_timer(60).timeout.connect(func():
		push_error("FAIL: campaign flow timed out")
		quit(1))


func _play() -> void:
	Save.path = "/private/tmp/starfire-flow-%d.json" % OS.get_process_id()
	var result := change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	if result != OK:
		push_error("Could not start the game")
		quit(1)
		return
	await scene_changed
	var title := current_scene
	await _capture("title")
	_click(_center(title.help_button))
	_expect(is_instance_valid(title.instructions), "Menu shows controls")
	_key(KEY_ESCAPE)
	await process_frame
	_expect(not is_instance_valid(title.instructions), "Escape dismisses menu help")
	_click(_center(title.start_button))
	await scene_changed
	var game := current_scene
	game.set_process(false)
	await _capture("landing")
	_expect(_visible_sites(game) == 3 and game.sites["shelter"].visible and game.state.crew.size() == 1, "Opening has shelter, two resource sites and one crew")
	_expect(game.state.inventory == {"food": 6, "tool": 1, "scrap": 0, "ore": 0, "ice": 0, "plate": 0, "circuit": 0}, "Starting supplies")
	_expect(not Save.read_game().is_empty(), "New campaign creates its first save")
	_expect(not game.state.assign("lead", "research"), "Later jobs are unavailable")

	_click(game.field.position + Vector2(300, 465), MOUSE_BUTTON_RIGHT)
	_expect(game.state.crew["lead"]["phase"] == "move", "Right click sends movement order")
	_click(_center(game.sites["wreck"]), MOUSE_BUTTON_RIGHT)
	_advance(game, 0.2)
	_expect(game.state.crew["lead"]["phase"] == "travel" and game.state.inventory["scrap"] == 0,
		"No yield in transit")
	_key(KEY_SPACE)
	_expect(game.paused, "Space pauses after right click")
	var timestamp: float = game.state.clock
	game.set_process(true)
	await process_frame
	await process_frame
	_expect(game.state.clock == timestamp, "Paused simulation stays still")
	game.set_process(false)
	_key(KEY_SPACE)
	await process_frame
	_expect(not game.paused, "Space resumes from planning pause")
	_advance(game, 10)
	_expect(game.state.inventory["scrap"] == 3, "Salvage enters inventory")
	_click(_center(game.sites["wreck"]), MOUSE_BUTTON_RIGHT)
	_advance(game, 10)
	_expect(game.state.inventory["scrap"] == 3, "Depleted wreck does not duplicate loot")

	await _drag(_center(game.crew_cards["lead"]), _center(game.sites["ore"]))
	_expect(game.state.crew["lead"]["job"] == "mine", "Dragging crew to ore issues mining order")
	_advance(game, 15)
	_expect(game.state.inventory["ore"] == 2 and game.state.recovered.size() == 2, "Both objectives complete")
	_click(_center(game.items["ore"]))
	_expect(game.detail_title.text == "矿物样本", "Inventory inspection")
	_advance(game, 400)
	_expect(game.state.inventory["food"] == 6, "Opening does not impose survival timer")

	_expect(game.sites["casualty"].visible and not game.sites["greenhouse"].visible, "Survey reveals rescue only")
	var rescue_site := _center(game.sites["casualty"])
	_click(rescue_site, MOUSE_BUTTON_RIGHT)
	_advance(game, 12)
	_expect(game.state.recruited and not game.sites["casualty"].visible, "Rescue recruits a new crew member")
	_expect(game.state.inventory["food"] == 5 and game.state.inventory["ore"] == 2, "Rescue spends food and retains survey materials")
	if not game.crew_cards.has("tech"):
		quit(1)
		return

	_click(_center(game.crew_cards["tech"]))
	await _drag(_center(game.items["scrap"]), _center(game.sites["greenhouse"]))
	_expect(game.state.crew["tech"]["job"] == "build", "Dragging scrap schedules construction for selected crew")
	_click(_center(game.crew_cards["lead"]))
	_click(_center(game.sites["ice"]), MOUSE_BUTTON_RIGHT)
	_expect(game.state.crew["lead"]["job"] == "extract", "Lead can collect ice while the other crew builds")
	_advance(game, 14)
	_expect(game.state.greenhouse_built and game.state.inventory["ice"] == 2, "Both jobs finish")
	_expect(game.state.inventory["scrap"] == 2, "Construction consumes a recovered scrap")

	await _drag(_center(game.crew_cards["tech"]), _center(game.sites["greenhouse"]))
	_expect(game.state.crew["tech"]["job"] == "grow", "Assign crew to permanent greenhouse work")
	_advance(game, 0.2)
	_expect(game.state.inventory["ice"] == 1, "Greenhouse reserves ice on arrival")
	_click(_center(game.crew_cards["tech"]))
	var stop_button := _center(game.action_button)
	_motion(stop_button)
	_mouse(stop_button, MOUSE_BUTTON_LEFT, true)
	game._refresh()
	await process_frame
	_mouse(stop_button, MOUSE_BUTTON_LEFT, false)
	_expect(game.state.inventory["ice"] == 2 and game.state.crew["tech"]["job"] == "", "Cancel refunds reserved ice")

	await _drag(_center(game.crew_cards["tech"]), _center(game.sites["greenhouse"]))
	_advance(game, 19)
	_expect(game.state.first_harvest and game.state.inventory["food"] == 11, "Two batches supply the camp")
	_expect(game.state.crew["tech"]["phase"] == "waiting" and game.state.inventory["ice"] == 0,
		"Greenhouse waits for supply without losing the assignment")
	_click(_center(game.crew_cards["lead"]))
	_click(_center(game.sites["ice"]), MOUSE_BUTTON_RIGHT)
	_advance(game, 7)
	_expect(game.state.crew["tech"]["phase"] == "working" and game.state.inventory["ice"] == 1,
		"Collecting ice automatically restarts greenhouse")
	await _capture("camp")
	await _restore_communications(game)
	await _survey_highlands(game)
	await _recover_second_record(game)
	game = await _continue_saved_game(game)
	_key(KEY_ESCAPE)
	_click(_center(game.save_button))
	var prior_save := FileAccess.get_file_as_string(Save.path)
	_click(_center(game.restart_button))
	_expect(is_instance_valid(game.replace_prompt), "Mid-campaign restart can be canceled")
	if not is_instance_valid(game.replace_prompt):
		quit(1)
		return
	_expect(root.gui_get_focus_owner() == game.replace_prompt.cancel, "Keep progress is the default")
	_click(_center(game.replace_prompt.cancel))
	await process_frame
	_expect(game.state.navigation_count() == 2 and game.paused and prior_save == FileAccess.get_file_as_string(Save.path), "Cancel keeps the running camp and on-disk progress intact")
	_key(KEY_ESCAPE)
	await process_frame
	if game.paused or is_instance_valid(game.pause_overlay):
		_expect(false, "Escape resumes gameplay after canceling a restart")
		quit(1)
		return
	await _finish_campaign(game)
	if failures > 0:
		quit(1)
		return
	game = current_scene
	_key(KEY_ESCAPE)
	_click(_center(game.restart_button))
	if not _confirm_replacement(game):
		quit(1)
		return
	await scene_changed
	game = current_scene
	_expect(game.state.recovered.is_empty() and game.state.inventory["scrap"] == 0 and _visible_sites(game) == 3 and not game.region_button.visible, "Restart resets the landing and region access")
	_key(KEY_ESCAPE)
	_click(_center(game.back_button))
	await scene_changed
	_expect(current_scene.name == "Title", "Pause menu returns to title")
	if failures == 0:
		print("PASS: fresh campaign from landing to all three records and homeward launch, flight log, save/continue and protected restart")
	DirAccess.remove_absolute(Save.path)
	quit(1 if failures else 0)


func _restore_communications(game: Control) -> void:
	var craft := "--craft" in OS.get_cmdline_user_args()
	_expect(game.sites["lab"].visible and not game.sites["beacon"].visible, "The first harvest opens new sites")
	_expect(not game.state.assign("lead", "etch"), "Circuit fabrication requires the blueprint")
	_click(_center(game.crew_cards["lead"]))
	await _drag(_center(game.items["ore"]), _center(game.sites["lab"]))
	_expect(game.state.crew["lead"]["job"] == "research", "Dragging a mineral sample starts research")
	_advance(game, 19)
	_expect(game.state.blueprint and game.sites["beacon"].visible, "Blueprint reveals the beacon")
	_expect(game.state.inventory["scrap"] == 1 and game.state.inventory["ore"] == 1,
		"Research uses the original survey materials")

	_click(_center(game.sites["wreck"]), MOUSE_BUTTON_RIGHT)
	_advance(game, 15)
	_expect(game.state.inventory["scrap"] == 4, "Deeper salvage provides materials for later jobs")
	_click(_center(game.sites["bench"]), MOUSE_BUTTON_RIGHT)
	_advance(game, 16)
	_expect(game.state.inventory["plate"] == 1, "Bench makes the first repair part. Log: " + game.log_line.text)
	if craft:
		_click(_center(game.sites["ore"]), MOUSE_BUTTON_RIGHT)
		_advance(game, 17)
		_click(_center(game.sites["bench"]))
		_expect(game.alternate_button.visible and not game.alternate_button.disabled, "Crafting is selectable after research")
		_click(_center(game.alternate_button))
		_expect(game.state.crew["lead"]["job"] == "etch", "Alternate button sends circuit order")
		_advance(game, 24)
		_expect(game.state.inventory["plate"] == 0, "Circuit uses a structure part")
		_click(_center(game.sites["bench"]), MOUSE_BUTTON_RIGHT)
		_advance(game, 17)
	else:
		var stock: int = game.state.neighbor_stock
		var supplies: int = game.state.inventory["food"]
		_click(_center(game.sites["relay"]))
		_expect(game.alternate_button.visible, "Relay lists its two offers")
		await _drag(_center(game.items["food"]), _center(game.sites["relay"]))
		_expect(game.state.crew["lead"]["job"] == "trade_food", "Dragging food sends a trade order. Log: " + game.log_line.text)
		_advance(game, 10)
		_expect(game.state.neighbor_stock < stock and game.state.inventory["food"] <= supplies - 2,
			"Trade affects both inventories")
	_expect(game.state.inventory["plate"] == 1 and game.state.inventory["circuit"] == 1,
		"Player procures both repair components")

	_click(_center(game.sites["beacon"]), MOUSE_BUTTON_RIGHT)
	_expect(game.state.crew["lead"]["job"] == "repair", "Beacon accepts repair order")
	_advance(game, 25)
	_expect(game.state.won and game.objective_title.text == "寻找归航航标", "Campaign reaches the orbital milestone")
	_expect(game.state.inventory["plate"] == 0 and game.state.inventory["circuit"] == 0, "Repair consumes both components")
	_expect(game.state.crew["tech"]["job"] == "grow", "Milestone leaves greenhouse assignment intact")
	_expect(not game.state.assign("lead", "repair") and game.state.assign("lead", "extract"),
		"Repair cannot repeat, but the camp stays playable")
	await _capture("communications")


func _survey_highlands(game: Control) -> void:
	_expect(not game.region_button.visible and not game.sites["archive"].visible, "Highlands must be visited first")
	_expect(not game.state.reason("lead", "deliver").is_empty(), "Building cargo requires a plate and circuit")
	_advance(game, 12)
	_click(_center(game.sites["beacon"]), MOUSE_BUTTON_RIGHT)
	_expect(game.state.crew["lead"]["job"] == "depart", "Repaired beacon dispatches an expedition")
	_advance(game, 23)
	_expect(game.viewed_region == "highlands" and game.crew_cards["lead"].visible, "View follows the arriving crew")
	_expect(not game.crew_cards["tech"].visible and game.state.crew_region("tech") == "camp",
		"Other crew stays at camp")
	if game.viewed_region != "highlands":
		return
	_expect(not game.state.assign("lead", "salvage"), "Crew cannot work across regions")
	_click(_center(game.sites["outpost"]), MOUSE_BUTTON_RIGHT)
	_expect(game.state.crew["lead"]["job"].is_empty(), "Outpost construction requires delivered cargo")
	_click(_center(game.sites["archive"]), MOUSE_BUTTON_RIGHT)
	_expect(game.state.crew["lead"]["job"] == "survey_archive", "Survey starts at the archive")

	_click(_center(game.region_button))
	_expect(game.viewed_region == "camp" and game.selected_crew == "tech", "Map switch selects local crew")
	game.state.stop_crew("tech")
	var prior_ice: int = game.state.inventory["ice"]
	_click(_center(game.sites["ice"]), MOUSE_BUTTON_RIGHT)
	_advance(game, 19)
	_expect(game.state.navigation_record, "Survey finishes in the background")
	_click(_center(game.region_button))
	_expect(game.state.inventory["ice"] == prior_ice + 2, "Camp crew continues gathering")
	_click(_center(game.region_button))
	_click(_center(game.sites["wreck"]), MOUSE_BUTTON_RIGHT)
	_advance(game, 16)
	_click(_center(game.sites["bench"]), MOUSE_BUTTON_RIGHT)
	_advance(game, 23)
	_click(_center(game.sites["relay"]), MOUSE_BUTTON_RIGHT)
	_advance(game, 22)
	_expect(game.state.inventory["plate"] == 1 and game.state.inventory["circuit"] == 1,
		"Camp manufactures and trades for the shipment")
	_click(_center(game.sites["beacon"]))
	_expect(game.alternate_button.visible and not game.alternate_button.disabled, "Cargo option is available")
	_click(_center(game.alternate_button))
	_advance(game, 7)
	_expect(game.state.crew["tech"]["phase"] == "working" and game.state.inventory["plate"] == 0,
		"Shipment reserves physical components before transit finishes")
	_click(_center(game.crew_buttons["tech"]))
	_click(_center(game.action_button))
	_expect(game.state.inventory["plate"] == 1 and game.state.inventory["circuit"] == 1 and not game.state.outpost_supplied,
		"Canceling shipment returns reserved cargo")

	await _drag(_center(game.items["plate"]), _center(game.sites["beacon"]))
	_expect(game.state.crew["tech"]["job"] == "deliver", "Dragging a component schedules shipment")
	_advance(game, 22)
	_expect(game.state.outpost_supplied and game.viewed_region == "highlands", "Cargo reaches the highlands with the crew")
	_expect(game.state.inventory["plate"] == 0 and game.state.inventory["circuit"] == 0,
		"Delivered components are removed from camp stock")
	_click(_center(game.sites["outpost"]), MOUSE_BUTTON_RIGHT)
	_advance(game, 23)
	_expect(game.state.outpost_built and not game.state.outpost_supplied, "Building consumes delivered cargo")
	_expect(game.state.navigation_count() == 1 and game.objective_title.text == "恢复第二份航标", "Outpost uploads the record and reveals the next objective")
	_expect(not game.state.assign("tech", "establish_outpost"), "Outpost cannot be built twice")
	await _capture("highlands")

	_click(_center(game.sites["trail"]), MOUSE_BUTTON_RIGHT)
	_advance(game, 21)
	_expect(game.viewed_region == "camp" and game.state.crew_region("tech") == "camp", "Crew returns to camp")
	_click(_center(game.region_button))
	_expect(game.sites["outpost"].visible and game.state.outpost_built, "Outpost persists when switching regions")
	_click(_center(game.crew_cards["lead"]))
	_click(_center(game.sites["trail"]), MOUSE_BUTTON_RIGHT)
	_advance(game, 19)
	_expect(game.state.crew_region("lead") == "camp", "All crew can return without another food cost. Log: " + game.log_line.text)
	_click(_center(game.region_button))
	_expect(game.selected_crew.is_empty() and game.action_button.disabled, "Empty region view does not dispatch remote crew")
	_click(_center(game.region_button))


func _recover_second_record(game: Control) -> void:
	_click(_center(game.crew_cards["lead"]))
	_expect(not game.state.reason("lead", "deliver_array").is_empty(), "Array shipment requires calibration blueprint")
	_run_job(game, "ice", "extract")
	_run_job(game, "ice", "extract")
	_run_job(game, "ice", "extract")
	_click(_center(game.crew_cards["tech"]))
	await _drag(_center(game.crew_cards["tech"]), _center(game.sites["greenhouse"]))
	_click(_center(game.crew_cards["lead"]))
	var research := "--craft" in OS.get_cmdline_user_args()
	if research:
		_stock(game, "circuit", 1)
		_stock(game, "ore", 3)
		_click(_center(game.sites["lab"]), MOUSE_BUTTON_RIGHT)
		_expect(game.state.crew["lead"]["job"] == "research_calibration", "Lab accepts new research after the first blueprint")
	else:
		_stock(game, "plate", 2)
		await _drag(_center(game.items["plate"]), _center(game.sites["relay"]))
		_expect(game.state.crew["lead"]["job"] == "exchange_calibration", "Dragging parts starts cooperation: " + game.log_line.text + " / " + game.selected_crew)
	var other := "exchange_calibration" if research else "research_calibration"
	_expect(game.state.reason("tech", other) == "另一名队员正在获取校准蓝图", "Two crew cannot buy and research the same blueprint concurrently")
	_advance(game, 75)
	_expect(game.state.calibration_blueprint and game.state.calibration_source == ("research" if research else "exchange"), "Both blueprint routes unlock the same capability")
	_expect(game.state.neighbor_parts == (0 if research else 2), "Cooperation transfers parts to the neighbor")
	_expect(not game.state.assign("lead", other), "Already acquired blueprint cannot be purchased twice")
	_expect(game.state.default_recipe("relay") == "trade_food", "Circuit trading remains available after cooperation")
	_stock(game, "circuit", 1)
	_stock(game, "plate", 2)
	_run_job(game, "ice", "extract")
	_run_job(game, "ice", "extract")
	_advance(game, 20)
	_expect(game.state.inventory["food"] >= 2, "Camp grows expedition rations")
	_click(_center(game.sites["beacon"]))
	_expect(game.alternate_button.visible and not game.alternate_button.disabled, "Second expedition offers the correct cargo")
	_click(_center(game.alternate_button))
	_advance(game, 7)
	_expect(game.state.crew["lead"]["phase"] == "working" and not game.state.array_supplied, "Array cargo stays in transit until arrival")
	var stock: Dictionary = game.state.inventory.duplicate()
	_expect(Save.write_game(game.state, game.viewed_region, game.selected_crew), "Save in transit")
	var saved := Save.read_game()
	_expect(not saved.is_empty(), "Read transit snapshot")
	if not saved.is_empty():
		var restored: RefCounted = saved["state"]
		_expect(is_equal_approx(restored.crew["lead"]["elapsed"], game.state.crew["lead"]["elapsed"]) and restored.inventory == stock,
			"Save preserves elapsed transit and deducted inventory")
		restored.stop_crew("lead")
		_expect(restored.inventory["plate"] == stock["plate"] + 2 and restored.inventory["circuit"] == stock["circuit"] + 1,
			"Cancel after loading refunds exactly the reserved components")
	_click(_center(game.crew_buttons["lead"]))
	_click(_center(game.action_button))
	_expect(game.state.inventory["plate"] == stock["plate"] + 2 and not game.state.array_supplied, "Canceled cargo never arrives")
	await _drag(_center(game.items["plate"]), _center(game.sites["beacon"]))
	_expect(game.state.crew["lead"]["job"] == "deliver_array", "Material drag selects array cargo after the outpost stage")
	_advance(game, 22)
	_expect(game.viewed_region == "highlands" and game.state.array_supplied, "Second shipment arrives at the highlands")
	_expect(game.sites["array"].visible and not game.state.assign("tech", "calibrate_array"), "Array is local to the highlands")
	_run_job(game, "array", "calibrate_array")
	_expect(game.state.array_calibrated and not game.state.array_supplied and game.state.navigation_count() == 2,
		"Calibration consumes delivered equipment and uploads a unique second record")
	_expect(game.objective_title.text == "寻找最后一份航标", "Objective leads from the second record to a playable next goal")
	game._process(0)
	var checkpoint := Save.read_game()
	_expect(not checkpoint.is_empty() and checkpoint["state"].navigation_count() == 2, "Milestone automatically saves completed records")
	_click(_center(game.sites["array"]))
	await _capture("second_record")
	_expect(not game.state.assign("lead", "calibrate_array"), "Record cannot be duplicated")
	_expect(not game.state.assign("tech", "deliver_array"), "Completed array cannot accept another shipment")
	game._process(30)
	var periodic := Save.read_game()
	_expect(not periodic.is_empty() and is_equal_approx(periodic["state"].clock, game.state.clock), "Periodic save preserves ordinary camp progress")


func _continue_saved_game(game: Control) -> Control:
	_key(KEY_ESCAPE)
	var timestamp: float = game.state.clock
	_click(_center(game.save_button))
	_expect(game.save_button.text == "进度已保存", "Pause menu saves without advancing time")
	_expect(game.state.clock == timestamp, "Saving keeps simulation paused")
	_click(_center(game.back_button))
	await scene_changed
	_expect(current_scene.continue_button.visible, "Main menu offers continue for a valid save")
	await _capture("continue_menu")
	_click(_center(current_scene.continue_button))
	await scene_changed
	var resumed := current_scene
	resumed.set_process(false)
	_expect(resumed.state.navigation_count() == 2 and resumed.viewed_region == "highlands", "Continue restores progress and viewed region")
	_expect(resumed.selected_crew == "lead" and resumed.state.crew_region("lead") == "highlands", "Continue restores selected crew and physical location")
	_expect(resumed.state.crew["tech"]["job"] == "grow", "Background greenhouse assignment survives reload")
	_run_job(resumed, "trail", "return")
	_expect(resumed.viewed_region == "camp", "Loaded expedition can return normally")
	return resumed


func _finish_campaign(game: Control) -> void:
	# Actually grow the provisions and craft the hull from the stock left by both expeditions.
	for cycle in range(12):
		_run_job(game, "ice", "extract")
		if game.state.inventory["food"] >= 25 and game.state.inventory["ice"] >= 4:
			break
	_click(_center(game.crew_buttons["tech"]))
	_click(_center(game.action_button))
	_click(_center(game.crew_buttons["lead"]))
	var survey := "--craft" in OS.get_cmdline_user_args()
	if survey:
		_stock(game, "ore", 2)
		_run_job(game, "beacon", "depart")
		_run_job(game, "array", "survey_last_record")
		_run_job(game, "trail", "return")
	else:
		_stock(game, "circuit", 1)
		_stock(game, "plate", 2)
		if not _start_finale_action(game, "relay", "exchange_last_record"):
			return
		_wait_finale_job(game, "exchange_last_record")
	_expect(game.state.navigation_count() == 3 and game.state.third_record_source == ("survey" if survey else "exchange"), "Both final record routes complete through map controls")
	_stock(game, "circuit", 2)
	_stock(game, "plate", 3)
	if not _start_finale_action(game, "wreck", "assemble_return_craft"):
		return
	_wait_finale_job(game, "assemble_return_craft")
	_expect(game.state.return_craft_ready and not game.state.homeward_launched, "Assembly leaves final departure to the player")
	while game.state.inventory["ice"] < 4:
		_run_job(game, "ice", "extract")
		if failures > 0:
			return
	for batch in range(5):
		if game.state.inventory["food"] >= 5:
			break
		_run_job(game, "greenhouse", "grow")
		if game.state.inventory["ice"] < 3:
			_run_job(game, "ice", "extract")
	if not _start_finale_action(game, "beacon", "launch_homeward"):
		return
	_wait_finale_job(game, "launch_homeward")
	_expect(game.state.homeward_launched and is_instance_valid(game.flight_log), "A distinct flight log appears after launch")
	if not is_instance_valid(game.flight_log):
		return
	var elapsed: float = game.state.clock
	game._process(6)
	_expect(game.state.clock == elapsed, "The terminal report freezes simulation time")
	if DisplayServer.get_name() != "headless" and not OS.get_cmdline_user_args().is_empty():
		await create_timer(3.0).timeout
	await _capture("homeward_flight_log")
	_click(_center(game.flight_log.menu_button))
	await scene_changed
	_expect(current_scene.continue_button.text == "查看归航记录", "Main menu recognizes a completed campaign")
	_click(_center(current_scene.continue_button))
	await scene_changed
	var finished := current_scene
	_expect(finished.state.homeward_launched and finished.state.third_record_source == ("survey" if survey else "exchange") and is_equal_approx(finished.state.clock, elapsed) and is_instance_valid(finished.flight_log), "Recorded journey reopens with the same route and time")
	if not is_instance_valid(finished.flight_log):
		return
	_click(_center(finished.flight_log.menu_button))
	await scene_changed
	var title := current_scene
	_click(_center(title.start_button))
	_expect(is_instance_valid(title.replace_prompt), "Starting over first asks to replace the finished campaign")
	_key(KEY_ESCAPE)
	await process_frame
	_expect(not is_instance_valid(title.replace_prompt) and Save.read_game()["state"].homeward_launched, "Cancel preserves the full flight log")
	_click(_center(title.start_button))
	if not _confirm_replacement(title):
		return
	await scene_changed
	_expect(current_scene.state.navigation_count() == 0 and not current_scene.state.homeward_launched, "Confirmed new game starts a fresh campaign")


func _confirm_replacement(scene: Control) -> bool:
	_expect(is_instance_valid(scene.replace_prompt), "Replacement requires an explicit button")
	if not is_instance_valid(scene.replace_prompt):
		return false
	_expect(root.gui_get_focus_owner() == scene.replace_prompt.cancel, "Default keyboard focus protects the existing save")
	_click(_center(scene.replace_prompt.confirm))
	return true


func _start_finale_action(game: Control, site: String, recipe: String) -> bool:
	var at := _center(game.sites[site])
	_motion(at)
	_mouse(at, MOUSE_BUTTON_RIGHT, true)
	_mouse(at, MOUSE_BUTTON_RIGHT, false)
	var action: Button = game.context_buttons.get(recipe)
	_expect(is_instance_valid(game.context_overlay) and is_instance_valid(action), "Map menu offers " + recipe)
	if not is_instance_valid(action) or not is_instance_valid(game.context_overlay):
		return false
	_expect(not action.disabled, "Finale supplies and crew meet " + recipe + ": " + action.tooltip_text)
	if action.disabled:
		return false
	_click(_center(action))
	_expect(game.state.crew["lead"]["job"] == recipe, "Explicit map action starts " + recipe)
	return game.state.crew["lead"]["job"] == recipe


func _wait_finale_job(game: Control, recipe: String) -> void:
	for step in range(100):
		_advance(game, 1)
		if game.state.crew["lead"]["job"] != recipe:
			return
	_expect(false, "Finale work timed out: " + recipe)


func _stock(game: Control, item: String, minimum: int) -> void:
	for attempt in range(15):
		if game.state.inventory[item] >= minimum:
			return
		match item:
			"plate":
				_stock(game, "scrap", 2)
				_run_job(game, "bench", "fabricate")
			"circuit":
				_stock(game, "ore", 2)
				_stock(game, "plate", 1)
				_click(_center(game.sites["bench"]))
				_click(_center(game.alternate_button))
				_expect(game.state.crew["lead"]["job"] == "etch", "Manufacture circuit for second expedition")
				_advance(game, 45)
			"scrap": _run_job(game, "wreck", "salvage")
			"ore": _run_job(game, "ore", "mine")
	_expect(false, "Could not obtain " + item)


func _run_job(game: Control, site: String, recipe: String) -> void:
	_click(_center(game.sites[site]), MOUSE_BUTTON_RIGHT)
	_expect(game.state.crew[game.selected_crew]["job"] == recipe, "Start " + recipe + ": " + game.log_line.text)
	for step in range(100):
		_advance(game, 1.0)
		if game.state.crew[game.selected_crew]["job"].is_empty():
			return
	_expect(false, "Job timed out: " + recipe)


func _visible_sites(game: Control) -> int:
	var count := 0
	for card in game.sites.values():
		if card.visible:
			count += 1
	return count


func _capture(name: String) -> void:
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() == "headless" or args.is_empty() or args[0].begins_with("--"):
		return
	await RenderingServer.frame_post_draw
	_expect(root.get_texture().get_image().save_png(args[0].path_join(name + ".png")) == OK, "Capture " + name)


func _center(control: Control) -> Vector2:
	return control.get_global_rect().get_center()


func _advance(game: Control, seconds: float) -> void:
	for i in range(roundi(seconds * 20.0)):
		game.state.tick(0.05)
	game._refresh()


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event, true)


func _click(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	_motion(at)
	_mouse(at, button, true)
	_mouse(at, button, false)
	# Existing campaign routes now choose the primary task through the board menu.
	if button == MOUSE_BUTTON_RIGHT and current_scene.has_method("_close_context") and is_instance_valid(current_scene.context_overlay):
		var primary: Button = current_scene.context_buttons.values()[0]
		if primary.disabled:
			current_scene._close_context()
		else:
			_click(_center(primary))


func _drag(from: Vector2, to: Vector2) -> void:
	_motion(from)
	_mouse(from, MOUSE_BUTTON_LEFT, true)
	_motion(from.lerp(to, 0.20), MOUSE_BUTTON_MASK_LEFT)
	await process_frame
	_motion(to, MOUSE_BUTTON_MASK_LEFT)
	await process_frame
	_mouse(to, MOUSE_BUTTON_LEFT, false)


func _motion(at: Vector2, mask: int = 0) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = at - pointer
	event.button_mask = mask
	pointer = at
	root.push_input(event, true)


func _mouse(at: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = button
	event.pressed = pressed
	event.button_mask = (1 << (button - 1)) if pressed else 0
	root.push_input(event, true)


func _expect(ok: bool, condition: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + condition)
