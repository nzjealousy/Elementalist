extends Node
## Element registry and combo resolver. Pure data + lookup, no scene dependencies.
## Combo keys are the two element ids sorted alphabetically and joined with "+".

const MAIN := ["fire", "water", "air", "mineral", "earth"]
const RARE := ["light", "dark"]

const COLORS := {
	"fire": Color("ff6a2b"),
	"water": Color("3fa7ff"),
	"air": Color("d9f2ff"),
	"mineral": Color("b5a58a"),
	"earth": Color("5fbf4a"),
	"light": Color("fff3a8"),
	"dark": Color("7a3fb5"),
	"martial": Color("c9c9d2"),  # not an element: the physical skill set of non-elementalists
}

## effect kinds understood by Enemy: dot, slow, root, stun, vuln
const COMBOS := {
	"air+earth": {"name": "Spore", "mult": 1.2, "effect": "dot", "time": 3.0, "power": 3.0, "color": Color("a6d65a")},
	"air+fire": {"name": "Lightning", "mult": 1.6, "effect": "stun", "time": 0.8, "power": 1.0, "color": Color("fff06a")},
	"air+mineral": {"name": "Sand", "mult": 1.2, "effect": "slow", "time": 2.5, "power": 0.5, "color": Color("d9c28a")},
	"air+water": {"name": "Frost", "mult": 1.3, "effect": "root", "time": 1.5, "power": 1.0, "color": Color("bfeaff")},
	"earth+fire": {"name": "Ash", "mult": 1.3, "effect": "dot", "time": 3.0, "power": 5.0, "color": Color("9a8f86")},
	"earth+mineral": {"name": "Amber", "mult": 1.2, "effect": "root", "time": 1.8, "power": 1.0, "color": Color("e0a43a")},
	"earth+water": {"name": "Growth", "mult": 1.2, "effect": "root", "time": 1.2, "power": 1.0, "color": Color("4fd18b")},
	"fire+mineral": {"name": "Magma", "mult": 1.5, "effect": "dot", "time": 3.0, "power": 7.0, "color": Color("ff3a1a")},
	"fire+water": {"name": "Steam", "mult": 1.4, "effect": "vuln", "time": 3.0, "power": 1.0, "color": Color("e6ecf2")},
	"mineral+water": {"name": "Crystal", "mult": 1.3, "effect": "stun", "time": 0.7, "power": 1.0, "color": Color("9be8e0")},
}


## Combos with the rare elements: Light and Dark each pair with the five main elements, and with each
## other. Same shape as COMBOS; resolve() looks in both.
const RARE_COMBOS := {
	"air+light": {"name": "Halo", "mult": 1.3, "effect": "stun", "time": 0.8, "power": 1.0, "color": Color("fff8c8")},
	"earth+light": {"name": "Bloom", "mult": 1.2, "effect": "root", "time": 1.5, "power": 1.0, "color": Color("c8f09a")},
	"fire+light": {"name": "Solar Flare", "mult": 1.6, "effect": "dot", "time": 3.0, "power": 6.0, "color": Color("ffd24a")},
	"light+mineral": {"name": "Gleam", "mult": 1.3, "effect": "vuln", "time": 3.5, "power": 1.0, "color": Color("fff0b0")},
	"light+water": {"name": "Dawn Mist", "mult": 1.3, "effect": "slow", "time": 2.5, "power": 0.6, "color": Color("c8ecff")},
	"air+dark": {"name": "Miasma", "mult": 1.3, "effect": "dot", "time": 3.0, "power": 4.0, "color": Color("8a7ab0")},
	"dark+earth": {"name": "Blight", "mult": 1.3, "effect": "dot", "time": 3.0, "power": 5.0, "color": Color("5a6a3a")},
	"dark+fire": {"name": "Hellfire", "mult": 1.6, "effect": "dot", "time": 3.0, "power": 8.0, "color": Color("c8204a")},
	"dark+mineral": {"name": "Obsidian", "mult": 1.4, "effect": "stun", "time": 0.8, "power": 1.0, "color": Color("3a2f4a")},
	"dark+water": {"name": "Abyss", "mult": 1.3, "effect": "root", "time": 1.5, "power": 1.0, "color": Color("2a3a7a")},
	"dark+light": {"name": "Twilight", "mult": 1.8, "effect": "vuln", "time": 4.0, "power": 1.0, "color": Color("c89af0")},
}


## Resonance: this many discrete hits of the SAME element in a row (without another element
## breaking the chain) trigger that element's resonance combo, and reset the count.
const RESONANCE_HITS := 3
const RESONANCE := {
	"fire": {"name": "Blaze", "mult": 1.3, "effect": "dot", "time": 3.0, "power": 6.0, "color": Color("ff8a3a")},
	"water": {"name": "Drench", "mult": 1.2, "effect": "slow", "time": 3.0, "power": 0.7, "color": Color("6bc4ff")},
	"earth": {"name": "Overgrowth", "mult": 1.2, "effect": "root", "time": 2.0, "power": 1.0, "color": Color("7fe05a")},
	"air": {"name": "Gale", "mult": 1.25, "effect": "stun", "time": 0.7, "power": 1.0, "color": Color("e8f8ff")},
	"mineral": {"name": "Fracture", "mult": 1.4, "effect": "vuln", "time": 3.5, "power": 1.0, "color": Color("d9c7a0")},
	"light": {"name": "Smite", "mult": 1.3, "effect": "stun", "time": 0.8, "power": 1.0, "color": Color("fff3a8")},
	"dark": {"name": "Wither", "mult": 1.3, "effect": "dot", "time": 3.0, "power": 6.0, "color": Color("9a5fd5")},
}

## Martial combo: this many physical hits (slashes, martial skills) on one enemy within
## MARTIAL_CHAIN_TIME seconds of each other trigger "Rend". It never touches the element aura.
const MARTIAL_CHAIN_HITS := 3
const MARTIAL_CHAIN_TIME := 3.0
const MARTIAL_COMBO := {"name": "Rend", "mult": 1.5, "effect": "dot", "time": 3.0, "power": 5.0, "color": Color("e8e8f0")}


func pair_key(a: String, b: String) -> String:
	var pair := [a, b]
	pair.sort()
	return "%s+%s" % pair


## Returns the combo definition for two elements, or {} if there is none.
func resolve(a: String, b: String) -> Dictionary:
	var key := pair_key(a, b)
	return COMBOS.get(key, RARE_COMBOS.get(key, {}))


## One-line description of a combo's payoff, e.g. "x1.4 damage, vulnerable 3s".
## The name and colour a set of locked elements goes by on the HUD: the pair's combo for two
## ("Steam"), "Trio" / "Quartet" / "Prism" for three, four or more (colours blended), the element
## itself for one, and "Lock" for none.
func fusion_label(locked: Array) -> Dictionary:
	match locked.size():
		0:
			return {"name": "Lock", "color": Color(0.5, 0.52, 0.6)}
		1:
			return {"name": String(locked[0]).capitalize(), "color": color_of(String(locked[0]))}
		2:
			var combo := resolve(String(locked[0]), String(locked[1]))
			if not combo.is_empty():
				return {"name": combo["name"], "color": combo["color"]}
	var blend := Color(0, 0, 0)
	for element in locked:
		blend += color_of(String(element))
	blend = Color(blend.r / locked.size(), blend.g / locked.size(), blend.b / locked.size())
	return {"name": {3: "Trio", 4: "Quartet"}.get(locked.size(), "Prism"), "color": blend}


func describe_combo(combo: Dictionary) -> String:
	var effects := {
		"dot": "burning", "slow": "slowed", "root": "rooted", "stun": "stunned",
		"vuln": "takes +25% damage",
	}
	return "x%.1f damage, %s %.1fs" % [float(combo["mult"]), effects[combo["effect"]], float(combo["time"])]


func color_of(id: String) -> Color:
	return COLORS.get(id, Color.WHITE)
