extends Control

const PLAYER_COUNTRY_ID := "auroria"

@onready var bridge := $SimulationBridge
@onready var date_label: Label = $Center/TurnControls/DateLabel
@onready var turn_length: OptionButton = $Center/TurnControls/TurnLength
@onready var event_log: Label = $Center/EventLog
@onready var province_map := $MapPanel/ProvinceMap
@onready var recruit_button: Button = $Center/ArmyControls/RecruitArmy
@onready var move_army_button: Button = $Center/ArmyControls/MovementButtons/MoveArmy
@onready var war_target: OptionButton = $Center/DiplomacyControls/WarTarget

var province_by_id: Dictionary = {}
var road_start_id := ""
var road_end_id := ""
var moving_army_id := ""
var movement_origin_id := ""
var movement_destination_id := ""

func _ready() -> void:
    var data_directory := ProjectSettings.globalize_path("res://data")
    if not bridge.load_scenario(data_directory, 1000, 1):
        $Center/Status.text = "Scenario load failed: %s" % bridge.get_last_error()
        push_error(bridge.get_last_error())
        return

    _refresh_map_data()
    province_map.province_selected.connect(_on_province_selected)
    province_map.province_hovered.connect(_on_province_hovered)
    $Center/RoadControls/Buttons/BuildRoad.pressed.connect(_on_build_road_pressed)
    $Center/RoadControls/Buttons/ClearRoad.pressed.connect(_clear_road_selection)
    recruit_button.pressed.connect(_on_recruit_army_pressed)
    move_army_button.pressed.connect(_on_move_army_pressed)
    $Center/DiplomacyControls/DeclareWar.pressed.connect(_on_declare_war_pressed)
    $Center/ArmyControls/MovementButtons/ClearMovement.pressed.connect(
        _clear_movement_selection
    )
    var provinces: Array = bridge.get_province_summaries()
    var countries: Array = bridge.get_country_summaries()
    $Center/Status.text = "Core %s · %d countries · %d provinces" % [
        bridge.get_core_version(), countries.size(), provinces.size()
    ]
    _refresh_province_summary()

    for months: int in [1, 3, 6, 12]:
        turn_length.add_item("%d个月" % months)
        turn_length.set_item_metadata(turn_length.item_count - 1, months)
    turn_length.select(0)
    $Center/TurnControls/AdvanceTurn.pressed.connect(_on_advance_turn_pressed)
    _refresh_date()

    _refresh_country_list()
    _populate_war_targets()

    print($Center/Status.text)


func _refresh_country_list() -> void:
    for child: Node in $Center/CountryList.get_children():
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
        $Center/CountryList.add_child(label)


func _populate_war_targets() -> void:
    war_target.clear()
    for country: Dictionary in bridge.get_country_summaries():
        if country["id"] == PLAYER_COUNTRY_ID:
            continue
        war_target.add_item(country["name"])
        war_target.set_item_metadata(war_target.item_count - 1, country["id"])


func _on_declare_war_pressed() -> void:
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


func _refresh_map_data() -> void:
    var provinces: Array = bridge.get_province_summaries()
    var countries: Array = bridge.get_country_summaries()
    province_by_id.clear()
    for province: Dictionary in provinces:
        province_by_id[province["id"]] = province
    province_map.set_scenario_data(provinces, countries)
    province_map.set_roads(bridge.get_road_summaries())
    province_map.set_armies(bridge.get_army_summaries())


func _refresh_province_summary() -> void:
    var total_population := 0
    var soldier_population := 0
    for province: Dictionary in bridge.get_province_summaries():
        total_population += int(province["population"])
        soldier_population += int(province["soldier_population"])
    $Center/ProvinceSummary.text = "总人口 %d · 士兵人口 %d" % [
        total_population, soldier_population
    ]


func _on_advance_turn_pressed() -> void:
    var months: int = turn_length.get_selected_metadata()
    var result: Dictionary = bridge.advance_turn(months)
    if not result.get("accepted", false):
        event_log.text = "命令被拒绝：%s" % result.get("error", "未知错误")
        return

    _refresh_date()
    _refresh_country_list()
    _refresh_map_data()
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


func _refresh_date() -> void:
    var date: Dictionary = bridge.get_current_date()
    date_label.text = "当前日期：%d年%02d月" % [date["year"], date["month"]]


func _on_province_selected(province_id: String) -> void:
    if province_id.is_empty():
        $Center/SelectionStatus.text = "请选择一个地区"
        recruit_button.disabled = true
        return
    _show_province_details(province_id)
    var province: Dictionary = province_by_id[province_id]
    recruit_button.disabled = province["owner_id"] != PLAYER_COUNTRY_ID
    $Center/ArmyControls/ArmyHint.text = (
        "可从此地区招募" if not recruit_button.disabled else "只能从奥罗里亚地区招募"
    )
    if road_start_id.is_empty():
        road_start_id = province_id
        road_end_id = ""
    elif road_end_id.is_empty() and province_id != road_start_id:
        road_end_id = province_id
    else:
        road_start_id = province_id
        road_end_id = ""
    _refresh_road_selection()
    _update_movement_from_province(province_id)


func _show_province_details(province_id: String) -> void:
    var province: Dictionary = province_by_id[province_id]
    var stationed_manpower := 0
    for army: Dictionary in bridge.get_army_summaries():
        if army["province_id"] == province_id:
            stationed_manpower += int(army["manpower"])
    $Center/SelectionStatus.text = "%s · 人口%d · 士兵%d · 经济%d" % [
        province["name"],
        province["population"],
        province["soldier_population"],
        province["economy"],
    ]
    if stationed_manpower > 0:
        $Center/SelectionStatus.text += " · 驻军%d" % stationed_manpower


func _on_province_hovered(province_id: String) -> void:
    province_map.tooltip_text = "" if province_id.is_empty() else str(
        province_by_id[province_id]["name"]
    )


func _on_build_road_pressed() -> void:
    if road_start_id.is_empty() or road_end_id.is_empty():
        return
    var result: Dictionary = bridge.build_road(
        PLAYER_COUNTRY_ID,
        road_start_id,
        road_end_id
    )
    if not result.get("accepted", false):
        event_log.text = "修路失败：%s" % result.get("error", "未知错误")
        return

    event_log.text = "事件 #%d：公路建成，支出%d" % [
        result["event_sequence"], result["cost"]
    ]
    _refresh_country_list()
    _refresh_map_data()
    _clear_road_selection()


func _on_recruit_army_pressed() -> void:
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
    _refresh_country_list()
    _refresh_map_data()
    _refresh_province_summary()
    _show_province_details(province_id)
    moving_army_id = result["army_id"]
    movement_origin_id = province_id
    movement_destination_id = ""
    _refresh_movement_selection()


func _on_move_army_pressed() -> void:
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
    if result.get("battle_occurred", false):
        var total_casualties := 0
        for outcome: Dictionary in result.get("battle_outcomes", []):
            total_casualties += int(outcome.get("casualties", 0))
        event_log.text = "Battle resolved: %s; casualties %d%s" % [
            "attacker victory" if result.get("attacker_won", false) else "defender victory",
            total_casualties,
            "; province occupied" if result.get("province_occupied", false) else "",
        ]
    elif result.get("province_occupied", false):
        event_log.text = "Province occupied without resistance"
    movement_origin_id = result.get("army_province_id", result["destination"])
    movement_destination_id = ""
    _refresh_map_data()
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
    elif province_id != movement_origin_id:
        movement_destination_id = province_id
    _refresh_movement_selection()


func _find_player_army_in_province(province_id: String) -> Dictionary:
    for army: Dictionary in bridge.get_army_summaries():
        if army["owner_id"] == PLAYER_COUNTRY_ID and army["province_id"] == province_id:
            return army
    return {}


func _clear_movement_selection() -> void:
    moving_army_id = ""
    movement_origin_id = ""
    movement_destination_id = ""
    _refresh_movement_selection()


func _refresh_movement_selection() -> void:
    move_army_button.disabled = (
        moving_army_id.is_empty() or movement_destination_id.is_empty()
    )
    if moving_army_id.is_empty():
        $Center/ArmyControls/MovementStatus.text = "移动：请选择有己方军队的地区"
        return

    var movement_points := 0
    for army: Dictionary in bridge.get_army_summaries():
        if army["id"] == moving_army_id:
            movement_points = int(army["movement_points"])
            break
    if movement_destination_id.is_empty():
        $Center/ArmyControls/MovementStatus.text = "%s（%dMP）· 请选择目的地" % [
            moving_army_id, movement_points
        ]
    else:
        $Center/ArmyControls/MovementStatus.text = "%s：%s → %s（%dMP）" % [
            moving_army_id,
            province_by_id[movement_origin_id]["name"],
            province_by_id[movement_destination_id]["name"],
            movement_points,
        ]


func _clear_road_selection() -> void:
    road_start_id = ""
    road_end_id = ""
    _refresh_road_selection()


func _refresh_road_selection() -> void:
    province_map.set_road_selection(road_start_id, road_end_id)
    $Center/RoadControls/Buttons/BuildRoad.disabled = (
        road_start_id.is_empty() or road_end_id.is_empty()
    )
    if road_start_id.is_empty():
        $Center/RoadControls/RoadSelection.text = "修路：请选择起点（当前玩家：奥罗里亚）"
    elif road_end_id.is_empty():
        $Center/RoadControls/RoadSelection.text = "起点：%s · 请选择终点" % [
            province_by_id[road_start_id]["name"]
        ]
    else:
        $Center/RoadControls/RoadSelection.text = "路线：%s → %s" % [
            province_by_id[road_start_id]["name"],
            province_by_id[road_end_id]["name"],
        ]
