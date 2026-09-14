extends Control

const QUICK_SAVE_PATH := "user://quick_save.json"
const GameText := preload("res://scripts/ui/game_text_formatter.gd")
const StrategyPresenter := preload("res://scripts/ui/strategy_panel_presenter.gd")
const ProvinceInfoScene := preload("res://scenes/ui/province_info_window.tscn")
const ProvinceManagementScene := preload("res://scenes/ui/province_management_window.tscn")
const RoadConstructionScene := preload("res://scenes/ui/road_construction_window.tscn")

enum WorkspaceMode {
    CLOSED,
    PROVINCE_INFO,
    PROVINCE_MANAGEMENT,
    ROAD_CONSTRUCTION,
}

enum MapInputMode {
    NORMAL,
    ARMY_DESTINATION,
    AUTO_ADVANCE_DESTINATION,
    ROAD_START,
    ROAD_END,
}

@onready var bridge := $SimulationBridge
@onready var global_status_bar := %GlobalStatusBar
@onready var primary_navigation := %PrimaryNavigation
@onready var province_map := %ProvinceMap
@onready var map_hover_tooltip: Label = %MapHoverTooltip
@onready var context_inspector := %ContextInspector
@onready var map_mode_bar := %MapModeBar
@onready var bottom_drawer := %BottomDrawer
@onready var management_page_host := %ManagementPageHost

var player_country_id := "auroria"
var province_by_id: Dictionary = {}
var road_start_id := ""
var road_end_id := ""
var moving_army_id := ""
var movement_origin_id := ""
var movement_destination_id := ""
var auto_advance_target_id := ""
var managed_province_id := ""
var _road_selection_notice := ""
var workspace_mode := WorkspaceMode.CLOSED
var map_input_mode := MapInputMode.NORMAL
var event_history_lines: Array[String] = []
var _notifications: Array[String] = []
var _latest_event_message := ""
var _active_map_mode := "political"
var _game_status_message_key := ""
var province_info_window: Control
var province_management_window: Control
var road_construction_window: Control


func _ready() -> void:
    province_info_window = ProvinceInfoScene.instantiate()
    province_management_window = ProvinceManagementScene.instantiate()
    road_construction_window = RoadConstructionScene.instantiate()
    context_inspector.add_to_group("context_inspector")

    if not province_map.load_grid_layout("res://data/grid_map_layout.json"):
        _set_event_message("地图加载失败：%s" % province_map.geometry_error())
        push_error(province_map.geometry_error())
        return
    var data_directory := ProjectSettings.globalize_path("res://data")
    if not bridge.load_scenario(data_directory, 1000, 1):
        var scenario_error := _scenario_load_failure_text(String(bridge.get_last_error()))
        _set_event_message(scenario_error)
        push_error(scenario_error)
        return

    _connect_strategic_ui()
    _connect_context_intents()
    _refresh_map_data()
    _refresh_strategic_ui()
    _record_event("场景已加载：%d 个地区" % province_by_id.size())


func _exit_tree() -> void:
    for panel: Control in [
        province_info_window, province_management_window, road_construction_window,
    ]:
        if is_instance_valid(panel) and not panel.is_queued_for_deletion():
            panel.free()


func _connect_strategic_ui() -> void:
    global_status_bar.advance_turn_requested.connect(_on_advance_turn_pressed)
    primary_navigation.destination_requested.connect(_on_navigation_requested)
    map_mode_bar.map_mode_requested.connect(_on_map_mode_requested)
    map_mode_bar.drawer_requested.connect(_on_drawer_requested)
    context_inspector.close_requested.connect(_close_workspace)
    bottom_drawer.cancel_order_requested.connect(_on_cancel_order_pressed)
    management_page_host.back_requested.connect(_return_to_map)
    province_map.province_selected.connect(_on_province_selected)
    province_map.province_clicked.connect(_on_province_clicked)
    province_map.province_double_clicked.connect(_on_province_double_clicked)
    province_map.map_blank_clicked.connect(_on_map_blank_clicked)
    province_map.province_hovered.connect(_on_province_hovered)


func _connect_context_intents() -> void:
    province_info_window.manage_requested.connect(_on_manage_province_requested)
    province_management_window.recruit_requested.connect(_on_management_recruit_requested)
    province_management_window.rename_requested.connect(_on_management_rename_requested)
    province_management_window.merge_requested.connect(_on_management_merge_requested)
    province_management_window.army_selected.connect(_on_management_army_selected)
    province_management_window.destination_selection_requested.connect(
        _on_management_destination_requested
    )
    province_management_window.reachable_destination_selected.connect(
        _on_management_reachable_destination_selected
    )
    province_management_window.move_requested.connect(_on_management_move_requested)
    province_management_window.advance_destination_selection_requested.connect(
        _on_management_advance_destination_requested
    )
    province_management_window.auto_advance_requested.connect(
        _on_management_auto_advance_requested
    )
    province_management_window.movement_clear_requested.connect(
        _on_management_movement_clear_requested
    )
    province_management_window.advance_plan_action_requested.connect(
        _on_advance_plan_clicked
    )
    road_construction_window.select_start_requested.connect(
        _on_road_start_selection_requested
    )
    road_construction_window.select_end_requested.connect(_on_road_end_selection_requested)
    road_construction_window.build_requested.connect(_on_build_road_pressed)
    road_construction_window.reset_requested.connect(_on_road_reset_requested)
    road_construction_window.exit_requested.connect(_on_road_exit_requested)

    var pages := management_page_host.get_node("Pages")
    pages.get_node("Diplomacy").declare_war_requested.connect(_on_declare_war_pressed)
    pages.get_node("Diplomacy").make_peace_requested.connect(_on_make_peace_pressed)
    pages.get_node("Technology").research_requested.connect(_on_research_technology)
    pages.get_node("Settings").quick_save_requested.connect(_on_quick_save_pressed)
    pages.get_node("Settings").quick_load_requested.connect(_on_quick_load_pressed)


func active_page_name() -> String:
    return management_page_host.current_page()


func active_drawer_name() -> String:
    return bottom_drawer.current_drawer()


func active_map_mode_name() -> String:
    return _active_map_mode


func workspace_mode_name() -> String:
    match workspace_mode:
        WorkspaceMode.PROVINCE_INFO:
            return "province_summary"
        WorkspaceMode.PROVINCE_MANAGEMENT:
            return "province_management"
        WorkspaceMode.ROAD_CONSTRUCTION:
            return "road_construction"
        _:
            return "closed"


func map_input_mode_name() -> String:
    match map_input_mode:
        MapInputMode.ARMY_DESTINATION:
            return "army_destination"
        MapInputMode.AUTO_ADVANCE_DESTINATION:
            return "auto_advance_destination"
        MapInputMode.ROAD_START:
            return "road_start"
        MapInputMode.ROAD_END:
            return "road_end"
        _:
            return "normal"


func _refresh_strategic_ui() -> void:
    global_status_bar.set_snapshot(_player_country_summary(), bridge.get_current_date())
    map_mode_bar.set_counts(_player_pending_orders().size(), _notifications.size())
    map_mode_bar.set_active_mode(_active_map_mode)
    global_status_bar.set_advance_enabled(true)
    _refresh_active_context()
    _refresh_active_management_page()
    _refresh_game_status_feedback()


func _game_status_message(status: Dictionary) -> String:
    if not status.get("has_scenario", false):
        return "当前没有已加载的场景"
    if status.get("player_won", false):
        return "胜利：%s已经控制世界" % _country_name(player_country_id)
    if status.get("player_eliminated", false):
        return "失败：%s已经灭亡" % _country_name(player_country_id)
    var winner_id := String(status.get("winner_id", ""))
    if not winner_id.is_empty():
        return "胜利国家：%s" % _country_name(winner_id)
    var surviving_countries := 0
    for country: Dictionary in status.get("countries", []):
        if not country.get("eliminated", false):
            surviving_countries += 1
    return "存续国家：%d" % surviving_countries


func _refresh_game_status_feedback() -> void:
    var message := _game_status_message(bridge.get_game_status(player_country_id))
    if message == _game_status_message_key:
        return
    _game_status_message_key = message
    _record_event(message)


func _refresh_active_context() -> void:
    match workspace_mode:
        WorkspaceMode.PROVINCE_INFO:
            var province: Dictionary = province_by_id.get(managed_province_id, {})
            if province.is_empty():
                _close_workspace()
            else:
                _show_province_summary(province)
        WorkspaceMode.PROVINCE_MANAGEMENT:
            _refresh_management_window(moving_army_id)
        WorkspaceMode.ROAD_CONSTRUCTION:
            _refresh_road_workspace_state()


func _refresh_active_management_page() -> void:
    var page := active_page_name()
    if page == "closed":
        return
    var pages := management_page_host.get_node("Pages")
    var country := _player_country_summary()
    match page:
        "country":
            pages.get_node("Country").set_snapshot(country, _country_totals())
        "diplomacy":
            pages.get_node("Diplomacy").set_snapshot(
                player_country_id,
                bridge.get_country_summaries(),
                bridge.get_war_summaries()
            )
        "technology":
            pages.get_node("Technology").set_snapshot(
                _player_technology(), _player_pending_orders(), _player_treasury()
            )
        "military":
            pages.get_node("Military").set_snapshot(
                _player_army_rows(), _player_order_rows()
            )
        "economy":
            pages.get_node("Economy").set_snapshot(
                country, _controlled_provinces()
            )
        "settings":
            pages.get_node("Settings").set_build_info(
                bridge.get_core_version(), _quick_save_count()
            )


func _on_navigation_requested(destination: String) -> void:
    bottom_drawer.close()
    _close_workspace()
    if destination == "map":
        _return_to_map()
        return
    management_page_host.open_page(destination)
    _refresh_active_management_page()


func _return_to_map() -> void:
    management_page_host.close_page()
    primary_navigation.set_active_destination("map")


func _on_map_mode_requested(mode: String) -> void:
    _active_map_mode = mode
    map_mode_bar.set_active_mode(mode)
    if mode == "roads":
        if active_page_name() != "closed":
            _return_to_map()
        _open_road_construction()
    elif workspace_mode == WorkspaceMode.ROAD_CONSTRUCTION:
        _close_workspace()


func _on_drawer_requested(drawer: String) -> void:
    if bottom_drawer.current_drawer() == drawer:
        bottom_drawer.close()
        return
    if active_page_name() != "closed":
        _return_to_map()
    match drawer:
        "orders":
            bottom_drawer.set_order_lookups(
                _province_name_lookup(), _country_name_lookup()
            )
            bottom_drawer.show_orders(_player_pending_orders())
        "notifications":
            bottom_drawer.show_notifications(_notifications)
        "turn_report":
            bottom_drawer.show_turn_report("\n".join(event_history_lines))


func _open_workspace(mode: WorkspaceMode, title: String) -> void:
    workspace_mode = mode
    if mode != WorkspaceMode.PROVINCE_MANAGEMENT:
        moving_army_id = "" if mode == WorkspaceMode.PROVINCE_INFO else moving_army_id
    match mode:
        WorkspaceMode.PROVINCE_INFO:
            context_inspector.show_panel("province_summary", title, province_info_window)
        WorkspaceMode.PROVINCE_MANAGEMENT:
            context_inspector.show_panel("province_management", title, province_management_window)
        WorkspaceMode.ROAD_CONSTRUCTION:
            context_inspector.show_panel("road_construction", title, road_construction_window)


func _close_workspace() -> void:
    workspace_mode = WorkspaceMode.CLOSED
    map_input_mode = MapInputMode.NORMAL
    managed_province_id = ""
    province_info_window.clear()
    province_management_window.clear()
    road_construction_window.clear()
    road_start_id = ""
    road_end_id = ""
    province_map.set_auto_advance_path([])
    province_map.set_road_selection("", "")
    context_inspector.show_empty(_empty_inspector_message())


func _close_transient_workspace() -> void:
    if workspace_mode == WorkspaceMode.PROVINCE_INFO:
        _close_workspace()


func _empty_inspector_message() -> String:
    return "请选择地区查看摘要，双击地区进行管理"


func _on_province_clicked(province_id: String) -> void:
    if map_input_mode != MapInputMode.NORMAL or workspace_mode == WorkspaceMode.ROAD_CONSTRUCTION:
        return
    var province: Dictionary = province_by_id.get(province_id, {})
    if province.is_empty():
        return
    managed_province_id = province_id
    _open_workspace(WorkspaceMode.PROVINCE_INFO, "地区摘要")
    _show_province_summary(province)


func _show_province_summary(province: Dictionary) -> void:
    province_info_window.display_province(
        province,
        bridge.get_army_summaries(),
        bridge.get_road_summaries(),
        province_by_id,
        bridge.get_country_summaries()
    )


func _on_manage_province_requested(province_id: String) -> void:
    _on_province_double_clicked(province_id)


func _on_province_double_clicked(province_id: String) -> void:
    if map_input_mode != MapInputMode.NORMAL or workspace_mode == WorkspaceMode.ROAD_CONSTRUCTION:
        return
    if not province_by_id.has(province_id):
        return
    managed_province_id = province_id
    _open_workspace(WorkspaceMode.PROVINCE_MANAGEMENT, "地区管理")
    _refresh_management_window()


func _on_map_blank_clicked() -> void:
    if map_input_mode == MapInputMode.NORMAL:
        _close_transient_workspace()


func _refresh_management_window(preferred_army_id := "", status_message := "") -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT or managed_province_id.is_empty():
        return
    var province: Dictionary = province_by_id.get(managed_province_id, {})
    if province.is_empty():
        _close_workspace()
        return
    province_management_window.display_province(
        province,
        bridge.get_army_summaries(),
        player_country_id,
        preferred_army_id,
        _player_treasury(),
        _authoritative_recruitment_quote(managed_province_id)
    )
    province_management_window.set_pending_orders(_player_pending_orders())
    var selected_army_id := preferred_army_id
    if selected_army_id.is_empty():
        for army: Dictionary in bridge.get_army_summaries():
            if String(army.get("owner_id", "")) == player_country_id and \
                    String(army.get("province_id", "")) == managed_province_id:
                selected_army_id = String(army.get("id", ""))
                break
    if not selected_army_id.is_empty():
        _select_army(selected_army_id)
    else:
        _clear_local_managed_army_state()
    _refresh_advance_plans()
    _refresh_management_action_state()
    if not status_message.is_empty():
        province_management_window.set_status(status_message)


func _player_country_summary() -> Dictionary:
    var country: Dictionary = {}
    for value: Dictionary in bridge.get_country_summaries():
        if String(value.get("id", "")) == player_country_id:
            country = value.duplicate(true)
            break
    country["recruitable_population"] = _country_totals().get("recruitable_population", 0)
    var technology := _player_technology()
    for key: String in ["economy_level", "military_level", "roads_level"]:
        country[key] = technology.get(key, 0)
    return country


func _country_totals() -> Dictionary:
    var totals := {"population": 0, "recruitable_population": 0, "controlled_provinces": 0}
    for province: Dictionary in bridge.get_province_summaries():
        if String(province.get("owner_id", "")) != player_country_id:
            continue
        totals["population"] += int(province.get("population", 0))
        totals["recruitable_population"] += int(province.get("recruitable_population", 0))
        totals["controlled_provinces"] += 1
    return totals


func _controlled_provinces() -> Array:
    var provinces: Array = []
    for province: Dictionary in bridge.get_province_summaries():
        if String(province.get("owner_id", "")) == player_country_id:
            provinces.append(province.duplicate(true))
    return provinces


func _player_treasury() -> int:
    return int(_player_country_summary().get("treasury", 0))


func _player_pending_orders() -> Array:
    return bridge.get_pending_orders(player_country_id)


func _authoritative_recruitment_quote(province_id: String) -> Dictionary:
    var province: Dictionary = province_by_id.get(province_id, {})
    var high := maxi(0, int(province.get("recruitable_population", 0)))
    var low := 0
    var best: Dictionary = {}
    var maximum_manpower := 0
    while low <= high:
        var candidate := low + int((high - low) / 2)
        var quote: Dictionary = bridge.get_recruitment_order_quote(
            player_country_id, province_id, candidate
        )
        if quote.get("accepted", false):
            best = quote
            maximum_manpower = candidate
            low = candidate + 1
        else:
            high = candidate - 1
    if maximum_manpower <= 0:
        return {"accepted": false, "maximum_manpower": 0, "cost": 0}
    if best.is_empty() or int(best.get("manpower", 0)) != maximum_manpower:
        best = bridge.get_recruitment_order_quote(player_country_id, province_id, maximum_manpower)
    best["maximum_manpower"] = maximum_manpower
    return best


func _localized_failure(result: Dictionary, fallback := "未知错误") -> String:
    return GameText.order_failure_reason(String(result.get("error", fallback)))


func _scenario_load_failure_text(reason: String) -> String:
    return "场景加载失败：%s" % GameText.order_failure_reason(reason)


func _refresh_pending_orders() -> void:
    global_status_bar.set_snapshot(_player_country_summary(), bridge.get_current_date())
    map_mode_bar.set_counts(_player_pending_orders().size(), _notifications.size())
    if workspace_mode == WorkspaceMode.PROVINCE_MANAGEMENT:
        province_management_window.set_pending_orders(_player_pending_orders())
        _refresh_management_action_state()
    elif workspace_mode == WorkspaceMode.ROAD_CONSTRUCTION:
        _refresh_road_workspace_state()
    if bottom_drawer.current_drawer() == "orders":
        bottom_drawer.set_order_lookups(_province_name_lookup(), _country_name_lookup())
        bottom_drawer.show_orders(_player_pending_orders())
    if active_page_name() != "closed":
        _refresh_active_management_page()


func _on_cancel_order_pressed(order_id: String) -> void:
    if order_id.is_empty():
        return
    var result: Dictionary = bridge.cancel_order(order_id)
    if not result.get("accepted", false):
        var message := "取消订单失败：%s" % _localized_failure(result)
        _record_event(message)
        _show_context_status(message)
        bottom_drawer.show_notifications(_notifications)
        return
    var message := "订单已取消"
    var refunded_cost := int(result.get("refunded_cost", 0))
    var refunded_movement_half := int(result.get("refunded_movement_half", 0))
    if refunded_cost > 0:
        message += "，退款%d" % refunded_cost
    if refunded_movement_half > 0:
        message += "，退还移动%s" % GameText.movement_points(float(refunded_movement_half) / 2.0)
    if refunded_cost == 0 and refunded_movement_half == 0:
        message += "，无退款"
    _record_event(message)
    _refresh_map_data()
    _refresh_pending_orders()


func _on_management_recruit_requested(province_id: String, manpower: int) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT or province_id != managed_province_id:
        return
    var quote: Dictionary = bridge.get_recruitment_order_quote(player_country_id, province_id, manpower)
    if not quote.get("accepted", false):
        _show_context_status("招募失败：%s" % _localized_failure(quote))
        return
    var result: Dictionary = bridge.recruit_army(player_country_id, province_id, manpower)
    if not result.get("accepted", false):
        _show_context_status("招募失败：%s" % _localized_failure(result))
        return
    _record_event("征兵订单已创建：%s，预留%d人，预付%d，剩余%d个月" % [
        _province_name(province_id), result.get("manpower", manpower),
        result.get("cost", 0), result.get("remaining_months", 1),
    ])
    _refresh_map_data()
    _refresh_pending_orders()
    _refresh_management_window("", "订单已创建：征兵将在下月项目阶段完成")


func _on_management_rename_requested(army_id: String, formation_number: int) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT:
        return
    var result: Dictionary = bridge.rename_army(army_id, formation_number)
    if not result.get("accepted", false):
        _show_context_status("更名失败：%s" % _localized_failure(result))
        return
    _record_event("军队已更名为%s" % String(result.get("display_name", "该军队")))
    _refresh_map_data()
    _refresh_management_window(army_id, _latest_event_message)


func _on_management_merge_requested(primary_army_id: String, merged_army_ids: Array) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT:
        return
    var result: Dictionary = bridge.merge_armies(primary_army_id, merged_army_ids)
    if not result.get("accepted", false):
        _show_context_status("合并失败：%s" % _localized_failure(result))
        return
    var primary := _find_army_by_id(primary_army_id)
    _record_event("%s完成合并，现有兵力%d" % [
        String(primary.get("display_name", "该军队")), result.get("current_manpower", 0),
    ])
    moving_army_id = primary_army_id
    _refresh_map_data()
    _refresh_management_window(primary_army_id, _latest_event_message)


func _on_management_army_selected(army_id: String) -> void:
    if workspace_mode == WorkspaceMode.PROVINCE_MANAGEMENT:
        _select_army(army_id)


func _on_management_destination_requested(army_id: String) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT:
        return
    _select_army(army_id)
    if moving_army_id != army_id:
        _show_context_status("无法选择该军队")
        return
    map_input_mode = MapInputMode.ARMY_DESTINATION
    _show_context_status("请在地图上点击列表中的可达目的地")


func _on_management_reachable_destination_selected(army_id: String, destination_id: String) -> void:
    if workspace_mode == WorkspaceMode.PROVINCE_MANAGEMENT and army_id == moving_army_id:
        _apply_management_order_destination(destination_id)


func _available_order_targets(army_id: String) -> Array:
    var targets: Array = []
    if army_id.is_empty():
        return targets
    for value: Dictionary in bridge.get_army_order_targets(army_id):
        var target := value.duplicate(true)
        target["province_name"] = _province_name(String(target.get("province_id", "")))
        targets.append(target)
    return targets


func _find_order_target(army_id: String, destination_id: String) -> Dictionary:
    for target: Dictionary in _available_order_targets(army_id):
        if String(target.get("province_id", "")) == destination_id:
            return target
    return {}


func _apply_management_order_destination(destination_id: String) -> void:
    var target := _find_order_target(moving_army_id, destination_id)
    if target.is_empty():
        _show_context_status("该地区不在当前权威可达目标中")
        return
    movement_destination_id = destination_id
    auto_advance_target_id = ""
    bridge.clear_army_advance_target(moving_army_id)
    map_input_mode = MapInputMode.NORMAL
    province_management_window.set_destination(
        destination_id, String(target.get("province_name", "未知地区")),
        target.get("movement_cost", 0), target.get("is_attack", false)
    )
    _show_context_status("%s目标已选择，可创建订单" % (
        "进攻" if target.get("is_attack", false) else "调动"
    ))
    _refresh_management_action_state()


func _on_management_advance_destination_requested(army_id: String) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT:
        return
    _select_army(army_id)
    if moving_army_id != army_id:
        _show_context_status("无法选择该军队")
        return
    map_input_mode = MapInputMode.AUTO_ADVANCE_DESTINATION
    _show_context_status("请在地图上点击推进目标")


func _select_management_destination(province_id: String) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT or moving_army_id.is_empty():
        map_input_mode = MapInputMode.NORMAL
        return
    if province_id.is_empty() or province_id == movement_origin_id:
        _show_context_status("目的地必须是其他地区")
        return
    _apply_management_order_destination(province_id)


func _select_management_advance_target(province_id: String) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT or moving_army_id.is_empty():
        map_input_mode = MapInputMode.NORMAL
        return
    if province_id.is_empty() or province_id == movement_origin_id:
        _show_context_status("推进目标必须是其他地区")
        return
    var result: Dictionary = bridge.set_army_advance_target(moving_army_id, province_id)
    if not result.get("accepted", false):
        _show_context_status("设置推进目标失败：%s" % _localized_failure(result))
        return
    auto_advance_target_id = province_id
    movement_destination_id = ""
    map_input_mode = MapInputMode.NORMAL
    _refresh_advance_plans()
    _refresh_management_action_state()
    _show_context_status("推进目标已设置")


func _on_management_move_requested(army_id: String, destination_id: String) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT or army_id != moving_army_id or \
            destination_id != movement_destination_id:
        return
    var result: Dictionary = bridge.move_army(army_id, destination_id)
    if not result.get("accepted", false):
        _show_context_status("调动失败：%s" % _localized_failure(result))
        return
    _record_event("%s订单已创建：%s → %s，预留移动%s，剩余%d个月" % [
        "进攻" if result.get("is_attack", false) else "调动",
        _province_name(String(result.get("origin", movement_origin_id))),
        _province_name(String(result.get("destination", destination_id))),
        GameText.movement_points(result.get("movement_cost", 0)),
        result.get("remaining_months", 1),
    ])
    bridge.clear_army_advance_target(army_id)
    movement_destination_id = ""
    auto_advance_target_id = ""
    map_input_mode = MapInputMode.NORMAL
    _refresh_map_data()
    _refresh_pending_orders()
    _refresh_management_window(army_id, "订单已创建：将在下月军事阶段执行")


func _on_management_auto_advance_requested(army_id: String, target_id: String) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT or army_id != moving_army_id or target_id.is_empty():
        return
    var result: Dictionary = bridge.auto_advance_army_to(army_id, target_id)
    if not result.get("accepted", false):
        _show_context_status("自动推进失败：%s" % _localized_failure(result))
        return
    _record_event("自动推进订单已创建：目标%s，预留移动%s" % [
        _province_name(String(result.get("destination", target_id))),
        GameText.movement_points(result.get("movement_cost", 0)),
    ])
    movement_destination_id = ""
    map_input_mode = MapInputMode.NORMAL
    _refresh_map_data()
    _refresh_pending_orders()
    _refresh_management_window(army_id, "订单已创建：自动推进将在下月军事阶段执行")


func _on_management_movement_clear_requested(army_id: String) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT or army_id != moving_army_id:
        return
    movement_destination_id = ""
    map_input_mode = MapInputMode.NORMAL
    province_management_window.set_destination("", "")
    _show_context_status("已清除临时移动选择")
    _refresh_management_action_state()


func _open_road_construction() -> void:
    if _player_treasury() < 0:
        _record_event("国库负债：不能创建修路订单")
        return
    _clear_road_selection()
    _road_selection_notice = ""
    map_input_mode = MapInputMode.NORMAL
    _open_workspace(WorkspaceMode.ROAD_CONSTRUCTION, "道路规划")
    road_construction_window.open_window()


func _on_road_start_selection_requested() -> void:
    if workspace_mode != WorkspaceMode.ROAD_CONSTRUCTION:
        return
    _clear_road_selection()
    _road_selection_notice = ""
    map_input_mode = MapInputMode.ROAD_START
    road_construction_window.reset_selection("请在地图上选择由你控制的道路起点")


func _on_road_end_selection_requested() -> void:
    if workspace_mode != WorkspaceMode.ROAD_CONSTRUCTION:
        return
    if road_start_id.is_empty():
        road_construction_window.set_status("请先选择道路起点")
        return
    road_end_id = ""
    map_input_mode = MapInputMode.ROAD_END
    road_construction_window.set_start(_province_name(road_start_id))
    road_construction_window.set_status("请在地图上选择相邻的道路终点")


func _on_road_reset_requested() -> void:
    if workspace_mode != WorkspaceMode.ROAD_CONSTRUCTION:
        return
    _clear_road_selection()
    _road_selection_notice = ""
    map_input_mode = MapInputMode.NORMAL
    road_construction_window.reset_selection("道路选择已重置")


func _on_road_exit_requested() -> void:
    _active_map_mode = "political"
    map_mode_bar.set_active_mode(_active_map_mode)
    _close_workspace()


func _select_road_endpoint(province_id: String) -> void:
    if workspace_mode != WorkspaceMode.ROAD_CONSTRUCTION:
        map_input_mode = MapInputMode.NORMAL
        return
    var province: Dictionary = province_by_id.get(province_id, {})
    if province.is_empty():
        road_construction_window.set_status("请选择一个有效地区")
        return
    if String(province.get("owner_id", "")) != player_country_id:
        road_construction_window.set_status("道路端点必须由玩家实际控制")
        return
    if map_input_mode == MapInputMode.ROAD_START:
        road_start_id = province_id
        road_end_id = ""
        _road_selection_notice = ""
        map_input_mode = MapInputMode.NORMAL
        province_map.set_road_selection(road_start_id, "")
        road_construction_window.set_start(_province_name(province_id))
        return
    if map_input_mode != MapInputMode.ROAD_END:
        return
    if road_start_id.is_empty() or province_id == road_start_id:
        road_construction_window.set_status("道路终点不能与起点相同")
        return
    if not _are_provinces_adjacent(road_start_id, province_id):
        road_construction_window.set_status("道路终点必须与起点相邻")
        return
    if _road_connection_exists(road_start_id, province_id):
        road_construction_window.set_status("这两个地区之间已经存在公路")
        return
    road_end_id = province_id
    _road_selection_notice = ""
    map_input_mode = MapInputMode.NORMAL
    province_map.set_road_selection(road_start_id, road_end_id)
    var quote: Dictionary = bridge.get_road_order_quote(player_country_id, road_start_id, road_end_id)
    var accepted := bool(quote.get("accepted", false))
    road_construction_window.set_end_province(
        _province_name(province_id), int(quote.get("cost", 0)), accepted,
        "路线合法，可以创建修路订单" if accepted else "当前无法下单：%s" % \
            _localized_failure(quote)
    )


func _on_build_road_pressed() -> void:
    if road_start_id.is_empty() or road_end_id.is_empty():
        _show_context_status("请先选择道路起点和终点")
        return
    var result: Dictionary = bridge.build_road(player_country_id, road_start_id, road_end_id)
    if not result.get("accepted", false):
        _show_context_status("修路失败：%s" % _localized_failure(result))
        return
    _record_event("修路订单已创建：%s → %s，预付%d，剩余%d个月" % [
        _province_name(road_start_id), _province_name(road_end_id),
        result.get("cost", 0), result.get("remaining_months", 1),
    ])
    _refresh_pending_orders()
    _clear_road_selection()
    if workspace_mode == WorkspaceMode.ROAD_CONSTRUCTION:
        road_construction_window.reset_selection("已下单，道路将在下月项目阶段完成")


func _are_provinces_adjacent(origin_id: String, target_id: String) -> bool:
    var origin: Dictionary = province_by_id.get(origin_id, {})
    for neighbor_id: Variant in origin.get("neighbors", []):
        if String(neighbor_id) == target_id:
            return true
    return false


func _road_connection_exists(province_a: String, province_b: String) -> bool:
    for road: Dictionary in bridge.get_road_summaries():
        var first := String(road.get("province_a", ""))
        var second := String(road.get("province_b", ""))
        if (first == province_a and second == province_b) or (first == province_b and second == province_a):
            return true
    return false


func _clear_road_selection() -> void:
    road_start_id = ""
    road_end_id = ""
    if map_input_mode in [MapInputMode.ROAD_START, MapInputMode.ROAD_END]:
        map_input_mode = MapInputMode.NORMAL
    province_map.set_road_selection("", "")


func _refresh_road_workspace_state() -> void:
    if workspace_mode != WorkspaceMode.ROAD_CONSTRUCTION:
        return
    if road_start_id.is_empty():
        road_construction_window.reset_selection(
            _road_selection_notice if not _road_selection_notice.is_empty() else \
                ("国库负债：不能创建修路订单" if _player_treasury() < 0 else "请选择道路起点")
        )
        return
    var start: Dictionary = province_by_id.get(road_start_id, {})
    if start.is_empty() or String(start.get("owner_id", "")) != player_country_id:
        _clear_road_selection()
        _road_selection_notice = "原道路起点已失效或不再由玩家实际控制"
        road_construction_window.reset_selection(_road_selection_notice)
        return
    if road_end_id.is_empty():
        road_construction_window.set_start(_province_name(road_start_id))
        return
    var end: Dictionary = province_by_id.get(road_end_id, {})
    if end.is_empty() or String(end.get("owner_id", "")) != player_country_id:
        _clear_road_selection()
        _road_selection_notice = "原道路终点已失效或不再由玩家实际控制"
        road_construction_window.reset_selection(_road_selection_notice)
        return
    if not _are_provinces_adjacent(road_start_id, road_end_id):
        _clear_road_selection()
        _road_selection_notice = "原道路端点已不再相邻"
        road_construction_window.reset_selection(_road_selection_notice)
        return
    if _road_connection_exists(road_start_id, road_end_id):
        _clear_road_selection()
        _road_selection_notice = "这两个地区之间已经存在公路，原路线已清除"
        road_construction_window.reset_selection(_road_selection_notice)
        return
    var quote: Dictionary = bridge.get_road_order_quote(player_country_id, road_start_id, road_end_id)
    var accepted := bool(quote.get("accepted", false))
    road_construction_window.set_end_province(
        _province_name(road_end_id), int(quote.get("cost", 0)), accepted,
        "路线合法，可以创建修路订单" if accepted else "当前无法下单：%s" % _localized_failure(quote)
    )


func _on_declare_war_pressed(defender_id: String) -> void:
    if defender_id.is_empty():
        return
    var result: Dictionary = bridge.declare_war(player_country_id, defender_id)
    if not result.get("accepted", false):
        _record_event("宣战失败：%s" % _localized_failure(result))
        return
    _record_event("%s 向 %s 宣战" % [
        _country_name(String(result.get("aggressor_id", player_country_id))),
        _country_name(String(result.get("defender_id", defender_id))),
    ])
    _refresh_map_data()
    _refresh_strategic_ui()


func _on_make_peace_pressed(other_country_id: String, annex: bool) -> void:
    if other_country_id.is_empty():
        return
    var result: Dictionary = bridge.make_peace(player_country_id, other_country_id, annex)
    if not result.get("accepted", false):
        _record_event("议和失败：%s" % _localized_failure(result))
        return
    var message := "和平协议达成：处理%d个地区，遣返%d支军队" % [
        result.get("provinces", []).size(), result.get("armies", []).size(),
    ]
    var cancelled_orders: Array = result.get("cancelled_orders", [])
    if not cancelled_orders.is_empty():
        var refunded_cost := 0
        var refunded_movement_half := 0
        for cancellation: Dictionary in cancelled_orders:
            refunded_cost += int(cancellation.get("refunded_cost", 0))
            refunded_movement_half += int(cancellation.get("refunded_movement_half", 0))
        message += "；取消%d个行动订单，退款%d，退还移动%s" % [
            cancelled_orders.size(), refunded_cost,
            GameText.movement_points(float(refunded_movement_half) / 2.0),
        ]
    _record_event(message)
    _clear_movement_selection()
    _refresh_map_data()
    _refresh_strategic_ui()
    _refresh_pending_orders()


func _on_research_technology(track: String) -> void:
    var result: Dictionary = bridge.research_technology(player_country_id, track)
    if not result.get("accepted", false):
        _record_event("科技研究失败：%s" % _localized_failure(result))
        return
    _record_event("研究订单已创建：%s → %d级，预付%d，剩余%d个月" % [
        GameText.technology_track_name(track), result.get("target_level", result.get("current_level", 0)),
        result.get("cost", 0), result.get("remaining_months", 0),
    ])
    _refresh_pending_orders()
    _refresh_active_management_page()


func _player_technology() -> Dictionary:
    for technology: Dictionary in bridge.get_technology_summaries():
        if String(technology.get("country_id", "")) == player_country_id:
            return technology
    return {}


func _on_quick_save_pressed() -> void:
    var result: Dictionary = bridge.save_game(ProjectSettings.globalize_path(QUICK_SAVE_PATH))
    if not result.get("accepted", false):
        _record_event("保存失败：%s" % _localized_failure(result))
        return
    _record_event("游戏已保存")
    _refresh_active_management_page()


func _on_quick_load_pressed() -> void:
    var result: Dictionary = bridge.load_game(ProjectSettings.globalize_path(QUICK_SAVE_PATH))
    if not result.get("accepted", false):
        _record_event("读取失败：%s" % _localized_failure(result))
        return
    player_country_id = String(result.get("player_country_id", player_country_id))
    _game_status_message_key = ""
    _clear_local_managed_army_state()
    _clear_road_selection()
    _close_workspace()
    _refresh_map_data()
    _refresh_strategic_ui()
    _record_event("已读取快速存档并恢复玩家身份")


func _quick_save_count() -> int:
    return 1 if FileAccess.file_exists(ProjectSettings.globalize_path(QUICK_SAVE_PATH)) else 0


func _refresh_map_data() -> void:
    var provinces: Array = bridge.get_province_summaries()
    var countries: Array = bridge.get_country_summaries()
    province_by_id.clear()
    for province: Dictionary in provinces:
        province_by_id[String(province.get("id", ""))] = province
    province_map.set_scenario_data(provinces, countries)
    province_map.set_roads(bridge.get_road_summaries())
    province_map.set_frontlines(bridge.get_frontline_edges())
    province_map.set_armies(bridge.get_army_summaries())
    if workspace_mode == WorkspaceMode.ROAD_CONSTRUCTION:
        _refresh_road_workspace_state()


func _select_army(army_id: String) -> void:
    var army := _find_army_by_id(army_id)
    if army.is_empty():
        return
    moving_army_id = army_id
    movement_origin_id = String(army.get("province_id", ""))
    movement_destination_id = ""
    auto_advance_target_id = String(army.get("advance_target_id", ""))
    _refresh_management_action_state()


func _find_army_by_id(army_id: String) -> Dictionary:
    for army: Dictionary in bridge.get_army_summaries():
        if String(army.get("id", "")) == army_id:
            return army
    return {}


func _refresh_advance_plans() -> void:
    if workspace_mode == WorkspaceMode.PROVINCE_MANAGEMENT:
        province_management_window.set_advance_plans(StrategyPresenter.advance_plans(
            bridge, bridge.get_army_summaries(), province_by_id, player_country_id, 1
        ))


func _on_advance_plan_clicked(meta: Variant) -> void:
    var command := String(meta)
    if command.is_empty():
        return
    var parts := command.split(":")
    if parts.size() < 2:
        return
    var army_id := String(parts[1])
    var result: Dictionary = {}
    if command.begins_with("clear:"):
        result = bridge.clear_army_advance_target(army_id)
    elif command.begins_with("pause:") or command.begins_with("resume:"):
        result = bridge.set_army_advance_enabled(army_id, command.begins_with("resume:"))
    elif command.begins_with("strategy:") and parts.size() == 3:
        result = bridge.set_army_advance_strategy(army_id, String(parts[2]))
    elif command.begins_with("select:"):
        var army := _find_army_by_id(army_id)
        if not army.is_empty():
            managed_province_id = String(army.get("province_id", ""))
            _open_workspace(WorkspaceMode.PROVINCE_MANAGEMENT, "地区管理")
            _refresh_management_window(army_id)
        return
    else:
        return
    if not result.get("accepted", false):
        _show_context_status("推进计划操作失败：%s" % _localized_failure(result))
        return
    _record_event("已更新%s的推进计划" % String(_find_army_by_id(army_id).get("display_name", "该军队")))
    _refresh_map_data()
    _refresh_management_window(army_id, _latest_event_message)


func _on_advance_turn_pressed() -> void:
    _close_transient_workspace()
    var result: Dictionary = bridge.advance_turn()
    if not result.get("accepted", false):
        _record_event("命令被拒绝：%s" % _localized_failure(result))
        return
    _refresh_map_data()
    var total_income := 0
    for income: Dictionary in result.get("fiscal_incomes", []):
        total_income += int(income.get("amount", 0))
    var total_growth := 0
    for change: Dictionary in result.get("population_changes", []):
        total_growth += int(change.get("growth", 0))
    _record_turn_actions(result.get("turn_actions", result.get("ai_actions", [])))
    _record_event("推进%d个月，财政收入%d，人口增长%d" % [
        result.get("elapsed_months", 1), total_income, total_growth,
    ])
    _refresh_strategic_ui()
    _refresh_pending_orders()


func _on_province_selected(province_id: String) -> void:
    if map_input_mode == MapInputMode.ARMY_DESTINATION:
        _select_management_destination(province_id)
    elif map_input_mode == MapInputMode.AUTO_ADVANCE_DESTINATION:
        _select_management_advance_target(province_id)
    elif map_input_mode in [MapInputMode.ROAD_START, MapInputMode.ROAD_END]:
        _select_road_endpoint(province_id)


func _on_province_hovered(province_id: String) -> void:
    map_hover_tooltip.text = "" if province_id.is_empty() else _province_name(province_id)


func _clear_movement_selection() -> void:
    if not moving_army_id.is_empty():
        bridge.clear_army_advance_target(moving_army_id)
    _clear_local_managed_army_state()
    _refresh_advance_plans()
    _refresh_management_action_state()


func _clear_local_managed_army_state() -> void:
    moving_army_id = ""
    movement_origin_id = ""
    movement_destination_id = ""
    auto_advance_target_id = ""
    map_input_mode = MapInputMode.NORMAL
    province_map.set_auto_advance_path([])


func _refresh_movement_preview() -> bool:
    province_map.set_auto_advance_path([])
    if moving_army_id.is_empty() or auto_advance_target_id.is_empty():
        return false
    var path_preview: Dictionary = bridge.get_auto_advance_path_for_months(
        moving_army_id, auto_advance_target_id, 1
    )
    if not path_preview.get("accepted", false):
        return false
    province_map.set_auto_advance_paths(
        path_preview.get("path", []), path_preview.get("preview_path", []),
        String(path_preview.get("preview_stop_reason", "unknown"))
    )
    return int(path_preview.get("step_count", 0)) > 0


func _refresh_management_action_state() -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT:
        return
    var reachable_targets := _available_order_targets(moving_army_id)
    province_management_window.set_reachable_targets(reachable_targets)
    if not movement_destination_id.is_empty():
        var selected_target := _find_order_target(moving_army_id, movement_destination_id)
        if selected_target.is_empty():
            movement_destination_id = ""
            province_management_window.set_destination("", "")
        else:
            province_management_window.set_destination(
                movement_destination_id, String(selected_target.get("province_name", "未知地区")),
                selected_target.get("movement_cost", 0), selected_target.get("is_attack", false)
            )
    province_management_window.set_action_state(
        not moving_army_id.is_empty() and not movement_destination_id.is_empty(),
        not reachable_targets.is_empty() and _refresh_movement_preview()
    )
    province_management_window.set_advance_target(auto_advance_target_id, _province_name(auto_advance_target_id))


func _record_turn_actions(actions: Array) -> void:
    for action: Dictionary in actions:
        var report := GameText.turn_action_report(action, province_by_id)
        if not report.is_empty():
            _record_event(report)


func _set_event_message(message: String) -> void:
    _latest_event_message = message


func _record_event(message: String) -> void:
    if message.is_empty():
        return
    _set_event_message(message)
    event_history_lines.append(message)
    _notifications.append(message)
    while event_history_lines.size() > 80:
        event_history_lines.pop_front()
    while _notifications.size() > 20:
        _notifications.pop_front()
    map_mode_bar.set_counts(_player_pending_orders().size(), _notifications.size())
    if bottom_drawer.current_drawer() == "notifications":
        bottom_drawer.show_notifications(_notifications)
    elif bottom_drawer.current_drawer() == "turn_report":
        bottom_drawer.show_turn_report("\n".join(event_history_lines))


func _unhandled_key_input(event: InputEvent) -> void:
    if not event.is_action_pressed("ui_cancel"):
        return
    if bottom_drawer.current_drawer() != "closed":
        bottom_drawer.close()
    elif workspace_mode == WorkspaceMode.ROAD_CONSTRUCTION:
        _on_road_exit_requested()
    elif map_input_mode != MapInputMode.NORMAL:
        map_input_mode = MapInputMode.NORMAL
        _refresh_management_action_state()
        _show_context_status("已退出地图目标选择")
    else:
        _on_navigation_requested("settings")
    get_viewport().set_input_as_handled()


func _show_context_status(message: String) -> void:
    _set_event_message(message)
    if workspace_mode == WorkspaceMode.PROVINCE_MANAGEMENT:
        province_management_window.set_status(message)
    elif workspace_mode == WorkspaceMode.ROAD_CONSTRUCTION:
        road_construction_window.set_status(message)


func _country_name(country_id: String) -> String:
    var country: Dictionary = _country_name_lookup().get(country_id, {})
    var name := String(country.get("name", ""))
    return name if not name.is_empty() else "未知国家"


func _province_name(province_id: String) -> String:
    var province: Dictionary = province_by_id.get(province_id, {})
    var name := String(province.get("name", ""))
    return name if not name.is_empty() else "未知地区"


func _province_name_lookup() -> Dictionary:
    return province_by_id.duplicate(true)


func _country_name_lookup() -> Dictionary:
    var countries: Dictionary = {}
    for country: Dictionary in bridge.get_country_summaries():
        countries[String(country.get("id", ""))] = country.duplicate(true)
    return countries


func _player_army_rows() -> Array:
    var rows: Array = []
    for army: Dictionary in bridge.get_army_summaries():
        if String(army.get("owner_id", "")) != player_country_id:
            continue
        rows.append({
            "name": String(army.get("display_name", "未命名军队")),
            "soldiers": army.get("manpower", 0),
            "province_name": _province_name(String(army.get("province_id", ""))),
            "status": "推进中" if not String(army.get("advance_target_id", "")).is_empty() else "驻防",
        })
    return rows


func _player_order_rows() -> Array:
    var rows: Array = []
    for order: Dictionary in _player_pending_orders():
        rows.append({
            "name": GameText.pending_order_text(order, _province_name_lookup(), _country_name_lookup()),
            "status": "剩余%d个月" % int(order.get("remaining_months", 0)),
        })
    return rows
