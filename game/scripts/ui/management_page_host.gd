class_name ManagementPageHost
extends PanelContainer


signal back_requested

const PAGE_IDS := ["country", "diplomacy", "technology", "military", "economy", "settings"]

var _page := "closed"


func _ready() -> void:
	%Back.pressed.connect(_on_back_pressed)
	close_page()


func open_page(page_id: String) -> void:
	if not page_id in PAGE_IDS:
		return
	for child: Node in %Pages.get_children():
		var page := child as Control
		if page != null:
			page.visible = String(page.get_meta("page_id", "")) == page_id
	_page = page_id
	visible = true


func close_page() -> void:
	_page = "closed"
	visible = false


func current_page() -> String:
	return _page


func _on_back_pressed() -> void:
	close_page()
	back_requested.emit()
