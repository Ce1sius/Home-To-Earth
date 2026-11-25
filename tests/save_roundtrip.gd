extends SceneTree

const State := preload("res://scripts/mission_state.gd")
const Save := preload("res://scripts/campaign_save.gd")
var failures := 0


func _initialize() -> void:
	Save.path = "/private/tmp/starfire-save-check-%d.json" % OS.get_process_id()
	var state := State.new(true)
	_expect(Save.read_game().is_empty() and Save.last_error.is_empty(), "Missing save is a normal first launch")
	_expect(Save.write_game(state, State.CAMP, "lead"), "Save fresh campaign")
	var fresh := Save.read_game()
	_expect(not fresh.is_empty() and fresh["state"].inventory == state.inventory, "Fresh campaign loads")
	_expect(state.assign("lead", "salvage"), "Assign initial salvage")
	_advance(state, 1.0)
	_expect(Save.write_game(state, State.CAMP, "lead"), "Save walking crew")
	var walking := Save.read_game()
	if walking.is_empty():
		_expect(false, "Read walking crew")
	else:
		_advance(walking["state"], 15)
		_expect(walking["state"].inventory["scrap"] == 3 and state.inventory["scrap"] == 0, "Loaded work finishes once and leaves original state separate")

	state = _later_campaign()
	_expect(state.assign("lead", "deliver_array"), "Assign array delivery")
	_expect(state.set_order("tech", "grow", "continuous"), "Assign greenhouse duty")
	_advance(state, 5)
	_expect(state.crew["lead"]["phase"] == "working", "Fixture is in transit")
	_expect(Save.write_game(state, State.CAMP, "lead"), "Save simultaneous work")
	var snapshot := FileAccess.get_file_as_string(Save.path)
	var loaded := Save.read_game()
	if loaded.is_empty():
		_expect(false, "Read simultaneous work")
	else:
		var restored: RefCounted = loaded["state"]
		_expect(restored.crew["lead"]["reserved"] == {"food": 2, "plate": 2, "circuit": 1}, "Reserved cargo survives JSON")
		_expect(restored.crew["tech"]["reserved"] == {"ice": 1}, "Greenhouse input survives JSON")
		_expect(is_equal_approx(restored._ration_clock, state._ration_clock) and is_equal_approx(restored._neighbor_clock, state._neighbor_clock), "Production and supply timers persist")
		_advance(restored, 30)
		_expect(restored.array_supplied and restored.crew_region("lead") == State.HIGHLANDS, "Delivery completes after loading")
		_expect(restored.inventory["plate"] == 0 and restored.inventory["circuit"] == 0, "Load never duplicates delivery inputs")
		_expect(restored.crew["tech"]["phase"] == "waiting", "Greenhouse continues until it needs ice")
		_expect(Save.write_game(restored, State.HIGHLANDS, "lead"), "Save waiting greenhouse and field crew")
		var waiting := Save.read_game()
		_expect(not waiting.is_empty(), "Waiting assignment reloads")
		if not waiting.is_empty():
			var regrown: RefCounted = waiting["state"]
			var food: int = regrown.inventory["food"]
			regrown.inventory["ice"] = 1
			_advance(regrown, 9)
			_expect(regrown.inventory["food"] == food + 3, "Reloaded waiting job resumes when supplied")

	var legacy: Dictionary = JSON.parse_string(snapshot)
	legacy["version"] = 1
	for key in ["shelter_expanded", "pump_blueprint", "pump_built", "botanist_joined", "neighbor_upgraded", "neighbor_trades"]:
		legacy["state"].erase(key)
	for unit in legacy["state"]["crew"].values():
		for key in ["health", "stamina", "morale", "duty"]:
			unit.erase(key)
	_write_text(JSON.stringify(legacy))
	var migrated := Save.read_game()
	_expect(not migrated.is_empty(), "Existing version 1 campaign migrates")
	if not migrated.is_empty():
		_expect(migrated["state"].calibration_blueprint and migrated["state"].inventory == state.inventory,
			"Migration retains main story and deducted supplies")
		_expect(migrated["state"].crew["lead"]["reserved"] == state.crew["lead"]["reserved"], "Migration keeps in-flight cargo intact")
		_expect(migrated["state"].crew["lead"]["stamina"] == 100 and not migrated["state"].pump_built, "New camp features receive compatible defaults")
	for bad in ["{broken json", "null", "{}"]:
		_write_text(bad)
		_expect(Save.read_game().is_empty() and not Save.last_error.is_empty(), "Reject broken JSON")
	for issue in ["version", "negative", "missing", "timer", "position", "job", "reservation", "progress", "selection", "stats", "duty"]:
		var data: Dictionary = JSON.parse_string(snapshot)
		match issue:
			"version": data["version"] = 999
			"negative": data["state"]["inventory"]["food"] = -1
			"missing": data["state"]["inventory"].erase("ice")
			"timer": data["state"]["_ration_clock"] = "bad"
			"position": data["state"]["crew"]["lead"]["pos"] = [1, null]
			"job": data["state"]["crew"]["lead"]["job"] = "unknown_recipe"
			"reservation": data["state"]["crew"]["lead"]["reserved"]["plate"] = 50
			"progress": data["state"]["outpost_built"] = false
			"selection": data["selected"] = "unknown_crew"
			"stats": data["state"]["crew"]["lead"]["stamina"] = 999
			"duty": data["state"]["crew"]["lead"]["duty"] = {"recipe": "repair", "mode": "continuous", "remaining": 1, "target": 1}
		_write_text(JSON.stringify(data))
		_expect(Save.read_game().is_empty() and not Save.last_error.is_empty(), "Reject invalid " + issue)
	_write_text(snapshot)
	var original_path := Save.path
	Save.path += "/missing/save.json"
	_expect(not Save.write_game(state, State.CAMP, "lead"), "Write failure is reported")
	Save.path = original_path
	_expect(FileAccess.get_file_as_string(Save.path) == snapshot and not Save.read_game().is_empty(), "Failed write preserves the prior campaign")
	DirAccess.remove_absolute(Save.path)
	if failures == 0:
		print("PASS: save/restore walking, transit, working, waiting, timers, version 1 migration, invalid data and write failure")
	quit(1 if failures else 0)


func _later_campaign() -> RefCounted:
	var state := State.new(true)
	state.recovered = {"wreck": true, "ore": true}
	state.recruited = true
	state.greenhouse_built = true
	state.first_harvest = true
	state.blueprint = true
	state.won = true
	state.highlands_visited = true
	state.navigation_record = true
	state.outpost_built = true
	state.calibration_blueprint = true
	state.calibration_source = "research"
	state.inventory.merge({"food": 12, "plate": 2, "circuit": 1, "ice": 2}, true)
	state.crew["lead"]["pos"] = Vector2(760, 250)
	state.crew["lead"]["dest"] = Vector2(760, 250)
	state.crew["tech"] = {"pos": Vector2(350, 178), "dest": Vector2(350, 178),
		"job": "", "phase": "", "elapsed": 0.0, "reserved": {}}
	return state


func _advance(state: RefCounted, seconds: float) -> void:
	for i in range(roundi(seconds * 20)):
		state.tick(0.05)


func _write_text(value: String) -> void:
	var file := FileAccess.open(Save.path, FileAccess.WRITE)
	file.store_string(value)
	file.close()


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL: " + message)
