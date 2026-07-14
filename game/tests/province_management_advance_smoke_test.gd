extends SceneTree


func _army(bridge: Object, army_id: String) -> Dictionary:
    for summary: Dictionary in bridge.get_army_summaries():
        if summary.get("id", "") == army_id:
            return summary
    return {}


func _fail(main_scene: Node, message: String) -> void:
    push_error(message)
    main_scene.free()
    quit(1)


func _initialize() -> void:
    var packed := load("res://scenes/main/main.tscn") as PackedScene
    var main_scene := packed.instantiate()
    root.add_child(main_scene)
    await process_frame

    var bridge := main_scene.get_node("SimulationBridge")
    var province_map := main_scene.get_node("MapPanel/ProvinceMap")
    var management := main_scene.get_node(
        "WorkspacePanel/Workspace/WindowViewport/WindowContent/ProvinceManagementWindow"
    )
    var advance_turn := main_scene.get_node(
        "TurnBar/TurnControls/AdvanceTurn"
    ) as Button

    province_map.province_double_clicked.emit("northreach")
    management.get_node("RecruitArmy").pressed.emit()
    await process_frame
    var selector := management.get_node("ArmySelector") as OptionButton
    var army_id := String(selector.get_item_metadata(0))

    for _month: int in range(3):
        advance_turn.pressed.emit()
    province_map.province_double_clicked.emit("northreach")

    var select_advance := management.get_node(
        "AdvanceActions/SelectAdvanceTarget"
    ) as Button
    var advance_now := management.get_node("AdvanceActions/AdvanceNow") as Button
    var advance_plans := management.get_node("AdvancePlans") as RichTextLabel
    select_advance.pressed.emit()
    if main_scene.map_input_mode_name() != "auto_advance_destination":
        _fail(main_scene, "Management page did not enter advance target selection")
        return

    province_map.province_selected.emit("z_wm_1")
    await process_frame
    var advance_target_name: String = main_scene.province_by_id["z_wm_1"]["name"]
    if not management.get_node("AdvanceTarget").text.contains(advance_target_name) or \
            not advance_plans.text.contains(army_id):
        _fail(main_scene, "Non-adjacent advance target was not stored and displayed")
        return

    advance_plans.meta_clicked.emit("pause:%s" % army_id)
    await process_frame
    if _army(bridge, army_id).get("advance_enabled", true):
        _fail(main_scene, "Advance plan did not pause from management")
        return

    advance_plans.meta_clicked.emit("resume:%s" % army_id)
    advance_plans.meta_clicked.emit("strategy:%s:one_step" % army_id)
    await process_frame
    if not _army(bridge, army_id).get("advance_enabled", false) or \
            _army(bridge, army_id).get("advance_strategy", "") != "one_step":
        _fail(main_scene, "Advance plan resume or strategy action failed")
        return

    advance_plans.meta_clicked.emit("clear:%s" % army_id)
    await process_frame
    if not String(_army(bridge, army_id).get("advance_target_id", "")).is_empty():
        _fail(main_scene, "Advance plan did not clear from management")
        return

    advance_plans.meta_clicked.emit("strategy:%s:max" % army_id)
    select_advance.pressed.emit()
    province_map.province_selected.emit("z_wm_1")
    await process_frame
    advance_now.pressed.emit()
    await process_frame
    var moved_army := _army(bridge, army_id)
    if moved_army.is_empty() or moved_army.get("province_id", "") == "northreach":
        _fail(main_scene, "Immediate automatic advance did not move the army")
        return

    var moved_province_id: String = moved_army.get("province_id", "")
    var moved_name: String = main_scene.province_by_id[moved_province_id]["name"]
    select_advance.pressed.emit()
    province_map.province_selected.emit("northreach")
    await process_frame
    province_map.province_double_clicked.emit("northreach")
    await process_frame
    advance_plans.meta_clicked.emit("select:%s" % army_id)
    await process_frame
    if management.get_node("ProvinceName").text != moved_name:
        _fail(main_scene, "Selecting a remote plan did not switch managed province")
        return

    print("Province management advance smoke test passed")
    main_scene.free()
    quit(0)
