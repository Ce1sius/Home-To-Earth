extends "res://tests/frontier_play.gd"


func _play() -> void:
	Save.path = "/private/tmp/starfire-radar-play-%d.json" % OS.get_process_id()
	change_scene_to_file("res://scenes/title.tscn")
	await scene_changed
	if "--compact" in OS.get_cmdline_user_args():
		root.size = Vector2i(960, 640)
		await process_frame
	_click(_center(current_scene.start_button))
	await scene_changed
	var game := current_scene
	game.set_process(false)
	game.feedback.sound_enabled = false
	_expect(not game.radar_button.visible and not game.sites["radar_cache"].visible, "The landing scene keeps the highland survey undiscovered")
	_run_job(game, "wreck", "salvage")
	_run_job(game, "ore", "mine")
	_run_job(game, "casualty", "rescue")
	_click(_center(game.crew_buttons["lead"]))
	_run_job(game, "greenhouse", "build")
	for i in range(3):
		_run_job(game, "ice", "extract")
	for i in range(2):
		_run_job(game, "greenhouse", "grow")
	_run_job(game, "lab", "research")
	_run_job(game, "wreck", "salvage")
	_run_job(game, "bench", "fabricate")
	_run_job(game, "relay", "trade_food")
	_run_job(game, "beacon", "repair")
	_run_job(game, "beacon", "depart")
	_expect(game.viewed_region == "highlands" and game.radar_button.visible and not game.radar_button.disabled, "Landing in the highlands opens the survey instrument")
	await create_timer(1.35).timeout
	_click(_center(game.radar_button))
	var board: Control = game.radar_board
	if not is_instance_valid(board):
		_expect(false, "Highlands map opens the radar instrument")
		quit(1)
		return
	_expect(game.paused and board.mark_button.disabled, "Survey pauses camp time and needs two probe readings")
	_scan(board, Vector2i(0, 0))
	_key(KEY_RIGHT)
	_key(KEY_ENTER)
	_expect(game.state.radar.probes["lens"] == [Vector2i(0, 0), Vector2i(1, 0)], "Keyboard can place a probe in an adjacent grid cell")
	_click(_center(board.undo_button))
	_key(KEY_ESCAPE)
	_expect(not game.paused and game.radar_board == null, "Closing the scanner restores the map clock")
	game = await _save_reload(game)
	_click(_center(game.radar_button))
	board = game.radar_board
	_expect(game.state.radar.probes["lens"] == [Vector2i(0, 0)] and game.viewed_region == "highlands", "Continue restores the unfinished survey and the viewed highlands")
	_scan(board, Vector2i(8, 1))
	_scan(board, Vector2i(2, 5))
	var target := _solve(game, "lens")
	_click(_center(board.mark_button))
	_motion(board.grid_control.get_global_transform() * board.grid_control.cell_center(target))
	await _capture("radar_echoes")
	_scan(board, Vector2i((target.x + 1) % 9, target.y))
	_expect(not game.state.radar.marked["lens"] and game.state.radar.probes["lens"].size() == 3, "An incorrect mark preserves the clues for another attempt")
	_scan(board, target)
	_expect(game.state.radar.marked["lens"] and not game.state.radar.collected["lens"], "Solving the instrument reveals a worksite without awarding inventory")
	_click(_center(board.zone_buttons["cache"]))
	_scan(board, Vector2i(0, 0))
	_scan(board, Vector2i(8, 0))
	_click(_center(board.mark_button))
	_scan(board, _solve(game, "cache"))
	_click(_center(board.close_button))
	_expect(game.sites["radar_lens"].visible and game.sites["radar_cache"].visible, "Both marked deposits become real highland cards")
	var stock: Dictionary = game.state.inventory.duplicate()
	await _drag(_center(game.crew_cards["lead"]), _center(game.sites["radar_lens"]))
	_expect(game.state.crew["lead"]["job"] == "dig_lens", "Stacking a crew card on a marked lens starts excavation")
	_wait_finale_job(game, "dig_lens")
	_expect(game.state.radar.depot_cargo() == {"ice": 5, "ore": 2} and game.state.inventory["ice"] == stock["ice"], "Excavation puts the samples on the highland shelf")
	_run_job(game, "radar_cache", "dig_cache")
	var manifest: Dictionary = {"ice": 5, "ore": 2, "plate": 2, "circuit": 1}
	_expect(game.state.radar.depot_cargo() == manifest and game.state.inventory["circuit"] == stock["circuit"], "Right-click recovery stores a second local load")
	_click(_center(game.sites["trail"]))
	_expect("水冰×5" in game.detail_body.text and "结构件×2" in game.energy_label.text, "The shelf and return point show the actual manifest")
	await create_timer(1.35).timeout
	await _capture("radar_highlands")
	_click(_center(game.action_button))
	_advance_until_away(game)
	game = await _save_reload(game)
	_expect(game.state.radar.aboard_cargo("lead") == manifest and game.state.radar.depot_cargo().is_empty(), "A returning crew carries the saved samples while camp stock is unchanged")
	_click(_center(game.crew_buttons["lead"]))
	_expect("水冰×5" in game.detail_body.text and game.radar_button.disabled, "The roster shows the carrier's load and an unstaffed highland cannot scan")
	_click(_center(game.action_button))
	_expect(game.state.radar.depot_cargo() == manifest and game.state.crew_region("lead") == "highlands", "Recalling a loaded trip returns cargo to the shelf")
	_run_job(game, "trail", "return")
	for item in manifest:
		_expect(game.state.inventory[item] == stock[item] + manifest[item], "Arrival delivers exactly one load of " + item)
	_expect(game.viewed_region == "camp" and not game.radar_button.visible, "Return follows the crew home")
	game = await _save_reload(game)
	_click(_center(game.region_button))
	_expect(game.radar_button.visible and game.radar_button.disabled and game.state.radar.collected["cache"] and game.state.radar.depot_cargo().is_empty(), "Empty highlands retain the cleared sites and delivered manifest after loading")
	DirAccess.remove_absolute(Save.path)
	if failures == 0:
		print("PASS: fresh-menu highland radar, keyboard and mouse probes, wrong mark, partial reload, two discoveries, crew work, local storage, loaded recall and delivered cargo")
	quit(1 if failures else 0)


func _scan(board: Control, cell: Vector2i) -> void:
	var grid: Control = board.grid_control
	_click(grid.get_global_transform() * grid.cell_center(cell))


func _solve(game: Control, zone: String) -> Vector2i:
	# Use only measured radii. The test exercises the same deduction available to a player.
	var answers: Array[Vector2i] = []
	for x in range(9):
		for y in range(6):
			var cell := Vector2i(x, y)
			var fits := true
			for probe: Vector2i in game.state.radar.probes[zone]:
				if not is_equal_approx(cell.distance_to(probe), game.state.radar.reading(zone, probe)):
					fits = false
					break
			if fits:
				answers.append(cell)
	_expect(answers.size() == 1, "Measured distances identify exactly one grid cell")
	return answers[0] if answers.size() == 1 else Vector2i.ZERO
