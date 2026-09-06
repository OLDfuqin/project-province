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
    var normal_style := theme.get_stylebox("normal", "Button") as StyleBox
    var hover_style := theme.get_stylebox("hover", "Button") as StyleBox
    var pressed_style := theme.get_stylebox("pressed", "Button") as StyleBox
    if normal_style.content_margin_left != hover_style.content_margin_left or \
            normal_style.content_margin_top != hover_style.content_margin_top or \
            normal_style.content_margin_right != hover_style.content_margin_right or \
            normal_style.content_margin_bottom != hover_style.content_margin_bottom or \
            normal_style.content_margin_left != pressed_style.content_margin_left or \
            normal_style.content_margin_top != pressed_style.content_margin_top or \
            normal_style.content_margin_right != pressed_style.content_margin_right or \
            normal_style.content_margin_bottom != pressed_style.content_margin_bottom:
        push_error("Button interaction styles must preserve content margins")
        quit(1)
        return
    card.free()
    print("Strategic theme smoke test passed")
    quit(0)
