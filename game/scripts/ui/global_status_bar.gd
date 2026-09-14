class_name GlobalStatusBar
extends PanelContainer

signal advance_turn_requested

const ADVANCE_TURN_TOOLTIP := "结算当前月并进入下一回合"

var _compact := false
var _country_snapshot: Dictionary = {}
var _date_snapshot: Dictionary = {}


func _ready() -> void:
    $Margin/Row/AdvanceTurn.pressed.connect(func() -> void:
        advance_turn_requested.emit()
    )


func set_snapshot(country: Dictionary, date: Dictionary) -> void:
    _country_snapshot = country.duplicate(true)
    _date_snapshot = date.duplicate(true)
    _render_snapshot()


func set_compact(compact: bool) -> void:
    _compact = compact
    _render_snapshot()


func _render_snapshot() -> void:
    $Margin/Row/CountryName.text = String(_country_snapshot.get("name", "未知国家"))
    $Margin/Row/Treasury.text = "%s%s" % [
        "国 " if _compact else "国库 ", _number(_country_snapshot.get("treasury", 0)),
    ]
    $Margin/Row/Income.text = "%s%s" % [
        "收 " if _compact else "月收入 ", _number(_country_snapshot.get("fiscal_income", 0)),
    ]
    $Margin/Row/Maintenance.text = "%s%s" % [
        "维 " if _compact else "维护费 ",
        _number(_country_snapshot.get("last_maintenance_charge", 0)),
    ]
    $Margin/Row/Recruitable.text = "%s%s" % [
        "招 " if _compact else "可招募 ",
        _number(_country_snapshot.get("recruitable_population", 0)),
    ]
    for metric: Label in [
        $Margin/Row/Treasury, $Margin/Row/Income,
        $Margin/Row/Maintenance, $Margin/Row/Recruitable,
    ]:
        metric.visible = true
    $Margin/Row/Date.text = "%d年%d月" % [
        _date_snapshot.get("year", 0), _date_snapshot.get("month", 1),
    ]


func set_advance_enabled(enabled: bool, warning: String = "") -> void:
    var advance := $Margin/Row/AdvanceTurn as Button
    advance.disabled = not enabled
    advance.tooltip_text = ADVANCE_TURN_TOOLTIP if enabled else (
        warning if not warning.is_empty() else "当前不可用：存在未解决的回合阻塞"
    )


func _number(value: Variant) -> String:
    return str(int(value))
