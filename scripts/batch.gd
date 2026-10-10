class_name Batch
extends RefCounted
## Adds up a run of duels into one summary: win rates (with a 1-sigma band), how they ended,
## and per-side weapon and wound statistics.

var n := 0
var wins := [0, 0]
var draws := 0
var how := {}
var t_sum := 0.0
var side := [{}, {}]
var species := ["", ""]
var preset := ["", ""]


func _init() -> void:
	for s in 2:
		side[s] = {"weapons": {}, "taken": {}, "breaks": {}, "holds": 0, "latches": 0, "charges": 0, "roars": 0,
			"kd_dealt": 0, "dodges": 0, "fled": 0, "died": 0, "blood_end": 0.0, "exhausted_s": 0.0, "dmg": 0.0,
			"causes": {}}


func add(r: Dictionary) -> void:
	n += 1
	var w: int = r.winner
	if w < 0:
		draws += 1
	else:
		wins[w] += 1
	how[r.how] = int(how.get(r.how, 0)) + 1
	t_sum += float(r.t)
	for s in 2:
		var fd: Dictionary = r.fighters[s]
		species[s] = fd.species
		preset[s] = fd.preset
		var sd: Dictionary = side[s]
		var st: Dictionary = fd.stats
		for wid in st.attacks:
			var a: Dictionary = st.attacks[wid]
			if not sd.weapons.has(wid):
				sd.weapons[wid] = {"name": a.name, "tries": 0, "hits": 0, "dodged": 0, "missed": 0, "dmg": 0.0}
			var acc: Dictionary = sd.weapons[wid]
			for k in ["tries", "hits", "dodged", "missed"]:
				acc[k] += int(a[k])
			acc.dmg += float(a.dmg)
		for z in st.taken:
			sd.taken[z] = float(sd.taken.get(z, 0.0)) + float(st.taken[z])
		for z in fd.broken:
			sd.breaks[z] = int(sd.breaks.get(z, 0)) + 1
		for k in ["holds", "latches", "charges", "roars", "kd_dealt", "dodges"]:
			sd[k] += int(st[k])
		sd.dmg += float(st.dmg_dealt)
		sd.exhausted_s += float(st.exhausted_s)
		sd.blood_end += float(fd.blood)
		if fd.fled:
			sd.fled += 1
		if not fd.alive:
			sd.died += 1
			sd.causes[fd.cause] = int(sd.causes.get(fd.cause, 0)) + 1


func win_pct(s: int) -> float:
	return 100.0 * (wins[s] + 0.5 * draws) / maxf(1.0, n)


## 1-sigma band on a win rate, in percentage points.
func sigma() -> float:
	return 100.0 * sqrt(0.25 / maxf(1.0, n))


func summary() -> Dictionary:
	return {"n": n, "wins": wins, "draws": draws, "how": how, "avg_t": t_sum / maxf(1.0, n), "side": side,
		"species": species, "preset": preset, "win_pct": [win_pct(0), win_pct(1)], "sigma": sigma()}


func one_line() -> String:
	return "%s (%s) %d - %d %s (%s), %d draws, n=%d, avg %.0fs | A %.0f%% +-%.0f" % [species[0], preset[0], wins[0], wins[1],
		species[1], preset[1], draws, n, t_sum / maxf(1.0, n), win_pct(0), sigma()]
