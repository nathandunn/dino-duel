extends SceneTree
## godot --headless --path . -s tools/trace.gd -- --a=allo --b=stego --seed=3 [--every=0.5] [--until=30]
func _init() -> void:
	var d := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			d[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var du := Duel.new()
	du.setup(String(d.get("a", "allo")), Personality.preset(String(d.get("pa", "Balanced"))), String(d.get("pa", "Balanced")), String(d.get("b", "stego")), Personality.preset(String(d.get("pb", "Balanced"))), String(d.get("pb", "Balanced")), int(d.get("seed", "3")))
	var every := float(d.get("every", "0.5"))
	var until := float(d.get("until", "40"))
	var nxt := 0.0
	var seen := 0
	while not du.over and du.t < until:
		du.step()
		while seen < du.log_lines.size():
			print("      >> %5.1f %s" % [du.log_lines[seen][0], du.log_lines[seen][1]])
			seen += 1
		if du.t >= nxt:
			nxt += every
			var a: Fighter = du.f[0]
			var b: Fighter = du.f[1]
			print("%5.1f d=%5.1f | A phi_in_B=%6.0f spd=%4.1f %-22s act=%-8s st=%.2f | B phi_in_A=%6.0f spd=%4.1f %-22s act=%-8s tailreach=%s" % [du.t, a.dist_to(b), a.phi_around(b), a.speed, a.mode, (a.act.w.id + ":" + a.act.phase) if a.act.size() else "", a.stamina, b.phi_around(a), b.speed, b.mode, (b.act.w.id + ":" + b.act.phase) if b.act.size() else "", a._opp_tail_reaches()])
	print(du.result.get("how", "running"))
	quit()
