extends SceneTree


func _fail(main_scene: Control, message: String) -> void:
    push_error(message)
    if is_instance_valid(main_scene):
        main_scene.free()
    quit(1)


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
        var normalized: Array = []
        for item: Variant in value:
            normalized.append(_normalize_json_numbers(item))
        return normalized
    if value is Dictionary:
        var normalized: Dictionary = {}
        for key: Variant in value:
            normalized[key] = _normalize_json_numbers(value[key])
        return normalized
    return value


func _write_json(path: String, document: Dictionary) -> bool:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(_normalize_json_numbers(document)))
    file.close()
    return true


func _army(bridge: Object, army_id: String) -> Dictionary:
    for army: Dictionary in bridge.get_army_summaries():
        if String(army.get("id", "")) == army_id:
            return army
    return {}


func _escape_key() -> InputEventKey:
    var escape := InputEventKey.new()
    escape.pressed = true
    escape.keycode = KEY_ESCAPE
    return escape


func _resize_root_window(viewport_size: Vector2) -> void:
    root.size = Vector2i(viewport_size)
    await process_frame
    await process_frame


func _assert_responsive_shell(
    main_scene: Control,
    top_bar: Control,
    navigation: Control,
    map_panel: Control,
    inspector: Control,
    drawer: Control,
    profile: Dictionary
) -> String:
    var viewport_size: Vector2 = profile["size"]
    await _resize_root_window(viewport_size)

    var expected_name := String(profile["name"])
    if Vector2(root.size) != viewport_size or main_scene.size != viewport_size or \
            main_scene.get_viewport().get_visible_rect().size != viewport_size:
        return "Window resize to %s remained in a fixed %s logical viewport" % [
            viewport_size, main_scene.get_viewport().get_visible_rect().size,
        ]
    if main_scene.viewport_profile_name() != expected_name:
        return "Viewport %s selected %s instead of %s" % [
            viewport_size, main_scene.viewport_profile_name(), expected_name,
        ]
    if not is_equal_approx(navigation.custom_minimum_size.x, float(profile["navigation_width"])) or \
            not is_equal_approx(inspector.custom_minimum_size.x, float(profile["inspector_width"])):
        return "Viewport %s did not apply the declared navigation/inspector profile" % viewport_size
    for metric_name: String in ["Treasury", "Income", "Maintenance", "Recruitable"]:
        var metric := top_bar.get_node("Margin/Row/%s" % metric_name) as Label
        if metric == null or not metric.visible or metric.text.is_empty():
            return "Viewport %s hid a required compact status metric: %s" % [viewport_size, metric_name]

    var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
    var map_rect := map_panel.get_global_rect()
    var inspector_rect := inspector.get_global_rect()
    var advance_turn := top_bar.get_node("Margin/Row/AdvanceTurn") as Button
    if advance_turn == null:
        return "Strategic layout has no next-turn action at %s" % viewport_size
    var advance_rect: Rect2 = advance_turn.get_global_rect()
    if map_rect.intersects(inspector_rect) or not viewport_rect.encloses(advance_rect):
        return "Strategic layout overlaps or hides the next-turn action at %s" % viewport_size
    if not viewport_rect.encloses(map_rect) or not viewport_rect.encloses(inspector_rect):
        return "Strategic shell escaped the viewport at %s" % viewport_size

    main_scene.call("_on_drawer_requested", "orders")
    await process_frame
    var drawer_panel := drawer.get_node("Panel") as Control
    if drawer_panel == null or not drawer.visible or \
            drawer_panel.get_global_rect().intersects(inspector_rect) or \
            not viewport_rect.encloses(drawer_panel.get_global_rect()):
        return "Bottom drawer overlaps the inspector or escaped the viewport at %s" % viewport_size
    main_scene.call("_on_drawer_requested", "orders")
    await process_frame
    return ""


func _assert_management_order_drawer(
    main_scene: Control,
    bridge: Object,
    province_map: Control,
    inspector: Control,
    mode_bar: Control,
    drawer: Control,
    profile: Dictionary
) -> String:
    var created: Dictionary = bridge.recruit_army("auroria", "capital_auroria", 1)
    if not created.get("accepted", false):
        return "Could not create a real pending order for responsive drawer verification"
    main_scene.call("_refresh_pending_orders")
    province_map.province_double_clicked.emit("capital_auroria")
    await process_frame
    var tabs := main_scene.province_management_window.get_node("Tabs") as TabContainer
    tabs.current_tab = 1

    await _resize_root_window(profile["size"])
    main_scene.call("_on_drawer_requested", "orders")
    await process_frame
    await process_frame

    var viewport_rect := Rect2(Vector2.ZERO, Vector2(profile["size"]))
    var drawer_panel := drawer.get_node("Panel") as Control
    var cancel := drawer.get_node_or_null("Panel/Body/Orders/Rows/Order0/Cancel") as Button
    if not drawer.visible or drawer_panel.get_global_rect().intersects(inspector.get_global_rect()) or \
            drawer_panel.get_global_rect().intersects(mode_bar.get_global_rect()):
        return "Real order drawer overlapped the inspector or bottom bar at %s" % profile["size"]
    if cancel == null or cancel.disabled or not cancel.is_visible_in_tree() or \
            cancel.mouse_filter == Control.MOUSE_FILTER_IGNORE or \
            not viewport_rect.encloses(cancel.get_global_rect()):
        return "Real order cancellation is not visible and clickable at %s" % profile["size"]

    cancel.pressed.emit()
    await process_frame
    await process_frame
    if not bridge.get_pending_orders("auroria").is_empty():
        return "Clickable order cancellation did not reach the authoritative bridge"
    drawer.close()
    main_scene.call("_close_workspace")
    return ""


func _initialize() -> void:
    var packed_scene := load("res://scenes/main/main.tscn") as PackedScene
    if packed_scene == null:
        _fail(null, "Main scene could not be loaded")
        return
    var main_scene := packed_scene.instantiate() as Control
    root.add_child(main_scene)
    await process_frame

    var top_bar := main_scene.get_node_or_null(
        "Shell/Layout/GlobalStatusBar"
    ) as Control
    var navigation := main_scene.get_node_or_null(
        "Shell/Layout/MainRow/PrimaryNavigation"
    ) as Control
    var map_panel := main_scene.get_node_or_null(
        "Shell/Layout/MainRow/MapPanel"
    ) as Control
    var inspector := main_scene.get_node_or_null(
        "Shell/Layout/MainRow/ContextInspector"
    ) as Control
    var mode_bar := main_scene.get_node_or_null(
        "Shell/Layout/MapModeBar"
    ) as Control
    var drawer := main_scene.get_node_or_null("Shell/BottomDrawer") as Control
    var pages := main_scene.get_node_or_null("Shell/ManagementPageHost") as Control
    if top_bar == null or navigation == null or map_panel == null or \
            inspector == null or mode_bar == null or drawer == null or pages == null:
        _fail(main_scene, "Strategic shell is incomplete")
        return
    if main_scene.get_node_or_null("RightPanel") != null or \
            main_scene.get_node_or_null("WorkspacePanel") != null or \
            main_scene.get_node_or_null("TurnBar") != null:
        _fail(main_scene, "Legacy double-right-column layout still exists")
        return

    var advance_turn := top_bar.get_node_or_null("Margin/Row/AdvanceTurn") as Button
    if advance_turn == null or advance_turn.text != "进入下一回合" or \
            not advance_turn.visible or drawer.visible:
        _fail(main_scene, "Fixed next-turn control or closed drawer state is wrong")
        return
    if top_bar.get_node_or_null("Margin/Row/CoreVersion") != null or \
            top_bar.get_node_or_null("Margin/Row/SaveCount") != null:
        _fail(main_scene, "Build metadata leaked into the map-first status bar")
        return
    if inspector.get_parent() != map_panel.get_parent() or \
            main_scene.get_tree().get_nodes_in_group("context_inspector").size() > 1:
        _fail(main_scene, "Strategic shell must own exactly one context inspector")
        return

    if main_scene.active_page_name() != "closed" or \
            main_scene.active_drawer_name() != "closed" or \
            main_scene.active_map_mode_name() != "political" or \
            main_scene.workspace_mode_name() != "closed" or \
            main_scene.map_input_mode_name() != "normal":
        _fail(main_scene, "Main scene did not expose the initial strategic state")
        return

    var bridge := main_scene.get_node("SimulationBridge") as Object
    if bridge == null:
        _fail(main_scene, "Main scene lost its simulation bridge before responsive verification")
        return
    var province_map := map_panel.get_node_or_null("ProvinceMap")
    if province_map == null:
        _fail(main_scene, "Map panel lost the interactive province map")
        return
    var date_before_profiles: Dictionary = bridge.get_current_date().duplicate(true)
    var countries_before_profiles: Array = bridge.get_country_summaries().duplicate(true)
    var orders_before_profiles: Array = bridge.get_pending_orders("auroria").duplicate(true)
    for profile: Dictionary in [
        {
            "size": Vector2(1280, 720), "name": "compact",
            "navigation_width": 56.0, "inspector_width": 320.0,
        },
        {
            "size": Vector2(1440, 900), "name": "standard",
            "navigation_width": 64.0, "inspector_width": 360.0,
        },
        {
            "size": Vector2(1920, 1080), "name": "wide",
            "navigation_width": 64.0, "inspector_width": 420.0,
        },
    ]:
        var responsive_error := await _assert_responsive_shell(
            main_scene, top_bar, navigation, map_panel, inspector, drawer, profile
        )
        if not responsive_error.is_empty():
            _fail(main_scene, responsive_error)
            return
    if bridge.get_current_date() != date_before_profiles or \
            bridge.get_country_summaries() != countries_before_profiles or \
            bridge.get_pending_orders("auroria") != orders_before_profiles:
        _fail(main_scene, "Viewport profiles changed authoritative simulation data")
        return
    for profile: Dictionary in [
        {"size": Vector2(1280, 720)},
        {"size": Vector2(1440, 900)},
        {"size": Vector2(1920, 1080)},
    ]:
        var combination_error := await _assert_management_order_drawer(
            main_scene, bridge, province_map, inspector, mode_bar, drawer, profile
        )
        if not combination_error.is_empty():
            _fail(main_scene, combination_error)
            return
    for scroll: ScrollContainer in [
        inspector.get_node("Body/ScrollContainer"),
        drawer.get_node("Panel/Body/Orders"),
        drawer.get_node("Panel/Body/Notifications"),
        drawer.get_node("Panel/Body/TurnReportSection"),
    ]:
        if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
            _fail(main_scene, "Strategic responsive content permits horizontal scrolling")
            return
    var theme := load("res://themes/strategic_ui_theme.tres") as Theme
    var focus_style := theme.get_stylebox("focus", "Button") as StyleBoxFlat
    var disabled_style := theme.get_stylebox("disabled", "Button") as StyleBoxFlat
    var gold := Color("d6a64a")
    if focus_style == null or focus_style.border_width_left != 2 or \
            focus_style.border_width_top != 2 or \
            not is_equal_approx(focus_style.border_color.r, gold.r) or \
            not is_equal_approx(focus_style.border_color.g, gold.g) or \
            not is_equal_approx(focus_style.border_color.b, gold.b) or \
            disabled_style == null or disabled_style.bg_color.a >= 1.0:
        _fail(main_scene, "Strategic theme lacks the required gold focus ring or disabled presentation")
        return
    top_bar.set_advance_enabled(false, "演示禁用原因")
    main_scene.call("_apply_accessibility_presentation")
    if not advance_turn.disabled or not advance_turn.tooltip_text.contains("演示禁用原因"):
        _fail(main_scene, "Disabled primary actions did not retain their Chinese reason tooltip")
        return
    top_bar.set_advance_enabled(true)
    main_scene.call("_apply_accessibility_presentation")
    if advance_turn.disabled or advance_turn.tooltip_text != "结算当前月并进入下一回合":
        _fail(main_scene, "Re-enabled primary action retained a disabled tooltip")
        return

    province_map.province_double_clicked.emit("capital_auroria")
    await process_frame
    var inspector_scroll := inspector.get_node("Body/ScrollContainer") as ScrollContainer
    if inspector_scroll == null or inspector_scroll.size.y <= 0.0 or \
            inspector_scroll.get_v_scroll_bar() == null:
        _fail(main_scene, "Province management is not vertically reachable through the inspector")
        return
    var management_tabs := main_scene.province_management_window.get_node("Tabs") as TabContainer
    var expected_tab_titles := ["概览", "军事", "建设", "订单"]
    for index: int in expected_tab_titles.size():
        if management_tabs.get_tab_title(index) != expected_tab_titles[index]:
            _fail(main_scene, "Province management leaked an English or internal tab title")
            return
    inspector.get_node("Body/Header/Close").pressed.emit()

    navigation.get_node("Margin/Row/Diplomacy").pressed.emit()
    await process_frame
    var escape := _escape_key()
    var diplomacy_for_escape := pages.get_node("Pages/Diplomacy") as Control
    diplomacy_for_escape.select_country("caelus")
    diplomacy_for_escape.get_node("Content/Actions/DeclareWar").pressed.emit()
    await process_frame
    var confirmation := main_scene.get_node_or_null("Shell/ActionConfirmation") as ConfirmationDialog
    if confirmation == null or not confirmation.visible:
        _fail(main_scene, "High-impact diplomacy action did not open a confirmation layer")
        return
    main_scene._unhandled_key_input(escape)
    await process_frame
    if confirmation.visible or main_scene.active_page_name() != "diplomacy":
        _fail(main_scene, "Esc did not dismiss only the confirmation layer first")
        return
    diplomacy_for_escape.get_node("Content/Actions/DeclareWar").pressed.emit()
    await process_frame
    if not confirmation.visible or main_scene._pending_confirmation.is_empty():
        _fail(main_scene, "Could not reopen a confirmation for native cancellation testing")
        return
    confirmation.get_cancel_button().pressed.emit()
    await process_frame
    if confirmation.visible or not main_scene._pending_confirmation.is_empty():
        _fail(main_scene, "ConfirmationDialog cancellation retained a stale intent")
        return
    confirmation.confirmed.emit()
    await process_frame
    if not bridge.get_pending_orders("auroria").is_empty():
        _fail(main_scene, "A canceled confirmation submitted its stale diplomacy intent later")
        return
    main_scene.call("_on_drawer_requested", "orders")
    main_scene._unhandled_key_input(escape)
    await process_frame
    if main_scene.active_drawer_name() != "closed" or main_scene.active_page_name() != "closed":
        _fail(main_scene, "Esc did not dismiss the drawer before other layers")
        return
    main_scene.map_input_mode = main_scene.MapInputMode.ARMY_DESTINATION
    main_scene._unhandled_key_input(escape)
    await process_frame
    if main_scene.map_input_mode_name() != "normal" or main_scene.active_page_name() != "closed":
        _fail(main_scene, "Esc did not leave a pending map target selection")
        return
    navigation.get_node("Margin/Row/Technology").pressed.emit()
    await process_frame
    main_scene._unhandled_key_input(escape)
    await process_frame
    if main_scene.active_page_name() != "closed" or navigation.active_destination() != "map":
        _fail(main_scene, "Esc did not return from the management page to the map")
        return
    main_scene._unhandled_key_input(escape)
    await process_frame
    if main_scene.active_page_name() != "settings" or navigation.active_destination() != "settings":
        _fail(main_scene, "Esc did not open settings as the final return layer")
        return
    main_scene._unhandled_key_input(escape)
    await process_frame
    if main_scene.active_page_name() != "closed" or navigation.active_destination() != "map":
        _fail(main_scene, "Esc did not return from settings to the map")
        return

    for case: Dictionary in [
        {"status": {"has_scenario": true, "player_won": true}, "text": "胜利：奥罗里亚已经控制世界"},
        {"status": {"has_scenario": true, "player_eliminated": true}, "text": "失败：奥罗里亚已经灭亡"},
        {"status": {"has_scenario": true, "winner_id": "caelus"}, "text": "胜利国家：凯洛斯"},
        {"status": {"has_scenario": true, "countries": [{"eliminated": false}, {"eliminated": false}, {"eliminated": true}]}, "text": "存续国家：2"},
    ]:
        if String(main_scene.call("_game_status_message", case["status"])) != case["text"]:
            _fail(main_scene, "Game status feedback did not preserve the strategic result message")
            return
    if not "\n".join(main_scene._notifications).contains("存续国家：4"):
        _fail(main_scene, "Game status did not enter the visible notification workflow")
        return

    province_map.province_clicked.emit("capital_auroria")
    await process_frame
    if main_scene.workspace_mode_name() != "province_summary" or \
            inspector.current_mode() != "province_summary":
        _fail(main_scene, "Single map click did not open the province summary")
        return
    province_map.map_blank_clicked.emit()
    await process_frame
    if main_scene.workspace_mode_name() != "closed":
        _fail(main_scene, "Blank map click did not close the temporary summary")
        return
    province_map.province_double_clicked.emit("capital_auroria")
    await process_frame
    if main_scene.workspace_mode_name() != "province_management" or \
            inspector.current_mode() != "province_management":
        _fail(main_scene, "Double click did not open province management in the inspector")
        return
    province_map.map_blank_clicked.emit()
    if main_scene.workspace_mode_name() != "province_management":
        _fail(main_scene, "Blank map click discarded a persistent management context")
        return
    inspector.get_node("Body/Header/Close").pressed.emit()
    await process_frame
    if main_scene.workspace_mode_name() != "closed":
        _fail(main_scene, "Inspector close did not restore the map context")
        return

    mode_bar.get_node("Margin/Row/PendingOrders").pressed.emit()
    await process_frame
    if main_scene.active_drawer_name() != "orders" or not drawer.visible:
        _fail(main_scene, "Order drawer did not open from the map mode bar")
        return
    drawer.get_node("Panel/Body/Header/Close").pressed.emit()
    mode_bar.get_node("Margin/Row/Roads").pressed.emit()
    await process_frame
    if main_scene.active_map_mode_name() != "roads" or \
            main_scene.workspace_mode_name() != "road_construction":
        _fail(main_scene, "Road map mode did not enter road planning")
        return
    inspector.get_node("Body/Header/Close").pressed.emit()

    navigation.get_node("Margin/Row/Technology").pressed.emit()
    await process_frame
    if main_scene.active_page_name() != "technology" or not pages.visible or \
            main_scene.workspace_mode_name() != "closed":
        _fail(main_scene, "Primary navigation did not open the technology page")
        return

    mode_bar.get_node("Margin/Row/PendingOrders").pressed.emit()
    await process_frame
    if main_scene.active_page_name() != "closed" or pages.visible or \
            main_scene.active_drawer_name() != "orders" or not drawer.visible:
        _fail(main_scene, "Opening a drawer did not return from the covering management page")
        return
    drawer.get_node("Panel/Body/Header/Close").pressed.emit()
    navigation.get_node("Margin/Row/Technology").pressed.emit()
    await process_frame
    mode_bar.get_node("Margin/Row/Roads").pressed.emit()
    await process_frame
    if main_scene.active_page_name() != "closed" or pages.visible or \
            main_scene.workspace_mode_name() != "road_construction" or \
            inspector.current_mode() != "road_construction" or \
            not main_scene.road_construction_window.visible:
        _fail(main_scene, "Road entry from a management page did not expose the inspector")
        return
    inspector.get_node("Body/Header/Close").pressed.emit()

    mode_bar.get_node("Margin/Row/PendingOrders").pressed.emit()
    main_scene._unhandled_key_input(escape)
    await process_frame
    if main_scene.active_drawer_name() != "closed":
        _fail(main_scene, "ui_cancel did not close the open bottom drawer first")
        return

    main_scene.map_input_mode = main_scene.MapInputMode.ARMY_DESTINATION
    main_scene._unhandled_key_input(escape)
    await process_frame
    if main_scene.map_input_mode_name() != "normal" or main_scene.active_page_name() != "closed":
        _fail(main_scene, "ui_cancel did not leave a pending map target selection")
        return

    mode_bar.get_node("Margin/Row/Roads").pressed.emit()
    main_scene._unhandled_key_input(escape)
    await process_frame
    if main_scene.workspace_mode_name() != "closed" or \
            main_scene.active_map_mode_name() != "political":
        _fail(main_scene, "ui_cancel did not leave road selection and restore the map")
        return

    main_scene._unhandled_key_input(escape)
    await process_frame
    if main_scene.active_page_name() != "settings" or not pages.visible or \
            navigation.active_destination() != "settings":
        _fail(main_scene, "ui_cancel did not open settings with matching navigation state")
        return
    pages.get_node("Pages/Header/Back").pressed.emit()
    if main_scene.active_page_name() != "closed" or \
            navigation.active_destination() != "map":
        _fail(main_scene, "Management page back action did not return to the map")
        return

    mode_bar.get_node("Margin/Row/TurnReport").pressed.emit()
    advance_turn.pressed.emit()
    await process_frame
    await process_frame
    var turn_report := drawer.get_node("Panel/Body/TurnReportSection/TurnReportText") as Label
    if main_scene.active_drawer_name() != "turn_report" or \
            not main_scene._latest_event_message.contains("财政收入") or \
            not turn_report.text.contains("财政收入"):
        _fail(main_scene, "Next turn did not refresh the visible turn report")
        return

    drawer.get_node("Panel/Body/Header/Close").pressed.emit()
    if bridge == null:
        _fail(main_scene, "Main scene lost its simulation bridge during save/load testing")
        return
    var prepared_recruit: Dictionary = bridge.recruit_army("auroria", "capital_auroria", 100)
    if not prepared_recruit.get("accepted", false) or not bridge.advance_turn().get("accepted", false):
        _fail(main_scene, "Could not prepare an army for the quick-load fixture")
        return
    main_scene.call("_refresh_map_data")
    var preserved_army_id := ""
    for army: Dictionary in bridge.get_army_summaries():
        if army.get("owner_id", "") == "auroria":
            preserved_army_id = String(army.get("id", ""))
            break
    var preserved_origin_id := String(_army(bridge, preserved_army_id).get("province_id", ""))
    var preserved_target_id := ""
    for province: Dictionary in bridge.get_province_summaries():
        if String(province.get("id", "")) != preserved_origin_id:
            preserved_target_id = String(province.get("id", ""))
            break
    if preserved_army_id.is_empty() or preserved_target_id.is_empty() or \
            not bridge.set_army_advance_target(preserved_army_id, preserved_target_id).get("accepted", false):
        _fail(main_scene, "Could not prepare the saved automatic advance target")
        return
    main_scene.moving_army_id = preserved_army_id
    navigation.get_node("Margin/Row/Settings").pressed.emit()
    await process_frame
    var settings := pages.get_node("Pages/Settings") as Control
    settings.get_node("Content/Actions/QuickSave").pressed.emit()
    bridge.clear_army_advance_target(preserved_army_id)
    if not String(_army(bridge, preserved_army_id).get("advance_target_id", "")).is_empty():
        _fail(main_scene, "Quick-load fixture did not clear the saved advance target")
        return
    settings.get_node("Content/Actions/QuickLoad").pressed.emit()
    await process_frame
    if String(_army(bridge, preserved_army_id).get("advance_target_id", "")) != preserved_target_id or \
            not main_scene.moving_army_id.is_empty() or \
            main_scene.map_input_mode_name() != "normal":
        _fail(main_scene, "Quick load did not restore advance progress and clear local selection")
        return

    var quick_path := ProjectSettings.globalize_path("user://quick_save.json")
    var extreme_quote_path := ProjectSettings.globalize_path(
        "res://../build/task9-extreme-recruitment-quote.json"
    )
    if not bridge.save_game(extreme_quote_path).get("accepted", false):
        _fail(main_scene, "Could not save the extreme recruitment quote fixture")
        return
    var extreme_document := _read_json(extreme_quote_path)
    for country: Dictionary in extreme_document.get("countries", []):
        if country.get("id", "") == "auroria":
            country["treasury"] = 9223372036854775807
    for province: Dictionary in extreme_document.get("provinces", []):
        if province.get("id", "") == "capital_auroria":
            province["population"] = 9223372036854775807
            province["recruitable_population"] = 9223372036854775807
    if not _write_json(extreme_quote_path, extreme_document) or \
            not bridge.load_game(extreme_quote_path).get("accepted", false):
        _fail(main_scene, "Could not load the extreme recruitment quote fixture")
        return
    main_scene.call("_refresh_map_data")
    var extreme_quote: Dictionary = main_scene.call(
        "_authoritative_recruitment_quote", "capital_auroria"
    )
    if not extreme_quote.get("accepted", false) or \
            extreme_quote.get("maximum_manpower", 0) != 2305843009213693951 or \
            extreme_quote.get("cost", 0) != 9223372036854775804:
        _fail(main_scene, "Extreme recruitment quote did not retain bridge authority")
        return
    if not bridge.load_game(quick_path).get("accepted", false):
        _fail(main_scene, "Could not restore the quick-load fixture after the extreme quote")
        return
    main_scene.call("_refresh_map_data")

    bridge.clear_army_advance_target(preserved_army_id)
    for order: Dictionary in bridge.get_pending_orders("auroria"):
        bridge.cancel_order(String(order.get("order_id", "")))
    var peace_target: Dictionary = {}
    for _month: int in range(4):
        for target: Dictionary in bridge.get_army_order_targets(preserved_army_id):
            if not target.get("is_attack", true):
                peace_target = target
                break
        if not peace_target.is_empty():
            break
        bridge.advance_turn()
    var peace_origin := String(_army(bridge, preserved_army_id).get("province_id", ""))
    var peace_order: Dictionary = bridge.move_army(
        preserved_army_id, String(peace_target.get("province_id", ""))
    )
    if peace_target.is_empty() or peace_origin.is_empty() or \
            not peace_order.get("accepted", false) or not bridge.save_game(quick_path).get("accepted", false):
        _fail(main_scene, "Could not create the peace cancellation fixture")
        return
    var peace_document := _read_json(quick_path)
    for province: Dictionary in peace_document.get("provinces", []):
        if province.get("id", "") == peace_origin:
            province["owner_id"] = "caelus"
            break
    var occupations: Array = []
    for occupation: Dictionary in peace_document.get("occupations", []):
        if occupation.get("province_id", "") != peace_origin:
            occupations.append(occupation)
    occupations.append({"province_id": peace_origin, "controller_id": "auroria"})
    peace_document["occupations"] = occupations
    var found_peace_relation := false
    for relation: Dictionary in peace_document.get("relations", []):
        var pair := [String(relation.get("country_a", "")), String(relation.get("country_b", ""))]
        if "auroria" in pair and "caelus" in pair:
            relation["status"] = "war"
            found_peace_relation = true
            break
    if not found_peace_relation:
        peace_document["relations"].append({
            "country_a": "auroria", "country_b": "caelus", "status": "war",
        })
    if not _write_json(quick_path, peace_document):
        _fail(main_scene, "Could not write the peace cancellation fixture")
        return
    main_scene.call("_on_quick_load_pressed")
    await process_frame
    navigation.get_node("Margin/Row/Diplomacy").pressed.emit()
    await process_frame
    var diplomacy := pages.get_node("Pages/Diplomacy") as Control
    diplomacy.select_country("caelus")
    diplomacy.get_node("Content/Actions/MakePeace").pressed.emit()
    await process_frame
    var peace_confirmation := main_scene.get_node("Shell/ActionConfirmation") as ConfirmationDialog
    if peace_confirmation == null or not peace_confirmation.visible:
        _fail(main_scene, "Peace intent did not require confirmation")
        return
    peace_confirmation.get_ok_button().pressed.emit()
    await process_frame
    if not bridge.get_pending_orders("auroria").is_empty() or \
            not main_scene._latest_event_message.contains("取消1个行动订单") or \
            not main_scene._latest_event_message.contains("退款") or \
            not main_scene._latest_event_message.contains("退还移动"):
        _fail(main_scene, "Peace cancellation did not refresh orders and both refund dimensions")
        return

    if not bridge.set_ai_enabled(false, "caelus"):
        _fail(main_scene, "Could not switch the saved player identity to Caelus")
        return
    for order: Dictionary in bridge.get_pending_orders("caelus"):
        bridge.cancel_order(String(order.get("order_id", "")))
    var caelus_order: Dictionary = bridge.recruit_army("caelus", "capital_caelus", 1)
    if not caelus_order.get("accepted", false) or not bridge.save_game(quick_path).get("accepted", false):
        _fail(main_scene, "Could not save the Caelus player fixture")
        return
    main_scene.call("_on_quick_load_pressed")
    await process_frame
    if main_scene.player_country_id != "caelus" or \
            main_scene._player_pending_orders().size() != 1 or \
            (main_scene.get_node("Shell/Layout/GlobalStatusBar/Margin/Row/CountryName") as Label).text != "凯洛斯":
        _fail(main_scene, "Quick load did not restore the Caelus player identity")
        return
    diplomacy.select_country("auroria")
    if not diplomacy.get_node("Content/Selection").text.contains("奥罗里亚"):
        _fail(main_scene, "Diplomacy targets did not refresh for the restored Caelus player")
        return
    DirAccess.remove_absolute(extreme_quote_path)
    DirAccess.remove_absolute(quick_path)

    print("Strategic main layout smoke test passed")
    main_scene.free()
    quit(0)
