extends "res://scripts/screen.gd"

signal accepted
signal canceled

var confirm: Button
var cancel: Button


func _ready() -> void:
	super._ready()
	name = "ConfirmOverlay"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 300
	fill_at(self, Rect2(Vector2.ZERO, SIZE), Color(0.06, 0.04, 0.05, 0.78))
	var panel := panel_at(self, Rect2(438, 316, 564, 267))
	text_at(panel, "重新在火星着陆？", Rect2(32, 22, 500, 57), 32, INK, true)
	var warning := text_at(panel, "", Rect2(32, 91, 500, 70), 20, MUTED)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warning.text = "开始新游戏会用这次着陆替换已保存的营地和飞行记录。"
	cancel = button_at(panel, "保留进度", Rect2(32, 187, 235, 50), _cancel)
	confirm = button_at(panel, "替换进度", Rect2(292, 187, 240, 50), _accept)
	for pair in [[cancel, confirm], [confirm, cancel]]:
		var button: Button = pair[0]
		var other: NodePath = pair[1].get_path()
		button.focus_next = other
		button.focus_previous = other
		button.focus_neighbor_left = other
		button.focus_neighbor_right = other
		button.focus_neighbor_top = other
		button.focus_neighbor_bottom = other
	cancel.grab_focus()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_cancel()


func _accept() -> void:
	accepted.emit()
	queue_free()


func _cancel() -> void:
	canceled.emit()
	queue_free()
