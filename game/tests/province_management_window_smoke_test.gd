extends SceneTree


func _initialize() -> void:
    var packed_scene := load("res://scenes/main/main.tscn") as PackedScene
    if packed_scene == null:
        push_error("Main scene could not be loaded for province management testing")
        quit(1)
        return

    var main_scene := packed_scene.instantiate() as Control
    root.add_child(main_scene)
    await process_frame

    var province_map := main_scene.get_node("MapPanel/ProvinceMap")
    var management := main_scene.get_node_or_null(
        "WorkspacePanel/Workspace/WindowViewport/WindowContent/ProvinceManagementWindow"
    ) as Control
    if management == null:
        push_error("Province management window was not embedded in the workspace")
        main_scene.free()
        quit(1)
        return

    province_map.province_double_clicked.emit("northreach")
    var recruit := management.get_node("RecruitArmy") as Button
    var army_selector := management.get_node("ArmySelector") as OptionButton
    var select_destination := management.get_node("ArmyActions/SelectDestination") as Button
    var move_army := management.get_node("ArmyActions/MoveArmy") as Button
    if main_scene.workspace_mode_name() != "province_management" or \
            not management.visible or \
            management.get_node("ProvinceName").text != "北境" or \
            recruit.disabled or army_selector.item_count != 0 or \
            not management.get_node("Placeholders/EconomyInvestment").disabled or \
            not management.get_node("Placeholders/CivilInvestment").disabled or \
            not management.get_node("Placeholders/BuildingManagement").disabled:
        push_error("Province management window did not show the initial province state")
        main_scene.free()
        quit(1)
        return

    var technology_status := management.get_node("Technology/Status") as Label
    var economy_research := management.get_node(
        "Technology/Buttons/Economy"
    ) as Button
    if not technology_status.text.contains("经济 0"):
        push_error("Management page did not display technology")
        main_scene.free()
        quit(1)
        return
    economy_research.pressed.emit()
    await process_frame
    if not technology_status.text.contains("经济 1"):
        push_error("Technology research did not refresh management page")
        main_scene.free()
        quit(1)
        return

    recruit.pressed.emit()
    if main_scene.workspace_mode_name() != "province_management" or \
            army_selector.item_count != 1 or \
            not management.get_node("ProvinceSummary").text.contains("可招募士兵：1000"):
        push_error("Recruitment did not refresh the open management window")
        main_scene.free()
        quit(1)
        return

    var advance_turn := main_scene.get_node(
        "TurnBar/TurnControls/AdvanceTurn"
    ) as Button
    advance_turn.pressed.emit()
    province_map.province_double_clicked.emit("northreach")
    if army_selector.item_count != 1 or select_destination.disabled:
        push_error("The recruited army was not available after reopening management")
        main_scene.free()
        quit(1)
        return

    select_destination.pressed.emit()
    if main_scene.map_input_mode_name() != "army_destination" or \
            main_scene.workspace_mode_name() != "province_management":
        push_error("Destination selection mode did not start from management")
        main_scene.free()
        quit(1)
        return

    province_map.province_clicked.emit("westmark")
    province_map.province_selected.emit("westmark")
    if main_scene.map_input_mode_name() != "normal" or move_army.disabled or \
            not management.get_node("DirectDestination").text.contains("西境"):
        push_error("The management window did not accept an adjacent destination")
        main_scene.free()
        quit(1)
        return

    var army_id := String(army_selector.get_selected_metadata())
    move_army.pressed.emit()
    var moved := false
    for army: Dictionary in main_scene.get_node("SimulationBridge").get_army_summaries():
        if army.get("id", "") == army_id and army.get("province_id", "") == "westmark":
            moved = true
            break
    if not moved or main_scene.workspace_mode_name() != "province_management" or \
            army_selector.item_count != 0:
        push_error("The selected army was not moved from the management window")
        main_scene.free()
        quit(1)
        return

    province_map.map_blank_clicked.emit()
    if main_scene.workspace_mode_name() != "closed" or management.visible:
        push_error("Blank map click did not close the province management window")
        main_scene.free()
        quit(1)
        return

    print("Province management window smoke test passed")
    main_scene.free()
    quit(0)
