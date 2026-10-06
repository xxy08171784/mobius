extends "res://tests/test_case.gd"
## RouteGraph 纯查询与渐进状态测试（入口/解锁/可达/汇合/visited）。


func run() -> Array[String]:
	reset()
	_test_entry_and_initial_unlock()
	_test_enter_progressive()
	_test_sibling_and_backtrack_locked()
	_test_path_queries()
	_test_merge_same_cell()
	_test_visited_persistence()
	return failures()


## 手搭一个小 DAG：
## row0: 0,1(入口)；row1: 2,3；row2: 4(boss)
## 边 0->2、1->2(汇合)、1->3、2->4、3->4。
func _graph() -> RouteGraph:
	var g := RouteGraph.new()
	g.rows = 2
	g.cols = 2
	var n0 := g.add_node(0, 0, true)
	var n1 := g.add_node(0, 1, true)
	var n2 := g.add_node(1, 0, false)
	var n3 := g.add_node(1, 1, false)
	var n4 := g.add_boss(2)
	g.add_edge(n0.id, n2.id)
	g.add_edge(n1.id, n2.id)
	g.add_edge(n1.id, n3.id)
	g.add_edge(n2.id, n4.id)
	g.add_edge(n3.id, n4.id)
	return g


func _test_entry_and_initial_unlock() -> void:
	var g := _graph()
	var entries := g.get_entry_nodes()
	assert_equal(entries.size(), 2, "两个入口")
	assert_equal(entries[0].col, 0, "入口按 col 升序")
	assert_equal(entries[1].col, 1, "入口按 col 升序")
	var top := g.get_nodes_at_row(2)
	assert_true(top.size() == 1, "boss 行恰一节点")
	if top.size() == 1:
		assert_equal(g.boss_id, top[0].id, "boss_id 指向顶层节点")

	# 初始：入口可进，非入口不可进。
	for e in entries:
		assert_true(g.can_enter(e.id), "初始入口应可进")
	for id in g.nodes:
		var n: MapNodeState = g.nodes[id]
		if not n.is_entry:
			assert_true(not g.can_enter(id), "初始非入口不可进")
	assert_true(not g.can_enter(g.boss_id), "boss 初始不可进")


func _test_enter_progressive() -> void:
	var g := _graph()
	var n0 := g.get_nodes_at_row(0)[0]
	var n2 := g.get_node(g.get_nodes_at_row(0)[0].next_ids[0])
	assert_true(not g.can_enter(n2.id), "未进入任何节点时非入口不可进")
	assert_true(g.enter(n0.id), "进入入口成功")
	assert_true(g.nodes[n0.id].visited, "enter 标记 visited")
	assert_true(not g.can_enter(n0.id), "已访问节点不可再进")
	assert_true(not g.enter(n0.id), "重复进入被拒，零副作用")
	assert_true(g.can_enter(n2.id, n0.id), "从当前节点可进其直接后继")


## 回归：StS 式单路径推进 —— 进入某节点后，同层兄弟与其余入口一律锁定。
func _test_sibling_and_backtrack_locked() -> void:
	var g := _graph()
	var n0 := g.get_nodes_at_row(0)[0]
	var n1 := g.get_nodes_at_row(0)[1]
	assert_true(g.enter(n0.id), "进入入口 n0")
	var n2 := g.get_node(n0.next_ids[0])
	assert_true(g.can_enter(n2.id, n0.id), "n0 的直接后继可进")
	assert_true(not g.can_enter(n1.id, n0.id), "同层兄弟 n1 不可从 n0 进入")
	assert_true(not g.can_enter(n0.id, n0.id), "当前节点不可再进")
	assert_true(not g.can_enter(g.boss_id, n0.id), "boss 非 n0 后继不可进")


func _test_path_queries() -> void:
	var g := _graph()
	var n0 := g.get_nodes_at_row(0)[0]
	var n1 := g.get_nodes_at_row(0)[1]
	var n4 := g.get_node(g.boss_id)
	assert_true(g.has_path(n0.id, n4.id), "入口0 可达 boss")
	assert_true(g.has_path(n1.id, n4.id), "入口1 可达 boss")
	assert_true(not g.has_path(n4.id, n0.id), "反向不可达（边只向高行）")
	assert_true(g.has_path(n0.id, n0.id), "自身可达")


func _test_merge_same_cell() -> void:
	var g := RouteGraph.new()
	var a := g.add_node(2, 3, false)
	var b := g.add_node(2, 3, false)
	assert_true(a == b, "同格 add_node 复用同一节点（汇合）")
	assert_equal(g.nodes.size(), 1, "同格不新建节点")
	assert_true(g.node_at(Vector2i(3, 2)) == a, "node_at 按 (col,row) 查询")


func _test_visited_persistence() -> void:
	var g := _graph()
	var n0 := g.get_nodes_at_row(0)[0]
	g.mark_visited(n0.id)
	assert_true(g.nodes[n0.id].visited, "mark_visited 置位")
	var n2 := g.get_node(n0.next_ids[0])
	assert_true(g.can_enter(n2.id, n0.id), "从已访问节点可进其直接后继")
