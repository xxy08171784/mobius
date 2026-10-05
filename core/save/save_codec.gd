class_name SaveCodec
extends RefCounted
## 运行状态 <-> Dictionary 的唯一编解码路径。
## 约定（architecture_review.md H2）：clone = encode(state) -> decode()，
## 避免维护第二套手写 clone()；新字段漏进 codec 会被往返测试立刻抓到。
## 需手动编码 Vector2i；64 位整数存为十进制字符串。

func encode_state(_state: RefCounted) -> Dictionary:
	# TODO
	return {}


func decode_state(_data: Dictionary) -> RefCounted:
	# TODO
	return null
