extends "res://tests/save_roundtrip.gd"


func _initialize() -> void:
	Save.path = "/private/tmp/starfire-highland-radar-%d.json" % OS.get_process_id()
	_expect(_probe_survey(), "Probe survey finished")
	_expect(_field_logistics(), "Sample shipping finished")
	_expect(_migration_and_validation(), "Radar saves finished")
	DirAccess.remove_absolute(Save.path)
	if failures == 0:
		print("PASS: randomized zones, triangulation, undo, map reveal, excavation, two crews, departure manifests, shelf recall, saved delivery, v7 migration and corrupt cargo rejection")
	quit(1 if failures else 0)


func _highland_party() -> RefCounted:
	var state := _later_campaign()
	state.crew["lead"]["region"] = State.HIGHLANDS
	state.crew["lead"]["pos"] = Vector2(339, 311)
	state.crew["lead"]["dest"] = state.crew["lead"]["pos"]
	state.crew["tech"]["region"] = State.HIGHLANDS
	state.crew["tech"]["pos"] = Vector2(630, 300)
	state.crew["tech"]["dest"] = state.crew["tech"]["pos"]
	State.CrewWork.ensure(state.crew["tech"])
	return state


# Triangulate using only measurements the player can see. Two probes on the
# upper edge remove the usual reflection ambiguity outside the playing area.
func _triangulate(radar: RefCounted, zone: String) -> Vector2i:
	var candidates: Array[Vector2i] = []
	for y in range(radar.GRID.y):
		for x in range(radar.GRID.x):
			var cell := Vector2i(x, y)
			var matches := true
			for probe: Vector2i in radar.probes[zone]:
				if not is_equal_approx(probe.distance_to(cell), radar.reading(zone, probe)):
					matches = false
			if matches:
				candidates.append(cell)
	_expect(candidates.size() == 1, "Readable circles identify one target")
	return candidates[0] if candidates.size() == 1 else Vector2i(-1, -1)


func _survey_zone(state: RefCounted, zone: String) -> bool:
	var radar: RefCounted = state.radar
	return radar.place(state, zone, Vector2i(0, 0)) and radar.place(state, zone, Vector2i(8, 0)) and radar.mark(state, zone, _triangulate(radar, zone))


func _probe_survey() -> bool:
	var state := State.new(true)
	_expect(not state.radar.place(state, "lens", Vector2i.ZERO), "A new camp cannot survey the highlands")
	state = _later_campaign()
	_expect(not state.radar.place(state, "lens", Vector2i.ZERO), "Prior visit without local crew cannot operate the radar")
	state = _highland_party()
	var radar: RefCounted = state.radar
	_expect(not state.site_visible("radar_lens") and not state.assign("lead", "dig_lens"), "Unmarked targets cannot be excavated")
	_expect(radar.reading("lens", Vector2i.ONE) < 0 and radar.marked_cell("lens") == Vector2i(-1, -1), "Unprobed readings and coordinates stay hidden")
	_expect(not radar.place(state, "unknown", Vector2i.ONE) and not radar.place(state, "lens", Vector2i(9, 0)), "Grid and zone bounds apply")
	_expect(radar.place(state, "lens", Vector2i.ZERO) and not radar.place(state, "lens", Vector2i.ZERO), "Only distinct probes occupy slots")
	_expect(not radar.mark(state, "lens", Vector2i.ONE), "One echo cannot confirm a marker")
	_expect(Save.write_game(state, State.HIGHLANDS, "lead"), "Save partial survey")
	var loaded := Save.read_game()
	if loaded.is_empty():
		return false
	state = loaded["state"]
	radar = state.radar
	_expect(radar.probes["lens"] == [Vector2i.ZERO] and radar.probes["cache"].is_empty(), "Independent probes survive a JSON round trip")
	_expect(radar.place(state, "lens", Vector2i(8, 0)) and radar.place(state, "lens", Vector2i(4, 4)), "Three probes can be deployed")
	_expect(not radar.place(state, "lens", Vector2i(1, 1)) and radar.undo(state, "lens") and radar.probes["lens"].size() == 2, "Probe cap and last-in undo")
	_expect(not radar.mark(state, "lens", Vector2i.ZERO) and radar.probes["lens"].size() == 2, "Wrong guesses preserve echoes")
	var target := _triangulate(radar, "lens")
	state.crew["lead"]["pos"] = state.site_position("radar_lens")
	state.crew["lead"]["dest"] = state.crew["lead"]["pos"]
	_expect(radar.mark(state, "lens", target) and radar.marked_cell("lens") == target, "Triangulation reveals the worksite")
	_expect(state.site_visible("radar_lens") and state._campaign_position_free("lead", state.crew["lead"]["pos"], State.HIGHLANDS), "Revealing a worksite preserves a usable crew marker")
	_expect(not radar.undo(state, "lens") and not radar.mark(state, "lens", target), "Locked surveys cannot be claimed again")
	var layouts := {}
	for seed_value in range(8):
		var geology := State.HighlandRadar.new(seed_value)
		var data: Dictionary = geology.snapshot()
		layouts[data["lens"]["target"]] = true
	_expect(layouts.size() >= 4, "Different geological seeds produce distinct playable sites")
	return true


func _reach_phase(state: RefCounted, who: String, recipe: String, phase: String) -> bool:
	for i in range(1400):
		if state.crew[who]["job"] == recipe and state.crew[who]["phase"] == phase:
			return true
		state.tick(0.05)
	return false


func _field_logistics() -> bool:
	var state := _highland_party()
	var initial: Dictionary = state.inventory.duplicate()
	_expect(_survey_zone(state, "lens") and _survey_zone(state, "cache"), "Both sites can be found independently")
	_expect(state.assign("lead", "dig_lens") and not state.assign("tech", "dig_lens"), "Only one worker can excavate a site")
	_expect(_reach_phase(state, "lead", "dig_lens", "working"), "Crew reaches the actual mapped location")
	state.stop_crew("lead")
	_expect(state.radar.depot_cargo().is_empty() and not state.radar.collected["lens"], "Canceled digging produces no samples")
	_expect(state.assign("lead", "dig_lens"), "Digging can resume")
	_advance(state, 27)
	var ice: Dictionary = State.HighlandRadar.ZONES["lens"]["reward"]
	var parts: Dictionary = State.HighlandRadar.ZONES["cache"]["reward"]
	_expect(state.radar.depot_cargo() == ice and state.inventory == initial and not state.assign("lead", "dig_lens"), "One shelf load and no remote inventory gain")
	_expect(state.assign("tech", "dig_cache") and _reach_phase(state, "tech", "dig_cache", "working"), "Second worker can dig during the next return")
	_advance(state, 8.5)
	_expect(state.assign("lead", "return") and state.radar.aboard_cargo("lead").is_empty(), "Walking to departure does not move cargo")
	_expect(_reach_phase(state, "lead", "return", "working"), "Actual return departure")
	_expect(state.radar.aboard_cargo("lead") == ice and state.radar.depot_cargo().is_empty(), "Manifest takes only the cargo present at departure")
	for i in range(160):
		if state.radar.collected["cache"]:
			break
		state.tick(0.05)
	_expect(state.radar.aboard_cargo("lead") == ice and state.radar.depot_cargo() == parts, "Late excavation stays on the highland shelf")
	_expect(Save.write_game(state, State.HIGHLANDS, "lead"), "Save both a shelf load and a returning manifest")
	var loaded := Save.read_game()
	if loaded.is_empty():
		return false
	state = loaded["state"]
	_expect(state.radar.aboard_cargo("lead") == ice and state.radar.depot_cargo() == parts, "Returning manifest never absorbs later finds on reload")
	state.recall_crew("lead")
	var combined := ice.duplicate()
	combined.merge(parts)
	_expect(state.radar.depot_cargo() == combined and state.radar.aboard_cargo("lead").is_empty() and state.inventory == initial, "Recall returns the manifest to the shelf, with no duplicate deposit")
	state.recall_crew("lead")
	_expect(state.assign("tech", "return") and _reach_phase(state, "tech", "return", "working"), "Another crew member can pick up both loads")
	state.stop_crew("tech")
	_expect(state.radar.depot_cargo() == combined and state.radar.aboard_cargo("tech").is_empty(), "Stopping an active trip also restores its cargo")
	_expect(state.assign("tech", "return") and _reach_phase(state, "tech", "return", "working"), "Depart after an explicit stop")
	var reports := []
	state.radar_delivered.connect(func(cargo: Dictionary): reports.append(cargo))
	_advance(state, 20)
	_expect(reports == [combined] and state.crew_region("tech") == State.CAMP and state.radar.depot_cargo().is_empty(), "Return delivers one receipt in camp")
	for item in combined:
		_expect(state.inventory[item] == initial[item] + combined[item], "Delivered item added exactly once: " + item)
	_expect(Save.write_game(state, State.CAMP, "tech"), "Save completed returns")
	loaded = Save.read_game()
	if loaded.is_empty():
		return false
	state = loaded["state"]
	_expect(state.assign("lead", "return") and _reach_phase(state, "lead", "return", "working"), "Last worker embarks on an empty return")
	_expect(not state.radar.operator_reason(state).is_empty() and state.radar.aboard_cargo("lead").is_empty(), "Returning crew cannot operate a remote radar or collect a delivered batch")
	_advance(state, 18)
	for item in combined:
		_expect(state.inventory[item] == initial[item] + combined[item], "Second trip never duplicates " + item)
	return true


func _migration_and_validation() -> bool:
	var state := _later_campaign()
	var data: Dictionary = Save._encode(state)
	data.erase("radar")
	_write_text(JSON.stringify({"version": 7, "region": State.CAMP, "selected": "lead", "state": data}))
	var loaded := Save.read_game()
	if loaded.is_empty():
		return false
	var radar: RefCounted = loaded["state"].radar
	var repeated := Save.read_game()
	if repeated.is_empty():
		return false
	_expect(radar.snapshot() == repeated["state"].radar.snapshot() and radar.probes["lens"].is_empty() and radar.depot_cargo().is_empty() and loaded["state"].navigation_record, "Old saves receive stable untouched geology and keep earlier achievements")
	state = _highland_party()
	_expect(_survey_zone(state, "lens"), "Valid unlocked save fixture")
	data = Save._encode(state)
	for changed in [{"target": 1.2}, {"target": 54}, {"probes": [0, 0]}, {"probes": [0]}, {"probes": [0, 8, 17, 35]}, {"cargo": "unknown"}, {"cargo": "lead"}, {"marked": false, "cargo": "depot"}]:
		var bad := data.duplicate(true)
		bad["radar"]["lens"].merge(changed, true)
		_expect(Save._decode(bad) == null, "Reject invalid radar record " + str(changed))
	var early := State.new(true)
	var premature := Save._encode(early)
	premature["radar"] = data["radar"]
	_expect(Save._decode(premature) == null, "Reject surveys preceding the first highland visit")
	return true
