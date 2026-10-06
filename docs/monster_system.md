# 怪物系统（第一幕·墓外）

日期：2026-10-06。范围：**第一幕小怪的池化、走位、攻击范围形状、威胁格显示、两朝向待机动画接口**。
设计依据：`C:\Users\yang\Desktop\游戏机制.md`（怪物表/地块/移动）。合同变更见 `combat_rules.md` §2/§10。

## 0. 一句话

进入战斗时从**怪物池**抽 2~4 只墓外小怪；怪物沿**真实路径持续接近**玩家（远程怪风筝），
攻击用**方框（含对角）**范围；点击怪物可看到它**能打到的格子**；每只怪预留**与玩家同一套的两朝向待机动画**。

## 1. 怪物池（`MonsterPoolDef` + `MonsterPool`）

- `gameplay/run/monster_pool_def.gd`（Resource）：`enemy_ids` 池 + 棋盘/回合模板（同 `EncounterDef` 字段）。
- `gameplay/run/monster_pool.gd`（纯静态，`MonsterPool`）：
  - `draw_count(battle_index, rng)`：`battle_index <= 2` → **2**；否则 `randi_range(2, 4)`。
  - `draw_ids(pool, battle_index, rng)`：**有放回**均匀抽（允许同种重复）。
  - `build_encounter(pool, battle_index, rng)`：把抽到的 ids + 棋盘模板合成**临时 `EncounterDef`**，复用 `EncounterBuilder.build`。
- `battle_index` = `RunState.next_battle_id`（1 起、每进一个战斗节点 +1、已随存档持久化）。**"前 2 个战斗节点固定 2 只"按整局计。**
- 接线：`RunSession._resolve_node` 的 `node.monster` 优先走池（`ContentDB.get_monster_pool("monster_pool.act{act+1}")`），无池则回退固定 `EncounterDef`；elite/boss 仍用固定遭遇。
- 随机取自 `RngStreams` 的 `encounter` 流，确定性。

## 2. 走位（A* 逼近 / 远程风筝 / 执行时重算）

`EnemyPlanner.plan_move(board, enemy, target_cell, move_budget, action) -> Array[Vector2i]`（纯函数，返回真实路径含起点）：
- 近战（`action.kiting=false`）：优先"能打到目标"的落点（离目标最近）；都打不到则尽量接近；**已能攻击即原地**（不横向挪动）。
- 远程（`action.kiting=true`）：能打到目标时取**离目标最远**的落点（风筝）；都打不到则接近以进入射程；已在最远处则原地。
- 评分格距用**曼哈顿**（与射程形状无关），保证 `UNLIMITED` 射程的远程怪也能正确"拉开距离"。
- **执行时重算**：`TurnSystem._approach_plan` 在敌人行动那一刻按**当前**最近玩家格调用 `plan_move`（`combat_rules.md` §2）。攻击/防御仍用回合开始锁定的意图。
- **每回合"先移动再行动"**（2026-10-06）：`ATTACK` 行动若 `advance_steps>0`，执行时先按当前玩家 `plan_move`（近战逼近/远程风筝）推进，**命中从移动后的格子判定** → 敌人和玩家同构，每回合都动一次再出手（不再隔回合移动）。`DASH` 自带移动；`DEFEND/SUMMON/CHARGE` 为 0。旧 `APPROACH`（`move_steps`）保留给特殊用法。

## 3. 攻击范围形状

`EnemyActionDef.range_shape`（引用 `BoardQuery.RangeShape`）：`BOX`（默认，含对角）/ `DIAMOND` / `UNLIMITED`。
命中判定（`TurnSystem._attack_plan_if_valid`）与威胁格显示共用 `BoardQuery.within_range` / `get_target_cells_shaped`。详见 `combat_rules.md` §10。

## 4. 威胁格显示（点击怪物）

- `EnemyPlanner.threat_cells(board, enemy_id, actions)`：该怪**所有攻击类行动射程的并集**（`UNLIMITED` → 全盘可见格）。
- `BattlePresenter.refresh` 在选中目标为敌人时计算并下发 `BoardView.set_threat_cells`；紫色高亮（`THREAT_COLOR`）叠加在常规高亮之上。再点同一只 / 点空地清除。

## 5. 动画接口（与玩家完全同一套）

- **两段动画 = 朝屏幕左 / 朝屏幕右**（互为镜像），**没有**走路/攻击/受击/死亡帧；位移与待机都复用这两段。
- 目录：`res://assets/textures/units/<appearance_key>/`，文件 `l*.png` / `r*.png` → 动画 `walk_l` / `walk_r`（与玩家同名同套）。**帧数可变**（3 帧、4 帧都行，只加载目录里实际存在的）。
- 加载：`UnitSpriteFrames.get_frames_for(appearance_key)`（按 key 缓存；缺素材返回 null）。`UnitView.setup(id, is_player, appearance_key)`；敌人由 `BoardView` 经 `ContentDB.get_unit(def_id).appearance_key` 解析。缺素材回退色块菱形，不报错。
- **规格统一**：单位帧一律 **1280×1280 画布、脚底 y=1219、水平居中 x=640**（与玩家同款），`UnitView` 的 `SPRITE_SCALE` / `SPRITE_FEET_OFFSET` 对所有单位通用。原始怪物美术画布不一（1280/2560/5120），用一次性工具归一化：`tools/normalize_monsters.gd`（`-- <源目录> <appearance_key>`，内容最长边只降不升 ≤940）。
- **飞行悬停**：飞行单位在渲染时**整体上移**（精灵 + 浮标），地面单位踩在格子上。悬停高度在 `UnitSpriteFrames.HOVER_PX`（纹理像素，当前：蝙蝠 150、引魂灯 120；可调）。
- **当前已接入**（8 只墓外怪）：`tomb_scorpion` / `tomb_slime` / `tomb_soul_lantern` / `tomb_bat` / `tomb_skeleton` / `tomb_crossbow` / `tomb_statue` / `tomb_viper`。
- 新增一只是纯数据：写好 `.tres`（带 `appearance_key`）+ 把 `<appearance_key>/l*,r*.png` 丢进目录即可，无需改代码；缺素材自动回退色块。

## 5.1 数值面板与死亡表现

- **数值面板**：点击怪物 → 侧栏 `monster_label` 显示名字 / `HP x/max（盾）` / 技能摘要。名字走 `UnitState.enemy_id -> ContentDB.get_enemy().display_name`（缺则回退外观键）；技能摘要由 `BattleSession.enemy_actions_for(unit_id)` 自动生成（`伤害N[×k]` / `防御N` / `冲撞N` / `召唤` / `无视距离` / `附带中毒N`）。
- **进场选格预览**（2026-10-06）：进入战斗节点先弹"选择进场位置"盘——**红格 = 敌人落点，绿格 = 可选进场格**。`RunSession.preview_battle` 在 **RNG 克隆**上解析（不提交、不推进正式 RNG）；敌人落点**不依赖玩家起点**（`EncounterBuilder._plan_enemy_spawns` 只从内部格洗牌，玩家选格恒在外圈），故**预览 = 开战时**。
- **死亡表现**：`hp==0` 时规则层即从棋盘移除（尸体不占格，`combat_rules.md` §6/§9）；表现层在命中事件 `after.hp<=0` 时串播 撞击+脉冲 → `BoardView.animate_death`（上升 ~70px + 虚化 ~0.7s），动画结束后由 `_sync_units`（按棋盘占用）释放视图 → 上升→虚化→消失。

## 6. 第一幕数值表与技能边界

**小怪**：HP 12 / 移动 2 / 攻击范围 3×3（`BOX` 半径 1）。行为 = `SequenceBehaviorDef([approach, attack])`，`fallback` = approach。

| 名称 | 敌人 ID | 本轮技能 | 留待下一轮 |
|---|---|---|---|
| 引魂灯 | `enemy.tomb.soul_lantern` | 幽火：`UNLIMITED` 伤害 6（远程，`kiting=true`） | 引魂（下次伤害 +2） |
| 蝙蝠 | `enemy.tomb.bat` | 啃咬：方框半径 1 伤害 7 | 嗜血（受击后攻击 +2） |
| 蝎子 | `enemy.tomb.scorpion` | 毒刺：施加 4 层中毒（`status.poison`，持续 3） | 钩刺拖拽（拖拽 2 格 + 每步额外伤害） |
| 史莱姆 | `enemy.tomb.slime` | 弹力碰撞：方框半径 1 伤害 6 | 死亡爆炸（3×3 变水潭，改地形） |

- 中毒（`status.poison`）与流血同型：拥有者回合结束按层数掉血；**中毒无视护甲（不吃护盾）且减层数**，流血吃盾、按持续递减（见 `combat_rules.md` §8）。
- 敌人"命中附带状态"经 `EnemyActionDef.apply_status_id/stacks/duration`，由 `TurnSystem._attack_plan_if_valid` 组装 `apply_status` 效果。
- 旧莫比乌斯怪（`echo_guard/loop_hound/ring_stalker/mobius_warden`）**保留**，仍可在战斗屏 demo 选择器使用。

### 6.1 精英（HP 25~27 / 移动 3 / 攻击范围 5×5 = `BOX` 半径 2）

精英战组成 = **1 精英（精英池随机）+ 2 小怪（小怪池有放回）**，共 3 个敌人。

| 名称 | 敌人 ID | 行为序列 |
|---|---|---|
| 毒蛇 | `enemy.tomb.viper` | `[approach, venom(施加4层中毒), bite(7)]` |
| 朽骨骷髅 | `enemy.tomb.skeleton` | `[approach, slash(7), heavy(11), guard(5)]` |
| 驽俑 | `enemy.tomb.crossbow` | `[approach(kiting), shot(无视距离8), volley(4×2)]` |

毒蛇的"无视护甲"即中毒本身的机制（中毒不吃护盾）；驽俑远程风筝（`kiting=true`），强射为多段（`hit_count=2`）。

### 6.2 Boss（陵墓石像 HP 38 / 移动 3 / 攻击范围 5×5）

| 敌人 ID | 行为序列（循环，4 回合） |
|---|---|
| `enemy.tomb.tomb_statue` | `[dash(6, 每走一步+3), smash(8), guard(7), summon]` |

- 单独上场，**每隔 4 回合**（序列第 4 拍）**召唤**一只墓外小怪在玩家附近（切比雪夫 ≤2 的空格，`TurnSystem.SUMMON_RADIUS`）。
- 遭遇 `encounter.boss.act1` 的 `summon_enemy_ids` 列出 4 只小怪；`EncounterBuilder` 解析成**召唤池**。

### 6.3 四个新机制（本轮）

| 机制 | 载体 |
|---|---|
| 多段伤害 | `EnemyActionDef.hit_count`（强射 4×2） |
| 无视护甲 DoT | 伤害管线参数 `ignore_block`；中毒的 `StatusRules.is_armor_ignoring` |
| 随位移加成伤害 | `Kind.DASH` + `dash_damage_per_step`；伤害 = `damage + 移动步数 × per_step` |
| 中毒改减层 | `StatusRules.is_stack_decaying` / `decay_stacks`（层数驱动，跳过持续递减） |
| 召唤 | `Kind.SUMMON` + 召唤池（见 §6.4） |

### 6.4 召唤架构

不做成 `EffectResolver` 效果（效果解析器是**内容无关**的规则层，拿不到 ContentDB）。改由 `TurnSystem` 直接生成：

1. `EncounterBuilder.build` 把 `encounter.summon_enemy_ids` 经 content 解析成 **spec 列表**（`{enemy_id, unit_def_id, max_hp, appearance_key, behavior, actions}`），放进装配 dict 的 `"summon_pool"`。
2. `BattleSession.setup` 保存 `summon_pool` 并透传给 `TurnSystem.run_end_turn`。
3. `TurnSystem._execute_summon`：随机取一条 spec → 分配不冲突的 `next_uid`（`_next_unit_id`）→ 建 `UnitState` → 在玩家附近落点 → **把该单位的 behavior/actions 注册进会话字典**（随后的 `begin_round` 锁意图即带上，**召唤单位首回合即可行动**）→ 产 `unit_summoned` 事件。
4. **不动 `BattleState`/`SaveCodec`**：召唤单位的 behavior 存活在会话字典（不序列化），而 v1 明确"战斗内不续档"；`duplicate_state` 只用于单条命令的工作快照，会话字典仍有效。

## 6.5 精英 / Boss 组装（`MonsterPool` + `RunSession`）

- `MonsterPool.draw_elite_composition(elite_pool, mob_pool, rng)` / `build_elite_encounter(...)`：1 精英 + 2 小怪。
- `RunSession` 节点分配：`node.monster` → 小怪池抽 2~4；`node.elite` → 精英组成（池 `monster_pool.act1_elite` + 小怪池）；`node.boss` → 直接取 `encounter.boss.act1`（墓外石像 + 召唤池）。旧固定遭遇作回退保留。

## 7. 文件清单

小怪轮新增：`gameplay/run/monster_pool_def.gd`、`gameplay/run/monster_pool.gd`、`content/pools/act1_monsters.tres`、`content/enemies/tomb_{soul_lantern,bat,scorpion,slime}[_unit].tres`、`content/statuses/poison.tres`。
精英/Boss 轮新增：`content/enemies/tomb_{viper,skeleton,crossbow,tomb_statue}[_unit].tres`、`content/pools/act1_elite.tres`、`content/encounters/boss_act1.tres`。
改动：`enemy_action_def.gd`(+range_shape/kiting/apply_status*/hit_count/dash_damage_per_step/Kind.DASH+SUMMON)、`enemy_planner.gd`(plan_move/plan_approach/threat_cells)、`board_query.gd`(+RangeShape/shaped/within_range)、`turn_system.gd`(形状判定/移动重算/DoT/多段/DASH/SUMMON/召唤池、`ignore_block`)、`damage_effect.gd`(+ignore_block)、`status_rules.gd`(+is_armor_ignoring/is_stack_decaying/decay_stacks)、`battle_session.gd`(+enemy_actions_for/summon_pool)、`encounter_def.gd`(+summon_enemy_ids)、`encounter_builder.gd`(+summon_pool)、`run_session.gd`(小怪池/精英组成/Boss 接线)、`monster_pool.gd`(+精英组成)、`content_db.gd`/`content_catalog.gd`/`catalog.tres`(+monster_pools)、`unit_sprite_frames.gd`/`unit_view.gd`/`board_view.gd`/`battle_presenter.gd`(动画接口/威胁格/召唤日志)。

## 8. 测试（`tests/run_all.gd` 自动采集）

`test_range_shape.gd`（方框含对角/菱形回归/无视距离/LoS 过滤）、`test_enemy_movement.gd`（逼近/绕墙/停手/风筝/**执行时重算**/威胁格）、`test_monster_pool.gd`（前 2 战=2、2~4、确定性、有放回、合成 EncounterDef）、`test_enemy_mechanics.gd`（多段/无视护甲 DoT/流血回归/DASH/SUMMON 含首回合可行动与确定性）、`test_elite_boss.gd`（精英组成 1+2 / 精英节点 3 敌 / Boss 节点石像+召唤池）。
`test_run_session.gd` 新增"第 1 个战斗节点走池 → 2 只墓外怪"的集成断言。
