# 第三幕「内墓」系统（crypt_system.md）

日期：2026-10-06。范围：**第三幕 8 只怪的池化、2 个新机制（腐蚀/着火）、立绘接入、玩家血量调至 80**。
设计依据：`C:\Users\yang\Desktop\游戏机制.pdf`（怪物表/第三幕内墓）。合同变更见 `combat_rules.md` §8。

## 0. 一句话

第三幕沿用前两幕的池化/走位/威胁格/两朝向动画体系：小怪池 4 只、精英池 3 只、Boss 墓主人带召唤池。
新增 2 个状态机制（腐蚀=防御 −25%、着火=火焰 DoT），其余技能复用现有机制。玩家血量已调至 **80**。

## 1. 玩家数值（2026-10-06）

- `content/enemies/prototype_unit.tres`（玩家 UnitDef `unit.hero.prototype`）：`stat.max_hp` 30 → **80**。
- **移动保持 2**（设计文档写 3，本轮经确认不改）。
- 影响的测试已同步：`test_run_session.gd`（初始 max_hp/满血）、`test_node_systems.gd`（休息回血、事件加血按 80 上限）。

## 2. 池（`MonsterPoolDef`）

- `monster_pool.act3`（小怪池 4 只）+ `monster_pool.act3_elite`（精英池 3 只）+ `encounter.boss.act3`（墓主人 + 召唤池）。
- 检索完全复用泛化逻辑（`RunSession` 按 `act{N}`），**无需改代码**。抽取规则同前两幕。

## 3. 新机制（2026-10-06）

| 机制 | 实现 | 载体 |
|---|---|---|
| 腐蚀 | 获得护盾 −25%（`StatusRules.outgoing_block_percent`，`block_effect` 按获得方折算） | 变异史莱姆「腐蚀粘液」、食尸鬼「舔舐」 |
| 着火 | 火焰 DoT，回合结束按 层数×5 掉血、减层、吃护盾（`dot_tick_damage`/`is_stack_decaying`） | 旱魃「炽热爪击」 |

**复用**：钳制≈减速（`status.slow`）、双斩=多段（`hit_count=2`）、旱地冲击=方框射程 2（`BOX` r2）、消化液=中毒、石肤/防御=护盾、召唤守墓=召唤池。

## 4. 数值表

**小怪**（HP 25 / 移动 2 / 射程 1 菱形）：

| 名称 | 敌人 ID | 行为序列 |
|---|---|---|
| 变异史莱姆 | enemy.crypt.mutated_slime | `[approach, 腐蚀粘液(5+腐蚀2)]` |
| 石狮子 | enemy.crypt.stone_lion | `[approach, 沉重石击(7), 石肤(5盾)]` |
| 地狱骷髅 | enemy.crypt.hell_skeleton | `[approach, 朽骨挥砍(6)]` |
| 食人花 | enemy.crypt.man_eating_flower | `[approach, 撕咬(7), 消化液(中毒3)]` |

**精英**（HP 40 / 移动 3）：

| 名称 | 敌人 ID | 行为序列 |
|---|---|---|
| 旱魃 | enemy.crypt.drought_demon | `[approach, 炽热爪击(8+着火1), 旱地冲击(BOX r2, 5)]` |
| 蜥蜴人 | enemy.crypt.lizardman | `[approach, 双斩(5×2), 防御(5盾), 钳制(减速2)]` |
| 食尸鬼 | enemy.crypt.ghoul | `[approach, 爪击(7), 舔舐(腐蚀2)]` |

**Boss**（HP 70 / 移动 3）：墓主人 `enemy.crypt.tomb_master`，3 拍循环
`[棺椁重击(12), 防御(8盾), 召唤守墓]`，召唤池 = [地狱骷髅, 石狮子]。
（设计为"召唤 2 地狱骷髅 或 1 石狮子"，本轮近似为从 2 只池中召唤 1 只。）

## 5. 素材与动画接口

- 8 套两朝向待机立绘（`l*.png`/`r*.png`，各 3 帧），经 `tools/normalize_monsters.gd` 归一到
  1280×1280 / 脚底 y=1219，输出 `assets/textures/units/crypt_<name>/`。均为地面单位，无悬停。

## 6. 文件清单

- 新增：`content/enemies/crypt_{mutated_slime,stone_lion,hell_skeleton,man_eating_flower,drought_demon,lizardman,ghoul,tomb_master}[_unit].tres`、
  `content/statuses/{corrode,ignite}.tres`、`content/pools/act3_{monsters,elite}.tres`、
  `content/encounters/boss_act3.tres`、`assets/textures/units/crypt_*/`、`tests/rules/test_act3_mechanics.gd`。
- 改动：`status_rules.gd`(+corrode/ignite/`outgoing_block_percent`/`dot_tick_damage`)、
  `block_effect.gd`(腐蚀折算)、`turn_system.gd`(DoT 用 `dot_tick_damage`)、`cleanse_effect.gd`(负面清单)、
  `unit_view.gd`/`battle_presenter.gd`(状态文案)、`content/catalog.tres`(注册)、
  `content/enemies/prototype_unit.tres`(玩家血量 80)。

## 7. 测试（`tests/run_all.gd` 自动采集）

`test_act3_mechanics.gd`（腐蚀/着火/净化 + 内容注册）；`test_elite_boss.gd` 新增第三幕小怪节点走内墓池、
Boss 节点 = 墓主人 + 召唤池 2 只；`test_content_db.gd` 数量断言更新；玩家血量相关断言在 `test_run_session.gd`/`test_node_systems.gd`。

## 8. 留待下一轮（明确标注，非遗漏）

以下均需 on_death / on_damaged **反应系统**，与前两幕遗留项一并留待下一轮统一实现：

| 幕 | 怪物 | 技能 | 说明 |
|---|---|---|---|
| 第二幕 | 鬼火 | 反伤 / 自爆 | 受击反弹 3 / 死亡 3×3 造成 6 |
| 第二幕 | 纸人 | 易燃 | 需火焰伤害类型（受火焰 +5） |
| 第二幕 | 石俑 | 崩裂 | 受击反伤 2 |
| 第三幕 | 变异史莱姆 | 分裂 | 死亡时原地生成 2 只 5HP 微型史莱姆 |
| 第三幕 | 地狱骷髅 | 亡灵意志 | 死亡时让墓主人下回合 +2 攻 |
| 第三幕 | 旱魃 | 汲血 | 回血 = 玩家攻击 ×120%，玩家防御则不触发 |
| 第三幕 | 食尸鬼 | 食尸鬼体质 | 场内有单位死亡时自愈 +7、下回合 +2 攻 |
