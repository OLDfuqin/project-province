class_name MetricCard
extends PanelContainer

func set_metric(title: String, value: String, detail: String = "") -> void:
    $Content/Title.text = title
    $Content/Value.text = value
    $Content/Detail.text = detail
    $Content/Detail.visible = not detail.is_empty()
