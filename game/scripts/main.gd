extends Control

const PLAYER_COUNTRY_ID := "auroria"
const QUICK_SAVE_PATH := "user://quick_save.json"
const DEFAULT_ROAD_BUILD_COST := 600
const GameText := preload("res://scripts/ui/game_text_formatter.gd")
const StrategyPresenter := preload("res://scripts/ui/strategy_panel_presenter.gd")

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
@onready var date_label: Label = $TurnBar/TurnControls/DateLabel
@onready var turn_length: OptionButton = $TurnBar/TurnControls/TurnLength
@onready var advance_turn_button: Button = $TurnBar/TurnControls/AdvanceTurn
@onready var event_log: Label = $RightPanel/Center/EventLog
@onready var event_history: RichTextLabel = $RightPanel/Center/EventHistory
@onready var country_details: Label = $RightPanel/Center/CountryDetails
@onready var war_overview: Label = $RightPanel/Center/WarOverview
@onready var province_map := $MapPanel/ProvinceMap
@onready var war_target: OptionButton = $RightPanel/Center/DiplomacyControls/WarTarget
@onready var peace_policy: OptionButton = $RightPanel/Center/DiplomacyControls/PeacePolicy
@onready var road_construction_entry: Button = $RightPanel/Center/RoadConstructionEntry
@onready var workspace_title: Label = $WorkspacePanel/Workspace/TitleBar/Title
@onready var workspace_close: Button = $WorkspacePanel/Workspace/TitleBar/Close
@onready var workspace_scroll: ScrollContainer = $WorkspacePanel/Workspace/WindowViewport
@onready var workspace_content: Label = $WorkspacePanel/Workspace/WindowViewport/WindowContent/Content
@onready var province_info_window := $WorkspacePanel/Workspace/WindowViewport/WindowContent/ProvinceInfoWindow
@onready var province_management_window := $WorkspacePanel/Workspace/WindowViewport/WindowContent/ProvinceManagementWindow
@onready var road_construction_window := $WorkspacePanel/Workspace/WindowViewport/WindowContent/RoadConstructionWindow

var province_by_id: Dictionary = {}
var road_start_id := ""
var road_end_id := ""
var moving_army_id := ""
var movement_origin_id := ""
var movement_destination_id := ""
var auto_advance_target_id := ""
var event_history_lines: Array[String] = []
var workspace_mode := WorkspaceMode.CLOSED
var map_input_mode := MapInputMode.NORMAL
var managed_province_id := ""

func _ready() -> void:
    if not province_map.load_map_geometry("res://data/map_geometry.json"):
        $RightPanel/Center/Status.text = "地图加载失败：%s" % province_map.geometry_error()
        push_error(province_map.geometry_error())
        return
    var data_directory := ProjectSettings.globalize_path("res://data")
    if not bridge.load_scenario(data_directory, 1000, 1):
        $RightPanel/Center/Status.text = "场景加载失败：%s" % bridge.get_last_error()
        push_error(bridge.get_last_error())
        return

    _refresh_map_data()
    province_map.province_selected.connect(_on_province_selected)
    province_map.province_clicked.connect(_on_province_clicked)
    province_map.province_double_clicked.connect(_on_province_double_clicked)
    province_map.map_blank_clicked.connect(_on_map_blank_clicked)
    province_map.province_hovered.connect(_on_province_hovered)
    $RightPanel/Center/RoadControls/Buttons/BuildRoad.pressed.connect(_on_build_road_pressed)
    $RightPanel/Center/RoadControls/Buttons/ClearRoad.pressed.connect(_clear_road_selection)
    road_construction_entry.pressed.connect(_on_road_construction_entry_pressed)
    workspace_close.pressed.connect(_close_workspace)
    province_management_window.recruit_requested.connect(
        _on_management_recruit_requested
    )
    province_management_window.rename_requested.connect(
        _on_management_rename_requested
    )
    province_management_window.merge_requested.connect(
        _on_management_merge_requested
    )
    province_management_window.technology_research_requested.connect(
        _on_research_technology
    )
    province_management_window.army_selected.connect(
        _on_management_army_selected
    )
    province_management_window.destination_selection_requested.connect(
        _on_management_destination_requested
    )
    province_management_window.move_requested.connect(
        _on_management_move_requested
    )
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
    road_construction_window.select_end_requested.connect(
        _on_road_end_selection_requested
    )
    road_construction_window.build_requested.connect(_on_build_road_pressed)
    road_construction_window.reset_requested.connect(_on_road_reset_requested)
    $RightPanel/Center/DiplomacyControls/DeclareWar.pressed.connect(_on_declare_war_pressed)
    $RightPanel/Center/DiplomacyControls/MakePeace.pressed.connect(_on_make_peace_pressed)
    $RightPanel/Center/SaveControls/Save.pressed.connect(_on_quick_save_pressed)
    $RightPanel/Center/SaveControls/Load.pressed.connect(_on_quick_load_pressed)
    var provinces: Array = bridge.get_province_summaries()
    var countries: Array = bridge.get_country_summaries()
    $RightPanel/Center/Status.text = "核心版本 %s · %d 个国家 · %d 个地区" % [
        bridge.get_core_version(), countries.size(), provinces.size()
    ]
    _refresh_province_summary()

    for months: int in [1, 3, 6, 12]:
        turn_length.add_item("%d个月" % months)
        turn_length.set_item_metadata(turn_length.item_count - 1, months)
    turn_length.select(0)
    turn_length.item_selected.connect(_on_turn_length_selected)
    advance_turn_button.pressed.connect(_on_advance_turn_pressed)
    _refresh_turn_controls()
    _refresh_date()

    _refresh_country_list()
    _refresh_country_details()
    _refresh_war_overview()
    _refresh_game_status()
    _refresh_technology_status()
    _populate_war_targets()
    peace_policy.add_item("恢复战前边界")
    peace_policy.set_item_metadata(0, false)
    peace_policy.add_item("吞并占领地区")
    peace_policy.set_item_metadata(1, true)

    print($RightPanel/Center/Status.text)
    _record_event("场景已加载：%d 个地区" % provinces.size())


func workspace_mode_name() -> String:
    match workspace_mode:
        WorkspaceMode.PROVINCE_INFO:
            return "province_info"
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


func _open_workspace(mode: WorkspaceMode, title: String, content: String) -> void:
    workspace_mode = mode
    if mode != WorkspaceMode.PROVINCE_MANAGEMENT:
        managed_province_id = ""
    workspace_title.text = title
    workspace_content.text = content
    workspace_content.visible = true
    province_info_window.clear()
    province_management_window.clear()
    road_construction_window.clear()
    workspace_scroll.scroll_vertical = 0
    workspace_close.disabled = false


func _close_workspace() -> void:
    workspace_mode = WorkspaceMode.CLOSED
    map_input_mode = MapInputMode.NORMAL
    managed_province_id = ""
    workspace_title.text = "功能窗口"
    workspace_content.text = "请选择地区或打开功能"
    workspace_content.visible = true
    province_info_window.clear()
    province_management_window.clear()
    road_construction_window.clear()
    workspace_scroll.scroll_vertical = 0
    road_start_id = ""
    road_end_id = ""
    province_map.set_auto_advance_path([])
    _refresh_road_selection()
    workspace_close.disabled = true


func _close_transient_workspace() -> void:
    if workspace_mode in [
        WorkspaceMode.PROVINCE_INFO,
        WorkspaceMode.PROVINCE_MANAGEMENT,
    ]:
        _close_workspace()


func _on_province_clicked(province_id: String) -> void:
    if map_input_mode != MapInputMode.NORMAL or \
            workspace_mode == WorkspaceMode.ROAD_CONSTRUCTION:
        return
    var province: Dictionary = province_by_id.get(province_id, {})
    if province.is_empty():
        return
    _open_workspace(WorkspaceMode.PROVINCE_INFO, "地区信息", "")
    workspace_content.visible = false
    province_info_window.display_province(
        province,
        bridge.get_army_summaries(),
        bridge.get_road_summaries(),
        province_by_id,
        bridge.get_country_summaries()
    )


func _on_province_double_clicked(province_id: String) -> void:
    if map_input_mode != MapInputMode.NORMAL or \
            workspace_mode == WorkspaceMode.ROAD_CONSTRUCTION:
        return
    var province: Dictionary = province_by_id.get(province_id, {})
    if province.is_empty():
        return
    managed_province_id = province_id
    _open_workspace(WorkspaceMode.PROVINCE_MANAGEMENT, "地区管理", "")
    workspace_content.visible = false
    _refresh_management_window()


func _on_map_blank_clicked() -> void:
    if map_input_mode == MapInputMode.NORMAL:
        _close_transient_workspace()


func _refresh_management_window(
    preferred_army_id := "",
    status_message := ""
) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT or \
            managed_province_id.is_empty():
        return
    var province: Dictionary = province_by_id.get(managed_province_id, {})
    if province.is_empty():
        _close_workspace()
        return
    province_management_window.display_province(
        province,
        bridge.get_army_summaries(),
        PLAYER_COUNTRY_ID,
        preferred_army_id,
        _player_treasury()
    )
    province_management_window.set_technology(_player_technology())
    var selected_army_id := preferred_army_id
    if selected_army_id.is_empty():
        for army: Dictionary in bridge.get_army_summaries():
            if army.get("owner_id", "") == PLAYER_COUNTRY_ID and \
                    army.get("province_id", "") == managed_province_id:
                selected_army_id = String(army.get("id", ""))
                break
    if not selected_army_id.is_empty():
        _select_army(selected_army_id)
    _refresh_advance_plans()
    _refresh_management_action_state()
    if not status_message.is_empty():
        province_management_window.set_status(status_message)


func _player_treasury() -> int:
    for country: Dictionary in bridge.get_country_summaries():
        if country.get("id", "") == PLAYER_COUNTRY_ID:
            return int(country.get("treasury", 0))
    return 0


func _on_management_recruit_requested(province_id: String, manpower: int) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT or \
            province_id != managed_province_id:
        return
    var result: Dictionary = bridge.recruit_army(
        PLAYER_COUNTRY_ID,
        province_id,
        manpower
    )
    if not result.get("accepted", false):
        var error_message := "招募失败：%s" % result.get("error", "未知错误")
        event_log.text = error_message
        province_management_window.set_status(error_message)
        return

    event_log.text = "事件 #%d：%s 招募%d人，支出%d" % [
        result["event_sequence"],
        result.get("display_name", result["army_id"]),
        result["manpower"],
        result["cost"],
    ]
    _record_event(event_log.text)
    moving_army_id = result["army_id"]
    movement_origin_id = province_id
    movement_destination_id = ""
    auto_advance_target_id = ""
    _refresh_country_list()
    _refresh_country_details()
    _refresh_map_data()
    _refresh_province_summary()
    _refresh_management_window(result["army_id"], event_log.text)


func _on_management_rename_requested(
    army_id: String,
    formation_number: int
) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT:
        return
    var result: Dictionary = bridge.rename_army(army_id, formation_number)
    if not result.get("accepted", false):
        province_management_window.set_status(
            "更名失败：%s" % result.get("error", "未知错误")
        )
        return
    var message := "军队已更名为%s" % result.get("display_name", army_id)
    _record_event(message)
    _refresh_map_data()
    _refresh_advance_plans()
    _refresh_management_window(army_id, message)


func _on_management_merge_requested(
    primary_army_id: String,
    merged_army_ids: Array
) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT:
        return
    var result: Dictionary = bridge.merge_armies(
        primary_army_id, merged_army_ids
    )
    if not result.get("accepted", false):
        province_management_window.set_status(
            "合并失败：%s" % result.get("error", "未知错误")
        )
        return
    var primary := _find_army_by_id(primary_army_id)
    var message := "%s完成合并，现有兵力%d" % [
        primary.get("display_name", primary_army_id),
        result.get("current_manpower", 0),
    ]
    _record_event(message)
    moving_army_id = primary_army_id
    _refresh_map_data()
    _refresh_province_summary()
    _refresh_advance_plans()
    _refresh_management_window(primary_army_id, message)


func _on_management_army_selected(army_id: String) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT:
        return
    _select_army(army_id)


func _on_management_destination_requested(army_id: String) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT:
        return
    _select_army(army_id)
    if moving_army_id != army_id:
        province_management_window.set_status("无法选择该军队")
        return
    map_input_mode = MapInputMode.ARMY_DESTINATION
    province_management_window.set_status("请在地图上点击一个相邻地区")


func _on_management_advance_destination_requested(army_id: String) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT:
        return
    _select_army(army_id)
    if moving_army_id != army_id:
        province_management_window.set_status("无法选择该军队")
        return
    map_input_mode = MapInputMode.AUTO_ADVANCE_DESTINATION
    province_management_window.set_status("请在地图上点击推进目标")


func _select_management_destination(province_id: String) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT or \
            moving_army_id.is_empty():
        map_input_mode = MapInputMode.NORMAL
        return
    if province_id.is_empty():
        province_management_window.set_status("请选择一个地区作为目的地")
        return
    if province_id == movement_origin_id:
        province_management_window.set_status("目的地不能与军队所在地相同")
        return
    if not _are_provinces_adjacent(movement_origin_id, province_id):
        province_management_window.set_status("首版调动只能选择相邻地区")
        return
    movement_destination_id = province_id
    auto_advance_target_id = ""
    bridge.clear_army_advance_target(moving_army_id)
    map_input_mode = MapInputMode.NORMAL
    province_management_window.set_destination(
        province_id,
        province_by_id.get(province_id, {"name": province_id}).get(
            "name", province_id
        )
    )
    _refresh_management_action_state()


func _select_management_advance_target(province_id: String) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT or \
            moving_army_id.is_empty():
        map_input_mode = MapInputMode.NORMAL
        return
    if province_id.is_empty() or province_id == movement_origin_id:
        province_management_window.set_status("推进目标必须是其他地区")
        return
    var result: Dictionary = bridge.set_army_advance_target(
        moving_army_id,
        province_id
    )
    if not result.get("accepted", false):
        province_management_window.set_status(
            "设置推进目标失败：%s" % result.get("error", "未知错误")
        )
        return
    auto_advance_target_id = province_id
    movement_destination_id = ""
    map_input_mode = MapInputMode.NORMAL
    _refresh_advance_plans()
    _refresh_management_action_state()
    province_management_window.set_status("推进目标已设置")


func _on_management_move_requested(army_id: String, destination_id: String) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT or \
            army_id != moving_army_id or destination_id != movement_destination_id:
        return
    var result: Dictionary = bridge.move_army(army_id, destination_id)
    if not result.get("accepted", false):
        var error_message := "调动失败：%s" % result.get("error", "未知错误")
        event_log.text = error_message
        province_management_window.set_status(error_message)
        return

    _record_movement_result(result)
    bridge.clear_army_advance_target(army_id)
    movement_destination_id = ""
    auto_advance_target_id = ""
    map_input_mode = MapInputMode.NORMAL
    _refresh_map_data()
    _refresh_country_details()
    _refresh_game_status()
    _refresh_province_summary()
    _refresh_advance_plans()
    if result.get("army_destroyed", false):
        _clear_movement_selection()
    else:
        movement_origin_id = result.get("army_province_id", result["destination"])
        _refresh_management_action_state()
    _refresh_management_window("", event_log.text)


func _record_movement_result(result: Dictionary) -> void:
    event_log.text = "事件 #%d：%s → %s，消耗%d移动点，剩余%s" % [
        result.get("event_sequence", 0),
        _province_name(result.get("origin", "")),
        _province_name(result.get("destination", "")),
        result.get("movement_cost", 0),
        GameText.movement_points(result.get("remaining_points", 0)),
    ]
    var battle_report := _battle_report(result)
    if not battle_report.is_empty():
        event_log.text = battle_report
    _record_event(event_log.text)


func _on_management_auto_advance_requested(
    army_id: String,
    target_id: String
) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT or \
            army_id != moving_army_id or target_id.is_empty():
        return
    var result: Dictionary = bridge.auto_advance_army_to(army_id, target_id)
    if not result.get("accepted", false):
        event_log.text = "自动推进失败：%s" % result.get("error", "未知错误")
        province_management_window.set_status(event_log.text)
        return
    _record_movement_result(result)
    if result.get("army_destroyed", false):
        _clear_movement_selection()
        _refresh_map_data()
        _close_workspace()
        return
    var new_province_id: String = result.get(
        "army_province_id",
        result.get("destination", "")
    )
    movement_origin_id = new_province_id
    movement_destination_id = ""
    auto_advance_target_id = String(
        _find_army_by_id(army_id).get("advance_target_id", "")
    )
    map_input_mode = MapInputMode.NORMAL
    _refresh_map_data()
    _refresh_country_details()
    _refresh_game_status()
    _open_management_for_army(army_id, new_province_id, event_log.text)


func _on_management_movement_clear_requested(army_id: String) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT or \
            army_id != moving_army_id:
        return
    movement_destination_id = ""
    map_input_mode = MapInputMode.NORMAL
    province_management_window.set_destination("", "")
    province_management_window.set_status("已清除临时移动选择")
    _refresh_management_action_state()


func _on_road_construction_entry_pressed() -> void:
    _clear_road_selection()
    map_input_mode = MapInputMode.NORMAL
    _open_workspace(
        WorkspaceMode.ROAD_CONSTRUCTION,
        "道路建设",
        ""
    )
    workspace_content.visible = false
    road_construction_window.open_window(_estimated_road_build_cost())


func _estimated_road_build_cost() -> int:
    var first: Dictionary = province_by_id.get(road_start_id, {})
    var second: Dictionary = province_by_id.get(road_end_id, {})
    if first.is_empty() or second.is_empty():
        return DEFAULT_ROAD_BUILD_COST
    var base_cost: int = _road_endpoint_base_cost(first.get("terrain", "plains")) + \
        _road_endpoint_base_cost(second.get("terrain", "plains"))
    var roads_level: int = _player_roads_level()
    var discount: int = {1: 10, 2: 20, 3: 30, 4: 50}.get(roads_level, 0)
    return int(base_cost * (100 - discount) / 100)


func _player_roads_level() -> int:
    for technology: Dictionary in bridge.get_technology_summaries():
        if technology.get("country_id", "") == PLAYER_COUNTRY_ID:
            return int(technology.get("roads_level", 0))
    return 0


func _road_endpoint_base_cost(terrain: String) -> int:
    match terrain:
        "plains":
            return 300
        "mountains":
            return 700
        _:
            return 500


func _road_required_level(first_terrain: String, second_terrain: String) -> int:
    var first_t: int = {"plains": 10, "forest": 9, "hills": 9, "mountains": 8}.get(first_terrain, 10)
    var second_t: int = {"plains": 10, "forest": 9, "hills": 9, "mountains": 8}.get(second_terrain, 10)
    var minimum_t: int = mini(first_t, second_t)
    return 1 if minimum_t >= 10 else 2 if minimum_t >= 9 else 3


func _on_road_start_selection_requested() -> void:
    if workspace_mode != WorkspaceMode.ROAD_CONSTRUCTION:
        return
    _clear_road_selection()
    map_input_mode = MapInputMode.ROAD_START
    road_construction_window.reset_selection(
        _estimated_road_build_cost(),
        "请在地图上选择由你控制的道路起点"
    )


func _on_road_end_selection_requested() -> void:
    if workspace_mode != WorkspaceMode.ROAD_CONSTRUCTION:
        return
    if road_start_id.is_empty():
        road_construction_window.set_status("请先选择道路起点")
        return
    road_end_id = ""
    map_input_mode = MapInputMode.ROAD_END
    _refresh_road_selection()
    road_construction_window.set_start(
        province_by_id.get(road_start_id, {"name": road_start_id}).get(
            "name", road_start_id
        ),
        _estimated_road_build_cost()
    )
    road_construction_window.set_status("请在地图上选择相邻的道路终点")


func _on_road_reset_requested() -> void:
    if workspace_mode != WorkspaceMode.ROAD_CONSTRUCTION:
        return
    _clear_road_selection()
    map_input_mode = MapInputMode.NORMAL
    road_construction_window.reset_selection(
        _estimated_road_build_cost(),
        "道路选择已重置"
    )


func _select_road_endpoint(province_id: String) -> void:
    if workspace_mode != WorkspaceMode.ROAD_CONSTRUCTION:
        map_input_mode = MapInputMode.NORMAL
        return
    var province: Dictionary = province_by_id.get(province_id, {})
    if province.is_empty():
        road_construction_window.set_status("请选择一个有效地区")
        return
    if province.get("owner_id", "") != PLAYER_COUNTRY_ID:
        road_construction_window.set_status("道路端点必须由玩家实际控制")
        return

    if map_input_mode == MapInputMode.ROAD_START:
        road_start_id = province_id
        road_end_id = ""
        map_input_mode = MapInputMode.NORMAL
        _refresh_road_selection()
        road_construction_window.set_start(
            province.get("name", province_id),
            _estimated_road_build_cost()
        )
        return

    if map_input_mode != MapInputMode.ROAD_END:
        return
    if road_start_id.is_empty():
        road_construction_window.set_status("请先选择道路起点")
        return
    if province_id == road_start_id:
        road_construction_window.set_status("道路终点不能与起点相同")
        return
    if not _are_provinces_adjacent(road_start_id, province_id):
        road_construction_window.set_status("道路终点必须与起点相邻")
        return
    if _road_connection_exists(road_start_id, province_id):
        road_construction_window.set_status("这两个地区之间已经存在公路")
        return
    road_end_id = province_id
    map_input_mode = MapInputMode.NORMAL
    _refresh_road_selection()
    var required_level: int = _road_required_level(
        province_by_id.get(road_start_id, {}).get("terrain", "plains"),
        province.get("terrain", "plains")
    )
    var can_build: bool = _player_roads_level() >= required_level
    var status: String = "路线合法，可以确认修建" if can_build else \
        "需要道路科技%d级（当前%d级）" % [required_level, _player_roads_level()]
    road_construction_window.set_end_province(
        province.get("name", province_id),
        _estimated_road_build_cost(),
        can_build,
        status
    )


func _road_connection_exists(province_a: String, province_b: String) -> bool:
    for road: Dictionary in bridge.get_road_summaries():
        var first: String = road.get("province_a", "")
        var second: String = road.get("province_b", "")
        if (first == province_a and second == province_b) or \
                (first == province_b and second == province_a):
            return true
    return false


func _record_event(message: String) -> void:
    if message.is_empty():
        return
    event_history_lines.append(message)
    while event_history_lines.size() > 80:
        event_history_lines.pop_front()
    event_history.text = "\n".join(event_history_lines)


func _country_name(country_id: String) -> String:
    for country: Dictionary in bridge.get_country_summaries():
        if country.get("id", "") == country_id:
            return country.get("name", country_id)
    return country_id


func _province_name(province_id: String) -> String:
    return province_by_id.get(
        province_id,
        {"name": province_id}
    ).get("name", province_id)


func _record_turn_actions(actions: Array) -> void:
    for action: Dictionary in actions:
        match String(action.get("type", "other")):
            "army_recruited":
                _record_event("回合行动：%s 招募了一支军队" % _country_name(
                    action.get("country_id", "?")
                ))
            "war_declared":
                _record_event("回合行动：%s 向 %s 宣战" % [
                    _country_name(action.get("country_id", "?")),
                    _country_name(action.get("target_id", "?")),
                ])
            "army_moved":
                _record_event("回合行动：%s 从 %s 调动至 %s，消耗%d移动点，剩余%s移动点" % [
                    action.get("army_id", "?"),
                    _province_name(action.get("origin", "?")),
                    _province_name(action.get("destination", "?")),
                    action.get("movement_cost", 0),
                    GameText.movement_points(action.get("remaining_points", 0)),
                ])
            "battle_resolved":
                _record_event(_battle_action_report(action))
            "technology_researched":
                _record_event("回合行动：%s 完成了一项科技研究" % _country_name(
                    action.get("country_id", "?")
                ))


func _refresh_turn_controls() -> void:
    var months := 1
    if turn_length.item_count > 0:
        months = int(turn_length.get_selected_metadata())
    advance_turn_button.text = "进入下一回合（%d个月）" % months


func _refresh_country_list() -> void:
    for child: Node in $RightPanel/Center/CountryList.get_children():
        child.free()

    for country: Dictionary in bridge.get_country_summaries():
        var label := Label.new()
        var rgb: int = country["color_rgb"]
        label.text = "%s · 国库 %d · 地区 %d · 经济 %d · 财政收入 %d" % [
            country["name"],
            country["treasury"],
            country["province_count"],
            country.get("economy", 0),
            country.get("fiscal_income", 0),
        ]
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        label.add_theme_font_size_override("font_size", 20)
        label.add_theme_color_override(
            "font_color",
            Color8((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255)
        )
        $RightPanel/Center/CountryList.add_child(label)


func _battle_report(result: Dictionary) -> String:
    return GameText.battle_report(result, province_by_id)


func _battle_action_report(action: Dictionary) -> String:
    return GameText.battle_action_report(action, province_by_id)


func _refresh_country_details() -> void:
    var countries: Array = bridge.get_country_summaries()
    var country_names: Dictionary = {}
    for country: Dictionary in countries:
        country_names[country["id"]] = country["name"]
    var status: Dictionary = bridge.get_game_status(PLAYER_COUNTRY_ID)
    country_details.text = StrategyPresenter.country_details(
        countries,
        bridge.get_technology_summaries(),
        status,
        bridge.get_diplomatic_relations(),
        country_names
    )
    _refresh_war_overview()


func _refresh_war_overview() -> void:
    var country_names: Dictionary = {}
    for country: Dictionary in bridge.get_country_summaries():
        country_names[country["id"]] = country["name"]
    war_overview.text = StrategyPresenter.war_overview(
        bridge.get_war_summaries(),
        country_names
    )


func _refresh_game_status() -> void:
    var status: Dictionary = bridge.get_game_status(PLAYER_COUNTRY_ID)
    if not status.get("has_scenario", false):
        $RightPanel/Center/GameStatus.text = "当前没有已加载的场景"
        return
    if status.get("player_won", false):
        $RightPanel/Center/GameStatus.text = "胜利：奥罗里亚已经控制世界"
    elif status.get("player_eliminated", false):
        $RightPanel/Center/GameStatus.text = "失败：奥罗里亚已经灭亡"
    elif status.get("winner_id", "") != "":
        $RightPanel/Center/GameStatus.text = "胜利国家：%s" % _country_name(
            status["winner_id"]
        )
    else:
        var active := 0
        for country: Dictionary in status.get("countries", []):
            if not country.get("eliminated", false):
                active += 1
        $RightPanel/Center/GameStatus.text = "存续国家：%d" % active


func _populate_war_targets() -> void:
    war_target.clear()
    for country: Dictionary in bridge.get_country_summaries():
        if country["id"] == PLAYER_COUNTRY_ID:
            continue
        war_target.add_item(country["name"])
        war_target.set_item_metadata(war_target.item_count - 1, country["id"])


func _on_declare_war_pressed() -> void:
    _close_transient_workspace()
    if war_target.item_count == 0:
        return
    var defender_id: String = war_target.get_selected_metadata()
    var result: Dictionary = bridge.declare_war(PLAYER_COUNTRY_ID, defender_id)
    if not result.get("accepted", false):
        event_log.text = "宣战失败：%s" % result.get("error", "未知错误")
        return
    event_log.text = "事件 #%d：%s 向 %s 宣战" % [
        result["event_sequence"],
        _country_name(result["aggressor_id"]),
        _country_name(result["defender_id"]),
    ]
    _record_event(event_log.text)


func _on_make_peace_pressed() -> void:
    _close_transient_workspace()
    if war_target.item_count == 0:
        return
    var other_country_id: String = war_target.get_selected_metadata()
    var annex: bool = peace_policy.get_selected_metadata()
    var result: Dictionary = bridge.make_peace(
        PLAYER_COUNTRY_ID,
        other_country_id,
        annex
    )
    if not result.get("accepted", false):
        event_log.text = "议和失败：%s" % result.get("error", "未知错误")
        return
    event_log.text = "和平协议达成：处理%d个地区，遣返%d支军队" % [
        result.get("provinces", []).size(),
        result.get("armies", []).size(),
    ]
    _record_event(event_log.text)
    _clear_movement_selection()
    _refresh_map_data()
    _refresh_country_list()
    _refresh_country_details()
    _refresh_game_status()


func _on_research_technology(track: String) -> void:
    var result: Dictionary = bridge.research_technology(PLAYER_COUNTRY_ID, track)
    if not result.get("accepted", false):
        event_log.text = "科技研究失败：%s" % result.get("error", "未知错误")
        if workspace_mode == WorkspaceMode.PROVINCE_MANAGEMENT:
            province_management_window.set_status(event_log.text)
        return
    event_log.text = "科技提升至%d级，支出%d" % [
        result["current_level"], result["cost"]
    ]
    _record_event(event_log.text)
    _refresh_country_list()
    _refresh_country_details()
    _refresh_technology_status()
    _refresh_management_window(moving_army_id, event_log.text)


func _player_technology() -> Dictionary:
    for technology: Dictionary in bridge.get_technology_summaries():
        if technology.get("country_id", "") == PLAYER_COUNTRY_ID:
            return technology
    return {}


func _refresh_technology_status() -> void:
    var technology := _player_technology()
    if workspace_mode == WorkspaceMode.PROVINCE_MANAGEMENT:
        province_management_window.set_technology(technology)


func _on_quick_save_pressed() -> void:
    _close_transient_workspace()
    var path := ProjectSettings.globalize_path(QUICK_SAVE_PATH)
    var result: Dictionary = bridge.save_game(path)
    if not result.get("accepted", false):
        event_log.text = "保存失败：%s" % result.get("error", "未知错误")
        return
    event_log.text = "游戏已保存至 quick_save.json"
    _record_event(event_log.text)


func _on_quick_load_pressed() -> void:
    _close_transient_workspace()
    var path := ProjectSettings.globalize_path(QUICK_SAVE_PATH)
    var result: Dictionary = bridge.load_game(path)
    if not result.get("accepted", false):
        event_log.text = "读取失败：%s" % result.get("error", "未知错误")
        return
    _clear_movement_selection()
    _clear_road_selection()
    _refresh_date()
    _refresh_country_list()
    _refresh_country_details()
    _refresh_map_data()
    _refresh_province_summary()
    _refresh_technology_status()
    _refresh_game_status()
    event_log.text = "已从 quick_save.json 读取游戏"
    _record_event(event_log.text)


func _refresh_map_data() -> void:
    var provinces: Array = bridge.get_province_summaries()
    var countries: Array = bridge.get_country_summaries()
    province_by_id.clear()
    for province: Dictionary in provinces:
        province_by_id[province["id"]] = province
    province_map.set_scenario_data(provinces, countries)
    province_map.set_roads(bridge.get_road_summaries())
    province_map.set_frontlines(bridge.get_frontline_edges())
    province_map.set_armies(bridge.get_army_summaries())
    _refresh_advance_plans()


func _select_army(army_id: String) -> void:
    var army := _find_army_by_id(army_id)
    if army.is_empty():
        return
    moving_army_id = army_id
    movement_origin_id = army["province_id"]
    movement_destination_id = ""
    auto_advance_target_id = army.get("advance_target_id", "")
    _refresh_management_action_state()


func _find_army_by_id(army_id: String) -> Dictionary:
    for army: Dictionary in bridge.get_army_summaries():
        if army.get("id", "") == army_id:
            return army
    return {}


func _open_management_for_army(
    army_id: String,
    province_id := "",
    status_message := ""
) -> void:
    var army := _find_army_by_id(army_id)
    if army.is_empty():
        return
    managed_province_id = (
        province_id if not province_id.is_empty() else String(army["province_id"])
    )
    moving_army_id = army_id
    movement_origin_id = managed_province_id
    movement_destination_id = ""
    auto_advance_target_id = army.get("advance_target_id", "")
    _open_workspace(WorkspaceMode.PROVINCE_MANAGEMENT, "地区管理", "")
    workspace_content.visible = false
    _refresh_management_window(army_id, status_message)


func _refresh_advance_plans() -> void:
    var preview_months := 1
    if turn_length.item_count > 0:
        preview_months = int(turn_length.get_selected_metadata())
    if workspace_mode == WorkspaceMode.PROVINCE_MANAGEMENT:
        province_management_window.set_advance_plans(
            StrategyPresenter.advance_plans(
                bridge,
                bridge.get_army_summaries(),
                province_by_id,
                PLAYER_COUNTRY_ID,
                preview_months
            )
        )


func _on_advance_plan_clicked(meta: Variant) -> void:
    var command := String(meta)
    if command.is_empty():
        return
    if command.begins_with("clear:"):
        var army_id := command.trim_prefix("clear:")
        var result: Dictionary = bridge.clear_army_advance_target(army_id)
        if not result.get("accepted", false):
            event_log.text = "清除推进计划失败：%s" % result.get("error", "未知错误")
            return
        if army_id == moving_army_id:
            auto_advance_target_id = ""
            province_map.set_auto_advance_path([])
        _refresh_map_data()
        _refresh_advance_plans()
        var message := "已清除推进计划：%s" % army_id
        _record_event(message)
        _refresh_management_action_state()
        _refresh_management_window(moving_army_id, message)
        return
    if command.begins_with("pause:") or command.begins_with("resume:"):
        var enabled := command.begins_with("resume:")
        var separator := command.find(":")
        var army_id := command.substr(separator + 1)
        var result: Dictionary = bridge.set_army_advance_enabled(army_id, enabled)
        if not result.get("accepted", false):
            event_log.text = "切换推进计划状态失败：%s" % result.get("error", "未知错误")
            return
        _refresh_map_data()
        _refresh_advance_plans()
        var message := "%s推进计划：%s" % [
            "已继续" if enabled else "已暂停",
            army_id,
        ]
        _record_event(message)
        _refresh_management_action_state()
        _refresh_management_window(moving_army_id, message)
        return
    if command.begins_with("strategy:"):
        var parts := command.split(":")
        if parts.size() != 3:
            return
        var army_id := String(parts[1])
        var strategy := String(parts[2])
        var result: Dictionary = bridge.set_army_advance_strategy(army_id, strategy)
        if not result.get("accepted", false):
            event_log.text = "设置推进策略失败：%s" % result.get("error", "未知错误")
            return
        _refresh_map_data()
        _refresh_advance_plans()
        var message := "已设置推进策略：%s → %s" % [
            army_id,
            GameText.advance_strategy(strategy),
        ]
        _record_event(message)
        _refresh_management_action_state()
        _refresh_management_window(moving_army_id, message)
        return
    var army_id := command.trim_prefix("select:")
    _open_management_for_army(army_id)
    _record_event("已选择推进计划：%s" % army_id)


func _refresh_province_summary() -> void:
    var total_population := 0
    var recruitable_population := 0
    for province: Dictionary in bridge.get_province_summaries():
        total_population += int(province["population"])
        recruitable_population += int(province["recruitable_population"])
    $RightPanel/Center/ProvinceSummary.text = "总人口 %d · 可招募士兵 %d" % [
        total_population, recruitable_population
    ]


func _on_turn_length_selected(_index: int) -> void:
    _close_transient_workspace()
    _refresh_turn_controls()
    _refresh_advance_plans()


func _on_advance_turn_pressed() -> void:
    _close_transient_workspace()
    var months: int = turn_length.get_selected_metadata()
    var result: Dictionary = bridge.advance_turn(months)
    if not result.get("accepted", false):
        event_log.text = "命令被拒绝：%s" % result.get("error", "未知错误")
        return

    _refresh_date()
    _refresh_country_list()
    _refresh_country_details()
    _refresh_map_data()
    _refresh_game_status()
    _refresh_province_summary()
    var total_income := 0
    for income: Dictionary in result["fiscal_incomes"]:
        total_income += int(income["amount"])
    var total_growth := 0
    for change: Dictionary in result["population_changes"]:
        total_growth += int(change["growth"])
    event_log.text = "事件 #%d：推进%d个月，财政收入%d，人口增长%d（原日期 %d-%02d）" % [
        result["event_sequence"],
        result["elapsed_months"],
        total_income,
        total_growth,
        result["previous_year"],
        result["previous_month"],
    ]
    var turn_actions: Array = result.get("turn_actions", result.get("ai_actions", []))
    var turn_action_count := turn_actions.size()
    if turn_action_count > 0:
        event_log.text += " | 回合行动：%d" % turn_action_count
        _record_turn_actions(turn_actions)
    _record_event(event_log.text)


func _refresh_date() -> void:
    var date: Dictionary = bridge.get_current_date()
    date_label.text = "当前日期：%d年%02d月" % [date["year"], date["month"]]


func _on_province_selected(province_id: String) -> void:
    if map_input_mode == MapInputMode.ARMY_DESTINATION:
        _select_management_destination(province_id)
        return
    if map_input_mode == MapInputMode.AUTO_ADVANCE_DESTINATION:
        _select_management_advance_target(province_id)
        return
    if map_input_mode in [MapInputMode.ROAD_START, MapInputMode.ROAD_END]:
        _select_road_endpoint(province_id)


func _on_province_hovered(province_id: String) -> void:
    province_map.tooltip_text = "" if province_id.is_empty() else str(
        province_by_id[province_id]["name"]
    )


func _on_build_road_pressed() -> void:
    if road_start_id.is_empty() or road_end_id.is_empty():
        if workspace_mode == WorkspaceMode.ROAD_CONSTRUCTION:
            road_construction_window.set_status("请先选择道路起点和终点")
        return
    var result: Dictionary = bridge.build_road(
        PLAYER_COUNTRY_ID,
        road_start_id,
        road_end_id
    )
    if not result.get("accepted", false):
        event_log.text = "修路失败：%s" % result.get("error", "未知错误")
        if workspace_mode == WorkspaceMode.ROAD_CONSTRUCTION:
            road_construction_window.set_status(event_log.text)
        return

    event_log.text = "事件 #%d：公路建成，支出%d" % [
        result["event_sequence"], result["cost"]
    ]
    _record_event(event_log.text)
    _refresh_country_list()
    _refresh_country_details()
    _refresh_map_data()
    _clear_road_selection()
    map_input_mode = MapInputMode.NORMAL
    if workspace_mode == WorkspaceMode.ROAD_CONSTRUCTION:
        road_construction_window.reset_selection(
            _estimated_road_build_cost(),
            "公路已建成，选择已自动重置"
        )


func _are_provinces_adjacent(origin_id: String, target_id: String) -> bool:
    var origin: Dictionary = province_by_id.get(origin_id, {})
    for neighbor_id in origin.get("neighbors", []):
        if String(neighbor_id) == target_id:
            return true
    return false


func _clear_movement_selection() -> void:
    if not moving_army_id.is_empty():
        bridge.clear_army_advance_target(moving_army_id)
    moving_army_id = ""
    movement_origin_id = ""
    movement_destination_id = ""
    auto_advance_target_id = ""
    province_map.set_auto_advance_path([])
    _refresh_advance_plans()
    _refresh_management_action_state()


func _refresh_movement_preview() -> bool:
    province_map.set_auto_advance_path([])
    if moving_army_id.is_empty() or auto_advance_target_id.is_empty():
        return false

    var movement_points: float = 0.0
    for army: Dictionary in bridge.get_army_summaries():
        if army["id"] == moving_army_id:
            movement_points = float(army["movement_points"])
            break
    var preview_months := 1
    if turn_length.item_count > 0:
        preview_months = int(turn_length.get_selected_metadata())
    var path_preview: Dictionary = bridge.get_auto_advance_path_for_months(
        moving_army_id,
        auto_advance_target_id,
        preview_months
    )
    if not path_preview.get("accepted", false):
        return false
    province_map.set_auto_advance_paths(
        path_preview.get("path", []),
        path_preview.get("preview_path", []),
        path_preview.get("preview_stop_reason", "unknown")
    )
    return (
        int(path_preview.get("step_count", 0)) > 0 and
        movement_points >= int(path_preview.get("first_step_cost", 0))
    )


func _refresh_management_action_state() -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT:
        return
    var can_auto_advance := _refresh_movement_preview()
    province_management_window.set_action_state(
        not moving_army_id.is_empty() and not movement_destination_id.is_empty(),
        can_auto_advance
    )
    var target_name := ""
    if not auto_advance_target_id.is_empty():
        target_name = province_by_id.get(
            auto_advance_target_id,
            {"name": auto_advance_target_id}
        ).get("name", auto_advance_target_id)
    province_management_window.set_advance_target(
        auto_advance_target_id,
        target_name
    )


func _clear_road_selection() -> void:
    road_start_id = ""
    road_end_id = ""
    if map_input_mode in [MapInputMode.ROAD_START, MapInputMode.ROAD_END]:
        map_input_mode = MapInputMode.NORMAL
    _refresh_road_selection()


func _refresh_road_selection() -> void:
    province_map.set_road_selection(road_start_id, road_end_id)
    $RightPanel/Center/RoadControls/Buttons/BuildRoad.disabled = (
        road_start_id.is_empty() or road_end_id.is_empty()
    )
    if road_start_id.is_empty():
        $RightPanel/Center/RoadControls/RoadSelection.text = "修路：请选择起点（当前玩家：奥罗里亚）"
    elif road_end_id.is_empty():
        $RightPanel/Center/RoadControls/RoadSelection.text = "起点：%s · 请选择终点" % [
            province_by_id[road_start_id]["name"]
        ]
    else:
        $RightPanel/Center/RoadControls/RoadSelection.text = "路线：%s → %s" % [
            province_by_id[road_start_id]["name"],
            province_by_id[road_end_id]["name"],
        ]
