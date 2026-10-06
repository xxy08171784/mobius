# Phase 4：最小战斗屏 UI（占位美术版）

当前没有正式角色、卡牌、棋盘或 VFX 美术，因此 Phase 4 第一版使用 Godot 原生 `Control/Button/Label` 作为占位表现。

## 已落地

- `battle_screen.tscn/gd`：战斗屏装配与 Demo 战斗入口。
- `board_view.tscn/gd`：**等轴测棋盘**（2026-10-06 起）——`TileMapLayer` 铺首章地块 + `UnitView` 单位棋子 + 可移动/意图/目标/悬停高亮，自动缩放居中；由 `IsoBoardTheme`（运行时 TileSet）与 `IsoGrid`（几何）支撑，对外接口 `cell_pressed`/`render_state`/`pulse_unit` 不变，另加 `render_deployment`。此前为 8×8 按钮网格占位。
- `hand_view.tscn/gd`：手牌、卡牌 UID、组合选择顺序。
- `battle_input.gd`：卡牌选择、目标选择、移动、出牌、结束回合全部转换成 `GameCommand`。
- `battle_presenter.gd`：只读 BattleState / EventBatch，更新 HUD 与战斗记录。
- `animation_queue.gd`：按 EventBatch 顺序播放的最小节拍队列；后续美术动画从这里接入。
- `demo_battle_setup.gd`：仅用于原型的 1 玩家 / 1 敌人 / 3 类卡牌数据。
- `ConfiguredEffectDef`：提供可配置的具体 EffectDef，避免正式代码依赖 tests fixture。

## 当前操作

1. 没有选牌时点击空格：提交 `MoveCommand`。
2. 点击一张或多张手牌：按点击顺序形成组合。
3. 点击敌人：锁定单位目标。
4. 点击“打出所选”：提交 `PlayCardsCommand`。
5. 点击“结束回合”：提交 `EndTurnCommand`，敌人执行已锁定 Intent，并进入下一回合。
6. 点击“速度 1×”：循环切换 1×/2×/3×，加快玩家与敌人的**行走位移**；`AnimatedSprite2D` 帧率不变（动画不加速）。倍率跨场次保留（`BoardView.last_speed_multiplier`）。

Demo 中攻击牌统一使用 Manhattan 距离 1 + LoS 作为占位射程规则。正式卡牌的射程/LoS 字段仍需内容规则确定后再进入 CardDef，不把原型规则偷偷写成正式合同。

## 美术接入点

后续有正式美术后主要替换/扩展 `BoardView`、`HandView/CardView` 与 `BattleAnimationQueue`。`BattleSession`、`BattleState`、效果结算和命令入口不需要因换美术而重写。
