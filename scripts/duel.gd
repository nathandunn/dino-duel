class_name Duel
extends RefCounted
## One duel: two Fighters in a clearing with a few boulders, stepped at a fixed rate. Pure
## simulation - the 3D scene only reads it - so batches and headless runs use this directly.
##
## Ends when one animal dies, can't get up (DOWN_FINISH s permanently down), or runs off; at
## TIME_CAP it goes to a decision on condition (blood, wounds, stamina).

const DT := 1.0 / 30.0
const ARENA_R := 40.0
const TIME_CAP := 180.0
const FLEE_GAP := 30.0

var f: Array[Fighter] = []
var rng := RandomNumberGenerator.new()
var seed_used := 0
var t := 0.0
var over := false
var result := {}
var obstacles: Array = []      # [Vector2 centre, radius]
var events: Array = []          # drained by the view each frame
var log_lines: Array = []       # [t, text, who]
var keep_events := true


func setup(sp_a: String, p_a: Personality, pn_a: String, sp_b: String, p_b: Personality, pn_b: String, seed_v: int = -1) -> void:
	if seed_v < 0:
		rng.randomize()
		seed_v = rng.randi() % 1000000
	seed_used = seed_v
	rng.seed = seed_v
	_make_obstacles()
	var a := Fighter.new()
	a.setup(self, 0, sp_a, p_a, pn_a)
	var b := Fighter.new()
	b.setup(self, 1, sp_b, p_b, pn_b)
	a.opp = b
	b.opp = a
	var off := rng.randf_range(-4.0, 4.0)
	var gap := 15.0 + rng.randf_range(-1.5, 1.5)
	a.pos = Vector2(-gap, off)
	b.pos = Vector2(gap, -off)
	a.heading = atan2(b.pos.y - a.pos.y, b.pos.x - a.pos.x) + rng.randf_range(-0.3, 0.3)
	b.heading = atan2(a.pos.y - b.pos.y, a.pos.x - b.pos.x) + rng.randf_range(-0.3, 0.3)
	a.last_dist = a.dist_to(b)
	b.last_dist = a.last_dist
	a.think_t = rng.randf() * 0.2
	b.think_t = rng.randf() * 0.2
	f = [a, b]


func _make_obstacles() -> void:
	obstacles.clear()
	# a few boulders off the line between the starting points, mirrored so neither end is favoured
	var n := 2 + rng.randi() % 2
	for i in n:
		var a := rng.randf_range(0.5, PI - 0.5)
		var r := rng.randf_range(16.0, 30.0)
		var c := Vector2(cos(a) * r * 0.6, sin(a) * r)
		var rad := rng.randf_range(1.2, 2.6)
		obstacles.append([c, rad])
		obstacles.append([-c, rad])


func emit(e: Dictionary) -> void:
	if keep_events:
		e["t"] = t
		events.append(e)


func log_text(text: String, who: int = -1) -> void:
	log_lines.append([t, text, who])


func log_hit(att: Fighter, def: Fighter, w: Dictionary, zone: String, units: float, arm: float, frac: bool, kd: bool, mult: float) -> void:
	if not keep_events:
		return
	var verb := {"bite": "bites", "hatchet": "slashes", "gore": "gores", "club": "clubs", "thag": "spikes",
		"kick": "rakes", "leap": "lands on", "rake": "claws", "slam": "slams into", "beak": "nips", "stomp": "stomps on"}
	var v: String = verb.get(w.id, "hits")
	if mult > 1.25 and w.get("charge", false):
		v = "charges and gores"
	var sev := "grazes" if units < 0.12 else ""
	var line := "%s %s %s's %s" % [name_of(att), v if sev == "" else sev, name_of(def), Species.ZONES[zone].label]
	if arm > 0.5:
		line += " (armour takes most of it)"
	if frac:
		line += {"head": " - SKULL BREAKS", "neck": " - NECK SNAPS", "chest": " - ribs cave in", "hips": " - PELVIS BREAKS",
			"flank": " - ribs crack", "tail": " - tail breaks", "belly": " - guts torn open"}.get(zone, " - BONE SNAPS")
	if kd:
		line += ", knocked off its feet"
	log_text(line, att.idx)


func name_of(x: Fighter) -> String:
	if f[0].spname == f[1].spname:
		return "%s %s" % [["Red", "Blue"][x.idx], x.spname]
	return x.spname


func step() -> void:
	if over:
		return
	t += DT
	for x in f:
		x.step(DT)
	_collide()
	_check_end()


func _collide() -> void:
	var a := f[0]
	var b := f[1]
	if a.latch.size() > 0 or b.latch.size() > 0:
		return
	for ca in a.foot:
		for cb in b.foot:
			var pa: Vector2 = a.pos + a.fwd() * float(ca[0])
			var pb: Vector2 = b.pos + b.fwd() * float(cb[0])
			var d := pa - pb
			var dl := d.length()
			var minl: float = float(ca[1]) + float(cb[1])
			if dl < minl and dl > 0.001:
				var push := (minl - dl)
				var n := d / dl
				var wa := b.mass / (a.mass + b.mass)
				if not a.alive:
					wa = 0.1
				if not b.alive:
					wa = 0.9
				a.pos += n * push * wa
				b.pos -= n * push * (1.0 - wa)
	for x in f:
		if x.latch.size() > 0:
			continue
		for ob in obstacles:
			for c in x.foot:
				var p: Vector2 = x.pos + x.fwd() * float(c[0])
				var d2: Vector2 = p - ob[0]
				var minl2: float = float(ob[1]) + float(c[1])
				if d2.length() < minl2 and d2.length() > 0.001:
					x.pos += d2.normalized() * (minl2 - d2.length())
		if x.mode != "fleeing" and x.pos.length() > ARENA_R:
			x.pos = x.pos.normalized() * ARENA_R


func _check_end() -> void:
	var a := f[0]
	var b := f[1]
	if not a.alive and not b.alive:
		_finish(-1, "both dead")
		return
	for x in f:
		if not x.alive:
			_finish(x.opp.idx, "killed: " + x.death_cause)
			return
	for x in f:
		if x.down_perm and x.down_for > Fighter.DOWN_FINISH:
			x.alive = false
			x.death_cause = "couldn't rise - finished"
			emit({"type": "dead", "who": x.idx, "cause": x.death_cause})
			_finish(x.opp.idx, "killed: couldn't rise")
			return
	for x in f:
		if x.mode == "fleeing" and (x.dist_to(x.opp) > FLEE_GAP or x.pos.length() > ARENA_R + 6.0):
			x.fled = true
			emit({"type": "fled", "who": x.idx})
			_finish(x.opp.idx, "fled")
			return
	if t >= TIME_CAP:
		var ca := a.condition()
		var cb := b.condition()
		if absf(ca - cb) < 0.04:
			_finish(-1, "time: draw")
		else:
			_finish(0 if ca > cb else 1, "time: decision")


func _finish(w: int, how: String) -> void:
	over = true
	result = {"winner": w, "how": how, "t": t, "seed": seed_used,
		"species": [f[0].spname, f[1].spname], "preset": [f[0].pname, f[1].pname],
		"fighters": [_summary(f[0]), _summary(f[1])]}
	var line := "Draw (%s)" % how if w < 0 else "%s wins - %s" % [name_of(f[w]), how]
	log_text(line, w)
	emit({"type": "over", "winner": w, "how": how})


func _summary(x: Fighter) -> Dictionary:
	return {"species": x.spname, "preset": x.pname, "alive": x.alive, "fled": x.fled, "cause": x.death_cause,
		"blood": x.blood, "stamina": x.stamina, "broken": x.broken.keys(), "stats": x.stats.duplicate(true),
		"zone_hp": x.zone_hp.duplicate(), "travelled": x.travelled, "condition": x.condition()}


## Break the fighter <-> duel reference cycles so they can be freed.
func dispose() -> void:
	for x in f:
		x.opp = null
		x.duel = null
		x.held_by = null
		x.latched_by = null
	f.clear()


## Run to the end without any rendering. Returns the result.
func run_to_end() -> Dictionary:
	keep_events = false
	while not over:
		step()
	return result
