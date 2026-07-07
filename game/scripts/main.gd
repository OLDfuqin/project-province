extends Control

@onready var bridge := $SimulationBridge
@onready var date_label: Label = $Center/TurnControls/DateLabel
@onready var turn_length: OptionButton = $Center/TurnControls/TurnLength
@onready var event_log: Label = $Center/EventLog

func _ready() -> void:
    var data_directory := ProjectSettings.globalize_path("res://data")
    if not bridge.load_scenario(data_directory, 1000, 1):
        $Center/Status.text = "Scenario load failed: %s" % bridge.get_last_error()
        push_error(bridge.get_last_error())
        return

    var provinces: Array = bridge.get_province_summaries()
    var countries: Array = bridge.get_country_summaries()
    $Center/Status.text = "Core %s · %d countries · %d provinces" % [
        bridge.get_core_version(), countries.size(), provinces.size()
    ]
    $Center/ProvinceSummary.text = "Scenario year 1000 · Full world simulation ready"

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


func _on_advance_turn_pressed() -> void:
    var months: int = turn_length.get_selected_metadata()
    var result: Dictionary = bridge.advance_turn(months)
    if not result.get("accepted", false):
        event_log.text = "命令被拒绝：%s" % result.get("error", "未知错误")
        return

    _refresh_date()
    _refresh_country_list()
    var total_income := 0
    for income: Dictionary in result["incomes"]:
        total_income += int(income["amount"])
    event_log.text = "事件 #%d：推进%d个月，四国总收入%d（原日期 %d-%02d）" % [
        result["event_sequence"],
        result["elapsed_months"],
        total_income,
        result["previous_year"],
        result["previous_month"],
    ]


func _refresh_date() -> void:
    var date: Dictionary = bridge.get_current_date()
    date_label.text = "当前日期：%d年%02d月" % [date["year"], date["month"]]
