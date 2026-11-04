class_name UiKit
extends RefCounted
## Small builders shared by every menu screen, so they look and behave alike: a dimmed backdrop,
## a centred framed column, buttons that click and take focus (keyboard and gamepad), and the
## "back to the first button" focus rule from the game-UI checklist.


## A full-screen dim layer under the menu. `alpha` 0.75 keeps the game visible behind a pause menu.
static func dim(parent: Node, alpha: float = 0.78) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = Color(0.02, 0.01, 0.01, alpha)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(rect)
	return rect


## A framed panel centred on the screen, holding a VBox. Returns the VBox to add rows to.
static func column(parent: Node, theme: Theme, min_width: float = 150.0, separation: int = 3) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var panel := PanelContainer.new()
	panel.theme = theme
	panel.custom_minimum_size = Vector2(min_width, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", separation)
	panel.add_child(box)
	return box


## A themed button. `action` runs on press; hovering plays a tick, pressing a click.
static func button(text: String, action: Callable, min_width: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(min_width, 0)
	b.pressed.connect(func():
		Sfx.ui("ui_click")
		action.call())
	b.mouse_entered.connect(func(): Sfx.ui("ui_tick"))
	b.focus_entered.connect(func(): Sfx.ui("ui_tick"))
	return b


static func label(text: String, color: Color = UiTheme.TEXT, size: int = 7, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.horizontal_alignment = align as HorizontalAlignment
	return l


## Focuses the first enabled button under `root` (menus must open with something focused, or the
## gamepad does nothing).
static func focus_first(root: Node) -> void:
	var first := _first_focusable(root)
	if first:
		first.grab_focus.call_deferred()


static func _first_focusable(node: Node) -> Control:
	if node is BaseButton and not (node as BaseButton).disabled and (node as Control).focus_mode == Control.FOCUS_ALL and (node as Control).is_visible_in_tree():
		return node as Control
	for child in node.get_children():
		var found := _first_focusable(child)
		if found:
			return found
	return null


## Wraps vertical focus so Up on the first button lands on the last (and the reverse).
static func wrap_focus(buttons: Array) -> void:
	if buttons.size() < 2:
		return
	var first: Control = buttons[0]
	var last: Control = buttons[-1]
	first.focus_neighbor_top = first.get_path_to(last)
	last.focus_neighbor_bottom = last.get_path_to(first)
