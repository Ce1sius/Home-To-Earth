extends Panel

signal facility_placed(site: String, at: Vector2)
var placement_check: Callable


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if not data is Dictionary or data.get("kind") != "facility" or not placement_check.is_valid():
		return false
	return placement_check.call(data.get("id", ""), at)


func _drop_data(at: Vector2, data: Variant) -> void:
	facility_placed.emit(data["id"], at)
