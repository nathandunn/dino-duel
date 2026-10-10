class_name DinoView
extends Node3D
## Draws one Fighter. The model is built in code from the same body plan the simulation's
## hitboxes come from (Species.points), so a bite on the "left hind leg" lands on the leg you
## see. A chain of pivots - torso, neck, head and jaw, a jointed tail, two- or four-legged
## gait - is posed every frame from the fighter's state: walking, lunging, swinging, holding,
## clinging, lying down, dead. Wounds stay on the body; bleeding drips and pools.

var f: Fighter
var b: Dictionary
var pts: Dictionary
var team_color := Color.WHITE
var skin: StandardMaterial3D
var belly_mat: StandardMaterial3D
var accent_mat: StandardMaterial3D
var bone_mat: StandardMaterial3D
var wound_mat: StandardMaterial3D
var dark_mat: StandardMaterial3D

var body: Node3D           # rolls over when down
var torso: Node3D
var neck_piv: Node3D
var head_piv: Node3D
var jaw_piv: Node3D
var tail_pivs: Array[Node3D] = []
var legs: Array = []       # [{hip: Node3D, knee: Node3D, zone, front: bool, side: float}]
var arms: Array[Node3D] = []
var label: Label3D
var drip: CPUParticles3D
var wounds := 0

var prev_pos := Vector2.ZERO
var prev_head := 0.0
var cur_pos := Vector2.ZERO
var cur_head := 0.0
var phase := 0.0
var roll := 0.0
var lunge := 0.0
var jaw := 0.0
var swing := 0.0
var shake_t := 0.0
var flinch := 0.0
var cheer := -1.0
var show_intent := false
var _pool_t := 0.0
var _step_side := 0
var on_step: Callable


func setup(fighter: Fighter, color: Color) -> void:
	f = fighter
	b = f.body
	pts = Species.points(b)
	team_color = color
	_materials()
	_build()
	cur_pos = f.pos
	prev_pos = f.pos
	cur_head = f.heading
	prev_head = f.heading
	_apply_root(1.0)


func _materials() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.09
	noise.seed = hash(f.spname)
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	var grad := Gradient.new()
	grad.set_color(0, Color(0.72, 0.72, 0.72))
	grad.set_color(1, Color(1.08, 1.08, 1.08))
	tex.color_ramp = grad
	skin = StandardMaterial3D.new()
	skin.albedo_color = b.color
	skin.albedo_texture = tex
	skin.uv1_triplanar = true
	skin.uv1_scale = Vector3(1.6, 1.6, 1.6)
	skin.roughness = 0.85
	belly_mat = StandardMaterial3D.new()
	belly_mat.albedo_color = b.color2
	belly_mat.albedo_texture = tex
	belly_mat.uv1_triplanar = true
	belly_mat.uv1_scale = Vector3(2.5, 2.5, 2.5)
	belly_mat.roughness = 0.9
	accent_mat = StandardMaterial3D.new()
	accent_mat.albedo_color = b.accent
	accent_mat.roughness = 0.7
	bone_mat = StandardMaterial3D.new()
	bone_mat.albedo_color = Color(0.86, 0.82, 0.7)
	bone_mat.roughness = 0.5
	wound_mat = StandardMaterial3D.new()
	wound_mat.albedo_color = Color(0.32, 0.01, 0.01)
	wound_mat.roughness = 0.25
	wound_mat.metallic_specular = 0.8
	dark_mat = StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.05, 0.04, 0.03)
	dark_mat.roughness = 0.3


func _ell(parent: Node3D, at: Vector3, radii: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 20
	s.rings = 10
	m.mesh = s
	m.material_override = mat
	m.position = at
	m.rotation = rot
	m.scale = radii
	parent.add_child(m)
	return m


func _cone(parent: Node3D, at: Vector3, r: float, h: float, mat: Material, rot: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	c.rings = 1
	m.mesh = c
	m.material_override = mat
	m.rotation = rot
	parent.add_child(m)
	# shift so the base sits at `at` and the cone points along its local +Y
	m.position = at + m.basis.y * (h * 0.5)
	return m


func _cap(parent: Node3D, from: Vector3, to: Vector3, r0: float, r1: float, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	var d := to - from
	c.top_radius = r1
	c.bottom_radius = r0
	c.height = d.length()
	c.radial_segments = 10
	c.rings = 1
	m.mesh = c
	m.material_override = mat
	parent.add_child(m)
	m.position = (from + to) * 0.5
	if d.length() > 0.001:
		var up := d.normalized()
		var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var x := ref.cross(up).normalized()
		var z := x.cross(up).normalized()
		m.basis = Basis(x, up, z)
	# round the ends
	var j0 := MeshInstance3D.new()
	var s0 := SphereMesh.new()
	s0.radius = r0
	s0.height = r0 * 2.0
	s0.radial_segments = 10
	s0.rings = 6
	j0.mesh = s0
	j0.material_override = mat
	j0.position = from
	parent.add_child(j0)
	var j := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r1
	s.height = r1 * 2.0
	s.radial_segments = 10
	s.rings = 6
	j.mesh = s
	j.material_override = mat
	j.position = to
	parent.add_child(j)
	return m


func _build() -> void:
	var tl: float = b.torso_len
	var th: float = b.torso_h
	var tw: float = b.torso_w
	body = Node3D.new()
	add_child(body)
	torso = Node3D.new()
	body.add_child(torso)
	var pitch := 0.0
	if not b.biped:
		pitch = atan2(float(b.chest_h) - float(b.hip_h), tl * 0.6)
	_ell(torso, pts.torso, Vector3(tl * 0.55, th * 0.5, tw * 0.5), skin, Vector3(0, 0, pitch))
	_ell(torso, pts.torso + Vector3(tl * 0.05, -th * 0.18, 0), Vector3(tl * 0.42, th * 0.36, tw * 0.44), belly_mat, Vector3(0, 0, pitch))
	# hips and shoulders bulk
	_ell(torso, pts.hip + Vector3(0, -th * 0.05, 0), Vector3(tl * 0.3, th * 0.45, tw * 0.47), skin)
	if not b.biped:
		_ell(torso, pts.shoulder + Vector3(0, -th * 0.05, 0), Vector3(tl * 0.25, th * 0.42, tw * 0.47), skin)

	# neck and head
	neck_piv = Node3D.new()
	neck_piv.position = pts.neck_base
	torso.add_child(neck_piv)
	var nvec: Vector3 = pts.neck_end - pts.neck_base
	var nr: float = b.neck_r
	_cap(neck_piv, Vector3(-0.15, 0, 0), nvec, nr * 1.15, maxf(float(b.head_h) * 0.42, nr * 0.75), skin)
	head_piv = Node3D.new()
	head_piv.position = nvec
	neck_piv.add_child(head_piv)
	var hl: float = b.head_len
	var hh: float = b.head_h
	var hw: float = b.head_w
	var hy := 0.0 if b.biped else -hh * 0.15
	_ell(head_piv, Vector3(hl * 0.4, hy + hh * 0.1, 0), Vector3(hl * 0.55, hh * 0.45, hw * 0.5), skin)
	jaw_piv = Node3D.new()
	jaw_piv.position = Vector3(hl * 0.05, hy - hh * 0.12, 0)
	head_piv.add_child(jaw_piv)
	_ell(jaw_piv, Vector3(hl * 0.42, -hh * 0.12, 0), Vector3(hl * 0.5, hh * 0.22, hw * 0.42), belly_mat)
	for sgn in [-1.0, 1.0]:
		_ell(head_piv, Vector3(hl * 0.38, hy + hh * 0.32, sgn * hw * 0.42), Vector3(0.07, 0.07, 0.04) * maxf(1.0, hh * 1.5), dark_mat)
	if f.sp.id in ["rex", "allo", "raptor"]:
		for i in 7:
			var x := hl * (0.2 + i * 0.1)
			for sgn in [-1.0, 1.0]:
				_cone(head_piv, Vector3(x, hy - hh * 0.12, sgn * hw * 0.36), hh * 0.05, hh * 0.18, bone_mat, Vector3(PI, 0, 0))
	if b.has("frill"):
		var fr: float = b.frill
		var disc := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = fr
		cm.bottom_radius = fr
		cm.height = 0.12
		cm.radial_segments = 24
		disc.mesh = cm
		disc.material_override = accent_mat
		# the frill rises up and back from the back of the skull
		var up_back := Vector3(-0.5, 0.87, 0)
		disc.position = Vector3(hl * 0.05, hy + hh * 0.25, 0) + up_back * fr * 0.75
		disc.rotation = Vector3(0, 0, deg_to_rad(-60))
		disc.scale = Vector3(1.0, 1.0, 1.15)
		head_piv.add_child(disc)
		var hr: float = b.horns
		for sgn in [-1.0, 1.0]:
			_cone(head_piv, Vector3(hl * 0.42, hy + hh * 0.45, sgn * hw * 0.3), 0.11, hr, bone_mat, Vector3(sgn * 0.1, 0, -deg_to_rad(62)))
		_cone(head_piv, Vector3(hl * 0.82, hy + hh * 0.3, 0), 0.08, hr * 0.35, bone_mat, Vector3(0, 0, -deg_to_rad(30)))
		_cone(head_piv, Vector3(hl * 0.95, hy, 0), 0.1, 0.25, accent_mat, Vector3(0, 0, -PI * 0.5))
	if b.has("crests"):
		for sgn in [-1.0, 1.0]:
			_cone(head_piv, Vector3(hl * 0.32, hy + hh * 0.42, sgn * hw * 0.2), 0.07, 0.16, accent_mat, Vector3(0, 0, 0.2))
	if f.sp.id == "rex":
		_ell(head_piv, Vector3(hl * 0.2, hy + hh * 0.38, 0), Vector3(hl * 0.35, hh * 0.18, hw * 0.35), skin)

	# tail: a jointed chain so swings and sways bend through it
	var tb: Vector3 = pts.tail_base
	var te: Vector3 = pts.tail_end
	var segs := 6
	var parent: Node3D = torso
	var prev := tb
	var tr: float = b.tail_r
	for i in segs:
		var piv := Node3D.new()
		piv.position = prev if i == 0 else (prev - _seg_start(i - 1, tb, te, segs))
		parent.add_child(piv)
		var a := tb.lerp(te, float(i) / segs)
		var c := tb.lerp(te, float(i + 1) / segs)
		var r0 := tr * (1.0 - 0.8 * float(i) / segs)
		var r1 := tr * (1.0 - 0.8 * float(i + 1) / segs)
		_cap(piv, Vector3.ZERO, c - a, r0, maxf(r1, 0.05), skin)
		tail_pivs.append(piv)
		parent = piv
		prev = c
		if b.has("osteoderms") and i < segs - 1:
			for sgn in [-1.0, 1.0]:
				_cone(piv, (c - a) * 0.5 + Vector3(0, 0, sgn * r0 * 0.8), r0 * 0.25, r0 * 0.5, accent_mat, Vector3(sgn * PI * 0.5, 0, 0))
	var tip := tail_pivs[segs - 1]
	var tip_at := te - tb.lerp(te, float(segs - 1) / segs)
	if b.has("club"):
		var cl: float = b.club
		_ell(tip, tip_at, Vector3(cl * 1.3, cl * 0.7, cl * 1.5), accent_mat)
	if b.has("spikes"):
		var sl: float = b.spikes
		for k in 4:
			var sgn := -1.0 if k % 2 == 0 else 1.0
			var back := -0.25 * (k / 2)
			_cone(tip, tip_at + Vector3(back - 0.1, 0.05, 0), 0.07, sl, bone_mat, Vector3(sgn * deg_to_rad(70), 0, deg_to_rad(25 + 15 * (k / 2))))
	if b.has("feathers"):
		for k in 5:
			_ell(tip, tip_at * (0.5 + 0.1 * k) + Vector3(0, 0.06, 0), Vector3(0.3, 0.05, 0.16), accent_mat, Vector3(0, 0, 0.1))
		_ell(neck_piv, nvec * 0.4 + Vector3(-0.05, nr * 0.9, 0), Vector3(0.25, 0.06, 0.08), accent_mat, Vector3(0, 0, 0.6))

	# back armour / plates
	if b.has("osteoderms"):
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 7:
			for j in 5:
				var x := -tl * 0.5 + tl * (i + 0.5) / 7.0
				var zz := (j - 2) * tw * 0.2
				var yy: float = pts.torso.y + th * 0.48 * sqrt(maxf(0.0, 1.0 - pow(zz / (tw * 0.55), 2)))
				_cone(torso, Vector3(x, yy - 0.05, zz), 0.13, 0.18 + rng.randf() * 0.1, accent_mat, Vector3(zz * 0.4, 0, 0))
		for sgn in [-1.0, 1.0]:
			for i in 4:
				_cone(torso, Vector3(-tl * 0.3 + i * tl * 0.2, pts.torso.y, sgn * tw * 0.52), 0.12, 0.35, accent_mat, Vector3(sgn * PI * 0.5, 0, 0))
	if b.has("plates"):
		var n := 9
		for i in n:
			var u := float(i) / (n - 1)
			var x := lerpf(tl * 0.45, -tl * 0.7, u)
			var size := sin(u * PI) * 0.85 + 0.25
			var yy: float = pts.torso.y + th * 0.5 * sqrt(maxf(0.0, 1.0 - pow(x / (tl * 0.6), 2))) - 0.05
			for sgn in [-1.0, 1.0]:
				var pl := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(0.7, 0.7, 0.06) * size
				pl.mesh = bm
				pl.material_override = accent_mat
				pl.position = Vector3(x + sgn * 0.15 * size, yy + size * 0.32, sgn * 0.09)
				pl.rotation = Vector3(sgn * 0.12, 0, PI * 0.25)
				torso.add_child(pl)

	# legs
	var hx: float = pts.hip.x
	for sgn in [-1.0, 1.0]:
		legs.append(_leg(Vector3(hx, float(b.hip_h), sgn * tw * 0.38), float(b.hip_h), float(b.leg_r), b.biped, false, "l_hind" if sgn < 0 else "r_hind", sgn))
	if not b.biped:
		for sgn in [-1.0, 1.0]:
			legs.append(_leg(Vector3(pts.shoulder.x, float(b.chest_h), sgn * tw * 0.38), float(b.chest_h), float(b.leg_r) * 0.95, false, true, "l_fore" if sgn < 0 else "r_fore", sgn))
	else:
		for sgn in [-1.0, 1.0]:
			var ap := Node3D.new()
			ap.position = pts.shoulder + Vector3(tl * 0.2, -th * 0.15, sgn * tw * 0.42)
			torso.add_child(ap)
			var al: float = b.fore_len
			_cap(ap, Vector3.ZERO, Vector3(al * 0.4, -al * 0.6, 0), float(b.leg_r) * 0.35, float(b.leg_r) * 0.25, skin)
			if b.has("feathers"):
				_ell(ap, Vector3(al * 0.2, -al * 0.45, 0), Vector3(al * 0.4, al * 0.12, 0.04), accent_mat, Vector3(0, 0, -0.9))
			for k in 2:
				_cone(ap, Vector3(al * 0.4, -al * 0.6, 0), 0.03, 0.14 + float(f.sp.id == "allo") * 0.1, bone_mat, Vector3(0, 0, -PI * 0.6 - k * 0.3))
			arms.append(ap)

	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0009
	label.font_size = 18
	label.outline_size = 6
	label.modulate = team_color.lightened(0.35)
	label.position = Vector3(0, maxf(pts.head.y, float(b.hip_h) + float(b.torso_h)) + 1.6, 0)
	add_child(label)

	drip = CPUParticles3D.new()
	drip.amount = 40
	drip.lifetime = 1.0
	drip.emitting = false
	drip.local_coords = false
	drip.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drip.emission_box_extents = Vector3(tl * 0.4, 0.2, tw * 0.3)
	drip.direction = Vector3(0, -1, 0)
	drip.spread = 15.0
	drip.gravity = Vector3(0, -9.8, 0)
	drip.initial_velocity_min = 0.2
	drip.initial_velocity_max = 0.8
	drip.scale_amount_min = 0.6
	drip.scale_amount_max = 1.2
	var dm := SphereMesh.new()
	dm.radius = 0.04
	dm.height = 0.08
	dm.radial_segments = 6
	dm.rings = 3
	dm.material = wound_mat
	drip.mesh = dm
	drip.position = pts.torso + Vector3(0, -th * 0.3, 0)
	torso.add_child(drip)


func _seg_start(i: int, tb: Vector3, te: Vector3, segs: int) -> Vector3:
	return tb.lerp(te, float(i) / segs)


func _leg(at: Vector3, h: float, r: float, biped: bool, front: bool, zone: String, sgn: float) -> Dictionary:
	var hip := Node3D.new()
	hip.position = at
	torso.add_child(hip)
	var thigh_len := h * (0.48 if biped else 0.5)
	var knee := Node3D.new()
	var kx := thigh_len * (0.35 if biped else 0.0)
	knee.position = Vector3(kx, -thigh_len, 0)
	hip.add_child(knee)
	_cap(hip, Vector3(0, r * 0.4, 0), knee.position, r * 1.25, r * 0.85, skin)
	var shin_len := h - thigh_len
	if biped:
		# shin back, then the long foot forward to the toes
		_cap(knee, Vector3.ZERO, Vector3(-shin_len * 0.35, -shin_len * 0.62, 0), r * 0.8, r * 0.55, skin)
		_cap(knee, Vector3(-shin_len * 0.35, -shin_len * 0.62, 0), Vector3(-shin_len * 0.15, -shin_len + r * 0.3, 0), r * 0.5, r * 0.4, skin)
		for k in 3:
			var ang := (k - 1) * 0.35
			_cap(knee, Vector3(-shin_len * 0.15, -shin_len + r * 0.3, 0), Vector3(-shin_len * 0.15 + r * 2.0 * cos(ang), -shin_len + r * 0.2, r * 2.0 * sin(ang)), r * 0.3, r * 0.15, skin)
		if f.sp.id == "raptor":
			_cone(knee, Vector3(-shin_len * 0.1, -shin_len + r * 0.6, sgn * r * 0.4), 0.04, 0.22, bone_mat, Vector3(0, 0, -PI * 0.3))
	else:
		_cap(knee, Vector3.ZERO, Vector3(0, -shin_len + r * 0.3, 0), r * 0.85, r * 0.8, skin)
		_ell(knee, Vector3(r * 0.2, -shin_len + r * 0.4, 0), Vector3(r * 1.2, r * 0.45, r * 1.1), skin)
	return {"hip": hip, "knee": knee, "zone": zone, "front": front, "side": sgn, "biped": biped}


# ---------------------------------------------------------------- per frame

func snapshot() -> void:
	prev_pos = cur_pos
	prev_head = cur_head
	cur_pos = f.pos
	cur_head = f.heading


func _apply_root(alpha: float) -> void:
	var p := prev_pos.lerp(cur_pos, alpha)
	var h := lerp_angle(prev_head, cur_head, alpha)
	position = Vector3(p.x, f.y_off, p.y)
	rotation = Vector3(0, -h, 0)


func update(delta: float, alpha: float) -> void:
	_apply_root(alpha)
	var t := Time.get_ticks_msec() / 1000.0
	var top: float = float(f.sp.top_speed)
	var spd := absf(f.speed)
	var stride: float = float(b.hip_h) * (1.4 if b.biped else 1.1)
	var old_phase := phase
	phase += (spd * delta / stride) * TAU * 0.5 * signf(f.speed if f.speed != 0.0 else 1.0)
	var gait := clampf(spd / maxf(1.0, top * 0.6), 0.0, 1.0)
	if f.alive and f.down <= 0.0 and int(floor(phase / PI)) != int(floor(old_phase / PI)) and spd > 0.6:
		_step_side = 1 - _step_side
		if on_step.is_valid():
			on_step.call(self, gait)

	# lying down / dead: roll onto the side
	var want_roll := 0.0
	if not f.alive or f.down > 0.0:
		want_roll = 1.35
	roll = move_toward(roll, want_roll, delta * (2.2 if want_roll > roll else 1.2))
	body.rotation.x = roll * (1.0 if f.idx == 0 else -1.0)
	var lie_drop: float = (float(pts.torso.y) - float(b.torso_w) * 0.45) * clampf(roll / 1.35, 0.0, 1.0)
	body.position.y = -lie_drop
	# breathing and bob
	var tired := 1.0 - clampf(f.stamina / 0.5, 0.0, 1.0)
	torso.position.y = sin(phase * 2.0) * 0.04 * float(b.hip_h) * gait + sin(t * (2.0 + 3.0 * tired)) * 0.02 * (1.0 + 2.0 * tired)
	flinch = move_toward(flinch, 0.0, delta * 3.0)
	torso.rotation.z = -flinch * 0.08

	# legs
	for L in legs:
		var hip: Node3D = L.hip
		var knee: Node3D = L.knee
		var ph := phase + (PI if L.side > 0 else 0.0) + (PI if L.front else 0.0)
		var sw := sin(ph) * 0.5 * gait
		var kb := maxf(0.0, -cos(ph)) * 0.7 * gait
		var broken: bool = f.broken.has(L.zone)
		if roll > 0.3:
			sw = 0.6 * (1.0 if L.front else -0.6) + (sin(t * 7.0 + L.side) * 0.15 if f.alive and f.down_perm else 0.0)
			kb = 0.4
		if broken:
			sw = 0.25
			kb = 1.1
		if f.latch.size() > 0:
			sw = sin(t * 11.0 + L.side) * 0.9
			kb = 0.8 + 0.5 * sin(t * 11.0 + L.side)
		if cheer > 0.0:
			sw = sin(t * 9.0 + L.side * 1.5) * 0.35
			kb = 0.2 + 0.2 * sin(t * 9.0)
		hip.rotation.z = lerp_angle(hip.rotation.z, sw, clampf(delta * 14.0, 0.0, 1.0))
		knee.rotation.z = lerp_angle(knee.rotation.z, (-kb if L.biped else kb), clampf(delta * 14.0, 0.0, 1.0))
	for a in arms:
		a.rotation.z = sin(t * 3.0) * 0.1 + (0.8 if f.latch.size() > 0 else 0.0)

	# what the head, jaw and tail are doing
	var act := f.act
	var want_lunge := 0.0
	var want_jaw := 0.08 + 0.05 * sin(t * 1.3)
	var want_swing := 0.0
	var want_drop := 0.0
	if act.size() > 0:
		var w: Dictionary = act.w
		var ph2: String = act.phase
		if w.has("roar"):
			want_jaw = 0.75 if ph2 == "strike" else 0.3
			want_lunge = 0.15
			want_drop = -0.25
		elif w.get("rear", false):
			var dir := 1.0 if f.opp != null and f.bearing(f.opp.pos) > 0.0 else -1.0
			want_swing = (-0.35 * dir) if ph2 == "wind" else (1.0 * dir if ph2 == "strike" else 0.3 * dir)
		elif w.origin in ["head", "horns"]:
			want_jaw = 0.65 if ph2 == "wind" else (0.05 if ph2 == "strike" else 0.15)
			if w.origin == "horns":
				want_jaw = 0.1
				want_drop = 0.35 if ph2 == "wind" else -0.1
			want_lunge = -0.25 if ph2 == "wind" else (1.0 if ph2 == "strike" else 0.3)
			if f.opp != null:
				var zh: float = f.to_world(f._origin_local(w)).y
				var tz := zh
				for z in f.opp.zones_world():
					if z.zone == act.zone:
						tz = z.c.y
				want_drop += clampf((zh - tz) / 4.0, -0.4, 0.8)
		elif w.origin == "feet":
			want_lunge = 0.3
		elif w.origin == "chest":
			want_lunge = 0.5 if ph2 == "strike" else 0.0
	if f.hold.size() > 0:
		shake_t += delta
		want_jaw = 0.12
		want_lunge = 0.8
		want_drop = 0.3
	if f.held_by != null or f.latched_by != null:
		flinch = maxf(flinch, 0.5 + 0.3 * sin(t * 13.0))
	if not f.alive:
		want_jaw = 0.4
		want_drop = 0.5
	if cheer > 0.0:
		cheer -= delta
		want_jaw = 0.7 + 0.1 * sin(t * 6.0)
		want_drop = -0.35
		want_lunge = 0.1
	lunge = move_toward(lunge, want_lunge, delta * 6.0)
	jaw = move_toward(jaw, want_jaw, delta * 7.0)
	swing = move_toward(swing, want_swing, delta * (8.0 if absf(want_swing) > absf(swing) else 3.0))
	neck_piv.rotation.z = -want_drop * 0.7 + lunge * -0.15 + (sin(shake_t * 18.0) * 0.12 if f.hold.size() > 0 else 0.0)
	neck_piv.rotation.y = sin(t * 0.7 + f.idx) * 0.08 + (sin(shake_t * 15.0) * 0.25 if f.hold.size() > 0 else 0.0)
	neck_piv.position = pts.neck_base + Vector3(lunge * 0.45 * float(b.head_len), 0, 0)
	head_piv.rotation.z = -want_drop * 0.4
	jaw_piv.rotation.z = -jaw * 0.6
	var sway := sin(t * 1.2 + f.idx * 2.0) * 0.06 + sin(phase) * 0.07 * gait
	for i in tail_pivs.size():
		var k := float(i + 1) / tail_pivs.size()
		tail_pivs[i].rotation.y = sway * (0.6 + k) + swing * 0.28
		tail_pivs[i].rotation.z = (0.05 if i == 0 else 0.0) + (-0.12 if not f.alive else 0.0)
	if f.broken.has("tail"):
		tail_pivs[2].rotation.z = -0.5

	# label
	if show_intent and f.alive:
		label.text = "%s · %s\n%s" % [f.spname, f.pname, f.mode]
	else:
		label.text = "%s · %s" % [f.spname, f.pname] if f.alive else ("%s · dead" % f.spname if not f.fled else "")
	label.visible = not f.fled

	drip.emitting = f.bleed > 0.0012 and f.alive
	drip.amount = 40
	drip.speed_scale = clampf(f.bleed * 250.0, 0.4, 2.5)
	visible = not (f.fled and (position - Vector3.ZERO).length() > Duel.ARENA_R + 20.0)


func add_wound(zone: String, units: float) -> void:
	if wounds > 40:
		return
	wounds += 1
	var c := Vector3.ZERO
	var r := 0.3
	var cands: Array = []
	for h in f.hb_local:
		if h.zone == zone:
			cands.append(h)
	if cands.is_empty():
		return
	var h: Dictionary = cands[randi() % cands.size()]
	c = h.c
	r = h.r
	var dir := Vector3(randf_range(-0.4, 0.4), randf_range(0.2, 1.0), randf_range(-1.0, 1.0)).normalized()
	var m := MeshInstance3D.new()
	var s := SphereMesh.new()
	var sz := clampf(0.08 + units * 0.25, 0.08, 0.45) * clampf(f.size_k * 0.6, 0.5, 1.4)
	s.radius = sz
	s.height = sz * 0.8
	s.radial_segments = 8
	s.rings = 4
	m.mesh = s
	m.material_override = wound_mat
	m.position = c + dir * r * 0.92
	m.scale = Vector3(1.4, 0.6, 1.0)
	torso.add_child(m)
	flinch = 1.0


func start_cheer(s: float) -> void:
	cheer = s
