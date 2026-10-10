class_name Cli
extends RefCounted
## Headless runs (no window, no rendering):
##   godot --headless --path . -- --sim=50 --a=rex --b=trike [--pa=Stalker --pb=Bulwark] [--seed=1] [--log]
##   godot --headless --path . -- --matrix=40        every species against every other, Balanced v Balanced
##   godot --headless --path . -- --presets=40 --a=rex --b=trike   each preset on A v Balanced B, then on B v Balanced A
## Prints per-run lines and a SUMMARY {json} line.


static func personality(name: String, custom: String, rng: RandomNumberGenerator) -> Array:
	var pn := Personality.resolve(name)
	if custom != "":
		var p := Personality.preset("Balanced")
		for kv in custom.split(",", false):
			var a := kv.split(":")
			if a.size() == 2 and Personality.TRAITS.has(a[0]):
				p.t[a[0]] = clampf(float(a[1]), 0.0, 1.0)
		return [p, "Custom"]
	return [Personality.preset(pn, rng), pn]


static func run_pair(sa: String, pa: String, sb: String, pb: String, n: int, seed0: int, both_ends: bool = false) -> Batch:
	var bt := Batch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = maxi(seed0, 0) + 99991
	for i in n:
		var A := personality(pa, "", rng)
		var B := personality(pb, "", rng)
		var d := Duel.new()
		var flip := both_ends and i % 2 == 1
		if flip:
			d.setup(sb, B[0], B[1], sa, A[0], A[1], seed0 + i if seed0 >= 0 else -1)
		else:
			d.setup(sa, A[0], A[1], sb, B[0], B[1], seed0 + i if seed0 >= 0 else -1)
		var r := d.run_to_end()
		d.dispose()
		if flip:
			r = _flip(r)
		bt.add(r)
	return bt


static func _flip(r: Dictionary) -> Dictionary:
	var o := r.duplicate()
	o.winner = -1 if r.winner < 0 else 1 - int(r.winner)
	o.fighters = [r.fighters[1], r.fighters[0]]
	o.species = [r.species[1], r.species[0]]
	o.preset = [r.preset[1], r.preset[0]]
	return o


static func run(args: Dictionary) -> void:
	var seed0 := int(args.get("seed", "1"))
	var sa := Species.resolve(String(args.get("a", "rex")))
	var sb := Species.resolve(String(args.get("b", "trike")))
	var t0 := Time.get_ticks_msec()
	if args.has("matrix"):
		var n := int(args.matrix)
		var rows := {}
		print("Species matrix, Balanced v Balanced, %d duels per pairing (both ends)" % n)
		for a in Species.ORDER:
			rows[a] = {}
			for b in Species.ORDER:
				if a == b:
					continue
				var bt := run_pair(a, "Balanced", b, "Balanced", n, seed0, true)
				rows[a][b] = bt.win_pct(0)
				print("  %-13s v %-13s %5.1f%%  avg %3.0fs  %s" % [a, b, bt.win_pct(0), bt.t_sum / bt.n, JSON.stringify(bt.how)])
		var hdr := "%-13s" % ""
		for b in Species.ORDER:
			hdr += " %6s" % Species.DATA[b].id
		print(hdr)
		for a in Species.ORDER:
			var line := "%-13s" % a
			var tot := 0.0
			for b in Species.ORDER:
				line += "   ----" if a == b else " %5.0f%%" % rows[a][b]
				if a != b:
					tot += rows[a][b]
			print(line + "   avg %.0f%%" % (tot / 5.0))
		print("SUMMARY " + JSON.stringify({"matrix": rows, "n": n}))
	elif args.has("presets"):
		var n := int(args.presets)
		var out := {}
		for side in 2:
			var me := sa if side == 0 else sb
			var other := sb if side == 0 else sa
			print("Presets on %s v Balanced %s, %d duels each (both ends)" % [me, other, n])
			var base := run_pair(me, "Balanced", other, "Balanced", n, seed0, true)
			print("  %-10s %5.1f%%  (baseline)  avg %3.0fs %s" % ["Balanced", base.win_pct(0), base.t_sum / base.n, JSON.stringify(base.how)])
			for pn in Personality.ORDER:
				if pn == "Balanced":
					continue
				var bt := run_pair(me, pn, other, "Balanced", n, seed0, true)
				out["%s/%s" % [me, pn]] = bt.win_pct(0)
				print("  %-10s %5.1f%%  avg %3.0fs %s" % [pn, bt.win_pct(0), bt.t_sum / bt.n, JSON.stringify(bt.how)])
		print("SUMMARY " + JSON.stringify(out))
	else:
		var n := maxi(1, int(args.get("sim", "1")))
		var pa := String(args.get("pa", "Balanced"))
		var pb := String(args.get("pb", "Balanced"))
		var bt := Batch.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = seed0 + 7
		for i in n:
			var A := personality(pa, String(args.get("ca", "")), rng)
			var B := personality(pb, String(args.get("cb", "")), rng)
			var d := Duel.new()
			d.setup(sa, A[0], A[1], sb, B[0], B[1], seed0 + i)
			if args.has("log"):
				d.keep_events = true
				while not d.over:
					d.step()
					d.events.clear()
				for l in d.log_lines:
					print("  %5.1f  %s" % [l[0], l[1]])
			else:
				d.run_to_end()
			var r := d.result
			bt.add(r)
			var fa: Dictionary = r.fighters[0]
			var fb: Dictionary = r.fighters[1]
			print("#%d seed %d: %s in %.0fs | A blood %.2f broken %s | B blood %.2f broken %s" % [i, d.seed_used,
				("draw" if r.winner < 0 else ["A", "B"][r.winner]) + " " + String(r.how), r.t, fa.blood, fa.broken, fb.blood, fb.broken])
		print(bt.one_line())
		var s := bt.summary()
		print("SUMMARY " + JSON.stringify(s))
	print("(%.1fs wall)" % ((Time.get_ticks_msec() - t0) / 1000.0))
