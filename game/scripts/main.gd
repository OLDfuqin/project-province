extends Control

@onready var bridge := $SimulationBridge
@onready var date_label: Label = $Center/TurnControls/DateLabel
@onready var turn_length: OptionButton = $Center/TurnControls/TurnLength
@onready var event_log: Label = $Center/EventLog
@onready var province_map := $MapPanel/ProvinceMap

var province_by_id: Dictionary = {}

func _ready() -> void:
    var data_directory := ProjectSettings.globalize_path("res://data")
    if not bridge.load_scenario(data_directory, 1000, 1):
        $Center/Status.text = "Scenario load failed: %s" % bridge.get_last_error()
        push_error(bridge.get_last_error())
        return

    var provinces: Array = bridge.get_province_summaries()
    var countries: Array = bridge.get_country_summaries()
    for province: Dictionary in provinces:
        province_by_id[province["id"]] = province
    province_map.set_scenario_data(provinces, countries)
    province_map.province_selected.connect(_on_province_selected)
    province_map.province_hovered.connect(_on_province_hovered)
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
    _refresh_province_summary()
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
        return
    var province: Dictionary = province_by_id[province_id]
    $Center/SelectionStatus.text = "%s · 人口%d · 士兵%d · 经济%d" % [
        province["name"],
        province["population"],
        province["soldier_population"],
        province["economy"],
    ]


func _on_province_hovered(province_id: String) -> void:
    province_map.tooltip_text = "" if province_id.is_empty() else str(
        province_by_id[province_id]["name"]
    )
