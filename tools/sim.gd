extends SceneTree
## godot --headless --path . -s tools/sim.gd -- --sim=20 --a=rex --b=trike
func _init() -> void:
	var d := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			d[kv[0]] = kv[1] if kv.size() > 1 else "1"
	Cli.run(d)
	quit()
