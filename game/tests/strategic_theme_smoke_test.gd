extends SceneTree

func _initialize() -> void:
    var theme := load("res://themes/strategic_ui_theme.tres") as Theme
    var card_scene := load("res://scenes/ui/metric_card.tscn") as PackedScene
    if theme == null or card_scene == null:
        push_error("Strategic theme or metric card is missing")
        quit(1)
        return
    var card := card_scene.instantiate()
    root.add_child(card)
    card.set_metric("人口", "340,000", "本月 +1,700")
    if card.get_node("Content/Title").text != "人口" or \
            card.get_node("Content/Value").text != "340,000" or \
            card.get_node("Content/Detail").text != "本月 +1,700":
        push_error("Metric card did not render its snapshot")
        quit(1)
        return
    if theme.get_color("font_color", "Label") != Color("e8eef7"):
        push_error("Strategic theme tokens are not authoritative")
        quit(1)
        return
    card.free()
    print("Strategic theme smoke test passed")
    quit(0)
