class_name Species
extends RefCounted
## The six animals. Everything physical lives here: mass, speed, turning, stamina, the body
## plan (which both the simulation's hitboxes and the 3D model are built from, so what you
## see is what gets bitten), armour, and the weapons.
##
## Numbers are rounded from the palaeontology literature - masses after Hutchinson et al.
## 2011 / Campione & Evans 2012, speeds after Sellers et al. 2017 and Hutchinson & Garcia
## 2002, bite after Bates & Falkingham 2012, tail clubs after Arbour 2009, the thagomizer
## after McWhinney et al. 2001 (an Allosaurus vertebra with a spike-shaped hole in it), the
## allosaur "hatchet" bite after Rayfield et al. 2001 and Snively et al. 2013. They are best
## guesses for game purposes, not a claim about which one really won.
##
## Units: metres, kilograms, seconds. Weapon damage is in "damage units": a zone of a
## one-tonne animal with toughness 1 breaks at 1.0. A bigger animal's bones are thicker:
## damage is divided by (mass / 1000)^(1/3).
##
## Directions on the body are (f, u, s): forward, up, right-side.

const ORDER: Array[String] = ["T. rex", "Triceratops", "Ankylosaurus", "Stegosaurus", "Allosaurus", "Utahraptor"]
const SHORT := {"rex": "T. rex", "trex": "T. rex", "trike": "Triceratops", "tri": "Triceratops", "anky": "Ankylosaurus",
	"stego": "Stegosaurus", "allo": "Allosaurus", "raptor": "Utahraptor", "utah": "Utahraptor"}

## Per-zone defaults. tough: divides damage. bleed: how much an open wound there bleeds.
## value: how much a thinking attacker wants to hit it. Effects of a zone reaching 0 hp are
## handled in Fighter._zone_broken.
const ZONES := {
	"head":  {"tough": 1.6, "bleed": 0.6, "value": 0.9, "label": "head"},
	"neck":  {"tough": 1.4,  "bleed": 2.0, "value": 1.0, "label": "neck"},
	"chest": {"tough": 2.2,  "bleed": 1.0, "value": 0.6, "label": "chest"},
	"flank": {"tough": 2.4,  "bleed": 0.9, "value": 0.45, "label": "flank"},
	"belly": {"tough": 1.5,  "bleed": 1.6, "value": 0.65, "label": "belly"},
	"hips":  {"tough": 2.4,  "bleed": 0.7, "value": 0.4, "label": "hips"},
	"tail":  {"tough": 1.3,  "bleed": 0.5, "value": 0.2, "label": "tail"},
	"l_hind": {"tough": 1.15, "bleed": 1.0, "value": 0.55, "label": "left hind leg"},
	"r_hind": {"tough": 1.15, "bleed": 1.0, "value": 0.55, "label": "right hind leg"},
	"l_fore": {"tough": 1.1,  "bleed": 0.9, "value": 0.45, "label": "left foreleg"},
	"r_fore": {"tough": 1.1,  "bleed": 0.9, "value": 0.45, "label": "right foreleg"},
}

## Weapon fields:
##   dmg       base damage units
##   types     share of crush / pierce / slash (armour is per type)
##   origin    which body point it strikes from: head, horns, chest, hips, feet
##   reach     horizontal reach from the origin to the surface of the target zone (m)
##   min       too close to swing (tails need room)
##   arc       [centre, half-width] in degrees, relative to the animal's facing
##   y         [lowest, highest] target height it can reach
##   wind/strike/rec  timings (s); cost: stamina; bleed/fracture/kd: multipliers
##   flags: hold (bite and shake), latch (leap onto the body), charge (momentum bonus),
##          down_only (only against an animal on the ground), rear (a tail weapon)
const DATA := {
	"T. rex": {
		"id": "rex", "era": "Late Cretaceous, Hell Creek (68-66 Ma)",
		"mass": 8000.0, "length": 12.3, "top_speed": 7.5, "accel": 1.7, "turn": 0.95, "agility": 0.22,
		"stamina_drain": 1.15, "recover": 0.045, "kd_resist": 0.5,
		"blurb": "8 t, 12 m, ~27 km/h. The strongest bite of any land animal (35-57 kN, Bates & Falkingham 2012): crushes bone, holds and shakes. Turns slowly; forearms useless.",
		"body": {"biped": true, "torso_len": 4.3, "torso_h": 2.2, "torso_w": 1.75, "hip_h": 3.4, "chest_h": 3.4,
			"neck_len": 1.5, "neck_up": 28.0, "neck_r": 0.62, "head_len": 1.55, "head_h": 0.95, "head_w": 0.85,
			"tail_len": 5.6, "tail_r": 0.75, "leg_r": 0.48, "fore_len": 0.9,
			"color": Color(0.36, 0.30, 0.21), "color2": Color(0.62, 0.55, 0.42), "accent": Color(0.25, 0.18, 0.12)},
		"armour": {},
		"weapons": [
			{"acc": 0.8, "id": "bite", "name": "bite", "dmg": 2.3, "types": {"crush": 0.6, "pierce": 0.4}, "origin": "head",
				"reach": 1.5, "min": 0.0, "arc": [0.0, 38.0], "y": [0.2, 5.2], "wind": 0.42, "strike": 0.15, "rec": 0.95,
				"cost": 0.07, "bleed": 1.0, "fracture": 1.1, "kd": 0.25, "hold": true},
			{"acc": 0.9, "id": "slam", "name": "body slam", "dmg": 0.35, "types": {"crush": 1.0}, "origin": "chest",
				"reach": 1.0, "min": 0.0, "arc": [0.0, 45.0], "y": [0.0, 4.5], "wind": 0.45, "strike": 0.15, "rec": 0.9,
				"cost": 0.05, "bleed": 0.2, "fracture": 0.4, "kd": 0.9},
			{"acc": 0.6, "id": "stomp", "name": "stomp", "dmg": 0.9, "types": {"crush": 1.0}, "origin": "feet",
				"reach": 1.6, "min": 0.0, "arc": [0.0, 35.0], "y": [0.0, 1.3], "wind": 0.4, "strike": 0.15, "rec": 0.8,
				"cost": 0.05, "bleed": 0.4, "fracture": 1.2, "kd": 0.3},
		],
	},
	"Triceratops": {
		"id": "trike", "era": "Late Cretaceous, Hell Creek (68-66 Ma)",
		"mass": 9000.0, "length": 8.5, "top_speed": 7.0, "accel": 1.9, "turn": 1.05, "agility": 0.2,
		"stamina_drain": 1.0, "recover": 0.05, "kd_resist": 0.75,
		"blurb": "9 t, 8.5 m. Two 1 m brow horns driven by a charging rhino-sized body; the frill shields the neck from the front. Bite is a shearing beak - not a weapon.",
		"body": {"biped": false, "torso_len": 3.7, "torso_h": 1.95, "torso_w": 2.05, "hip_h": 2.1, "chest_h": 1.8,
			"neck_len": 0.6, "neck_up": 0.0, "neck_r": 0.7, "head_len": 2.2, "head_h": 1.15, "head_w": 0.9,
			"tail_len": 2.6, "tail_r": 0.55, "leg_r": 0.42, "fore_len": 1.55,
			"frill": 1.05, "horns": 1.0,
			"color": Color(0.33, 0.37, 0.27), "color2": Color(0.55, 0.53, 0.42), "accent": Color(0.62, 0.30, 0.16)},
		"armour": {"head": {"crush": 0.35, "pierce": 0.4, "slash": 0.5}},
		# frill and horn bosses only cover you from the front
		"armour_front": {"arc": 70.0, "zones": {
			"neck": {"crush": 0.5, "pierce": 0.75, "slash": 0.8},
			"head": {"crush": 0.55, "pierce": 0.65, "slash": 0.75},
			"chest": {"crush": 0.25, "pierce": 0.35, "slash": 0.4}}},
		"weapons": [
			{"acc": 0.8, "id": "gore", "name": "horns", "dmg": 1.25, "types": {"pierce": 0.85, "crush": 0.15}, "origin": "horns",
				"reach": 1.0, "min": 0.0, "arc": [0.0, 32.0], "y": [0.2, 3.4], "wind": 0.35, "strike": 0.15, "rec": 0.8,
				"cost": 0.06, "bleed": 1.3, "fracture": 0.55, "kd": 0.5, "charge": true},
			{"acc": 0.8, "id": "beak", "name": "beak", "dmg": 0.3, "types": {"slash": 0.7, "pierce": 0.3}, "origin": "head",
				"reach": 0.5, "min": 0.0, "arc": [0.0, 25.0], "y": [0.0, 2.2], "wind": 0.3, "strike": 0.12, "rec": 0.5,
				"cost": 0.03, "bleed": 1.0, "fracture": 0.1, "kd": 0.0},
			{"acc": 0.9, "id": "slam", "name": "shove", "dmg": 0.35, "types": {"crush": 1.0}, "origin": "chest",
				"reach": 1.0, "min": 0.0, "arc": [0.0, 45.0], "y": [0.0, 4.0], "wind": 0.4, "strike": 0.15, "rec": 0.85,
				"cost": 0.05, "bleed": 0.2, "fracture": 0.4, "kd": 0.9},
		],
	},
	"Ankylosaurus": {
		"id": "anky", "era": "Late Cretaceous, Hell Creek (68-66 Ma)",
		"mass": 6000.0, "length": 7.5, "top_speed": 3.6, "accel": 1.0, "turn": 0.8, "agility": 0.08,
		"stamina_drain": 0.8, "recover": 0.06, "kd_resist": 0.9,
		"blurb": "6 t, 7.5 m. Fused bony armour over head, neck, back and flanks; only the belly is soft, and it is on the ground. A tail club big enough to break bone (Arbour 2009). Slow.",
		"body": {"biped": false, "torso_len": 3.6, "torso_h": 1.45, "torso_w": 2.3, "hip_h": 1.55, "chest_h": 1.35,
			"neck_len": 0.45, "neck_up": 0.0, "neck_r": 0.55, "head_len": 0.65, "head_h": 0.5, "head_w": 0.7,
			"tail_len": 3.2, "tail_r": 0.45, "leg_r": 0.36, "fore_len": 1.15,
			"club": 0.42, "osteoderms": true,
			"color": Color(0.42, 0.36, 0.24), "color2": Color(0.58, 0.50, 0.36), "accent": Color(0.30, 0.25, 0.18)},
		"armour": {
			"head": {"crush": 0.6, "pierce": 0.85, "slash": 0.9},
			"neck": {"crush": 0.55, "pierce": 0.8, "slash": 0.9},
			"chest": {"crush": 0.45, "pierce": 0.75, "slash": 0.85},
			"flank": {"crush": 0.45, "pierce": 0.75, "slash": 0.85},
			"hips": {"crush": 0.45, "pierce": 0.75, "slash": 0.85},
			"tail": {"crush": 0.4, "pierce": 0.7, "slash": 0.8},
			"l_hind": {"crush": 0.15, "pierce": 0.25, "slash": 0.3}, "r_hind": {"crush": 0.15, "pierce": 0.25, "slash": 0.3},
			"l_fore": {"crush": 0.15, "pierce": 0.25, "slash": 0.3}, "r_fore": {"crush": 0.15, "pierce": 0.25, "slash": 0.3}},
		"covered": ["belly"],   # unreachable unless it is knocked over
		"weapons": [
			{"acc": 0.6, "id": "club", "name": "tail club", "dmg": 1.8, "types": {"crush": 1.0}, "origin": "hips",
				"reach": 3.7, "min": 1.4, "arc": [180.0, 62.0], "y": [0.0, 2.6], "wind": 0.5, "strike": 0.2, "rec": 1.25,
				"cost": 0.08, "bleed": 0.4, "fracture": 1.7, "kd": 0.55, "rear": true},
			{"acc": 0.8, "id": "beak", "name": "beak", "dmg": 0.15, "types": {"slash": 0.6, "pierce": 0.4}, "origin": "head",
				"reach": 0.4, "min": 0.0, "arc": [0.0, 25.0], "y": [0.0, 1.5], "wind": 0.3, "strike": 0.12, "rec": 0.5,
				"cost": 0.02, "bleed": 0.8, "fracture": 0.0, "kd": 0.0},
		],
	},
	"Stegosaurus": {
		"id": "stego", "era": "Late Jurassic, Morrison Formation (155-145 Ma)",
		"mass": 5000.0, "length": 9.0, "top_speed": 4.6, "accel": 1.2, "turn": 0.85, "agility": 0.14,
		"stamina_drain": 0.9, "recover": 0.055, "kd_resist": 0.6,
		"blurb": "5 t, 9 m. Four 60-90 cm tail spikes (the thagomizer) swung sideways; an Allosaurus vertebra with a spike-shaped hole shows it worked. Plates are display, not armour.",
		"body": {"biped": false, "torso_len": 3.7, "torso_h": 1.9, "torso_w": 1.5, "hip_h": 2.6, "chest_h": 1.45,
			"neck_len": 1.25, "neck_up": -12.0, "neck_r": 0.36, "head_len": 0.5, "head_h": 0.3, "head_w": 0.3,
			"tail_len": 4.0, "tail_r": 0.5, "leg_r": 0.36, "fore_len": 1.2,
			"plates": true, "spikes": 0.8,
			"color": Color(0.32, 0.36, 0.24), "color2": Color(0.56, 0.54, 0.40), "accent": Color(0.70, 0.40, 0.18)},
		"armour": {"neck": {"crush": 0.1, "pierce": 0.3, "slash": 0.35}, "flank": {"crush": 0.05, "pierce": 0.15, "slash": 0.2},
			"hips": {"crush": 0.05, "pierce": 0.15, "slash": 0.2}},
		"weapons": [
			{"acc": 0.62, "id": "thag", "name": "thagomizer", "dmg": 1.15, "types": {"pierce": 1.0}, "origin": "hips",
				"reach": 4.3, "min": 1.6, "arc": [180.0, 68.0], "y": [0.2, 3.2], "wind": 0.42, "strike": 0.16, "rec": 1.05,
				"cost": 0.07, "bleed": 1.7, "fracture": 0.65, "kd": 0.15, "rear": true},
			{"acc": 0.8, "id": "beak", "name": "beak", "dmg": 0.1, "types": {"slash": 0.6, "pierce": 0.4}, "origin": "head",
				"reach": 0.35, "min": 0.0, "arc": [0.0, 25.0], "y": [0.0, 1.5], "wind": 0.3, "strike": 0.12, "rec": 0.5,
				"cost": 0.02, "bleed": 0.8, "fracture": 0.0, "kd": 0.0},
		],
	},
	"Allosaurus": {
		"id": "allo", "era": "Late Jurassic, Morrison Formation (155-145 Ma)",
		"mass": 2000.0, "length": 9.0, "top_speed": 9.0, "accel": 2.6, "turn": 1.8, "agility": 0.45,
		"stamina_drain": 1.0, "recover": 0.06, "kd_resist": 0.3,
		"blurb": "2 t, 9 m, quick. A weak bite (~3-8 kN) but a wide gape used like a hatchet: slashing, bleeding wounds rather than crushed bone. Three-clawed arms that can rake.",
		"body": {"biped": true, "torso_len": 2.7, "torso_h": 1.3, "torso_w": 1.0, "hip_h": 2.4, "chest_h": 2.4,
			"neck_len": 1.1, "neck_up": 32.0, "neck_r": 0.34, "head_len": 0.95, "head_h": 0.55, "head_w": 0.4,
			"tail_len": 4.3, "tail_r": 0.42, "leg_r": 0.27, "fore_len": 0.8, "crests": true,
			"color": Color(0.55, 0.44, 0.30), "color2": Color(0.78, 0.70, 0.55), "accent": Color(0.55, 0.20, 0.14)},
		"armour": {},
		"weapons": [
			{"acc": 0.85, "id": "hatchet", "name": "hatchet bite", "dmg": 0.85, "types": {"slash": 0.8, "pierce": 0.2}, "origin": "head",
				"reach": 1.25, "min": 0.0, "arc": [0.0, 38.0], "y": [0.2, 4.0], "wind": 0.3, "strike": 0.12, "rec": 0.55,
				"cost": 0.05, "bleed": 1.35, "fracture": 0.2, "kd": 0.05},
			{"acc": 0.8, "id": "rake", "name": "claw rake", "dmg": 0.35, "types": {"slash": 1.0}, "origin": "chest",
				"reach": 0.8, "min": 0.0, "arc": [0.0, 40.0], "y": [0.5, 2.8], "wind": 0.25, "strike": 0.12, "rec": 0.45,
				"cost": 0.035, "bleed": 1.3, "fracture": 0.0, "kd": 0.0},
		],
	},
	"Utahraptor": {
		"id": "raptor", "era": "Early Cretaceous, Cedar Mountain (~135 Ma)",
		"mass": 500.0, "length": 6.0, "top_speed": 8.5, "accel": 4.0, "turn": 3.5, "agility": 0.8,
		"stamina_drain": 1.1, "recover": 0.07, "kd_resist": 0.15,
		"blurb": "500 kg, 6 m, feathered. A 22 cm sickle claw on each foot; it leaps onto prey, pins and kicks. Nimble, but one bite from anything big ends it.",
		"body": {"biped": true, "torso_len": 1.6, "torso_h": 0.85, "torso_w": 0.6, "hip_h": 1.5, "chest_h": 1.5,
			"neck_len": 0.7, "neck_up": 38.0, "neck_r": 0.2, "head_len": 0.6, "head_h": 0.32, "head_w": 0.24,
			"tail_len": 3.0, "tail_r": 0.22, "leg_r": 0.17, "fore_len": 0.9, "feathers": true,
			"color": Color(0.52, 0.30, 0.17), "color2": Color(0.80, 0.68, 0.50), "accent": Color(0.18, 0.14, 0.12)},
		"armour": {},
		"weapons": [
			{"acc": 0.7, "id": "leap", "name": "leap", "dmg": 0.4, "types": {"slash": 0.6, "pierce": 0.4}, "origin": "chest",
				"reach": 5.5, "min": 2.2, "arc": [0.0, 25.0], "y": [0.3, 4.2], "wind": 0.4, "strike": 0.35, "rec": 1.2,
				"cost": 0.12, "bleed": 1.4, "fracture": 0.0, "kd": 0.2, "latch": true},
			{"acc": 0.8, "id": "kick", "name": "sickle kick", "dmg": 0.6, "types": {"slash": 0.7, "pierce": 0.3}, "origin": "feet",
				"reach": 1.2, "min": 0.0, "arc": [0.0, 40.0], "y": [0.0, 1.9], "wind": 0.25, "strike": 0.12, "rec": 0.5,
				"cost": 0.05, "bleed": 1.7, "fracture": 0.1, "kd": 0.05},
			{"acc": 0.8, "id": "bite", "name": "bite", "dmg": 0.3, "types": {"slash": 0.5, "pierce": 0.5}, "origin": "head",
				"reach": 0.8, "min": 0.0, "arc": [0.0, 30.0], "y": [0.2, 2.6], "wind": 0.25, "strike": 0.1, "rec": 0.45,
				"cost": 0.03, "bleed": 1.2, "fracture": 0.05, "kd": 0.0},
		],
	},
}


static func resolve(name: String) -> String:
	if DATA.has(name):
		return name
	var k := name.to_lower().replace(" ", "").replace(".", "")
	if SHORT.has(k):
		return SHORT[k]
	for n in ORDER:
		if n.to_lower().replace(" ", "").replace(".", "") == k:
			return n
	return "T. rex"


static func get_data(name: String) -> Dictionary:
	return DATA[resolve(name)]


## Key body points in the animal's own frame (f, u, s) as Vector3(f, u, s).
static func points(b: Dictionary) -> Dictionary:
	var tl: float = b.torso_len
	var biped: bool = b.biped
	var hip_y: float = b.hip_h
	var sh_y: float = b.chest_h if not biped else hip_y + 0.05
	var cy: float = (hip_y + sh_y) * 0.5 + (0.0 if biped else b.torso_h * 0.12)
	var p := {}
	p["torso"] = Vector3(0, cy, 0)
	p["hip"] = Vector3(-tl * 0.3, hip_y, 0)
	p["shoulder"] = Vector3(tl * 0.3, sh_y, 0)
	var nb := Vector3(tl * 0.46, (hip_y + b.torso_h * 0.22) if biped else (sh_y + b.torso_h * 0.15), 0)
	p["neck_base"] = nb
	var up := deg_to_rad(float(b.neck_up))
	var ne := nb + Vector3(cos(up), sin(up), 0) * float(b.neck_len)
	p["neck_end"] = ne
	p["head"] = ne + Vector3(float(b.head_len) * 0.42, 0.0 if biped else -float(b.head_h) * 0.15, 0)
	p["snout"] = ne + Vector3(float(b.head_len) * 0.95, 0, 0)
	p["horns"] = ne + Vector3(float(b.head_len) * 0.55, float(b.head_h) * 0.55, 0) if b.has("horns") else p["snout"]
	var tb := Vector3(-tl * 0.5, hip_y + (0.0 if biped else b.torso_h * 0.05), 0)
	p["tail_base"] = tb
	p["tail_end"] = Vector3(tb.x - float(b.tail_len), tb.y * (0.72 if biped else 0.45), 0)
	p["feet"] = Vector3(-tl * 0.3 + (0.6 if biped else 0.0), 0.35, 0) if biped else Vector3(tl * 0.3, 0.3, 0)
	return p


## Hitbox spheres: [{zone, c: Vector3(f,u,s), r}]. Some zones have more than one sphere.
static func hitboxes(b: Dictionary) -> Array:
	var p := points(b)
	var tl: float = b.torso_len
	var th: float = b.torso_h
	var tw: float = b.torso_w
	var cy: float = p.torso.y
	var m := minf(th, tw)
	var hb: Array = []
	hb.append({"zone": "head", "c": p.head, "r": maxf(float(b.head_h), float(b.head_w)) * 0.55 + float(b.head_len) * 0.15})
	hb.append({"zone": "neck", "c": (p.neck_base + p.neck_end) * 0.5, "r": float(b.neck_r) * 1.1})
	hb.append({"zone": "chest", "c": Vector3(tl * 0.28, cy + (p.shoulder.y - cy) * 0.4, 0), "r": m * 0.5})
	hb.append({"zone": "flank", "c": Vector3(0, cy, 0), "r": m * 0.56})
	hb.append({"zone": "hips", "c": Vector3(-tl * 0.3, cy + (p.hip.y - cy) * 0.4, 0), "r": m * 0.5})
	hb.append({"zone": "belly", "c": Vector3(tl * 0.04, cy - th * 0.33, 0), "r": th * 0.3})
	var tb: Vector3 = p.tail_base
	var te: Vector3 = p.tail_end
	hb.append({"zone": "tail", "c": tb.lerp(te, 0.25), "r": float(b.tail_r) * 0.95})
	hb.append({"zone": "tail", "c": tb.lerp(te, 0.62), "r": float(b.tail_r) * 0.6})
	var hx: float = -tl * 0.3
	var leg_r: float = b.leg_r
	hb.append({"zone": "l_hind", "c": Vector3(hx, b.hip_h * 0.45, -tw * 0.36), "r": leg_r * 1.25})
	hb.append({"zone": "r_hind", "c": Vector3(hx, b.hip_h * 0.45, tw * 0.36), "r": leg_r * 1.25})
	if not b.biped:
		hb.append({"zone": "l_fore", "c": Vector3(tl * 0.3, b.chest_h * 0.45, -tw * 0.38), "r": leg_r * 1.2})
		hb.append({"zone": "r_fore", "c": Vector3(tl * 0.3, b.chest_h * 0.45, tw * 0.38), "r": leg_r * 1.2})
	return hb


## Collision footprint: two circles on the long axis, [f, radius].
static func footprint(b: Dictionary) -> Array:
	var tl: float = b.torso_len
	var r: float = float(b.torso_w) * 0.55 + 0.1
	return [[tl * 0.3, r], [-tl * 0.3, r]]


static func zone_list(b: Dictionary) -> Array[String]:
	var z: Array[String] = ["head", "neck", "chest", "flank", "belly", "hips", "tail", "l_hind", "r_hind"]
	if not b.biped:
		z.append_array(["l_fore", "r_fore"])
	return z
