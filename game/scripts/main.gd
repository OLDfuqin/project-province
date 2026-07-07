extends Control


func _ready() -> void:
    var bridge := $SimulationBridge
    var data_directory := ProjectSettings.globalize_path("res://data")
    if not bridge.load_scenario(data_directory, 1000, 1):
        $Center/Status.text = "Scenario load failed: %s" % bridge.get_last_error()
        push_error(bridge.get_last_error())
        return

    var countries: Array = bridge.get_country_summaries()
    var provinces: Array = bridge.get_province_summaries()
    $Center/Status.text = "Core %s · %d countries · %d provinces" % [
        bridge.get_core_version(), countries.size(), provinces.size()
    ]
    $Center/ProvinceSummary.text = "Scenario year 1000 · Full world simulation ready"

    for country: Dictionary in countries:
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

    print($Center/Status.text)
