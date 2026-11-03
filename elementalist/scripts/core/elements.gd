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


## Resonance: this many discrete hits of the SAME element in a row (without another element
## breaking the chain) trigger that element's resonance combo, and reset the count.
const RESONANCE_HITS := 3
const RESONANCE := {
	"fire": {"name": "Blaze", "mult": 1.3, "effect": "dot", "time": 3.0, "power": 6.0, "color": Color("ff8a3a")},
	"water": {"name": "Drench", "mult": 1.2, "effect": "slow", "time": 3.0, "power": 0.7, "color": Color("6bc4ff")},
	"earth": {"name": "Overgrowth", "mult": 1.2, "effect": "root", "time": 2.0, "power": 1.0, "color": Color("7fe05a")},
	"air": {"name": "Gale", "mult": 1.25, "effect": "stun", "time": 0.7, "power": 1.0, "color": Color("e8f8ff")},
	"mineral": {"name": "Fracture", "mult": 1.4, "effect": "vuln", "time": 3.5, "power": 1.0, "color": Color("d9c7a0")},
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
	return COMBOS.get(pair_key(a, b), {})


## One-line description of a combo's payoff, e.g. "x1.4 damage, vulnerable 3s".
func describe_combo(combo: Dictionary) -> String:
	var effects := {
		"dot": "burning", "slow": "slowed", "root": "rooted", "stun": "stunned",
		"vuln": "takes +25% damage",
	}
	return "x%.1f damage, %s %.1fs" % [float(combo["mult"]), effects[combo["effect"]], float(combo["time"])]


func color_of(id: String) -> Color:
	return COLORS.get(id, Color.WHITE)
