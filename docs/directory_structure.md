# GAMEGAM 项目目录结构说明

日期：2026-10-05。对应 `D:\mobius`（Godot 4.7，类型化 GDScript）。
本文件解释**每个文件夹干什么、里面放什么**。完整架构见 `godot_architecture.md`；待办的精确规则见 `combat_rules.md`；待修缺口见 `architecture_review.md`。

> 记号：`✅ 已有` = 该文件已创建；`⬜ 占位` = 文件夹已建但为空（`.gitkeep`），等对应阶段再填。

## 0. 一句话总览

```
app/ 场景装配  │  autoload/ 全局单例  │  core/ 与玩法无关的基础
gameplay/ 规则层（不碰 UI）  │  presentation/ 表现层（只投影规则结果）
content/ 设计数据（Resource）  │  assets/ 美术音频  │  localization/ 文本
tools/ 调试  │  tests/ 测试  │  docs/ 文档
```

### 分层依赖（决定"东西该放哪"）

- `core/`、`gameplay/` = **规则层**：`RefCounted`，不访问 Node/Tween/SceneTree，无界面测试可跑。
- `presentation/` = **表现层**：Node/Node2D/Control，读规则层结果、收输入；**不能**直接改血量/费用/发奖励。
- `content/` = **静态定义**：Resource（`.tres`），启动加载后**只读**，运行时不改。
- 存引用走**稳定 ID**（如 `card.warrior.slash`），不存节点路径/中文名/引擎 uid。

## 1. 根目录

| 文件/夹 | 职责 | 内容 |
|---|---|---|
| `project.godot` | 引擎配置 | 主场景、autoload 注册、显示/渲染设置（✅ 已有） |
| `icon.svg` | 图标 | 项目图标（✅ 已有，可换） |
| `app/` | 启动与装配 | 见 §2 |
| `autoload/` | 全局单例 | 见 §3 |
| `core/` | 基础层 | 见 §4 |
| `gameplay/` | 玩法规则层 | 见 §5 |
| `presentation/` | 表现层 | 见 §6 |
| `content/` | 设计数据 | 见 §7 |
| `assets/` | 美术音频 | 见 §8 |
| `localization/` | 本地化 | 见 §9 |
| `tools/` | 调试工具 | 见 §10 |
| `tests/` | 测试 | 见 §11 |
| `docs/` | 文档 | 见 §12 |

## 2. `app/` — 启动与装配

**干什么**：程序入口、场景切换。只做装配，不放玩法逻辑。

| 应有文件 | 内容 | 状态 |
|---|---|---|
| `main.tscn` + `main.gd` | 稳定根场景；`_ready` 里做启动流程（加载内容 → 读设置/档案 → 进主菜单） | ✅ 已有（目前只调 `ContentDB.load_catalog`） |
| `scene_router.gd` | 菜单 / 路线 / 战斗的场景切换 | ✅ 已有（占位） |

## 3. `autoload/` — 全局单例

**干什么**：4 个进程级服务，注册在 `project.godot` 的 `[autoload]`。规则：
- **脚本里不写 `class_name`**（4.7 里同名会 Parse Error），用单例名直接引用，如 `ContentDB.get_card(...)`。
- `App` 只做生命周期，禁止变成 God Object。

| 应有文件 | 职责 | 状态 |
|---|---|---|
| `app.gd` | 当前 `Profile` / `Run` 生命周期（create_run / load_profile / end_run） | ✅ 已有（占位） |
| `content_db.gd` | 稳定 ID → 只读定义；从 `catalog.tres` 加载 | ✅ 已有（占位） |
| `save_service.gd` | 存档读写门面（原子写、备份）；`user://profile.json`、`user://runs/current.json` | ✅ 已有（占位） |
| `audio_service.gd` | 音量、BGM、音效 | ✅ 已有（占位） |

## 4. `core/` — 与玩法无关的基础

**干什么**：命令、事件、随机、存档这些"所有玩法共用"的机制。不依赖 `gameplay/`。

| 子目录 | 职责 | 应有内容 | 状态 |
|---|---|---|---|
| `core/commands/` | 命令基类与结果 | `game_command.gd`（`@abstract` 基类）、`command_result.gd`（错误码 + 事件批 + 版本） | ✅ 已有 |
| `core/events/` | 结算事件 | `game_event.gd`（`@abstract` 基类）、`event_batch.gd`（有序事件序列） | ✅ 已有 |
| `core/rng/` | 确定性随机 | `rng_streams.gd`（分流、seed/state 持久化、可克隆） | ✅ 已有（`battle_rng()` 未实现） |
| `core/save/` | 存档编解码 | `save_codec.gd`（状态↔字典唯一路径）、`save_migrator.gd`（版本升级/门禁） | ✅ 已有（占位） |

## 5. `gameplay/` — 玩法规则层

**干什么**：规则。用 `RefCounted` + 显式数据结构，**不引用场景节点**；深拷贝统一走 `SaveCodec`。这一层必须能脱离界面跑、能进无头测试。

### `gameplay/battle/` — 战斗流程（现阶段最核心）

| 应有文件 | 内容 | 状态 |
|---|---|---|
| `battle_state.gd` | 阶段、版本号、`next_uid`/`next_event_seq`、命令锁、去重表 | ✅ 已有 |
| `battle_session.gd` | **唯一命令入口** `submit()` | ✅ 已有（校验/结算未实现） |
| `battle_result.gd` | 战斗结果 → 交给 `RunSession` | ✅ 已有 |
| `turn_system.gd` | 阶段推进 | ✅ 已有（占位） |
| `battle_factory.gd` | `RunState` → `BattleState` | ⬜ 占位 |
| `battle_simulator.gd` | **按评审 H1 不单独建**，并入 `EffectResolver.resolve()` | — |
| `commands/` | 具体命令：`play_cards_command.gd`、`move_command.gd`、`end_turn_command.gd` | ✅ 已有 |

### `gameplay/board/` — 棋盘与空间

**干什么**：坐标 `Vector2i`，8×8 可配；地形、占用、可达性、射程、视线。**逻辑坐标与画面分开**，`TileMapLayer` 只在表现层用。

| 应有文件 | 内容 | 状态 |
|---|---|---|
| `board_state.gd` | 地形 + cell→unit 占用 | ⬜ 占位 |
| `cell_state.gd` | 单格地形/标志 | ⬜ 占位 |
| `board_query.gd` | 射程、视线、合法格子（`reachable_cells` / `get_target_cells` / `has_line_of_sight`） | ⬜ 占位 |
| `pathfinder.gd` | 可达/寻路（可包 `AStarGrid2D`） | ⬜ 占位 |
| `target_spec.gd` | 单位/格子/方向三类目标 | ⬜ 占位 |

### `gameplay/cards/` — 卡牌与组合

**干什么**：定义/永久卡/战斗卡三类分离；牌堆（抽/手/弃/消耗/结算中）；组合规划。同一定义两张卡 UID 不同；每张牌任意时刻只属一个牌区。

| 应有文件 | 内容 | 状态 |
|---|---|---|
| `card_def.gd` | 只读定义（ID、费用、目标规则、效果列表、升级） | ⬜ 占位 |
| `run_card_state.gd` | 局内永久卡（UID、升级、永久附魔） | ⬜ 占位 |
| `battle_card_state.gd` | 本场临时改动（费用修正、临时标签） | ⬜ 占位 |
| `deck_state.gd` | 牌区管理 | ⬜ 占位 |
| `card_system.gd` | 抽/洗/消耗规则 | ⬜ 占位 |
| `combo_planner.gd` | 组合合法性 + 执行计划 | ⬜ 占位 |

### `gameplay/units/` — 单位与角色

**干什么**：玩家与敌人共用一套状态。位置不在 UnitState，从 BoardState 查。

| 应有文件 | 内容 | 状态 |
|---|---|---|
| `unit_def.gd` | 基础属性 + 外观引用 | ⬜ 占位 |
| `character_def.gd` | 初始卡组/遗物/职业标签 | ⬜ 占位 |
| `unit_state.gd` | 阵营、HP、护盾、资源、状态实例 | ⬜ 占位 |
| `stat_system.gd` | 属性计算顺序（基础→固定→百分比→上下限→取整） | ⬜ 占位 |

### `gameplay/effects/` — 效果与触发（整个项目最值得提前设计）

**干什么**：基础效果 handler + 纯函数 `resolve()` + 触发队列。普通新卡只要新 `.tres`，新机制才加 handler。

| 应有文件 | 内容 | 状态 |
|---|---|---|
| `effect_def.gd` | 效果定义基类 | ⬜ 占位 |
| `effect_context.gd` | 来源/目标/触发根 ID/深度 | ⬜ 占位 |
| `effect_resolver.gd` | **纯函数** `resolve(state, plan, rng) -> {state_out, rng_out, events}` | ⬜ 占位（H1 落点） |
| `trigger_system.gd` | 触发排序（阶段→优先级→稳定 ID）+ 上限 | ⬜ 占位 |
| `handlers/` | `damage`、`block`、`draw`、`move`、`push`、`apply_status` 等基础操作 | ⬜ 占位 |
| `statuses/` | `status_def.gd`、`status_state.gd`（层数/回合/来源） | ⬜ 占位 |
| `relics/` | `relic_def.gd`、`relic_state.gd`（遗物属 RunState，进战斗提供钩子） | ⬜ 占位 |

### `gameplay/enemies/` — 敌人与意图

**干什么**：可预测行为优先——规则表/FSM，不必先上行为树。`plan()` 产出 `IntentState`，UI 预告与执行共用同一对象。

| 应有文件 | 内容 | 状态 |
|---|---|---|
| `enemy_def.gd` | 敌人定义 | ⬜ 占位 |
| `behavior_def.gd` | 行为规则表 | ⬜ 占位 |
| `enemy_planner.gd` | 意图规划 | ⬜ 占位 |
| `intent_state.gd` | 行动 ID、目标策略、锁定目标/格子、影响范围 | ⬜ 占位 |

### `gameplay/run/` — 单局冒险

**干什么**：一次完整游玩。`RunState` 是跨场景的局内状态权威；战斗进入/退出只经 `BattleFactory`/`BattleResult`。

| 应有文件 | 内容 | 状态 |
|---|---|---|
| `run_session.gd` / `run_state.gd` | 单局生命周期 / 局内状态权威 | ⬜ 占位 |
| `route_map_def.gd` | 地图生成配置（Resource，`RouteMapDef`） | ✅ 已有 |
| `map_generator.gd` | **纯函数** `generate(def, rng) -> RouteGraph`（StS 式 DAG，见 `route_map_rules.md`） | ✅ 已有 |
| `route_graph.gd` | 地图 DAG 数据 + 解锁/可达查询 | ✅ 已有 |
| `map_node_state.gd` | 节点状态（类型键/访问/邻居） | ✅ 已有 |
| `encounter_def.gd` / `encounter_builder.gd` | 遭遇配置 / 生成具体战斗 | ⬜ 占位 |
| `reward_system.gd` / `shop_system.gd` / `event_system.gd` / `rest_system.gd` | 奖励/商店/事件/休息规则 | ⬜ 占位 |

### `gameplay/meta/` — 局外成长

**干什么**：解锁、难度、图鉴、永久货币。**与当前局分开保存**，战斗中不随时读档案改属性。

| 应有文件 | 内容 | 状态 |
|---|---|---|
| `profile_state.gd` | 局外档案 | ⬜ 占位 |
| `unlock_def.gd` / `unlock_system.gd` | 解锁定义/系统 | ⬜ 占位 |

## 6. `presentation/` — 表现层

**干什么**：**展示规则的结果**——收集输入、按事件批播放动画/血条/音效、显示意图与目标预览。预览走同一 `resolve()` 但丢弃输出、不推进正式 RNG。播放期间由命令锁禁止下一条输入。

| 子目录 | 职责 | 应有内容 | 状态 |
|---|---|---|---|
| `presentation/battle/` | 战斗界面 | `battle_screen.tscn`、`battle_presenter.gd`、`battle_input.gd`、`board_view.tscn/.gd`、`unit_view.gd`、`iso_grid.gd`、`iso_board_theme.gd`、`animation_queue.gd`、`demo_battle_setup.gd`（`target_overlay`/`intent_overlay` 暂并入 board_view 高亮层） | ✅ 已有（棋盘已换等轴测地块） |
| `presentation/cards/` | 卡牌视图 | `card_view.tscn/.gd`、`hand_view.tscn/.gd`（悬停/选中/拖拽/排布） | ⬜ 占位 |
| `presentation/screens/` | 各界面 | 每屏 `.tscn` + 同名 `.gd`：`main_menu`、`character_select`、`route_map`、`reward_screen`、`shop_screen`、`event_screen`、`rest_screen`、`run_result` | ⬜ 占位 |
| `presentation/common/` | 通用组件 | `card_info.gd`（卡牌/遗物/状态展示文案与悬浮详情）、`deck_popup.gd`（卡组/牌堆查看弹层）（✅ 已有） |

## 7. `content/` — 设计数据（Resource）

**干什么**：设计师编辑的静态数据。用自定义 Resource（`CardDef`/`EnemyDef`/`StatusDef`/`RelicDef`/`EncounterDef`）。数值走 Inspector 编辑 `.tres`，新机制才写代码。

| 应有内容 | 用途 | 状态 |
|---|---|---|
| `catalog.tres` | **显式引用全部资源**：索引 + 导出保资源 + 校验 | ✅ 已有（空） |
| `cards/{neutral,warrior,mage}/` | 职业卡组目录（实际目录按已实现职业创建） | ⬜ 占位 |
| `characters/` | 角色定义 | ⬜ 占位 |
| `enemies/` | 敌人定义 | ⬜ 占位 |
| `statuses/` | 状态定义 | ⬜ 占位 |
| `relics/` | 遗物定义 | ⬜ 占位 |
| `encounters/` | 遭遇配置 | ⬜ 占位 |
| `board_templates/` | 手工战场模板 | ⬜ 占位 |
| `events/` | 事件内容 | ⬜ 占位 |
| `rewards/` | 奖励池 | ⬜ 占位 |
| `difficulty/` | 难度配置 | ⬜ 占位 |
| `maps/` | 选关地图生成配置（`route_map_default.tres`） | ✅ 已有 |

命名规范：每条内容配稳定 ID（如 `card.warrior.slash`），显示名走 `localization/` 文本键；effect 定义建议**独立 `.tres` 外链**，别内联进卡牌（避免共享子资源被改动）。

## 8. `assets/` — 美术与音频

**干什么**：原始素材，Godot 导入为资源。只放资源，不放脚本。

| 子目录 | 用途 | 状态 |
|---|---|---|
| `textures/units/` | 单位贴图 | ⬜ 占位 |
| `textures/cards/` | 卡牌贴图 | ⬜ 占位 |
| `textures/tiles/` | 瓦片（地形/装饰） | ⬜ 占位 |
| `textures/ui/` | 界面贴图 | ⬜ 占位 |
| `textures/vfx/` | 特效 | ⬜ 占位 |
| `audio/bgm/` | 背景音乐 | ⬜ 占位 |
| `audio/sfx/` | 音效 | ⬜ 占位 |
| `fonts/` | 字体 | ⬜ 占位 |
| `themes/` | Godot 主题 | ⬜ 占位 |

## 9. `localization/` — 本地化

**干什么**：文本键与翻译资源（Godot `Translation` / CSV）。显示文案不进存档，内容用稳定 ID，与文本键有约定映射。

| 应有内容 | 用途 | 状态 |
|---|---|---|
| 翻译资源（每语言一份） | 显示名/UI 文案 | ⬜ 占位 |

## 10. `tools/` — 调试与内容工具

**干什么**：编辑期/调试脚本，**不随游戏导出**（导出预设加 `exclude_filter`）。

| 应有内容 | 用途 | 状态 |
|---|---|---|
| `validate_content.gd` | 内容校验器（重复 ID、缺失引用、奖励池空等） | ⬜ 占位 |
| `battle_sandbox.tscn` | 指定卡组/敌人/种子的调试场景 | ⬜ 占位 |

## 11. `tests/` — 测试

**干什么**：规则层无界面测试 + 确定性回放。框架拍板后（GUT / gdUnit4）进 CI：`godot --headless -s`。

| 子目录 | 用途 | 状态 |
|---|---|---|
| `tests/rules/` | 规则单测（同一状态+随机+命令→同结果；不合法命令零副作用；同名卡 UID 不混） | ⬜ 占位 |
| `tests/integration/` | 跨模块/存档往返/读档不重复领奖 | ⬜ 占位 |
| `tests/fixtures/` | 测试用 `.tres`/存档快照 | ⬜ 占位 |

## 12. `docs/` — 文档

| 文件 | 内容 | 状态 |
|---|---|---|
| `godot_architecture.md` | 原始架构方案（只读，位于 Downloads） | — |
| `architecture_review.md` | 评审：风险/缺口/修订清单 | ✅ 已有 |
| `combat_rules.md` | 战斗规则精确合同（阶段/伤害管线/触发/位移/胜负） | ✅ 已有 |
| `route_map_rules.md` | 选关地图生成合同（DAG 拓扑/固定行/相邻约束/解锁） | ✅ 已有 |
| `directory_structure.md` | 本文件 | ✅ 已有 |

## 附：当前占位分布（`.gitkeep`）

以下文件夹已建、为空，等对应阶段实现：

`gameplay/board`、`gameplay/cards`、`gameplay/units`、`gameplay/effects/{handlers,statuses,relics}`、`gameplay/enemies`、`gameplay/run`、`gameplay/meta`、`presentation/{battle,cards,screens,common}`、`content/{cards/neutral,cards/warrior,cards/mage,characters,enemies,statuses,relics,encounters,board_templates,events,rewards,difficulty}`、`assets/*`、`localization/`、`tools/`、`tests/{rules,integration,fixtures}`。

**按架构文档 §8 的开发顺序填**：先 `gameplay/battle` + `gameplay/board` + `gameplay/cards` + `gameplay/units` + `gameplay/effects`（阶段 A/B 战斗闭环），再 `run`/`enemies`/`meta`（阶段 C/D），最后 `presentation` 与大量 `content`。
