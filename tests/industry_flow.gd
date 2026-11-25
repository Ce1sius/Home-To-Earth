extends "res://tests/camp_life.gd"


func _after_camp(game: Control) -> void:
	for id in game.state.crew:
		game.state.stop_crew(id)
	game._refresh()
	_click(_center(game.crew_cards["lead"]))
	_expect(not game.state.assign("lead", "build_solar"), "Solar construction requires an energy blueprint")
	var research := "--craft" in OS.get_cmdline_user_args()
	var recipe := "research_power" if research else "trade_power"
	if research:
		_stock(game, "ore", 2)
		_stock(game, "circuit", 1)
	else:
		_stock(game, "plate", 1)
	var prior_parts: int = game.state.neighbor_parts
	await _engineering(game, recipe)
	var other := "trade_power" if research else "research_power"
	_expect(game.state.reason("tech", other) == "另一名队员正在获取能源蓝图", "Energy blueprint routes cannot duplicate a concurrent purchase")
	_finish_job(game)
	_expect(game.state.power.blueprint, "Both research and trade unlock energy construction")
	_expect(game.state.neighbor_parts == prior_parts + (0 if research else 1), "Blueprint trade transfers its structure part to the partner")
	_expect(not game.state.assign("lead", other), "Energy blueprint cannot be bought twice")
	_stock(game, "plate", 2)
	_stock(game, "circuit", 1)
	_click(_center(game.sites["wreck"]))
	_click(_center(game.alternate_button))
	_advance(game, 7)
	_expect(game.state.crew["lead"]["job"] == "build_solar" and not game.state.power.solar_built, "Solar assembly remains a physical timed job")
	var reserved: Dictionary = game.state.crew["lead"]["reserved"].duplicate()
	var plates: int = game.state.inventory["plate"]
	_click(_center(game.crew_cards["lead"]))
	_click(_center(game.action_button))
	_expect(game.state.inventory["plate"] == plates + reserved.get("plate", 0) and not game.state.power.solar_built, "Canceled construction refunds reserved parts without granting power")
	await _engineering(game, "build_solar")
	_finish_job(game)
	_expect(game.state.power.solar_built and game.energy_label.visible, "Completed solar assembly enables power status")
	_expect(not game.state.assign("lead", "build_solar"), "Solar construction cannot repeat")
	_stock(game, "circuit", 1)
	_stock(game, "plate", 2)
	_click(_center(game.sites["ice"]))
	_click(_center(game.alternate_button))
	_expect(game.state.crew["lead"]["job"] == "build_extractor", "Ice site offers machine assembly")
	_finish_job(game)
	_expect(game.state.power.extractor_built and game.auto_button.visible, "Extractor built and controls visible")
	_click(_center(game.crew_cards["botanist"]))
	await _set_work(game, "grow", 1, 5)
	_click(_center(game.crew_cards["lead"]))
	_run_job(game, "ore", "mine")
	_advance(game, 45)
	_expect(game.state.active_at("ice").is_empty() and game.state.power.condition < 100, "Machine supplies ice while crew work elsewhere")
	_expect(game.state.inventory["ice"] > 0 and game.state.power.energy >= 0 and game.state.power.energy <= 40, "Automatic production spends finite power")
	_click(_center(game.sites["ice"]))
	await _capture("automation")
	for second in range(241):
		if game.state.power.weather_stage() == "warning":
			break
		_advance(game, 1)
	_expect(game.state.power.weather_stage() == "warning" and "沙尘预警" in game.energy_label.text, "Forecast is visible before the dust storm")
	await _capture("dust_warning")
	_advance(game, 30)
	_expect(game.state.power.weather_stage() == "storm" and game.state.power.cleanliness < 75, "Dust event reduces solar cleanliness")
	_click(_center(game.sites["wreck"]))
	await _capture("dust_storm")
	_advance(game, 32)
	_stock(game, "scrap", 2)
	await _engineering(game, "clean_solar")
	_finish_job(game)
	_expect(game.state.power.cleanliness > 99, "Crew can restore solar cleanliness after weather event")
	_key(KEY_SPACE)
	var time_before: float = game.state.power.time
	_click(_center(game.auto_button))
	game._process(5)
	_expect(not game.state.power.extractor_enabled and game.state.power.time == time_before, "Planning pause allows equipment control without advancing power time")
	_key(KEY_SPACE)
	await _engineering(game, "service_extractor")
	_finish_job(game)
	_expect(game.state.power.condition == 100, "Maintenance restores the paused machine")
	var progress_before: float = game.state.power.progress
	_key(KEY_ESCAPE)
	_click(_center(game.save_button))
	_expect(game.save_button.text == "进度已保存", "Save new industrial state")
	_click(_center(game.back_button))
	await scene_changed
	_expect(current_scene.continue_button.visible, "Saved industrial campaign is offered in the menu")
	_click(_center(current_scene.continue_button))
	await scene_changed
	game = current_scene
	game.set_process(false)
	_expect(game.state.power.extractor_built and not game.state.power.extractor_enabled, "Continue restores equipment and paused switch")
	_expect(is_equal_approx(game.state.power.progress, progress_before), "Continue preserves partial machine batch")
	_click(_center(game.auto_button))
	_expect(game.state.power.extractor_enabled, "Loaded equipment can resume normally")
	if failures == 0:
		print("PASS: energy blueprint routes, solar assembly, automatic ice, weather, maintenance and menu save/continue")


func _engineering(game: Control, recipe: String) -> void:
	_click(_center(game.orders_button))
	var index: int = game._order_recipes.find(recipe)
	_expect(index >= 0, "Engineering task is available: " + recipe)
	if index < 0:
		game._close_orders()
		await process_frame
		return
	game.order_recipe.select(index)
	game.order_recipe.item_selected.emit(index)
	_expect(game.order_mode.selected == 3 and game.order_mode.disabled, "Engineering task uses a single job rather than a repeat order")
	_click(_center(game.order_confirm))
	await process_frame
	_expect(not is_instance_valid(game.orders_overlay), "Engineering order accepted: " + game.log_line.text)
	if is_instance_valid(game.orders_overlay):
		game._close_orders()
		await process_frame


func _finish_job(game: Control) -> void:
	for second in range(100):
		_advance(game, 1)
		if game.state.crew[game.selected_crew]["job"].is_empty():
			return
	_expect(false, "Engineering job did not finish")
