class_name GlobalStatusBar
extends PanelContainer

signal advance_turn_requested


func _ready() -> void:
    $Margin/Row/AdvanceTurn.pressed.connect(func() -> void:
        advance_turn_requested.emit()
    )


func set_snapshot(country: Dictionary, date: Dictionary) -> void:
    $Margin/Row/CountryName.text = String(country.get("name", "未知国家"))
    $Margin/Row/Treasury.text = "国库 %s" % _number(country.get("treasury", 0))
    $Margin/Row/Income.text = "月收入 %s" % _number(country.get("fiscal_income", 0))
    $Margin/Row/Maintenance.text = "维护费 %s" % _number(
        country.get("last_maintenance_charge", 0)
    )
    $Margin/Row/Recruitable.text = "可招募 %s" % _number(
        country.get("recruitable_population", 0)
    )
    $Margin/Row/Date.text = "%d年%d月" % [date.get("year", 0), date.get("month", 1)]


func set_advance_enabled(enabled: bool, warning: String = "") -> void:
    $Margin/Row/AdvanceTurn.disabled = not enabled
    $Margin/Row/AdvanceTurn.tooltip_text = warning


func _number(value: Variant) -> String:
    return str(int(value))
