extends SceneTree

func _initialize() -> void:
	var samples := 6
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		samples = maxi(1, int(args[0]))
	var simulation: RefCounted = load("res://tools/balance_simulation.gd").new()
	simulation.run(samples)
	simulation = null
	quit(0)
