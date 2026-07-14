# Province Management Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move technology, recruitment, army movement, automatic advance, and advance-plan controls into the double-click province management page, then remove their duplicated main-panel controls.

**Architecture:** `ProvinceManagementWindow` remains a presentation-only component that displays current dictionaries and emits typed requests. `main.gd` remains the controller and sole caller of `ProvinceBridge`; it translates window requests into existing bridge calls, owns transient map-selection state, and refreshes the open page. The simulation core and save format do not change.

**Tech Stack:** Godot 4.6.3, GDScript, `.tscn` scenes, C++ GDExtension through the existing `ProvinceBridge`, headless Godot smoke tests.

## Global Constraints

- Do not change simulation-core, save-format, economy, combat, technology-cost, or pathfinding rules.
- Preserve save/load, road construction, country selection/details, diplomacy, war information, global population summary, event history, and turn controls on the main page.
- Remove `RegionDetails`, `TechnologyControls`, `SelectionStatus`, and `ArmyControls` from `RightPanel/Center`; do not merely hide them.
- Keep single-click province information, double-click province management, and the shared vertical workspace scrolling behavior.
- Keep future economy investment, civil investment, and building management placeholders disabled and visible in province management.
- Work in an isolated worktree created from `main` so the user's uncommitted Godot editor formatting in the primary working tree is not modified.
- Write Godot logs outside the hidden worktree, for example under `C:\Users\Asus\Documents\Codex\2026-07-07\w`, because Godot 4.6.3 crashes while creating logs inside this hidden worktree path on this machine.

---

### Task 1: Expand the province management presentation contract

**Files:**
- Modify: `game/scenes/ui/province_management_window.tscn`
- Modify: `game/scripts/province_management_window.gd`
- Create: `game/tests/province_management_window_component_smoke_test.gd`

**Interfaces:**
- Consumes: existing `display_province(province: Dictionary, armies: Array, player_country_id: String, preferred_army_id := "")`.
- Produces signals:
  - `technology_research_requested(track: String)`
  - `advance_destination_selection_requested(army_id: String)`
  - `auto_advance_requested(army_id: String, target_id: String)`
  - `movement_clear_requested(army_id: String)`
  - `advance_plan_action_requested(command: String)`
- Produces methods:
  - `set_technology(technology: Dictionary) -> void`
  - `set_advance_target(province_id: String, province_name: String) -> void`
  - `set_advance_plans(bbcode: String) -> void`
  - `set_action_state(direct_enabled: bool, advance_enabled: bool) -> void`

- [ ] **Step 1: Write a failing component smoke test**

Create `game/tests/province_management_window_component_smoke_test.gd` with a direct scene test that does not instantiate `main.tscn`:

```gdscript
extends SceneTree


func _initialize() -> void:
    var packed := load("res://scenes/ui/province_management_window.tscn") as PackedScene
    var window := packed.instantiate()
    root.add_child(window)
    await process_frame

    var research_track := ""
    var advance_army := ""
    var plan_command := ""
    window.technology_research_requested.connect(
        func(track: String) -> void: research_track = track
    )
    window.advance_destination_selection_requested.connect(
        func(army_id: String) -> void: advance_army = army_id
    )
    window.advance_plan_action_requested.connect(
        func(command: String) -> void: plan_command = command
    )

    window.display_province(
        {"id": "northreach", "name": "北境", "owner_id": "auroria",
         "population": 120000, "recruitable_population": 1000, "economy": 80},
        [{"id": "army_1", "owner_id": "auroria", "province_id": "northreach",
          "manpower": 1000, "movement_points": 0}],
        "auroria",
        "army_1"
    )
    window.set_technology({
        "economy_level": 1, "military_level": 2, "roads_level": 3
    })
    window.set_advance_target("rivergate", "河间")
    window.set_advance_plans("[url=pause:army_1]暂停[/url]")
    window.get_node("Technology/Buttons/Economy").pressed.emit()
    window.get_node("AdvanceActions/SelectAdvanceTarget").pressed.emit()
    window.get_node("AdvancePlans").meta_clicked.emit("pause:army_1")

    if research_track != "economy" or advance_army != "army_1" or \
            plan_command != "pause:army_1" or \
            not window.get_node("Technology/Status").text.contains("道路 3") or \
            not window.get_node("AdvanceTarget").text.contains("河间"):
        push_error("Province management component contract is incomplete")
        window.free()
        quit(1)
        return

    print("Province management component smoke test passed")
    window.free()
    quit(0)
```

- [ ] **Step 2: Run the test and verify the expected failure**

Run:

```powershell
$godot='C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --log-file C:\Users\Asus\Documents\Codex\2026-07-07\w\management-component-red.log --path game --script res://tests/province_management_window_component_smoke_test.gd
```

Expected: non-zero exit because `technology_research_requested` and the new child nodes do not exist.

- [ ] **Step 3: Add the new management-page sections**

In `game/scenes/ui/province_management_window.tscn`, add these nodes after `RecruitArmy` and before `ArmyTitle`:

```text
[node name="Technology" type="VBoxContainer" parent="."]
layout_mode = 2
theme_override_constants/separation = 4

[node name="Title" type="Label" parent="Technology"]
layout_mode = 2
text = "国家科技"

[node name="Status" type="Label" parent="Technology"]
layout_mode = 2
horizontal_alignment = 1

[node name="Buttons" type="HBoxContainer" parent="Technology"]
layout_mode = 2
alignment = 1

[node name="Economy" type="Button" parent="Technology/Buttons"]
layout_mode = 2
text = "研究经济"

[node name="Military" type="Button" parent="Technology/Buttons"]
layout_mode = 2
text = "研究军事"

[node name="Roads" type="Button" parent="Technology/Buttons"]
layout_mode = 2
text = "研究道路"
```

Rename the existing `Destination` label to `DirectDestination`, retain the existing direct movement buttons, then add:

```text
[node name="AdvanceTarget" type="Label" parent="."]
layout_mode = 2
text = "推进目标：尚未选择"
horizontal_alignment = 1

[node name="AdvanceActions" type="HBoxContainer" parent="."]
layout_mode = 2
alignment = 1

[node name="SelectAdvanceTarget" type="Button" parent="AdvanceActions"]
layout_mode = 2
disabled = true
text = "在地图选择推进目标"

[node name="AdvanceNow" type="Button" parent="AdvanceActions"]
layout_mode = 2
disabled = true
text = "立即自动推进"

[node name="ClearMovement" type="Button" parent="AdvanceActions"]
layout_mode = 2
disabled = true
text = "清除选择"

[node name="AdvancePlansTitle" type="Label" parent="."]
layout_mode = 2
text = "国家推进计划"

[node name="AdvancePlans" type="RichTextLabel" parent="."]
custom_minimum_size = Vector2(0, 120)
layout_mode = 2
bbcode_enabled = true
text = "暂无推进计划"
```

- [ ] **Step 4: Implement the presentation API and typed signals**

Add the signals and target state in `province_management_window.gd`:

```gdscript
signal technology_research_requested(track: String)
signal advance_destination_selection_requested(army_id: String)
signal auto_advance_requested(army_id: String, target_id: String)
signal movement_clear_requested(army_id: String)
signal advance_plan_action_requested(command: String)

var _advance_target_id := ""
```

Connect the new controls in `_ready()`:

```gdscript
$Technology/Buttons/Economy.pressed.connect(
    func() -> void: technology_research_requested.emit("economy")
)
$Technology/Buttons/Military.pressed.connect(
    func() -> void: technology_research_requested.emit("military")
)
$Technology/Buttons/Roads.pressed.connect(
    func() -> void: technology_research_requested.emit("roads")
)
$AdvanceActions/SelectAdvanceTarget.pressed.connect(
    func() -> void: advance_destination_selection_requested.emit(_selected_army_id)
)
$AdvanceActions/AdvanceNow.pressed.connect(
    func() -> void: auto_advance_requested.emit(_selected_army_id, _advance_target_id)
)
$AdvanceActions/ClearMovement.pressed.connect(
    func() -> void: movement_clear_requested.emit(_selected_army_id)
)
$AdvancePlans.meta_clicked.connect(
    func(meta: Variant) -> void: advance_plan_action_requested.emit(String(meta))
)
```

Add the public methods:

```gdscript
func set_technology(technology: Dictionary) -> void:
    $Technology/Status.text = "经济 %d | 军事 %d | 道路 %d" % [
        technology.get("economy_level", 0),
        technology.get("military_level", 0),
        technology.get("roads_level", 0),
    ]


func set_destination(province_id: String, province_name: String) -> void:
    if province_id.is_empty():
        _clear_destination()
        return
    _destination_id = province_id
    $DirectDestination.text = "直接调动目的地：%s" % province_name
    $ArmyActions/MoveArmy.disabled = _selected_army_id.is_empty()
    $Status.text = "目的地已选择，可确认调动"


func set_advance_target(province_id: String, province_name: String) -> void:
    _advance_target_id = province_id
    $AdvanceTarget.text = (
        "推进目标：尚未选择" if province_id.is_empty()
        else "推进目标：%s" % province_name
    )
    $AdvanceActions/AdvanceNow.disabled = (
        _selected_army_id.is_empty() or _advance_target_id.is_empty()
    )


func set_advance_plans(bbcode: String) -> void:
    $AdvancePlans.text = "暂无推进计划" if bbcode.is_empty() else bbcode


func set_action_state(direct_enabled: bool, advance_enabled: bool) -> void:
    $ArmyActions/MoveArmy.disabled = not direct_enabled
    $AdvanceActions/AdvanceNow.disabled = not advance_enabled
    $AdvanceActions/ClearMovement.disabled = _selected_army_id.is_empty()
```

In the no-army branch of `_populate_armies()`, add:

```gdscript
$AdvanceActions/SelectAdvanceTarget.disabled = true
$AdvanceActions/AdvanceNow.disabled = true
$AdvanceActions/ClearMovement.disabled = true
set_advance_target("", "")
```

In the selected-army branch, enable target selection and clearing:

```gdscript
$AdvanceActions/SelectAdvanceTarget.disabled = false
$AdvanceActions/ClearMovement.disabled = false
```

Make `_clear_destination()` handle the renamed direct label exactly:

```gdscript
func _clear_destination() -> void:
    _destination_id = ""
    $DirectDestination.text = "直接调动目的地：尚未选择"
    $ArmyActions/MoveArmy.disabled = true
```

At the end of `clear()`, reset `_advance_target_id` and both visible targets:

```gdscript
_advance_target_id = ""
_clear_destination()
set_advance_target("", "")
```

- [ ] **Step 5: Run the component and existing management tests**

Run sequentially:

```powershell
& $godot --headless --log-file C:\Users\Asus\Documents\Codex\2026-07-07\w\management-component-green.log --path game --script res://tests/province_management_window_component_smoke_test.gd
& $godot --headless --log-file C:\Users\Asus\Documents\Codex\2026-07-07\w\management-existing-green.log --path game --script res://tests/province_management_window_smoke_test.gd
```

Expected: both exit with code `0`.

- [ ] **Step 6: Commit the presentation contract**

```powershell
git add game/scenes/ui/province_management_window.tscn game/scripts/province_management_window.gd game/tests/province_management_window_component_smoke_test.gd
git commit -m "feat: expand province management controls"
```

---

### Task 2: Route technology research through province management

**Files:**
- Modify: `game/scripts/main.gd`
- Modify: `game/tests/province_management_window_smoke_test.gd`

**Interfaces:**
- Consumes: `technology_research_requested(track: String)` and `set_technology(technology: Dictionary)` from Task 1.
- Produces: `_player_technology() -> Dictionary` and a management-safe `_on_research_technology(track: String)` that does not close the active management page.

- [ ] **Step 1: Add a failing technology migration assertion**

After opening `northreach` in `province_management_window_smoke_test.gd`, require the new technology controls and press the economy button:

```gdscript
var technology_status := management.get_node("Technology/Status") as Label
var economy_research := management.get_node("Technology/Buttons/Economy") as Button
if not technology_status.text.contains("经济 0"):
    push_error("Management page did not display technology")
    main_scene.free()
    quit(1)
    return
economy_research.pressed.emit()
await process_frame
if not technology_status.text.contains("经济 1"):
    push_error("Technology research did not refresh management page")
    main_scene.free()
    quit(1)
    return
```

- [ ] **Step 2: Run the test and verify it fails because main is not connected**

Run the management smoke test. Expected: non-zero exit with `Technology research did not refresh management page`.

- [ ] **Step 3: Connect and refresh technology through the page**

In `_ready()` connect:

```gdscript
province_management_window.technology_research_requested.connect(
    _on_research_technology
)
```

Add:

```gdscript
func _player_technology() -> Dictionary:
    for technology: Dictionary in bridge.get_technology_summaries():
        if technology.get("country_id", "") == PLAYER_COUNTRY_ID:
            return technology
    return {}
```

At the end of `_refresh_management_window()`, call:

```gdscript
province_management_window.set_technology(_player_technology())
```

Remove `_close_transient_workspace()` from `_on_research_technology()`. On rejection, also call `province_management_window.set_status(event_log.text)` when management is open. On success, refresh the open page while retaining the selected army:

```gdscript
_refresh_country_list()
_refresh_country_details()
_refresh_technology_status()
_refresh_management_window(moving_army_id, event_log.text)
```

Make `_refresh_technology_status()` update the management window only when `workspace_mode == WorkspaceMode.PROVINCE_MANAGEMENT`; Task 4 will remove the old main-panel target completely.

- [ ] **Step 4: Run the management and technology bridge tests**

Run:

```powershell
& $godot --headless --log-file C:\Users\Asus\Documents\Codex\2026-07-07\w\management-tech-green.log --path game --script res://tests/province_management_window_smoke_test.gd
& $godot --headless --log-file C:\Users\Asus\Documents\Codex\2026-07-07\w\technology-bridge-green.log --path game --script res://tests/technology_bridge_smoke_test.gd
```

Expected: both pass.

- [ ] **Step 5: Commit technology migration**

```powershell
git add game/scripts/main.gd game/tests/province_management_window_smoke_test.gd
git commit -m "feat: manage technology from province window"
```

---

### Task 3: Route direct movement, automatic advance, and plan actions through province management

**Files:**
- Modify: `game/scripts/main.gd`
- Modify: `game/scripts/province_management_window.gd`
- Create: `game/tests/province_management_advance_smoke_test.gd`

**Interfaces:**
- Consumes: Task 1 movement and plan signals.
- Produces: `MapInputMode.AUTO_ADVANCE_DESTINATION`, `_select_management_advance_target(province_id: String)`, `_on_management_auto_advance_requested(army_id: String, target_id: String)`, `_open_management_for_army(army_id: String)`, and management-rendered advance plans.

- [ ] **Step 1: Add failing automatic-advance and plan-action coverage**

Create `game/tests/province_management_advance_smoke_test.gd`. Instantiate `main.tscn`, open `northreach`, recruit one army, grant it movement points before assigning a plan, and then exercise every migrated plan action:

```gdscript
extends SceneTree


func _army(bridge: Object, army_id: String) -> Dictionary:
    for summary: Dictionary in bridge.get_army_summaries():
        if summary.get("id", "") == army_id:
            return summary
    return {}


func _initialize() -> void:
    var packed := load("res://scenes/main/main.tscn") as PackedScene
    var main_scene := packed.instantiate()
    root.add_child(main_scene)
    await process_frame
    var bridge := main_scene.get_node("SimulationBridge")
    var province_map := main_scene.get_node("MapPanel/ProvinceMap")
    var management := main_scene.get_node(
        "WorkspacePanel/Workspace/WindowViewport/WindowContent/ProvinceManagementWindow"
    )
    province_map.province_double_clicked.emit("northreach")
    management.get_node("RecruitArmy").pressed.emit()
    await process_frame
    var selector := management.get_node("ArmySelector") as OptionButton
    var army_id := String(selector.get_item_metadata(0))
    bridge.advance_turn(3)
    province_map.province_double_clicked.emit("northreach")

var select_advance := management.get_node(
    "AdvanceActions/SelectAdvanceTarget"
) as Button
var advance_now := management.get_node("AdvanceActions/AdvanceNow") as Button
var advance_plans := management.get_node("AdvancePlans") as RichTextLabel
select_advance.pressed.emit()
if main_scene.map_input_mode_name() != "auto_advance_destination":
    push_error("Management page did not enter advance target selection")
    main_scene.free()
    quit(1)
    return
province_map.province_selected.emit("rivergate")
await process_frame
if not management.get_node("AdvanceTarget").text.contains("河间") or \
        not advance_plans.text.contains(army_id):
    push_error("Non-adjacent advance target was not stored and displayed")
    main_scene.free()
    quit(1)
    return

advance_plans.meta_clicked.emit("pause:%s" % army_id)
await process_frame
if _army(bridge, army_id).get("advance_enabled", true):
    push_error("Advance plan did not pause from management")
    main_scene.free()
    quit(1)
    return
advance_plans.meta_clicked.emit("resume:%s" % army_id)
advance_plans.meta_clicked.emit("strategy:%s:one_step" % army_id)
await process_frame
if not _army(bridge, army_id).get("advance_enabled", false) or \
        _army(bridge, army_id).get("advance_strategy", "") != "one_step":
    push_error("Advance plan resume or strategy action failed")
    main_scene.free()
    quit(1)
    return
advance_plans.meta_clicked.emit("clear:%s" % army_id)
await process_frame
if not String(_army(bridge, army_id).get("advance_target_id", "")).is_empty():
    push_error("Advance plan did not clear from management")
    main_scene.free()
    quit(1)
    return

advance_plans.meta_clicked.emit("strategy:%s:max" % army_id)
select_advance.pressed.emit()
province_map.province_selected.emit("rivergate")
advance_now.pressed.emit()
await process_frame
var moved_army := _army(bridge, army_id)
if moved_army.is_empty() or moved_army.get("province_id", "") == "northreach":
    push_error("Immediate automatic advance did not move the army")
    main_scene.free()
    quit(1)
    return

bridge.set_army_advance_target(army_id, "westhaven")
province_map.province_double_clicked.emit("northreach")
await process_frame
management.get_node("AdvancePlans").meta_clicked.emit("select:%s" % army_id)
await process_frame
var moved_name: String = main_scene.province_by_id.get(
    moved_army.get("province_id", ""), {}
).get("name", "")
if management.get_node("ProvinceName").text != moved_name:
    push_error("Selecting a remote plan did not switch managed province")
    main_scene.free()
    quit(1)
    return

print("Province management advance smoke test passed")
main_scene.free()
quit(0)
```

- [ ] **Step 2: Run the test and verify the missing map mode failure**

Expected: non-zero exit with `Management page did not enter advance target selection`.

- [ ] **Step 3: Add separate direct and advance map-selection modes**

Extend the enum and name mapper:

```gdscript
enum MapInputMode {
    NORMAL,
    ARMY_DESTINATION,
    AUTO_ADVANCE_DESTINATION,
    ROAD_START,
    ROAD_END,
}
```

In `_on_province_selected()` route both modes before normal selection:

```gdscript
if map_input_mode == MapInputMode.ARMY_DESTINATION:
    _select_management_destination(province_id)
    return
if map_input_mode == MapInputMode.AUTO_ADVANCE_DESTINATION:
    _select_management_advance_target(province_id)
    return
```

Connect Task 1 signals in `_ready()`:

```gdscript
province_management_window.advance_destination_selection_requested.connect(
    _on_management_advance_destination_requested
)
province_management_window.auto_advance_requested.connect(
    _on_management_auto_advance_requested
)
province_management_window.movement_clear_requested.connect(
    _on_management_movement_clear_requested
)
province_management_window.advance_plan_action_requested.connect(
    _on_advance_plan_clicked
)
```

Direct selection retains the existing adjacent-only validation. Implement advance target selection as:

```gdscript
func _select_management_advance_target(province_id: String) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT or \
            moving_army_id.is_empty():
        map_input_mode = MapInputMode.NORMAL
        return
    if province_id.is_empty() or province_id == movement_origin_id:
        province_management_window.set_status("推进目标必须是其他地区")
        return
    var result: Dictionary = bridge.set_army_advance_target(
        moving_army_id, province_id
    )
    if not result.get("accepted", false):
        province_management_window.set_status(
            "设置推进目标失败：%s" % result.get("error", "未知错误")
        )
        return
    auto_advance_target_id = province_id
    movement_destination_id = ""
    map_input_mode = MapInputMode.NORMAL
    province_management_window.set_advance_target(
        province_id,
        province_by_id.get(province_id, {"name": province_id}).get(
            "name", province_id
        )
    )
    _refresh_advance_plans()
    _refresh_management_action_state()
```

- [ ] **Step 4: Move automatic-advance execution into a management-safe handler**

Extract the bridge call and current battle-report handling from `_on_auto_advance_pressed()` into:

```gdscript
func _on_management_auto_advance_requested(
    army_id: String,
    target_id: String
) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT or \
            army_id != moving_army_id or target_id.is_empty():
        return
    var result: Dictionary = bridge.auto_advance_army_to(army_id, target_id)
    if not result.get("accepted", false):
        event_log.text = "自动推进失败：%s" % result.get("error", "未知错误")
        province_management_window.set_status(event_log.text)
        return
    _record_movement_result(result)
    var new_province_id: String = result.get("army_province_id", result["destination"])
    _refresh_map_data()
    _refresh_country_details()
    _refresh_game_status()
    _open_management_for_army(army_id, new_province_id, event_log.text)
```

Add the shared result formatter and call it from both management movement handlers:

```gdscript
func _record_movement_result(result: Dictionary) -> void:
    event_log.text = "事件 #%d：%s → %s，消耗%d移动点，剩余%d" % [
        result.get("event_sequence", 0),
        result.get("origin", ""),
        result.get("destination", ""),
        result.get("movement_cost", 0),
        result.get("remaining_points", 0),
    ]
    var battle_report := _battle_report(result)
    if not battle_report.is_empty():
        event_log.text = battle_report
    _record_event(event_log.text)
```

Add one renderer for controller-owned movement state and replace Task 3 calls to the old main-panel `_refresh_movement_selection()` with it:

```gdscript
func _refresh_management_action_state() -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT:
        return
    province_management_window.set_action_state(
        not moving_army_id.is_empty() and not movement_destination_id.is_empty(),
        not moving_army_id.is_empty() and not auto_advance_target_id.is_empty()
    )
    var target_name := ""
    if not auto_advance_target_id.is_empty():
        target_name = province_by_id.get(
            auto_advance_target_id,
            {"name": auto_advance_target_id}
        ).get("name", auto_advance_target_id)
    province_management_window.set_advance_target(
        auto_advance_target_id, target_name
    )
```

- [ ] **Step 5: Render and handle all advance plans in the management page**

Change `_refresh_advance_plans()` so it builds the existing BBCode but calls:

```gdscript
if workspace_mode == WorkspaceMode.PROVINCE_MANAGEMENT:
    province_management_window.set_advance_plans(
        "[b]推进计划[/b]\n%s" % "\n".join(lines) if not lines.is_empty() else ""
    )
```

Connect `advance_plan_action_requested` to `_on_advance_plan_clicked`. Remove `_close_transient_workspace()` from that handler. For `select:<army_id>`, replace the old main-panel selector call with:

```gdscript
func _open_management_for_army(
    army_id: String,
    province_id := "",
    status_message := ""
) -> void:
    var army := _find_army_by_id(army_id)
    if army.is_empty():
        return
    managed_province_id = (
        province_id if not province_id.is_empty() else String(army["province_id"])
    )
    moving_army_id = army_id
    movement_origin_id = managed_province_id
    movement_destination_id = ""
    auto_advance_target_id = army.get("advance_target_id", "")
    _open_workspace(WorkspaceMode.PROVINCE_MANAGEMENT, "地区管理", "")
    workspace_content.visible = false
    _refresh_management_window(army_id, status_message)
```

After every successful pause/resume, strategy, or clear bridge call, use the same refresh sequence:

```gdscript
_refresh_map_data()
_refresh_advance_plans()
_refresh_management_action_state()
_refresh_management_window(moving_army_id, event_log.text)
```

Implement movement reset without deleting a stored plan:

```gdscript
func _on_management_movement_clear_requested(army_id: String) -> void:
    if workspace_mode != WorkspaceMode.PROVINCE_MANAGEMENT or \
            army_id != moving_army_id:
        return
    movement_destination_id = ""
    map_input_mode = MapInputMode.NORMAL
    province_management_window.set_destination("", "")
    province_management_window.set_status("已清除临时移动选择")
    _refresh_management_action_state()
```

- [ ] **Step 6: Run management, advance, army bridge, and layout tests**

```powershell
& $godot --headless --log-file C:\Users\Asus\Documents\Codex\2026-07-07\w\management-base-green.log --path game --script res://tests/province_management_window_smoke_test.gd
& $godot --headless --log-file C:\Users\Asus\Documents\Codex\2026-07-07\w\management-advance-green.log --path game --script res://tests/province_management_advance_smoke_test.gd
& $godot --headless --log-file C:\Users\Asus\Documents\Codex\2026-07-07\w\army-bridge-green.log --path game --script res://tests/army_bridge_smoke_test.gd
& $godot --headless --log-file C:\Users\Asus\Documents\Codex\2026-07-07\w\management-layout-green.log --path game --script res://tests/main_layout_smoke_test.gd
```

Expected: all four pass and the management page remains open through plan actions.

- [ ] **Step 7: Commit movement and plan migration**

```powershell
git add game/scripts/main.gd game/scripts/province_management_window.gd game/tests/province_management_advance_smoke_test.gd
git commit -m "feat: manage army advances from province window"
```

---

### Task 4: Remove duplicate main-panel controls and obsolete controller paths

**Files:**
- Modify: `game/scenes/main/main.tscn`
- Modify: `game/scripts/main.gd`
- Modify: `game/tests/main_layout_smoke_test.gd`

**Interfaces:**
- Consumes: complete province management contract from Tasks 1-3.
- Produces: a main page with no `RegionDetails`, `TechnologyControls`, `SelectionStatus`, or `ArmyControls` nodes.

- [ ] **Step 1: Replace preservation assertions with failing removal assertions**

In `main_layout_smoke_test.gd`, keep assertions for save, diplomacy, technology now under management, road entry, global summary, and turn controls. Add:

```gdscript
var removed_controls := [
    "RightPanel/Center/RegionDetails",
    "RightPanel/Center/TechnologyControls",
    "RightPanel/Center/SelectionStatus",
    "RightPanel/Center/ArmyControls",
]
for control_path: String in removed_controls:
    if main_scene.get_node_or_null(control_path) != null:
        push_error("Duplicate main control still exists: %s" % control_path)
        main_scene.free()
        quit(1)
        return

var management := main_scene.get_node(
    "WorkspacePanel/Workspace/WindowViewport/WindowContent/ProvinceManagementWindow"
)
for relative_path: String in [
    "Technology/Buttons/Economy",
    "RecruitArmy",
    "ArmyActions/MoveArmy",
    "AdvanceActions/AdvanceNow",
    "AdvancePlans",
]:
    if management.get_node_or_null(relative_path) == null:
        push_error("Migrated management control is missing: %s" % relative_path)
        main_scene.free()
        quit(1)
        return
```

Run the layout test. Expected: failure because the duplicate main nodes still exist.

- [ ] **Step 2: Delete the duplicate scene nodes**

Remove the four exact subtrees from `main.tscn`:

```text
RightPanel/Center/RegionDetails
RightPanel/Center/TechnologyControls
RightPanel/Center/SelectionStatus
RightPanel/Center/ArmyControls
```

Do not remove `ProvinceSummary`, `CountryDetails`, `WarOverview`, `RoadConstructionEntry`, `EventLog`, or `EventHistory`.

- [ ] **Step 3: Remove direct references and obsolete functions from `main.gd`**

Delete old on-ready references for `region_details`, `recruit_button`, `move_army_button`, `auto_advance_button`, `army_selector`, `army_details`, and `advance_plans`. Delete old signal connections targeting removed nodes.

Replace normal-mode `_on_province_selected()` with only the special-mode routing; province information continues through `_on_province_clicked()`. Remove `_show_province_details()` and calls to it.

Remove obsolete main-panel handlers and renderers after their management equivalents exist:

```text
_on_recruit_army_pressed
_on_move_army_pressed
_on_auto_advance_pressed
_on_army_selected
_refresh_army_selector
_refresh_movement_selection
_update_movement_from_province
_find_player_army_in_province
_select_army_in_selector
```

Retain `_select_army`, `_are_provinces_adjacent`, `_clear_movement_selection`, `_refresh_advance_plans`, and plan command handling. Replace every call to `_refresh_movement_selection()` with `_refresh_management_action_state()`. Replace `_select_army()` with this state-only version:

```gdscript
func _select_army(army_id: String) -> void:
    var army := _find_army_by_id(army_id)
    if army.is_empty():
        return
    moving_army_id = army_id
    movement_origin_id = String(army["province_id"])
    movement_destination_id = ""
    auto_advance_target_id = String(army.get("advance_target_id", ""))
    _refresh_management_action_state()
```

Add the lookup used by `_select_army()` and `_open_management_for_army()`:

```gdscript
func _find_army_by_id(army_id: String) -> Dictionary:
    for army: Dictionary in bridge.get_army_summaries():
        if army.get("id", "") == army_id:
            return army
    return {}
```

In `_refresh_map_data()`, replace old selector refreshes with:

```gdscript
_refresh_advance_plans()
if workspace_mode == WorkspaceMode.PROVINCE_MANAGEMENT and \
        province_by_id.has(managed_province_id):
    _refresh_management_window(moving_army_id)
```

Make `_refresh_technology_status()` call `province_management_window.set_technology(_player_technology())` only when management is open. Run:

```powershell
rg -n "RegionDetails|TechnologyControls|SelectionStatus|ArmyControls|recruit_button|move_army_button|auto_advance_button|army_selector|army_details|advance_plans" game/scripts/main.gd game/scenes/main/main.tscn
```

Expected: no old main-panel references; `AdvancePlans` and new technology paths may appear only under `province_management_window.tscn` or its encapsulated script.

- [ ] **Step 4: Run the focused UI suite**

Run sequentially:

```powershell
& $godot --headless --log-file C:\Users\Asus\Documents\Codex\2026-07-07\w\consolidation-layout.log --path game --script res://tests/main_layout_smoke_test.gd
& $godot --headless --log-file C:\Users\Asus\Documents\Codex\2026-07-07\w\consolidation-info.log --path game --script res://tests/province_info_window_smoke_test.gd
& $godot --headless --log-file C:\Users\Asus\Documents\Codex\2026-07-07\w\consolidation-management.log --path game --script res://tests/province_management_window_smoke_test.gd
& $godot --headless --log-file C:\Users\Asus\Documents\Codex\2026-07-07\w\consolidation-component.log --path game --script res://tests/province_management_window_component_smoke_test.gd
& $godot --headless --log-file C:\Users\Asus\Documents\Codex\2026-07-07\w\consolidation-road.log --path game --script res://tests/road_construction_window_smoke_test.gd
```

Expected: all five pass.

- [ ] **Step 5: Commit main-page cleanup**

```powershell
git add game/scenes/main/main.tscn game/scripts/main.gd game/tests/main_layout_smoke_test.gd
git commit -m "refactor: remove duplicate main province controls"
```

---

### Task 5: Complete regression verification

**Files:**
- Verify only; no planned production-file changes.

**Interfaces:**
- Consumes: completed Tasks 1-4.
- Produces: verification evidence for integration.

- [ ] **Step 1: Run every Godot test sequentially**

```powershell
$tests=Get-ChildItem -LiteralPath game\tests -Filter '*.gd' | Sort-Object Name
foreach ($test in $tests) {
    & $godot --headless `
        --log-file "C:\Users\Asus\Documents\Codex\2026-07-07\w\final-$($test.BaseName).log" `
        --path game `
        --script "res://tests/$($test.Name)"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
```

Expected: all existing tests plus the new component test exit with code `0`.

- [ ] **Step 2: Run main-scene startup and repository checks**

```powershell
& $godot --headless --log-file C:\Users\Asus\Documents\Codex\2026-07-07\w\final-consolidated-main.log --path game --quit-after 2
git diff --check
git status --short
```

Expected: main scene starts without script errors, `git diff --check` is empty, and no implementation changes remain uncommitted.

- [ ] **Step 3: Review the requirement checklist**

Confirm from tests and scene inspection:

```text
[ ] Main duplicate region, technology, selection, and army nodes are deleted.
[ ] Province information remains available on single click.
[ ] Technology research works in province management.
[ ] Recruitment and adjacent movement work in province management.
[ ] Non-adjacent automatic advance works in province management.
[ ] Plan selection, pause/resume, strategy, and clear work in province management.
[ ] Other main-page controls and road workflow remain present.
[ ] Workspace scrolling contains the expanded page.
```
