extends SceneTree

const Helpers := preload("res://tests/generated_scenario_helpers.gd")


func _country(bridge: Object, country_id: String) -> Dictionary:
    for country: Dictionary in bridge.get_country_summaries():
        if country.get("id", "") == country_id:
            return country
    return {}


func _eligible_pair(bridge: Object, country_id: String) -> Array[String]:
    for province: Dictionary in Helpers.owned_provinces(bridge, country_id):
        var first_id := String(province.get("id", ""))
        var neighbors: Array = province.get("neighbors", []).duplicate()
        neighbors.sort()
        for neighbor: String in neighbors:
            var second := Helpers.province_by_id(bridge, neighbor)
            if first_id < neighbor and second.get("owner_id", "") == country_id and \
                    bridge.get_road_order_quote(
                        country_id, first_id, neighbor
                    ).get("accepted", false):
                return [first_id, neighbor]
    return []


func _has_road(bridge: Object, first: String, second: String) -> bool:
    for road: Dictionary in bridge.get_road_summaries():
        var endpoints := [String(road.get("province_a", "")), String(road.get("province_b", ""))]
        endpoints.sort()
        var expected := [first, second]
        expected.sort()
        if endpoints == expected and road.get("level", "") == "paved":
            return true
    return false


func _initialize() -> void:
    var bridge: Object = ClassDB.instantiate("ProvinceBridge")
    var data_directory := ProjectSettings.globalize_path("res://data")
    if bridge == null or not bridge.load_scenario(data_directory, 1000, 1):
        push_error("Scenario load failed")
        quit(1)
        return

    var invalid_errors: Dictionary = {}
    for _attempt: int in range(8):
        var invalid_results := {
            "quote": bridge.get_road_order_quote("", "", ""),
            "build": bridge.build_road("", "", ""),
        }
        for api_name: String in invalid_results:
            var invalid: Dictionary = invalid_results[api_name]
            var error := String(invalid.get("error", ""))
            if invalid.get("accepted", true) or error.is_empty() or \
                    error.to_ascii_buffer().get_string_from_ascii() != error or \
                    (invalid_errors.has(api_name) and invalid_errors[api_name] != error):
                push_error("Invalid road boundary was unstable for %s: %s" % [api_name, invalid])
                bridge.free()
                quit(1)
                return
            invalid_errors[api_name] = error
    bridge.set_ai_enabled(false, "auroria")

    var road_research: Dictionary = {}
    var pair: Array[String] = []
    for _level: int in range(3):
        road_research = bridge.research_technology("auroria", "roads")
        if not road_research.get("accepted", false):
            break
        for _month: int in range(int(road_research.get("remaining_months", 0))):
            bridge.advance_turn()
        pair = _eligible_pair(bridge, "auroria")
        if pair.size() == 2:
            break
    if pair.size() != 2:
        push_error("Could not prepare a road pair within the supported technology levels")
        bridge.free()
        quit(1)
        return

    var quote: Dictionary = bridge.get_road_order_quote("auroria", pair[0], pair[1])
    var treasury_before := int(_country(bridge, "auroria").get("treasury", 0))
    var queued: Dictionary = bridge.build_road("auroria", pair[0], pair[1])
    var pending: Array = bridge.get_pending_orders("auroria")
    if not quote.get("accepted", false) or int(quote.get("cost", 0)) <= 0 or \
            not queued.get("accepted", false) or queued.get("status", "") != "queued" or \
            queued.get("event_type", "") != "order_created" or \
            queued.get("order_type", "") != "road_construction" or \
            queued.get("order_id", "") == "" or \
            queued.get("cost", -1) != quote.get("cost", -2) or \
            _has_road(bridge, pair[0], pair[1]) or pending.size() != 1 or \
            pending[0].get("remaining_months", 0) != 1 or \
            int(_country(bridge, "auroria").get("treasury", 0)) != \
                treasury_before - int(quote.get("cost", 0)):
        push_error("Road order was not exposed as a prepaid delayed project: %s" % queued)
        bridge.free()
        quit(1)
        return

    var cancelled: Dictionary = bridge.cancel_order(queued["order_id"])
    if not cancelled.get("accepted", false) or cancelled.get("status", "") != "cancelled" or \
            bridge.get_pending_orders("auroria").size() != 0 or \
            int(_country(bridge, "auroria").get("treasury", 0)) != treasury_before:
        push_error("Road cancellation did not expose and refund the order")
        bridge.free()
        quit(1)
        return

    queued = bridge.build_road("auroria", pair[0], pair[1])
    var turn: Dictionary = bridge.advance_turn()
    var completion: Dictionary = {}
    for action: Dictionary in turn.get("turn_actions", []):
        if action.get("type", "") == "road_built" and \
                action.get("province_a", "") in pair and action.get("province_b", "") in pair:
            completion = action
            break
    if not queued.get("accepted", false) or not turn.get("accepted", false) or \
            not _has_road(bridge, pair[0], pair[1]) or \
            bridge.get_pending_orders("auroria").size() != 0 or completion.is_empty() or \
            completion.get("order_id", "") != queued.get("order_id", "missing") or \
            completion.get("cost", -1) != quote.get("cost", -2) or \
            completion.get("level", "") != "paved":
        push_error("Road order did not complete with a stable monthly event: %s" % completion)
        bridge.free()
        quit(1)
        return

    print("ProvinceBridge road integration smoke test passed")
    bridge.free()
    quit(0)
