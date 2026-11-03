class_name FloatText
extends Label
## Short-lived rising text for damage numbers and combo names.


static func spawn(parent: Node, pos: Vector2, text: String, color: Color) -> void:
	var label := FloatText.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.z_index = 100
	label.position = pos - Vector2(10, 18)
	parent.add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 14.0, 0.7)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.7)
	tween.tween_callback(label.queue_free)
