extends "res://tests/opening_flow.gd"


func _play() -> void:
	Save.path = "/private/tmp/starfire-camp-life-%d.json" % OS.get_process_id()
	change_scene_to_file("res://scenes/title.tscn")
	await scene_changed
	_click(_center(current_scene.start_button))
	await scene_changed
	var game := current_scene
	game.set_process(false)
	_run_job(game, "wreck", "salvage")
	_run_job(game, "ore", "mine")
	_run_job(game, "casualty", "rescue")
	_click(_center(game.crew_cards["lead"]))
	_run_job(game, "shelter", "expand_shelter")
	_expect(game.state.beds() == 3 and not game.state.assign("lead", "welcome_botanist"), "Housing alone is insufficient to recruit the agronomist")
	_click(_center(game.crew_cards["tech"]))
	_run_job(game, "greenhouse", "build")
	_click(_center(game.crew_cards["lead"]))
	_run_job(game, "ice", "extract")
	_run_job(game, "ice", "extract")
	await _drag(_center(game.crew_cards["tech"]), _center(game.sites["greenhouse"]))
	_advance(game, 15)
	_expect(game.state.first_harvest and game.state.crew["tech"]["duty"]["recipe"] == "grow", "Dragging creates a lasting greenhouse duty")
	_click(_center(game.crew_cards["lead"]))
	await _set_work(game, "extract", 2, 6)
	_advance(game, 45)
	_expect(game.state.inventory["ice"] >= 4 and game.state.crew["lead"]["duty"]["mode"] == "stock", "Supply work keeps water available as the greenhouse consumes it")
	_click(_center(game.crew_cards["tech"]))
	_click(_center(game.sites["wreck"]), MOUSE_BUTTON_RIGHT)
	_expect(game.state.crew["tech"]["job"] == "salvage" and game.state.crew["tech"]["duty"]["recipe"] == "grow", "Temporary salvage preserves greenhouse duty")
	_advance(game, 20)
	_expect(game.state.crew["tech"]["job"] == "grow", "Worker automatically returns to the greenhouse")
	game.state.stop_crew("lead")
	_click(_center(game.crew_cards["lead"]))
	_run_job(game, "lab", "research")
	if "--craft" in OS.get_cmdline_user_args():
		_stock(game, "ore", 2)
		_stock(game, "scrap", 1)
		_click(_center(game.sites["lab"]))
		_click(_center(game.alternate_button))
		_expect(game.state.crew["lead"]["job"] == "research_pump", "Player can recover pump technology without trading")
		_advance(game, 35)
	else:
		_run_job(game, "relay", "trade_food")
		_expect(game.state.neighbor_trades == 1, "First trade reaches both teams")
	_expect(game.state.pump_blueprint and not game.state.pump_built and game.state.production_output("grow")["food"] == 3,
		"Blueprint acquisition does not automatically grant the production upgrade")
	_stock(game, "circuit", 1)
	_stock(game, "plate", 1)
	_run_job(game, "ice", "extract")
	_click(_center(game.crew_cards["tech"]))
	_click(_center(game.sites["greenhouse"]))
	_click(_center(game.alternate_button))
	_expect(game.state.crew["tech"]["job"] == "trial_pump", "Existing grower can pause their duty to prototype the pump")
	_advance(game, 20)
	_expect(game.state.pump_built and game.state.production_output("grow")["food"] == 5, "Prototype consumes materials and improves food per ice")
	_expect(game.state.crew["tech"]["job"] == "grow", "Grower resumes after successful prototype")
	_click(_center(game.crew_cards["lead"]))
	_run_job(game, "shelter", "welcome_botanist")
	_expect(game.state.crew.size() == 3 and game.state.botanist_joined and game.crew_cards.has("botanist"), "Agronomist joins the playable map: " + game.log_line.text)
	if not game.state.botanist_joined:
		quit(1)
		return
	_expect(not game.state.assign("lead", "welcome_botanist"), "Recruitment cannot duplicate crew")
	game.state.stop_crew("tech")
	_stock(game, "scrap", 8)
	_click(_center(game.crew_cards["botanist"]))
	await _set_work(game, "grow", 2, 15)
	_click(_center(game.crew_cards["lead"]))
	await _set_work(game, "extract", 2, 6)
	_click(_center(game.crew_cards["tech"]))
	await _set_work(game, "fabricate", 1, 3)
	var plate_before: int = game.state.inventory["plate"]
	_advance(game, 45)
	_expect(game.state.inventory["plate"] == plate_before + 3 and game.state.crew["tech"]["duty"].is_empty(), "Batch order makes exactly three batches and ends")
	_expect(game.state.inventory["food"] >= 15 and game.state.crew["botanist"]["phase"] == "waiting", "Agronomist waits once food meets stock target")
	_expect(game.state.crew["lead"]["duty"]["recipe"] == "extract", "Independent water supply duty remains")
	var farmer_food: int = game.state.inventory["food"]
	_advance(game, 70)
	_expect(game.state.inventory["food"] >= 15 and game.state.inventory["food"] <= farmer_food + 5, "Target orders replenish consumed food without unbounded overproduction")
	_click(_center(game.crew_cards["tech"]))
	await _capture("camp_life")
	await _set_work(game, "fabricate", 1, 2)
	_advance(game, 35)
	_expect(game.state.crew["tech"]["phase"] == "waiting" and "残件" in game.state.activity("tech"), "Material shortage keeps batch order and reports the missing input")
	game.state.stop_crew("lead")
	_click(_center(game.crew_cards["lead"]))
	_run_job(game, "wreck", "salvage")
	_advance(game, 20)
	_expect(game.state.crew["tech"]["duty"].is_empty(), "Supplying scrap finishes the remaining batch")
	_key(KEY_SPACE)
	var clock_before: float = game.state.clock
	_click(_center(game.sites["ore"]), MOUSE_BUTTON_RIGHT)
	_expect(game.state.crew["lead"]["job"] == "mine", "Orders can be given while time is paused")
	game._process(5)
	_expect(game.state.clock == clock_before, "Planning pause does not advance work")
	_key(KEY_SPACE)
	_advance(game, 20)
	_expect(game.state.inventory["ore"] >= 2, "Planned task proceeds after resume")
	await _neighbor_upgrade(game)
	_click(_center(game.crew_cards["botanist"]))
	_click(_center(game.alternate_button))
	_expect(game.state.crew["botanist"]["phase"] == "resting", "Crew can rest while retaining their job")
	var health: float = game.state.crew["botanist"]["health"]
	_expect(game._save_game(), "Save camp duties and resting crew")
	var saved := Save.read_game()
	_expect(not saved.is_empty(), "Read expanded camp save")
	if not saved.is_empty():
		var restored: RefCounted = saved["state"]
		_expect(restored.crew.size() == 3 and restored.pump_built and restored.neighbor_upgraded, "Load preserves camp and neighbor development")
		_expect(restored.crew["botanist"]["duty"] == game.state.crew["botanist"]["duty"], "Resting worker keeps stock policy through save")
		for i in range(1000):
			restored.tick(0.05)
		_expect(restored.crew["botanist"]["health"] >= health and restored.crew["botanist"]["job"] == "grow", "Rested worker resumes after loading")
	await _after_camp(game)
	DirAccess.remove_absolute(Save.path)
	if failures == 0:
		print("PASS: shelter, specialties, pump blueprint/prototype, recruitment, duties, batch/stock orders, pause planning and neighbor growth")
	quit(1 if failures else 0)


func _after_camp(_game: Control) -> void:
	pass


func _set_work(game: Control, recipe: String, mode: int, amount: int) -> void:
	_click(_center(game.orders_button))
	_expect(is_instance_valid(game.orders_overlay), "Open work assignment dialog")
	if not is_instance_valid(game.orders_overlay):
		return
	game.order_recipe.select(game._order_recipes.find(recipe))
	game.order_mode.select(mode)
	game.order_mode.item_selected.emit(mode)
	game.order_amount.value = amount
	await _capture("production_orders")
	_click(_center(game.order_confirm))
	await process_frame
	_expect(not is_instance_valid(game.orders_overlay), "Confirm work order " + game.selected_crew + "/" + recipe + ": " + game.log_line.text)
	if is_instance_valid(game.orders_overlay):
		game._close_orders()
		await process_frame


func _neighbor_upgrade(game: Control) -> void:
	_click(_center(game.crew_cards["lead"]))
	_stock(game, "scrap", 6)
	_click(_center(game.sites["relay"]))
	_click(_center(game.alternate_button))
	_advance(game, 25)
	_run_job(game, "relay", "trade_food")
	_advance(game, 1)
	_expect(game.state.neighbor_upgraded and game.state.neighbor_interval() == 20.0, "Partner spends real stock to expand after trade")
	_click(_center(game.sites["relay"]))
	await _capture("neighbor_development")
