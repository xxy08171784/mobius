# Mobius：接口、可视化编辑入口与内容制作指南

更新：2026-10-06。本文中的 `res://` 指 `D:\GameProjects\GAMEGAM\mobius`。这里的“对外接口”指项目模块和内容扩展接口；当前没有 HTTP 服务、联机 API 或外部账号系统。

## 1. 可视化编辑总入口

打开 `project.godot`。启用 `addons/mobius_workbench/plugin.cfg` 后，编辑器右侧出现 **Mobius 工作台**：

- 分类筛选卡牌、敌人、单位属性、状态、角色、遗物、遭遇、怪物池、事件、商店。
- 搜索稳定 ID 或文件名，双击资源在 **Inspector** 中修改，Ctrl+S 保存。
- “内容目录”打开 `content/catalog.tres`，新内容需加入对应数组。
- 场景下拉框打开下面列出的界面；“音频”和“章节地图”打开对应配置。
- “校验内容引用”检查已登记内容；运行完整检查还会发现脚本与场景导入错误。

工作台是已有 Godot Resource/场景的编辑入口，不是独立的玩法脚本生成器。新增机制仍需编写对应规则并测试。

## 2. 各界面编辑位置

| 界面/用途 | 场景 | 编辑建议 |
|---|---|---|
| 正式游戏启动 | `app/main.tscn` | F5；启动校验后创建 RunFlow |
| 主菜单 | `presentation/screens/main_menu.tscn` | `%Title`、`%NewGame` 等唯一命名节点由脚本绑定，不要直接改名 |
| 角色、种子、难度选择 | `presentation/screens/character_select.tscn` | 角色数据来自 Catalog，解锁状态来自 Profile |
| 休息、商店、事件、宝箱、奖励、结算、历史、图鉴、帮助 | `presentation/screens/node_screen.tscn` | 共用 `%Title/%Body/%Options/%Status/%Leave`；列表由数据生成 |
| 设置 | `presentation/screens/settings_screen.tscn` | 音量、全屏、字号、减少动画、语言、改键 |
| 路线地图 | `presentation/route_map/route_map.tscn` | `Scroll/Center/Canvas`；布局参数在根脚本 Inspector |
| 单个路线节点 | `presentation/route_map/map_node_view.tscn` | 状态外观与点击区域；F6 地图可独立预览 |
| 战斗与部署 | `presentation/battle/battle_screen.tscn` | `BoardZone`、`DeploymentUI`、HUD；F6 为独立战斗演示 |
| 棋盘 | `presentation/battle/board_view.tscn` | 视觉配置见 `IsoBoardTheme`，不在这里改规则坐标 |
| 玩家/敌人信息 | `presentation/battle/battle_hud.tscn` | 玩家、当前选中敌人、存活敌人数、资源提示 |
| 战斗底部按钮与卡组区 | `presentation/battle/battle_card_hud.tscn` | 保留唯一节点名与既有信号 |
| 单张动态卡面 | `presentation/cards/battle_card_view.tscn` | 卡框、图标、费用、名称、文字；规则不在卡面脚本里 |
| 手牌排列 | `presentation/cards/hand_view.tscn` | 手牌布局与选择反馈 |
| 遗物/卡组/暂停顶栏 | `presentation/common/run_toolbar.tscn` | RunFlow 根据遗物列表动态填充按钮 |
| 等距棋盘/地块预览 | `presentation/battle/iso_preview.tscn`、`tile_preview.tscn` | 美术测试入口，不是正式游戏入口 |

暂停菜单复用 `node_screen.tscn`。卡组弹窗和特殊选牌弹窗分别由 `presentation/common/deck_popup.gd`、`card_choice_popup.gd` 创建；目前没有单独的 `.tscn`，其布局需要在脚本中调整。

正式运行由 `RunFlow` 先设 `BattleScreen.demo_autostart = false` 再加入场景树。F6 演示允许重试战斗；正式 Run 战败会结算并结束，不回到原战斗重开。

当前战斗美术保留 1920×1080 设计坐标，通过 `canvas_items + keep` 等比缩放。16:10 和超宽屏会留黑边。通用页面使用容器布局；字号设置影响继承主题的控件，旧战斗 HUD 的固定字号仍需单独编辑。

## 3. 内容资源入口

| 内容 | 文件/目录 | 核心字段与注意事项 |
|---|---|---|
| 总清单 | `content/catalog.tres` | 所有正式定义的根引用；各类 ID 不可重复 |
| 卡牌 | `content/cards/**/*.tres` | `CardDef.card_id/card_category/base_cost/tags/effects/upgrade_overrides`；显示名、icon_key 与规则分开 |
| 正式卡池 | `content/pools/formal_cards.tres` | `CardPoolDef`；奖励池和正式商店共享；可显式 ID、required/excluded_tags 筛选 |
| 初始角色 | `content/characters/*.tres` | `CharacterDef`；单位 ID、初始卡组/遗物、unlock_cost |
| 基础属性 | `content/units/**/*.tres` | `UnitDef`；角色与敌人的属性来源 |
| 敌人与行为 | `content/enemies/**/*.tres` | `EnemyDef` 引用单位和 `SequenceBehaviorDef`；行动顺序编辑嵌套 `EnemyActionDef` |
| 普通/精英池 | `content/pools/act*.tres` | 每幕 `monster_pool.actN` 和 `monster_pool.actN_elite`，enemy_ids 有放回抽取 |
| 固定遭遇/Boss | `content/encounters/*.tres` | 正式 Boss ID 必须是 `encounter.boss.actN`；含棋盘与召唤配置 |
| 三幕路线 | `content/maps/campaign_default.tres` | `CampaignDef.acts`；每幕 `RouteMapDef` 配置行列、固定楼层、权重等 |
| 事件 | `content/events/*.tres` | `EventDef` 标题/正文/choices；选项支持 hp_delta、gold_delta、add_card_id |
| 商店 | `content/shops/route_shop.tres` | 卡池、数量、卡价、删牌价、治疗价与治疗量 |
| 遗物 | `content/relics/*.tres` | `RelicDef` 的 trigger_key、trigger_params、priority |
| 状态 | `content/statuses/*.tres` | 定义图标/显示参数；新状态的实际算法在 StatusRules/StatusTickSystem |
| 音频 | `content/audio/default_audio.tres` | menu/route/battle 背景音乐，victory/defeat/click 音效；拖入 AudioStream |
| 本地化 | `localization/ui.csv` | CSV 第一列为键，zh_CN/en 列为翻译；保存后由 Godot 导入生成 translation |
| 地图美术 | `presentation/route_map/route_map_skin.gd` | RouteMapSkin 的各章背景、节点图标与连线样式 |
| 卡面美术 | `assets/textures/cards/frames`、`icons` | `CardVisuals` 根据卡类别和 icon_key 读取 |
| 棋盘地块 | `assets/textures/tiles/actN/normalized` | `IsoBoardTheme` 按幕加载；某幕缺图回退第一幕 |
| 棋盘障碍 | `content/obstacles/*.tres` + `assets/textures/obstacles/<appearance_key>.png` | `ObstacleDef`（阻挡移动，高物件 `blocks_los`）；按幕池 `content/pools/obstacle_pool.actN.tres`；`EncounterDef/MonsterPoolDef` 的 `obstacle_pool_id/obstacle_count` 控制每战随机摆放 |

表中的目录为查找范围，具体资源以 Catalog 的引用为准。事件当前使用全局候选池，尚未增加事件章节/角色条件树；需要这种规则时应扩展选择器，不要只在文件名加 act2 就期待自动过滤。

### 添加一张卡

1. 复制结构相近的 `CardDef`，更换 `card_id`、显示名、费用、标签和目标类型。不要复用旧卡 ID。
2. 常规伤害/护盾/抽牌/治疗/资源/位移/推拉/状态/净化用 `ConfiguredEffectDef` 组合；升级通过 `upgrade_overrides`。
3. 加入 Catalog.cards；想进入奖励池则启用 `reward_pool_enabled`。显式池模式需要把 `include_reward_enabled` 关掉，再填写 card_ids。
4. 填写 `icon_key` 并放对应 PNG；新增非标准机制按第 5 节注册规则。
5. 工作台校验 → 规则测试 → F6 演示出牌 → F5 正式奖励/商店测试。

旧 `tools/CardEditor/run_card_editor.bat` 仍可用于卡框、图标和合成预览图制作。它不创建规则、不写回 CardDef。正式手牌使用 Godot 动态卡面，不直接使用 generated 目录里的整卡 PNG。

### 添加敌人或新幕

先创建 UnitDef，再创建 EnemyDef 与行为序列，每个行动使用稳定 action.id。加入 Catalog.units/enemies，然后放入目标幕的普通/精英池，或固定遭遇。新幕还需在 Campaign.acts 添加地图，并提供该幕两个池和 Boss；缺少其中之一会被校验阻止，不会悄悄借用第一幕敌人。

现有行为支持攻击、护盾、状态、位移、拉拽、召唤、蓄力等 `EnemyActionDef.Kind`。全新的 AI 决策、Boss 阶段或新行动类型需要扩展规则代码；现有验证器当前要求 SequenceBehaviorDef。

### 添加角色与遗物

角色只需新增 CharacterDef、单位、初始卡组与遗物引用，登记后自动出现在选择页。`unlock_cost=0` 默认可选；大于 0 使用 Profile 的回响货币解锁。当前只有一个角色，更多角色的视觉映射仍需补齐。

已实现的遗物钩子及参数：

| trigger_key | 触发时机 | trigger_params |
|---|---|---|
| `battle_start` | 战斗第一次开场 | block、heal、energy、move_points、max_triggers_per_battle |
| `round_start` | 回合开始资源恢复后 | 同上 |
| `card_played` | 一次成功组合出牌命令结算后（按命令一次） | 同上 |
| `damage_taken` | 一次命令结算后玩家生命净下降时（按命令一次） | 同上 |
| `battle_victory` | 正式 Run 胜利事务 | reward_bonus、heal |

战斗钩子按 priority、遗物 instance_id 排序，计数器存入 BattleState；读档不会重复开场。命令末钩子不参与命令内部每段伤害的即时拦截，因此反伤、免死、每张牌逐次触发等新机制需要扩展结算事件接口。`reward_generated` 暂无实现，填入会被校验拒绝。

现有启用遗物：回声甲壳开场 +4 护盾，莫比乌斯硬币胜利 +1 金币。回环罗盘已停用，仅保留 ID 兼容旧存档；`RelicDef.enabled` 控制启用状态。

## 4. 推荐模块接口

下面列出支持上层调用的门面；下划线开头的方法是内部实现。定义资源当作只读，UI 不直接更改 Session.state。

### 全局服务

| 服务 | 推荐调用 | 结果/约定 |
|---|---|---|
| `App` | `ensure_profile()` | 读取或建立 ProfileState |
| `App` | `create_run(character_id, seed_text)` | 创建、绑定并立即尝试存档；替换旧局前归档；返回 RunState/null |
| `App` | `load_run()` | 读取并绑定 current_session/current_run |
| `App` | `end_run()` | 只结算终局，返回 bool；活动 Run 返回 false |
| `App` | `recover_ended_run()` | 主菜单重试未完成的终局归档 |
| `App` | `unlock_character(id)` | 扣回响并保存，失败不提交 Profile 副本 |
| `ContentDB` | `load_catalog(path)`、`ensure_loaded()` | bool；重复/无效 ID 拒绝注册 |
| `ContentDB` | `get_card/unit/enemy/status/relic/character/encounter/shop/event/monster_pool(id)` | 对应 Def 或 null |
| `ContentDB` | 各类 `*_ids()`、`all_cards()`、`reward_card_ids()` | 稳定 ID 枚举；池结果确定排序 |
| `SaveService` | `save_run(run)`、`save_profile(profile)` | bool；错误通过 persistence_error(message) 上报 |
| `SaveService` | `load_run(include_settled=false)`、`load_profile()`、`has_run()` | 检查主档/备份；has_run 仅对活动局为 true |
| `SaveService` | `archive_run(run)`、`clear_run()` | 终局归档并清理 current；应用层优先调用 App.end_run |
| `SettingsService` | `apply()`、`save_settings()`、`set_key(action,keycode)` | changed 信号；保存与改键返回 bool |
| `AudioService` | `play_music(key)`、`play_cue(key)` | 使用 AudioCatalog；未填音频的槽位静音 |
| `AudioService` | `play_bgm(stream,volume_db)`、`play_sfx(stream)` | 直接播放；音乐循环，音效 8 声部 |

### 整局玩法 RunSession

```gdscript
var session: RunSession = App.current_session
var available: Array[int] = session.available_node_ids()
# 战斗先部署；UI 提供玩家选中的起始格。
var pending: Dictionary = session.begin_deployment(available[0])
var transition: Dictionary = session.enter_node(available[0], Vector2i(0, 0))
if transition.get("ok", false):
    # kind == "battle" 时，将 transition["battle"] 交给 BattleScreen.configure。
    pass
```

| 方法/信号 | 含义 |
|---|---|
| `setup(run_state, content, campaign=null, save_service=null)` | 无头测试可注入内容和存档对象 |
| `create_run(character_id, seed_text, content, campaign=null)` | 静态纯玩法工厂；正式 UI 用 App.create_run 生成唯一局实例 ID 并存档 |
| `can_enter(id)`、`available_node_ids()`、`is_battle_node(id)` | 只读查询 |
| `preview_battle(id)` | 在 RNG 副本上生成部署预览，不消耗正式随机流 |
| `begin_deployment(id)`、`cancel_deployment()` | 保存/取消部署；取消不访问节点、不消耗 RNG |
| `enter_node(id, player_start)` | 唯一进入入口；成功返回 ok/kind/content_id，以及 battle/shop 等数据 |
| `resume_pending_flow()` | 根据持久化 flow_phase 重建界面所需数据 |
| `checkpoint_battle(state)` | 校验局/战斗 ID 和版本，保存已提交的战斗快照 |
| `on_battle_finished(result)` | 结算一次；校验 run_instance_id、pending_battle_id 与 settled_battle_ids |
| `generate_reward()` | 读取已经生成的 RewardState，名字保留兼容旧调用；不再抽取随机数 |
| `claim_reward(reward,index)` | 校验奖励身份与选项，领取；index=-1 放弃 |
| `resolve_node_action(action,data={})` | 下表中的节点事务入口 |
| `save()` | 保存当前内存状态，bool；last_save_ok 可查询最近保存结果 |
| `state_changed(run)`、`save_failed(message)` | 状态替换/持久化失败信号；保存失败后内存仍保留最新进度 |

`enter_node` 等 Dictionary 返回 `ok=false,error_code` 时没有玩法副作用。玩法成功与写盘成功不同：成功事务的内存状态会保留，`last_save_ok`/`saved` 标识是否已落盘。UI 必须允许重试，而不是重新执行奖励或购买。

| 当前阶段 | action | data |
|---|---|---|
| rest | heal / upgrade / leave | upgrade 使用 `{uid: run_card_uid}` |
| shop | buy / heal / remove / leave | buy 使用 `{index: offer_index}`；remove 使用 `{uid: run_card_uid}` |
| event | event_choice | `{index: choice_index}`；必须做选择，不能用 leave 跳过 |
| treasure | leave | 空；奖励已与进入节点一并提交，不再发放第二次 |

其他阶段或非法操作返回错误。商店 sold/remove_used/heal_used 随 pending 状态保存。

### 战斗玩法与表现接口

`BattleSession.setup(rng, initial_state, card_defs, enemy_behaviors, enemy_actions, target_validator, summon_pool)` 返回开场 EventBatch。只有 SETUP 阶段才执行首回合开始，恢复中途状态不会重新抽牌。

- `submit(GameCommand) -> CommandResult`：唯一提交入口；支持 PlayCardsCommand、MoveCommand、EndTurnCommand。command_id 必须单调分配并避免复用已见 ID。
- `preview(command)`：同一规则路径进行只读预览；不提交、不推进正式 RNG。
- `finish_presentation()`：动画播放完后解除 RESOLVING 锁。
- `battle_result() -> BattleResult`：只在终局返回结果，包含局实例 ID、战斗 ID、胜负、持续变化和 RNG 快照。
- `CommandResult.accepted/error_code/events/state_version`：输入层检查 accepted；表现层只播放 events 并读取最终状态，不重新计算伤害。

`BattleScreen` 的外部接口为 `configure(battle_data)`、`configure_deployment(preview)`，信号为 `battle_finished(result)`、`checkpoint_requested(state)`、`deployment_cell_chosen(cell)`、`deployment_cancelled`。先连接信号再 configure，防止恢复到终局时漏掉结算。正式屏禁止使用内部 demo 重开入口。

`EncounterBuilder.build(encounter, run, rng, content, player_start)` 产出标准 battle_data；`BattleCheckpoint.capture(data)` 与 `restore(payload,content)` 在值快照和运行时内容之间转换。所有内容引用通过稳定 ID 重绑定，存档不存 Node、Callable、Resource 实例。

## 5. 新机制的扩展位置

| 需求 | 扩展位置/约定 |
|---|---|
| 新原子效果 | 实现 EffectHandler，在 EffectResolver 初始化时 register_handler；必须同时让正式 resolver 和验证器认识该类型 |
| 特殊卡规则 | `FormalCardRuleRegistry.register_rule(card_id, callable)`；签名与 registry.resolve 一致，返回 handled/ok 等现有规则结果 |
| 特殊选牌、目标条件 | `CardChoiceRules`、`CardTargetRules`；规则检查与 UI 提示同时接入 |
| 卡牌共享计算 | `CardRuleSupport`；按技能/攻击/防御模块分组，避免把所有实现放回门面 |
| 回合状态 | `StatusTickSystem`、`RoundEffectSystem` |
| 敌人行动 | `EnemyTurnExecutor` 与 EnemyActionDef.Kind；新类型补战斗回放测试 |
| 胜负规则 | `OutcomeEvaluator`；TurnSystem 保持调用门面 |
| 整局节点种类 | `RunSession` 的阶段分发、`RunNodeTransaction`、RunFlow 页面分发一起扩展，补中断恢复测试 |
| 章节选择 | `EncounterSelector`、CampaignDef、ContentValidator；不要隐式回退错误幕内容 |
| 遗物效果 | `RelicSystem` 和触发位置；运行计数放 RelicState/BattleState，禁止写 Def |
| 新存档字段 | State + SaveCodec + SaveMigrator + 往返/旧版本测试一起改 |

注册在每次应用启动的装配阶段完成；当前没有面向第三方的热加载模组系统。`FormalCardRules`/`TurnSystem` 的门面仍保留以兼容既有调用。

## 6. 保存与验收

普通玩家不需要编辑 JSON。存档路径、恢复过程和旧版本限制详见 [存档说明](save_and_run_lifecycle.md)。

每次增加内容至少执行：保存资源 → 工作台校验 → `python tools/verify_project.py --godot <引擎路径>` → 实际进入新增内容 → 退出并继续一次。视觉编辑再用 `--capture --resolution 1366x768` 截图检查，人工看文字、遮挡、点击范围和键盘焦点。

稳定 ID 的删除/改名会影响旧存档；内容数值更新会影响旧战斗恢复后的行为。发布时应冻结版本，改动存档契约时写迁移代码；当前不保证任意热改规则后仍能重放旧版本战斗。


## 0.3.0 平衡编辑补充

全部升级、实时卡面、勇气/位移规则及批量调参入口见 [平衡说明](balance_design_2026-10-07.md#编辑入口与接口)。敌人实际数值与模拟方法见 [敌人表](balance_enemies_and_simulation_2026-10-07.md)。
