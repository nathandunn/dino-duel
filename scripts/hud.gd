class_name Hud
extends CanvasLayer
## All UI in code: clock, a card per animal (blood / stamina / fear bars and its wounds),
## controls, a running log of the fight, and the overlays - Fighters (species + personality
## per side, a preset or your own sliders), Results, and Batch / League reports.

signal new_duel_requested
signal batch_requested(n: int)
signal league_requested(n: int)
signal speed_changed(scale: float)
signal pause_toggled(paused: bool)
signal intents_toggled(on: bool)

const SIDE_NAMES := ["Red", "Blue"]
const SIDE_COLORS := [Color(0.85, 0.3, 0.25), Color(0.3, 0.55, 0.9)]
const PRESETS: Array[String] = ["Balanced", "Berserker", "Stalker", "Bully", "Bleeder", "Bulwark", "Brawler", "Skittish", "Random", "Custom"]

var cfg: Dictionary            # owned by main: species, preset, custom
var duel: Duel
var _root: Control
var clock: Label
var cards: Array = []          # [{title, bars: {blood, stamina, fear}, status}]
var ticker: VBoxContainer
var status_label: Label
var speed_buttons: Array[Button] = []
var setup_btn: Button
var results_btn: Button
var pause_btn: Button
var setup_overlay: Control
var setup_scroll: ScrollContainer
var results_overlay: Control
var results_scroll: ScrollContainer
var results_box: VBoxContainer
var results_title: Label
var next_panel: PanelContainer
var next_label: Label
var sp_pickers: Array[OptionButton] = []
var sp_help: Array[Label] = []
var pr_pickers: Array[OptionButton] = []
var pr_help: Array[Label] = []
var sliders := [{}, {}]
var _updating := false
var last_result := {}
var _log_seen := 0


func setup(config: Dictionary) -> void:
	cfg = config
	var theme := Theme.new()
	theme.default_font_size = 16
	_root = Control.new()
	_root.theme = theme
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(s, 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var row1 := HFlowContainer.new()
	row1.add_theme_constant_override("h_separation", 10)
	row1.add_theme_constant_override("v_separation", 6)
	row1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(row1)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(84, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row1.add_child(gap)
	clock = Label.new()
	clock.add_theme_font_size_override("font_size", 24)
	clock.text = "0:00"
	clock.custom_minimum_size = Vector2(70, 0)
	row1.add_child(clock)
	for s in 2:
		row1.add_child(_card(s))

	var row2 := HFlowContainer.new()
	row2.add_theme_constant_override("h_separation", 6)
	row2.add_theme_constant_override("v_separation", 4)
	row2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(row2)
	pause_btn = Button.new()
	pause_btn.text = "Pause"
	pause_btn.toggle_mode = true
	pause_btn.toggled.connect(func(on: bool): pause_btn.text = "Play" if on else "Pause"; pause_toggled.emit(on))
	row2.add_child(pause_btn)
	for s in [0.5, 1.0, 2.0, 4.0]:
		var b := Button.new()
		b.text = _sp(s)
		b.toggle_mode = true
		b.button_pressed = (s == 1.0)
		b.pressed.connect(func(): set_speed_ui(s); speed_changed.emit(s))
		row2.add_child(b)
		speed_buttons.append(b)
	setup_btn = Button.new()
	setup_btn.text = "Fighters"
	setup_btn.toggle_mode = true
	setup_btn.toggled.connect(func(on: bool): setup_overlay.visible = on; if on: results_overlay.visible = false)
	row2.add_child(setup_btn)
	results_btn = Button.new()
	results_btn.text = "Last results"
	results_btn.disabled = true
	results_btn.pressed.connect(func(): if not last_result.is_empty(): show_result(last_result))
	row2.add_child(results_btn)
	var new_btn := Button.new()
	new_btn.text = "New duel"
	new_btn.pressed.connect(func(): _close_overlays(); new_duel_requested.emit())
	row2.add_child(new_btn)
	for n in [20, 100]:
		var bb := Button.new()
		bb.text = "Sim x%d" % n
		bb.tooltip_text = "Run %d duels of this matchup instantly and show the statistics" % n
		bb.pressed.connect(func(): _close_overlays(); batch_requested.emit(n))
		row2.add_child(bb)
	var lg := Button.new()
	lg.text = "Personality league"
	lg.tooltip_text = "Every personality on Red against Blue's current one, 20 duels each, both ends"
	lg.pressed.connect(func(): _close_overlays(); league_requested.emit(20))
	row2.add_child(lg)
	var intents := Button.new()
	intents.text = "Show intents"
	intents.toggle_mode = true
	intents.toggled.connect(func(on: bool): intents_toggled.emit(on))
	row2.add_child(intents)
	var mute := Button.new()
	mute.text = "Sound on"
	mute.toggle_mode = true
	mute.toggled.connect(func(on: bool): Sfx.set_muted(on); mute.text = "Sound off" if on else "Sound on")
	row2.add_child(mute)

	ticker = VBoxContainer.new()
	ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ticker.add_theme_constant_override("separation", 0)
	vbox.add_child(ticker)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(status_label)

	_build_next()
	_build_setup()
	_build_results()
	get_tree().root.size_changed.connect(_relayout)
	_relayout()


func _bar(parent: Control, label: String, color: Color) -> ProgressBar:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(h)
	var l := _lbl(label, 11, Color(0.85, 0.82, 0.75))
	l.custom_minimum_size = Vector2(52, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	h.add_child(l)
	var pb := ProgressBar.new()
	pb.min_value = 0.0
	pb.max_value = 1.0
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(120, 10)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.45)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(3)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	h.add_child(pb)
	return pb


func _card(s: int) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.05, 0.62)
	sb.border_color = SIDE_COLORS[s]
	sb.border_width_left = 3
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(250, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	var title := _lbl("", 15, SIDE_COLORS[s].lightened(0.35))
	v.add_child(title)
	var bars := {}
	bars["blood"] = _bar(v, "blood", Color(0.75, 0.12, 0.1))
	bars["stamina"] = _bar(v, "stamina", Color(0.85, 0.7, 0.2))
	bars["fear"] = _bar(v, "fear", Color(0.55, 0.45, 0.85))
	var st := _lbl("", 11, Color(0.95, 0.85, 0.7))
	st.custom_minimum_size = Vector2(240, 0)
	v.add_child(st)
	cards.append({"title": title, "bars": bars, "status": st})
	return panel


func _lbl(text: String, size := 14, color := Color(0.92, 0.88, 0.8)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ---------------------------------------------------------------- overlays

func _overlay(title_text: String, on_close: Callable) -> Array:
	var ov := Control.new()
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.visible = false
	_root.add_child(ov)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.06, 0.94)
	sb.border_color = Color(0.55, 0.45, 0.28)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	panel.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	var title := _lbl(title_text, 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): ov.visible = false; on_close.call())
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	outer.add_child(scroll)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return [ov, scroll, content, title]


func _build_next() -> void:
	next_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.08, 0.06, 0.9)
	sb.border_color = Color(0.7, 0.55, 0.3)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(10)
	next_panel.add_theme_stylebox_override("panel", sb)
	next_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	next_panel.visible = false
	_root.add_child(next_panel)
	var v := VBoxContainer.new()
	next_panel.add_child(v)
	next_label = _lbl("", 17, Color(1, 0.9, 0.65))
	next_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	next_label.custom_minimum_size = Vector2(300, 0)
	v.add_child(next_label)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	for pair in [["Next duel", func(): _close_overlays(); new_duel_requested.emit()],
			["Results", func(): if not last_result.is_empty(): show_result(last_result)],
			["Change fighters", func(): setup_btn.button_pressed = true]]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(pair[1])
		h.add_child(b)


func _build_setup() -> void:
	var parts := _overlay("Fighters", func(): setup_btn.set_pressed_no_signal(false))
	setup_overlay = parts[0]
	setup_scroll = parts[1]
	var content: VBoxContainer = parts[2]
	content.add_child(_lbl("Pick an animal and a personality for each corner. The animal decides what it CAN do - its size, speed, weapons and armour; the personality decides what it WANTS to do. Any personality goes on any animal. 'Custom' uses the sliders.", 13))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 24)
	row.add_theme_constant_override("v_separation", 14)
	content.add_child(row)
	for s in 2:
		row.add_child(_side_panel(s))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	content.add_child(h)
	var start := Button.new()
	start.text = "Start the duel"
	start.add_theme_font_size_override("font_size", 18)
	start.pressed.connect(func(): _close_overlays(); new_duel_requested.emit())
	h.add_child(start)
	var swap := Button.new()
	swap.text = "Swap corners"
	swap.pressed.connect(_swap)
	h.add_child(swap)


func _side_panel(s: int) -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(360, 0)
	v.add_child(_lbl("%s corner" % SIDE_NAMES[s], 18, SIDE_COLORS[s].lightened(0.3)))
	v.add_child(_lbl("Animal", 14, Color(1, 0.85, 0.55)))
	var spk := OptionButton.new()
	for n in Species.ORDER:
		spk.add_item(n)
	spk.select(Species.ORDER.find(cfg.species[s]))
	spk.item_selected.connect(func(i: int): cfg.species[s] = Species.ORDER[i]; _refresh_help())
	v.add_child(spk)
	sp_pickers.append(spk)
	var sh := _lbl("", 12, Color(0.82, 0.8, 0.72))
	v.add_child(sh)
	sp_help.append(sh)
	v.add_child(_lbl("Personality", 14, Color(1, 0.85, 0.55)))
	var pp := OptionButton.new()
	for pn in PRESETS:
		pp.add_item(pn)
	pp.select(PRESETS.find(cfg.preset[s]))
	pp.item_selected.connect(func(i: int): cfg.preset[s] = PRESETS[i]; _refresh_help())
	v.add_child(pp)
	pr_pickers.append(pp)
	var ph := _lbl("", 12, Color(0.82, 0.8, 0.72))
	v.add_child(ph)
	pr_help.append(ph)
	v.add_child(_lbl("Traits (dragging one switches to Custom)", 13, Color(1, 0.85, 0.55)))
	var grid := GridContainer.new()
	grid.columns = 2
	v.add_child(grid)
	for k in Personality.TRAITS:
		var kl := _lbl(k, 13)
		kl.tooltip_text = String(Personality.TRAIT_HELP[k])
		kl.mouse_filter = Control.MOUSE_FILTER_STOP
		kl.custom_minimum_size = Vector2(96, 0)
		grid.add_child(kl)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.custom_minimum_size = Vector2(220, 22)
		sl.tooltip_text = String(Personality.TRAIT_HELP[k])
		sl.value = (cfg.custom[s] as Personality).g(k)
		var key: String = k
		sl.value_changed.connect(func(val: float):
			if _updating:
				return
			(cfg.custom[s] as Personality).t[key] = val
			cfg.preset[s] = "Custom"
			pr_pickers[s].select(PRESETS.find("Custom"))
			_refresh_help())
		grid.add_child(sl)
		sliders[s][k] = sl
	_refresh_help.call_deferred()
	return v


func _swap() -> void:
	var sp: Array = cfg.species
	var pr: Array = cfg.preset
	var cu: Array = cfg.custom
	cfg.species = [sp[1], sp[0]]
	cfg.preset = [pr[1], pr[0]]
	cfg.custom = [cu[1], cu[0]]
	for s in 2:
		sp_pickers[s].select(Species.ORDER.find(cfg.species[s]))
		pr_pickers[s].select(PRESETS.find(cfg.preset[s]))
	_refresh_help()


func _refresh_help() -> void:
	for s in sp_help.size():
		var d: Dictionary = Species.get_data(cfg.species[s])
		sp_help[s].text = "%s\n%s\nWeapons: %s" % [d.blurb, d.era, ", ".join(d.weapons.map(func(w): return String(w.name)))]
		var pn: String = cfg.preset[s]
		pr_help[s].text = "Your own mix from the sliders below" if pn == "Custom" else String(Personality.PRESET_HELP.get(pn, ""))
		if pn != "Custom" and pn != "Random" and not sliders[s].is_empty():
			_updating = true
			var p := Personality.preset(pn)
			(cfg.custom[s] as Personality).t = p.t.duplicate()
			for k in Personality.TRAITS:
				sliders[s][k].value = p.g(k)
			_updating = false


func _build_results() -> void:
	var parts := _overlay("Results", func(): pass)
	results_overlay = parts[0]
	results_scroll = parts[1]
	results_box = parts[2]
	results_title = parts[3]


func _close_overlays() -> void:
	setup_overlay.visible = false
	results_overlay.visible = false
	next_panel.visible = false
	setup_btn.set_pressed_no_signal(false)


func _relayout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var w := vs.x
	var h := vs.y
	setup_scroll.custom_minimum_size = Vector2(minf(820.0, w - 40.0), minf(620.0, h - 110.0))
	results_scroll.custom_minimum_size = Vector2(minf(820.0, w - 40.0), minf(620.0, h - 110.0))
	next_panel.position = Vector2(w * 0.5 - 170.0, h - 130.0)
	for c in cards:
		(c.status as Label).custom_minimum_size = Vector2(minf(240.0, w * 0.4), 0)


static func _sp(s: float) -> String:
	return ("%dx" % int(s)) if is_equal_approx(s, round(s)) else ("%.1fx" % s)


func set_speed_ui(s: float) -> void:
	for b in speed_buttons:
		b.set_pressed_no_signal(b.text == _sp(s))


func set_status(text: String) -> void:
	status_label.text = text


# ---------------------------------------------------------------- live

func on_duel_started(d: Duel) -> void:
	duel = d
	_log_seen = 0
	next_panel.visible = false
	results_overlay.visible = false
	for c in ticker.get_children():
		c.queue_free()
	set_status("%s (%s) v %s (%s) - seed %d. Drag to orbit, pinch or scroll to zoom." % [d.f[0].spname, d.f[0].pname, d.f[1].spname, d.f[1].pname, d.seed_used])


func _process(_delta: float) -> void:
	if duel == null or duel.f.is_empty():
		return
	var t := duel.t
	clock.text = "%d:%02d" % [int(t) / 60, int(t) % 60]
	for s in 2:
		var x: Fighter = duel.f[s]
		var c: Dictionary = cards[s]
		(c.title as Label).text = "%s · %s" % [x.spname, x.pname]
		var bars: Dictionary = c.bars
		(bars.blood as ProgressBar).value = clampf((x.blood - Fighter.BLED_OUT) / (1.0 - Fighter.BLED_OUT), 0.0, 1.0)
		(bars.stamina as ProgressBar).value = x.stamina
		(bars.fear as ProgressBar).value = clampf(x.fear / maxf(0.05, x.flee_threshold()), 0.0, 1.0)
		var lines := x.status_lines()
		var txt := x.mode if x.alive and not x.fled else ""
		if lines.size() > 0:
			txt = (txt + " - " if txt != "" else "") + ", ".join(lines)
		(c.status as Label).text = txt
	while _log_seen < duel.log_lines.size():
		var l: Array = duel.log_lines[_log_seen]
		_log_seen += 1
		var who: int = l[2]
		var col: Color = Color(1, 0.9, 0.6) if who < 0 else SIDE_COLORS[who].lightened(0.45)
		var lab := _lbl("%d:%02d  %s" % [int(l[0]) / 60, int(l[0]) % 60, l[1]], 13, col)
		ticker.add_child(lab)
		while ticker.get_child_count() > 6:
			var old := ticker.get_child(0)
			ticker.remove_child(old)
			old.queue_free()


func show_next(text: String) -> void:
	next_label.text = text
	next_panel.visible = true


# ---------------------------------------------------------------- results

func _clear_results() -> void:
	for c in results_box.get_children():
		c.queue_free()
	results_scroll.scroll_vertical = 0


func _grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 2)
	results_box.add_child(g)
	return g


func _cell(g: GridContainer, text: String, color := Color(0.92, 0.88, 0.8), size := 13) -> void:
	var l := _lbl(text, size, color)
	# autowrapping labels in a grid collapse to one letter wide unless given a width
	var w := results_scroll.custom_minimum_size.x - 24.0
	var col := g.get_child_count() % g.columns
	var first := minf(150.0, w * 0.28)
	if g.columns == 4:
		l.custom_minimum_size.x = [w * 0.26, w * 0.14, w * 0.14, w * 0.38][col]
	else:
		l.custom_minimum_size.x = first if col == 0 else (w - first) / float(g.columns - 1) - 14.0
	g.add_child(l)


func _side_title(s: int, sp: String, pr: String) -> String:
	return "%s: %s (%s)" % [SIDE_NAMES[s], sp, pr]


func show_result(r: Dictionary) -> void:
	last_result = r
	results_btn.disabled = false
	_clear_results()
	var w: int = r.winner
	var head := "Draw" if w < 0 else "%s wins" % _side_title(w, r.species[w], r.preset[w])
	results_title.text = "%s - %s, %d:%02d" % [head, String(r.how).replace("killed: ", ""), int(r.t) / 60, int(r.t) % 60]
	var g := _grid(3)
	_cell(g, "", Color.WHITE)
	for s in 2:
		_cell(g, _side_title(s, r.species[s], r.preset[s]), SIDE_COLORS[s].lightened(0.35), 14)
	var rows := [
		["Outcome", func(fd): return ("dead - " + String(fd.cause)) if not fd.alive else ("fled" if fd.fled else "standing")],
		["Blood left", func(fd): return "%d%%" % int(fd.blood * 100.0)],
		["Stamina left", func(fd): return "%d%%" % int(fd.stamina * 100.0)],
		["Broken", func(fd): return ", ".join(fd.broken.map(func(z): return "face" if z == "jaw" else String(Species.ZONES[z].label))) if fd.broken.size() > 0 else "-"],
		["Damage dealt", func(fd): return "%.2f" % float(fd.stats.dmg_dealt)],
		["Wounds taken", func(fd): return _wounds(fd.stats.taken)],
		["Bled", func(fd): return "%d%% of its blood" % int(float(fd.stats.bled_s) * 100.0)],
		["Holds / pins / charges", func(fd): return "%d / %d / %d" % [fd.stats.holds, fd.stats.latches, fd.stats.charges]],
		["Knockdowns dealt", func(fd): return str(fd.stats.kd_dealt)],
		["Roars / dodges", func(fd): return "%d / %d" % [fd.stats.roars, fd.stats.dodges]],
		["Peak fear", func(fd): return "%d%%" % int(float(fd.stats.max_fear) * 100.0)],
		["Exhausted", func(fd): return "%.0f s" % float(fd.stats.exhausted_s)],
		["Ground covered", func(fd): return "%.0f m" % float(fd.travelled)],
	]
	for row in rows:
		_cell(g, row[0], Color(1, 0.85, 0.55))
		for s in 2:
			_cell(g, row[1].call(r.fighters[s]))
	results_box.add_child(_lbl("Weapons (tries: hit / missed / dodged, damage)", 15, Color(1, 0.85, 0.55)))
	var g2 := _grid(3)
	_cell(g2, "")
	for s in 2:
		_cell(g2, SIDE_NAMES[s], SIDE_COLORS[s].lightened(0.35))
	var maxw := 0
	for s in 2:
		maxw = maxi(maxw, r.fighters[s].stats.attacks.size())
	var keys := [r.fighters[0].stats.attacks.keys(), r.fighters[1].stats.attacks.keys()]
	for i in maxw:
		_cell(g2, "")
		for s in 2:
			if i < keys[s].size():
				var a: Dictionary = r.fighters[s].stats.attacks[keys[s][i]]
				_cell(g2, "%s %d: %d / %d / %d, %.2f" % [a.name, a.tries, a.hits, a.missed, a.dodged, a.dmg])
			else:
				_cell(g2, "")
	if duel != null and duel.log_lines.size() > 0 and duel.result == r:
		results_box.add_child(_lbl("How it went", 15, Color(1, 0.85, 0.55)))
		for l in duel.log_lines:
			var who: int = l[2]
			results_box.add_child(_lbl("%d:%02d  %s" % [int(l[0]) / 60, int(l[0]) % 60, l[1]], 12, Color(1, 0.9, 0.6) if who < 0 else SIDE_COLORS[who].lightened(0.5)))
	results_overlay.visible = true
	setup_overlay.visible = false
	setup_btn.set_pressed_no_signal(false)


func _wounds(taken: Dictionary) -> String:
	var ks := taken.keys()
	ks.sort_custom(func(a, b): return taken[a] > taken[b])
	var parts: Array[String] = []
	for k in ks.slice(0, 4):
		parts.append("%s %.2f" % [Species.ZONES[k].label, taken[k]])
	return ", ".join(parts) if parts.size() > 0 else "-"


func show_batch(bt: Batch) -> void:
	_clear_results()
	var s := bt.summary()
	results_title.text = "%d duels: %s %s %.0f%% - %.0f%% %s %s" % [bt.n, bt.species[0], "(%s)" % bt.preset[0], bt.win_pct(0), bt.win_pct(1), bt.species[1], "(%s)" % bt.preset[1]]
	results_box.add_child(_lbl("Wins %d - %d, draws %d. Win rates are +-%.0f points (1 sigma) at this sample size. Average duel %.0f s." % [bt.wins[0], bt.wins[1], bt.draws, bt.sigma(), s.avg_t], 13))
	var how_parts: Array[String] = []
	var hk: Array = bt.how.keys()
	hk.sort_custom(func(a, b): return bt.how[a] > bt.how[b])
	for k in hk:
		how_parts.append("%s %d" % [String(k).replace("killed: ", ""), bt.how[k]])
	results_box.add_child(_lbl("How they ended: " + ", ".join(how_parts), 13))
	var g := _grid(3)
	_cell(g, "")
	for i in 2:
		_cell(g, _side_title(i, bt.species[i], bt.preset[i]), SIDE_COLORS[i].lightened(0.35), 14)
	var n := float(maxi(bt.n, 1))
	var rows := [
		["Won", func(sd, i): return "%d (%.0f%%)" % [bt.wins[i], bt.win_pct(i)]],
		["Died / fled", func(sd, i): return "%d / %d" % [sd.died, sd.fled]],
		["Causes of death", func(sd, i): return _top(sd.causes, 3)],
		["Broken (per duel)", func(sd, i): return _per(sd.breaks, n, 4)],
		["Wounds taken (per duel)", func(sd, i): return _per(sd.taken, n, 4)],
		["Damage dealt / duel", func(sd, i): return "%.2f" % (sd.dmg / n)],
		["Blood left, avg", func(sd, i): return "%d%%" % int(sd.blood_end / n * 100.0)],
		["Holds / pins / charges", func(sd, i): return "%.1f / %.1f / %.1f" % [sd.holds / n, sd.latches / n, sd.charges / n]],
		["Knockdowns / roars / dodges", func(sd, i): return "%.1f / %.1f / %.1f" % [sd.kd_dealt / n, sd.roars / n, sd.dodges / n]],
		["Exhausted, avg", func(sd, i): return "%.1f s" % (sd.exhausted_s / n)],
	]
	for row in rows:
		_cell(g, row[0], Color(1, 0.85, 0.55))
		for i in 2:
			_cell(g, row[1].call(bt.side[i], i))
	results_box.add_child(_lbl("Weapons (hit rate of tries, damage per duel)", 15, Color(1, 0.85, 0.55)))
	var g2 := _grid(3)
	var ks := [bt.side[0].weapons.keys(), bt.side[1].weapons.keys()]
	for k in maxi(ks[0].size(), ks[1].size()):
		_cell(g2, "")
		for i in 2:
			if k < ks[i].size():
				var a: Dictionary = bt.side[i].weapons[ks[i][k]]
				_cell(g2, "%s: %.1f tries, %d%% hit, %d%% missed, %d%% dodged, %.2f dmg" % [a.name, a.tries / n, _pc(a.hits, a.tries), _pc(a.missed, a.tries), _pc(a.dodged, a.tries), a.dmg / n])
			else:
				_cell(g2, "")
	results_overlay.visible = true


func show_league(rows: Array, base: Dictionary, n: int) -> void:
	_clear_results()
	results_title.text = "Personality league: %s (each) v %s (%s)" % [base.species_a, base.species_b, base.preset_b]
	results_box.add_child(_lbl("Every personality on the Red animal against Blue as set, %d duels each, half from each end. +-%.0f points (1 sigma)." % [n, 100.0 * sqrt(0.25 / n)], 13))
	var g := _grid(4)
	for h in ["Personality", "Win %", "Avg time", "Mostly ends by"]:
		_cell(g, h, Color(1, 0.85, 0.55))
	rows.sort_custom(func(a, b): return a.pct > b.pct)
	for r in rows:
		_cell(g, r.preset)
		_cell(g, "%.0f%%" % r.pct, Color(0.6, 1, 0.6) if r.pct >= 55.0 else (Color(1, 0.6, 0.55) if r.pct <= 45.0 else Color(0.92, 0.88, 0.8)))
		_cell(g, "%.0f s" % r.t)
		_cell(g, r.how)
	results_overlay.visible = true


static func _pc(a: int, b: int) -> int:
	return int(round(100.0 * a / maxf(1.0, b)))


func _top(d: Dictionary, k: int) -> String:
	var ks := d.keys()
	ks.sort_custom(func(a, b): return d[a] > d[b])
	var parts: Array[String] = []
	for x in ks.slice(0, k):
		parts.append("%s %d" % [x, d[x]])
	return ", ".join(parts) if parts.size() > 0 else "-"


func _per(d: Dictionary, n: float, k: int) -> String:
	var ks := d.keys()
	ks.sort_custom(func(a, b): return d[a] > d[b])
	var parts: Array[String] = []
	for x in ks.slice(0, k):
		var lab: String = "face" if x == "jaw" else String(Species.ZONES[x].label)
		parts.append("%s %.2f" % [lab, float(d[x]) / n])
	return ", ".join(parts) if parts.size() > 0 else "-"
