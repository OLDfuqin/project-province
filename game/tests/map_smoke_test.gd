extends SceneTree


func _initialize() -> void:
    var map_script := load("res://scripts/province_map.gd")
    var province_map: Control = map_script.new()

    var cases := {
        Vector2(90, 90): "northreach",
        Vector2(300, 80): "westmark",
        Vector2(500, 80): "greenvale",
        Vector2(720, 100): "sunmeadow",
        Vector2(720, 410): "blueharbor",
        Vector2(500, 430): "skyplain",
        Vector2(300, 430): "goldcoast",
        Vector2(80, 400): "redpass",
        Vector2(400, 250): "",
    }

    for point: Vector2 in cases:
        var actual: String = province_map.province_at_map_position(point)
        var expected: String = cases[point]
        if actual != expected:
            push_error("Map hit test failed at %s: expected '%s', got '%s'" % [
                point, expected, actual
            ])
            quit(1)
            return

    print("Province map hit-test smoke test passed")
    province_map.free()
    quit(0)
