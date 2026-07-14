# Scrollable Workspace Content Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent province information, province management, and road construction content from drawing outside the reserved workspace at the default `1280×720` resolution.

**Architecture:** Keep `WorkspacePanel/Workspace/TitleBar` fixed and place all switchable window content inside one shared `ScrollContainer` named `WindowViewport`. A nested `VBoxContainer` named `WindowContent` retains the existing one-visible-page-at-a-time behavior while the viewport clips overflow and exposes vertical scrolling only when required.

**Tech Stack:** Godot 4.6.3, GDScript, `.tscn` scenes, headless Godot smoke tests.

## Global Constraints

- Do not change the simulation core, economy, recruitment, movement, or road-building rules.
- Preserve the current map, right-side panel, top turn bar, and workspace anchors.
- Keep the title and close button outside the scrolling region.
- Disable horizontal scrolling; use automatic vertical scrolling.
- Reset vertical scroll position to the top whenever a workspace page opens or closes.
- Preserve all existing local changes in the main working tree by working only in `fix/workspace-overflow-scroll`.

---

### Task 1: Add and verify the shared scrollable workspace viewport

**Files:**
- Modify: `game/tests/main_layout_smoke_test.gd`
- Modify: `game/scenes/main/main.tscn`
- Modify: `game/scripts/main.gd`
- Modify: `game/tests/province_info_window_smoke_test.gd`
- Modify: `game/tests/province_management_window_smoke_test.gd`
- Modify: `game/tests/road_construction_window_smoke_test.gd`

**Interfaces:**
- Produces node: `WorkspacePanel/Workspace/WindowViewport` (`ScrollContainer`).
- Produces node: `WorkspacePanel/Workspace/WindowViewport/WindowContent` (`VBoxContainer`).
- Moves existing nodes `Content`, `ProvinceInfoWindow`, `ProvinceManagementWindow`, and `RoadConstructionWindow` under `WindowContent` without changing their names or scripts.
- Produces member: `@onready var workspace_scroll: ScrollContainer` in `main.gd`.

- [ ] **Step 1: Write the failing overflow regression test**

Extend `game/tests/main_layout_smoke_test.gd` after the existing `workspace_panel` lookup. Require the new viewport, ensure its rectangle stays inside the workspace, and open the longest page to prove that it has a usable vertical range:

```gdscript
var workspace_scroll := main_scene.get_node_or_null(
    "WorkspacePanel/Workspace/WindowViewport"
) as ScrollContainer
if workspace_scroll == null:
    push_error("Scrollable workspace viewport is missing")
    main_scene.free()
    quit(1)
    return

var panel_rect := workspace_panel.get_global_rect()
var viewport_rect := workspace_scroll.get_global_rect()
if not panel_rect.encloses(viewport_rect) or \
        workspace_scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
    push_error("Workspace viewport is outside the panel or allows horizontal overflow")
    main_scene.free()
    quit(1)
    return

var province_map := main_scene.get_node("MapPanel/ProvinceMap")
province_map.province_double_clicked.emit("northreach")
await process_frame
var vertical_bar := workspace_scroll.get_v_scroll_bar()
if vertical_bar.max_value <= vertical_bar.page:
    push_error("Province management content did not produce vertical scrolling")
    main_scene.free()
    quit(1)
    return
workspace_scroll.scroll_vertical = int(vertical_bar.max_value)
await process_frame
if workspace_scroll.scroll_vertical <= 0:
    push_error("Workspace could not scroll to its lower content")
    main_scene.free()
    quit(1)
    return
```

- [ ] **Step 2: Run the focused test and verify the expected failure**

Run:

```powershell
& $godot --headless --log-file build\workspace-scroll-red.log --path game --script res://tests/main_layout_smoke_test.gd
```

Expected: exit code `1` with `Scrollable workspace viewport is missing`.

- [ ] **Step 3: Add the shared scroll hierarchy**

In `game/scenes/main/main.tscn`, keep `TitleBar` directly under `Workspace`, then insert the following nodes:

```text
[node name="WindowViewport" type="ScrollContainer" parent="WorkspacePanel/Workspace"]
layout_mode = 2
size_flags_vertical = 3
clip_contents = true
horizontal_scroll_mode = 0
vertical_scroll_mode = 1
follow_focus = true

[node name="WindowContent" type="VBoxContainer" parent="WorkspacePanel/Workspace/WindowViewport"]
layout_mode = 2
size_flags_horizontal = 3
size_flags_vertical = 3
```

Change the parent of the four switchable content nodes to `WorkspacePanel/Workspace/WindowViewport/WindowContent`:

```text
[node name="Content" type="Label" parent="WorkspacePanel/Workspace/WindowViewport/WindowContent"]
[node name="ProvinceInfoWindow" parent="WorkspacePanel/Workspace/WindowViewport/WindowContent" instance=ExtResource("3_info")]
[node name="ProvinceManagementWindow" parent="WorkspacePanel/Workspace/WindowViewport/WindowContent" instance=ExtResource("4_management")]
[node name="RoadConstructionWindow" parent="WorkspacePanel/Workspace/WindowViewport/WindowContent" instance=ExtResource("5_road")]
```

Retain the existing properties on `Content` and the existing external-resource IDs.

- [ ] **Step 4: Update runtime node references and scroll reset**

In `game/scripts/main.gd`, replace the four old content paths with the new parent prefix and add the viewport reference:

```gdscript
@onready var workspace_scroll: ScrollContainer = $WorkspacePanel/Workspace/WindowViewport
@onready var workspace_content: Label = $WorkspacePanel/Workspace/WindowViewport/WindowContent/Content
@onready var province_info_window := $WorkspacePanel/Workspace/WindowViewport/WindowContent/ProvinceInfoWindow
@onready var province_management_window := $WorkspacePanel/Workspace/WindowViewport/WindowContent/ProvinceManagementWindow
@onready var road_construction_window := $WorkspacePanel/Workspace/WindowViewport/WindowContent/RoadConstructionWindow
```

Set `workspace_scroll.scroll_vertical = 0` in both `_open_workspace()` and `_close_workspace()` after clearing page visibility. Do not change workspace state transitions or page-specific logic.

- [ ] **Step 5: Migrate smoke-test node paths**

Update only the root path used to find each embedded window:

```gdscript
"WorkspacePanel/Workspace/WindowViewport/WindowContent/ProvinceInfoWindow"
"WorkspacePanel/Workspace/WindowViewport/WindowContent/ProvinceManagementWindow"
"WorkspacePanel/Workspace/WindowViewport/WindowContent/RoadConstructionWindow"
```

Keep every existing functional assertion for information display, recruitment, movement, road endpoint selection, construction, and automatic reset.

- [ ] **Step 6: Run the focused layout test and three workspace tests**

Run sequentially:

```powershell
& $godot --headless --log-file build\workspace-scroll-layout.log --path game --script res://tests/main_layout_smoke_test.gd
& $godot --headless --log-file build\workspace-scroll-info.log --path game --script res://tests/province_info_window_smoke_test.gd
& $godot --headless --log-file build\workspace-scroll-management.log --path game --script res://tests/province_management_window_smoke_test.gd
& $godot --headless --log-file build\workspace-scroll-road.log --path game --script res://tests/road_construction_window_smoke_test.gd
```

Expected: all four commands exit with code `0` and print their respective `passed` messages.

- [ ] **Step 7: Run the complete Godot regression suite and main-scene startup**

Run all 11 scripts in `game/tests` sequentially, followed by:

```powershell
& $godot --headless --log-file build\workspace-scroll-main.log --path game --quit-after 2
```

Expected: all 11 tests pass, the main scene starts without script errors, and `git diff --check` reports no whitespace errors.

- [ ] **Step 8: Commit the verified fix**

```powershell
git add game/scenes/main/main.tscn game/scripts/main.gd game/tests/main_layout_smoke_test.gd game/tests/province_info_window_smoke_test.gd game/tests/province_management_window_smoke_test.gd game/tests/road_construction_window_smoke_test.gd
git commit -m "fix: keep workspace content inside panel"
```
