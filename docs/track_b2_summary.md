# Track B2 工作总结（Run & Route + 非战斗节点 + 一局闭环）

日期：2026-10-05。分支：`xxy`。范围：**B 线一局玩法从规则层到可玩闭环**（含合并收尾、节点系统、奖励、入口/收尾界面）。
配套：`docs/track_b2_run_route.md`（共享契约与 API 细节）、`docs/route_map_rules.md`（地图合同）、`docs/combat_rules.md`（战斗合同）。

> 记号：✅ 完成并验证 ｜ ⚠️ 部分/有依据缺口 ｜ 🔗 与 A 线共享契约

## 0. 一句话

把「已有 RouteGraph/MapGenerator + 战斗闭环」接成**一局真正能从主菜单玩到通关的游戏**：
`选角 → 地图 → 战斗 → 奖励 → 商店/休息/事件/宝箱 → Boss → 结局`，全部可无头测试、确定性、失败零副作用。

## 1. 起点：合并收尾（已提交 `8dc2017`）

接手时仓库处于 `Merge branch 'cxm' into xxy` 半途，两个冲突文件：

| 文件 | 冲突 | 处理 |
|---|---|---|
| `gameplay/cards/combo_planner.gd` | `_deck_for_work_state` 注释措辞 | 并集，保留"纯函数不污染权威牌堆"语义 |
| `tests/fixtures/effect_test_state.gd` | `duplicate_state()` 注释措辞 | 保留更完整说明（对齐 H2/记忆 gotcha） |

合并完成后全量验证：**22 total, 22 passed**。合并提交 `8dc2017` 已提交；此后所有改动**未提交**。

## 2. Track B2 交付（第一轮：Run & Route）

| 步骤 | 交付 | 文件 |
|---|---|---|
| B2-0 | 地图测试规范化纳入 `run_all`；新增路线图测试；删冗余工具 | `tests/rules/test_map_generator.gd`（原 `map_generator_test.gd` 重命名）、`test_route_graph.gd`、删 `tools/run_map_tests.gd` |
| B2-1 | 局内权威状态 | `gameplay/run/run_state.gd` |
| B2-3 | 遭遇定义 + 纯函数装配器 | `encounter_def.gd`、`encounter_builder.gd`、`content/encounters/*.tres`（3 普通+1 精英+1 Boss） |
| B2-2 | 一局规则协调器（克隆→提交） | `run_session.gd` |
| B2-6 | Run 存档 + 版本升级 | `core/save/save_codec.gd`（+RunState/RouteGraph 编解码）、`save_migrator.gd`（schema 1→2）、`autoload/save_service.gd`（原子写） |
| B2-4 | 地图屏由 RunState 驱动 | `presentation/route_map/route_map.gd`（`bind_run_session` / `node_entered`） |
| B2-5 | 生命周期 + 场景编排 + 战斗屏接缝 | `autoload/app.gd`、`app/run_flow.gd`、`presentation/battle/battle_screen.gd`/`battle_input.gd`（`battle_finished` / `configure`）、`app/main.tscn` |

## 3. 第二轮交付（非战斗节点 + 入口/收尾 + 奖励）

| 系统 | 文件 | 能力 |
|---|---|---|
| 休息 | `rest_system.gd` | 回血（30% max_hp）/ 升级一张卡（等级上限 1） |
| 商店 | `shop_def/state/system.gd` + `content/shops/route_shop.tres` | 确定性商品、买卡/删卡/回血，校验先行 |
| 事件 | `event_def/choice/system.gd` + `content/events/*.tres`（2 个） | 多选项，HP/金币/加卡，钳制上限 |
| 宝箱 | `treasure_system.gd` | 随机遗物 + 40 金币（encounter 流确定性） |
| 奖励 | `reward_state.gd` + `reward_system.gd` | 战后三选一卡 + 胜利金币 15 |
| 通用选择屏 | `presentation/screens/node_screen.gd` | rest/shop/event/treasure/reward 共用 |
| 入口/收尾 | `presentation/screens/main_menu.gd`、`character_select.gd` | 主菜单（新游戏/继续/退出）、选角 |
| 编排 | `app/run_flow.gd` | 全场景流转 + 顶部 HUD（章/HP/金币/卡组数） |
| 角色 | `content/characters/hero.tres` | `CharacterDef`（初始 10 卡 + 1 遗物） |

## 4. 与 A 线的共享契约（🔗 改动需双方知情）

1. **ContentDB 线（A 地盘）**：`content/content_catalog.gd`、`autoload/content_db.gd` 加了 `characters/encounters/shops/events` 索引——纯加法。
2. **战斗屏接缝（A 地盘）**：`battle_screen.gd` 加 `battle_finished` 信号、`configure(data)`、`@export demo_autostart`；`battle_input.gd` 加 `battle_finished`。**A 的 demo 自启路径保留**（默认 `demo_autostart=true`）。
3. **持久 HP 桥**：`BattleResult.persistent_changes["player_hp"][1]` 写回 `RunState.hp`（玩家 unit ID 固定 1）。
4. **深拷贝（H2）**：`RunState.duplicate_state()` = `SaveCodec` 往返；已移除我本轮加的 `RouteGraph.duplicate_graph` / `RelicState.duplicate_state` 死代码（`RunCardState.duplicate_state` 属 A 线遗留未动）。

## 5. 自动测试与验证

| 里程碑 | 测试数 |
|---|---|
| 接手（合并后） | 22 |
| B2-0 地图规范化 + route graph | 24 |
| B2-1 RunState | 25 |
| B2-3 EncounterBuilder | 26 |
| B2-2 RunSession | 27 |
| B2-6 Run 存档 | 28 |
| 第二轮 节点系统 | 29 |
| 奖励系统 | **30** |

新增测试：`test_map_generator`、`test_route_graph`、`test_run_state`、`test_encounter_builder`、`test_run_session`、`test_run_save_codec`、`test_node_systems`、`test_reward_system`。

验证命令（Godot 4.7.2 mono，见记忆 `godot-toolchain`）：

```bash
"<godot_exe>" --headless --editor --quit-after 55 --path "D:/mobius"
"<godot_exe>" --headless --path "D:/mobius" -s res://tests/run_all.gd   # 30/30 PASS
"<godot_exe>" --headless --quit-after 15 --path "D:/mobius"             # 启动无错误
```

## 6. 最终可玩循环

```
主菜单 → 选角（游侠） → 第 1 章地图（StS DAG）
  ├─ monster/elite/boss → 战斗（BattleScreen）
  │    胜 → 奖励屏（三选一卡 + 金币）→ 回地图
  │    Boss 胜 → 奖励屏 → 进第 2/3 章；末章 → 通关结算屏
  │    败 → 结算屏 → 返回主菜单
  ├─ rest   → 回血 / 升级卡
  ├─ shop   → 买卡 / 删卡 / 回血
  ├─ treasure → 遗物 + 金币
  └─ event  → 多选项事件
主菜单「继续」→ 读节点边界存档续玩
```

## 7. 与分工文档对照（诚实核对）

**Track B2 13 项**：12 项 ✅；1 项 ⚠️（`RngStreams.route_rng()` 未建同名方法，功能用 `get_stream(&"route")` 达成）。
**第一轮 B DoD 7 项**：全部 ✅。
**第二轮 B 6 项**：5 项 ✅；**「Route Map 表现完善」❌ 未做**（只加了 HUD）。
**汇合循环** `选角→地图→战斗→奖励→商店/事件/休息→Boss→结局`：已全部打通。
**多做了 A 的一项**：RewardSystem + 三选一卡 UI（文档归 A，卡在同一个 `battle_finished` 接缝，顺手实现）。

## 8. 未做 / 待办

- **Route Map 表现完善**（B 唯一缺项）：Boss 特殊样式、节点动效、回地图聚焦。
- **奖励池内容化**：`RewardSystem` 现在用全部 `card_ids()` 当池；正式应建 `content/rewards/` + 稀有度。
- **A 线剩余**：卡牌升级 UI、遗物战斗内触发/奖励、Boss 战斗完善、战斗表现完善。
- **主菜单「继续」**：已实现，依赖节点边界存档；战斗内续档 v1 不做。
- **内容扩充**：1 角色 / 5 遭遇 / 1 商店 / 2 事件 / 3 遗物 / 3 状态。
- **Profile / 局外成长 / 难度 / 美术音频 / 本地化**：按计划最后做。

## 9. 文件清单

- **新增 30**（规则 13 + 内容 9 + UI 5 + 测试 8，含 `.uid`）
  `gameplay/run/`: run_state, run_session, encounter_def, encounter_builder, rest_system, shop_def, shop_state, shop_system, event_def, event_choice, event_system, treasure_system, reward_state, reward_system（14 个 `.gd`）
  `content/`: characters/hero, encounters/*5, shops/route_shop, events/*2
  `presentation/screens/`: node_screen, main_menu, character_select
  `app/`: run_flow
  `tests/rules/`: test_route_graph, test_run_state, test_encounter_builder, test_run_session, test_run_save_codec, test_node_systems, test_reward_system
  `docs/track_b2_run_route.md`
- **修改 14**：`app/main.*`、`autoload/app.gd`、`autoload/content_db.gd`、`autoload/save_service.gd`、`content/catalog.tres`、`content/content_catalog.gd`、`core/save/save_codec.gd`、`core/save/save_migrator.gd`、`docs/route_map_rules.md`、`gameplay/units/character_def.gd`、`presentation/battle/battle_input.gd`、`presentation/battle/battle_screen.gd`、`presentation/route_map/route_map.gd`
- **重命名 2**：`tests/rules/map_generator_test.gd(.uid)` → `test_map_generator.gd(.uid)`
- **删除 1**：`tools/run_map_tests.gd`

**提交状态**：合并提交 `8dc2017` 已提交；其余全部未提交（建议拆 `Track B2 规则层` / `Track B2 节点系统与奖励` 两个 commit）。
