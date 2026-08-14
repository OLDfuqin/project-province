extends SceneTree


func _fail(window: Node, message: String) -> void:
    push_error(message)
    window.free()
    quit(1)


func _initialize() -> void:
    var packed := load("res://scenes/ui/province_management_window.tscn") as PackedScene
    if packed == null:
        push_error("Province management component scene could not be loaded")
        quit(1)
        return

    var window := packed.instantiate()
    root.add_child(window)
    await process_frame

    var required_signals := [
        "technology_research_requested",
        "recruit_requested",
        "rename_requested",
        "merge_requested",
        "advance_destination_selection_requested",
        "auto_advance_requested",
        "movement_clear_requested",
        "advance_plan_action_requested",
    ]
    for signal_name: String in required_signals:
        if not window.has_signal(signal_name):
            _fail(window, "Province management signal is missing: %s" % signal_name)
            return

    var observed := {
        "research_track": "",
        "advance_army": "",
        "plan_command": "",
        "recruit_manpower": 0,
        "rename_number": 0,
        "merge_primary": "",
        "merge_ids": [],
    }
    window.technology_research_requested.connect(
        func(track: String) -> void: observed["research_track"] = track
    )
    window.advance_destination_selection_requested.connect(
        func(army_id: String) -> void: observed["advance_army"] = army_id
    )
    window.advance_plan_action_requested.connect(
        func(command: String) -> void: observed["plan_command"] = command
    )
    window.recruit_requested.connect(
        func(_province_id: String, manpower: int) -> void:
            observed["recruit_manpower"] = manpower
    )
    window.rename_requested.connect(
        func(_army_id: String, formation_number: int) -> void:
            observed["rename_number"] = formation_number
    )
    window.merge_requested.connect(
        func(primary_id: String, merged_ids: Array) -> void:
            observed["merge_primary"] = primary_id
            observed["merge_ids"] = merged_ids
    )

    window.display_province(
        {
            "id": "northreach",
            "name": "北境",
            "owner_id": "auroria",
            "population": 120000,
            "recruitable_population": 1000,
            "economy": 120000,
            "fiscal_income": 1200,
        },
        [
            {
                "id": "army_1",
                "owner_id": "auroria",
                "province_id": "northreach",
                "manpower": 1000,
                "movement_points": 3,
                "formation_number": 1,
                "display_name": "奥·第1军",
            },
            {
                "id": "army_2",
                "owner_id": "auroria",
                "province_id": "northreach",
                "manpower": 500,
                "movement_points": 1,
                "formation_number": 2,
                "display_name": "奥·第2军",
            },
            {
                "id": "army_3",
                "owner_id": "caelus",
                "province_id": "northreach",
                "manpower": 500,
                "movement_points": 1,
                "formation_number": 1,
                "display_name": "凯·第1军",
            },
        ],
        "auroria",
        "army_1",
        10000
    )
    window.set_technology({
        "economy_level": 1,
        "military_level": 2,
        "roads_level": 3,
    })
    window.set_advance_target("rivergate", "河间")
    window.set_advance_plans("[url=pause:army_1]暂停[/url]")

    var economy := window.get_node_or_null("Technology/Buttons/Economy") as Button
    var select_advance := window.get_node_or_null(
        "AdvanceActions/SelectAdvanceTarget"
    ) as Button
    var advance_plans := window.get_node_or_null("AdvancePlans") as RichTextLabel
    if economy == null or select_advance == null or advance_plans == null:
        _fail(window, "Province management component controls are missing")
        return

    economy.pressed.emit()
    select_advance.pressed.emit()
    advance_plans.meta_clicked.emit("pause:army_1")
    window.get_node("Recruitment/Open").pressed.emit()
    window.get_node("Recruitment/Amount").value = 125
    window.get_node("Recruitment/Buttons/Confirm").pressed.emit()
    window.get_node("Rename/FormationNumber").value = 5
    window.get_node("Rename/Confirm").pressed.emit()
    var merge_candidates := window.get_node("Merge/Candidates") as ItemList
    merge_candidates.select(0, false)
    merge_candidates.multi_selected.emit(0, true)
    window.get_node("Merge/Confirm").pressed.emit()

    var technology_status := window.get_node("Technology/Status") as Label
    var advance_target := window.get_node("AdvanceTarget") as Label
    var province_summary := window.get_node("ProvinceSummary") as Label
    if observed["research_track"] != "economy" or \
            observed["advance_army"] != "army_1" or \
            observed["plan_command"] != "pause:army_1" or \
            observed["recruit_manpower"] != 125 or \
            observed["rename_number"] != 5 or \
            observed["merge_primary"] != "army_1" or \
            observed["merge_ids"] != ["army_2"] or \
            merge_candidates.item_count != 1 or \
            not province_summary.text.contains("120000") or \
            not province_summary.text.ends_with("1200") or \
            not technology_status.text.contains("道路 3") or \
            not advance_target.text.contains("河间"):
        _fail(window, "Province management component contract is incomplete")
        return

    print("Province management component smoke test passed")
    window.free()
    quit(0)
