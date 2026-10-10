class_name Personality
extends RefCounted
## How an animal fights. The body (species.gd) says what it CAN do; this says what it WANTS
## to do. Every trait is 0..1 and feeds the utility brain in fighter.gd. Any preset can go on
## any species - a Skittish T. rex and a Berserker Stegosaurus are both allowed.

const TRAITS: Array[String] = ["aggression", "caution", "cunning", "persistence", "nerve", "pacing", "display", "opportunism"]

const TRAIT_HELP := {
	"aggression": "Closes in and attacks on marginal chances instead of waiting for a good one",
	"caution": "Keeps out of the enemy's weapon arcs, dodges, backs off when hurt",
	"cunning": "Circles to the blind side; aims for legs, neck and belly instead of whatever is nearest",
	"persistence": "Hangs on: holds a bite, keeps a pin, stays in close once engaged",
	"nerve": "Shrugs off pain, blood loss and roaring; slow to flee",
	"pacing": "Manages stamina: strikes, backs off, rests, lets the opponent tire and bleed",
	"display": "Roars and postures to frighten the other off before a blow is struck",
	"opportunism": "Pounces on a downed, exhausted, crippled or fleeing opponent",
}

const PRESETS := {
	"Balanced":  {"aggression": 0.5, "caution": 0.5, "cunning": 0.5, "persistence": 0.5, "nerve": 0.5, "pacing": 0.5, "display": 0.4, "opportunism": 0.5},
	"Berserker": {"aggression": 0.95, "caution": 0.1, "cunning": 0.25, "persistence": 0.85, "nerve": 0.95, "pacing": 0.1, "display": 0.35, "opportunism": 0.6},
	"Stalker":   {"aggression": 0.5, "caution": 0.6, "cunning": 0.95, "persistence": 0.3, "nerve": 0.6, "pacing": 0.65, "display": 0.05, "opportunism": 0.9},
	"Bully":     {"aggression": 0.75, "caution": 0.3, "cunning": 0.3, "persistence": 0.6, "nerve": 0.7, "pacing": 0.4, "display": 0.95, "opportunism": 0.5},
	"Bleeder":   {"aggression": 0.45, "caution": 0.75, "cunning": 0.7, "persistence": 0.1, "nerve": 0.55, "pacing": 0.9, "display": 0.2, "opportunism": 0.6},
	"Bulwark":   {"aggression": 0.2, "caution": 0.85, "cunning": 0.5, "persistence": 0.6, "nerve": 0.85, "pacing": 0.8, "display": 0.5, "opportunism": 0.7},
	"Brawler":   {"aggression": 0.8, "caution": 0.35, "cunning": 0.45, "persistence": 0.95, "nerve": 0.8, "pacing": 0.3, "display": 0.2, "opportunism": 0.75},
	"Skittish":  {"aggression": 0.25, "caution": 0.9, "cunning": 0.4, "persistence": 0.2, "nerve": 0.1, "pacing": 0.5, "display": 0.3, "opportunism": 0.4},
}

const PRESET_HELP := {
	"Balanced": "A bit of everything",
	"Berserker": "Never stops coming. Ignores pain and arcs; burns out fast",
	"Stalker": "Circles to the blind side, strikes legs and flanks, pounces when you stumble",
	"Bully": "Roars, postures and pushes in - wants you to quit before it gets bloody",
	"Bleeder": "Hit and run: opens a wound, backs off, rests, lets the blood do the work",
	"Bulwark": "Holds its ground with its weapon pointed at you and counter-strikes",
	"Brawler": "Gets in close and stays there: holds bites, pins, shoves",
	"Skittish": "Fights only when it must and bolts when hurt",
	"Random": "Every trait rolled fresh each duel",
}

const ORDER: Array[String] = ["Balanced", "Berserker", "Stalker", "Bully", "Bleeder", "Bulwark", "Brawler", "Skittish", "Random"]

var t := {}


static func preset(name: String, rng: RandomNumberGenerator = null) -> Personality:
	var p := Personality.new()
	if name == "Random" or not PRESETS.has(name):
		var r := rng
		if r == null:
			r = RandomNumberGenerator.new()
			r.randomize()
		for k in TRAITS:
			p.t[k] = snappedf(r.randf(), 0.05)
		return p
	var src: Dictionary = PRESETS[name]
	for k in TRAITS:
		p.t[k] = float(src.get(k, 0.5))
	return p


static func resolve(name: String) -> String:
	for n in ORDER:
		if n.to_lower() == name.to_lower():
			return n
	return "Custom" if name.to_lower() == "custom" else "Balanced"


func g(k: String) -> float:
	return float(t.get(k, 0.5))


func duplicate_p() -> Personality:
	var p := Personality.new()
	p.t = t.duplicate()
	return p


func describe() -> String:
	var parts: Array[String] = []
	for k in TRAITS:
		parts.append("%s %.2f" % [k.substr(0, 4), g(k)])
	return ", ".join(parts)
