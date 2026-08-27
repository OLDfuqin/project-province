extends SceneTree


func _technology(bridge: Object, country_id: String) -> Dictionary:
    for technology: Dictionary in bridge.get_technology_summaries():
        if technology.get("country_id", "") == country_id:
            return technology
    return {}


func _country(bridge: Object, country_id: String) -> Dictionary:
    for country: Dictionary in bridge.get_country_summaries():
        if country.get("id", "") == country_id:
            return country
    return {}


func _initialize() -> void:
    var bridge: Object = ClassDB.instantiate("ProvinceBridge")
    var data_directory := ProjectSettings.globalize_path("res://data")
    if bridge == null or not bridge.load_scenario(data_directory, 1000, 1):
        push_error("Scenario load failed")
        quit(1)
        return
    bridge.set_ai_enabled(false, "auroria")

    var cost := int(_technology(bridge, "auroria").get("economy_cost", 0))
    var queued: Dictionary = bridge.research_technology("auroria", "economy")
    var duplicate: Dictionary = bridge.research_technology("auroria", "military")
    var pending: Array = bridge.get_pending_orders("auroria")
    if cost != 5000 or not queued.get("accepted", false) or \
            queued.get("status", "") != "queued" or queued.get("order_type", "") != "research" or \
            queued.get("previous_level", -1) != 0 or queued.get("target_level", -1) != 1 or \
            queued.get("remaining_months", 0) != 2 or queued.get("cost", 0) != cost or \
            duplicate.get("accepted", true) or pending.size() != 1 or \
            _technology(bridge, "auroria").get("economy_level", -1) != 0:
        push_error("Research was not queued with its level and countdown: %s" % queued)
        bridge.free()
        quit(1)
        return

    var first_month: Dictionary = bridge.advance_turn()
    pending = bridge.get_pending_orders("auroria")
    var treasury_before_cancel := int(_country(bridge, "auroria").get("treasury", 0))
    var cancelled: Dictionary = bridge.cancel_order(queued["order_id"])
    if not first_month.get("accepted", false) or pending.size() != 1 or \
            pending[0].get("remaining_months", 0) != 1 or \
            not cancelled.get("accepted", false) or \
            int(_country(bridge, "auroria").get("treasury", 0)) != treasury_before_cancel or \
            _technology(bridge, "auroria").get("economy_level", -1) != 0:
        push_error("Progressed research cancellation was not exposed without a refund")
        bridge.free()
        quit(1)
        return

    queued = bridge.research_technology("auroria", "economy")
    bridge.advance_turn()
    var completed_turn: Dictionary = bridge.advance_turn()
    var completion: Dictionary = {}
    for action: Dictionary in completed_turn.get("turn_actions", []):
        if action.get("type", "") == "technology_researched" and \
                action.get("country_id", "") == "auroria":
            completion = action
            break
    var rejected_months: Dictionary = bridge.advance_turn(2)
    if not queued.get("accepted", false) or completion.is_empty() or \
            completion.get("track", "") != "economy" or \
            completion.get("previous_level", -1) != 0 or completion.get("current_level", -1) != 1 or \
            _technology(bridge, "auroria").get("economy_level", -1) != 1 or \
            rejected_months.get("accepted", true):
        push_error("Delayed research completion or fixed-month validation failed: %s" % completion)
        bridge.free()
        quit(1)
        return

    print("ProvinceBridge technology smoke test passed")
    bridge.free()
    quit(0)
