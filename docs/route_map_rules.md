# 选关地图规则合同（route_map_rules.md）

日期：2026-10-05。状态：**v2 已实现**（规则层）。实现见 `gameplay/run/`，测试见 `tests/rules/test_map_generator.gd`（由 `tests/run_all.gd` 采集）。
本文是**精确合同**：拓扑、生成、类型分配、解锁规则以此为准；实现改动需同步更新本文件。

术语：**入口** = 第 0 行可选节点；**层/行（row）** = 纵向进度，0 为底、越大越接近 boss；**列（col）** = 横向。

## 1. 拓扑

- **StS 式有向无环图（DAG）**：多条路径自入口上行，相邻层路径不交叉，但可**汇合**到同一节点（同一格只存在一个节点）。
- 边方向恒为**低行 → 高行**（向 boss）。边只存在于相邻两行之间。
- 节点身份 = 格 `(col, row)`；同格复访即合并，不新建。
- **不出现空行**：每行 0 .. `rows-1` 至少一个节点（6 条完整路径覆盖）。
- 固定行默认：row 0 全 monster、row 8 全 treasure、row `rows-1` 全 rest、row `rows` 单 boss。数值见 `RouteMapDef`。

## 2. 节点类型（稳定键）

```
node.monster  node.elite  node.rest  node.shop  node.treasure  node.event  node.boss
```

- 键同时是**内容查找前缀**与**表现层美术槽位索引**（下一轮 `RouteMapSkin.nodes[type_key]`）。
- 表现状态（available/locked/visited/current）**不存图**，是派生值：
  - `visited`：唯一持久化到图的标志。
  - `current`：`RunState.current_node_id`（不在图内）。
  - `available = can_enter(id)`，`locked = not available and not visited`。
- 节点 ID：由生成顺序单调分配，给定 `(def, rng)` 确定。

## 3. 生成算法（`MapGenerator.generate(def, rng) -> RouteGraph`）

**纯函数**：不改入参、不用全局随机。确定性 = `(def, rng 初始状态)`。

1. **入口列**：把 `[0, cols-1]` 做 Fisher-Yates 洗牌（用传入 rng），取前 `path_count` 个 → 入口互不相同、覆盖全宽。
2. **路径游走**：每条路径从入口逐行上行到 `rows-1`。每步在**合法候选中均匀抽签**决定列：
   - 候选 = `{col-1, col, col+1} ∩ [0, cols-1]`，剔除会与既有同层边交叉的（见下）。
   - **无交叉不变量**：新边 `(a→b)` 与既有同层边 `(c→d)` 若 `(a<c 且 b>d)` 或 `(a>c 且 b<d)` 则交叉 → 该候选列被剔除。
   - **连续竖直限制**：上一步已走竖直边 `(col→col)` 时，若仍有斜向候选则去掉竖直候选，避免叠成长廊。
   - 目标格已存在 → 合并（加边，不新建节点）。
   - 竖直边 `(a→a)` 对任意同层边恒不交叉，故**候选永不为空、路径永不中断**，每个入口都可达 boss（无陷阱入口）。
3. **boss**：单节点 `row = rows`，从 `rows-1` 全部节点连入，类型固定 `node.boss`。
4. **类型分配**：自上而下（`rows` → 0）。
   - 固定行（`fixed_floors`）强制类型，不参与抽签、不被降级；但**其特殊类型仍参与相邻约束**（例如顶层 rest 会阻止 row `rows-1` 再出 rest）。
   - 其余行按 `weights` 加权抽签，过滤：权重 ≤ 0、低于 `min_floors`、以及相邻约束下的特殊类型。
   - **相邻约束**：若节点的任一子节点（高一行直连）已是特殊类型（`special_types`：rest/shop/elite），本节点不得为特殊 → 降级（走 `weights` 中剩余类型，兜底 `fallback_chain`）。
   - 抽签遍历 `weights` 用**插入序**（Godot Dictionary 保序），保证确定性。

## 4. 解锁 / 可达（`RouteGraph`）

- `can_enter(id, current_id)`：未访问，且从 `current_id` 可进（StS 式**只能沿当前路径上行**，不能回退、不能跳到同层兄弟）：
  - `current_id < 0`（尚未进入任何节点，如章首）→ 仅入口可选；
  - 否则 → 仅 `current_id` 的**直接 `next_ids`** 可选。
- `enter(id, current_id)`：通过 `can_enter` 则标记 `visited` 并返回 true；否则零副作用。
- 位置不在图内存储（防双份状态）：由 `RunState.current_node_id` 传入（§2）。
- `has_path(a, b)`：沿 `next_ids` 搜索（边只向高行，天然无环）。
- 初始状态：仅入口可选；进入任一节点后，同层兄弟、其余入口与所有低行节点一律锁定。

## 5. 配置（`RouteMapDef`，Resource）

| 字段 | 默认 | 说明 |
|---|---|---|
| `rows` / `cols` | 15 / 7 | 楼层数 / 横向宽度 |
| `path_count` | 6 | 路径条数 = 入口数，须 ≤ `cols` |
| `fixed_floors` | `{0:monster, 8:treasure, 14:rest}` | 行 → 强制类型 |
| `min_floors` | `{rest:6, shop:6, elite:1}` | 类型最早出现的行 |
| `weights` | `{monster:53, event:22, elite:8, rest:12, shop:5}` | 抽签权重（无需归一化） |
| `special_types` | `[rest, shop, elite]` | 受相邻约束的类型 |
| `fallback_chain` | `[event, monster]` | 抽签池空的兜底 |

默认实例：`content/maps/route_map_default.tres`（改脚本默认值或在此覆盖）。

## 6. 已知取舍（v2）

- 每步在合法候选中均匀选列并**限制连续竖直**：竖直边占比由 ~45% 降到 ~31%，最长竖直走廊由 14 降到 ~7，更接近 StS 的蜿蜒观感（实测见 `docs/route_map_summary.md` §4）。
- 独立游走偶尔产生**宽 2 甚至宽 1 的行**（1000 seed 实测宽 1 约 0.3%），与 StS 原版行为一致；不强制消除。
- 内容绑定（`content_id`）本轮留空，待 `EncounterBuilder` + `ContentDB` 填充。
- boss 固定单节点、`col=0`；多 boss / boss 变体留待难度系统。

## 7. 接线点（后续，不在 v1）

- `RunState.map: RouteGraph` + `RunState.current_node_id`（需按分工文档 §4 契约流程同步）。
- RNG：`MapGenerator.generate(def, RngStreams.route_rng())`；本轮测试传普通 `RandomNumberGenerator`。
- 表现层 `presentation/screens/route_map/`：`RouteMapSkin`（背景/路径线/节点图标/按钮四态；显式槽位 > PNG 命名约定 > 占位色块）。
