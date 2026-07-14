extends Control

const PLAYER_COUNTRY_ID := "auroria"
const QUICK_SAVE_PATH := "user://quick_save.json"
const BASE_ROAD_BUILD_COST := 500
const ROAD_TECH_COST_DISCOUNT := 100

enum WorkspaceMode {
    CLOSED,
    PROVINCE_INFO,
    PROVINCE_MANAGEMENT,
    ROAD_CONSTRUCTION,
}

enum MapInputMode {
    NORMAL,
    ARMY_DESTINATION,
    ROAD_START,
    ROAD_END,
}

@onready var bridge := $SimulationBridge
@onready var date_label: Label = $TurnBar/TurnControls/DateLabel
@onready var turn_length: OptionButton = $TurnBar/TurnControls/TurnLength
@onready var advance_turn_button: Button = $TurnBar/TurnControls/AdvanceTurn
@onready var event_log: Label = $RightPanel/Center/EventLog
@onready var event_history: RichTextLabel = $RightPanel/Center/EventHistory
@onready var country_details: RichTextLabel = $RightPanel/Center/CountryDetails
@onready var war_overview: RichTextLabel = $RightPanel/Center/WarOverview
@onready var region_details: RichTextLabel = $RightPanel/Center/RegionDetails
@onready var province_map := $MapPanel/ProvinceMap
@onready var recruit_button: Button = $RightPanel/Center/ArmyControls/RecruitArmy
@onready var move_army_button: Button = $RightPanel/Center/ArmyControls/MovementButtons/MoveArmy
@onready var auto_advance_button: Button = $RightPanel/Center/ArmyControls/MovementButtons/AutoAdvance
@onready var army_selector: OptionButton = $RightPanel/Center/ArmyControls/ArmySelector
@onready var army_details: Label = $RightPanel/Center/ArmyControls/ArmyDetails
@onready var advance_plans: RichTextLabel = $RightPanel/Center/ArmyControls/AdvancePlans
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
        $RightPanel/Center/Status.text = "Map load failed: %s" % province_map.geometry_error()
        push_error(province_map.geometry_error())
        return
    var data_directory := ProjectSettings.globalize_path("res://data")
    if not bridge.load_scenario(data_directory, 1000, 1):
        $RightPanel/Center/Status.text = "Scenario load failed: %s" % bridge.get_last_error()
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
    province_management_window.army_selected.connect(
        _on_management_army_selected
    )
    province_management_window.destination_selection_requested.connect(
        _on_management_destination_requested
    )
    province_management_window.move_requested.connect(
        _on_management_move_requested
    )
    road_construction_window.select_start_requested.connect(
        _on_road_start_selection_requested
    )
    road_construction_window.select_end_requested.connect(
        _on_road_end_selection_requested
    )
    road_construction_window.build_requested.connect(_on_build_road_pressed)
    road_construction_window.reset_requested.connect(_on_road_reset_requested)
    recruit_button.pressed.connect(_on_recruit_army_pressed)
    move_army_button.pressed.connect(_on_move_army_pressed)
    auto_advance_button.pressed.connect(_on_auto_advance_pressed)
    army_selector.item_selected.connect(_on_army_selected)
    $RightPanel/Center/DiplomacyControls/DeclareWar.pressed.connect(_on_declare_war_pressed)
    $RightPanel/Center/DiplomacyControls/MakePeace.pressed.connect(_on_make_peace_pressed)
    $RightPanel/Center/TechnologyControls/Buttons/Economy.pressed.connect(
        _on_research_technology.bind("economy")
    )
    $RightPanel/Center/TechnologyControls/Buttons/Military.pressed.connect(
        _on_research_technology.bind("military")
    )
    $RightPanel/Center/TechnologyControls/Buttons/Roads.pressed.connect(
        _on_research_technology.bind("roads")
    )
    $RightPanel/Center/SaveControls/Save.pressed.connect(_on_quick_save_pressed)
    $RightPanel/Center/SaveControls/Load.pressed.connect(_on_quick_load_pressed)
    $RightPanel/Center/ArmyControls/MovementButtons/ClearMovement.pressed.connect(
        _clear_movement_selection
    )
    advance_plans.meta_clicked.connect(_on_advance_plan_clicked)
    var provinces: Array = bridge.get_province_summaries()
    var countries: Array = bridge.get_country_summaries()
    $RightPanel/Center/Status.text = "Core %s · %d countries · %d provinces" % [
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
    _refresh_army_selector()
    _refresh_game_status()
    _refresh_technology_status()
    _populate_war_targets()
    peace_policy.add_item("Restore borders")
    peace_policy.set_item_metadata(0, false)
    peace_policy.add_item("Annex occupations")
    peace_policy.set_item_metadata(1, true)

    print($RightPanel/Center/Status.text)
    _record_event("Scenario loaded: %d provinces" % provinces.size())


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
        province_by_id
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
    province_management_window.display_province(
        province,
        bridge.get_army_summaries(),
        PLAYER_COUNTRY_ID
    )


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
        preferred_army_id
    )
    if not status_message.is_empty():
        province_management_window.set_status(status_message)


func _on_management_recruit_requested(province_id: String) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT or \
            province_id != managed_province_id:
        return
    var result: Dictionary = bridge.recruit_army(
        PLAYER_COUNTRY_ID,
        province_id,
        1000
    )
    if not result.get("accepted", false):
        var error_message := "招募失败：%s" % result.get("error", "未知错误")
        event_log.text = error_message
        province_management_window.set_status(error_message)
        return

    event_log.text = "事件 #%d：%s 招募%d人，支出%d" % [
        result["event_sequence"],
        result["army_id"],
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
    _show_province_details(province_id)
    _refresh_army_selector()
    _refresh_movement_selection()
    _refresh_management_window(result["army_id"], event_log.text)


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
    _refresh_movement_selection()


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

    event_log.text = "事件 #%d：%s → %s，消耗%d移动点，剩余%d" % [
        result["event_sequence"],
        result["origin"],
        result["destination"],
        result["movement_cost"],
        result["remaining_points"],
    ]
    var battle_report := _battle_report(result)
    if not battle_report.is_empty():
        event_log.text = battle_report
    _record_event(event_log.text)
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
        _refresh_movement_selection()
    _refresh_army_selector()
    if province_by_id.has(managed_province_id):
        _show_province_details(managed_province_id)
    _refresh_management_window("", event_log.text)


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
    for technology: Dictionary in bridge.get_technology_summaries():
        if technology.get("country_id", "") == PLAYER_COUNTRY_ID:
            return maxi(
                0,
                BASE_ROAD_BUILD_COST - ROAD_TECH_COST_DISCOUNT * int(
                    technology.get("roads_level", 0)
                )
            )
    return BASE_ROAD_BUILD_COST


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
    road_construction_window.set_end_province(province.get("name", province_id))


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


func _record_turn_actions(actions: Array) -> void:
    for action: Dictionary in actions:
        match String(action.get("type", "other")):
            "army_recruited":
                _record_event("Turn: %s recruited an army" % action.get("country_id", "?"))
            "war_declared":
                _record_event("Turn: %s declared war on %s" % [
                    action.get("country_id", "?"), action.get("target_id", "?")
                ])
            "army_moved":
                _record_event("Turn: moved %s from %s to %s, cost %dMP, remaining %dMP" % [
                    action.get("army_id", "?"),
                    action.get("origin", "?"),
                    action.get("destination", "?"),
                    action.get("movement_cost", 0),
                    action.get("remaining_points", 0),
                ])
            "battle_resolved":
                _record_event(_battle_action_report(action))
            "technology_researched":
                _record_event("Turn: %s researched technology" % action.get("country_id", "?"))


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
        label.text = "%s  ·  Treasury %d  ·  Provinces %d" % [
            country["name"], country["treasury"], country["province_count"]
        ]
        label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        label.add_theme_font_size_override("font_size", 20)
        label.add_theme_color_override(
            "font_color",
            Color8((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255)
        )
        $RightPanel/Center/CountryList.add_child(label)


func _battle_report(result: Dictionary) -> String:
    if not result.get("battle_occurred", false) and not result.get("province_occupied", false):
        return ""
    if not result.get("battle_occurred", false):
        return "Province occupied without resistance"
    var total_casualties := 0
    var details: Array[String] = []
    for outcome: Dictionary in result.get("battle_outcomes", []):
        var casualties := int(outcome.get("casualties", 0))
        total_casualties += casualties
        var suffix := ""
        if outcome.get("destroyed", false):
            suffix = " destroyed"
        elif String(outcome.get("retreat_province", "")) != "":
            suffix = " retreated to %s" % outcome["retreat_province"]
        details.append("%s -%d%s" % [outcome.get("army_id", "?"), casualties, suffix])
    return "Battle: %s; casualties %d%s | %s" % [
        "attacker victory" if result.get("attacker_won", false) else "defender victory",
        total_casualties,
        "; province occupied" if result.get("province_occupied", false) else "",
        ", ".join(details),
    ]


func _battle_action_report(action: Dictionary) -> String:
    if not action.get("battle_occurred", false):
        return "Turn: occupied %s without resistance" % action.get("province_id", "?")
    var details: Array[String] = []
    for outcome: Dictionary in action.get("battle_outcomes", []):
        var suffix := ""
        if outcome.get("destroyed", false):
            suffix = " destroyed"
        elif String(outcome.get("retreat_province", "")) != "":
            suffix = " retreated to %s" % outcome["retreat_province"]
        details.append("%s -%d, %d left%s" % [
            outcome.get("army_id", "?"),
            outcome.get("casualties", 0),
            outcome.get("remaining_manpower", 0),
            suffix,
        ])
    return "Turn battle at %s: %s, casualties %d%s | %s" % [
        action.get("province_id", "?"),
        "attacker victory" if action.get("attacker_won", false) else "defender victory",
        action.get("casualties", 0),
        ", occupied" if action.get("province_occupied", false) else "",
        ", ".join(details),
    ]


func _refresh_country_details() -> void:
    var status: Dictionary = bridge.get_game_status(PLAYER_COUNTRY_ID)
    var technology_by_country: Dictionary = {}
    for technology: Dictionary in bridge.get_technology_summaries():
        technology_by_country[technology["country_id"]] = technology
    var status_by_country: Dictionary = {}
    for country_status: Dictionary in status.get("countries", []):
        status_by_country[country_status["country_id"]] = country_status
    var war_pairs: Array[String] = []
    for relation: Dictionary in bridge.get_diplomatic_relations():
        if relation.get("status", "") == "war":
            war_pairs.append("%s-%s" % [relation["country_a"], relation["country_b"]])
    var lines: Array[String] = []
    for country: Dictionary in bridge.get_country_summaries():
        var tech: Dictionary = technology_by_country.get(country["id"], {})
        var state: Dictionary = status_by_country.get(country["id"], {})
        lines.append("%s | $%d | Ctrl %d | Tech E%d M%d R%d%s" % [
            country["name"],
            country["treasury"],
            state.get("controlled_provinces", country["province_count"]),
            tech.get("economy_level", 0),
            tech.get("military_level", 0),
            tech.get("roads_level", 0),
            " | eliminated" if state.get("eliminated", false) else "",
        ])
    if not war_pairs.is_empty():
        lines.append("Wars: %s" % ", ".join(war_pairs))
    country_details.text = "\n".join(lines)
    _refresh_war_overview()


func _refresh_war_overview() -> void:
    var wars: Array = bridge.get_war_summaries()
    if wars.is_empty():
        war_overview.text = "No active wars"
        return
    var lines: Array[String] = []
    for war: Dictionary in wars:
        lines.append("%s vs %s | MP %d:%d | Occ %d:%d | Fronts %d" % [
            war["country_a"], war["country_b"],
            war["country_a_manpower"], war["country_b_manpower"],
            war["country_a_occupied_provinces"], war["country_b_occupied_provinces"],
            war["front_edges"],
        ])
    war_overview.text = "\n".join(lines)


func _refresh_game_status() -> void:
    var status: Dictionary = bridge.get_game_status(PLAYER_COUNTRY_ID)
    if not status.get("has_scenario", false):
        $RightPanel/Center/GameStatus.text = "No active scenario"
        return
    if status.get("player_won", false):
        $RightPanel/Center/GameStatus.text = "Victory: Auroria controls the world"
    elif status.get("player_eliminated", false):
        $RightPanel/Center/GameStatus.text = "Defeat: Auroria has fallen"
    elif status.get("winner_id", "") != "":
        $RightPanel/Center/GameStatus.text = "Winner: %s" % status["winner_id"]
    else:
        var active := 0
        for country: Dictionary in status.get("countries", []):
            if not country.get("eliminated", false):
                active += 1
        $RightPanel/Center/GameStatus.text = "Active countries: %d" % active


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
        event_log.text = "Declare war failed: %s" % result.get("error", "unknown error")
        return
    event_log.text = "Event #%d: %s declared war on %s" % [
        result["event_sequence"], result["aggressor_id"], result["defender_id"]
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
        event_log.text = "Peace failed: %s" % result.get("error", "unknown error")
        return
    event_log.text = "Peace concluded: %d provinces settled, %d armies repatriated" % [
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
    _close_transient_workspace()
    var result: Dictionary = bridge.research_technology(PLAYER_COUNTRY_ID, track)
    if not result.get("accepted", false):
        event_log.text = "Research failed: %s" % result.get("error", "unknown error")
        return
    event_log.text = "Technology advanced to level %d; cost %d" % [
        result["current_level"], result["cost"]
    ]
    _record_event(event_log.text)
    _refresh_country_list()
    _refresh_country_details()
    _refresh_technology_status()


func _refresh_technology_status() -> void:
    for technology: Dictionary in bridge.get_technology_summaries():
        if technology["country_id"] != PLAYER_COUNTRY_ID:
            continue
        $RightPanel/Center/TechnologyControls/Status.text = "Economy %d | Military %d | Roads %d" % [
            technology["economy_level"],
            technology["military_level"],
            technology["roads_level"],
        ]
        return


func _on_quick_save_pressed() -> void:
    _close_transient_workspace()
    var path := ProjectSettings.globalize_path(QUICK_SAVE_PATH)
    var result: Dictionary = bridge.save_game(path)
    if not result.get("accepted", false):
        event_log.text = "Save failed: %s" % result.get("error", "unknown error")
        return
    event_log.text = "Game saved to quick_save.json"
    _record_event(event_log.text)


func _on_quick_load_pressed() -> void:
    _close_transient_workspace()
    var path := ProjectSettings.globalize_path(QUICK_SAVE_PATH)
    var result: Dictionary = bridge.load_game(path)
    if not result.get("accepted", false):
        event_log.text = "Load failed: %s" % result.get("error", "unknown error")
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
    event_log.text = "Game loaded from quick_save.json"
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
    _refresh_army_selector()
    _refresh_advance_plans()


func _refresh_army_selector() -> void:
    var previous_id := moving_army_id
    army_selector.clear()
    var selected_index := -1
    for army: Dictionary in bridge.get_army_summaries():
        if army["owner_id"] != PLAYER_COUNTRY_ID:
            continue
        var province_id: String = army["province_id"]
        var province_name: String = province_by_id.get(province_id, {}).get("name", province_id)
        army_selector.add_item("%s · %s · %d人 · %dMP" % [
            army["id"], province_name, army["manpower"], army["movement_points"]
        ])
        var index := army_selector.item_count - 1
        army_selector.set_item_metadata(index, army["id"])
        if army["id"] == previous_id:
            selected_index = index

    if army_selector.item_count == 0:
        moving_army_id = ""
        movement_origin_id = ""
        movement_destination_id = ""
        auto_advance_target_id = ""
        army_details.text = "No player armies"
        _refresh_movement_selection()
        return
    if selected_index < 0:
        selected_index = 0
    army_selector.select(selected_index)
    _select_army(String(army_selector.get_item_metadata(selected_index)))


func _on_army_selected(index: int) -> void:
    _close_transient_workspace()
    if index < 0 or index >= army_selector.item_count:
        return
    _select_army(String(army_selector.get_item_metadata(index)))


func _select_army(army_id: String) -> void:
    for army: Dictionary in bridge.get_army_summaries():
        if army["id"] != army_id:
            continue
        moving_army_id = army_id
        movement_origin_id = army["province_id"]
        movement_destination_id = ""
        auto_advance_target_id = army.get("advance_target_id", "")
        var province_name: String = province_by_id.get(movement_origin_id, {}).get(
            "name", movement_origin_id
        )
        army_details.text = "%s\n位置：%s · 兵力：%d · 移动力：%d" % [
            army_id, province_name, army["manpower"], army["movement_points"]
        ]
        _refresh_movement_selection()
        return


func _advance_stop_reason_text(reason: String) -> String:
    match reason:
        "target_reached":
            return "已到达目标"
        "enemy_border":
            return "将在敌方边境前停止"
        "insufficient_movement":
            return "移动点不足"
        "strategy_limit":
            return "单步推进策略限制"
        _:
            return reason


func _refresh_advance_plans() -> void:
    var lines: Array[String] = []
    var preview_months := 1
    if turn_length.item_count > 0:
        preview_months = int(turn_length.get_selected_metadata())
    for army: Dictionary in bridge.get_army_summaries():
        if army["owner_id"] != PLAYER_COUNTRY_ID:
            continue
        var target_id: String = army.get("advance_target_id", "")
        if target_id.is_empty():
            continue
        var is_enabled := bool(army.get("advance_enabled", true))
        var strategy: String = army.get("advance_strategy", "max")
        var origin_id: String = army["province_id"]
        var origin_name: String = province_by_id.get(origin_id, {"name": origin_id})["name"]
        var target_name: String = province_by_id.get(target_id, {"name": target_id})["name"]
        var path_preview: Dictionary = bridge.get_auto_advance_path_for_months(
            army["id"],
            target_id,
            preview_months
        )
        var status := "blocked"
        if not is_enabled:
            status = "paused"
        elif path_preview.get("accepted", false):
            var first_cost := int(path_preview.get("first_step_cost", 0))
            var preview_destination_id: String = path_preview.get(
                "preview_destination_id",
                origin_id
            )
            var preview_destination_name: String = province_by_id.get(
                preview_destination_id,
                {"name": preview_destination_id}
            )["name"]
            status = "%d step(s), first %dMP, total %dMP, ready %d+%dMP, next %s in %dmo (%d step, %dMP, %s)" % [
                path_preview.get("step_count", 0),
                first_cost,
                path_preview.get("total_movement_cost", 0),
                army.get("movement_points", 0),
                path_preview.get("preview_movement_granted", 0),
                preview_destination_name,
                preview_months,
                path_preview.get("preview_step_count", 0),
                path_preview.get("preview_movement_cost", 0),
                _advance_stop_reason_text(path_preview.get("preview_stop_reason", "unknown")),
            ]
        else:
            status = "blocked: %s" % path_preview.get("error", "unknown")
        var toggle_command := "pause" if is_enabled else "resume"
        var toggle_label := "pause" if is_enabled else "resume"
        var next_strategy := "one_step"
        var strategy_label := "one-step"
        if strategy == "one_step":
            next_strategy = "stop_before_enemy"
            strategy_label = "border-stop"
        elif strategy == "stop_before_enemy":
            next_strategy = "max"
            strategy_label = "max"
        lines.append("[url=select:%s]%s[/url]: %s => %s | %s | strategy %s [url=strategy:%s:%s][%s][/url] [url=%s:%s][%s][/url] [url=clear:%s][clear][/url]" % [
            army["id"],
            army["id"], origin_name, target_name, status,
            strategy,
            army["id"],
            next_strategy,
            strategy_label,
            toggle_command,
            army["id"],
            toggle_label,
            army["id"],
        ])
    if lines.is_empty():
        advance_plans.text = "No advance plans"
    else:
        advance_plans.text = "[b]Advance plans[/b]\n%s" % "\n".join(lines)


func _on_advance_plan_clicked(meta: Variant) -> void:
    _close_transient_workspace()
    var command := String(meta)
    if command.is_empty():
        return
    if command.begins_with("clear:"):
        var army_id := command.trim_prefix("clear:")
        var result: Dictionary = bridge.clear_army_advance_target(army_id)
        if not result.get("accepted", false):
            event_log.text = "Clear advance plan failed: %s" % result.get("error", "unknown")
            return
        if army_id == moving_army_id:
            auto_advance_target_id = ""
            province_map.set_auto_advance_path([])
            _refresh_movement_selection()
        _refresh_map_data()
        _refresh_advance_plans()
        _record_event("Cleared advance plan: %s" % army_id)
        return
    if command.begins_with("pause:") or command.begins_with("resume:"):
        var enabled := command.begins_with("resume:")
        var separator := command.find(":")
        var army_id := command.substr(separator + 1)
        var result: Dictionary = bridge.set_army_advance_enabled(army_id, enabled)
        if not result.get("accepted", false):
            event_log.text = "Toggle advance plan failed: %s" % result.get("error", "unknown")
            return
        _refresh_map_data()
        _refresh_advance_plans()
        _refresh_movement_selection()
        _record_event("%s advance plan: %s" % [
            "Resumed" if enabled else "Paused",
            army_id,
        ])
        return
    if command.begins_with("strategy:"):
        var parts := command.split(":")
        if parts.size() != 3:
            return
        var army_id := String(parts[1])
        var strategy := String(parts[2])
        var result: Dictionary = bridge.set_army_advance_strategy(army_id, strategy)
        if not result.get("accepted", false):
            event_log.text = "Set advance strategy failed: %s" % result.get("error", "unknown")
            return
        _refresh_map_data()
        _refresh_advance_plans()
        _refresh_movement_selection()
        _record_event("Set advance strategy: %s -> %s" % [army_id, strategy])
        return
    var army_id := command.trim_prefix("select:")
    _select_army_in_selector(army_id)
    _record_event("Selected advance plan: %s" % army_id)


func _select_army_in_selector(army_id: String) -> void:
    for index: int in range(army_selector.item_count):
        if String(army_selector.get_item_metadata(index)) == army_id:
            army_selector.select(index)
            _select_army(army_id)
            return


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
    _refresh_movement_selection()


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
    if not province_map.selected_province_id().is_empty():
        _show_province_details(province_map.selected_province_id())
    _refresh_movement_selection()
    var total_income := 0
    for income: Dictionary in result["incomes"]:
        total_income += int(income["amount"])
    var total_growth := 0
    for change: Dictionary in result["population_changes"]:
        total_growth += int(change["growth"])
    event_log.text = "事件 #%d：推进%d个月，收入%d，人口+%d（原日期 %d-%02d）" % [
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
        event_log.text += " | Turn actions: %d" % turn_action_count
        _record_turn_actions(turn_actions)
    _record_event(event_log.text)


func _refresh_date() -> void:
    var date: Dictionary = bridge.get_current_date()
    date_label.text = "当前日期：%d年%02d月" % [date["year"], date["month"]]


func _on_province_selected(province_id: String) -> void:
    if map_input_mode == MapInputMode.ARMY_DESTINATION:
        _select_management_destination(province_id)
        return
    if map_input_mode in [MapInputMode.ROAD_START, MapInputMode.ROAD_END]:
        _select_road_endpoint(province_id)
        return
    if province_id.is_empty():
        $RightPanel/Center/SelectionStatus.text = "请选择一个地区"
        region_details.text = "Select a province for details"
        recruit_button.disabled = true
        return
    _show_province_details(province_id)
    var province: Dictionary = province_by_id[province_id]
    recruit_button.disabled = province["owner_id"] != PLAYER_COUNTRY_ID
    $RightPanel/Center/ArmyControls/ArmyHint.text = (
        "可从此地区招募" if not recruit_button.disabled else "只能从奥罗里亚地区招募"
    )
    _update_movement_from_province(province_id)


func _show_province_details(province_id: String) -> void:
    var province: Dictionary = province_by_id[province_id]
    var stationed_manpower := 0
    var stationed_armies := 0
    for army: Dictionary in bridge.get_army_summaries():
        if army["province_id"] == province_id:
            stationed_manpower += int(army["manpower"])
            stationed_armies += 1
    $RightPanel/Center/SelectionStatus.text = "%s · %s · 人口%d · 可招募士兵%d · 经济%d" % [
        province["name"],
        province.get("terrain", "plains"),
        province["population"],
        province["recruitable_population"],
        province["economy"],
    ]
    if stationed_manpower > 0:
        $RightPanel/Center/SelectionStatus.text += " · 驻军%d" % stationed_manpower
    region_details.text = "Region: %s\nOwner: %s | Legal: %s | Terrain: %s\nPopulation: %d | 可招募士兵: %d | Economy: %d\nArmies: %d | Manpower: %d | Neighbors: %d%s" % [
        province["name"],
        province["owner_id"],
        province.get("legal_owner_id", province["owner_id"]),
        province.get("terrain", "plains"),
        province["population"],
        province["recruitable_population"],
        province["economy"],
        stationed_armies,
        stationed_manpower,
        province.get("neighbor_count", 0),
        " | occupied" if province.get("occupied", false) else "",
    ]


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


func _on_recruit_army_pressed() -> void:
    _close_transient_workspace()
    var province_id: String = province_map.selected_province_id()
    if province_id.is_empty():
        return
    var result: Dictionary = bridge.recruit_army(
        PLAYER_COUNTRY_ID,
        province_id,
        1000
    )
    if not result.get("accepted", false):
        event_log.text = "招募失败：%s" % result.get("error", "未知错误")
        return

    event_log.text = "事件 #%d：%s 招募%d人，支出%d" % [
        result["event_sequence"],
        result["army_id"],
        result["manpower"],
        result["cost"],
    ]
    _record_event(event_log.text)
    _refresh_country_list()
    _refresh_country_details()
    _refresh_map_data()
    _refresh_province_summary()
    _show_province_details(province_id)
    moving_army_id = result["army_id"]
    movement_origin_id = province_id
    movement_destination_id = ""
    auto_advance_target_id = ""
    _refresh_army_selector()
    _refresh_movement_selection()


func _on_move_army_pressed() -> void:
    _close_transient_workspace()
    if moving_army_id.is_empty() or movement_destination_id.is_empty():
        return
    var result: Dictionary = bridge.move_army(moving_army_id, movement_destination_id)
    if not result.get("accepted", false):
        event_log.text = "移动失败：%s" % result.get("error", "未知错误")
        return

    event_log.text = "事件 #%d：%s → %s，消耗%d移动点，剩余%d" % [
        result["event_sequence"],
        result["origin"],
        result["destination"],
        result["movement_cost"],
        result["remaining_points"],
    ]
    var battle_report := _battle_report(result)
    if not battle_report.is_empty():
        event_log.text = battle_report
    _record_event(event_log.text)
    movement_origin_id = result.get("army_province_id", result["destination"])
    movement_destination_id = ""
    auto_advance_target_id = ""
    bridge.clear_army_advance_target(moving_army_id)
    _refresh_map_data()
    _refresh_country_details()
    _refresh_game_status()
    _refresh_advance_plans()
    if result.get("army_destroyed", false):
        _clear_movement_selection()
        return
    _show_province_details(movement_origin_id)
    _refresh_movement_selection()


func _on_auto_advance_pressed() -> void:
    _close_transient_workspace()
    if moving_army_id.is_empty():
        return
    var result: Dictionary = {}
    if auto_advance_target_id.is_empty():
        result = bridge.auto_advance_army(moving_army_id)
    else:
        result = bridge.auto_advance_army_to(moving_army_id, auto_advance_target_id)
    if not result.get("accepted", false):
        event_log.text = "自动推进失败：%s" % result.get("error", "未知错误")
        return

    event_log.text = "Auto advance: %s -> %s, %d step(s), cost %d MP, remaining %d" % [
        result["origin"],
        result["destination"],
        result.get("auto_step_count", 1),
        result["movement_cost"],
        result["remaining_points"],
    ]
    var battle_report := _battle_report(result)
    if not battle_report.is_empty():
        event_log.text = battle_report
    _record_event(event_log.text)
    movement_origin_id = result.get("army_province_id", result["destination"])
    movement_destination_id = ""
    auto_advance_target_id = ""
    _refresh_map_data()
    _refresh_country_details()
    _refresh_game_status()
    _refresh_advance_plans()
    if result.get("army_destroyed", false):
        _clear_movement_selection()
        return
    _show_province_details(movement_origin_id)
    _refresh_movement_selection()


func _update_movement_from_province(province_id: String) -> void:
    if moving_army_id.is_empty():
        var army := _find_player_army_in_province(province_id)
        if not army.is_empty():
            moving_army_id = army["id"]
            movement_origin_id = province_id
            movement_destination_id = ""
            auto_advance_target_id = ""
    elif province_id != movement_origin_id:
        if _are_provinces_adjacent(movement_origin_id, province_id):
            movement_destination_id = province_id
            auto_advance_target_id = ""
            bridge.clear_army_advance_target(moving_army_id)
        else:
            movement_destination_id = ""
            auto_advance_target_id = province_id
            var target_result: Dictionary = bridge.set_army_advance_target(
                moving_army_id,
                auto_advance_target_id
            )
            if not target_result.get("accepted", false):
                event_log.text = "Set advance target failed: %s" % target_result.get(
                    "error", "unknown"
                )
                auto_advance_target_id = ""
            _refresh_advance_plans()
    _refresh_movement_selection()


func _are_provinces_adjacent(origin_id: String, target_id: String) -> bool:
    var origin: Dictionary = province_by_id.get(origin_id, {})
    for neighbor_id in origin.get("neighbors", []):
        if String(neighbor_id) == target_id:
            return true
    return false


func _find_player_army_in_province(province_id: String) -> Dictionary:
    for army: Dictionary in bridge.get_army_summaries():
        if army["owner_id"] == PLAYER_COUNTRY_ID and army["province_id"] == province_id:
            return army
    return {}


func _clear_movement_selection() -> void:
    if not moving_army_id.is_empty():
        bridge.clear_army_advance_target(moving_army_id)
    moving_army_id = ""
    movement_origin_id = ""
    movement_destination_id = ""
    auto_advance_target_id = ""
    _refresh_advance_plans()
    _refresh_movement_selection()


func _refresh_movement_selection() -> void:
    move_army_button.disabled = (
        moving_army_id.is_empty() or movement_destination_id.is_empty()
    )
    auto_advance_button.disabled = moving_army_id.is_empty()
    province_map.set_auto_advance_path([])
    if moving_army_id.is_empty():
        $RightPanel/Center/ArmyControls/MovementStatus.text = "移动：请选择有己方军队的地区"
        return

    var movement_points := 0
    for army: Dictionary in bridge.get_army_summaries():
        if army["id"] == moving_army_id:
            movement_points = int(army["movement_points"])
            break
    if not auto_advance_target_id.is_empty():
        var preview_months := 1
        if turn_length.item_count > 0:
            preview_months = int(turn_length.get_selected_metadata())
        var path_preview: Dictionary = bridge.get_auto_advance_path_for_months(
            moving_army_id,
            auto_advance_target_id,
            preview_months
        )
        var preview_text := "no path"
        if path_preview.get("accepted", false):
            province_map.set_auto_advance_paths(
                path_preview.get("path", []),
                path_preview.get("preview_path", []),
                path_preview.get("preview_stop_reason", "unknown")
            )
            var first_step_cost := int(path_preview.get("first_step_cost", 0))
            auto_advance_button.disabled = (
                int(path_preview.get("step_count", 0)) <= 0 or
                movement_points < first_step_cost
            )
            preview_text = "%d step(s), first %dMP, total %dMP, turn %dmo: %d step, %dMP, %s" % [
                path_preview.get("step_count", 0),
                first_step_cost,
                path_preview.get("total_movement_cost", 0),
                preview_months,
                path_preview.get("preview_step_count", 0),
                path_preview.get("preview_movement_cost", 0),
                _advance_stop_reason_text(path_preview.get("preview_stop_reason", "unknown")),
            ]
        else:
            auto_advance_button.disabled = true
            preview_text = "blocked: %s" % path_preview.get("error", "unknown")
        $RightPanel/Center/ArmyControls/MovementStatus.text = "Auto target: %s · %s => %s · %s · ready %dMP" % [
            moving_army_id,
            province_by_id[movement_origin_id]["name"],
            province_by_id[auto_advance_target_id]["name"],
            preview_text,
            movement_points,
        ]
        return
    if movement_destination_id.is_empty():
        $RightPanel/Center/ArmyControls/MovementStatus.text = "%s（%dMP）· 请选择目的地" % [
            moving_army_id, movement_points
        ]
    else:
        $RightPanel/Center/ArmyControls/MovementStatus.text = "%s：%s → %s（%dMP）" % [
            moving_army_id,
            province_by_id[movement_origin_id]["name"],
            province_by_id[movement_destination_id]["name"],
            movement_points,
        ]


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
