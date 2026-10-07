extends SceneTree
## 在正式 PCK 上运行外部测试，禁止退回工作区 res://；测试脚本不进入发布包。

func _initialize() -> void:
	_start.call_deferred()


func _start() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		quit(2)
		return
	var script := load(args[0]) as Script
	if script == null:
		quit(2)
		return
	var suite := Node.new()
	suite.set_script(script)
	root.add_child(suite)
