class_name EconomicOverviewPage
extends PanelContainer


func set_snapshot(country: Dictionary, provinces: Array) -> void:
	var income := int(country.get("fiscal_income", 0))
	var maintenance := int(country.get("last_maintenance_charge", 0))
	var has_maintenance := bool(country.get("has_last_maintenance_charge", false))
	%NetIncome.text = "财政收入：%s\n上月维护：%s\n净收入：%s" % [
		str(income),
		str(maintenance) if has_maintenance else "暂无记录",
		str(income - maintenance) if has_maintenance else "暂无记录",
	]
	var rows := $Content/Provinces/Rows as VBoxContainer
	_clear_rows(rows)
	var sorted_provinces := provinces.duplicate()
	sorted_provinces.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("fiscal_income", 0)) > int(right.get("fiscal_income", 0))
	)
	for index: int in sorted_provinces.size():
		rows.add_child(_province_row(index, sorted_provinces[index]))
	%Empty.visible = sorted_provinces.is_empty()


func _clear_rows(rows: VBoxContainer) -> void:
	for child: Node in rows.get_children():
		if child.name == "Empty":
			continue
		rows.remove_child(child)
		child.queue_free()


func _province_row(index: int, province: Dictionary) -> Label:
	var row := Label.new()
	row.name = "Province%d" % index
	row.theme_type_variation = &"DataRow"
	row.custom_minimum_size = Vector2(720, 34)
	row.text = "%s：%s" % [
		_display_name(province), _number(province.get("fiscal_income", 0)),
	]
	return row


func _display_name(province: Dictionary) -> String:
	var name := String(province.get("name", province.get("display_name", "")))
	return name if not name.is_empty() else "未知地区"


func _number(value: Variant) -> String:
	var number := int(value)
	var digits := str(absi(number))
	var result := ""
	while digits.length() > 3:
		result = "," + digits.substr(digits.length() - 3) + result
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if number < 0 else "") + digits + result
