class_name FloatText
extends Label
## Short-lived rising text for damage numbers and combo names.


static func spawn(parent: Node, pos: Vector2, text: String, color: Color, font_size: int = 8) -> void:
	if not Settings.get_value("damage_numbers") and font_size <= 8:
		return  # big banners (combo names, "Dodge!") still show; plain numbers do not
	var label := FloatText.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
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
