# Phase 3 战斗集成说明

Phase 3 把 A1 效果、A2 卡牌与 B1 棋盘、B2 单位、B3 敌人规划接成正式战斗规则闭环。

## 1. BattleState

正式 BattleState 现在持有：

    phase / resume_phase / round_index / version
    board
    units
    deck
    enemy_intents
    enemy_steps
    enemy_charge_remaining / enemy_charge_intents
    rng_snapshot
    seen_command_ids / command_result_snapshots
    next_uid / next_event_seq

位置仍以 BoardState 为唯一权威；UnitState 不保存坐标。

## 2. BattleFactory

当前仓库还没有 RunState，因此没有伪造一套 RunState。

现阶段入口：

    BattleFactory.create_state(
        battle_id,
        board,
        units,
        deck,
        rng,
        hand_size,
        energy_per_round,
        move_points_per_round
    )

未来 RunState 落地后，只需要把 RunState / Encounter 数据转换成这些输入，不需要重写 BattleSession。

## 3. BattleSession

核心接口：

    setup(...)
    preview(command)
    submit(command)
    finish_presentation()
    battle_result()

submit 的固定校验顺序：

    command_id 去重
      ↓
    phase / command lock
      ↓
    actor
      ↓
    command type
      ↓
    cost
      ↓
    target
      ↓
    combo / resolve
      ↓
    一次性提交 State + RNG

任何失败都不修改权威 State，也不推进正式 RNG。

成功的非终局命令进入 RESOLVING 并设置 command_locked。表现层播放完 CommandResult.events 后调用 finish_presentation()，恢复到 resume_phase。

## 4. 玩家命令

### PlayCardsCommand

- 使用 ComboPlanner 顺序预演；
- 费用一次性计算与扣除；
- 卡牌 hand -> resolving -> discard / exhaust；
- 前一张牌位移后，后一张牌使用新状态重新检查目标；
- 中途终局时跳过后续 attack 卡效果，但继续完成牌区清理。

CardDef / TargetSpec 负责目标种类与阵营合同。

BattleSession 还接受可选 target_validator，用于内容层接入 B1 BoardQuery 做具体射程、LoS 或特殊目标条件。当前 CardDef / TargetSpec 数据合同本身没有统一的数值射程与 LoS 字段，所以 Phase 3 没有自行发明字段。

### MoveCommand

默认关闭；只有 move_points_per_round > 0 时接受。

路径与占用由 Pathfinder / Displacement 判定，成功后扣除实际路径步数。

### EndTurnCommand

一次命令完成：

    PLAYER_END
      ↓
    ENEMY_ACT
      ↓
    ROUND_END
      ↓
    下一轮 ROUND_START
      ↓
    PLAYER_INPUT

## 5. 敌人行动

敌人 Intent 在 ROUND_START 锁定。ENEMY_ACT 不重新规划，而是执行锁定 Intent：

- ATTACK -> A1 Damage Effect；
- DEFEND -> A1 Block Effect；
- APPROACH -> A1 Move Effect -> B1 Displacement；
- CHARGE -> 保存第一次锁定的目标，倒计时结束再执行。

目标在玩家行动后失效时，本次敌人行动落空，不重新选目标。

敌人攻击使用 EnemyActionDef.range 与 requires_los，并调用 BoardQuery 的 LoS。

## 6. 回合生命周期

玩家回合开始：

- 清玩家 Block；
- 刷新 energy；
- 刷新可选 move_points；
- 补手牌至 hand_size；
- 锁定敌人 Intent。

玩家结束回合：

- 玩家状态 duration 递减；
- 未打出的手牌进入 discard。

敌人行动前清该敌人 Block；敌人行动后该敌人的状态 duration 递减。

## 7. 终局

每个关键结算边界检查：

    玩家全部死亡 -> DEFEAT
    否则敌人全部死亡 -> VICTORY

如果双方同时死亡，DEFEAT 优先。终态 BattleState 不再接受新命令。

battle_result() 将终态转换为 BattleResult；当前最小持久化输出包括玩家剩余 HP。

## 8. 幂等与存档

最近 64 个已接受 command_id 使用 FIFO 保存：

    seen_command_ids
    command_result_snapshots

同一个 command_id 重发时返回第一次结果，不重复执行。读档后仍保持这一行为。

内存结果缓存也限制为同样的 64 条。

SaveCodec 现在完整覆盖：

- BoardState；
- UnitState / StatusState / resources；
- DeckState / BattleCardState / 五个牌区；
- Enemy Intent / 行为步数 / Charge；
- RNG snapshot；
- command 去重状态；
- uid / event_seq / phase / version。

## 9. 自动测试

Phase 3 测试覆盖：

- setup -> ROUND_START -> PLAYER_INPUT；
- 敌人 Intent 锁定；
- preview 零副作用；
- 非法命令零副作用；
- 费用校验；
- PlayCards 正式提交；
- RESOLVING / BUSY 命令锁；
- command_id 幂等与读档后幂等；
- 64 条 FIFO；
- MoveCommand 与行动点；
- BattleSession 转发卡牌 target_validator；
- EndTurn -> 敌人行动 -> 下一轮；
- 玩家胜利、敌人击杀玩家、同时死亡；
- BattleResult；
- 完整 BattleState JSON 往返与深复制；
- 相同 seed + 相同命令得到相同状态 / 事件哈希。
