extends "res://tests/save_roundtrip.gd"


func _initialize() -> void:
	Save.path = "/private/tmp/starfire-homeward-%d.json" % OS.get_process_id()
	_expect(_third_record_routes(), "Both routes reach settlement")
	_expect(_craft_and_launch(), "Craft and launch checks reach the end")
	_expect(_old_save_and_validation(), "Migration and validation checks reach the end")
	DirAccess.remove_absolute(Save.path)
	if failures == 0:
		print("PASS: exclusive final records, homeward readiness, crew restrictions, refund, end-state reload and version 5 migration")
	quit(1 if failures else 0)


func _ready_camp() -> RefCounted:
	var state := _later_campaign()
	state.array_calibrated = true
	state.inventory.merge({"food": 20, "ore": 6, "ice": 6, "plate": 8, "circuit": 6}, true)
	state.crew["tech"]["region"] = State.HIGHLANDS
	state.crew["tech"]["pos"] = Vector2(335, 310)
	state.crew["tech"]["dest"] = state.crew["tech"]["pos"]
	return state


func _third_record_routes() -> bool:
	var early := _later_campaign()
	_expect(not early.assign("lead", "exchange_last_record"), "Two records are required to seek the last one")
	for route in ["exchange", "survey"]:
		var state := _ready_camp()
		var worker := "tech" if route == "survey" else "lead"
		var recipe := str(route) + "_last_record"
		var other := "lead" if route == "survey" else "tech"
		var other_recipe := "exchange_last_record" if route == "survey" else "survey_last_record"
		_expect(not state.assign("lead", "assemble_return_craft"), "Cannot assemble before all three records")
		var stock: Dictionary = state.inventory.duplicate()
		_expect(state.assign(worker, recipe), "Can commit to " + recipe)
		_expect(not state.assign(other, other_recipe), "Remote partner cannot commit to second route simultaneously")
		_advance(state, 8)
		_expect(state.crew[worker]["phase"] == "working", "Final record has real travel and work")
		state.stop_crew(worker)
		_expect(state.inventory == stock and state.navigation_count() == 2, "Cancel returns investment and leaves both paths open")
		_expect(state.assign(worker, recipe), "Canceled route may be chosen again")
		_advance(state, 3)
		_expect(Save.write_game(state, state.crew_region(worker), worker), "Save final record in flight")
		var loaded := Save.read_game()
		if loaded.is_empty():
			return false
		state = loaded["state"]
		_advance(state, 40)
		_expect(state.navigation_count() == 3 and state.third_record_source == route, "Loaded route produces exactly its final record")
		_expect(not state.assign(other, other_recipe), "Alternative no longer grants a record")
		for item in State.ITEMS:
			_expect(state.inventory[item] == stock[item] - State.RECIPES[recipe]["cost"].get(item, 0), "One cost after load: " + item)
	return true


func _craft_and_launch() -> bool:
	var state := _ready_camp()
	state.third_record_source = "survey"
	_expect(not state.assign("lead", "launch_homeward"), "Assemble before launch")
	_expect(state.assign("lead", "assemble_return_craft"), "Start assembly")
	_advance(state, 9)
	var paid: Dictionary = state.crew["lead"]["reserved"].duplicate()
	_expect(paid == {"plate": 3, "circuit": 2}, "Assembly reserves its actual inputs")
	state.stop_crew("lead")
	_expect(state.inventory["plate"] == 8 and state.inventory["circuit"] == 6 and not state.return_craft_ready, "Cancel assembly grants no craft")
	state.assign("lead", "assemble_return_craft")
	_advance(state, 32)
	_expect(state.return_craft_ready and not state.homeward_launched, "Craft readiness is a separate achievement")
	_expect(state.default_recipe("beacon") != "launch_homeward" and state.recipe_for_material("beacon", "ice", "lead") != "launch_homeward", "Default drag and material drop do not end a run")
	state.assign("tech", "return")
	_advance(state, 20)
	_expect(state.crew_region("tech") == State.CAMP and not state.assign("tech", "launch_homeward"), "Only the leader can launch even with crew on site")
	_expect(state.set_order("lead", "mine", "stock", 6), "Leader has a preflight duty")
	_expect(state.assign("lead", "launch_homeward"), "Explicit final action is available")
	_advance(state, 6)
	_expect(state.crew["lead"]["reserved"] == {"food": 3, "ice": 2}, "Supplies reserved for a launch in progress")
	_expect(Save.write_game(state, State.CAMP, "lead"), "Save before final departure")
	var loaded := Save.read_game()
	if loaded.is_empty():
		return false
	state = loaded["state"]
	_advance(state, 20)
	_expect(state.homeward_launched and state.crew["lead"]["job"].is_empty() and state.crew["lead"]["duty"].is_empty(), "Final departure consumes the cargo and releases the leader")
	_expect(Save.write_game(state, State.CAMP, "lead"), "Save final state")
	loaded = Save.read_game()
	if loaded.is_empty():
		return false
	state = loaded["state"]
	var finished := Save._encode(state)
	_expect(not state.assign("lead", "launch_homeward"), "No repeated launch after continue")
	state.rest_crew("tech")
	state.move_crew("lead", Vector2(630, 340))
	_advance(state, 95)
	_expect(Save._encode(state) == finished, "Final campaign and result remain stable after reopening")
	return true


func _old_save_and_validation() -> bool:
	var state := _ready_camp()
	var data: Dictionary = Save._encode(state)
	for key in ["third_record_source", "return_craft_ready", "homeward_launched"]:
		data.erase(key)
	_write_text(JSON.stringify({"state": data, "version": 5, "region": State.CAMP, "selected": "lead"}))
	var loaded := Save.read_game()
	if loaded.is_empty():
		return false
	state = loaded["state"]
	_expect(state.navigation_count() == 2 and state.array_calibrated and not state.return_craft_ready, "Old saved second record opens both new routes")
	data = Save._encode(state)
	for change in [{"homeward_launched": true}, {"return_craft_ready": true}, {"third_record_source": "invalid"}, {"third_record_source": "survey", "array_calibrated": false}]:
		var invalid := data.duplicate(true)
		invalid.merge(change, true)
		_expect(Save._decode(invalid) == null, "Reject impossible finale: " + str(change))
	return true
