class_name AmbientMotes
extends Node2D
## The air of a room: a few slow, faint specks per place (Dungeon._theme) that make it feel alive. Decoration only.
## In the isometric view the emitter stands on IsoView's stage, so the specks float above the floor; it sorts before
## everything there, so walls and bodies hide the specks behind them. In the flat view it is this node's child. Built by
## Dungeon._build_room unless the setting "ambient_particles" is off; freed with the room.

const MAX_SPECKS := 24
const SPOTS := 48   # emission spots, scattered once over the floor

## Per place: colour (and `fade_to`), drift (direction, spread, speed px/s, gravity), life (s), the band the specks start in
## (px above the floor), the most alpha a speck reaches (<= 0.5), how many, and whether they blink like fireflies.
const LOOKS := {
	"camp": {"color": Color("b8bcff"), "dir": Vector2(0, -1), "spread": 180.0, "speed": Vector2(1.5, 4.0), "gravity": Vector2.ZERO,
		"life": 5.0, "height": Vector2(3, 16), "alpha": 0.5, "amount": 20, "blink": true},          # fireflies
	"vault": {"color": Color("b0a498"), "dir": Vector2(1, 0.3), "spread": 30.0, "speed": Vector2(1.0, 3.0), "gravity": Vector2(0, 0.6),
		"life": 7.0, "height": Vector2(4, 22), "alpha": 0.32, "amount": 22, "blink": false},        # ash and dust
	"crypt": {"color": Color("8af0e8"), "dir": Vector2(0, -1), "spread": 15.0, "speed": Vector2(1.5, 4.0), "gravity": Vector2(0, -1.5),
		"life": 6.0, "height": Vector2(0, 6), "alpha": 0.42, "amount": 22, "blink": false},         # rising like bubbles
	"hollow": {"color": Color("9ad870"), "dir": Vector2(1, 0.15), "spread": 25.0, "speed": Vector2(2.0, 5.0), "gravity": Vector2(0, 0.8),
		"life": 6.0, "height": Vector2(4, 20), "alpha": 0.42, "amount": 22, "blink": false},        # spores, leaf bits
	"ember": {"color": Color("ffb060"), "fade_to": Color("e0503a"), "dir": Vector2(0, -1), "spread": 20.0, "speed": Vector2(4.0, 9.0),
		"gravity": Vector2(0, -2.0), "life": 4.0, "height": Vector2(0, 3), "alpha": 0.5, "amount": 24, "blink": false},  # embers off the floor
	"spire": {"color": Color("c4a8ff"), "dir": Vector2(0, 1), "spread": 12.0, "speed": Vector2(1.0, 3.0), "gravity": Vector2(0, 0.5),
		"life": 7.0, "height": Vector2(18, 30), "alpha": 0.45, "amount": 22, "blink": true},        # star-dust falling
}

var theme := "vault"
var area := Rect2()          # the floor, world px
var emitter: CPUParticles2D


static func make(place: String, floor_rect: Rect2) -> AmbientMotes:
	var motes := AmbientMotes.new()
	motes.theme = place
	motes.area = floor_rect
	return motes


func _ready() -> void:
	var look: Dictionary = LOOKS.get(theme, LOOKS["vault"])
	var view := IsoView.active
	var iso := view != null and view.is_inside_tree()
	var rng := RandomNumberGenerator.new()  # its own stream: the room's look never shifts the game's randf()
	var spots := PackedVector2Array()
	for i in SPOTS:
		var p := Vector2(rng.randf_range(area.position.x, area.end.x), rng.randf_range(area.position.y, area.end.y))
		var h := rng.randf_range(look["height"].x, look["height"].y)
		spots.append(IsoView.project(p) - Vector2(0.0, h) if iso else p - Vector2(0.0, h * 0.5))  # flat: no height, a touch north
	emitter = CPUParticles2D.new()
	emitter.amount = mini(int(look["amount"]), MAX_SPECKS)
	emitter.lifetime = float(look["life"])
	emitter.preprocess = float(look["life"])  # the room is already full of them when it appears
	emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
	emitter.emission_points = spots
	emitter.direction = look["dir"]
	emitter.spread = float(look["spread"])
	emitter.gravity = look["gravity"]
	emitter.initial_velocity_min = float(look["speed"].x)
	emitter.initial_velocity_max = float(look["speed"].y)
	emitter.scale_amount_min = 1.4
	emitter.scale_amount_max = 2.0
	emitter.material = SkillFx.additive_material()  # light on the dark floor: a faint speck still reads over the floor's own grain
	emitter.color = look["color"]
	emitter.color_ramp = _ramp(look)
	if iso:
		view.add_upright(emitter, Vector2.ZERO)  # at the stage's origin: it sorts before every wall and body
		emitter.z_index = 0
	else:
		emitter.z_index = 40  # top-down, the air is over everything but the effects
		add_child(emitter)


## Fades each speck in and out (alpha never above the look's), blinking twice for fireflies; `fade_to` shifts the colour.
static func _ramp(look: Dictionary) -> Gradient:
	var a := float(look["alpha"])
	var end: Color = Color.WHITE
	if look.has("fade_to"):
		var from: Color = look["color"]
		var to: Color = look["fade_to"]
		end = Color(to.r / maxf(from.r, 0.01), to.g / maxf(from.g, 0.01), to.b / maxf(from.b, 0.01))  # a multiplier on `color`
	var ramp := Gradient.new()
	if look["blink"]:
		ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.32, 0.5, 0.68, 0.85, 1.0])
		ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, a), Color(1, 1, 1, a * 0.2), Color(1, 1, 1, a),
			Color(1, 1, 1, a * 0.25), Color(end, a), Color(end, 0.0)])
	else:
		ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.75, 1.0])
		ramp.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, a), Color(end, a), Color(end, 0.0)])
	return ramp


func _exit_tree() -> void:
	if is_instance_valid(emitter) and emitter.get_parent() != self:
		emitter.queue_free()  # it lived on the stage: it goes with the room
