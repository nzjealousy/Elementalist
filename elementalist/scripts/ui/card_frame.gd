class_name CardFrame
extends Control
## The border and backing of a selection card, drawn in pixels so it matches the sprites. The
## border colour and the corner ornaments say what kind of card it is: a class gets its own
## (rivets for the Vanguard, leaves for the Ranger and Druid, stars for the Mystic and Sage, flames for the
## Channeler, spikes for the Berserker and Assassin ...), reward cards take a colour from their kind.
## Put the card's content in a child Control; `inset` is the room the border takes. `hot` (mouse over
## or focus) brightens the border.

const ORNAMENTS := {
	"wanderer": "plain", "channeler": "flames", "vanguard": "rivets", "ranger": "leaves", "mystic": "stars",
	"assassin": "spikes", "berserker": "spikes", "sage": "stars", "druid": "leaves",
}
const INSET := 4

@export var color := Color("a098f0")
@export var ornament := "plain"
@export var thick := 2          # border width in pixels (2 or 3)
var hot := false:
	set(value):
		hot = value
		queue_redraw()


## A card frame styled for a class.
static func for_class(class_id: String) -> CardFrame:
	var frame := CardFrame.new()
	frame.color = HeroLook.class_color(class_id).lerp(HeroLook.class_trim(class_id), 0.35).lightened(0.15)
	frame.ornament = String(ORNAMENTS.get(class_id, "plain"))
	frame.thick = 3 if class_id in ["vanguard", "berserker"] else 2
	return frame


static func for_kind(kind_color: Color, kind_ornament: String = "plain") -> CardFrame:
	var frame := CardFrame.new()
	frame.color = kind_color
	frame.ornament = kind_ornament
	return frame


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var dark := Color("0a0618")  # the one ink outline
	var edge := color.lightened(0.25) if hot else color
	draw_rect(r, dark)                                              # outer line
	draw_rect(r.grow(-1), edge.darkened(0.45))                      # shadow side of the border
	draw_rect(r.grow(-2), edge.darkened(0.15))
	draw_rect(r.grow(-1.0 - float(thick)), Color("12102a")) # the obsidian backing
	var inner := r.grow(-1.0 - float(thick))
	draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * 0.45)), Color("1a1638"))   # a lighter top half
	draw_rect(Rect2(inner.position + Vector2(0, inner.size.y * 0.45), Vector2(inner.size.x, 1)), Color(edge, 0.35))
	draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2, 1)), edge.lightened(0.4))              # a lit top edge
	_ornaments(r, edge)


func _ornaments(r: Rect2, edge: Color) -> void:
	var tl := r.position
	var br := r.end
	match ornament:
		"rivets":
			for corner in [tl + Vector2(2, 2), Vector2(br.x - 4, tl.y + 2), Vector2(tl.x + 2, br.y - 4), br - Vector2(4, 4)]:
				draw_rect(Rect2(corner, Vector2(2, 2)), edge.lightened(0.5))
				draw_rect(Rect2(corner + Vector2(1, 1), Vector2(1, 1)), edge.darkened(0.4))
		"leaves":
			for p in [tl + Vector2(1, 1), Vector2(br.x - 4, tl.y + 1), Vector2(tl.x + 1, br.y - 4), br - Vector2(4, 4)]:
				draw_rect(Rect2(p, Vector2(3, 3)), Color("88e880"))
				draw_rect(Rect2(p + Vector2(1, 1), Vector2(1, 1)), Color("1a6a48"))
		"stars":
			for corner in [tl + Vector2(3, 3), Vector2(br.x - 4, tl.y + 3), Vector2(tl.x + 3, br.y - 4), br - Vector2(4, 4)]:
				draw_rect(Rect2(corner + Vector2(-1, 0), Vector2(3, 1)), Color("e8e0ff"))
				draw_rect(Rect2(corner + Vector2(0, -1), Vector2(1, 3)), Color("e8e0ff"))
		"flames":
			for x in [tl.x + 4, br.x - 7]:
				draw_rect(Rect2(Vector2(x, tl.y - 1), Vector2(3, 2)), Color("ff8040"))
				draw_rect(Rect2(Vector2(x + 1, tl.y - 3), Vector2(1, 2)), Color("ffd8a0"))
		"spikes":
			for i in 3:
				var x := tl.x + 4 + i * 5.0
				draw_rect(Rect2(Vector2(x, tl.y - 2), Vector2(1, 3)), edge.lightened(0.3))
				draw_rect(Rect2(Vector2(br.x - 5 - i * 5.0, br.y - 1), Vector2(1, 3)), edge.lightened(0.3))
		_:
			draw_rect(Rect2(Vector2(tl.x + r.size.x * 0.5 - 2, tl.y - 1), Vector2(4, 2)), edge.lightened(0.4))
