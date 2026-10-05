# Track B2：Run & Route 落地说明 + 共享契约

日期：2026-10-05。分支：`xxy`。范围：**规则层 + 存档 + 场景编排（第一轮 B DoD）**。
配套合同：`docs/route_map_rules.md`（地图生成）、`docs/combat_rules.md`（战斗）、`docs/architecture_review.md`（H2/H4）。

> 记号：🔗 = 与 A 线共享契约，改动须双方同意并同步本文。

## 0. 一句话

把已完成的 RouteGraph/MapGenerator 接进新的 **RunState / RunSession**，实现
`建 Run -> 生成地图 -> 点节点 -> EncounterBuilder 组战斗 -> BattleScreen -> BattleResult -> 写回 RunState -> 回地图`
的完整闭环，全部可无头测试。

## 1. 交付文件

| 文件 | 类 | 职责 |
|---|---|---|
| `gameplay/run/run_state.gd` | `RunState` | 局内权威状态：HP/金币/永久卡组/遗物/地图/当前节点/单调计数器/RNG 快照 |
| `gameplay/run/run_session.gd` | `RunSession` | 唯一节点入口 `enter_node()`；战斗进出；章节推进；自动存档 |
| `gameplay/run/encounter_def.gd` | `EncounterDef` (Resource) | 遭遇定义：敌人组成/棋盘/出生格/回合参数/tier |
| `gameplay/run/encounter_builder.gd` | `EncounterBuilder` | **纯函数** `build(encounter, run, rng, content) -> 装配 dict` |
| `app/run_flow.gd` | `RunFlow` | 路线 <-> 战斗 <-> 非战斗节点 场景编排 |
| `gameplay/run/rest_system.gd` | `RestSystem` | 休息：回血 / 升级一张卡 |
| `gameplay/run/shop_def.gd` / `shop_state.gd` / `shop_system.gd` | `ShopDef` / `ShopState` / `ShopSystem` | 商店：商品生成 / 买卡 / 删卡 / 回血 |
| `gameplay/run/event_def.gd` / `event_choice.gd` / `event_system.gd` | `EventDef` / `EventChoice` / `EventSystem` | 事件：选项与效果 |
| `presentation/screens/node_screen.gd` | `NodeChoiceScreen` | rest/shop/event 通用选择屏 |
| `presentation/screens/main_menu.gd` / `character_select.gd` | `MainMenuScreen` / `CharacterSelectScreen` | 主菜单 / 选角 |
| `gameplay/run/treasure_system.gd` | `TreasureSystem` | 宝箱：遗物 + 金币奖励 |
| `gameplay/run/reward_state.gd` / `reward_system.gd` | `RewardState` / `RewardSystem` | 战后三选一卡 + 胜利金币 |
| `content/characters/hero.tres` | `CharacterDef` | 初始卡组/遗物/职业标签 |
| `content/encounters/*.tres` | `EncounterDef` | 3 普通 + 1 精英 + 1 Boss |
| `content/shops/route_shop.tres` | `ShopDef` | 1 商店 |
| `content/events/*.tres` | `EventDef` | 2 事件 |
| `autoload/app.gd` | `App` | `create_run` / `load_run` / `end_run` 生命周期 |
| `autoload/save_service.gd` | `SaveService` | Run 原子写读（temp -> 校验 -> 备份 -> 替换） |
| `core/save/save_codec.gd` | `SaveCodec` | +RunState / RouteGraph / RunCard / Relic 编解码 |
| `core/save/save_migrator.gd` | `SaveMigrator` | schema 1 -> 2 |
| `tests/rules/test_run_state.gd` 等 | 测试 | 见 §5 |

### 存量文件的改动

- `gameplay/run/route_graph.gd`：+`duplicate_graph()`（RunState 快照）。
- `gameplay/effects/relics/relic_state.gd`：+`duplicate_state()`。
- `gameplay/units/character_def.gd`：+`is_valid()`（ContentDB 注册校验）。
- `content/content_catalog.gd` + `autoload/content_db.gd`：+`characters` / `encounters` 索引 🔗。
- `presentation/route_map/route_map.gd`：+`bind_run_session()` / `refresh_from_session()` / `node_entered` 信号。
- `presentation/battle/battle_input.gd`：+`battle_finished` 信号 🔗。
- `presentation/battle/battle_screen.gd`：+`battle_finished` 信号、`configure(data)`、`demo_autostart` 🔗。
- `app/main.gd` / `app/main.tscn`：启动改为 `RunFlow.start_run()`。
- `tests/rules/map_generator_test.gd` -> `test_map_generator.gd`（纳入 run_all 采集）；删除 `tools/run_map_tests.gd`。

## 2. 🔗 RunState 字段契约（与 A 对齐的核心）

```
run_id / seed / character_id
act_index / map: RouteGraph / current_node_id
hp / max_hp / gold                         # 持久 HP 是 run<->battle 唯一桥
deck: Array[RunCardState] / relics: Array[RelicState]
next_card_uid / next_relic_uid / next_battle_id   # 必须随存档持久化（§12.4）
rng_snapshot: Dictionary                    # 与 BattleState.rng_snapshot 同构
```

**A 的写入点**：`BattleResult.persistent_changes["player_hp"][1]`（玩家 unit ID = 1）由 RunSession 写回 `RunState.hp`。
**A 的读取点**：EncounterBuilder 用 `RunState.deck`（永久卡）建战斗牌堆，`RunCardState.run_uid -> BattleCardState.source_run_uid` 回指。

## 3. 🔗 战斗屏接缝（与 A 对齐）

```gdscript
# 输入：形状 == DemoBattleSetup.build() 的返回 dict
#   { rng, state, card_defs, enemy_behaviors, enemy_actions, card_labels }
battle_screen.configure(data: Dictionary)

# 输出：进入终态时发出
signal battle_finished(result: BattleResult)
```

约定：
- `demo_autostart=false` 时必须先设再 `add_child`，否则 `_ready` 会先开 demo。
- A 的旧路径（`BattleScreen` 作为主场景直接跑 demo）仍可用：直接实例化 `battle_screen.tscn`（`demo_autostart` 默认 true）。

## 4. 流程与幂等

```
App.create_run(seed)                     # RunSession.create_run + SaveService 绑定
  -> RunFlow.start_run -> RouteMapScreen.bind_run_session
  -> 点节点 -> RunSession.enter_node(id) # 克隆->校验->提交；失败零副作用
       kind == battle -> EncounterBuilder.build -> BattleScreen.configure
  -> battle_finished -> RunSession.on_battle_finished(result)
       非 Boss 胜 -> 奖励屏（三选一卡 + 金币）-> 回地图；Boss 胜 -> 奖励屏 -> act_index+1 换图
       玩家死 -> defeat；末章 -> run_complete
```

- `enter_node` 在工作快照上结算，成功才提交（`state` 被替换为新实例——调用方不可缓存旧引用）。
- 每次成功进入 / 战斗结束都 `_autosave()`（节点边界）。
- 战斗内续档 **v1 不做**（架构既定决策）。

## 5. 自动测试（30 total）

| 文件 | 覆盖 |
|---|---|
| `test_map_generator.gd` | 地图生成（原 9 组，规范化进 run_all） |
| `test_route_graph.gd` | 入口/解锁/可达/汇合/visited |
| `test_run_state.gd` | 计数器/卡组/遗物/深拷贝独立性（含地图） |
| `test_encounter_builder.gd` | 装配/持久 HP 带入/不改入参/确定性/非法输入 |
| `test_run_session.gd` | create_run/enter_node/锁定拒绝零副作用/幂等/确定性/HP 写回/Boss 进章 |
| `test_run_save_codec.gd` | RunState 往返/深拷贝独立性/版本门禁/磁盘往返 |
| `test_node_systems.gd` | Rest/Shop/Event：回血/升级上限/买卡扣金币/删卡下限/事件效果与钳制 |
| `test_reward_system.gd` | 三选一确定性/领卡/放弃/胜利金币 |

运行（Godot 4.7.2 mono，见记忆 `godot-toolchain`）：

```bash
"<godot_exe>" --headless --editor --quit-after 45 --path "D:/mobius"
"<godot_exe>" --headless --path "D:/mobius" -s res://tests/run_all.gd
```

## 6. 待办 / 已知缺口

1. **奖励池**：`RewardSystem` 目前用全部 `card_ids()` 当池（含基础卡）。正式版应建 `content/rewards/` 池并按节点类型/稀有度过滤。
2. **遗物战斗内生效**：RunState 只存 `RelicState`，A 的触发器接线后接。
3. **主菜单"继续"**：依赖 SaveService 的 Run 存档（已实现），写在节点边界；战斗内续档 v1 不做。
4. **内容量**：1 角色 / 5 遭遇 / 1 商店 / 2 事件 / 3 遗物 / 3 状态——扩充属内容轮。
5. **`content/maps/campaign_default.tres` 未进 ContentDB**：RunSession 用 `CampaignDef.new()` 默认值。
6. **卡牌升级 UI**：升级数据由 `CardDef.upgrade_overrides` 提供（休息节点已能用），A 的卡牌线做专门 UI。
7. **`RunState` 深拷贝已统一走 SaveCodec（H2 已闭环）**；`RunCardState.duplicate_state`（A 线遗留）未清理。
