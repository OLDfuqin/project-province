class_name MilitaryOverviewPage
extends PanelContainer


func set_snapshot(armies: Array, orders: Array) -> void:
	var army_rows := $Content/Armies/Rows as VBoxContainer
	var order_rows := $Content/Orders/Rows as VBoxContainer
	_clear_rows(army_rows)
	_clear_rows(order_rows)
	for index: int in armies.size():
		army_rows.add_child(_army_row(index, armies[index]))
	for index: int in orders.size():
		order_rows.add_child(_order_row(index, orders[index]))
	%EmptyArmies.visible = armies.is_empty()
	%EmptyOrders.visible = orders.is_empty()


func _clear_rows(rows: VBoxContainer) -> void:
	for child: Node in rows.get_children():
		if child.name.begins_with("Empty"):
			continue
		rows.remove_child(child)
		child.queue_free()


func _army_row(index: int, army: Dictionary) -> Label:
	var row := Label.new()
	row.name = "Army%d" % index
	row.theme_type_variation = &"DataRow"
	row.custom_minimum_size = Vector2(720, 52)
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.text = "%s：%s 人\n%s%s" % [
		_display_name(army, "未命名军队"),
		_number(army.get("soldiers", army.get("strength", 0))),
		String(army.get("province_name", "")),
		_status_suffix(army),
	]
	return row


func _order_row(index: int, order: Dictionary) -> Label:
	var row := Label.new()
	row.name = "Order%d" % index
	row.theme_type_variation = &"DataRow"
	row.custom_minimum_size = Vector2(720, 42)
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.text = "%s%s" % [_display_name(order, "待执行订单"), _status_suffix(order)]
	return row


func _display_name(item: Dictionary, fallback: String) -> String:
	var name := String(item.get("name", item.get("display_name", "")))
	return name if not name.is_empty() else fallback


func _status_suffix(item: Dictionary) -> String:
	var status := String(item.get("status", item.get("description", "")))
	return "（%s）" % status if not status.is_empty() else ""


func _number(value: Variant) -> String:
	var number := int(value)
	var digits := str(absi(number))
	var result := ""
	while digits.length() > 3:
		result = "," + digits.substr(digits.length() - 3) + result
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if number < 0 else "") + digits + result
