extends "res://tests/save_roundtrip.gd"


func _initialize() -> void:
	Save.path = "/private/tmp/starfire-frontier-rules-%d.json" % OS.get_process_id()
	var state := _later_campaign()
	var inventory: Dictionary = state.inventory.duplicate()
	_expect(state.layout.move_site(state, "greenhouse", Vector2(176, 288)), "Idle facility can be relocated")
	_expect(state.inventory == inventory, "Rearranging an existing facility does not spend construction materials")
	for bad in [Vector2(-200, 100), state.site_position("ore"), state.crew["tech"]["dest"]]:
		_expect(not state.layout.move_site(state, "greenhouse", bad), "Reject a blocked facility placement")
		_expect(state.site_position("greenhouse") == Vector2(176, 288), "Rejected placement preserves last valid location")
	var early := State.new(true)
	_expect(not early.layout.reason(early, "shelter", early.site_position("lab")).is_empty(), "Unrevealed future sites keep their ground reserved")
	_expect(not State.CampLayout.new().restore(state, {"greenhouse": [NAN, 288]}), "Reject a non-finite saved location")

	state.pump_blueprint = true
	state.pump_built = true
	state.power.blueprint = true
	state.power.solar_built = true
	state.power.extractor_built = true
	state.power.energy = 23.75
	state.power.progress = 7.5
	state.power.extractor_enabled = false
	_expect(Save.write_game(state, "camp", "lead"), "Save current camp")
	var valid := FileAccess.get_file_as_string(Save.path)
	var legacy: Dictionary = JSON.parse_string(valid)
	legacy["version"] = 3
	legacy["state"].erase("layout")
	legacy["state"].erase("expeditions")
	_write_text(JSON.stringify(legacy))
	var migrated := Save.read_game()
	_expect(not migrated.is_empty(), "Version 3 energy campaign migrates")
	if not migrated.is_empty():
		var restored: RefCounted = migrated["state"]
		_expect(restored.power.snapshot() == state.power.snapshot() and restored.pump_built, "Migration preserves battery, equipment, partial production and upgrades")
		_expect(restored.layout.positions.is_empty() and restored.expeditions.resolved.is_empty(), "Old save receives untouched exploration and original layout")
	for issue in ["bounds", "overlap", "unknown", "coordinate", "blueprint", "prototype", "outcome", "premature"]:
		var data: Dictionary = JSON.parse_string(valid)
		match issue:
			"bounds": data["state"]["layout"]["greenhouse"] = [10, 10]
			"overlap": data["state"]["layout"]["greenhouse"] = [state.site_position("ore").x, state.site_position("ore").y]
			"unknown": data["state"]["layout"]["unknown"] = [176, 288]
			"coordinate": data["state"]["layout"]["greenhouse"] = [null, 288]
			"blueprint": data["state"]["expeditions"]["sampler_blueprint"] = true
			"prototype": data["state"]["expeditions"]["sampler_built"] = true
			"outcome": data["state"]["expeditions"]["resolved"]["cargo"] = "scout_ice"
			"premature":
				data["state"]["expeditions"]["resolved"]["cargo"] = "scout_scrap"
				data["state"]["first_harvest"] = false
		_write_text(JSON.stringify(data))
		_expect(Save.read_game().is_empty(), "Reject invalid frontier save: " + issue)

	state = _later_campaign()
	state.crew["lead"]["health"] = 39.0
	inventory = state.inventory.duplicate()
	_expect(not state.assign("lead", "scout_ore") and state.inventory == inventory, "Injured crew cannot enter the risky route or lose its price")
	_expect(state.assign("lead", "scout_scrap"), "Injured crew can choose safer recovery")
	for step in range(300):
		_advance(state, 0.05)
		if state.crew_away("lead"):
			break
	_expect(state.crew_away("lead"), "Departure reaches the field phase")
	state._ration_clock = 59.9
	var food: int = state.inventory["food"]
	_advance(state, 0.2)
	_expect(state.inventory["food"] == food - 1, "Prepaid explorer does not consume a second camp ration")
	_expect(not state.assign("tech", "scout_parts"), "A location cannot be claimed by two crews at once")
	_expect(Save.write_game(state, "camp", "lead"), "Save a pending recovery")
	var conflict: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Save.path))
	conflict["state"]["expeditions"]["resolved"]["cargo"] = "scout_parts"
	_write_text(JSON.stringify(conflict))
	_expect(Save.read_game().is_empty(), "Reject a save that would collect a resolved location twice")
	var scrap: int = state.inventory["scrap"]
	_advance(state, 50)
	_expect(state.inventory["scrap"] == scrap + 5 and state.expeditions.resolved.get("cargo") == "scout_scrap", "One finished recovery grants exactly its announced cargo")
	_advance(state, 50)
	_expect(state.inventory["scrap"] == scrap + 5, "A finite recovery never repeats itself")
	DirAccess.remove_absolute(Save.path)
	if failures == 0:
		print("PASS: safe relocation, hidden plots, version 3 migration, invalid saves, risk gate, prepaid rations and finite recovery")
	quit(1 if failures else 0)
