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
        [{
            "id": "army_1",
            "owner_id": "auroria",
            "province_id": "northreach",
            "manpower": 1000,
            "movement_points": 0,
        }],
        "auroria",
        "army_1"
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

    var technology_status := window.get_node("Technology/Status") as Label
    var advance_target := window.get_node("AdvanceTarget") as Label
    var province_summary := window.get_node("ProvinceSummary") as Label
    if observed["research_track"] != "economy" or \
            observed["advance_army"] != "army_1" or \
            observed["plan_command"] != "pause:army_1" or \
            not province_summary.text.contains("120000") or \
            not province_summary.text.ends_with("1200") or \
            not technology_status.text.contains("道路 3") or \
            not advance_target.text.contains("河间"):
        _fail(window, "Province management component contract is incomplete")
        return

    print("Province management component smoke test passed")
    window.free()
    quit(0)
