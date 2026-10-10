class_name Arena
extends Node3D
## A late-Cretaceous clearing: open ground ringed by conifers and cycads, ferns underfoot,
## and the duel's boulders (rebuilt each duel from Duel.obstacles - the simulation steers
## round exactly these). Blood pools and footprints are dropped here by the views.

var rocks: Node3D
var marks: Node3D
var _marks: Array[Node3D] = []
var blood_mat: StandardMaterial3D
var print_mat: StandardMaterial3D


func _ready() -> void:
	_ground()
	_forest()
	rocks = Node3D.new()
	add_child(rocks)
	marks = Node3D.new()
	add_child(marks)
	blood_mat = StandardMaterial3D.new()
	blood_mat.albedo_color = Color(0.2, 0.01, 0.01)
	blood_mat.roughness = 0.2
	blood_mat.metallic_specular = 0.9
	print_mat = StandardMaterial3D.new()
	print_mat.albedo_color = Color(0.22, 0.18, 0.12, 0.55)
	print_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _noise_tex(freq: float, seed_v: int, c0: Color, c1: Color, size := 512) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.frequency = freq
	n.seed = seed_v
	n.fractal_octaves = 4
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	t.color_ramp = g
	return t


func _ground() -> void:
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(260, 260)
	g.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _noise_tex(0.012, 3, Color(0.22, 0.26, 0.12), Color(0.38, 0.35, 0.21))
	mat.uv1_scale = Vector3(12, 12, 12)
	mat.roughness = 0.95
	g.material_override = mat
	add_child(g)
	# a trampled, muddier centre where the fighting happens
	var mud := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = Duel.ARENA_R * 0.9
	cm.bottom_radius = Duel.ARENA_R * 0.9
	cm.height = 0.02
	cm.radial_segments = 48
	mud.mesh = cm
	var mm := StandardMaterial3D.new()
	mm.albedo_texture = _noise_tex(0.03, 9, Color(0.36, 0.30, 0.20, 0.0), Color(0.42, 0.35, 0.24, 0.85))
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.uv1_scale = Vector3(4, 4, 4)
	mm.roughness = 1.0
	mud.material_override = mm
	mud.position.y = 0.01
	add_child(mud)


func _mm(mesh: Mesh, mat: Material, xforms: Array) -> void:
	var mmi := MultiMeshInstance3D.new()
	var m := MultiMesh.new()
	m.transform_format = MultiMesh.TRANSFORM_3D
	m.mesh = mesh
	m.instance_count = xforms.size()
	for i in xforms.size():
		m.set_instance_transform(i, xforms[i])
	mmi.multimesh = m
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mmi)


func _forest() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.45
	trunk.height = 1.0
	trunk.radial_segments = 8
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.radial_segments = 9
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.28, 0.20, 0.13)
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.14, 0.24, 0.13)
	leaf_mat.roughness = 0.9
	var trunks: Array = []
	var cones: Array = []
	for i in 150:
		var a := rng.randf() * TAU
		var r := Duel.ARENA_R + 8.0 + rng.randf() * 55.0
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var h := rng.randf_range(14.0, 30.0)
		var w := rng.randf_range(2.2, 4.2)
		trunks.append(Transform3D(Basis().scaled(Vector3(1.0, h * 0.5, 1.0)), p + Vector3(0, h * 0.25, 0)))
		for k in 3:
			var y := h * (0.35 + 0.2 * k)
			var s := w * (1.0 - 0.25 * k)
			cones.append(Transform3D(Basis().scaled(Vector3(s, h * 0.32, s)), p + Vector3(0, y, 0)))
	_mm(trunk, trunk_mat, trunks)
	_mm(cone, leaf_mat, cones)
	# cycads: stubby trunks with a crown of fronds
	var frond := BoxMesh.new()
	frond.size = Vector3(2.4, 0.05, 0.45)
	var frond_mat := StandardMaterial3D.new()
	frond_mat.albedo_color = Color(0.22, 0.36, 0.16)
	var c_tr: Array = []
	var c_fr: Array = []
	for i in 70:
		var a := rng.randf() * TAU
		var r := Duel.ARENA_R + 2.0 + rng.randf() * 20.0
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var h := rng.randf_range(1.0, 2.6)
		c_tr.append(Transform3D(Basis().scaled(Vector3(1.5, h, 1.5)), p + Vector3(0, h * 0.5, 0)))
		for k in 9:
			var ang := k * TAU / 9.0 + rng.randf() * 0.3
			var bs := Basis(Vector3.UP, ang) * Basis(Vector3.BACK, 0.45)
			c_fr.append(Transform3D(bs, p + Vector3(cos(ang), 0, -sin(ang)) * 1.0 + Vector3(0, h + 0.3, 0)))
	_mm(trunk, trunk_mat, c_tr)
	_mm(frond, frond_mat, c_fr)
	# ferns in the clearing
	var fern := CylinderMesh.new()
	fern.top_radius = 0.0
	fern.bottom_radius = 0.6
	fern.height = 0.7
	fern.radial_segments = 6
	var fern_mat := StandardMaterial3D.new()
	fern_mat.albedo_color = Color(0.26, 0.38, 0.16)
	var ferns: Array = []
	for i in 320:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (Duel.ARENA_R + 18.0)
		if r < 10.0:
			continue
		var s := rng.randf_range(0.5, 1.4)
		ferns.append(Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(cos(a) * r, 0.3 * s, sin(a) * r)))
	_mm(fern, fern_mat, ferns)


func build_rocks(obs: Array) -> void:
	for c in rocks.get_children():
		c.queue_free()
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _noise_tex(0.08, 21, Color(0.28, 0.27, 0.25), Color(0.46, 0.44, 0.40), 128)
	mat.uv1_triplanar = true
	mat.roughness = 0.95
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for o in obs:
		var c: Vector2 = o[0]
		var r: float = o[1]
		for k in 3:
			var m := MeshInstance3D.new()
			var s := SphereMesh.new()
			s.radius = 1.0
			s.height = 2.0
			s.radial_segments = 9
			s.rings = 5
			m.mesh = s
			m.material_override = mat
			var rr := r * (1.0 if k == 0 else 0.55)
			var off := Vector3.ZERO if k == 0 else Vector3(rng.randf_range(-r, r), 0, rng.randf_range(-r, r)) * 0.7
			m.position = Vector3(c.x, rr * 0.45, c.y) + off
			m.scale = Vector3(rr, rr * rng.randf_range(0.7, 1.1), rr * rng.randf_range(0.8, 1.2))
			m.rotation.y = rng.randf() * TAU
			rocks.add_child(m)


func clear_marks() -> void:
	for m in _marks:
		m.queue_free()
	_marks.clear()


func blood_pool(at: Vector3, size: float) -> void:
	_mark(at, size, blood_mat, 0.02)


func footprint(at: Vector3, size: float, rot: float) -> void:
	var m := _mark(at, size, print_mat, 0.015)
	if m != null:
		m.rotation.y = rot
		m.scale = Vector3(1.3, 1.0, 0.8)


func _mark(at: Vector3, size: float, mat: Material, y: float) -> MeshInstance3D:
	if _marks.size() > 220:
		var old: Node3D = _marks.pop_front()
		old.queue_free()
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = size
	cm.bottom_radius = size
	cm.height = 0.01
	cm.radial_segments = 10
	m.mesh = cm
	m.material_override = mat
	m.position = Vector3(at.x, y, at.z)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marks.add_child(m)
	_marks.append(m)
	return m


func splash(at: Vector3, amount: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = int(clampf(10 + amount * 40.0, 10, 60))
	p.lifetime = 0.9
	p.explosiveness = 0.95
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0 + amount * 3.0
	p.gravity = Vector3(0, -9.8, 0)
	var dm := SphereMesh.new()
	dm.radius = 0.05
	dm.height = 0.1
	dm.radial_segments = 6
	dm.rings = 3
	dm.material = blood_mat
	p.mesh = dm
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


func dust(at: Vector3, amount: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = int(clampf(8 + amount * 20.0, 8, 40))
	p.lifetime = 1.4
	p.explosiveness = 0.9
	p.direction = Vector3(0, 1, 0)
	p.spread = 85.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.0 + amount
	p.gravity = Vector3(0, -0.6, 0)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0 + amount * 2.0
	var dm := SphereMesh.new()
	dm.radius = 0.12
	dm.height = 0.24
	dm.radial_segments = 6
	dm.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.47, 0.35, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.material = mat
	p.mesh = dm
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)
