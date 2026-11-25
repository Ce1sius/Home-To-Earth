extends Control

const FACE := preload("res://assets/fonts/FandolHei-Regular.otf")
const BOLD := preload("res://assets/fonts/FandolHei-Bold.otf")
const SIZE := Vector2(1440, 900)
const INK := Color("#fff1dc")
const MUTED := Color("#c8b8a4")
const ORANGE := Color("#edab7c")
const TEAL := Color("#acd6cc")
const DARK := Color("#1a181b")
const EDGE := Color("#544137")


func _ready() -> void:
	theme = Theme.new()
	theme.default_font = FACE
	theme.default_font_size = 16


func text_at(parent: Control, value: String, bounds: Rect2, pixels: int,
		tint: Color = INK, heavy: bool = false) -> Label:
	var node := Label.new()
	node.text = value
	node.position = bounds.position
	node.size = bounds.size
	node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	node.mouse_filter = MOUSE_FILTER_IGNORE
	node.add_theme_color_override("font_color", tint)
	node.add_theme_font_size_override("font_size", pixels)
	if heavy:
		node.add_theme_font_override("font", BOLD)
	parent.add_child(node)
	return node


func fill_at(parent: Control, bounds: Rect2, tint: Color) -> ColorRect:
	var node := ColorRect.new()
	node.position = bounds.position
	node.size = bounds.size
	node.color = tint
	node.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func art_at(parent: Control, texture: Texture2D, bounds: Rect2) -> TextureRect:
	var node := TextureRect.new()
	node.texture = texture
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.position = bounds.position
	node.size = bounds.size
	node.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func panel_at(parent: Control, bounds: Rect2, tint: Color = DARK) -> Panel:
	var node := Panel.new()
	node.position = bounds.position
	node.size = bounds.size
	node.mouse_filter = MOUSE_FILTER_IGNORE
	node.add_theme_stylebox_override("panel", _box(tint, EDGE))
	parent.add_child(node)
	return node


func button_at(parent: Control, value: String, bounds: Rect2, action: Callable,
		primary: bool = false, icon: Texture2D = null) -> Button:
	var node := Button.new()
	node.text = value
	node.position = bounds.position
	node.size = bounds.size
	node.alignment = HORIZONTAL_ALIGNMENT_LEFT
	node.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	node.icon = icon
	node.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	node.add_theme_font_size_override("font_size", 19)
	node.add_theme_constant_override("icon_max_width", 18)
	node.add_theme_stylebox_override("normal", _box(Color("#ac5434") if primary else Color("#272023"), Color("#bf7352") if primary else EDGE))
	node.add_theme_stylebox_override("hover", _box(Color("#bd6744") if primary else Color("#38282a"), ORANGE))
	node.add_theme_stylebox_override("pressed", _box(Color("#803c29"), ORANGE))
	node.add_theme_stylebox_override("disabled", _box(Color("#252024"), EDGE))
	var focus := _box(Color.TRANSPARENT, ORANGE)
	focus.draw_center = false
	focus.set_border_width_all(2)
	node.add_theme_stylebox_override("focus", focus)
	node.add_theme_color_override("font_color", INK)
	node.add_theme_color_override("font_hover_color", Color.WHITE)
	node.add_theme_color_override("font_disabled_color", MUTED)
	node.pressed.connect(action)
	parent.add_child(node)
	return node


func _box(tint: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 16
	style.content_margin_right = 16
	return style
