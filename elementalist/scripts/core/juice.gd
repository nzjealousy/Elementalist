extends Node
## Game-feel helpers: camera shake and hit-stop. Set `enabled = false` in tests.

var enabled := true

var _strength := 0.0
var _time := 0.0
var _total := 0.01
var _stopping := false


func shake(strength: float, duration: float) -> void:
	if not enabled:
		return
	_strength = maxf(_strength * (_time / _total), strength)
	_total = maxf(duration, 0.01)
	_time = _total


## Pixel offset to apply to the camera this frame.
func offset() -> Vector2:
	if _time <= 0.0:
		return Vector2.ZERO
	var falloff := _time / _total
	return (Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _strength * falloff).round()


## Briefly freeze the game (real-time duration) to give hits weight.
func hit_stop(duration: float) -> void:
	if not enabled or _stopping:
		return
	_stopping = true
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_stopping = false


func _process(delta: float) -> void:
	_time = maxf(0.0, _time - delta)
