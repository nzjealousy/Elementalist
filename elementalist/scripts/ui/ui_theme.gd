class_name UiTheme
extends RefCounted
## The shared look of the menu screens (character sheet, new character): small pixel-scale
## text, a dark framed panel, and flat buttons whose pressed state doubles as "selected".


static func make() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 6
	theme.set_constant("separation", "VBoxContainer", 1)

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.08, 0.09, 0.12, 0.96)
	panel.border_color = Color(0.45, 0.5, 0.6)
	panel.set_border_width_all(1)
	panel.set_content_margin_all(6)
	theme.set_stylebox("panel", "PanelContainer", panel)

	var colors := {
		"normal": Color(0.25, 0.3, 0.4), "hover": Color(0.35, 0.42, 0.55), "pressed": Color(0.5, 0.6, 0.85),
		"disabled": Color(0.15, 0.16, 0.2), "focus": Color(0.25, 0.3, 0.4), "hover_pressed": Color(0.55, 0.65, 0.9),
	}
	for state in colors:
		var box := StyleBoxFlat.new()
		box.bg_color = colors[state]
		box.set_content_margin_all(1)
		box.content_margin_left = 4
		box.content_margin_right = 4
		theme.set_stylebox(state, "Button", box)
	return theme
