extends SceneTree


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

    var result: Dictionary = bridge.recruit_army("auroria", "northreach", 1000)
    if not result.get("accepted", false) or result.get("cost", 0) != 1000:
        push_error("Bridge recruitment failed: %s" % result.get("error", "unknown"))
        bridge.free()
        quit(1)
        return

    var armies: Array = bridge.get_army_summaries()
    var northreach: Dictionary = {}
    var auroria: Dictionary = {}
    for province: Dictionary in bridge.get_province_summaries():
        if province["id"] == "northreach":
            northreach = province
    for country: Dictionary in bridge.get_country_summaries():
        if country["id"] == "auroria":
            auroria = country
    if armies.size() != 1 or armies[0]["manpower"] != 1000 or \
            northreach.get("soldier_population", -1) != 1000 or \
            auroria.get("treasury", -1) != 9000:
        push_error("Recruitment was not reflected in bridge snapshots")
        bridge.free()
        quit(1)
        return

    var road_result: Dictionary = bridge.build_road(
        "auroria", "northreach", "westmark"
    )
    var turn_result: Dictionary = bridge.advance_turn(1)
    var move_result: Dictionary = bridge.move_army(
        result["army_id"], "westmark"
    )
    armies = bridge.get_army_summaries()
    if not road_result.get("accepted", false) or \
            not turn_result.get("accepted", false) or \
            not move_result.get("accepted", false) or \
            move_result.get("movement_cost", 0) != 1 or \
            armies[0]["province_id"] != "westmark" or \
            armies[0]["movement_points"] != 1:
        push_error("Road movement was not reflected in bridge snapshots")
        bridge.free()
        quit(1)
        return

    var defender: Dictionary = bridge.recruit_army("verdantia", "greenvale", 500)
    var peace_entry: Dictionary = bridge.move_army(result["army_id"], "greenvale")
    var war_result: Dictionary = bridge.declare_war("auroria", "verdantia")
    bridge.advance_turn(1)
    var war_entry: Dictionary = bridge.auto_advance_army(result["army_id"])
    var relations: Array = bridge.get_diplomatic_relations()
    if peace_entry.get("accepted", false) or \
            not defender.get("accepted", false) or \
            not war_result.get("accepted", false) or \
            not war_entry.get("accepted", false) or \
            war_entry.get("auto_destination", "") != "greenvale" or \
            not war_entry.get("battle_occurred", false) or \
            not war_entry.get("attacker_won", false) or \
            not war_entry.get("province_occupied", false) or \
            relations.size() != 1 or relations[0].get("status", "") != "war":
        push_error("War declaration was not reflected in bridge state")
        bridge.free()
        quit(1)
        return

    var occupied_greenvale: Dictionary = {}
    var defender_after: Dictionary = {}
    for province: Dictionary in bridge.get_province_summaries():
        if province["id"] == "greenvale":
            occupied_greenvale = province
    for army: Dictionary in bridge.get_army_summaries():
        if army["id"] == defender["army_id"]:
            defender_after = army
    if occupied_greenvale.get("owner_id", "") != "auroria" or \
            occupied_greenvale.get("legal_owner_id", "") != "verdantia" or \
            not occupied_greenvale.get("occupied", false) or \
            defender_after.get("province_id", "") != "sunmeadow":
        push_error("Battle occupation or defender retreat was not reflected")
        bridge.free()
        quit(1)
        return
    if war_entry.get("battle_outcomes", []).is_empty():
        push_error("Battle outcome details were not reflected in bridge state")
        bridge.free()
        quit(1)
        return

    var peace_result: Dictionary = bridge.make_peace("auroria", "verdantia", false)
    relations = bridge.get_diplomatic_relations()
    var restored_greenvale: Dictionary = {}
    var attacker_after_peace: Dictionary = {}
    for province: Dictionary in bridge.get_province_summaries():
        if province["id"] == "greenvale":
            restored_greenvale = province
    for army: Dictionary in bridge.get_army_summaries():
        if army["id"] == result["army_id"]:
            attacker_after_peace = army
    if not peace_result.get("accepted", false) or \
            peace_result.get("provinces", []).size() != 1 or \
            peace_result.get("armies", []).size() != 1 or \
            not relations.is_empty() or \
            restored_greenvale.get("owner_id", "") != "verdantia" or \
            restored_greenvale.get("occupied", true) or \
            attacker_after_peace.get("province_id", "") != "northreach":
        push_error("Peace settlement was not reflected in bridge state")
        bridge.free()
        quit(1)
        return

    if not bridge.load_scenario(data_directory, 1000, 1):
        push_error("Scenario reload failed: %s" % bridge.get_last_error())
        bridge.free()
        quit(1)
        return
    bridge.set_ai_enabled(false, "auroria")
    var deep_army: Dictionary = bridge.recruit_army("auroria", "northreach", 1000)
    bridge.build_road("auroria", "northreach", "westmark")
    bridge.declare_war("auroria", "verdantia")
    bridge.advance_turn(3)
    var set_target: Dictionary = bridge.set_army_advance_target(
        deep_army["army_id"], "greenvale"
    )
    var planned_army: Dictionary = {}
    for army_summary: Dictionary in bridge.get_army_summaries():
        if army_summary["id"] == deep_army["army_id"]:
            planned_army = army_summary
    if not set_target.get("accepted", false) or \
            planned_army.get("advance_target_id", "") != "greenvale":
        push_error("Army advance target was not stored in bridge state")
        bridge.free()
        quit(1)
        return
    var path_preview: Dictionary = bridge.get_auto_advance_path(
        deep_army["army_id"], "greenvale"
    )
    if not path_preview.get("accepted", false) or \
            path_preview.get("path", []) != ["northreach", "westmark", "greenvale"] or \
            path_preview.get("step_count", 0) != 2 or \
            path_preview.get("first_step_cost", 0) != 1 or \
            path_preview.get("total_movement_cost", 0) != 3:
        push_error("Auto advance path preview was not reflected in bridge state")
        bridge.free()
        quit(1)
        return
    var auto_entry: Dictionary = bridge.auto_advance_army_to(
        deep_army["army_id"], "greenvale"
    )
    if not auto_entry.get("accepted", false) or \
            auto_entry.get("auto_target", "") != "greenvale" or \
            auto_entry.get("auto_step_count", 0) != 2 or \
            auto_entry.get("origin", "") != "northreach" or \
            auto_entry.get("destination", "") != "greenvale" or \
            auto_entry.get("auto_total_movement_cost", 0) != 3 or \
            auto_entry.get("movement_cost", 0) != 3 or \
            not auto_entry.get("province_occupied", false):
        push_error("Multi-step auto advance was not reflected in bridge state")
        bridge.free()
        quit(1)
        return
    var arrived_army: Dictionary = {}
    for army_summary: Dictionary in bridge.get_army_summaries():
        if army_summary["id"] == deep_army["army_id"]:
            arrived_army = army_summary
    if arrived_army.get("advance_target_id", "") != "":
        push_error("Army advance target was not cleared after reaching target")
        bridge.free()
        quit(1)
        return

    if not bridge.load_scenario(data_directory, 1000, 1):
        push_error("Scenario reload for paused advance failed: %s" % bridge.get_last_error())
        bridge.free()
        quit(1)
        return
    bridge.set_ai_enabled(false, "auroria")
    var paused: Dictionary = bridge.recruit_army("auroria", "northreach", 1000)
    bridge.build_road("auroria", "northreach", "westmark")
    bridge.declare_war("auroria", "verdantia")
    bridge.set_army_advance_target(paused["army_id"], "greenvale")
    var pause_result: Dictionary = bridge.set_army_advance_enabled(
        paused["army_id"], false
    )
    bridge.advance_turn(3)
    var paused_after: Dictionary = {}
    for army_summary: Dictionary in bridge.get_army_summaries():
        if army_summary["id"] == paused["army_id"]:
            paused_after = army_summary
    var resume_result: Dictionary = bridge.set_army_advance_enabled(
        paused["army_id"], true
    )
    bridge.advance_turn(1)
    var resumed_after: Dictionary = {}
    for army_summary: Dictionary in bridge.get_army_summaries():
        if army_summary["id"] == paused["army_id"]:
            resumed_after = army_summary
    if not pause_result.get("accepted", false) or \
            not resume_result.get("accepted", false) or \
            paused_after.get("province_id", "") != "northreach" or \
            paused_after.get("advance_target_id", "") != "greenvale" or \
            paused_after.get("advance_enabled", true) or \
            resumed_after.get("province_id", "") == "northreach" or \
            not resumed_after.get("advance_enabled", false):
        push_error("Paused army advance target was not respected during turn advance")
        bridge.free()
        quit(1)
        return

    if not bridge.load_scenario(data_directory, 1000, 1):
        push_error("Scenario reload for one-step advance failed: %s" % bridge.get_last_error())
        bridge.free()
        quit(1)
        return
    bridge.set_ai_enabled(false, "auroria")
    var one_step: Dictionary = bridge.recruit_army("auroria", "northreach", 1000)
    bridge.declare_war("auroria", "verdantia")
    bridge.set_army_advance_target(one_step["army_id"], "z_gv_2")
    var strategy_result: Dictionary = bridge.set_army_advance_strategy(
        one_step["army_id"], "one_step"
    )
    bridge.advance_turn(1)
    var one_step_after: Dictionary = {}
    for army_summary: Dictionary in bridge.get_army_summaries():
        if army_summary["id"] == one_step["army_id"]:
            one_step_after = army_summary
    if not strategy_result.get("accepted", false) or \
            one_step_after.get("advance_strategy", "") != "one_step" or \
            one_step_after.get("province_id", "") == "z_gv_2" or \
            one_step_after.get("province_id", "") == "northreach":
        push_error("One-step army advance strategy was not respected during turn advance")
        bridge.free()
        quit(1)
        return

    if not bridge.load_scenario(data_directory, 1000, 1):
        push_error("Scenario reload for border-stop advance failed: %s" % bridge.get_last_error())
        bridge.free()
        quit(1)
        return
    bridge.set_ai_enabled(false, "auroria")
    var border_stop: Dictionary = bridge.recruit_army("auroria", "northreach", 1000)
    bridge.build_road("auroria", "northreach", "westmark")
    bridge.declare_war("auroria", "verdantia")
    bridge.set_army_advance_target(border_stop["army_id"], "greenvale")
    var border_strategy: Dictionary = bridge.set_army_advance_strategy(
        border_stop["army_id"], "stop_before_enemy"
    )
    bridge.advance_turn(3)
    var border_after: Dictionary = {}
    var border_greenvale: Dictionary = {}
    for army_summary: Dictionary in bridge.get_army_summaries():
        if army_summary["id"] == border_stop["army_id"]:
            border_after = army_summary
    for province_summary: Dictionary in bridge.get_province_summaries():
        if province_summary["id"] == "greenvale":
            border_greenvale = province_summary
    if not border_strategy.get("accepted", false) or \
            border_after.get("advance_strategy", "") != "stop_before_enemy" or \
            border_after.get("province_id", "") != "westmark" or \
            border_after.get("advance_target_id", "") != "greenvale" or \
            border_greenvale.get("owner_id", "") != "verdantia":
        push_error("Border-stop army advance strategy was not respected during turn advance")
        bridge.free()
        quit(1)
        return

    if not bridge.load_scenario(data_directory, 1000, 1):
        push_error("Scenario reload for planned advance failed: %s" % bridge.get_last_error())
        bridge.free()
        quit(1)
        return
    bridge.set_ai_enabled(false, "auroria")
    var planned: Dictionary = bridge.recruit_army("auroria", "northreach", 1000)
    bridge.build_road("auroria", "northreach", "westmark")
    bridge.declare_war("auroria", "verdantia")
    var plan_result: Dictionary = bridge.set_army_advance_target(
        planned["army_id"], "greenvale"
    )
    var turn_plan: Dictionary = bridge.advance_turn(3)
    var planned_move_seen := false
    var planned_battle_seen := false
    for action: Dictionary in turn_plan.get("turn_actions", []):
        if action.get("type", "") == "army_moved" and \
                action.get("army_id", "") == planned["army_id"] and \
                action.get("origin", "") == "northreach" and \
                action.get("destination", "") == "westmark" and \
                action.get("movement_cost", 0) == 1:
            planned_move_seen = true
        if action.get("type", "") == "battle_resolved" and \
                action.get("province_id", "") == "greenvale" and \
                action.get("province_occupied", false):
            planned_battle_seen = true
    var planned_after: Dictionary = {}
    var planned_greenvale: Dictionary = {}
    for army_summary: Dictionary in bridge.get_army_summaries():
        if army_summary["id"] == planned["army_id"]:
            planned_after = army_summary
    for province_summary: Dictionary in bridge.get_province_summaries():
        if province_summary["id"] == "greenvale":
            planned_greenvale = province_summary
    if not plan_result.get("accepted", false) or \
            not turn_plan.get("accepted", false) or \
            not planned_move_seen or \
            not planned_battle_seen or \
            planned_after.get("province_id", "") != "greenvale" or \
            planned_after.get("advance_target_id", "") != "" or \
            planned_greenvale.get("owner_id", "") != "auroria" or \
            not planned_greenvale.get("occupied", false):
        push_error("Stored army advance target was not executed during turn advance")
        bridge.free()
        quit(1)
        return

    print("ProvinceBridge army recruitment smoke test passed")
    bridge.free()
    quit(0)
