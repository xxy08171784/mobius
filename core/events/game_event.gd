@abstract
class_name GameEvent
extends RefCounted
## 规则层产出的不可变结算事件，供表现层按序投影。
## 事件只描述"发生了什么"，不含表现对象（NodePath/Callable 等）。

## 事件批内的稳定顺序号（来自 BattleState.next_event_seq，随存档持久化）。
var seq: int = 0

var type_key: StringName = &""
var source_id: int = -1
var target_id: int = -1

## before/after 变化值，供表现层播放中间动画（例如位移动画的起止格）。
var before: Dictionary = {}
var after: Dictionary = {}
