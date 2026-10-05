# Track B 工作总结（棋盘 / 单位 / 敌人）

日期：2026-10-05。分支：`xxy`（B3 收尾时本地工作区）。范围：**规则层 B1+B2+B3 全部落地 + 无头测试**（UI / 集成 / 执行未做）。
配套合同：`docs/development_split.md`（分工与 §4 冻结契约）、`docs/combat_rules.md`（§9 位移 / §10 视线 / §6 伤害管线）、`docs/architecture_review.md`（H2/§1）。

> 记号：✅ 已交付并可测；⚠️ 有依据缺口需签字；🔗 属 §4 共享契约，改动须双方同意。

## 0. 一句话

在 A 线（效果/卡牌）并行开发期间，独立完成 **棋盘的形状与空间、单位的运行时状态与属性、敌人的意图规划**，全部脱离 `SceneTree`、可无头测试、纯函数、确定性。不碰 `core/`、不碰 `gameplay/battle/`、不碰 A 线文件。

## 1. 交付文件

### B1 棋盘 `gameplay/board/`（7 个）

| 文件 | 类 | 职责 |
|---|---|---|
| `target_spec.gd` | `@abstract TargetSpec` | 单位/格子/方向三类目标（🔗 §4 冻结契约；A 的卡牌 `targets` 引用） |
| `cell_state.gd` | `CellState` | 单格地形/标志：`blocks_los` / `traversable` / `trap`（三者正交） |
| `board_state.gd` | `BoardState` | 尺寸 + 地形 + `cell↔unit` 占用（**位置权威**，一格一单位），单一入口原语 |
| `pathfinder.gd` | `Pathfinder` | 等成本 BFS：`reachable_cells` / `find_path` |
| `board_query.gd` | `BoardQuery` | 空间查询门面：`has_line_of_sight`（supercover）/ `get_target_cells`（射程+LoS） |
| `displacement.gd` | `Displacement` | 移动/击退/交换/传送（§9 落点冲突） |
| `displacement_result.gd` | `DisplacementResult` | 位移结果（携带事件所需数据） |

### B2 单位 `gameplay/units/`（4 个）

| 文件 | 类 | 职责 |
|---|---|---|
| `unit_def.gd` | `UnitDef` (Resource) | 只读定义：基础属性字典 + 外观键 |
| `character_def.gd` | `CharacterDef` (Resource) | 角色：初始卡组/遗物/职业标签（稳定 ID 引用） |
| `unit_state.gd` | `UnitState` | 运行时状态：阵营/HP/护盾/资源/状态容器（🔗 核心字段 §4 冻结；**不存位置**） |
| `stat_system.gd` | `StatSystem` | 属性计算纯函数，顺序写死并测试 |

### B3 敌人 `gameplay/enemies/`（6 个）

| 文件 | 类 | 职责 |
|---|---|---|
| `enemy_action_def.gd` | `EnemyActionDef` (Resource) | 行为表一行：kind + 目标策略 + 射程/数值 |
| `behavior_def.gd` | `@abstract BehaviorDef` (Resource) | 行为基类（`fallback_action_id` 降级数据） |
| `sequence_behavior_def.gd` | `SequenceBehaviorDef` | 循环序列行为（MVP 默认） |
| `intent_state.gd` | `IntentState` | 已锁定意图：action_id / target / locked_cell / 影响范围（🔗 §4 字段） |
| `enemy_def.gd` | `EnemyDef` (Resource) | 敌人定义：unit_def + behavior + 外观 |
| `enemy_planner.gd` | `EnemyPlanner` | `plan() -> IntentState` 纯函数 |

### 测试 `tests/rules/`（6 个）

`test_board_state.gd`、`test_board_query.gd`、`test_displacement.gd`、`test_stat_system.gd`、`test_unit_state.gd`、`test_enemy_planner.gd`。

> 约定：文件名 `test_*.gd`、`extends "res://tests/test_case.gd"`、`run() -> Array[String]`。与 A 线 `tests/run_all.gd` 的发现规则一致，**自动被采集**，未改 A 线任何文件。

## 2. 核心设计

### 2.1 位置权威（§9 硬约束）

`UnitState` **不存坐标**，位置只在 `BoardState`。`BoardState` 用双索引 `_unit_at`（cell→unit）与 `_cell_of_unit`（unit→cell），**全部变更经 `place/remove/move/swap/teleport` 单一入口**，两索引恒一致。失败一律零副作用。

### 2.2 墙 / 视线 / 陷阱三分（§10）

`CellState` 三个正交标志：`traversable=false` 挡移动**不**挡视线；`blocks_los=true` 反之；`trap` 可进入但触发。测试专门验证"墙挡移动不挡视线"。

### 2.3 supercover 视线（§10，本轮硬骨头）

- 标准 supercover 算法：恰过格角时两轴各进一步，**两侧相邻格都入覆盖** → 无穿角窥视。
- **对称化**：`has_line_of_sight(a,b)` 取**两方向 supercover 的并集**（正反覆盖的贴角格不同，并集才完整且保证 `los(a,b)==los(b,a)`）。全量格对扫描验证对称。
- 起点/终点格本身不阻挡。

### 2.4 位移落点冲突（§9）

| 位移 | 规则 |
|---|---|
| 移动 | 可达 + 路径 ≤ 行动预算；不可达 → 拒绝 |
| 击退 | 逐格推进，遇**墙/单位/盘边**停在其前；**不移出盘外**（停边缘）；不造成碰撞伤害 |
| 交换 | 两格各有单位，不要求路径/射程，原子交换 |
| 传送 | **盘内 + 空格**即生效，忽略路径/视线/地形可走性（§9 字面） |

非法方向/超预算/不可达一律零副作用。

### 2.5 StatSystem 计算顺序（评审"中优先"）

写死：**基础 → 固定加成 → 百分比加成 → 上下限钳制 → 向下取整**。测试用可判别值锁定：
- 固定先于百分比：`(10+10)×1.5=30`（若反 = 25）。
- 向下取整：`5×1.5 → 7`（非 round 的 8）。
- 钳制在取整前；`±INF` 表示不钳。

### 2.6 敌人意图（§3 B3）

- **锁定格子优先**：`APPROACH` 在可达格中取离目标最近者作为落点。
- **目标策略**：`PLAYER` 取最近玩家（Manhattan，平手取较小 `unit_id`，确定性）；`SELF` 锁自身；`NONE` 无目标。
- **降级是数据**：目标缺失/无法接近 → 改用 `fallback_action_id` 并标记 `is_fallback`；无 fallback → 空意图。执行前失效不重算（combat_rules §2）。
- `plan()` 纯函数，**只规划不执行**（执行是 A 的 `resolve()`，Phase 3 接线）。

## 3. 验证结果

| 项 | 结果 |
|---|---|
| 全量测试 `tests/run_all.gd` | **10 total, 10 passed, 0 failed**（含 A 线 4 套 + B 线 6 套） |
| 编辑器扫描 `--headless --editor` | 无 `SCRIPT ERROR` / `Parse Error` |
| B1 视线对称 | 8×8 含 5 障碍，4096 组格对全量扫描 `los(a,b)==los(b,a)` |
| 位移 §9 | 墙/单位/盘边停下、出界不移出、传送忽略地形——均有断言 |
| StatSystem 顺序 | 固定→百分比→钳制→取整，判别值锁定 |

运行命令（Godot 4.7.2 mono，见记忆 `godot-toolchain`）：

```bash
# 前置：全新 clone 必须先扫一次，否则 class_name 未注册、-s 会挂死进程
"<godot_exe>" --headless --editor --quit-after 40 --path "D:/mobius"
"<godot_exe>" --headless --path "D:/mobius" -s res://tests/run_all.gd
```

## 4. 待确认的共享契约（§4，改动须双方同意）

| 契约 | 文件 | 我方产出 | A 线怎么用 |
|---|---|---|---|
| `TargetSpec`（单位/格子/方向） | `target_spec.gd` | ✅ | 卡牌 `targets` 字段引用（可拆独立 `class_name`，待定） |
| `UnitState` 核心字段 | `unit_state.gd` | ✅ | handler 按 unit ID 改 `hp/block/resources/statuses` |
| `IntentState` 字段 | `intent_state.gd` | ✅ | A 不依赖，Phase 3 接线 |
| `RngStreams` / `SaveCodec` API | Phase 0（已就绪） | — | 两线测试共用 |

**待 A 线/架构确认的具体点**：
1. `TargetSpec` 是否保持"一文件三内层类"，`kind()` 用枚举而非 StringName 键。
2. `UnitState` 字段名（`team/hp/max_hp/block/resources/statuses`）。
3. `StatSystem` 的取整/钳制顺序（A 的伤害管线 §6 也会用到）。

## 5. 已知缺口（⚠️ 需处理，非遗漏）

1. **"§5.6" 依据缺失**：`development_split.md` 给 `behavior_def` / `IntentState` 标的依据是 combat_rules **§5.6**，但仓库里没有该节（§5 是效果管线）。原规则应在外部 `godot_architecture.md`（不在 repo）。B3 为**据现有文档 + 补充解读**的 MVP，需与架构文档/队友核对：`EnemyActionDef` 字段、4 种 kind、接近落点算法、降级语义、是否要独立 `enemy_action_def.gd`。
2. **位移/棋盘事件类未建**：§9 要求位移"产 `UnitMoved`/`CellEntered`/`CellExited` 事件"，但 `GameEvent` 目前只有 `@abstract` 基类，**一个具体子类都没有**；A 线结算也会产事件（Damage/Block/Draw…），词汇表属共享。**故未擅自建**——改由 `DisplacementResult` 携带 `from/to/path/unit_id`，待约定后集成层一行适配。
3. **`SaveCodec` 扩展未做**：`BoardState`/`UnitState` 进 `BattleState` 后，`core/save/save_codec.gd` 需加 `_encode/_decode_*`，否则 clone/存档静默丢棋盘与单位。属 `core/`（§7 冻结），Phase 3 统一做。
4. **`StatusState` 命名未定**：`UnitState.statuses` 先用 `Dictionary[int, RefCounted]` 占位，等 A1 落地后收紧值类型（测试已锁定当前为 `RefCounted`）。
5. **蓄力跨回合推进**：`SequenceBehaviorDef.action_def_for(step)` 只管"第几步是哪个行动"，蓄力计时留给 Phase 3 回合系统。

## 6. 后续接线点（Phase 3，不在本轮）

- `BattleFactory`：`RunState` → `BattleState`，把 `BoardState` + `UnitState` 装进战斗状态。
- `SaveCodec`：补 `BoardState` / `UnitState` / `IntentState` 编解码。
- 敌人执行：`EnemyPlanner.plan()` 的 `IntentState` 交给 A 的 `resolve()` 执行（意图预告与执行共用同一对象）。
- 事件层：`DisplacementResult` → `UnitMoved`/`CellEntered`/`CellExited` 适配。
- 表现层 `presentation/battle/`：棋盘视图（`TileMapLayer`）、意图预告（`intent_overlay`）。

## 7. 提交状态

- 已推送：`target_spec.gd`（commit `0952a64 "b1"`，同批含地图美术文档与 `project.godot` C# feature）。
- **未提交**：`gameplay/board/` 6 个 + `gameplay/units/` 4 个 + `gameplay/enemies/` 6 个 + `tests/rules/` 6 个（及各自 `.uid`）。
