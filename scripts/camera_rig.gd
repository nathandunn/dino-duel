class_name CameraRig
extends Node3D
## Orbit camera that keeps both animals in frame: it follows their midpoint and pulls back as
## they separate. Drag to rotate (mouse or one finger), wheel or pinch to zoom; your zoom is
## a multiplier on the automatic framing, so it sticks.

var yaw := 0.9
var pitch := 0.5
var zoom := 1.0
var _cam: Camera3D
var _dragging := false
var _touches := {}
var _pinch_d := 0.0
var focus := Vector3(0, 2.0, 0)
var want_focus := Vector3(0, 2.0, 0)
var dist := 30.0
var want_dist := 30.0


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.fov = 55.0
	_cam.keep_aspect = Camera3D.KEEP_WIDTH
	_cam.far = 400.0
	add_child(_cam)
	_apply()


func frame(a: Vector3, b: Vector3, size: float) -> void:
	var mid := (a + b) * 0.5
	want_focus = Vector3(mid.x, clampf(size * 0.18, 1.0, 2.5), mid.z)
	var sep := Vector2(a.x - b.x, a.z - b.z).length()
	want_dist = clampf(sep * 0.85 + size * 1.7 + 6.0, 14.0, 100.0)
	# the camera keeps the width, so a tall phone screen needs it closer
	var vs := get_viewport().get_visible_rect().size
	if vs.y > vs.x:
		want_dist *= clampf(vs.x / vs.y * 1.25, 0.55, 1.0)


func _process(delta: float) -> void:
	var k := clampf(delta * 2.5, 0.0, 1.0)
	focus = focus.lerp(want_focus, k)
	dist = lerpf(dist, want_dist * zoom, clampf(delta * 1.5, 0.0, 1.0))
	_apply()


func _apply() -> void:
	pitch = clampf(pitch, 0.08, 1.4)
	zoom = clampf(zoom, 0.35, 2.5)
	var p := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	_cam.position = focus + p
	if _cam.position.y < 1.0:
		_cam.position.y = 1.0
	_cam.look_at(focus, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom *= 0.9
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom *= 1.1
	elif event is InputEventMouseMotion and _dragging:
		yaw -= event.relative.x * 0.006
		pitch += event.relative.y * 0.006
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() == 2:
			var pts := _touches.values()
			_pinch_d = pts[0].distance_to(pts[1])
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			yaw -= event.relative.x * 0.008
			pitch += event.relative.y * 0.008
		elif _touches.size() == 2:
			var pts := _touches.values()
			var d: float = pts[0].distance_to(pts[1])
			if _pinch_d > 0.0:
				zoom *= _pinch_d / maxf(d, 1.0)
			_pinch_d = d
