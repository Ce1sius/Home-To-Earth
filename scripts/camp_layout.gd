extends RefCounted

const MOVABLE := ["shelter", "greenhouse", "bench", "lab"]
const GRID := 16.0
var positions: Dictionary = {}


func snap_point(at: Vector2) -> Vector2:
	return at.snapped(Vector2(GRID, GRID))


func reason(state: RefCounted, site: String, at: Vector2, live: bool = true) -> String:
	if not state.campaign or site not in MOVABLE:
		return "自然资源和接驳设施不能搬移"
	if live and (not state.site_visible(site) or not state.active_at(site).is_empty()):
		return "先停止这处设施的工作，再调整位置"
	var area := Rect2(at - state.campaign_site_size(site) / 2, state.campaign_site_size(site)).grow(7)
	if not Rect2(8, 8, 982, 588).encloses(area):
		return "请放在地图边界内"
	if area.intersects(state.CAMPAIGN_MAP_LABEL) or area.intersects(state.CAMPAIGN_MAP_HELP) or area.intersects(state.CAMPAIGN_MAP_SCOUT):
		return "请为地图提示留出空间"
	for other in state.CAMPAIGN_SITES:
		if other == site or state.site_region(other) != state.CAMP:
			continue
		var other_area := Rect2(state.site_position(other) - state.campaign_site_size(other) / 2, state.campaign_site_size(other))
		if area.intersects(other_area):
			return "与其他设施或预留勘探点重叠"
	if live:
		for worker in state.crew:
			if state.crew_region(worker) != state.CAMP:
				continue
			for key in ["pos", "dest"]:
				var point: Vector2 = state.crew[worker][key]
				if area.intersects(Rect2(point - state.CAMPAIGN_CREW_SIZE / 2, state.CAMPAIGN_CREW_SIZE)):
					return "请避开队员及其目的地"
	return ""


func move_site(state: RefCounted, site: String, at: Vector2) -> bool:
	var point := snap_point(at)
	var why := reason(state, site, point)
	if not why.is_empty():
		state.reported.emit(why)
		return false
	var previous: Vector2 = state.site_position(site)
	var had_position := positions.has(site)
	positions[site] = point
	# Moving a facility must leave an approach to every visible worksite.
	for other in state.CAMPAIGN_SITES:
		if state.site_region(other) == state.CAMP and state.site_visible(other):
			if state._campaign_work_position("", other) == Vector2.INF:
				if had_position:
					positions[site] = previous
				else:
					positions.erase(site)
				state.reported.emit("此处会堵住工位，请多留一些通行空间")
				return false
	state.reported.emit("%s已调整位置，后续任务将前往新工位" % state.SITES[site]["title"])
	state.checkpoint.emit()
	return true


func snapshot() -> Dictionary:
	var data := {}
	for site in positions:
		data[site] = [positions[site].x, positions[site].y]
	return data


func restore(state: RefCounted, data: Dictionary) -> bool:
	var restored := {}
	for site in data:
		var point: Variant = data[site]
		if site not in MOVABLE or not point is Array or point.size() != 2:
			return false
		for value in point:
			if not (value is int or value is float) or not is_finite(float(value)):
				return false
		restored[site] = Vector2(point[0], point[1])
	positions = restored
	for site in positions:
		if not reason(state, site, positions[site], false).is_empty():
			positions = {}
			return false
	return true
