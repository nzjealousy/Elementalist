class_name UiTheme
extends RefCounted
## The shared medieval-fantasy look of every menu: dark stone panels with gold trim, leather and
## brass buttons, parchment text. The frames are 9-slice PNGs in res://assets/ui/ (made by
## tools/art/gen_ui.py); if one is missing the theme falls back to flat boxes so the game still runs.
## The same Theme is handed to every screen, so restyling happens here and nowhere else.

const UI_DIR := "res://assets/ui/"
const TEXT := Color("e8dcc0")
const TEXT_DIM := Color("a89a78")
const GOLD := Color("f2cf6a")
const GOLD_DARK := Color("b8892e")
const RED := Color("ff7a6a")
const GREEN := Color("9ae87a")
const PANEL_BG := Color(0.09, 0.07, 0.06, 0.97)

static var _cached: Theme


static func font() -> Font:
	var system := SystemFont.new()
	system.font_names = PackedStringArray(["Palatino Linotype", "Book Antiqua", "Georgia", "Cambria", "Times New Roman", "serif"])
	system.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	system.hinting = TextServer.HINTING_LIGHT
	system.generate_mipmaps = false
	return system


static func make() -> Theme:
	if _cached != null:
		return _cached
	var theme := Theme.new()
	theme.default_font = font()
	theme.default_font_size = 7
	theme.set_constant("separation", "VBoxContainer", 2)
	theme.set_constant("separation", "HBoxContainer", 3)
	theme.set_color("font_color", "Label", TEXT)

	theme.set_stylebox("panel", "PanelContainer", frame("panel", 8, 7))
	theme.set_stylebox("panel", "Panel", frame("panel", 8, 7))
	theme.set_stylebox("panel", "PopupPanel", frame("panel", 8, 7))

	for control in ["Button", "OptionButton", "CheckButton", "CheckBox"]:
		theme.set_color("font_color", control, TEXT)
		theme.set_color("font_hover_color", control, GOLD)
		theme.set_color("font_pressed_color", control, Color("fff3c8"))
		theme.set_color("font_focus_color", control, GOLD)
		theme.set_color("font_disabled_color", control, Color("6d6454"))
		theme.set_color("font_hover_pressed_color", control, Color("fff3c8"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := frame("button_" + state, 5, 3, 1)
		for control in ["Button", "OptionButton"]:
			theme.set_stylebox(state, control, box)
	theme.set_stylebox("hover_pressed", "Button", frame("button_pressed", 5, 3, 1))
	theme.set_stylebox("focus", "Button", frame("button_focus", 5, 3, 1))

	# Text fields (the hero's name, the join address): a dark well with a gold rim, like the slider groove.
	var well := _flat(Color("120d0a"), GOLD_DARK, 1, 2)
	well.content_margin_left = 3
	well.content_margin_right = 3
	theme.set_stylebox("normal", "LineEdit", well)
	theme.set_stylebox("focus", "LineEdit", _flat(Color("1a130d"), GOLD, 1, 2))
	theme.set_stylebox("read_only", "LineEdit", well)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	theme.set_color("caret_color", "LineEdit", GOLD)
	theme.set_color("selection_color", "LineEdit", Color(GOLD_DARK, 0.55))
	theme.set_constant("caret_width", "LineEdit", 1)

	# Sliders (settings): a dark groove with a gold fill.
	theme.set_stylebox("slider", "HSlider", _flat(Color("120d0a"), Color("4a3512"), 1, 2))
	theme.set_stylebox("grabber_area", "HSlider", _flat(GOLD_DARK, GOLD_DARK, 0, 2))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _flat(GOLD, GOLD, 0, 2))
	var knob := _knob_texture()
	for name in ["grabber", "grabber_highlight", "grabber_disabled"]:
		theme.set_icon(name, "HSlider", knob)
	theme.set_constant("center_grabber", "HSlider", 1)

	var scroll := _flat(Color("120d0a"), Color("4a3512"), 1, 1)
	theme.set_stylebox("scroll", "VScrollBar", scroll)
	theme.set_stylebox("grabber", "VScrollBar", _flat(GOLD_DARK, GOLD_DARK, 0, 1))
	theme.set_stylebox("grabber_highlight", "VScrollBar", _flat(GOLD, GOLD, 0, 1))
	theme.set_stylebox("grabber_pressed", "VScrollBar", _flat(GOLD, GOLD, 0, 1))
	_cached = theme
	return theme


## A 9-slice frame from res://assets/ui/<name>.png; `margin` is the slice width in the source,
## `content` the inner padding. Falls back to a flat box when the image is not there.
static func frame(name: String, margin: int, content: int, content_extra: int = 0) -> StyleBox:
	var path := UI_DIR + name + ".png"
	if not ResourceLoader.exists(path):
		return _flat(PANEL_BG, GOLD_DARK, 1, content)
	var box := StyleBoxTexture.new()
	box.texture = load(path)
	box.texture_margin_left = margin
	box.texture_margin_right = margin
	box.texture_margin_top = margin
	box.texture_margin_bottom = margin
	box.content_margin_left = content + content_extra * 2
	box.content_margin_right = content + content_extra * 2
	box.content_margin_top = content
	box.content_margin_bottom = content
	box.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	box.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return box


static func _flat(bg: Color, border: Color, border_width: int, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_content_margin_all(margin)
	return box


static func _knob_texture() -> Texture2D:
	var img := Image.create(5, 9, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in 9:
		for x in 5:
			var edge := x == 0 or x == 4 or y == 0 or y == 8
			img.set_pixel(x, y, Color("4a3512") if edge else (Color("f6df94") if x == 1 else Color("d4a94a")))
	return ImageTexture.create_from_image(img)


## Gold section heading used at the top of screens.
static func heading(text: String, size: int = 10) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", GOLD)
	label.add_theme_color_override("font_outline_color", Color("2a1c08"))
	label.add_theme_constant_override("outline_size", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## A thin gold rule with a diamond in the middle.
static func divider() -> TextureRect:
	var rect := TextureRect.new()
	var path := UI_DIR + "divider.png"
	if ResourceLoader.exists(path):
		rect.texture = load(path)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	rect.custom_minimum_size = Vector2(0, 5)
	return rect
