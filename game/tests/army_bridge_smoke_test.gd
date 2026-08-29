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


func _is_ascii_error(value: Variant) -> bool:
    var message := String(value)
    return not message.is_empty() and \
            message.to_ascii_buffer().get_string_from_ascii() == message


func _read_json(path: String) -> Dictionary:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    file.close()
    return parsed if parsed is Dictionary else {}


func _normalize_json_numbers(value: Variant) -> Variant:
    if value is float and is_equal_approx(value, round(value)):
        return int(value)
    if value is Array:
        var normalized_array: Array = []
        for item: Variant in value:
            normalized_array.append(_normalize_json_numbers(item))
        return normalized_array
    if value is Dictionary:
        var normalized_dictionary: Dictionary = {}
        for key: Variant in value:
            normalized_dictionary[key] = _normalize_json_numbers(value[key])
        return normalized_dictionary
    return value


func _write_json(path: String, document: Dictionary) -> bool:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(_normalize_json_numbers(document)))
    file.close()
    return true


func _clear_initial_orders(bridge: Object) -> void:
    for country_id: String in ["auroria", "caelus", "solmere", "verdantia"]:
        bridge.set_ai_enabled(false, country_id)
        for order: Dictionary in bridge.get_pending_orders(country_id):
            bridge.cancel_order(order.get("order_id", ""))


func _legacy_army_management_complete(data_directory: String) -> bool:
    var legacy: Object = ClassDB.instantiate("ProvinceBridge")
    if legacy == null or not legacy.load_scenario(data_directory, 1000, 1):
        return false
    _clear_initial_orders(legacy)
    legacy.set_ai_enabled(false, "auroria")
    var capital := Helpers.capital_id("auroria")
    var first_order: Dictionary = legacy.recruit_army("auroria", capital, 1500)
    var first_turn: Dictionary = legacy.advance_turn()
    var first_id := ""
    for action: Dictionary in first_turn.get("turn_actions", []):
        if action.get("type", "") == "army_recruited" and \
                action.get("order_id", "") == first_order.get("order_id", "missing"):
            first_id = String(action.get("army_id", ""))
    var second_quote: Dictionary = legacy.get_recruitment_order_quote("auroria", capital, 1500)
    for _month: int in range(12):
        if second_quote.get("accepted", false):
            break
        legacy.advance_turn()
        second_quote = legacy.get_recruitment_order_quote("auroria", capital, 1500)
    var second_order: Dictionary = legacy.recruit_army("auroria", capital, 1500)
    var second_turn: Dictionary = legacy.advance_turn()
    var second_id := ""
    for action: Dictionary in second_turn.get("turn_actions", []):
        if action.get("type", "") == "army_recruited" and \
                action.get("order_id", "") == second_order.get("order_id", "missing"):
            second_id = String(action.get("army_id", ""))
    var renamed: Dictionary = legacy.rename_army(first_id, 5)
    var duplicate: Dictionary = legacy.rename_army(second_id, 5)
    var merged: Dictionary = legacy.merge_armies(first_id, [second_id])
    var target_id := "cell_4_4"
    var target: Dictionary = legacy.set_army_advance_target(first_id, target_id)
    var strategy: Dictionary = legacy.set_army_advance_strategy(first_id, "one_step")
    var disabled: Dictionary = legacy.set_army_advance_enabled(first_id, false)
    var enabled: Dictionary = legacy.set_army_advance_enabled(first_id, true)
    var preview: Dictionary = legacy.get_auto_advance_path_for_months(first_id, target_id, 1)
    var cleared: Dictionary = legacy.clear_army_advance_target(first_id)
    var summary := _army(legacy, first_id)
    var complete: bool = first_order.get("accepted", false) and \
            second_order.get("accepted", false) and not first_id.is_empty() and \
            not second_id.is_empty() and renamed.get("accepted", false) and \
            renamed.get("formation_number", 0) == 5 and \
            duplicate.get("accepted", true) == false and merged.get("accepted", false) and \
            merged.get("primary_army_id", "") == first_id and \
            merged.get("merged_army_ids", []).has(second_id) and \
            summary.get("manpower", 0) == 3000 and _army(legacy, second_id).is_empty() and \
            target.get("accepted", false) and strategy.get("accepted", false) and \
            disabled.get("accepted", false) and enabled.get("accepted", false) and \
            preview.get("accepted", false) and not preview.get("preview_path", []).is_empty() and \
            cleared.get("accepted", false)
    legacy.free()
    return complete


func _unguarded_occupation_complete(data_directory: String) -> bool:
    var occupation: Object = ClassDB.instantiate("ProvinceBridge")
    if occupation == null or not occupation.load_scenario(data_directory, 1000, 1):
        return false
    _clear_initial_orders(occupation)
    occupation.set_ai_enabled(false, "auroria")
    var border := Helpers.neutral_neighbor(occupation, "auroria")
    if border.size() != 2:
        occupation.free()
        return false
    var first_recruit: Dictionary = occupation.recruit_army("auroria", border[0], 100)
    var recruit_turn: Dictionary = occupation.advance_turn()
    var army_id := ""
    for action: Dictionary in recruit_turn.get("turn_actions", []):
        if action.get("type", "") == "army_recruited" and \
                action.get("order_id", "") == first_recruit.get("order_id", "missing"):
            army_id = String(action.get("army_id", ""))
    for _month: int in range(3):
        occupation.advance_turn()
    var save_path := ProjectSettings.globalize_path(
        "res://../build/task8-unguarded-occupation.json"
    )
    var saved: Dictionary = occupation.save_game(save_path)
    if army_id.is_empty() or not saved.get("accepted", false):
        print("UNGUARDED_DIAGNOSTIC army=%s recruit=%s saved=%s" % [army_id, first_recruit, saved])
        occupation.free()
        return false
    var document := _read_json(save_path)
    var surviving_armies: Array = []
    for army_document: Dictionary in document.get("armies", []):
        if army_document.get("province_id", "") != border[1]:
            surviving_armies.append(army_document)
    document["armies"] = surviving_armies
    for province_document: Dictionary in document.get("provinces", []):
        if province_document.get("id", "") == border[1]:
            province_document["owner_id"] = "solmere"
            province_document["population"] = 1
            province_document["recruitable_population"] = 0
    var wrote := _write_json(save_path, document)
    var loaded: Dictionary = occupation.load_game(save_path) if wrote else {"accepted": false}
    if not wrote or not loaded.get("accepted", false):
        print("UNGUARDED_DIAGNOSTIC mutation load=%s armies_before=%d armies_after=%d" % [
            loaded, document.get("armies", []).size() + 1, document.get("armies", []).size(),
        ])
        DirAccess.remove_absolute(save_path)
        occupation.free()
        return false
    var declaration: Dictionary = occupation.declare_war("auroria", "solmere")
    var first_attack: Dictionary = occupation.move_army(army_id, border[1])
    var battle_turn: Dictionary = occupation.advance_turn()
    var battle: Dictionary = {}
    for action: Dictionary in battle_turn.get("turn_actions", []):
        if action.get("type", "") == "battle_resolved" and \
                action.get("province_id", "") == border[1]:
            battle = action
            break
    var complete: bool = declaration.get("accepted", false) and \
            first_attack.get("accepted", false) and \
            not battle.get("battle_occurred", true) and \
            battle.get("province_occupied", false) and \
            battle.get("order_ids", []).has(first_attack.get("order_id", "missing-a")) and \
            Helpers.province_by_id(occupation, border[1]).get("owner_id", "") == "auroria"
    if not complete:
        print("UNGUARDED_DIAGNOSTIC declaration=%s attack=%s battle=%s province=%s" % [
            declaration, first_attack, battle, Helpers.province_by_id(occupation, border[1]),
        ])
    DirAccess.remove_absolute(save_path)
    occupation.free()
    return complete


func _monthly_action_refund_dictionary_complete(data_directory: String) -> bool:
    var refund_bridge: Object = ClassDB.instantiate("ProvinceBridge")
    if refund_bridge == null or not refund_bridge.load_scenario(data_directory, 1000, 1):
        return false
    _clear_initial_orders(refund_bridge)
    refund_bridge.set_ai_enabled(false, "auroria")
    var capital := Helpers.capital_id("auroria")
    var recruited: Dictionary = refund_bridge.recruit_army("auroria", capital, 100)
    var recruit_turn: Dictionary = refund_bridge.advance_turn()
    var army_id := ""
    for action: Dictionary in recruit_turn.get("turn_actions", []):
        if action.get("type", "") == "army_recruited" and \
                action.get("order_id", "") == recruited.get("order_id", "missing"):
            army_id = String(action.get("army_id", ""))
    for _month: int in range(3):
        refund_bridge.advance_turn()
    var target := _first_friendly_target(refund_bridge.get_army_order_targets(army_id))
    var queued: Dictionary = refund_bridge.move_army(army_id, target.get("province_id", ""))
    var save_path := ProjectSettings.globalize_path(
        "res://../build/task8-action-refund.json"
    )
    if army_id.is_empty() or target.is_empty() or not queued.get("accepted", false) or \
            not refund_bridge.save_game(save_path).get("accepted", false):
        refund_bridge.free()
        return false
    var document := _read_json(save_path)
    var destination := String(target.get("province_id", ""))
    var occupations: Array = []
    for occupation_document: Dictionary in document.get("occupations", []):
        if occupation_document.get("province_id", "") != destination:
            occupations.append(occupation_document)
    occupations.append({"province_id": destination, "controller_id": "solmere"})
    document["occupations"] = occupations
    if not _write_json(save_path, document) or \
            not refund_bridge.load_game(save_path).get("accepted", false):
        DirAccess.remove_absolute(save_path)
        refund_bridge.free()
        return false
    var turn: Dictionary = refund_bridge.advance_turn()
    var refund: Dictionary = {}
    for action: Dictionary in turn.get("turn_actions", []):
        if action.get("type", "") == "order_cancelled" and \
                action.get("order_id", "") == queued.get("order_id", "missing"):
            refund = action
            break
    var complete: bool = turn.get("accepted", false) and \
            refund.get("country_id", "") == "auroria" and \
            refund.get("army_id", "") == army_id and refund.get("refunded_cost", -1) == 0 and \
            refund.get("refunded_movement_half", -1) == queued.get("reserved_movement_half", -2) and \
            not String(refund.get("reason", "")).is_empty() and \
            refund.get("status", "") == "cancelled"
    DirAccess.remove_absolute(save_path)
    refund_bridge.free()
    return complete


func _converted_attack_dictionary_complete(data_directory: String) -> bool:
    var converted_bridge: Object = ClassDB.instantiate("ProvinceBridge")
    if converted_bridge == null or not converted_bridge.load_scenario(data_directory, 1000, 1):
        return false
    _clear_initial_orders(converted_bridge)
    converted_bridge.set_ai_enabled(false, "auroria")
    var border := Helpers.neutral_neighbor(converted_bridge, "auroria")
    if border.size() != 2:
        converted_bridge.free()
        return false
    var recruited: Dictionary = converted_bridge.recruit_army("auroria", border[0], 100)
    var recruit_turn: Dictionary = converted_bridge.advance_turn()
    var army_id := ""
    for action: Dictionary in recruit_turn.get("turn_actions", []):
        if action.get("type", "") == "army_recruited" and \
                action.get("order_id", "") == recruited.get("order_id", "missing"):
            army_id = String(action.get("army_id", ""))
    for _month: int in range(3):
        converted_bridge.advance_turn()
    var queued: Dictionary = converted_bridge.move_army(army_id, border[1])
    var save_path := ProjectSettings.globalize_path(
        "res://../build/task8-converted-attack.json"
    )
    if army_id.is_empty() or not queued.get("accepted", false) or \
            not queued.get("is_attack", false) or \
            not converted_bridge.save_game(save_path).get("accepted", false):
        converted_bridge.free()
        return false
    var document := _read_json(save_path)
    var occupations: Array = []
    for occupation_document: Dictionary in document.get("occupations", []):
        if occupation_document.get("province_id", "") != border[1]:
            occupations.append(occupation_document)
    occupations.append({"province_id": border[1], "controller_id": "auroria"})
    document["occupations"] = occupations
    if not _write_json(save_path, document) or \
            not converted_bridge.load_game(save_path).get("accepted", false):
        DirAccess.remove_absolute(save_path)
        converted_bridge.free()
        return false
    var turn: Dictionary = converted_bridge.advance_turn()
    var moved: Dictionary = {}
    for action: Dictionary in turn.get("turn_actions", []):
        if action.get("type", "") == "army_moved" and \
                action.get("order_id", "") == queued.get("order_id", "missing"):
            moved = action
            break
    var expected_cost := (
        int(queued.get("reserved_movement_half", 0)) - 4
    ) / 2.0
    var complete: bool = moved.get("converted_from_attack", false) and \
            moved.get("army_id", "") == army_id and moved.get("origin", "") == border[0] and \
            moved.get("destination", "") == border[1] and \
            is_equal_approx(float(moved.get("movement_cost", -1.0)), expected_cost)
    DirAccess.remove_absolute(save_path)
    converted_bridge.free()
    return complete


func _automatic_merge_dictionary_complete(data_directory: String) -> bool:
    var merge_bridge: Object = ClassDB.instantiate("ProvinceBridge")
    if merge_bridge == null or not merge_bridge.load_scenario(data_directory, 1000, 1):
        return false
    merge_bridge.set_ai_enabled(false, "auroria")
    var capital := Helpers.capital_id("auroria")
    var first_order: Dictionary = merge_bridge.recruit_army("auroria", capital, 100)
    var first_turn: Dictionary = merge_bridge.advance_turn()
    var second_order: Dictionary = merge_bridge.recruit_army("auroria", capital, 100)
    var second_turn: Dictionary = merge_bridge.advance_turn()
    var first_army_id := ""
    var second_army_id := ""
    for action: Dictionary in first_turn.get("turn_actions", []):
        if action.get("type", "") == "army_recruited" and \
                action.get("order_id", "") == first_order.get("order_id", "missing"):
            first_army_id = String(action.get("army_id", ""))
    for action: Dictionary in second_turn.get("turn_actions", []):
        if action.get("type", "") == "army_recruited" and \
                action.get("order_id", "") == second_order.get("order_id", "missing"):
            second_army_id = String(action.get("army_id", ""))
    var merge_action: Dictionary = {}
    for action: Dictionary in second_turn.get("turn_actions", []):
        if action.get("type", "") == "armies_merged" and action.get("automatic", false):
            merge_action = action
            break
    var complete: bool = first_order.get("accepted", false) and \
            second_order.get("accepted", false) and not first_army_id.is_empty() and \
            not second_army_id.is_empty() and merge_action.get("country_id", "") == "auroria" and \
            merge_action.get("province_id", "") == capital and \
            merge_action.get("primary_army_id", "") == first_army_id and \
            merge_action.get("merged_army_ids", []).has(second_army_id) and \
            merge_action.get("previous_manpower", 0) == 100 and \
            merge_action.get("current_manpower", 0) == 200 and \
            merge_action.get("formation_number", 0) > 0 and \
            not String(merge_action.get("display_name", "")).is_empty() and \
            merge_action.has("movement_points")
    merge_bridge.free()
    return complete


func _initialize() -> void:
    var bridge: Object = ClassDB.instantiate("ProvinceBridge")
    var data_directory := ProjectSettings.globalize_path("res://data")
    if bridge == null or not bridge.load_scenario(data_directory, 1000, 1):
        push_error("Scenario load failed")
        quit(1)
        return

    var capital := Helpers.capital_id("auroria")
    var boundary_errors: Dictionary = {}
    for _attempt: int in range(8):
        if not bridge.get_pending_orders("").is_empty() or \
                not bridge.get_army_order_targets("").is_empty():
            push_error("Invalid stable IDs produced non-empty order queries")
            bridge.free()
            quit(1)
            return
        var invalid_results := {
            "cancel": bridge.cancel_order(""),
            "recruitment_quote": bridge.get_recruitment_order_quote("", "", 100),
            "recruitment": bridge.recruit_army("", "", 100),
            "move": bridge.move_army("", ""),
            "rename": bridge.rename_army("", 1),
            "merge": bridge.merge_armies("", []),
            "auto_advance": bridge.auto_advance_army(""),
            "auto_advance_to": bridge.auto_advance_army_to("", capital),
            "preview": bridge.get_auto_advance_path("", capital),
            "preview_months": bridge.get_auto_advance_path_for_months("", capital, 1),
            "set_target": bridge.set_army_advance_target("", capital),
            "clear_target": bridge.clear_army_advance_target(""),
            "set_enabled": bridge.set_army_advance_enabled("", true),
            "set_strategy": bridge.set_army_advance_strategy("", "max"),
        }
        for api_name: String in invalid_results:
            var invalid: Dictionary = invalid_results[api_name]
            var error := String(invalid.get("error", ""))
            if invalid.get("accepted", true) or not _is_ascii_error(error) or \
                    (boundary_errors.has(api_name) and boundary_errors[api_name] != error):
                push_error("Invalid-ID boundary was not stable for %s: %s" % [api_name, invalid])
                bridge.free()
                quit(1)
                return
            boundary_errors[api_name] = error

    # The bridge initializes AI orders for a new scenario, but a human query may
    # only expose the configured human country's orders.
    if bridge.get_pending_orders("auroria").size() != 0 or \
            bridge.get_pending_orders("solmere").size() != 0:
        push_error("Enemy AI orders leaked through the human bridge query")
        bridge.free()
        quit(1)
        return
    bridge.set_ai_enabled(false, "auroria")

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
            cancelled.get("country_id", "") != "auroria" or \
            cancelled.get("army_id", "not-empty") != "" or \
            cancelled.get("refunded_cost", -1) != 400 or \
            cancelled.get("refunded_movement_half", -1) != 0 or \
            String(cancelled.get("reason", "")).is_empty() or \
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
    var auroria_maintenance := -1
    for charge: Dictionary in completion_turn.get("maintenance_charges", []):
        if charge.get("country_id", "") == "auroria":
            auroria_maintenance = int(charge.get("amount", -1))
    var auroria_summary := _country(bridge, "auroria")
    var fiscal_sequence := int(completion_turn.get("fiscal_income_event_sequence", -1))
    var maintenance_sequence := int(maintenance_action.get("event_sequence", -1))
    var population_sequence := int(completion_turn.get("population_event_sequence", -1))
    var movement_sequence := int(movement_grant_action.get("event_sequence", -1))
    var recruitment_sequence := int(recruited_action.get("event_sequence", -1))
    if rejected_turn.get("accepted", true) or bridge.get_current_date().get("month", 0) != \
            ((int(date_before.get("month", 0)) % 12) + 1) or \
            not completion_turn.get("accepted", false) or recruited_action.is_empty() or \
            recruited_action.get("order_id", "") != queued.get("order_id", "missing") or \
            recruited_action.get("province_id", "") != capital or \
            recruited_action.get("manpower", 0) != 100 or army_id == "" or \
            recruited_action.get("event_sequence", 0) <= 0 or maintenance_action.is_empty() or \
            movement_grant_action.is_empty() or not completion_turn.has("fiscal_incomes") or \
            not completion_turn.has("maintenance_charges") or \
            not completion_turn.has("population_changes") or \
            not completion_turn.has("movement_grants") or \
            auroria_maintenance < 0 or \
            not auroria_summary.get("has_last_maintenance_charge", false) or \
            int(auroria_summary.get("last_maintenance_charge", -1)) != \
                    auroria_maintenance or \
            not (fiscal_sequence < maintenance_sequence and \
                    maintenance_sequence < population_sequence and \
                    population_sequence < movement_sequence and \
                    movement_sequence < recruitment_sequence) or \
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
            move_cancel.get("country_id", "") != "auroria" or \
            move_cancel.get("army_id", "") != army_id or \
            move_cancel.get("refunded_cost", -1) != 0 or \
            move_cancel.get("refunded_movement_half", 0) <= 0 or \
            String(move_cancel.get("reason", "")).is_empty() or \
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
            movement_action.get("order_id", "") != move.get("order_id", "missing") or \
            movement_action.get("converted_from_attack", true) or \
            movement_action.get("origin", "") != origin or \
            movement_action.get("destination", "") != destination["province_id"] or \
            movement_action.get("remaining_points", -99.0) < -1.0:
        push_error("Queued army movement did not resolve next month")
        bridge.free()
        quit(1)
        return

    if not _automatic_merge_dictionary_complete(data_directory):
        push_error("Automatic army consolidation lost its stable survivor dictionary")
        bridge.free()
        quit(1)
        return

    if not _legacy_army_management_complete(data_directory):
        push_error("Legacy army rename/merge/advance-target/preview contracts regressed")
        bridge.free()
        quit(1)
        return

    if not _unguarded_occupation_complete(data_directory):
        push_error("Monthly grouped attack no longer reports unguarded occupation")
        bridge.free()
        quit(1)
        return

    if not _monthly_action_refund_dictionary_complete(data_directory):
        push_error("Monthly invalidated army action lost refund metadata")
        bridge.free()
        quit(1)
        return

    if not _converted_attack_dictionary_complete(data_directory):
        push_error("Converted attack movement lost its order correlation dictionary")
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
    _clear_initial_orders(grouped)
    grouped.set_ai_enabled(false, "auroria")
    var border := Helpers.neutral_neighbor(grouped, "auroria")
    if border.size() != 2:
        push_error("Generated scenario has no Auroria-neutral border")
        bridge.free()
        grouped.free()
        quit(1)
        return
    var first_quote: Dictionary = grouped.get_recruitment_order_quote(
        "auroria", border[0], 1500
    )
    for _month: int in range(24):
        if first_quote.get("accepted", false):
            break
        grouped.advance_turn()
        first_quote = grouped.get_recruitment_order_quote("auroria", border[0], 1500)
    var first_recruit: Dictionary = grouped.recruit_army("auroria", border[0], 1500)
    grouped.advance_turn()
    var second_quote: Dictionary = grouped.get_recruitment_order_quote(
        "auroria", border[0], 1500
    )
    for _month: int in range(24):
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
            not battle.get("order_ids", []).has(first_attack.get("order_id", "missing")) or \
            not battle.get("order_ids", []).has(second_attack.get("order_id", "missing")) or \
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
