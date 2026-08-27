extends SceneTree

const Helpers := preload("res://tests/generated_scenario_helpers.gd")


func _country(bridge: Object, country_id: String) -> Dictionary:
    for country: Dictionary in bridge.get_country_summaries():
        if country.get("id", "") == country_id:
            return country
    return {}


func _army(bridge: Object, army_id: String) -> Dictionary:
    for army: Dictionary in bridge.get_army_summaries():
        if army.get("id", "") == army_id:
            return army
    return {}


func _player_army_count(bridge: Object) -> int:
    var count := 0
    for army: Dictionary in bridge.get_army_summaries():
        if army.get("owner_id", "") == "auroria":
            count += 1
    return count


func _first_friendly_target(targets: Array) -> Dictionary:
    for target: Dictionary in targets:
        if not target.get("is_attack", true):
            return target
    return {}


func _has_target(targets: Array, province_id: String) -> bool:
    for target: Dictionary in targets:
        if target.get("province_id", "") == province_id:
            return true
    return false


func _at_war(bridge: Object, first: String, second: String) -> bool:
    for relation: Dictionary in bridge.get_diplomatic_relations():
        var countries := [String(relation.get("country_a", "")), String(relation.get("country_b", ""))]
        if first in countries and second in countries:
            return relation.get("status", "peace") == "war"
    return false


func _initialize() -> void:
    var bridge: Object = ClassDB.instantiate("ProvinceBridge")
    var data_directory := ProjectSettings.globalize_path("res://data")
    if bridge == null or not bridge.load_scenario(data_directory, 1000, 1):
        push_error("Scenario load failed")
        quit(1)
        return

    # The bridge initializes AI orders for a new scenario, but a human query may
    # only expose the configured human country's orders.
    if bridge.get_pending_orders("auroria").size() != 0 or \
            bridge.get_pending_orders("solmere").size() != 0:
        push_error("Enemy AI orders leaked through the human bridge query")
        bridge.free()
        quit(1)
        return
    bridge.set_ai_enabled(false, "auroria")

    var capital := Helpers.capital_id("auroria")
    var province_before := Helpers.province_by_id(bridge, capital)
    var treasury_before := int(_country(bridge, "auroria").get("treasury", 0))
    var army_count_before := _player_army_count(bridge)
    var quote: Dictionary = bridge.get_recruitment_order_quote("auroria", capital, 100)
    var rejected: Dictionary = bridge.recruit_army("auroria", capital, 0)
    var queued: Dictionary = bridge.recruit_army("auroria", capital, 100)
    var province_after_queue := Helpers.province_by_id(bridge, capital)
    var pending: Array = bridge.get_pending_orders("auroria")
    if quote.get("cost", 0) != 400 or rejected.get("accepted", true) or \
            not queued.get("accepted", false) or queued.get("status", "") != "queued" or \
            queued.get("order_type", "") != "recruitment" or queued.get("order_id", "") == "" or \
            queued.get("manpower", 0) != 100 or queued.get("remaining_months", 0) != 1 or \
            _player_army_count(bridge) != army_count_before or \
            province_after_queue.get("population", -1) != province_before.get("population", -1) or \
            province_after_queue.get("recruitable_population", -1) != \
                province_before.get("recruitable_population", -1) or \
            pending.size() != 1 or int(_country(bridge, "auroria").get("treasury", 0)) != \
                treasury_before - 400:
        push_error("Recruitment was not exposed as a prepaid delayed order: %s" % queued)
        bridge.free()
        quit(1)
        return

    var cancelled: Dictionary = bridge.cancel_order(queued["order_id"])
    if not cancelled.get("accepted", false) or cancelled.get("event_type", "") != "order_cancelled" or \
            bridge.get_pending_orders("auroria").size() != 0 or \
            int(_country(bridge, "auroria").get("treasury", 0)) != treasury_before:
        push_error("Recruitment cancellation did not refund its prepaid cost")
        bridge.free()
        quit(1)
        return

    queued = bridge.recruit_army("auroria", capital, 100)
    var date_before: Dictionary = bridge.get_current_date()
    var rejected_turn: Dictionary = bridge.advance_turn(3)
    var completion_turn: Dictionary = bridge.advance_turn()
    var recruited_action: Dictionary = {}
    var maintenance_action: Dictionary = {}
    var movement_grant_action: Dictionary = {}
    for action: Dictionary in completion_turn.get("turn_actions", []):
        if action.get("type", "") == "army_recruited" and \
                action.get("country_id", "") == "auroria":
            recruited_action = action
        elif action.get("type", "") == "maintenance_resolved":
            maintenance_action = action
        elif action.get("type", "") == "movement_points_granted":
            movement_grant_action = action
    var army_id := String(recruited_action.get("army_id", ""))
    if rejected_turn.get("accepted", true) or bridge.get_current_date().get("month", 0) != \
            ((int(date_before.get("month", 0)) % 12) + 1) or \
            not completion_turn.get("accepted", false) or recruited_action.is_empty() or \
            recruited_action.get("province_id", "") != capital or \
            recruited_action.get("manpower", 0) != 100 or army_id == "" or \
            recruited_action.get("event_sequence", 0) <= 0 or maintenance_action.is_empty() or \
            movement_grant_action.is_empty() or not completion_turn.has("fiscal_incomes") or \
            not completion_turn.has("maintenance_charges") or \
            not completion_turn.has("population_changes") or \
            not completion_turn.has("movement_grants") or \
            _army(bridge, army_id).is_empty() or bridge.get_pending_orders("auroria").size() != 0:
        push_error("Recruitment order did not complete through the monthly event stream")
        bridge.free()
        quit(1)
        return

    bridge.advance_turn()
    var targets: Array = bridge.get_army_order_targets(army_id)
    var destination := _first_friendly_target(targets)
    if destination.is_empty():
        bridge.advance_turn()
        targets = bridge.get_army_order_targets(army_id)
        destination = _first_friendly_target(targets)
    if destination.is_empty():
        push_error("Bridge exposed no reachable friendly order target")
        bridge.free()
        quit(1)
        return
    var origin := String(_army(bridge, army_id).get("province_id", ""))
    var movement_points_before := float(_army(bridge, army_id).get("movement_points", 0.0))
    var move: Dictionary = bridge.move_army(army_id, destination["province_id"])
    if not move.get("accepted", false) or move.get("order_type", "") != "army_action" or \
            move.get("origin", "") != origin or move.get("destination", "") != destination["province_id"] or \
            move.get("path", []).size() < 2 or move.get("movement_cost", 0.0) <= 0.0 or \
            _army(bridge, army_id).get("province_id", "") != origin:
        push_error("Army action was not queued with its range and cost: %s" % move)
        bridge.free()
        quit(1)
        return
    var move_cancel: Dictionary = bridge.cancel_order(move.get("order_id", ""))
    if not move_cancel.get("accepted", false) or \
            not is_equal_approx(
                float(_army(bridge, army_id).get("movement_points", -1.0)),
                movement_points_before
            ):
        push_error("Army action cancellation did not restore reserved movement")
        bridge.free()
        quit(1)
        return
    move = bridge.move_army(army_id, destination["province_id"])
    var movement_turn: Dictionary = bridge.advance_turn()
    var movement_action: Dictionary = {}
    for action: Dictionary in movement_turn.get("turn_actions", []):
        if action.get("type", "") == "army_moved" and action.get("army_id", "") == army_id:
            movement_action = action
            break
    if _army(bridge, army_id).get("province_id", "") != destination["province_id"] or \
            movement_action.get("origin", "") != origin or \
            movement_action.get("destination", "") != destination["province_id"] or \
            movement_action.get("remaining_points", -99.0) < -1.0:
        push_error("Queued army movement did not resolve next month")
        bridge.free()
        quit(1)
        return

    # Build a deterministic grouped battle setup to verify the monthly battle
    # dictionary retains every attacking army identity.
    var grouped: Object = ClassDB.instantiate("ProvinceBridge")
    if not grouped.load_scenario(data_directory, 1000, 1):
        push_error("Grouped battle scenario load failed")
        bridge.free()
        grouped.free()
        quit(1)
        return
    grouped.set_ai_enabled(false, "auroria")
    var border := Helpers.neutral_neighbor(grouped, "auroria")
    if border.size() != 2:
        push_error("Generated scenario has no Auroria-neutral border")
        bridge.free()
        grouped.free()
        quit(1)
        return
    for _month: int in range(4):
        grouped.advance_turn()
    var first_recruit: Dictionary = grouped.recruit_army("auroria", border[0], 1500)
    grouped.advance_turn()
    var second_quote: Dictionary = grouped.get_recruitment_order_quote(
        "auroria", border[0], 1500
    )
    for _month: int in range(12):
        if second_quote.get("accepted", false):
            break
        grouped.advance_turn()
        second_quote = grouped.get_recruitment_order_quote("auroria", border[0], 1500)
    var second_recruit: Dictionary = grouped.recruit_army("auroria", border[0], 1500)
    grouped.advance_turn()
    var attacker_ids: Array[String] = []
    for summary: Dictionary in grouped.get_army_summaries():
        if summary.get("owner_id", "") == "auroria" and \
                summary.get("province_id", "") == border[0]:
            attacker_ids.append(String(summary.get("id", "")))
    for _month: int in range(3):
        grouped.advance_turn()
    if not first_recruit.get("accepted", false) or not second_recruit.get("accepted", false) or \
            attacker_ids.size() < 2:
        push_error("Grouped battle attackers were not recruited: %s / %s" % [
            first_recruit, second_recruit,
        ])
        bridge.free()
        grouped.free()
        quit(1)
        return
    var first_attack: Dictionary = grouped.move_army(attacker_ids[0], border[1])
    var second_attack: Dictionary = grouped.move_army(attacker_ids[1], border[1])
    var battle_turn: Dictionary = grouped.advance_turn()
    var battle: Dictionary = {}
    for action: Dictionary in battle_turn.get("turn_actions", []):
        if action.get("type", "") == "battle_resolved" and \
                action.get("province_id", "") == border[1]:
            battle = action
            break
    var outcome_ids: Dictionary = {}
    for outcome: Dictionary in battle.get("battle_outcomes", []):
        outcome_ids[String(outcome.get("army_id", ""))] = true
    if not first_attack.get("accepted", false) or not second_attack.get("accepted", false) or \
            battle.is_empty() or not battle.get("battle_occurred", false) or \
            battle.get("attacker_id", "") != "auroria" or battle.get("defender_id", "") != "neutral" or \
            not outcome_ids.has(attacker_ids[0]) or not outcome_ids.has(attacker_ids[1]):
        push_error("Grouped monthly battle report lost stable participants: %s" % battle)
        bridge.free()
        grouped.free()
        quit(1)
        return

    # A range query is a list of queueable destinations, not just geometrically
    # reachable ones. Respect an attack lock already owned by another country.
    var locked: Object = ClassDB.instantiate("ProvinceBridge")
    locked.load_scenario(data_directory, 1000, 1)
    for country_id: String in ["auroria", "caelus", "solmere", "verdantia"]:
        locked.set_ai_enabled(false, country_id)
        for order: Dictionary in locked.get_pending_orders(country_id):
            locked.cancel_order(order.get("order_id", ""))
    locked.set_ai_enabled(false, "auroria")
    var auroria_recruit: Dictionary = locked.recruit_army("auroria", "cell_4_4", 100)
    locked.set_ai_enabled(false, "caelus")
    var caelus_recruit: Dictionary = locked.recruit_army("caelus", "cell_6_4", 100)
    for _month: int in range(4):
        locked.advance_turn()
    var auroria_army_id := ""
    var caelus_army_id := ""
    for summary: Dictionary in locked.get_army_summaries():
        if summary.get("owner_id", "") == "auroria" and \
                summary.get("province_id", "") == "cell_4_4":
            auroria_army_id = String(summary.get("id", ""))
        elif summary.get("owner_id", "") == "caelus" and \
                summary.get("province_id", "") == "cell_6_4":
            caelus_army_id = String(summary.get("id", ""))
    locked.set_ai_enabled(false, "caelus")
    var lock_order: Dictionary = locked.move_army(caelus_army_id, "cell_5_4")
    locked.set_ai_enabled(false, "auroria")
    var player_targets: Array = locked.get_army_order_targets(auroria_army_id)
    if not auroria_recruit.get("accepted", false) or not caelus_recruit.get("accepted", false) or \
            auroria_army_id.is_empty() or caelus_army_id.is_empty() or \
            not lock_order.get("accepted", false) or _has_target(player_targets, "cell_5_4"):
        push_error("Army order range exposed a target locked by another country")
        bridge.free()
        grouped.free()
        locked.free()
        quit(1)
        return

    var diplomacy: Object = ClassDB.instantiate("ProvinceBridge")
    diplomacy.load_scenario(data_directory, 1000, 1)
    diplomacy.set_ai_enabled(false, "auroria")
    var declaration: Dictionary = diplomacy.declare_war("auroria", "solmere")
    var declaration_orders: Array = diplomacy.get_pending_orders("auroria")
    if not declaration.get("accepted", false) or \
            declaration.get("aggressor_id", "") != "auroria" or \
            declaration.get("defender_id", "") != "solmere" or \
            declaration.get("event_sequence", 0) <= 0 or not declaration_orders.is_empty() or \
            not _at_war(diplomacy, "auroria", "solmere"):
        push_error("Existing player diplomacy call no longer returned its stable event dictionary")
        bridge.free()
        grouped.free()
        locked.free()
        diplomacy.free()
        quit(1)
        return

    print("ProvinceBridge army integration smoke test passed")
    bridge.free()
    grouped.free()
    locked.free()
    diplomacy.free()
    quit(0)
