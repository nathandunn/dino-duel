extends Node3D
## Entry point. Builds the clearing, the HUD and the camera, runs duels and renders them.
## The fight itself is Duel/Fighter (pure simulation, fixed 30 Hz); this file steps it,
## interpolates the views between steps, and turns its events into sound and gore.
##
## Headless (no window): see cli.gd, e.g.
##   godot --headless --path . -- --sim=50 --a=rex --b=trike --pa=Stalker
##   godot --headless --path . -- --matrix=40
##   godot --headless --path . -- --presets=40 --a=allo --b=stego
## On the web the query string stands in for the flags: index.html?a=anky&b=rex&pa=Bulwark&seed=7

var args := {}
var cfg := {}
var duel: Duel
var views: Array[DinoView] = []
var arena: Arena
var cam: CameraRig
var hud: Hud
var sfx: Sfx
var speed := 1.0
var paused := false
var acc := 0.0
var show_intents := false
var duel_index := 0
var base_seed := -1
var _over_t := -1.0
var _pool_t := [0.0, 0.0]
var _cry_t := [0.0, 0.0]
# batch / league in progress
var _batch: Batch = null
var _batch_left := 0
var _batch_total := 0
var _league: Array = []
var _league_rows: Array = []
var _league_n := 0
var _league_cur := ""
var _in_league := false


func _ready() -> void:
	args = _parse_args(OS.get_cmdline_user_args())
	var headless := DisplayServer.get_name() == "headless" or args.has("sim") or args.has("matrix") or args.has("presets")
	if headless and not args.has("ui"):
		Cli.run(args)
		get_tree().quit()
		return
	cfg = {
		"species": [Species.resolve(String(args.get("a", "rex"))), Species.resolve(String(args.get("b", "trike")))],
		"preset": [Personality.resolve(String(args.get("pa", "Balanced"))), Personality.resolve(String(args.get("pb", "Balanced")))],
		"custom": [Personality.preset("Balanced"), Personality.preset("Balanced")],
	}
	for k in [["ca", 0], ["cb", 1]]:
		if args.has(k[0]):
			var r := Cli.personality("Custom", String(args[k[0]]), null)
			cfg.custom[k[1]] = r[0]
			cfg.preset[k[1]] = "Custom"
	if args.has("seed"):
		base_seed = int(args.seed)
	_setup_ui_scale()
	_environment()
	arena = Arena.new()
	add_child(arena)
	sfx = Sfx.new()
	add_child(sfx)
	cam = CameraRig.new()
	add_child(cam)
	hud = Hud.new()
	add_child(hud)
	hud.setup(cfg)
	hud.new_duel_requested.connect(start_duel)
	hud.batch_requested.connect(_start_batch)
	hud.league_requested.connect(_start_league)
	hud.speed_changed.connect(func(s: float): speed = s)
	hud.pause_toggled.connect(func(p: bool): paused = p)
	hud.intents_toggled.connect(func(on: bool):
		show_intents = on
		for v in views:
			v.show_intent = on)
	if args.has("intents"):
		show_intents = true
	start_duel()
	match String(args.get("open", "")):
		"setup":
			hud.setup_btn.button_pressed = true
		"batch":
			_start_batch(int(args.get("n", "20")))
		"league":
			_start_league(int(args.get("n", "6")))


func _setup_ui_scale() -> void:
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	var dpi := DisplayServer.screen_get_dpi()
	root.content_scale_factor = clampf(float(dpi) / 96.0, 1.0, 3.0)


func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.36, 0.52, 0.72)
	sm.sky_horizon_color = Color(0.72, 0.70, 0.60)
	sm.ground_horizon_color = Color(0.5, 0.48, 0.38)
	sm.ground_bottom_color = Color(0.2, 0.2, 0.15)
	sm.sun_angle_max = 30.0
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.72, 0.62)
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.3
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


func _parse_args(list: PackedStringArray) -> Dictionary:
	var d := {}
	for a in list:
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			d[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if OS.has_feature("web"):
		var raw = JavaScriptBridge.eval("window.location.search.slice(1)", true)
		if raw != null:
			for pair in String(raw).split("&", false):
				var kv := pair.split("=", true, 1)
				if kv[0] != "":
					d[kv[0].uri_decode()] = (kv[1].uri_decode() if kv.size() > 1 else "1")
	return d


func _make_personality(s: int, rng: RandomNumberGenerator) -> Array:
	var pn: String = cfg.preset[s]
	if pn == "Custom":
		return [(cfg.custom[s] as Personality).duplicate_p(), "Custom"]
	return [Personality.preset(pn, rng), pn]


func _new_duel(seed_v: int) -> Duel:
	var rng := RandomNumberGenerator.new()
	if seed_v >= 0:
		rng.seed = seed_v + 31
	else:
		rng.randomize()
	var a := _make_personality(0, rng)
	var b := _make_personality(1, rng)
	var d := Duel.new()
	d.setup(cfg.species[0], a[0], a[1], cfg.species[1], b[0], b[1], seed_v)
	return d


func start_duel() -> void:
	for v in views:
		v.queue_free()
	views.clear()
	if duel != null:
		duel.dispose()
	arena.clear_marks()
	var s := -1 if base_seed < 0 else base_seed + duel_index
	duel_index += 1
	duel = _new_duel(s)
	arena.build_rocks(duel.obstacles)
	for i in 2:
		var v := DinoView.new()
		add_child(v)
		v.setup(duel.f[i], Hud.SIDE_COLORS[i])
		v.show_intent = show_intents
		v.on_step = _on_step
		views.append(v)
	acc = 0.0
	_over_t = -1.0
	hud.on_duel_started(duel)
	var a: Fighter = duel.f[0]
	var b: Fighter = duel.f[1]
	cam.frame(Vector3(a.pos.x, 0, a.pos.y), Vector3(b.pos.x, 0, b.pos.y), maxf(float(a.sp.length), float(b.sp.length)))
	cam.focus = cam.want_focus
	cam.dist = cam.want_dist * cam.zoom


var _shot_t := 0.0


## --shot=/path.png --shot_at=12 [--shot_quit]: save a frame (used for checking renders).
func _shots(delta: float) -> void:
	if not args.has("shot"):
		return
	_shot_t += delta
	var times := String(args.get("shot_at", "8")).split(",")
	for i in times.size():
		var ts := float(times[i])
		if _shot_t >= ts and _shot_t - delta < ts:
			var img := get_viewport().get_texture().get_image()
			var path := String(args.shot).replace(".png", "_%d.png" % i)
			img.save_png(path)
			print("shot ", path, " t=", duel.t if duel != null else 0.0)
			if i == times.size() - 1 and args.has("shot_quit"):
				get_tree().quit()


func _process(delta: float) -> void:
	_shots(delta)
	if _batch_left > 0:
		_batch_tick()
	if duel == null or views.is_empty():
		return
	if not paused:
		acc += minf(delta, 0.1) * speed
		var steps := 0
		while acc >= Duel.DT and steps < 40:
			for v in views:
				v.snapshot()
			if not duel.over:
				duel.step()
			else:
				# the sim has stopped; keep the views ticking over in place
				for x in duel.f:
					x.speed = move_toward(x.speed, 0.0, 0.3)
			_events()
			acc -= Duel.DT
			steps += 1
	var alpha := clampf(acc / Duel.DT, 0.0, 1.0)
	for v in views:
		v.update(delta * (0.0 if paused else speed), alpha)
	_ground_marks(delta * (0.0 if paused else speed))
	var a: Fighter = duel.f[0]
	var b: Fighter = duel.f[1]
	var pa := views[0].position
	var pb := views[1].position
	if a.fled:
		pa = pb
	if b.fled:
		pb = pa
	cam.frame(pa, pb, maxf(float(a.sp.length), float(b.sp.length)))
	if duel.over and _over_t >= 0.0:
		_over_t += delta
		if _over_t > 1.2 and _over_t - delta <= 1.2:
			var w: int = duel.result.winner
			if w >= 0 and duel.f[w].alive:
				views[w].start_cheer(3.0)
				sfx.play("roar_" + duel.f[w].sp.id, views[w].position + Vector3(0, 3, 0), 1.0, 2.0)
		if _over_t > 2.5 and _over_t - delta <= 2.5:
			var r := duel.result
			var w2: int = r.winner
			var line := "Draw" if w2 < 0 else "%s %s wins" % [Hud.SIDE_NAMES[w2], r.species[w2]]
			hud.show_next("%s - %s" % [line, String(r.how).replace("killed: ", "")])


func _events() -> void:
	for e in duel.events:
		var ty: String = e.type
		if ty == "over":
			_over_t = 0.0
			hud.last_result = duel.result
			hud.results_btn.disabled = false
			continue
		var who: int = e.get("who", -1)
		var x: Fighter = duel.f[who] if who >= 0 else null
		var at := views[who].position + Vector3(0, 2.5, 0) if who >= 0 else Vector3.ZERO
		match ty:
			"roar":
				sfx.play("roar_" + x.sp.id, at, 1.0, 1.0)
			"strike":
				var w := _weapon(x, String(e.w))
				if w.get("rear", false) or w.get("latch", false):
					sfx.play("whoosh", at, 0.7 if w.get("rear", false) else 1.2)
			"miss", "dodge":
				sfx.play("whoosh", at, 1.4, -6.0)
			"hit":
				var d: int = e.def
				var att: Fighter = duel.f[e.who]
				var units: float = e.units
				var hp: Vector3 = e.at
				var wid: String = e.w
				var cue := "crunch"
				if wid in ["hatchet", "kick", "rake", "leap"]:
					cue = "slash"
				elif wid in ["gore", "thag"]:
					cue = "gore"
				elif wid in ["club", "slam", "stomp"]:
					cue = "thud"
				sfx.play(cue, hp, clampf(1.6 - att.size_k * 0.3, 0.6, 1.4), clampf(units * 6.0 - 4.0, -10.0, 2.0))
				if units > 0.04 and e.armour < 0.7:
					arena.splash(hp, units)
					views[d].add_wound(String(e.zone), units)
				elif units > 0.04:
					arena.dust(hp, 0.3)
				views[d].flinch = 1.0
				if e.frac:
					sfx.play("crack", hp, 1.0, 2.0)
				if units > 0.15 and duel.t - _cry_t[d] > 1.5 and duel.f[d].alive:
					_cry_t[d] = duel.t
					sfx.play("cry_" + duel.f[d].sp.id, views[d].position + Vector3(0, 2.5, 0))
			"down":
				sfx.play("fall", views[who].position, clampf(1.5 - x.size_k * 0.3, 0.5, 1.3), 2.0)
				arena.dust(views[who].position + Vector3(0, 0.3, 0), x.size_k)
			"dead":
				sfx.play("die_" + x.sp.id, at, 1.0, 2.0)
			"flee":
				sfx.play("cry_" + x.sp.id, at, 1.1)
			"hold":
				sfx.play("crunch", at, 0.8, 1.0)
			"shake":
				sfx.play("cry_" + x.sp.id, at, 1.0)
				arena.dust(views[who].position, 0.6)
			"break_free":
				sfx.play("cry_" + x.sp.id, at, 1.2)
			"charge":
				sfx.play("roar_" + x.sp.id, at, 1.15, -2.0)
	duel.events.clear()


func _weapon(x: Fighter, id: String) -> Dictionary:
	for w in x.sp.weapons:
		if w.id == id:
			return w
	return {}


func _on_step(v: DinoView, gait: float) -> void:
	var x := v.f
	if x.mass > 1500.0:
		sfx.play("step", v.position, clampf(1.5 - x.size_k * 0.35, 0.5, 1.3), clampf(-14.0 + x.size_k * 3.0 + gait * 3.0, -18.0, -2.0))
	var side := 1.0 if v._step_side == 0 else -1.0
	var p := v.position + v.global_basis.z * float(x.body.torso_w) * 0.35 * side
	arena.footprint(p, float(x.body.leg_r) * 1.3, v.rotation.y)


func _ground_marks(dt: float) -> void:
	for i in 2:
		var x: Fighter = duel.f[i]
		if x.bleed > 0.0012 or (not x.alive and _pool_t[i] > -5.0):
			_pool_t[i] -= dt
			if _pool_t[i] <= 0.0:
				_pool_t[i] = clampf(0.03 / maxf(x.bleed, 0.0005), 0.6, 4.0)
				var off := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * float(x.body.torso_w) * 0.4
				arena.blood_pool(views[i].position + off, clampf(x.bleed * 60.0, 0.15, 0.6) * x.size_k * (2.0 if not x.alive else 1.0))
				if not x.alive:
					_pool_t[i] = -10.0


# ---------------------------------------------------------------- batches

func _start_batch(n: int) -> void:
	_league.clear()
	_in_league = false
	_batch = Batch.new()
	_batch_left = n
	_batch_total = n
	paused = true
	hud.pause_btn.set_pressed_no_signal(true)
	hud.pause_btn.text = "Play"


func _start_league(n: int) -> void:
	_league = Personality.ORDER.duplicate()
	_league_rows.clear()
	_league_n = n
	_in_league = true
	paused = true
	hud.pause_btn.set_pressed_no_signal(true)
	hud.pause_btn.text = "Play"
	_next_league()


func _next_league() -> void:
	if _league.is_empty():
		_in_league = false
		hud.show_league(_league_rows, {"species_a": cfg.species[0], "species_b": cfg.species[1], "preset_b": cfg.preset[1]}, _league_n)
		hud.set_status("League done. Press Play to go back to the duel.")
		return
	_league_cur = _league.pop_front()
	_batch = Batch.new()
	_batch_left = _league_n
	_batch_total = _league_n


func _batch_tick() -> void:
	var t0 := Time.get_ticks_msec()
	var league := _in_league
	while _batch_left > 0 and Time.get_ticks_msec() - t0 < 30:
		var i := _batch_total - _batch_left
		var flip := i % 2 == 1
		var d: Duel
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + i
		if league:
			var A := [Personality.preset(_league_cur, rng), _league_cur]
			var B := _make_personality(1, rng)
			d = Duel.new()
			if flip:
				d.setup(cfg.species[1], B[0], B[1], cfg.species[0], A[0], A[1], 5000 + i)
			else:
				d.setup(cfg.species[0], A[0], A[1], cfg.species[1], B[0], B[1], 5000 + i)
		else:
			d = _new_duel(-1)
			flip = false
		var r := d.run_to_end()
		d.dispose()
		if flip:
			r = Cli._flip(r)
		_batch.add(r)
		_batch_left -= 1
	if league:
		hud.set_status("Personality league: %s (%d/%d) ... %d/%d" % [_league_cur, _league_rows.size() + 1, Personality.ORDER.size(), _batch_total - _batch_left, _batch_total])
	else:
		hud.set_status("Simulating %d/%d duels..." % [_batch_total - _batch_left, _batch_total])
	if _batch_left == 0:
		if league:
			var hk: Array = _batch.how.keys()
			hk.sort_custom(func(a, b): return _batch.how[a] > _batch.how[b])
			var how_s := ", ".join(hk.slice(0, 2).map(func(k): return "%s %d" % [String(k).replace("killed: ", ""), _batch.how[k]]))
			_league_rows.append({"preset": _league_cur, "pct": _batch.win_pct(0), "t": _batch.t_sum / maxf(1.0, _batch.n), "how": how_s})
			_next_league()
		else:
			hud.show_batch(_batch)
			hud.set_status("%s. Press Play to go back to the duel." % _batch.one_line())
