# 0.4.0 战斗操作与 HUD

本轮按已确认方案实现：拖拽立即打出单牌，点击保留组合选择。保留前一轮卡牌升级、状态与敌人数值，以及 0.3.1 导出资源加载修复。

## 玩家操作

- 拖动手牌到有效敌人或格子后松手，直接打出该牌；防御、自身增益等无外部目标牌可拖到棋盘内释放。
- 拖到棋盘外取消；无效目标、超出范围或其他规则不允许时不扣资源、不消耗卡牌。拖动时有效落点显示绿色边框，无效落点显示红色边框。
- 点击手牌仍然选择组合，点击敌人或格子指定目标，按出牌键或“打出所选”确认。点击目标不会立即出牌。拖动单牌时只打出拖动的那张牌。
- 需要选择抽取、弃置等卡牌的技能仍打开选择窗口；取消窗口不消耗资源。
- 能量不足的牌变暗，点击或尝试拖动时中央短暂显示“能量不足”。组合按总实际消耗限制，升级减费与本场临时减费均计入；有效消耗为零的牌仍可使用。
- 删除手牌上方常驻描述/预览文字；牌面与悬浮详情保留完整说明和实时数值。
- 默认 Q 确认组合、E 结束回合、Backspace 清除选择；可在设置改键，出牌与结束回合按钮同步显示当前键位。

## HUD 与怪物意图

能量、移动力、弃牌堆、结束回合、攻击意图、施加状态意图使用新绘制的六张透明 PNG。能量显示当前/每回合值；移动显示剩余/每回合值，缠绕时显示“缠绕”。能量或移动耗尽时对应图标变暗。

玩家与所选敌人的护盾数字置于盾牌内部，零护盾时图标与数字一起隐藏。左右面板按护盾和状态数量收缩。敌人详细血量、护盾和状态仍只在选中时显示。

敌人意图使用图标与数值：有伤害时显示剑与伤害值，多段攻击显示每段值与次数；零伤害的施加状态行动显示施法图标与层数。攻击同时施加状态时增加小施法图标。防御、移动、召唤和等待保留相应区分；悬停显示细节，点击意图可选中怪物。参考 [Lost in Fantaland 的官方产品介绍](https://store.steampowered.com/app/1266430/Lost_In_Fantaland/) 的棋盘卡牌交互方向，未复制其美术素材。

## 素材与可视化编辑入口

素材由内置 `image_gen` 生成，透明背景，原文件保存在项目内，不依赖机器上的生成缓存。完整提示词记录在 `assets/textures/ui/hud_v04/prompts.json`。

| 内容 | 文件或 Godot 场景入口 |
| --- | --- |
| 六张原始 PNG | `assets/textures/ui/hud_v04/energy.png`、`movement.png`、`discard.png`、`end_turn.png`、`intent_attack.png`、`intent_status.png` |
| 图标绑定与透明边距裁切 | `presentation/common/ui_art.gd` 的 `GENERATED_KEYS` / `texture()` |
| 能量、移动、牌堆、结束回合位置大小 | `presentation/battle/battle_card_hud.tscn`，在 Godot 2D 编辑器拖拽相应节点 |
| 血量、盾牌、状态、敌人面板 | `presentation/battle/battle_hud.tscn`；动态高度在 `battle_hud.gd::_fit_panel()` |
| 手牌、确认与清除按钮 | `presentation/battle/battle_screen.tscn` 的 `HandView` / `ActionButtons` |
| 卡牌外观与悬浮详情 | `presentation/cards/battle_card_view.tscn`、`battle_card_view.gd` |
| 怪物意图框尺寸与布局 | `presentation/battle/enemy_intent_bubble.gd` 的 `BUBBLE_SIZE` / `_ready()` |
| 意图图标和数字映射 | `presentation/battle/battle_presenter.gd` 的 `_intent_icon()` / `_intent_badge_text()` |
| 中央提示位置、字号与时间 | `presentation/battle/battle_screen.gd` 的 `_create_feedback()` / `show_feedback()` |

PNG 的 Godot 导入尺寸上限设为 256，保留透明度；UI 使用最近邻过滤。运行时仅裁切透明边距，不改写原图。替换同名图片并重新导入即可生效。

## 交互接口

| 接口 | 用途 |
| --- | --- |
| `CardSelectionBudget.total_cost(state, defs, uids)` | 用实际卡牌状态计算组合能量消耗 |
| `BattleInput.can_start_drag(uid)` | 检查能否开始拖动，能量不足时发出反馈 |
| `BattleInput.drop_status(uid, cell)` | 只预演，不修改战斗状态或随机数；空字符串表示可释放 |
| `BattleInput.play_dropped(uid, cell)` | 释放时重新验证并通过现有命令通道打出单牌 |
| `BoardView.card_dropped(uid, cell)` | 棋盘向输入层传递释放落点 |
| `BattleInput.feedback_requested(message)` | 输入层向界面发送短暂提示 |
| `BattleCardView.drag_validator` | 仅手牌启用拖动；奖励、牌库预览不启用 |

## 验证与试玩

`tools/verify_project.py --capture` 在隔离存档中执行导入、内容检查、全部规则测试、原场景流程测试、原生 GUI 拖拽测试、正式入口启动和截图。新测试在 `tests/battle_controls_smoke.gd`，覆盖有效/无效释放、盘外取消、组合确认、零费牌、临时减费、组合预算、二次选牌取消、护盾和状态意图。合成事件注入独立 SubViewport，不移动操作者的系统鼠标。

`tools/verify_export.py --package <Mobius.pck> --capture` 从真正的发布 PCK 检查地板、25 种单位动画、六张 HUD 图标、图标不重叠且文字位于屏幕内、地图进入部署、64 格拾取、拖牌获得护盾且只扣一次能量、下一回合与读档。分别检查 OpenGL 与默认 Forward+ / D3D12；正式 EXE 另做实际启动检查。发布模板不允许从命令行替换测试脚本，因此 PCK 流程测试使用同版本引擎运行包外测试驱动。

导出截图额外发现：父场景启用 HUD“可编辑子节点”后，导出时会生成子节点的锚点预设覆盖，使底部图标的偏移重置。已删除没有实际用途的该继承覆盖，HUD 布局统一在 `battle_card_hud.tscn` 编辑；上述导出布局断言可防止同类回归。

本次最终检查：52/52 组规则通过；内容、场景、原生拖拽与截图测试均无失败。1366×768 和 1920×1080 已检查；真正发布 PCK 的 OpenGL、Forward+ / D3D12 流程与 HUD 布局均通过，正式 EXE 两种模式的启动退出码均为 0。测试环境的 Windows 根证书读取提示与离线游戏无关，由验证器单独识别，其他引擎或脚本错误仍判定失败。

0.4.0 试玩包位于 `builds/playtest/Mobius-0.4.0-UI-Windows-x64.zip`。请完整解压并一起分发 EXE 与 PCK，不要混用旧包文件。测试日志和截图在 `.validation`，发布包和日志不提交到 Git。自动化不能代替真人手感与长期平衡试玩。
