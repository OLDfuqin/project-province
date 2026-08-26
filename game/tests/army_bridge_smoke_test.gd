extends SceneTree

const Helpers := preload("res://tests/generated_scenario_helpers.gd")


func _army(bridge: Object, army_id: String) -> Dictionary:
    for summary: Dictionary in bridge.get_army_summaries():
        if summary.get("id", "") == army_id:
            return summary
    return {}


func _has_complete_battle_metadata(battle: Dictionary) -> bool:
    var required := [
        "battle_result", "attacker_random_x", "defender_random_x",
        "attacker_initial_manpower", "defender_initial_manpower",
        "attacker_military_level", "defender_military_level",
        "attacker_base_strength", "defender_base_strength",
        "defender_final_strength", "terrain_defense_bonus",
        "attacker_casualties", "defender_casualties",
        "attacker_remaining_manpower", "defender_remaining_manpower",
    ]
    for key: String in required:
        if not battle.has(key):
            return false
    var result := String(battle.get("battle_result", ""))
    if result not in ["defender_victory", "attacker_victory", "mutual_destruction"]:
        return false
    for key: String in ["attacker_random_x", "defender_random_x"]:
        var random_x := float(battle[key])
        if random_x < 0.7 or random_x > 1.4 or \
                not is_equal_approx(random_x * 10.0, round(random_x * 10.0)):
            return false
    for outcome: Dictionary in battle.get("battle_outcomes", []):
        if String(outcome.get("army_id", "")).is_empty() or \
                String(outcome.get("display_name", "")).is_empty():
            return false
    return true


func _find_unopposed_group_target(
        bridge: Object, attacker_country: String, defender_country: String
) -> Dictionary:
    var defending_armies: Dictionary = {}
    for army: Dictionary in bridge.get_army_summaries():
        if army.get("owner_id", "") != defender_country:
            continue
        var province_id := String(army.get("province_id", ""))
        defending_armies[province_id] = int(defending_armies.get(province_id, 0)) + 1

    var candidates: Dictionary = {}
    for province: Dictionary in bridge.get_province_summaries():
        if province.get("owner_id", "") != attacker_country:
            continue
        var origin_id := String(province.get("id", ""))
        var neighbors: Array = province.get("neighbors", []).duplicate()
        neighbors.sort()
        for neighbor: String in neighbors:
            var target := Helpers.province_by_id(bridge, neighbor)
            if target.get("owner_id", "") != defender_country or \
                    target.get("occupied", false) or \
                    int(defending_armies.get(neighbor, 0)) != 0:
                continue
            if not candidates.has(neighbor):
                candidates[neighbor] = []
            candidates[neighbor].append(origin_id)

    var targets: Array = candidates.keys()
    targets.sort()
    for target_id: String in targets:
        var origins: Array = candidates[target_id]
        origins.sort()
        if origins.size() >= 2:
            return {"target": target_id, "origins": [origins[0], origins[1]]}
    return {}


func _initialize() -> void:
    var bridge: Object = ClassDB.instantiate("ProvinceBridge")
    if bridge == null:
        push_error("ProvinceBridge could not be instantiated")
        quit(1)
        return
    var data_directory := ProjectSettings.globalize_path("res://data")
    if not bridge.load_scenario(data_directory, 1000, 1):
        push_error("Scenario load failed: %s" % bridge.get_last_error())
        bridge.free()
        quit(1)
        return
    bridge.set_ai_enabled(false, "auroria")

    var provinces: Array = bridge.get_province_summaries()
    var neutral_armies := 0
    for army: Dictionary in bridge.get_army_summaries():
        if army.get("owner_id", "") == "neutral":
            neutral_armies += 1
    if provinces.size() != 69 or bridge.get_country_summaries().size() != 4 or \
            neutral_armies != 17:
        push_error("Generated scenario bridge snapshot is incomplete: provinces=%d countries=%d neutral_armies=%d total_armies=%d" % [
            provinces.size(), bridge.get_country_summaries().size(), neutral_armies,
            bridge.get_army_summaries().size(),
        ])
        bridge.free()
        quit(1)
        return

    var capital := Helpers.capital_id("auroria")
    var capital_before := Helpers.province_by_id(bridge, capital)
    var rejected: Dictionary = bridge.recruit_army("auroria", capital, 0)
    var first: Dictionary = bridge.recruit_army("auroria", capital, 100)
    var second: Dictionary = bridge.recruit_army("auroria", capital, 125)
    var capital_after := Helpers.province_by_id(bridge, capital)
    if rejected.get("accepted", true) or not first.get("accepted", false) or \
            not second.get("accepted", false) or \
            first.get("display_name", "") != "奥·第1军" or \
            second.get("display_name", "") != "奥·第2军" or \
            capital_after.get("population", -1) != capital_before.get("population", -1) - 225 or \
            capital_after.get("recruitable_population", -1) != \
                capital_before.get("recruitable_population", -1) - 225:
        push_error("Variable recruitment or generated army naming failed")
        bridge.free()
        quit(1)
        return

    var renamed: Dictionary = bridge.rename_army(first["army_id"], 5)
    var duplicate: Dictionary = bridge.rename_army(second["army_id"], 5)
    var merged: Dictionary = bridge.merge_armies(first["army_id"], [second["army_id"]])
    var third: Dictionary = bridge.recruit_army("auroria", capital, 50)
    if not renamed.get("accepted", false) or duplicate.get("accepted", true) or \
            not merged.get("accepted", false) or \
            _army(bridge, first["army_id"]).get("manpower", 0) != 225 or \
            not _army(bridge, second["army_id"]).is_empty() or \
            third.get("formation_number", 0) != 1:
        push_error("Army rename, uniqueness, merge or released numbering failed")
        bridge.free()
        quit(1)
        return

    var turn: Dictionary = bridge.advance_turn(3)
    var moved: Dictionary = bridge.move_army(first["army_id"], "cell_1_2")
    var target: Dictionary = bridge.set_army_advance_target(first["army_id"], "cell_4_4")
    var strategy: Dictionary = bridge.set_army_advance_strategy(first["army_id"], "one_step")
    var preview: Dictionary = bridge.get_auto_advance_path_for_months(
        first["army_id"], "cell_4_4", 1
    )
    if not turn.get("accepted", false) or not moved.get("accepted", false) or \
            moved.get("origin", "") != capital or moved.get("destination", "") != "cell_1_2" or \
            not target.get("accepted", false) or not strategy.get("accepted", false) or \
            not preview.get("accepted", false) or \
            preview.get("preview_path", []).is_empty():
        push_error("Movement or advance-plan bridge contract failed: turn=%s moved=%s target=%s strategy=%s preview=%s" % [
            turn, moved, target, strategy, preview,
        ])
        bridge.free()
        quit(1)
        return

    var battle_bridge: Object = ClassDB.instantiate("ProvinceBridge")
    if not battle_bridge.load_scenario(data_directory, 1000, 1):
        push_error("Battle scenario load failed")
        bridge.free()
        battle_bridge.free()
        quit(1)
        return
    battle_bridge.set_ai_enabled(false, "auroria")
    var border := Helpers.neutral_neighbor(battle_bridge, "auroria")
    if border.size() != 2:
        push_error("Generated map has no Auroria-neutral border")
        bridge.free()
        battle_bridge.free()
        quit(1)
        return
    var neutral_before := Helpers.province_by_id(battle_bridge, border[1])
    var guard_before: Dictionary = {}
    for army: Dictionary in battle_bridge.get_army_summaries():
        if army.get("province_id", "") == border[1] and \
                army.get("owner_id", "") == "neutral":
            guard_before = army
            break
    var neutral_turn: Dictionary = battle_bridge.advance_turn(1)
    var neutral_after_growth := Helpers.province_by_id(battle_bridge, border[1])
    var guard_after: Dictionary = {}
    for army: Dictionary in battle_bridge.get_army_summaries():
        if army.get("province_id", "") == border[1] and \
                army.get("owner_id", "") == "neutral":
            guard_after = army
            break
    var expected_guard_growth := int(neutral_before.get("population", 0)) / 1000
    if not neutral_turn.get("accepted", false) or \
            neutral_after_growth.get("population", -1) != neutral_before.get("population", -1) or \
            guard_after.get("manpower", -1) != guard_before.get("manpower", -1) + expected_guard_growth:
        push_error("Neutral monthly population diversion failed")
        bridge.free()
        battle_bridge.free()
        quit(1)
        return

    var attacker: Dictionary = battle_bridge.recruit_army("auroria", border[0], 100)
    battle_bridge.advance_turn(3)
    var battle: Dictionary = battle_bridge.move_army(attacker["army_id"], border[1])
    var neutral_after_battle := Helpers.province_by_id(battle_bridge, border[1])
    var attacker_won: bool = battle.get("battle_result", "") == "attacker_victory"
    if not battle.get("accepted", false) or not battle.get("battle_occurred", false) or \
            not _has_complete_battle_metadata(battle) or \
            (attacker_won and (
                neutral_after_battle.get("owner_id", "") != "auroria" or \
                neutral_after_battle.get("occupied", true)
            )) or \
            (not attacker_won and neutral_after_battle.get("owner_id", "") != "neutral"):
        push_error("Neutral defensive battle or direct conquest failed")
        bridge.free()
        battle_bridge.free()
        quit(1)
        return

    var grouped_bridge: Object = ClassDB.instantiate("ProvinceBridge")
    if not grouped_bridge.load_scenario(data_directory, 1000, 1):
        push_error("Grouped battle scenario load failed")
        bridge.free()
        battle_bridge.free()
        grouped_bridge.free()
        quit(1)
        return
    grouped_bridge.set_ai_enabled(false, "auroria")
    var grouped_target := _find_unopposed_group_target(
        grouped_bridge, "auroria", "solmere"
    )
    if grouped_target.is_empty():
        push_error("Generated map has no grouped unopposed Auroria-Solmere target")
        bridge.free()
        battle_bridge.free()
        grouped_bridge.free()
        quit(1)
        return
    var grouped_origins: Array = grouped_target.get("origins", [])
    var grouped_attack_a: Dictionary = grouped_bridge.recruit_army(
        "auroria", grouped_origins[0], 100
    )
    var grouped_attack_b: Dictionary = grouped_bridge.recruit_army(
        "auroria", grouped_origins[1], 100
    )
    grouped_bridge.declare_war("auroria", "solmere")
    grouped_bridge.advance_turn(3)
    var queued_a: Dictionary = grouped_bridge.move_army(
        grouped_attack_a["army_id"], grouped_target["target"]
    )
    var queued_b: Dictionary = grouped_bridge.move_army(
        grouped_attack_b["army_id"], grouped_target["target"]
    )
    var grouped_turn: Dictionary = grouped_bridge.advance_turn(1)
    var grouped_action: Dictionary = {}
    for action: Dictionary in grouped_turn.get("turn_actions", []):
        if action.get("type", "") == "battle_resolved" and \
                action.get("province_id", "") == grouped_target["target"]:
            grouped_action = action
            break
    var grouped_after := Helpers.province_by_id(grouped_bridge, grouped_target["target"])
    var grouped_outcomes: Array = grouped_action.get("battle_outcomes", [])
    var grouped_ids: Dictionary = {}
    for outcome: Dictionary in grouped_outcomes:
        grouped_ids[String(outcome.get("army_id", ""))] = true
    if not queued_a.get("accepted", false) or not queued_b.get("accepted", false) or \
            not grouped_turn.get("accepted", false) or grouped_action.is_empty() or \
            grouped_action.get("battle_occurred", true) or \
            not grouped_action.get("province_occupied", false) or \
            grouped_outcomes.size() != 2 or \
            not grouped_ids.has(grouped_attack_a["army_id"]) or \
            not grouped_ids.has(grouped_attack_b["army_id"]) or \
            grouped_after.get("owner_id", "") != "auroria":
        push_error("Unopposed grouped occupation did not expose every attacker outcome")
        bridge.free()
        battle_bridge.free()
        grouped_bridge.free()
        quit(1)
        return

    print("ProvinceBridge army integration smoke test passed")
    bridge.free()
    battle_bridge.free()
    grouped_bridge.free()
    quit(0)
