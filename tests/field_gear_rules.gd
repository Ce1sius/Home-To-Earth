extends "res://tests/save_roundtrip.gd"


func _initialize() -> void:
	Save.path = "/private/tmp/starfire-field-gear-%d.json" % OS.get_process_id()
	for test in ["_tray_accounting", "_cooler_trip", "_winch_trip", "_save_validation"]:
		_expect(call(test) == true, test + " completed")
	DirAccess.remove_absolute(Save.path)
	if failures == 0:
		print("PASS: tray accounting across saves, two reusable modules, loadout locks, actual discounted payment/refund, expedition speed and injury, v6 migration and invalid snapshots")
	quit(1 if failures else 0)


func _camp_with_parts() -> RefCounted:
	var state := _later_campaign()
	state.inventory.merge({"food": 15, "scrap": 6, "ore": 5, "ice": 3, "plate": 3}, true)
	return state


func _make(state: RefCounted, module: String) -> bool:
	var cost: Dictionary = state.FieldGear.MODULES[module]["cost"]
	for item in cost:
		for count in range(cost[item]):
			if not state.field_gear.add(state, item):
				return false
	return state.field_gear.assemble(state)


func _reach_work(state: RefCounted, worker: String) -> bool:
	for frame in range(300):
		state.tick(0.05)
		if state.crew[worker]["phase"] == "working":
			return true
	return false


func _finish_work(state: RefCounted, worker: String) -> float:
	var start: float = state.clock
	for frame in range(1400):
		state.tick(0.05)
		if state.crew[worker]["job"].is_empty():
			return state.clock - start
	return -1


func _tray_accounting() -> bool:
	var early := State.new(true)
	early.inventory["scrap"] = 3
	_expect(not early.field_gear.add(early, "scrap") and early.inventory["scrap"] == 3, "First harvest unlocks the tray")
	var state := _camp_with_parts()
	var gear: RefCounted = state.field_gear
	var stock: Dictionary = state.inventory.duplicate()
	_expect(not gear.add(state, "tool") and state.inventory == stock, "Initial tool is independent of module ingredients")
	for item in ["ore", "ore", "ice"]:
		_expect(gear.add(state, item), "Reserve ingredient " + item)
	_expect(not gear.add(state, "plate") and not gear.assemble(state), "Wrong full tray neither assembles nor accepts a fourth card")
	_expect(not gear.remove_at(state, -1) and not gear.remove_at(state, 3), "Invalid slot cannot issue a refund")
	_expect(gear.remove_at(state, 0) and gear.tray == ["ore", "ice"] and state.inventory["ore"] == stock["ore"] - 1, "Removing one duplicate returns one copy")
	_expect(Save.write_game(state, State.CAMP, "lead"), "Save partially filled tray")
	var saved := Save.read_game()
	if saved.is_empty():
		return false
	state = saved["state"]
	gear = state.field_gear
	_expect(gear.tray == ["ore", "ice"] and state.inventory["ice"] == stock["ice"] - 1, "Continue retains order and reserves")
	_expect(gear.clear_tray(state) and not gear.clear_tray(state) and state.inventory == stock, "Clearing the loaded tray refunds exactly once")
	for item in ["scrap", "ice", "scrap"]:
		gear.add(state, item)
	_expect(gear.match_module() == "cooler" and gear.assemble(state), "Three ingredients match in any order")
	_expect(gear.equipped.is_empty() and gear.built.has("cooler") and gear.tray.is_empty(), "Assembling alone does not equip")
	var after_first: Dictionary = state.inventory.duplicate()
	for item in ["ice", "scrap", "scrap"]:
		gear.add(state, item)
	_expect(not gear.assemble(state) and gear.tray.size() == 3, "Already built module keeps staged materials refundable")
	gear.clear_tray(state)
	_expect(state.inventory == after_first, "Retrying a completed assembly consumes nothing")
	_expect(_make(state, "winch") and gear.built.size() == 2 and gear.tray.is_empty(), "Both permanent modules can be owned")
	state.homeward_launched = true
	_expect(not gear.equip(state, "winch") and not gear.add(state, "ice"), "Completed campaign cannot be edited")
	return true


func _cooler_trip() -> bool:
	var state := _camp_with_parts()
	_expect(_make(state, "cooler") and _make(state, "winch"), "Assemble both modules")
	_expect(state.equip_tool("lead") and state.field_gear.equip(state, "cooler"), "Hand tool and expedition pack can coexist")
	state.inventory["food"] = 1
	_expect(state.recipe_cost("scout_blueprint") == {"food": 1, "scrap": 1}, "Cooler discounts food only")
	_expect(state.recipe_cost("scout_scrap") == {"food": 1} and state.recipe_cost("depart") == {"food": 2}, "Food minimum and normal transport price retained")
	var scrap: int = state.inventory["scrap"]
	_expect(state.assign("lead", "scout_blueprint"), "One meal is sufficient for a two-meal blueprint trip using the cooler")
	_expect(not state.field_gear.equip(state, "") and not state.field_gear.equip(state, "winch"), "Accepted travel fixes loadout before materials are paid")
	if not _reach_work(state, "lead"):
		return false
	_expect(state.crew["lead"]["reserved"] == {"food": 1, "scrap": 1} and state.inventory["food"] == 0, "Actual departure reserves discounted supplies")
	_expect(Save.write_game(state, State.CAMP, "lead"), "Save discounted expedition en route")
	var saved := Save.read_game()
	if saved.is_empty():
		return false
	state = saved["state"]
	_expect(state.field_gear.equipped == "cooler" and state.tool_holder == "lead" and not state.field_gear.equip(state, "winch"), "Both slots and expedition lock persist")
	var incorrect := Save._encode(state)
	incorrect["crew"]["lead"]["reserved"]["food"] = 2
	_expect(Save._decode(incorrect) == null, "Reject falsely enlarged reservation")
	state.recall_crew("lead")
	state.recall_crew("lead")
	_expect(state.inventory["food"] == 1 and state.inventory["scrap"] == scrap, "Recalling a discounted trip refunds the actual reservation only")
	_expect(state.field_gear.equip(state, "winch") and not state.assign("lead", "scout_blueprint"), "Swapping back reinstates ordinary two-meal cost")
	return true


func _winch_trip() -> bool:
	var plain := _camp_with_parts()
	var fitted := _camp_with_parts()
	_expect(_make(fitted, "winch") and fitted.field_gear.equip(fitted, "winch"), "Mount rope winch")
	_expect(is_equal_approx(fitted._duration("scout_ore"), plain._duration("scout_ore") / 1.25) and fitted._duration("mine") == plain._duration("mine"), "Only expedition work is faster")
	var durations: Array[float] = []
	for state in [plain, fitted]:
		_expect(state.assign("lead", "scout_ore"), "Dispatch dangerous expedition")
		if not _reach_work(state, "lead"):
			return false
		var health: float = state.crew["lead"]["health"]
		var ore: int = state.inventory["ore"]
		var expected: float = state.expedition_injury("scout_ore")
		durations.append(_finish_work(state, "lead"))
		_expect(health - state.crew["lead"]["health"] == expected and state.inventory["ore"] == ore + 6, "Trip pays yield and the announced injury")
	_expect(plain.expedition_injury("scout_ore") == 12 and fitted.expedition_injury("scout_ore") == 4, "Winch reduces rift injury from 12 to 4")
	_expect(durations.min() > 0 and absf(durations[1] - durations[0] / 1.25) < 0.1, "Measured rope work is 25 percent faster")
	_expect(fitted.field_gear.equip(fitted, "") and fitted._duration("scout_ore") == plain._duration("scout_ore"), "Return unlocks loadout and unequipping restores the regular work time")
	return true


func _save_validation() -> bool:
	var state := _camp_with_parts()
	state.tool_holder = "lead"
	state.assign("lead", "scout_parts")
	if not _reach_work(state, "lead"):
		return false
	var legacy := Save._encode(state)
	legacy.erase("field_gear")
	_write_text(JSON.stringify({"version": 6, "state": legacy, "region": "camp", "selected": "lead"}))
	var loaded := Save.read_game()
	if loaded.is_empty():
		return false
	state = loaded["state"]
	_expect(state.field_gear.snapshot() == State.FieldGear.new().snapshot() and state.tool_holder == "lead" and state.crew["lead"]["reserved"] == {"food": 2}, "V6 in-flight trip preserves full fare and hand tool")
	var data := Save._encode(state)
	for bad in [{"tray": ["ice", "ice", "ice", "ice"]}, {"tray": ["tool"]}, {"tray": [1]}, {"built": {"unknown": true}}, {"built": {"cooler": 1}}, {"equipped": "winch"}, {"equipped": "unknown"}, {"built": {"cooler": true, "winch": true}, "tray": ["ice"]}]:
		var invalid: Dictionary = data.duplicate(true)
		invalid["field_gear"].merge(bad, true)
		_expect(Save._decode(invalid) == null, "Reject inconsistent equipment snapshot " + str(bad))
	var early := Save._encode(State.new(true))
	early["field_gear"]["tray"] = ["scrap"]
	_expect(Save._decode(early) == null, "No hidden staged materials before unlocking the equipment bench")
	return true
