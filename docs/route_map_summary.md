# 选关地图规则层 — 工作总结

日期：2026-10-05。分支：`xxy`。范围：**规则层 + 生成 + 无头测试**（UI 轮未做，见文末）。
配套合同文档：`docs/route_map_rules.md`（算法精确合同，实现改动需同步更新）。

## 1. 做了什么

在战斗地基并行开发期间，单独完成选关地图的**规则层**：StS 式 DAG 生成、图数据结构、解锁/可达查询，全部脱离 SceneTree、可无头测试、确定性可回放。与战斗层零依赖（不碰 `core/`、`gameplay/battle/`），不与分工文档 §7 禁区冲突。

## 2. 交付文件

| 文件 | 类 | 职责 |
|---|---|---|
| `gameplay/run/route_map_def.gd` | `RouteMapDef extends Resource` | 生成配置（行列/路径数/固定行/楼层下限/权重/特殊类型）+ 7 个标准类型键 `const` |
| `gameplay/run/map_node_state.gd` | `MapNodeState extends RefCounted` | 单节点数据：`id`/`row`/`col`/`type_key`/`content_id`/`visited`/`prev_ids`/`next_ids`/`is_entry` |
| `gameplay/run/route_graph.gd` | `RouteGraph extends RefCounted` | DAG 数据 + 纯查询：`get_nodes_at_row`/`get_entry_nodes`/`node_at`/`can_enter`/`enter`/`has_path`/`mark_visited` |
| `gameplay/run/map_generator.gd` | `MapGenerator extends RefCounted` | **纯函数** `static generate(def, rng) -> RouteGraph` |
| `content/maps/route_map_default.tres` | `RouteMapDef` 实例 | 默认 StS 参数（设计师调参面；当前用脚本默认值，Inspector 编辑即可覆盖） |
| `tests/rules/map_generator_test.gd` | `MapGeneratorTest extends RefCounted` | 9 组断言，`run_all() -> Array[String]`（空=全过） |
| `tools/run_map_tests.gd` | 临时 `SceneTree` 脚本 | 无头测试入口（Phase 0 的 `run_all.gd` 落地后可删） |
| `docs/route_map_rules.md` | 文档 | 冻结的生成算法合同 |
| `docs/directory_structure.md` | 文档 | 更新 `run/`、`content/maps/`、docs 表的状态标记 |

## 3. 核心设计

### 类型键 = 美术/内容索引契约（本轮冻结）

```
node.monster  node.elite  node.rest  node.shop  node.treasure  node.event  node.boss
```

- 键同时是**内容查找前缀**与**下一轮美术槽位索引**（`RouteMapSkin.nodes[type_key]`）。
- 表现状态（available/locked/visited/current）**是派生值，不存图**：只有 `visited` 持久化，`current` 归 `RunState.current_node_id`。避免美术状态与存档不同步。
- 入口不设 `start` 节点：row 0 全是 `node.monster`，玩家选一个进场（StS 手感）。

### StS 式 DAG 生成（`MapGenerator`）

纯函数、RNG 入参注入、确定性 = `(def, rng 初始状态)`：

1. **入口列**：`[0, cols-1]` Fisher-Yates 洗牌取前 `path_count` → 入口互不相同、覆盖全宽。
2. **路径游走**：每条路径从入口逐层上行，每步在合法候选（界内且不交叉）中**均匀选列**；上一步竖直时优先斜向，避免叠成长廊。到已有格即**汇合**（DAG）。
3. **无交叉不变量**：新边与同层边水平顺序翻转则该候选被剔除。竖直边**证明恒不交叉** → 候选永不为空，路径永不中断，**每个入口必可达 boss（无陷阱入口）**。
4. **类型分配**（自上而下）：固定行强制；其余按权重抽签，过滤楼层下限 + "特殊类型（rest/shop/elite）不相邻"约束，冲突降级。

### 解锁规则（`RouteGraph`）

`can_enter(id)` = 未访问 且（是入口 或 任一前置已访问）。初始仅入口可进。

## 4. 验证结果

| 项 | 结果 |
|---|---|
| 无头测试 `tools/run_map_tests.gd` | **PASS**（确定性 / 固定行 / boss / 无交叉 / DAG 连通 / 相邻约束 / 下限 / 分布 / 解锁） |
| 编辑器扫描 `--headless --editor` | 无 `SCRIPT ERROR` / `Parse Error` |
| ASCII dump 肉眼检查 | 6 入口、row 0 战斗 / row 3 宝箱 / row 6 休息、其余行随机（战斗/事件/精英/休息/商店）、单 boss（2026-10-06 短章节改版） |
| 1000 seed 压测 | **无空行**；单节点瓶颈行约 0.3%（与 StS 原版一致，已记入文档取舍） |
| `.tres` 加载 | 默认值正确应用，可正常生成 |

命令（Godot 4.7.2 mono，见记忆 `godot-toolchain`）：

```bash
"<godot_exe>" --headless --path "D:/mobius" --script res://tools/run_map_tests.gd
"<godot_exe>" --headless --editor --quit-after 30 --path "D:/mobius"
```

## 5. 后续（不在本轮）

- **UI 轮** `presentation/screens/route_map/`：
  - `RouteMapSkin` + `MapNodeVisual`（Resource）：背景 / 路径线贴图 / 每 `type_key` 图标（未解锁/可选/已访问/当前）/ 按钮四态 StyleBox。接入优先级：**显式槽位 > PNG 命名约定 > 占位色块**。
  - `route_map.tscn/.gd`（**只读** RunState 的图渲染，点击走规则入口）、`map_node_view.tscn/.gd`、`route_edges_view.gd`。
- **接 RunState**：`RunState.map: RouteGraph` + `RunState.current_node_id`；`RunSession.enter_node(id) -> Result` 做成命令式规则入口（仿 `BattleSession.submit`）。**动 RunState 前按分工文档 §4 契约流程双方确认。**
- **内容绑定**：`content_id` 待 `EncounterBuilder` + `ContentDB` 填充（本轮留空）。
- **RNG 接线**：`MapGenerator.generate(def, RngStreams.route_rng())`（本轮测试传普通 `RandomNumberGenerator`）。

## 6. 给队友的交接点

1. Phase 0 的 `tests/run_all.gd` 落地后，请让它发现并调用 `tests/rules/*`；本轮的 `MapGeneratorTest.run_all()` 已是该形状，可直接纳入。
2. `RunState` 形状变更（新增 `map`/`current_node_id`）属共享契约，改动前需双方同意。
