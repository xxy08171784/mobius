# 第二幕「墓道」系统（catacomb_system.md）

日期：2026-10-06。范围：**第二幕 8 只怪的池化、6 个新机制（虚弱/减速缠绕/随机区间/拖拽/净化/贯穿）、立绘接入**。
设计依据：`C:\Users\yang\Desktop\游戏机制.pdf`（怪物表/第二幕墓道）。合同变更见 `combat_rules.md` §8/§9/§10。

## 0. 一句话

第二幕沿用第一幕的池化/走位/威胁格/两朝向动画体系：小怪池 4 只、精英池 3 只、Boss 阴兵带召唤池。
新增 6 个引擎机制，让第二幕怪有各自的控制/防御特色；反伤/自爆/易燃 三项暂缓（见 §7）。

## 1. 池（`MonsterPoolDef`）

- `monster_pool.act2`（小怪池 4 只）+ `monster_pool.act2_elite`（精英池 3 只）+ `encounter.boss.act2`（阴兵 + 召唤池）。
- 检索完全复用第一幕泛化逻辑（`RunSession` 按 `act{N}`），**无需改代码**。
- 抽取规则同第一幕：普通战斗前 2 战 2 只、其后 2~4 只有放回；精英战 = 1 精英 + 2 小怪；Boss 单独上场、每隔 6 拍召唤一只小怪。

## 2. 新机制（2026-10-06）

| 机制 | 实现 | 载体 |
|---|---|---|
| 虚弱 | 来源侧伤害 −25%（`StatusRules.outgoing_damage_percent`，`damage_effect` 叠加到 percent） | 守墓尸「腐烂之握」 |
| 减速 | 每层开局移动力 −1（`StatusRules.move_penalty`，`TurnSystem.begin_round` 结算） | 泥俑「泥浆喷射」 |
| 缠绕 | 存在时开局移动力置 0（`StatusRules.move_locked`） | 蜘蛛「吐丝」 |
| 随机区间 | `EnemyActionDef.damage_min/max`、`block_min/max`；执行时在战斗流掷 | 尸鳖/石俑 |
| 拖拽 | `Displacement.pull`（朝施法者直线拉）+ `Kind.PULL` + `pull_effect`；伤害 = 每步 × 步数 | 阴兵「勾魂」 |
| 净化 | `cleanse_effect`（移除 流血/中毒/易伤/虚弱/减速/缠绕，保留正面）| 阴兵「阴气护体」 |
| 贯穿 | `EnemyActionDef.pierce`：主目标身后一格若为玩家阵营单位则追加同额伤害 | 阴兵「阴兵过境」 |

> 随机区间掷值发生在**执行时**（`battle_rng`），与结算同一流、确定性。意图预告显示区间文案「伤害9-12」。

## 3. 数值表

**小怪**（HP 20 / 移动 2 / 射程 1 菱形）：

| 名称 | 敌人 ID | 行为序列 |
|---|---|---|
| 蜘蛛 | enemy.catacomb.spider | `[approach, 毒液(中毒2), 吐丝(缠绕)]` |
| 纸人 | enemy.catacomb.paper | `[approach, 纸刃(5)]` |
| 鬼火 | enemy.catacomb.will_o_wisp | `[幽火(无视距离4, kiting)]` |
| 尸鳖 | enemy.catacomb.corpse_beetle | `[approach, 啃咬(6-8), 甲壳(3-6盾)]` |

**精英**（HP 30 / 移动 3）：

| 名称 | 敌人 ID | 行为序列 |
|---|---|---|
| 守墓尸 | enemy.catacomb.guard_corpse | `[approach, 重击(9), 腐烂之握(5+虚弱), 坚壁(6盾)]` |
| 泥俑 | enemy.catacomb.clay_figure | `[approach, 泥浆喷射(6+减速2), 固化(7盾)]` |
| 石俑 | enemy.catacomb.stone_figure | `[approach, 沉重打击(9-12), 岩石护甲(8-12盾)]` |

**Boss**（HP 50 / 移动 3）：阴兵 `enemy.catacomb.ghost_soldier`，6 拍循环
`[阴兵过境(贯穿10), 勾魂(拉2格,每格+3), 阴气护体(12盾+净化), 阴兵过境, 勾魂, 召唤]`。

## 4. 素材与动画接口

- 8 套两朝向待机立绘（`l*.png`/`r*.png`，3 或 4 帧），经 `tools/normalize_monsters.gd` 归一到
  1280×1280 / 脚底 y=1219，输出 `assets/textures/units/catacomb_<name>/`。
- **鬼火**登记悬停（`UnitSpriteFrames.HOVER_PX` `&"catacomb_will_o_wisp"`），其余地面单位。
- 缺素材自动回退色块菱形（可无头跑）。

## 5. 文件清单

- 新增：`content/enemies/catacomb_{spider,paper,will_o_wisp,corpse_beetle,guard_corpse,clay_figure,stone_figure,ghost_soldier}[_unit].tres`、
  `content/statuses/{weak,slow,entangle}.tres`、`content/pools/act2_{monsters,elite}.tres`、
  `content/encounters/boss_act2.tres`、`assets/textures/units/catacomb_*/`、
  `gameplay/effects/handlers/{pull_effect,cleanse_effect}.gd`、`tests/rules/test_act2_mechanics.gd`。
- 改动：`enemy_action_def.gd`(+Kind.PULL / damage_min/max / block_min/max / cleanse / pierce)、
  `turn_system.gd`(移动限制/区间掷值/PULL/贯穿/净化分支)、`status_rules.gd`(+weak/slow/entangle)、
  `damage_effect.gd`(来源侧百分比)、`displacement.gd`(+pull/pull_path)、`effect_resolver.gd`(注册 2 handler)、
  `unit_view.gd`(状态文案)、`unit_sprite_frames.gd`(悬停)、`battle_presenter.gd`(技能文案)、
  `content/catalog.tres`(注册)。

## 6. 测试（`tests/run_all.gd` 自动采集）

`test_act2_mechanics.gd`（虚弱/减速缠绕/拖拽/贯穿/区间/净化 + 内容注册）；
`test_elite_boss.gd` 新增第二幕小怪节点走墓道池、Boss 节点 = 阴兵 + 召唤池 4 只。

## 7. 暂缓项（明确标注，非遗漏）

**已实现（2026-10-06 反应系统 v1，见 `combat_rules.md` §7.5）**：鬼火「反伤 3 / 自爆（死亡 3×3 造成 6）」、石俑「崩裂（受击反伤 2）」——经 `EnemyDef.reactions` 落地。

**仍暂缓**：

| 怪物 | 技能 | 说明 |
|---|---|---|
| 纸人 | 易燃（受火焰伤害 +5） | 需"火焰伤害类型/元素"子系统，非反应范畴 |
