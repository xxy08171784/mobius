# A1 效果模块说明

本文对应 development_split.md 的 Track A / A1。A1 只负责“效果如何结算”，不实现棋盘寻路、UnitState、牌堆和 BattleSession 提交。

## 1. 核心入口

核心接口：

    EffectResolver.resolve(state_in, plan, rng_in) -> Dictionary

成功时返回新的 state_out、rng_out、EventBatch 和已处理触发数量；失败时返回原始 state_in / rng_in 和空事件，因此不会留下半结算状态。

plan 当前包含 context、effects、triggers。单个 effect 最少提供 type_key，通常还会带 target 和 params。

## 2. EffectDef / EffectContext

- EffectDef：抽象 Resource，提供 type_key、params，并直接使用 B1 的 TargetSpec 作为目标合同。
- EffectContext：运行时上下文，包含 source_unit_id、source_card_uid、target、root_trigger_id、depth。
- A2 卡牌系统之后只需要把卡牌转换成 effect plan，不应直接扣 HP 或加 Block。

## 3. 已有 handler

| type_key | 文件 | 当前职责 |
|---|---|---|
| damage | handlers/damage_effect.gd | 合法性 → 伤害值 → Block 吸收 → HP → 事件/死亡触发 |
| block | handlers/block_effect.gd | 给目标增加 Block |
| draw | handlers/draw_effect.gd | 调用 A2 提供的统一抽牌入口 |
| move | handlers/move_effect.gd | 调用 B1 提供的统一移动入口 |
| push | handlers/push_effect.gd | 调用 B1 提供的统一击退入口 |
| apply_status | handlers/apply_status_effect.gd | 创建 StatusState 并放入目标状态容器 |

伤害数值已经接入 B2 的 StatSystem 统一取整/钳制语义，再进入 Block → HP。力量、虚弱、易伤等具体修饰来源还没有冻结，因此目前不擅自新增字段。

draw 继续调用 A2 牌堆入口；move / push 已正式接到 B1 的 BoardState + Displacement，因此寻路、移动预算、墙、单位阻挡、盘边都只由 B1 判定。

## 4. Status / Relic

StatusDef 是只读定义，包含 status_id、tick_timing、priority。

StatusState 保存 instance_id、status_id、stacks、duration、source_unit_id。

RelicDef 是只读定义，不保存运行计数；RelicState 保存 instance_id、relic_id、counters。

B2 的 UnitState.statuses 已收紧为 Dictionary[int, StatusState]，键使用状态实例 instance_id。

## 5. TriggerSystem

触发只允许入队，不允许递归内联执行。

固定排序：

    phase
      ↓
    priority（小者先）
      ↓
    instance_id（小者先）

默认单次命令最多处理 1000 个触发。超过上限，EffectResolver 返回 trigger_overflow，并丢弃整个工作快照。

触发产生的新 effects 仍走同一套 handler 路径。

## 6. A/B 接线点

A1 通过 EffectStateAccess 读取 UnitState，并直接消费 B1 的 TargetSpec / BoardState；空间规则仍由 B1 自己负责。

跨模块效果使用以下调用约定：

    draw_cards(unit_id, count, rng)
    Displacement.move(board, unit_id, destination, move_points)
    Displacement.push(board, unit_id, direction, steps)

旧测试桩仍保留兼容入口，但正式 B1/B2 路径已经有 A/B 集成测试覆盖。

## 7. 当前测试覆盖

- test_effect_models.gd：Status / Relic / Context。
- test_trigger_system.gd：触发排序、处理上限。
- test_effect_resolver.gd：纯结算、State/RNG 不被输入侧修改、Damage → Block → HP、非法目标零副作用、Block、ApplyStatus、Draw/Move/Push 调用契约、触发超限拒绝。
- test_ab_integration.gd：真实 TargetSpec + UnitState + BoardState + Displacement 的跨线对接，并验证预览零副作用。

tests/fixtures/effect_test_state.gd 只用于 A1 单测，不是正式 UnitState / BoardState。
