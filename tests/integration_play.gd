extends "res://tests/frontier_play.gd"


func _play() -> void:
	Save.path = "/private/tmp/starfire-integration-%d.json" % OS.get_process_id()
	change_scene_to_file("res://scenes/title.tscn")
	await scene_changed
	if "--compact" in OS.get_cmdline_user_args():
		root.size = Vector2i(960, 640)
		await process_frame
	_click(_center(current_scene.help_button))
	await _capture("integrated_controls")
	_key(KEY_ESCAPE)
	await process_frame
	_click(_center(current_scene.start_button))
	await scene_changed
	var game := current_scene
	game.set_process(false)
	game.feedback.sound_enabled = false
	var opening_stock: Dictionary = game.state.inventory.duplicate()
	_click(_center(game.goal_button))
	_expect(game.paused and game.context_buttons.has("salvage") and game.state.inventory == opening_stock,
		"Goal locates an actual worksite without assigning or spending")
	_click(_center(game.context_buttons["salvage"]))
	_advance(game, 18)
	_run_job(game, "ore", "mine")
	_click(_center(game.goal_button))
	_click(_center(game.context_buttons["rescue"]))
	_advance(game, 16)
	_expect(game.crew_buttons["tech"].visible, "Rescued crew immediately joins the persistent roster")
	_click(_center(game.crew_buttons["tech"]))
	await _drag(_center(game.sites["greenhouse"]), game.MAP_POS + Vector2(176, 288))
	_expect(game.state.site_position("greenhouse") == Vector2(176, 288), "Integrated camp uses a player-placed greenhouse")
	_run_job(game, "greenhouse", "build")
	await _drag(_center(game.crew_cards["tech"]), _center(game.sites["greenhouse"]))
	_advance(game, 8)
	_expect("缺水" in game.goal_button.text, "Waiting greenhouse offers an actionable water reminder")
	_click(_center(game.crew_buttons["lead"]))
	_click(_center(game.goal_button))
	_expect(game.context_buttons.has("extract"), "Water reminder opens the ice worksite")
	_click(_center(game.context_buttons["extract"]))
	_advance(game, 24)
	_expect(game.state.first_harvest and game.objective_title.text == "恢复轨道通信", "First harvest connects to the main objective without imposing optional upgrades")
	for id in game.state.crew:
		for site in ["bench", "lab", "relay"]:
			_expect(not game.crew_cards[id].get_rect().intersects(game.sites[site].get_rect()), "Newly revealed facilities do not hide " + id)
	_run_job(game, "ice", "extract")
	await _choose_order(game, "extract", 2, 6)
	_click(_center(game.scout_button))
	_click(_center(game.expedition_buttons["scout_blueprint"]))
	_advance_until_away(game)
	_advance(game, 2)
	_click(_center(game.crew_buttons["lead"]))
	_expect(not game.crew_cards["lead"].visible and game.focus == "lead" and game.alternate_button.disabled and game.orders_button.disabled,
		"Roster selects a deployed worker and prevents camp-only work")
	await create_timer(1.4).timeout
	await _capture("integrated_expedition")
	game = await _save_reload(game)
	_expect(game.focus == "lead" and game.state.crew_away("lead"), "Continue restores the selected explorer's actual status")
	var paid: int = game.state.crew["lead"]["reserved"]["food"]
	var food: int = game.state.inventory["food"]
	_click(_center(game.action_button))
	_expect(game.state.inventory["food"] == food + paid and game.state.crew["lead"]["duty"].get("recipe") == "extract" and game.state.crew["lead"]["job"] == "extract",
		"Roster recall refunds the trip and resumes its saved gathering duty")
	_click(_center(game.scout_button))
	_click(_center(game.expedition_buttons["scout_blueprint"]))
	_finish_trip(game, "scout_blueprint")
	_click(_center(game.crew_buttons["lead"]))
	_click(_center(game.action_button))
	var at := _center(game.sites["lab"])
	_motion(at)
	_mouse(at, MOUSE_BUTTON_RIGHT, true)
	_mouse(at, MOUSE_BUTTON_RIGHT, false)
	_expect(game.context_buttons.has("research") and game.context_buttons.has("research_pump") and game.context_buttons.has("trial_sampler"),
		"Exploration blueprint coexists with communication and pump research")
	await _capture("integrated_research")
	_key(KEY_ESCAPE)
	await _choose_order(game, "research_pump", 3, 1, "integrated_orders")
	_advance(game, 24)
	_expect(game.state.pump_blueprint and not game.state.expeditions.sampler_built, "Unified orders can perform another research branch first")
	_run_job(game, "ore", "mine")
	_stock(game, "scrap", 4)
	_run_job(game, "lab", "research")
	_run_job(game, "relay", "trade_food")
	await _drag(_center(game.items["scrap"]), _center(game.sites["lab"]))
	_expect(game.state.crew["lead"]["job"] == "trial_sampler", "Material drop skips completed communication research and starts the available prototype")
	_advance(game, 24)
	_expect(game.state.expeditions.sampler_built, "Found blueprint becomes an operating tool")
	var ore: int = game.state.inventory["ore"]
	_run_job(game, "ore", "mine")
	_expect(game.state.inventory["ore"] == ore + 3, "Integrated tool changes gathering yield")
	_stock(game, "plate", 1)
	_run_job(game, "relay", "trade_food")
	await _choose_order(game, "repair", 3, 1)
	_advance(game, 24)
	_expect(game.state.won and not game.state.botanist_joined and not game.state.power.solar_built,
		"Communication is reachable with exploration while population and power remain optional")
	_run_job(game, "beacon", "depart")
	_expect(game.viewed_region == "highlands" and "高地" in game.crew_buttons["lead"].text, "Roster reflects actual arrival in the other region")
	await _choose_order(game, "survey_archive", 3, 1)
	_advance(game, 24)
	_expect(game.state.navigation_record, "Unified work menu also performs highland field tasks")
	_click(_center(game.crew_buttons["tech"]))
	_expect(game.viewed_region == "camp" and game.selected_crew == "tech", "Roster locates the remaining camp worker without moving either person")
	_click(_center(game.crew_buttons["lead"]))
	await _choose_order(game, "return", 3, 1)
	_advance(game, 22)
	_expect(game.viewed_region == "camp" and game.state.crew_region("lead") == "camp", "Field orders can bring the explorer back")
	_click(_center(game.goal_button))
	_expect(game.context_buttons.has("extract"), "Camp shortage after a long field trip routes back to water supply")
	_click(_center(game.context_buttons["extract"]))
	_advance(game, 24)
	await _choose_order(game, "extract", 2, 6)
	_click(_center(game.crew_buttons["tech"]))
	await _choose_order(game, "grow", 2, 15)
	_advance(game, 90)
	_expect(game.state.inventory["food"] >= 3 and game.state.inventory["ice"] > 0,
		"Returning crew can restore both supply chains after depleting camp food")
	_click(_center(game.sites["greenhouse"]))
	await create_timer(1.4).timeout
	await _capture("integrated_camp")
	_expect(Save.write_game(game.state, "camp", "lead") and not Save.read_game().is_empty(), "Integrated layout, discoveries, upgrades and mainline progress save together")
	DirAccess.remove_absolute(Save.path)
	if failures == 0:
		print("PASS: integrated opening, relocated camp, supply guidance, crew roster, recall/duty, combined research, material routing, field orders, optional progression and save")
	quit(1 if failures else 0)


func _choose_order(game: Control, recipe: String, mode: int, amount: int, capture: String = "") -> void:
	_click(_center(game.orders_button))
	_expect(is_instance_valid(game.orders_overlay), "Open unified work menu for " + recipe)
	if not is_instance_valid(game.orders_overlay):
		return
	var index: int = game._order_recipes.find(recipe)
	_expect(index >= 0, "Unified catalogue exposes " + recipe)
	if index < 0:
		_key(KEY_ESCAPE)
		return
	game.order_recipe.select(index)
	game.order_recipe.item_selected.emit(index)
	game.order_mode.select(mode)
	game.order_mode.item_selected.emit(mode)
	game.order_amount.value = amount
	await process_frame
	_expect(game.orders_overlay.is_ancestor_of(root.gui_get_focus_owner()), "Keyboard focus remains in the work menu")
	_key(KEY_TAB)
	await process_frame
	_expect(game.orders_overlay.is_ancestor_of(root.gui_get_focus_owner()), "Tab stays within the work menu")
	if mode in [1, 2]:
		for step in range(8):
			if root.gui_get_focus_owner() == game.order_amount.get_line_edit():
				break
			_key(KEY_TAB)
			await process_frame
		_expect(root.gui_get_focus_owner() == game.order_amount.get_line_edit(), "Keyboard can reach the enabled stock or batch amount")
	_expect(not game.order_confirm.disabled, "Selected work is executable: " + game.order_feedback.text)
	if not capture.is_empty():
		await _capture(capture)
	_click(_center(game.order_confirm))
	_expect(not is_instance_valid(game.orders_overlay), "Confirm actual work " + recipe)
