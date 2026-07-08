extends Control

const PLAYER_COUNTRY_ID := "auroria"
const QUICK_SAVE_PATH := "user://quick_save.json"

@onready var bridge := $SimulationBridge
@onready var date_label: Label = $Center/TurnControls/DateLabel
@onready var turn_length: OptionButton = $Center/TurnControls/TurnLength
@onready var event_log: Label = $Center/EventLog
@onready var event_history: RichTextLabel = $Center/EventHistory
@onready var country_details: RichTextLabel = $Center/CountryDetails
@onready var war_overview: RichTextLabel = $Center/WarOverview
@onready var region_details: RichTextLabel = $Center/RegionDetails
@onready var province_map := $MapPanel/ProvinceMap
@onready var recruit_button: Button = $Center/ArmyControls/RecruitArmy
@onready var move_army_button: Button = $Center/ArmyControls/MovementButtons/MoveArmy
@onready var auto_advance_button: Button = $Center/ArmyControls/MovementButtons/AutoAdvance
@onready var army_selector: OptionButton = $Center/ArmyControls/ArmySelector
@onready var army_details: Label = $Center/ArmyControls/ArmyDetails
@onready var war_target: OptionButton = $Center/DiplomacyControls/WarTarget
@onready var peace_policy: OptionButton = $Center/DiplomacyControls/PeacePolicy

var province_by_id: Dictionary = {}
var road_start_id := ""
var road_end_id := ""
var moving_army_id := ""
var movement_origin_id := ""
var movement_destination_id := ""
var event_history_lines: Array[String] = []

func _ready() -> void:
    if not province_map.load_map_geometry("res://data/map_geometry.json"):
        $Center/Status.text = "Map load failed: %s" % province_map.geometry_error()
        push_error(province_map.geometry_error())
        return
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
    auto_advance_button.pressed.connect(_on_auto_advance_pressed)
    army_selector.item_selected.connect(_on_army_selected)
    $Center/DiplomacyControls/DeclareWar.pressed.connect(_on_declare_war_pressed)
    $Center/DiplomacyControls/MakePeace.pressed.connect(_on_make_peace_pressed)
    $Center/TechnologyControls/Buttons/Economy.pressed.connect(
        _on_research_technology.bind("economy")
    )
    $Center/TechnologyControls/Buttons/Military.pressed.connect(
        _on_research_technology.bind("military")
    )
    $Center/TechnologyControls/Buttons/Roads.pressed.connect(
        _on_research_technology.bind("roads")
    )
    $Center/SaveControls/Save.pressed.connect(_on_quick_save_pressed)
    $Center/SaveControls/Load.pressed.connect(_on_quick_load_pressed)
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

    print($Center/Status.text)
    _record_event("Scenario loaded: %d provinces" % provinces.size())


func _record_event(message: String) -> void:
    if message.is_empty():
        return
    event_history_lines.append(message)
    while event_history_lines.size() > 80:
        event_history_lines.pop_front()
    event_history.text = "\n".join(event_history_lines)


func _record_ai_actions(actions: Array) -> void:
    for action: Dictionary in actions:
        match String(action.get("type", "other")):
            "army_recruited":
                _record_event("AI %s recruited an army" % action.get("country_id", "?"))
            "war_declared":
                _record_event("AI %s declared war on %s" % [
                    action.get("country_id", "?"), action.get("target_id", "?")
                ])
            "army_moved":
                _record_event("AI moved %s" % action.get("army_id", "?"))
            "battle_resolved":
                var battle_text := "AI occupied %s without resistance" % action.get("province_id", "?")
                if action.get("battle_occurred", false):
                    battle_text = "AI battle at %s: %s, casualties %d%s" % [
                        action.get("province_id", "?"),
                        "attacker victory" if action.get("attacker_won", false) else "defender victory",
                        action.get("casualties", 0),
                        ", occupied" if action.get("province_occupied", false) else "",
                    ]
                _record_event(battle_text)
            "technology_researched":
                _record_event("AI %s researched technology" % action.get("country_id", "?"))


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
        $Center/GameStatus.text = "No active scenario"
        return
    if status.get("player_won", false):
        $Center/GameStatus.text = "Victory: Auroria controls the world"
    elif status.get("player_eliminated", false):
        $Center/GameStatus.text = "Defeat: Auroria has fallen"
    elif status.get("winner_id", "") != "":
        $Center/GameStatus.text = "Winner: %s" % status["winner_id"]
    else:
        var active := 0
        for country: Dictionary in status.get("countries", []):
            if not country.get("eliminated", false):
                active += 1
        $Center/GameStatus.text = "Active countries: %d" % active


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
    _record_event(event_log.text)


func _on_make_peace_pressed() -> void:
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
        $Center/TechnologyControls/Status.text = "Economy %d | Military %d | Roads %d" % [
            technology["economy_level"],
            technology["military_level"],
            technology["roads_level"],
        ]
        return


func _on_quick_save_pressed() -> void:
    var path := ProjectSettings.globalize_path(QUICK_SAVE_PATH)
    var result: Dictionary = bridge.save_game(path)
    if not result.get("accepted", false):
        event_log.text = "Save failed: %s" % result.get("error", "unknown error")
        return
    event_log.text = "Game saved to quick_save.json"
    _record_event(event_log.text)


func _on_quick_load_pressed() -> void:
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
        army_details.text = "No player armies"
        _refresh_movement_selection()
        return
    if selected_index < 0:
        selected_index = 0
    army_selector.select(selected_index)
    _select_army(String(army_selector.get_item_metadata(selected_index)))


func _on_army_selected(index: int) -> void:
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
        var province_name: String = province_by_id.get(movement_origin_id, {}).get(
            "name", movement_origin_id
        )
        army_details.text = "%s\n位置：%s · 兵力：%d · 移动力：%d" % [
            army_id, province_name, army["manpower"], army["movement_points"]
        ]
        _refresh_movement_selection()
        return


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
    var ai_action_count: int = result.get("ai_actions", []).size()
    if ai_action_count > 0:
        event_log.text += " | AI actions: %d" % ai_action_count
        _record_ai_actions(result.get("ai_actions", []))
    _record_event(event_log.text)


func _refresh_date() -> void:
    var date: Dictionary = bridge.get_current_date()
    date_label.text = "当前日期：%d年%02d月" % [date["year"], date["month"]]


func _on_province_selected(province_id: String) -> void:
    if province_id.is_empty():
        $Center/SelectionStatus.text = "请选择一个地区"
        region_details.text = "Select a province for details"
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
    var stationed_armies := 0
    for army: Dictionary in bridge.get_army_summaries():
        if army["province_id"] == province_id:
            stationed_manpower += int(army["manpower"])
            stationed_armies += 1
    $Center/SelectionStatus.text = "%s · %s · 人口%d · 士兵%d · 经济%d" % [
        province["name"],
        province.get("terrain", "plains"),
        province["population"],
        province["soldier_population"],
        province["economy"],
    ]
    if stationed_manpower > 0:
        $Center/SelectionStatus.text += " · 驻军%d" % stationed_manpower
    region_details.text = "Region: %s\nOwner: %s | Legal: %s | Terrain: %s\nPopulation: %d | Soldiers: %d | Economy: %d\nArmies: %d | Manpower: %d | Neighbors: %d%s" % [
        province["name"],
        province["owner_id"],
        province.get("legal_owner_id", province["owner_id"]),
        province.get("terrain", "plains"),
        province["population"],
        province["soldier_population"],
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
    _record_event(event_log.text)
    _refresh_country_list()
    _refresh_country_details()
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
    _record_event(event_log.text)
    _refresh_country_list()
    _refresh_country_details()
    _refresh_map_data()
    _refresh_province_summary()
    _show_province_details(province_id)
    moving_army_id = result["army_id"]
    movement_origin_id = province_id
    movement_destination_id = ""
    _refresh_army_selector()
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
    var battle_report := _battle_report(result)
    if not battle_report.is_empty():
        event_log.text = battle_report
    _record_event(event_log.text)
    movement_origin_id = result.get("army_province_id", result["destination"])
    movement_destination_id = ""
    _refresh_map_data()
    _refresh_country_details()
    _refresh_game_status()
    if result.get("army_destroyed", false):
        _clear_movement_selection()
        return
    _show_province_details(movement_origin_id)
    _refresh_movement_selection()


func _on_auto_advance_pressed() -> void:
    if moving_army_id.is_empty():
        return
    var result: Dictionary = {}
    if movement_destination_id.is_empty():
        result = bridge.auto_advance_army(moving_army_id)
    else:
        result = bridge.auto_advance_army_to(moving_army_id, movement_destination_id)
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
    _refresh_map_data()
    _refresh_country_details()
    _refresh_game_status()
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
    auto_advance_button.disabled = moving_army_id.is_empty()
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
