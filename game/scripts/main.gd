extends Control


func _ready() -> void:
    var bridge := $SimulationBridge
    var next_date: Dictionary = bridge.advance_date(1000, 11, 3)
    var message := "Core %s ready · Date test: %d-%02d" % [
        bridge.get_core_version(),
        next_date["year"],
        next_date["month"],
    ]
    $Center/Status.text = message
    print(message)
