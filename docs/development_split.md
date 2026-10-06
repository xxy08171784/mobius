> 历史设计记录（2026-10-05），保留原文供追溯；其中脚手架/占位/旧路径描述不代表当前工程。请以 [current_status.md](current_status.md)、[editor_and_api_guide.md](editor_and_api_guide.md) 为准。

# GAMEGAM 开发分工计划（双人并行）

日期：2026-10-05。目标：把可并行的实现工作拆成 **两条串行线**，两人各领一条，线内按序、线间并行，最后汇合到集成阶段。

依据：`godot_architecture.md` §5/§8（模块与阶段）、`combat_rules.md`（规则合同）、`architecture_review.md`（H1–H5 修订）、`directory_structure.md`（目录说明）。

## 0. 分工总览

```text
Phase 0  公共地基（由 A 先做，快，双方都依赖）        [串行, 单边]
   ↓
Track A  A1 效果模块 → A2 卡牌模块  ──────────────┐
Track B  B1 棋盘模块 → B2 单位模块 → B3 敌人模块  ├── 并行（两线互不阻塞）
   ↓                                            │
Phase 3  集成（BattleSession.submit 等）           ← 必须等两线都完成   [串行, 汇合]
   ↓
Phase 4  最小战斗屏 UI（不急，可任一/双方）         [并行, 可选]
```

- **线内串行**：每条线内部任务有依赖，按编号顺序做，不得跳。
- **线间并行**：两线只在"共享契约"上相交（见 §4），契约外互不等待。
- **Phase 3 必须串行**：把两线产出拧成一台机器，建议由更熟结算的人主做，另一人做集成测试复核。

## 1. Phase 0：公共地基（A 先做，串行，规模小）

**为什么先做**：两线都要用测试运行器、RNG、编解码；这些不做好，两线后面没法自测。

| # | 交付 | 内容 | 验收 |
|---|---|---|---|
| 0.1 | `tests/run_all.gd` 测试运行器 | `extends SceneTree` 的手写运行器（无插件，符合架构"不引框架"）；能逐个跑 `tests/rules/*.gd` 并汇总失败 | 一条最简用例通过 |
| 0.2 | 确定性回放测试壳 | 封装"seed + 命令序列 → 最终状态哈希 + 事件流哈希"的公共工具函数，供两线复用 | 空跑可运行 |
| 0.3 | `RngStreams` 实现 | `derive_streams`（splitmix64(run_seed, stream_id)）、`snapshot/restore`、`clone`、`battle_rng`（combat_rules §12） | 子流不互相污染；clone 不推进原流 |
| 0.4 | `SaveCodec` 实现 + 往返测试 | BattleState ↔ Dictionary（schema 带版本）；`clone = encode→decode`；Vector2i/64 位整数处理（评审 H2） | 往返等价；深改 clone 后原图不变 |

> A 做完 0.1–0.4 即提交并告知 B；B 在 0.1 落地前可以先读契约文档、起草 B1 的文件骨架，但不写依赖测试。

## 2. Track A：效果 / 卡牌线（A 做）

**依赖**：Phase 0。**线内顺序**：A1 → A2。

### A1 效果模块（`gameplay/effects/`）

| 文件 | 内容 |
|---|---|
| `effect_def.gd` | `@abstract` 基类：`type_key`、数值参数字典、目标策略引用 |
| `effect_context.gd` | 来源单位/来源卡/目标/触发根 ID/深度 |
| `effect_resolver.gd` | **纯函数** `resolve(state_in, plan, rng_in) -> { state_out, rng_out, events }`（评审 H1）；事件生成、错误路径、触发上限拒绝（combat_rules §7.4） |
| `handlers/` | `damage`（按 §6 伤害管线 8 步）、`block`、`draw`、`move`、`push`、`apply_status` |
| `trigger_system.gd` | 触发入队模型 + 排序键（阶段→优先级→稳定实例 ID）+ 上限（§7） |
| `statuses/` | `status_def.gd`、`status_state.gd`（层数/回合/来源；tick_timing） |
| `relics/` | `relic_def.gd`、`relic_state.gd`（计数器在 State，定义不存计数） |

**DoD**：`resolve` 纯函数单测——同输入同输出；预览不推进 RNG；Damage→Block→HP 管线顺序正确；非法输入不产出半状态；触发超限拒绝。

### A2 卡牌模块（`gameplay/cards/`）

| 文件 | 内容 |
|---|---|
| `card_def.gd` | 只读定义（ID、费用、标签、目标规则、效果列表、升级） |
| `run_card_state.gd` / `battle_card_state.gd` | 永久卡（UID/升级）vs 本场临时卡（费用修正） |
| `deck_state.gd` | 抽/手/弃/消耗/结算中五区；洗牌规则 |
| `card_system.gd` | 抽/洗/消耗规则服务 |
| `combo_planner.gd` | 组合合法性（费用、顺序、目标）+ 执行计划（combat_rules §4） |

**DoD**：两张同名卡 UID 不混；一卡只属一区；组合费用一次性扣、非法组合零副作用；位移后射程重算。

## 3. Track B：棋盘 / 单位 / 敌人线（B 做）

**依赖**：Phase 0。**线内顺序**：B1 → B2 → B3。

### B1 棋盘模块（`gameplay/board/`）

| 文件 | 内容 |
|---|---|
| `board_state.gd` | 地形 + cell→unit 占用（一格一单位）；位置权威 |
| `cell_state.gd` | 单格地形/标志（blocks_los、traversable、trap） |
| `board_query.gd` | `is_inside`、`get_unit_at`、`get_unit_cell`、`reachable_cells`、`get_target_cells`、`has_line_of_sight`（supercover，§10） |
| `pathfinder.gd` | 等成本 BFS（8×8 足够） |
| `target_spec.gd` | 单位/格子/方向三类目标（§6 契约） |
| 位移规则 | 移动/击退/交换/传送碰撞处理（§9 表），走同一入口、产 `UnitMoved/CellEntered/CellExited` 事件 |

**DoD**：可达性/占用/视线测试（含对角穿角规则、墙阻挡）；位移落点冲突按 §9 处理。

### B2 单位模块（`gameplay/units/`）

| 文件 | 内容 |
|---|---|
| `unit_def.gd` | 基础属性 + 外观引用 |
| `character_def.gd` | 初始卡组/初始遗物/职业标签 |
| `unit_state.gd` | 阵营、HP、护盾、资源、状态实例（**状态容器先用 `Dictionary[int, RefCounted]` 占位**，A1 落地后收紧类型） |
| `stat_system.gd` | 属性计算：基础→固定→百分比→上下限→取整（顺序写死并测试） |

**DoD**：StatSystem 计算顺序测试（取整/钳制位置固定）；UnitState 不存位置（从 BoardState 查）。

### B3 敌人模块（`gameplay/enemies/`）

| 文件 | 内容 |
|---|---|
| `enemy_def.gd` | 敌人定义 |
| `behavior_def.gd` | 行为规则表（蓄力/普通/接近，§5.6） |
| `enemy_planner.gd` | `plan() -> IntentState`：锁定格子优先、目标策略 |
| `intent_state.gd` | 行动 ID、目标策略、锁定目标/格子、影响范围 |

**DoD**：`plan()` 在合法状态下产出符合规则的 `IntentState`；被击退/堵路时有明确降级路径（数据，不实现执行）。

## 4. 共享契约（两线都不许单方改）

以下签名冻结在文档，改动必须双方同意并同步更新对应 md（否则 Phase 3 汇合时必然返工）。

| 契约 | 冻结于 | 谁产出 | 对方怎么用 |
|---|---|---|---|
| `resolve(state_in, plan, rng_in) -> {state_out, rng_out, events}` | combat_rules §5 | Track A | B 的敌人动作执行由它落点 |
| `EffectDef` 基础字段 + `@abstract` 基类 | architecture_review §1 | Track A | B 不直接依赖，只经 IntentState |
| `TargetSpec`（单位/格子/方向） | 架构文档 §5.2 | Track B | A 的卡牌 `targets` 字段引用它；**B 落地前 A 用 `Array` 占位** |
| `UnitState` 核心字段（阵营/HP/护盾/资源） | 架构文档 §5.4 | Track B | A 的 handler 按 unit ID 改数，不依赖 UnitState 类细节 |
| `IntentState` 字段（action_id/target/locked_cell） | combat_rules §5.6 | Track B | A 不依赖，Phase 3 接线 |
| `RngStreams` / `SaveCodec` API | Phase 0 | A | 两线测试共用 |
| 命令错误码枚举 | combat_rules §3 | 已有 | 两线测试复用 |

**跨线交汇点（谁等谁）**：

- A 的 `card_def` 效果列表等 B 的 `TargetSpec` 命名落地 → **B 优先做 `target_spec.gd`**（B1 第一步）。
- B 的 `UnitState` 状态容器等 A1 的 `StatusState` 命名 → **A 优先做 `statuses/`**（A1 靠前）。
- 双方各自提交时保持 `gameplay/` 不互相触碰，只动自己线内的目录。

## 5. Phase 3：集成（串行，汇合点）

两线 DoD 都完成后开始。**谁做**：建议 A 主做 submit，B 复核测试。

| # | 交付 | 内容 |
|---|---|---|
| 3.1 | `battle_session.submit` 全实现 | combat_rules §3 校验序（去重/阶段/锁/施法者/类型/费用/目标/组合）→ `resolve()` → 提交 state_out/rng_out → version++ → 命令锁 → 有界去重表 |
| 3.2 | `turn_system` 阶段迁移 | combat_rules §1 状态机；终态边界；同时死亡判 DEFEAT |
| 3.3 | `battle_factory.gd` | RunState → BattleState（临时修正不进 run_state） |
| 3.4 | 规则集成测试 | 确定性回放（seed+命令日志→状态/事件哈希）、不变量清单（一卡一区、UID 不混、拒绝零副作用）、读档不重复领奖 |
| 3.5 | **验收点 A** | 固定 8×8、1 玩家 1 敌人、移动/攻击/防御、结束回合；可胜可负；范围/占用/血量一致 |

## 6. Phase 4：最小战斗屏 UI（不急，可任一或双方）

在验收点 A 之后再做。`presentation/battle/`：棋盘视图（TileMapLayer）、手牌视图、意图预告、动画队列。预览走同一 `resolve()` 且不推进正式 RNG（combat_rules §12.2）。

## 7. 协作约定

- **分支**：Phase 0 完成后，A 在 `feat/track-a`、B 在 `feat/track-b`，各自从当前基底拉出；Phase 3 前合并回 `xxy`（或临时 `integrate` 分支）。
- **提交粒度**：每完成一个文件的 DoD 就提交一次，消息写清"模块+文件+验收点"。
- **契约变更流程**：任何人想改 §4 的签名 → 先写 issue/msg 给另一方 → 双方同意 → 更新对应 md → 再改代码。
- **不要并行做的事**：`core/`、`gameplay/battle/`（除 commands 已有）、契约文件、Phase 3。
- **每线独立**：线内 DoD 完成后即可停下，不必等另一线；集成前两线各自确保 `godot --headless` 扫描无 ERROR（命令见记忆/`docs`）。

## 8. 里程碑参考

| 里程碑 | 内容 | 两条线状态 |
|---|---|---|
| M0 | Phase 0 完成 | A 提交，B 拿到测试运行器与契约 |
| M1 | A1+B1 完成（效果+棋盘） | 两线可自测，无阻塞 |
| M2 | A2+B2 完成（卡牌+单位） | DoD 过半 |
| M3 | B3 完成、A 全部 DoD 达成 | 进入 Phase 3 |
| M4 | 集成 + 验收点 A | 战斗闭环可胜可负 |
| M5 | 最小战斗屏 UI | 可视原型 |
