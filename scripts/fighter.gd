class_name Fighter
extends RefCounted
## One animal in a duel: body state (blood, bleeding, per-zone damage, fractures, stamina,
## shock, fear), movement, the action in progress, and the brain that picks what to do.
## Pure simulation - no nodes, no rendering - so a hundred duels run in a blink and the
## headless sims use exactly the code the browser does. fighter_view.gd draws it.

const THINK_DT := 0.2
const DOWN_FINISH := 12.0     # permanently down this long = can't rise, beaten
const BLED_OUT := 0.6         # blood fraction at which it collapses and dies

var duel                       # Duel (untyped: cyclic reference)
var idx := 0
var spname := ""
var sp: Dictionary
var body: Dictionary
var hb_local: Array
var foot: Array
var pers: Personality
var pname := ""
var opp: Fighter
var mass := 1000.0
var size_k := 1.0

# kinematics
var pos := Vector2.ZERO
var heading := 0.0
var speed := 0.0               # along heading, m/s (negative = backing up)
var side_v := 0.0              # sideways shuffle (dodges), m/s
var y_off := 0.0
var travelled := 0.0
var turn_rate_now := 0.0

# body
var blood := 1.0
var bleed := 0.0               # blood fraction per second
var zone_hp := {}
var broken := {}               # zone -> true
var stamina := 1.0
var shock := 0.0
var fear := 0.0
var fear_spike := 0.0
var stun := 0.0
var down := 0.0
var down_perm := false
var down_for := 0.0
var alive := true
var fled := false
var death_cause := ""
var dying := -1.0
var exhausted := false

# action / brain
var act := {}                  # {w, phase: wind|strike|rec, t, zone, mult}
var cool := {}
var plan := {"kind": "hold"}
var mode := "size up"
var think_t := 0.0
var commit := 0.0              # reaction delay accumulator
var retreat_t := 0.0
var rest := false
var roar_cd := 3.0
var dodge_cd := 0.0
var hold := {}                 # this animal is biting and holding: {zone, t, tick}
var latch := {}                # this animal is clinging to the other: {zone, t, tick, off}
var held_by: Fighter = null
var latched_by: Fighter = null
var charging := false
var last_dist := 99.0
var orbit_dir := 0.0
var stats := {}
var last_units := 0.0
var att_w := {}


func setup(d, i: int, species_name: String, p: Personality, preset_name: String) -> void:
	duel = d
	idx = i
	spname = Species.resolve(species_name)
	sp = Species.get_data(spname)
	body = sp.body
	hb_local = Species.hitboxes(body)
	foot = Species.footprint(body)
	pers = p
	pname = preset_name
	mass = float(sp.mass)
	size_k = pow(mass / 1000.0, 1.0 / 3.0)
	for z in Species.zone_list(body):
		zone_hp[z] = 1.0
	stats = {"attacks": {}, "taken": {}, "fractures": [], "roars": 0, "holds": 0, "latches": 0, "charges": 0,
		"kd_dealt": 0, "kd_taken": 0, "exhausted_s": 0.0, "max_fear": 0.0, "dodges": 0, "dmg_dealt": 0.0, "bled_s": 0.0}
	for w in sp.weapons:
		stats.attacks[w.id] = {"name": w.name, "tries": 0, "hits": 0, "dodged": 0, "missed": 0, "dmg": 0.0}


# ---------------------------------------------------------------- geometry

func fwd() -> Vector2:
	return Vector2(cos(heading), sin(heading))


func right() -> Vector2:
	return Vector2(-sin(heading), cos(heading))


func lying() -> bool:
	return down > 0.0 or not alive


## Body point (f, u, s) -> world (x, y, z). Lying animals are squashed onto the ground.
func to_world(l: Vector3) -> Vector3:
	var u := l.y
	if lying():
		u = l.y * 0.42 + 0.15
	var p2 := pos + fwd() * l.x + right() * l.z
	return Vector3(p2.x, u + y_off, p2.y)


func zones_world() -> Array:
	var out: Array = []
	var cov: Array = sp.get("covered", [])
	for h in hb_local:
		if cov.has(h.zone) and down <= 0.0 and alive:
			continue
		out.append({"zone": h.zone, "c": to_world(h.c), "r": float(h.r)})
	return out


func point(name: String) -> Vector3:
	return to_world(Species.points(body)[name])


func dist_to(o: Fighter) -> float:
	return pos.distance_to(o.pos)


## Bearing of a world point from this animal, relative to its facing, degrees in (-180, 180].
func bearing(p: Vector2) -> float:
	var d := p - pos
	return rad_to_deg(wrapf(atan2(d.y, d.x) - heading, -PI, PI))


## Where this animal sits around the other, in the other's frame: 0 = in front of it.
func phi_around(o: Fighter) -> float:
	return o.bearing(pos)


## Furthest the other's body reaches in direction phi (its frame), used to stand off it.
static func extent(f: Fighter, phi_deg: float) -> float:
	var d := Vector2(cos(deg_to_rad(phi_deg)), sin(deg_to_rad(phi_deg)))
	var best := 0.5
	for h in f.hb_local:
		var c: Vector3 = h.c
		best = maxf(best, c.x * d.x + c.z * d.y + float(h.r) * 0.6)
	return best


# ---------------------------------------------------------------- per tick

func step(dt: float) -> void:
	if not alive:
		speed = move_toward(speed, 0.0, 6.0 * dt)
		return
	_physiology(dt)
	if not alive or fled:
		return
	for k in cool.keys():
		cool[k] = maxf(0.0, cool[k] - dt)
	roar_cd -= dt
	dodge_cd -= dt
	retreat_t -= dt
	stun = maxf(0.0, stun - dt)
	if down > 0.0:
		down_for += dt
		if not down_perm:
			down -= dt
			if down <= 0.0:
				if stamina > 0.04:
					stamina = maxf(0.0, stamina - 0.06)
					duel.emit({"type": "up", "who": idx})
				else:
					down = 0.3
	else:
		down_for = 0.0
	if latch.size() > 0:
		_latched_step(dt)
		return
	if hold.size() > 0:
		_hold_step(dt)
	if act.size() > 0:
		_act_step(dt)
	think_t -= dt
	if think_t <= 0.0:
		think_t = THINK_DT
		think()
	if act.is_empty() and down <= 0.0 and stun <= 0.0 and hold.is_empty() and held_by == null:
		_try_attack(dt)
	_move(dt)


func _physiology(dt: float) -> void:
	# bleeding: wounds clot slowly; exertion keeps them open
	if bleed > 0.0:
		var lost := bleed * dt
		blood -= lost
		stats.bled_s += lost
		bleed *= exp(-dt * (0.018 - 0.008 * clampf(absf(speed) / float(sp.top_speed), 0.0, 1.0)))
		if bleed < 0.0002:
			bleed = 0.0
	if blood <= BLED_OUT:
		_die("bled out")
		return
	if dying > 0.0:
		dying -= dt
		if dying <= 0.0:
			_die(death_cause if death_cause != "" else "mortal wound")
			return
	# stamina: running above a trot and holding on cost; rest pays back. Blood loss and
	# broken ribs cap how far it can recover.
	var cap := clampf(1.0 - (1.0 - blood) * 1.2, 0.2, 1.0) * (0.55 if broken.has("flank") else 1.0)
	var effort := maxf(0.0, absf(speed) / float(sp.top_speed) - 0.42) * 0.11 * float(sp.stamina_drain)
	if hold.size() > 0 or latch.size() > 0:
		effort += 0.05
	if held_by != null or latched_by != null:
		effort += 0.03
	if effort > 0.0:
		stamina -= effort * dt
	elif act.is_empty():
		var rec: float = float(sp.recover) * (1.0 if absf(speed) < float(sp.top_speed) * 0.3 else 0.4)
		stamina += rec * dt
	stamina = clampf(stamina, 0.0, cap)
	if stamina < 0.12:
		exhausted = true
	elif stamina > 0.3:
		exhausted = false
	if exhausted:
		stats.exhausted_s += dt
	shock = maxf(0.0, shock - dt * 0.07)
	# fear: a floor from what has happened to it, plus spikes that fade
	var nerve := pers.g("nerve")
	var floor_f := (1.0 - blood) * 1.3 * (1.15 - nerve) + broken.size() * 0.07 * (1.2 - nerve) + shock * 0.25
	if opp != null and opp.alive and dist_to(opp) < 15.0:
		var ratio := opp.mass / mass
		if ratio > 2.0:
			fear_spike += dt * 0.012 * clampf(log(ratio) / log(2.0) - 1.0, 0.0, 4.0) * (1.05 - nerve)
	fear_spike = maxf(0.0, fear_spike - dt * 0.025 * (0.5 + nerve))
	fear = clampf(floor_f + fear_spike, 0.0, 1.0)
	stats.max_fear = maxf(stats.max_fear, fear)


func flee_threshold() -> float:
	return 0.42 + 0.5 * pers.g("nerve") - 0.15 * pers.g("caution")


func top_speed_now() -> float:
	var s: float = float(sp.top_speed)
	var legs := 0
	for z in ["l_hind", "r_hind", "l_fore", "r_fore"]:
		if broken.has(z):
			legs += 1
	if legs > 0:
		s *= 0.33
	if broken.has("hips"):
		s *= 0.4
	s *= 0.45 + 0.55 * clampf(stamina / 0.35, 0.0, 1.0)
	s *= clampf((blood - BLED_OUT) / 0.25, 0.35, 1.0)
	return s


func crippled() -> bool:
	return down_perm or top_speed_now() < float(sp.top_speed) * 0.35


func vulnerable() -> bool:
	return down > 0.0 or exhausted or crippled() or stun > 0.0 or latched_by != null or held_by != null


# ---------------------------------------------------------------- brain

func think() -> void:
	var o := opp
	if o == null:
		return
	var d := dist_to(o)
	var approach_rate := (last_dist - d) / THINK_DT
	last_dist = d
	if not o.alive or o.fled:
		plan = {"kind": "hold", "face": "front"}
		mode = "victorious"
		return
	if down > 0.0:
		mode = "down"
		return
	if latch.size() > 0 or hold.size() > 0:
		mode = "holding on" if hold.size() > 0 else "clinging, kicking"
		return
	if held_by != null:
		mode = "in its jaws"
		return
	if latched_by != null:
		mode = "shaking it off"
		plan = {"kind": "hold", "face": "none"}
		return
	if act.size() > 0:
		return
	var vuln := o.vulnerable()
	var opp_threat_now: bool = o.act.size() > 0 and o.act.phase == "wind"

	# -- dodge an incoming blow it can see coming
	if opp_threat_now and dodge_cd <= 0.0 and o.act.has("w") and not o.act.w.has("roar"):
		var aware := absf(bearing(o.pos)) < 110.0 or pers.g("caution") > 0.6
		if aware and duel.rng.randf() < float(sp.agility) * (0.35 + 0.6 * pers.g("caution")) * (0.4 + 0.6 * stamina):
			var away := (pos - o.pos).normalized()
			side_v = (1.0 if right().dot(away) >= 0.0 else -1.0) * (2.0 + 5.0 * float(sp.agility))
			speed = minf(speed, 0.0) - 1.5 * float(sp.agility)
			dodge_cd = 1.2
			stats.dodges += 1

	# -- flee?
	var fth := flee_threshold()
	if fear > fth or (mode == "fleeing" and fear > fth - 0.12):
		mode = "fleeing"
		charging = false
		plan = {"kind": "flee"}
		if not stats.has("fled_once"):
			stats["fled_once"] = true
			duel.emit({"type": "flee", "who": idx})
		return
	# -- the other one is running away: chase or let it go
	if o.mode == "fleeing":
		var chase := pers.g("aggression") * 0.6 + pers.g("opportunism") * 0.7 + (0.3 if o.crippled() else 0.0)
		if chase > 0.75 and stamina > 0.3 and top_speed_now() > o.top_speed_now() * 0.8:
			mode = "chasing"
			plan = {"kind": "chase"}
		else:
			mode = "letting it go"
			plan = {"kind": "hold", "face": "front"}
		return
	# -- display
	if roar_cd <= 0.0 and d > 7.0 and d < 28.0 and not vuln and duel.rng.randf() < pers.g("display") * 0.22:
		_start_roar()
		return
	# -- rest when blown (if the other isn't on top of it)
	var low := 0.15 + 0.25 * pers.g("pacing")
	if stamina < low and d > 5.0 and not vuln:
		rest = true
	if rest and (stamina > 0.4 + 0.35 * pers.g("pacing") or d < 5.0 or vuln):
		rest = false
	if rest:
		mode = "resting"
		charging = false
		plan = {"kind": "away", "d": 16.0 + 6.0 * pers.g("caution"), "walk": true}
		return
	# -- hit and run
	if retreat_t > 0.0 and not vuln:
		mode = "backing off"
		plan = {"kind": "away", "d": 8.0 + 5.0 * pers.g("caution"), "walk": false}
		return
	# -- choose a weapon and a position
	var wp := _pick_weapon(vuln)
	if wp.is_empty():
		mode = "circling"
		plan = {"kind": "orbit", "phi": phi_around(o) + 30.0, "d": 8.0, "face": "front"}
		return
	var w: Dictionary = wp.w
	var rear: bool = w.get("rear", false)
	# a tail fighter mostly waits for the enemy to walk into the club
	if rear:
		var wait := pers.g("caution") * 0.7 + pers.g("pacing") * 0.3 - pers.g("aggression") * 0.5 + 0.25
		var dpref := absf(_origin_local(w).x) + float(w.reach) * 0.55 + extent(o, phi_around(o))
		if vuln and pers.g("opportunism") > 0.4:
			wait = 0.0
		if d < dpref + 7.0 and wait > 0.25:
			mode = "tail to it, waiting"
			plan = {"kind": "hold", "face": "rear"}
			if d < dpref - 0.4:
				plan = {"kind": "orbit", "phi": phi_around(o), "d": dpref, "face": "rear"}
			return
		mode = "backing in, tail first" if d < 14.0 else "closing"
		plan = {"kind": "orbit", "phi": _best_phi(w, vuln), "d": dpref, "face": "rear"}
		return
	# -- the charge
	if w.get("charge", false) and not charging and d > 8.0 and d < 24.0 and absf(bearing(o.pos)) < 25.0 \
			and stamina > 0.45 and not crippled() and duel.rng.randf() < 0.12 + 0.5 * pers.g("aggression"):
		charging = true
		stats.charges += 1
		duel.emit({"type": "charge", "who": idx})
	if charging:
		if d > 28.0 or absf(bearing(o.pos)) > 45.0 or stamina < 0.15:
			charging = false
		else:
			mode = "charging"
			plan = {"kind": "chase", "lead": 0.6}
			return
	var phi := _best_phi(w, vuln)
	var of: float = _origin_local(w).x
	var dgoal := of + extent(o, phi) + float(w.reach) * 0.55
	mode = "pressing" if vuln else ("flanking" if absf(wrapf(phi - phi_around(o), -180.0, 180.0)) > 45.0 else "closing")
	if pers.g("caution") > 0.6 and not vuln and o.act.is_empty() and d > dgoal + 4.0 and approach_rate < -0.5:
		mode = "holding ground"
		plan = {"kind": "hold", "face": "front"}
		return
	plan = {"kind": "orbit", "phi": phi, "d": dgoal, "face": "front"}


## Which weapon to fight with: best reachable value with the other where it is now.
func _pick_weapon(vuln: bool) -> Dictionary:
	var best := {}
	var best_v := -1.0
	for w in sp.weapons:
		if broken.has("tail") and w.get("rear", false):
			continue
		if broken.has("jaw") and w.origin == "head" and sp.weapons.size() > 1 and w == sp.weapons[0] and not w.get("charge", false):
			pass
		var v: float = float(w.dmg) * (1.0 + float(w.bleed) * 0.3 + float(w.fracture) * 0.3)
		if w.has("latch") and opp.mass < mass * 1.2:
			v *= 0.5
		if w.id == "stomp" and not opp.lying() and opp.mass > mass * 0.3:
			v *= 0.05
		if w.id == "slam":
			v *= 0.6 if opp.mass < mass * 1.3 else 0.25
		if v > best_v:
			best_v = v
			best = {"w": w, "v": v}
	return best


## Best angle around the other to attack from (in its frame), weighing what this weapon can
## reach there against the other's weapons that cover that angle.
func _best_phi(w: Dictionary, vuln: bool) -> float:
	var o := opp
	var cur := phi_around(o)
	var cunning := pers.g("cunning")
	var w_threat := clampf(0.3 + 1.1 * pers.g("caution") - 0.5 * pers.g("aggression"), 0.05, 1.5)
	if vuln:
		w_threat *= 0.3
	var best := cur
	var best_u := -INF
	for k in 16:
		var phi := -180.0 + k * 22.5
		var u := _access_value(o, phi, w) * (0.6 + 0.8 * cunning)
		u -= w_threat * _threat_at(o, phi)
		var dphi := absf(wrapf(phi - cur, -180.0, 180.0))
		u -= dphi / 180.0 * (0.9 - 0.6 * cunning)
		if u > best_u:
			best_u = u
			best = phi
	return best


func _access_value(o: Fighter, phi: float, w: Dictionary) -> float:
	var dir := Vector2(cos(deg_to_rad(phi)), sin(deg_to_rad(phi)))
	var v := 0.0
	var yr: Array = w.y
	for h in o.hb_local:
		var c: Vector3 = h.c
		var facing := (c.x * dir.x + c.z * dir.y) / maxf(0.5, Vector2(c.x, c.z).length())
		if facing < 0.15 and Vector2(c.x, c.z).length() > 1.0:
			continue
		var y := c.y * (0.42 if o.lying() else 1.0)
		if y < float(yr[0]) - 0.3 or y > float(yr[1]) + 0.3:
			continue
		if o.sp.get("covered", []).has(h.zone) and not o.lying():
			continue
		var zv := zone_value(o, h.zone)
		var arm := o.armour_vs(h.zone, w.types, phi)
		v = maxf(v, zv * (1.0 - arm))
	return v


func _threat_kind(o: Fighter, phi: float) -> String:
	var kind := ""
	var best := 0.0
	for w in o.sp.weapons:
		var a: Array = w.arc
		if absf(wrapf(phi - float(a[0]), -180.0, 180.0)) <= float(a[1]) + 15.0 and float(w.dmg) > best:
			best = float(w.dmg)
			kind = "rear" if w.get("rear", false) else "front"
	return kind


## How much this animal wants to hit that zone: legs, neck and belly appeal to the cunning;
## a zone that is already broken is mostly wasted; a downed animal's neck and head are the kill.
func zone_value(o: Fighter, zone: String) -> float:
	var v: float = float(Species.ZONES[zone].value)
	if zone in ["l_hind", "r_hind", "l_fore", "r_fore", "neck", "belly"]:
		v *= 0.6 + 0.8 * pers.g("cunning")
	if o.broken.has(zone) or float(o.zone_hp.get(zone, 1.0)) <= 0.0:
		v *= 0.12
	if o.down_perm or (o.lying() and pers.g("opportunism") > 0.3):
		if zone in ["neck", "head"]:
			v *= 2.2
		elif zone in ["l_hind", "r_hind", "l_fore", "r_fore", "tail"]:
			v *= 0.3
	return v


## How dangerous it is to stand at phi around o (o's frame).
func _threat_at(o: Fighter, phi: float) -> float:
	var t := 0.0
	for w in o.sp.weapons:
		if o.broken.has("tail") and w.get("rear", false):
			continue
		var a: Array = w.arc
		var off := absf(wrapf(phi - float(a[0]), -180.0, 180.0))
		if off <= float(a[1]) + 15.0:
			t = maxf(t, float(w.dmg) / size_k * (1.0 + float(w.fracture) * 0.3))
	return t


# ---------------------------------------------------------------- movement

func _move(dt: float) -> void:
	var o := opp
	var top := top_speed_now()
	if down > 0.0 or stun > 0.0:
		speed = move_toward(speed, 0.0, 8.0 * dt)
		side_v = move_toward(side_v, 0.0, 8.0 * dt)
		_integrate(dt)
		return
	if held_by != null:
		top = minf(top, 0.4)
	if hold.size() > 0:
		top = 0.6
	var goal := pos
	var want_speed := 0.0
	var face := "none"
	var face_ang := heading
	var to_o := o.pos - pos
	var kind: String = plan.get("kind", "hold")
	match kind:
		"orbit":
			var phi: float = plan.phi
			var dd: float = plan.d
			var cur := phi_around(o)
			var diff := wrapf(phi - cur, -180.0, 180.0)
			# commit to a way round: near 180 degrees the shortest way flips every tick
			if absf(diff) > 130.0 and orbit_dir != 0.0:
				diff = absf(diff) * orbit_dir
			elif absf(diff) > 20.0:
				orbit_dir = signf(diff)
			var step_a := clampf(diff, -50.0, 50.0)
			var rr := dd
			if absf(diff) > 50.0:
				# going round: give a front weapon (horns, jaws) a wide berth, but cut in close
				# past a tail - its swing needs room, and the flank is inside it
				# going round: stay outside whatever covers the way - a wide berth past horns
				# and jaws, and outside the tail's sweep - then dive in once nearly there
				var mid := cur + step_a
				var tk := _threat_kind(o, mid)
				if tk == "rear" or _threat_kind(o, cur) == "rear":
					rr = maxf(dd, _tail_radius(o) + 1.5 + 1.5 * pers.g("caution") - 1.0 * pers.g("aggression"))
				elif tk == "front":
					rr = maxf(dd, dist_to(o)) + 2.5 + 2.0 * pers.g("caution")
			var a := o.heading + deg_to_rad(cur + step_a)
			goal = o.pos + Vector2(cos(a), sin(a)) * rr
			want_speed = top
			face = plan.get("face", "front")
		"chase":
			var lead: float = plan.get("lead", 0.4)
			goal = o.pos + o.fwd() * o.speed * lead
			want_speed = top
			face = "front"
		"away":
			var dir := (pos - o.pos).normalized() if to_o.length() > 0.1 else -fwd()
			goal = o.pos + dir * float(plan.d)
			want_speed = top * (0.45 if plan.get("walk", false) else 0.85)
			face = "none"
		"flee":
			var dir2 := (pos - o.pos).normalized() if to_o.length() > 0.1 else -fwd()
			goal = pos + dir2 * 30.0
			want_speed = top
			face = "none"
		_:
			want_speed = 0.0
			face = plan.get("face", "front")
	# steer around boulders; stay inside the clearing unless running away
	goal = _avoid(goal, kind == "flee")
	var to_g := goal - pos
	var gd := to_g.length()
	var close := gd < 3.5
	if face == "front" and (close or kind == "hold"):
		face_ang = atan2(to_o.y, to_o.x)
	elif face == "rear" and (close or kind == "hold" or dist_to(o) < 12.0):
		face_ang = atan2(-to_o.y, -to_o.x)
	elif gd > 0.3:
		face_ang = atan2(to_g.y, to_g.x)
	# turning: slower when fast, and big animals are slower anyway
	var tr := float(sp.turn) * (1.25 - 0.55 * clampf(absf(speed) / maxf(1.0, float(sp.top_speed)), 0.0, 1.0))
	if broken.has("tail") and body.biped:
		tr *= 0.7
	if hold.size() > 0 or held_by != null:
		tr *= 0.3
	var dh := wrapf(face_ang - heading, -PI, PI)
	var turn := clampf(dh, -tr * dt, tr * dt)
	heading = wrapf(heading + turn, -PI, PI)
	turn_rate_now = turn / dt
	# speed along the heading (or backing up toward a goal behind)
	var target_v := 0.0
	if gd > 0.4:
		var al := fwd().dot(to_g / gd)
		if al > 0.0:
			target_v = want_speed * clampf(al * al * 1.2, 0.12, 1.0) * clampf(gd / 3.0, 0.15, 1.0)
		elif gd < 8.0 and (face == "front" or face == "rear"):
			target_v = -minf(1.2 + 1.5 * float(sp.agility), want_speed) * clampf(-al, 0.2, 1.0) * clampf(gd / 2.0, 0.2, 1.0)
		else:
			target_v = want_speed * 0.15
	var acc: float = float(sp.accel) * (1.6 if target_v < speed else 1.0)
	speed = move_toward(speed, target_v, acc * dt)
	side_v = move_toward(side_v, 0.0, 6.0 * dt)
	_integrate(dt)


func _integrate(dt: float) -> void:
	var v := fwd() * speed + right() * side_v
	pos += v * dt
	travelled += v.length() * dt


func _avoid(goal: Vector2, fleeing: bool) -> Vector2:
	var g := goal
	var dir := g - pos
	var dl := dir.length()
	if dl > 0.1:
		var u := dir / dl
		for ob in duel.obstacles:
			var c: Vector2 = ob[0]
			var r: float = float(ob[1]) + float(foot[0][1]) + 1.2
			var rel := c - pos
			var along := rel.dot(u)
			if along > 0.0 and along < dl + r:
				var perp := rel - u * along
				if perp.length() < r:
					var side := -perp.normalized() if perp.length() > 0.01 else Vector2(-u.y, u.x)
					g = pos + u * minf(along, dl) + side * (r + 1.0)
					break
	if not fleeing:
		var lim: float = duel.ARENA_R - 3.0
		if g.length() > lim:
			g = g.normalized() * lim
	return g


# ---------------------------------------------------------------- attacking

func _origin_local(w: Dictionary) -> Vector3:
	var pts := Species.points(body)
	match String(w.origin):
		"head":
			return pts.snout
		"horns":
			return pts.horns
		"chest":
			return pts.shoulder + Vector3(float(body.torso_len) * 0.2, 0, 0)
		"hips":
			return pts.hip
		"feet":
			return pts.feet
	return pts.torso


## Zones of the other this weapon can reach right now: [{zone, c, r, d}].
func reachable(w: Dictionary) -> Array:
	var out: Array = []
	var o := opp
	var ol := _origin_local(w)
	var orig := to_world(ol)
	var o2 := Vector2(orig.x, orig.z)
	var arc: Array = w.arc
	var yr: Array = w.y
	var from := pos if not w.get("rear", false) else Vector2(to_world(Species.points(body).hip).x, to_world(Species.points(body).hip).z)
	for z in o.zones_world():
		var c: Vector3 = z.c
		var c2 := Vector2(c.x, c.z)
		var r: float = z.r
		if c.y + r < float(yr[0]) or c.y - r > float(yr[1]):
			continue
		var hd := o2.distance_to(c2) - r
		if hd > float(w.reach) or o2.distance_to(c2) + r < float(w.min):
			continue
		var b := bearing(c2) if not w.get("rear", false) else rad_to_deg(wrapf(atan2((c2 - from).y, (c2 - from).x) - heading, -PI, PI))
		if absf(wrapf(b - float(arc[0]), -180.0, 180.0)) > float(arc[1]):
			continue
		var zz: Dictionary = z.duplicate()
		zz["d"] = hd
		out.append(zz)
	return out


func _try_attack(dt: float) -> void:
	var o := opp
	if not o.alive or o.fled:
		return
	if mode == "fleeing" and not (latched_by != null):
		return
	var best := {}
	var best_s := 0.0
	var phi := phi_around(o)
	for w in sp.weapons:
		if cool.get(w.id, 0.0) > 0.0 or stamina < float(w.cost) * 0.6:
			continue
		if broken.has("tail") and w.get("rear", false):
			continue
		if w.get("latch", false) and (o.mass < mass * 1.2 or latch.size() > 0):
			continue
		var zs := reachable(w)
		if zs.is_empty():
			continue
		for z in zs:
			var arm := o.armour_vs(z.zone, w.types, phi)
			var eff: float = float(w.dmg) * (1.0 - arm) / o.size_k / float(Species.ZONES[z.zone].tough)
			var val := zone_value(o, z.zone)
			if w.get("rear", false):
				# a swung tail is not aimed at a particular bone: it hits what is in the way
				val = 0.5 + 0.3 * duel.rng.randf()
			var s := eff * (0.5 + val) * (1.0 + float(w.bleed) * 0.2)
			# the unthinking go for whatever is nearest
			s *= lerpf(1.0 / (1.0 + float(z.d)), 1.0, pers.g("cunning"))
			if s > best_s:
				best_s = s
				best = {"w": w, "zone": z.zone}
	if best.is_empty():
		commit = 0.0
		return
	var th := 0.05 + 0.12 * (1.0 - pers.g("aggression"))
	if best_s < th:
		return
	# reaction: the aggressive commit at once, the cautious hesitate
	var rate := 2.5 + 9.0 * pers.g("aggression") + (6.0 if o.vulnerable() else 0.0) + (8.0 if charging else 0.0)
	commit += dt * rate
	if commit < 1.0:
		return
	commit = 0.0
	_start(best.w, best.zone)


func _start(w: Dictionary, zone: String) -> void:
	var wind: float = w.wind
	if charging and w.get("charge", false):
		wind = 0.15
	act = {"w": w, "phase": "wind", "t": wind, "zone": zone, "mult": 1.0}
	if charging and w.get("charge", false):
		var closing := maxf(0.0, (fwd() * speed).dot((opp.pos - pos).normalized()) - (opp.fwd() * opp.speed).dot((pos - opp.pos).normalized()) * -1.0)
		act.mult = 1.0 + clampf(closing / 6.0, 0.0, 0.8)
		charging = false
	stats.attacks[w.id].tries += 1
	stamina = maxf(0.0, stamina - float(w.cost))
	duel.emit({"type": "wind", "who": idx, "w": w.id})


func _start_roar() -> void:
	act = {"w": {"id": "roar", "roar": true}, "phase": "wind", "t": 0.35, "zone": "", "mult": 1.0}
	roar_cd = 7.0 + duel.rng.randf() * 6.0
	stamina = maxf(0.0, stamina - 0.03)
	mode = "roaring"
	stats.roars += 1


func _act_step(dt: float) -> void:
	act.t -= dt
	var w: Dictionary = act.w
	if w.has("roar"):
		if act.phase == "wind" and act.t <= 0.0:
			act.phase = "strike"
			act.t = 1.1
			duel.emit({"type": "roar", "who": idx})
			var mf := clampf(pow(mass / opp.mass, 0.35), 0.5, 2.0)
			opp.fear_spike += 0.13 * pers.g("display") * mf * (1.1 - opp.pers.g("nerve"))
			fear_spike = maxf(0.0, fear_spike - 0.06)
		elif act.phase == "strike" and act.t <= 0.0:
			act = {}
		return
	if down > 0.0 or stun > 0.0:
		act = {}
		return
	if act.phase == "wind" and act.t <= 0.0:
		act.phase = "strike"
		act.t = float(w.strike)
		duel.emit({"type": "strike", "who": idx, "w": w.id})
		_resolve(w)
	elif act.phase == "strike" and act.t <= 0.0:
		act.phase = "rec"
		act.t = float(w.rec)
	elif act.phase == "rec" and act.t <= 0.0:
		cool[w.id] = 0.15
		act = {}


func _resolve(w: Dictionary) -> void:
	var o := opp
	var st: Dictionary = stats.attacks[w.id]
	if w.get("latch", false):
		# the leap itself carries it forward
		var to := (o.pos - pos)
		var dl := to.length()
		pos += to.normalized() * minf(maxf(0.0, dl - 1.5), float(w.reach))
	var zs := reachable(w)
	if zs.is_empty():
		st.missed += 1
		duel.emit({"type": "miss", "who": idx, "w": w.id})
		_after_strike(false)
		return
	var target := {}
	for z in zs:
		if z.zone == act.zone:
			target = z
	var scatter := 0.25 * (1.0 - pers.g("cunning"))
	if w.get("rear", false):
		scatter = 0.6
	if target.is_empty() or duel.rng.randf() < scatter:
		target = zs[0]
		for z in zs:
			if float(z.d) < float(target.d):
				target = z
	# evasion: agile animals that see it coming slip some of it
	var seen := absf(o.bearing(pos)) < 120.0
	var ev: float = float(o.sp.agility) * (0.18 + 0.3 * o.pers.g("caution")) * (0.35 + 0.65 * o.stamina)
	if not seen:
		ev *= 0.3
	if o.lying() or o.held_by != null or o.latched_by != null or o.stun > 0.0:
		ev = 0.0
	if o.dodge_cd > 0.6:
		ev *= 1.6
	# plain inaccuracy: a swung tail is aimed by feel; anything moving is harder to hit
	var acc: float = float(w.get("acc", 0.8)) * (1.0 - 0.35 * clampf(absf(o.speed) / 6.0, 0.0, 1.0))
	if o.lying() or o.held_by != null or o.latched_by != null:
		acc = maxf(acc, 0.92)
	if duel.rng.randf() > acc:
		st.missed += 1
		duel.emit({"type": "miss", "who": idx, "w": w.id})
		_after_strike(false)
		return
	if duel.rng.randf() < ev:
		st.dodged += 1
		duel.emit({"type": "dodge", "who": o.idx, "by": idx, "w": w.id})
		_after_strike(false)
		return
	st.hits += 1
	var q: float = duel.rng.randf_range(0.75, 1.15) * (0.6 + 0.4 * clampf(stamina / 0.4, 0.0, 1.0))
	if broken.has("jaw") and w.origin == "head":
		q *= 0.45
	var dealt := o.take_hit(self, w, target.zone, float(act.mult) * q, target.c)
	st.dmg += dealt
	stats.dmg_dealt += dealt
	# follow-ups: bite and hold; leap and cling
	if w.get("hold", false) and o.alive and duel.rng.randf() < 0.2 + 0.7 * pers.g("persistence"):
		hold = {"zone": target.zone, "t": 0.8 + 2.4 * pers.g("persistence"), "tick": 0.5}
		o.held_by = self
		stats.holds += 1
		duel.emit({"type": "hold", "who": idx, "zone": target.zone})
	elif w.get("latch", false) and o.alive and target.zone in ["neck", "chest", "flank", "hips", "tail"]:
		latch = {"zone": target.zone, "t": 0.0, "tick": 0.35, "c": _zone_local(o, target.zone)}
		o.latched_by = self
		stats.latches += 1
		duel.emit({"type": "latch", "who": idx, "zone": target.zone})
	_after_strike(true)


func _after_strike(_hit: bool) -> void:
	var r := pers.g("pacing") * 0.6 + pers.g("caution") * 0.45 - pers.g("persistence") * 0.5 - pers.g("aggression") * 0.25
	# standing where a tail can reach you once the job is done is how predators got spiked
	if opp != null and _threat_kind(opp, phi_around(opp)) == "rear" or _opp_tail_reaches():
		r += 0.35 + 0.45 * pers.g("caution") + 0.2 * pers.g("cunning")
	if hold.is_empty() and latch.is_empty() and duel.rng.randf() < r:
		retreat_t = 1.2 + duel.rng.randf() * 2.5


## How far from the other's centre its tail weapon can reach.
func _tail_radius(o: Fighter) -> float:
	for w in o.sp.weapons:
		if w.get("rear", false) and not o.broken.has("tail"):
			return absf(float(Species.points(o.body).hip.x)) + float(w.reach) + float(body.torso_len) * 0.3
	return 0.0


## Could the other's tail weapon reach any part of this animal if it turned to swing?
func _opp_tail_reaches() -> bool:
	if opp == null:
		return false
	for w in opp.sp.weapons:
		if w.get("rear", false) and not opp.broken.has("tail"):
			var hip := opp.to_world(Species.points(opp.body).hip)
			var near := 99.0
			for z in zones_world():
				near = minf(near, Vector2(hip.x, hip.z).distance_to(Vector2(z.c.x, z.c.z)) - float(z.r))
			return near < float(w.reach) + 0.5
	return false


static func _zone_local(o: Fighter, zone: String) -> Vector3:
	for h in o.hb_local:
		if h.zone == zone:
			return h.c
	return Vector3.ZERO


func armour_vs(zone: String, types: Dictionary, attacker_phi: float) -> float:
	var arm: Dictionary = sp.armour.get(zone, {})
	var af: Dictionary = sp.get("armour_front", {})
	if af.size() > 0 and absf(attacker_phi) <= float(af.arc) and af.zones.has(zone):
		arm = af.zones[zone]
	var a := 0.0
	var tot := 0.0
	for k in types:
		a += float(types[k]) * float(arm.get(k, 0.0))
		tot += float(types[k])
	return a / maxf(tot, 0.001)


## A blow lands. Returns the damage units dealt.
func take_hit(att: Fighter, w: Dictionary, zone: String, mult: float, at: Vector3, quiet: bool = false) -> float:
	var phi := att.phi_around(self)
	var arm := armour_vs(zone, w.types, phi)
	if lying() and zone == "belly":
		arm = 0.0
	var z: Dictionary = Species.ZONES[zone]
	var units: float = float(w.dmg) * mult * (1.0 - arm) / size_k / float(z.tough)
	units = maxf(units, 0.0)
	var before: float = zone_hp.get(zone, 1.0)
	zone_hp[zone] = before - units
	stats.taken[zone] = float(stats.taken.get(zone, 0.0)) + units
	var ty: Dictionary = w.types
	var cut := float(ty.get("slash", 0.0)) * 1.5 + float(ty.get("pierce", 0.0)) * 1.0 + float(ty.get("crush", 0.0)) * 0.3
	# a wound's flow scales with the size of the teeth/horn that made it, against the size of
	# the animal it is draining: the same slash is a bigger hole in a smaller body
	bleed += units * float(z.bleed) * cut * float(w.bleed) * 0.0072 * sqrt(att.size_k / size_k) / sqrt(size_k)
	blood -= units * 0.008
	shock += units * 0.45
	fear_spike += units * 0.2 * (1.15 - pers.g("nerve"))
	if units > 0.3 and not lying():
		stun = maxf(stun, minf(1.0, units * 0.8))
		act = {} if act.size() > 0 and act.phase == "wind" else act
	var crushy := float(ty.get("crush", 0.0)) + 0.25 * float(ty.get("pierce", 0.0))
	var frac := false
	if zone in ["l_hind", "r_hind", "l_fore", "r_fore", "tail", "hips", "flank", "head"] and not broken.has(zone):
		if zone_hp[zone] <= 0.0 or (zone in ["l_hind", "r_hind", "l_fore", "r_fore", "tail"] and duel.rng.randf() < float(w.fracture) * crushy * units * 0.3):
			frac = true
	var kd := false
	var mr := clampf(pow(att.mass / mass, 0.5), 0.2, 3.0)
	var kd_p := float(w.kd) * mr * clampf(units, 0.1, 1.5) * (1.0 - float(sp.kd_resist)) * mult
	if not lying() and duel.rng.randf() < kd_p:
		kd = true
	duel.emit({"type": "hit", "who": att.idx, "def": idx, "w": w.id, "zone": zone, "units": units, "at": at,
		"armour": arm, "frac": frac, "kd": kd})
	last_units = units
	att_w = w
	if not quiet:
		duel.log_hit(att, self, w, zone, units, arm, frac, kd, mult)
	elif frac:
		duel.log_text("%s shakes %s - %s gives way" % [duel.name_of(att), duel.name_of(self), Species.ZONES[zone].label], att.idx)
	if frac:
		_zone_broken(zone, att)
	elif zone_hp[zone] <= 0.0:
		_zone_broken(zone, att)
	if kd and alive:
		knock_down(duel.rng.randf_range(1.6, 3.6))
		att.stats.kd_dealt += 1
	return units


func knock_down(t: float) -> void:
	down = maxf(down, t)
	stats.kd_taken += 1
	act = {}
	if latch.size() > 0:
		release_latch()
	if hold.size() > 0:
		release_hold()
	duel.emit({"type": "down", "who": idx})


func _zone_broken(zone: String, att: Fighter) -> void:
	if broken.has(zone) and zone != "belly":
		return
	broken[zone] = true
	stats.fractures.append(zone)
	match zone:
		"head":
			# a skull is killed by one crushing blow, not by a pile of grazes on the frill
			if last_units > 0.3 and float(att_w.get("types", {}).get("crush", 0.0)) >= 0.5:
				_die("skull crushed")
			elif last_units > 0.45:
				_die("head wound")
			else:
				zone_hp["head"] = 0.05
				broken.erase("head")
				stats.fractures.erase("head")
				broken["jaw"] = true
				shock += 0.3
		"neck":
			var ty: Dictionary = att_w.get("types", {})
			if float(ty.get("pierce", 0.0)) > 0.6 and float(zone_hp.neck) > -0.6:
				# run through but not severed: it bleeds hard and keeps fighting, for now
				broken.erase("neck")
				stats.fractures.erase("neck")
				zone_hp["neck"] = 0.02
				bleed += 0.012 / sqrt(size_k)
				shock += 0.3
				duel.log_text("%s's neck is run through" % duel.name_of(self), idx)
				return
			_die("neck broken" if float(ty.get("crush", 0.0)) >= 0.5 else "throat torn open")
		"chest":
			death_cause = "chest stove in"
			dying = 2.5
		"belly":
			bleed += 0.02
		"hips":
			down_perm = true
			knock_down(999.0)
		"l_hind", "r_hind":
			if body.biped or broken.has("l_hind") and broken.has("r_hind"):
				down_perm = true
				knock_down(999.0)
		"l_fore", "r_fore":
			var n := 0
			for z in ["l_hind", "r_hind", "l_fore", "r_fore"]:
				if broken.has(z):
					n += 1
			if n >= 2:
				down_perm = true
				knock_down(999.0)
	duel.emit({"type": "break", "who": idx, "zone": zone})


func _die(cause: String) -> void:
	if not alive:
		return
	alive = false
	death_cause = cause
	act = {}
	if hold.size() > 0:
		release_hold()
	if latch.size() > 0:
		release_latch()
	if held_by != null:
		held_by.release_hold()
	if latched_by != null:
		latched_by.release_latch()
	duel.emit({"type": "dead", "who": idx, "cause": cause})


# ---------------------------------------------------------------- holds and pins

func _hold_step(dt: float) -> void:
	var o := opp
	hold.t -= dt
	hold.tick -= dt
	if hold.tick <= 0.0:
		hold.tick = 0.5
		var w: Dictionary = sp.weapons[0]
		var dd := o.take_hit(self, w, hold.zone, 0.22 + 0.1 * pers.g("persistence"), o.to_world(_zone_local(o, hold.zone)), true)
		stats.attacks[w.id].dmg += dd
		stats.dmg_dealt += dd
		if hold.is_empty():
			return
		if o.alive and duel.rng.randf() < 0.1 * (o.mass / mass) * (0.3 + o.stamina) * (1.2 - pers.g("persistence") * 0.5):
			duel.emit({"type": "break_free", "who": o.idx})
			release_hold()
			return
	if hold.t <= 0.0 or stamina < 0.1 or not o.alive or down > 0.0:
		release_hold()


func release_hold() -> void:
	if opp != null and opp.held_by == self:
		opp.held_by = null
	hold = {}
	duel.emit({"type": "release", "who": idx})


func _latched_step(dt: float) -> void:
	var o := opp
	latch.t += dt
	latch.tick -= dt
	# ride along on the other's body
	var c: Vector3 = latch.c
	var wp := o.to_world(c)
	pos = Vector2(wp.x, wp.z) - o.fwd() * 0.2
	heading = o.heading + PI * 0.5 * (1.0 if idx == 0 else -1.0)
	y_off = maxf(0.0, wp.y - float(body.hip_h) * 0.8)
	speed = 0.0
	if latch.tick <= 0.0:
		latch.tick = 0.55
		var kick: Dictionary = sp.weapons[1] if sp.weapons.size() > 1 else sp.weapons[0]
		var dealt := o.take_hit(self, kick, latch.zone, 0.85, wp, true)
		stats.attacks[kick.id].tries += 1
		stats.attacks[kick.id].hits += 1
		stats.attacks[kick.id].dmg += dealt
		stats.dmg_dealt += dealt
		if not o.alive:
			release_latch()
			return
		# the big one bucks, rolls, snaps over its shoulder
		var shake := 0.16 + 0.12 * o.stamina + 0.06 * clampf(o.mass / mass / 8.0, 0.0, 2.0)
		var can_bite: bool = o.sp.weapons[0].origin == "head" and latch.zone in ["neck", "chest", "flank"] and o.body.neck_len > 0.6
		if can_bite:
			shake += 0.12
		if duel.rng.randf() < shake:
			var w0: Dictionary = o.sp.weapons[0]
			if can_bite and duel.rng.randf() < 0.55:
				duel.emit({"type": "shake", "who": o.idx, "bite": true})
				release_latch()
				take_hit(o, w0, "flank", 0.7, to_world(Vector3(0, float(body.hip_h), 0)))
			else:
				duel.emit({"type": "shake", "who": o.idx, "bite": false})
				release_latch()
				if alive:
					knock_down(1.2 + duel.rng.randf())
					shock += 0.2
	stamina = maxf(0.0, stamina - dt * 0.035)
	if latch.size() > 0 and (stamina < 0.12 or (fear > flee_threshold())):
		release_latch()


func release_latch() -> void:
	if opp != null and opp.latched_by == self:
		opp.latched_by = null
	latch = {}
	y_off = 0.0
	if opp != null:
		var away := (pos - opp.pos)
		if away.length() < 0.1:
			away = opp.right()
		pos = opp.pos + away.normalized() * (Fighter.extent(opp, 90.0) + 1.5)
	duel.emit({"type": "release", "who": idx})


# ---------------------------------------------------------------- reporting

func condition() -> float:
	var zsum := 0.0
	for z in zone_hp:
		zsum += clampf(zone_hp[z], 0.0, 1.0)
	return blood * 0.5 + zsum / maxf(1.0, zone_hp.size()) * 0.3 + stamina * 0.2 - broken.size() * 0.08


func status_lines() -> Array[String]:
	var out: Array[String] = []
	if not alive:
		out.append("DEAD - " + death_cause)
		return out
	if fled:
		out.append("fled")
		return out
	for z in broken:
		if z == "jaw":
			out.append("face smashed")
			continue
		var lab: String = Species.ZONES[z].label
		match z:
			"belly":
				out.append("gutted")
			"flank":
				out.append("ribs broken")
			"hips":
				out.append("pelvis broken")
			"tail":
				out.append("tail broken")
			"chest":
				out.append("chest caved in")
			_:
				out.append(lab + " broken")
	if bleed > 0.004:
		out.append("bleeding heavily")
	elif bleed > 0.0012:
		out.append("bleeding")
	if down_perm:
		out.append("can't rise")
	elif down > 0.0:
		out.append("knocked down")
	if exhausted:
		out.append("exhausted")
	if held_by != null:
		out.append("held in jaws")
	if latched_by != null:
		out.append("raptor on its back")
	return out
