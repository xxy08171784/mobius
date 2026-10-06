class_name RunNodeTransaction
extends RefCounted
## 在 RunSession 的工作副本上处理非战斗节点；UI 不直接写规则状态。


static func apply(work: RunState, content: Object, action: StringName, data: Dictionary) -> Dictionary:
	var result: Dictionary = {"ok": false, "error_code": &"invalid_action"}
	var complete := false
	match work.flow_phase:
		&"rest":
			if action == &"heal":
				result = RestSystem.apply(work, RestSystem.OPTION_HEAL)
			elif action == &"upgrade":
				result = RestSystem.apply(work, RestSystem.OPTION_UPGRADE, int(data.get("uid", -1)))
			elif action == &"leave":
				result = {"ok": true}
			complete = true
		&"shop":
			var shop := ShopState.from_dict(work.pending_payload.get("shop", {}))
			var definition: ShopDef = content.get_shop(work.pending_content_id)
			match action:
				&"buy":
					result = ShopSystem.buy_card(work, shop, definition, int(data.get("index", -1)))
				&"heal":
					result = ShopSystem.buy_heal(work, shop, definition)
				&"remove":
					result = ShopSystem.buy_remove(work, shop, definition, int(data.get("uid", -1)))
				&"leave":
					result = {"ok": true}
					complete = true
			work.pending_payload["shop"] = shop.to_dict()
		&"event":
			if action == &"event_choice":
				result = EventSystem.resolve(work, content.get_event(work.pending_content_id), int(data.get("index", -1)))
				complete = true
		&"treasure":
			if action == &"leave":
				result = {"ok": true}
				complete = true
	if bool(result.get("ok", false)) and complete:
		work.clear_pending()
		if not work.is_alive():
			work.flow_phase = &"run_over"
			work.outcome = &"defeat"
	return result
