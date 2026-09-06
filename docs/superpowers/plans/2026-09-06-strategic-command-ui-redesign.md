# 战略指挥台主界面重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有双右栏主界面重构为地图优先的战略指挥台，在不改变模拟规则的前提下提供顶部全局状态栏、左侧主导航、单一右侧上下文检查器、底部地图模式栏与信息抽屉。

**Architecture:** 先把主题、系统栏、业务面板和完整管理页做成可独立测试的 Godot 场景组件，保持现有主界面持续可运行；所有组件就绪后，再由 `main.tscn` 和 `main.gd` 完成一次受测试保护的壳层切换。UI 只消费 `ProvinceBridge` 的权威字典并发送信号，不复制费用、人口、移动、订单或科技规则。

**Tech Stack:** Godot 4.6.3、GDScript、Godot Control/Container/Theme、C++20 GDExtension `ProvinceBridge`、SCons、现有 headless Godot smoke tests。

**Spec:** `docs/superpowers/specs/2026-09-05-strategic-command-ui-redesign-design.md`

## Global Constraints

- 本次只调整界面结构、表现与 UI 编排，不修改模拟核心、固定一月回合、订单结算、存档 schema 或游戏数值。
- 任何费用、上限、可达目标、道路报价、科技状态和错误原因必须来自 `ProvinceBridge` 权威结果。
- 玩家可见文本使用中文，不显示内部稳定 ID，也不透传英文异常文本。
- 主界面在 1280×720、1440×900、1920×1080 下无重叠、截断或不可达操作。
- 每次提交都必须保持主场景可加载；旧入口只能在新入口接通并通过测试后删除。
- 不复制 OpenVic、Freeciv、OpenDoctrines、Sovereign 或 Unciv 的代码与美术资源。
- 新增字体、图标或纹理前必须记录许可证；本计划第一轮使用 Godot 绘制、文字和现有项目图标，不增加第三方素材。
- 保留工作树中用户已有的 `game/scripts/main.gd` 与 `game/tests/army_bridge_smoke_test.gd` 格式化改动，不覆盖、不暂存。

---

## File Structure

### 新增主题与通用组件

- `game/themes/strategic_ui_theme.tres`：全局颜色、字号、按钮、面板、页签、滚动条与焦点样式。
- `game/scenes/ui/metric_card.tscn`、`game/scripts/ui/metric_card.gd`：标题、主数值、副说明组成的通用指标卡。
- `game/scenes/ui/global_status_bar.tscn`、`game/scripts/ui/global_status_bar.gd`：国家身份、国库、收入、维护、人力、日期与下一回合。
- `game/scenes/ui/primary_navigation.tscn`、`game/scripts/ui/primary_navigation.gd`：地图、国家、外交、科技、军事、经济、设置导航。
- `game/scenes/ui/map_mode_bar.tscn`、`game/scripts/ui/map_mode_bar.gd`：政治、地形、经济、军事、道路模式及抽屉入口。
- `game/scenes/ui/context_inspector.tscn`、`game/scripts/ui/context_inspector.gd`：互斥展示地区摘要、地区管理、军队管理、修路工具。
- `game/scenes/ui/bottom_drawer.tscn`、`game/scripts/ui/bottom_drawer.gd`：订单、通知与回合报告。
- `game/scenes/ui/management_page_host.tscn`、`game/scripts/ui/management_page_host.gd`：全尺寸国家级页面容器与返回行为。

### 新增国家级页面

- `game/scenes/ui/country_overview_page.tscn`、`game/scripts/ui/country_overview_page.gd`：国家概况。
- `game/scenes/ui/diplomacy_page.tscn`、`game/scripts/ui/diplomacy_page.gd`：国家选择、宣战与议和。
- `game/scenes/ui/technology_page.tscn`、`game/scripts/ui/technology_page.gd`：科技等级、费用、耗时与研究订单。
- `game/scenes/ui/military_overview_page.tscn`、`game/scripts/ui/military_overview_page.gd`：全国军队与军事订单摘要。
- `game/scenes/ui/economic_overview_page.tscn`、`game/scripts/ui/economic_overview_page.gd`：收入、维护费与地区贡献。
- `game/scenes/ui/settings_page.tscn`、`game/scripts/ui/settings_page.gd`：快速保存、快速读取和版本信息。
- `game/scenes/ui/map_hover_tooltip.tscn`、`game/scripts/ui/map_hover_tooltip.gd`：地区悬停摘要。

### 修改既有文件

- `game/scenes/main/main.tscn`：替换 `TurnBar + RightPanel + WorkspacePanel` 为战略指挥台壳。
- `game/scripts/main.gd`：改用唯一节点名和组件信号，保留桥接调用与业务编排，删除旧面板文字拼装。
- `game/scenes/ui/province_info_window.tscn`、`game/scripts/province_info_window.gd`：改成卡片式地区摘要，保留 `display_province()` 与 `clear()` 兼容接口。
- `game/scenes/ui/province_management_window.tscn`、`game/scripts/province_management_window.gd`：改成概况、军事、建设、订单页签；保留现有业务信号。
- `game/scenes/ui/road_construction_window.tscn`、`game/scripts/road_construction_window.gd`：改成权威报价卡与地图选择工作流。
- `game/scripts/province_map.gd`：增加地图模式、交互高亮和悬停位置输出。
- `game/scripts/ui/game_text_formatter.gd`：只增加界面所需的稳定中文摘要格式，不新增规则计算。
- `docs/project-structure.md`：记录新增 UI 组件职责。

### 新增或更新测试

- 新增：`game/tests/strategic_theme_smoke_test.gd`
- 新增：`game/tests/strategic_chrome_component_smoke_test.gd`
- 新增：`game/tests/context_inspector_smoke_test.gd`
- 新增：`game/tests/bottom_drawer_smoke_test.gd`
- 新增：`game/tests/management_pages_smoke_test.gd`
- 新增：`game/tests/map_presentation_smoke_test.gd`
- 修改：`game/tests/main_layout_smoke_test.gd`
- 修改：`game/tests/province_info_window_smoke_test.gd`
- 修改：`game/tests/province_management_window_component_smoke_test.gd`
- 修改：`game/tests/province_management_window_smoke_test.gd`
- 修改：`game/tests/province_management_advance_smoke_test.gd`
- 修改：`game/tests/road_construction_window_smoke_test.gd`

测试命令均从仓库根目录执行：

```powershell
$godot = '..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/strategic_theme_smoke_test.gd
```

各任务下方另列出本任务所需的全部精确测试命令；上述命令仅用于说明统一的 Godot 路径和调用形式。

---

### Task 1: 建立战略 UI 主题与指标卡

**Files:**
- Create: `game/themes/strategic_ui_theme.tres`
- Create: `game/scenes/ui/metric_card.tscn`
- Create: `game/scripts/ui/metric_card.gd`
- Create: `game/tests/strategic_theme_smoke_test.gd`

**Interfaces:**
- Produces: `MetricCard.set_metric(title: String, value: String, detail: String = "") -> void`
- Produces: 可由 `Main.theme` 加载的 `res://themes/strategic_ui_theme.tres`

- [ ] **Step 1: 写主题与指标卡失败测试**

```gdscript
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
```

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```powershell
$godot = '..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/strategic_theme_smoke_test.gd
```

Expected: FAIL，原因是主题或指标卡场景尚不存在。

- [ ] **Step 3: 创建主题资源和指标卡最小实现**

`metric_card.gd`：

```gdscript
class_name MetricCard
extends PanelContainer

func set_metric(title: String, value: String, detail: String = "") -> void:
    $Content/Title.text = title
    $Content/Value.text = value
    $Content/Detail.text = detail
    $Content/Detail.visible = not detail.is_empty()
```

`strategic_ui_theme.tres` 至少定义以下权威令牌：

```text
Label/font_color = #E8EEF7
Label/font_size = 14
Button/font_color = #E8EEF7
Button/font_hover_color = #FFFFFF
PanelContainer/panel background = #111B2E
Button/normal background = #18243A
Button/hover background = #22314B
Button/pressed background = #D6A64A
Button/focus border = #D6A64A, 2px
```

- [ ] **Step 4: 运行主题测试并检查资源加载错误**

Run: 与 Step 2 相同。

Expected: PASS，日志包含 `Strategic theme smoke test passed`，且不含 `SCRIPT ERROR` 或 `ERROR:`。

- [ ] **Step 5: 提交主题基础**

```powershell
git add game/themes/strategic_ui_theme.tres game/scenes/ui/metric_card.tscn game/scripts/ui/metric_card.gd game/tests/strategic_theme_smoke_test.gd
git commit -m "feat: add strategic interface theme"
```

---

### Task 2: 创建顶部状态栏、左侧导航与底部模式栏

**Files:**
- Create: `game/scenes/ui/global_status_bar.tscn`
- Create: `game/scripts/ui/global_status_bar.gd`
- Create: `game/scenes/ui/primary_navigation.tscn`
- Create: `game/scripts/ui/primary_navigation.gd`
- Create: `game/scenes/ui/map_mode_bar.tscn`
- Create: `game/scripts/ui/map_mode_bar.gd`
- Create: `game/tests/strategic_chrome_component_smoke_test.gd`

**Interfaces:**
- Produces: `GlobalStatusBar.set_snapshot(country: Dictionary, date: Dictionary) -> void`
- Produces: `GlobalStatusBar.set_advance_enabled(enabled: bool, warning: String = "") -> void`
- Produces signal: `GlobalStatusBar.advance_turn_requested`
- Produces signal: `PrimaryNavigation.destination_requested(destination: String)`
- Produces: `PrimaryNavigation.set_active_destination(destination: String) -> void`
- Produces signal: `MapModeBar.map_mode_requested(mode: String)`
- Produces signal: `MapModeBar.drawer_requested(drawer: String)`
- Produces: `MapModeBar.set_counts(pending_orders: int, notifications: int) -> void`
- Produces: `MapModeBar.set_active_mode(mode: String) -> void`

- [ ] **Step 1: 写三个系统栏组件的失败测试**

```gdscript
extends SceneTree

func _initialize() -> void:
    var status := (load("res://scenes/ui/global_status_bar.tscn") as PackedScene).instantiate()
    var navigation := (load("res://scenes/ui/primary_navigation.tscn") as PackedScene).instantiate()
    var mode_bar := (load("res://scenes/ui/map_mode_bar.tscn") as PackedScene).instantiate()
    root.add_child(status)
    root.add_child(navigation)
    root.add_child(mode_bar)
    status.set_snapshot({
        "name": "奥罗里亚", "treasury": 10300, "fiscal_income": 3150,
        "last_maintenance_charge": 500, "recruitable_population": 3400,
    }, {"year": 1000, "month": 1})
    mode_bar.set_counts(4, 2)
    navigation.set_active_destination("map")
    if status.get_node("Margin/Row/CountryName").text != "奥罗里亚" or \
            status.get_node("Margin/Row/AdvanceTurn").text != "进入下一回合" or \
            mode_bar.get_node("Margin/Row/PendingOrders").text != "待执行订单 4" or \
            navigation.active_destination() != "map":
        push_error("Strategic chrome components lost their stable presentation")
        quit(1)
        return
    print("Strategic chrome component smoke test passed")
    quit(0)
```

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```powershell
$godot = '..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/strategic_chrome_component_smoke_test.gd
```

Expected: FAIL，原因是三个组件场景尚不存在。

- [ ] **Step 3: 实现稳定信号和展示 API**

`global_status_bar.gd`：

```gdscript
class_name GlobalStatusBar
extends PanelContainer

signal advance_turn_requested

func _ready() -> void:
    $Margin/Row/AdvanceTurn.pressed.connect(func() -> void:
        advance_turn_requested.emit()
    )

func set_snapshot(country: Dictionary, date: Dictionary) -> void:
    $Margin/Row/CountryName.text = String(country.get("name", "未知国家"))
    $Margin/Row/Treasury.text = "国库 %s" % _number(country.get("treasury", 0))
    $Margin/Row/Income.text = "月收入 %s" % _number(country.get("fiscal_income", 0))
    $Margin/Row/Maintenance.text = "维护费 %s" % _number(
        country.get("last_maintenance_charge", 0)
    )
    $Margin/Row/Recruitable.text = "可招募 %s" % _number(
        country.get("recruitable_population", 0)
    )
    $Margin/Row/Date.text = "%d年%d月" % [date.get("year", 0), date.get("month", 1)]

func set_advance_enabled(enabled: bool, warning: String = "") -> void:
    $Margin/Row/AdvanceTurn.disabled = not enabled
    $Margin/Row/AdvanceTurn.tooltip_text = warning

func _number(value: Variant) -> String:
    return str(int(value))
```

`primary_navigation.gd` 必须把按钮元数据限制为：

```gdscript
const DESTINATIONS := ["map", "country", "diplomacy", "technology", "military", "economy", "settings"]
```

`map_mode_bar.gd` 必须把地图模式限制为 `political`、`terrain`、`economy`、`military`、`roads`，抽屉限制为 `orders`、`notifications`、`turn_report`。

- [ ] **Step 4: 运行组件测试并确认 GREEN**

Run: 与 Step 2 相同。

Expected: PASS，信号可连接，按钮 tooltip 均为中文，组件最小高度分别为 56、44 像素或设计文件规定值。

- [ ] **Step 5: 提交系统栏组件**

```powershell
git add game/scenes/ui/global_status_bar.tscn game/scripts/ui/global_status_bar.gd game/scenes/ui/primary_navigation.tscn game/scripts/ui/primary_navigation.gd game/scenes/ui/map_mode_bar.tscn game/scripts/ui/map_mode_bar.gd game/tests/strategic_chrome_component_smoke_test.gd
git commit -m "feat: add strategic interface chrome"
```

---

### Task 3: 重构地区摘要并建立单一上下文检查器

**Files:**
- Create: `game/scenes/ui/context_inspector.tscn`
- Create: `game/scripts/ui/context_inspector.gd`
- Modify: `game/scenes/ui/province_info_window.tscn`
- Modify: `game/scripts/province_info_window.gd`
- Create: `game/tests/context_inspector_smoke_test.gd`
- Modify: `game/tests/province_info_window_smoke_test.gd`

**Interfaces:**
- Produces: `ContextInspector.show_empty(message: String = "请选择地区或军队") -> void`
- Produces: `ContextInspector.show_panel(mode: String, title: String, panel: Control) -> void`
- Produces: `ContextInspector.current_mode() -> String`
- Produces signal: `ContextInspector.close_requested`
- Extends existing: `ProvinceInfoWindow.display_province(...) -> void`
- Produces signal: `ProvinceInfoWindow.manage_requested(province_id: String)`

- [ ] **Step 1: 更新地区摘要测试并新增检查器失败测试**

```gdscript
var inspector := (load("res://scenes/ui/context_inspector.tscn") as PackedScene).instantiate()
var summary := (load("res://scenes/ui/province_info_window.tscn") as PackedScene).instantiate()
root.add_child(inspector)
summary.display_province(province, armies, roads, province_by_id, countries)
inspector.show_panel("province_summary", "地区信息", summary)
if inspector.current_mode() != "province_summary" or \
        summary.get_node("Body/Metrics/Population/Content/Value").text != "340,000" or \
        not summary.get_node("Body/ManageProvince").visible:
    push_error("Context inspector did not show the compact province summary")
    quit(1)
    return
```

测试还必须断言检查器在 `empty` 与 `province_summary` 之间切换时只有一个业务面板可见，且 `manage_requested` 返回当前地区 ID。

- [ ] **Step 2: 运行两个测试并确认 RED**

Run:

```powershell
$godot = '..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/context_inspector_smoke_test.gd
& $godot --headless --path game --script res://tests/province_info_window_smoke_test.gd
```

Expected: 新检查器测试 FAIL；地区摘要测试因新节点路径不存在而 FAIL。

- [ ] **Step 3: 实现互斥检查器与卡片式地区摘要**

`context_inspector.gd`：

```gdscript
class_name ContextInspector
extends PanelContainer

signal close_requested
var _mode := "empty"
var _active_panel: Control

func _ready() -> void:
    %Close.pressed.connect(func() -> void: close_requested.emit())
    show_empty()

func show_empty(message: String = "请选择地区或军队") -> void:
    _clear_active_panel()
    _mode = "empty"
    %Title.text = "战略信息"
    %Empty.text = message
    %Empty.visible = true

func show_panel(mode: String, title: String, panel: Control) -> void:
    _clear_active_panel()
    _mode = mode
    %Title.text = title
    %Empty.visible = false
    _active_panel = panel
    %Content.add_child(panel)
    panel.visible = true

func current_mode() -> String:
    return _mode

func _clear_active_panel() -> void:
    if is_instance_valid(_active_panel):
        %Content.remove_child(_active_panel)
    _active_panel = null
```

地区摘要把人口、经济、财政、驻军放入四个 `MetricCard`，其余内容只保留法理/控制、地形、道路和可招募士兵。现有 `display_province()` 参数与权威字典读取保持不变。

- [ ] **Step 4: 运行检查器与地区摘要测试**

Run: 与 Step 2 相同。

Expected: 两项 PASS；摘要中不显示内部 `owner_id`、`province_id`，按钮和 tooltip 均为中文。

- [ ] **Step 5: 提交上下文检查器**

```powershell
git add game/scenes/ui/context_inspector.tscn game/scripts/ui/context_inspector.gd game/scenes/ui/province_info_window.tscn game/scripts/province_info_window.gd game/tests/context_inspector_smoke_test.gd game/tests/province_info_window_smoke_test.gd
git commit -m "feat: add compact province inspector"
```

---

### Task 4: 将地区管理重排为页签结构

**Files:**
- Modify: `game/scenes/ui/province_management_window.tscn`
- Modify: `game/scripts/province_management_window.gd`
- Modify: `game/tests/province_management_window_component_smoke_test.gd`
- Modify: `game/tests/province_management_window_smoke_test.gd`
- Modify: `game/tests/province_management_advance_smoke_test.gd`

**Interfaces:**
- Preserves all existing signals from `ProvinceManagementWindow`.
- Preserves: `display_province()`、`set_destination()`、`set_technology()`、`set_pending_orders()`、`set_reachable_targets()`、`set_advance_target()`、`set_advance_plans()`、`set_action_state()`、`set_status()`、`clear()`。
- Produces: `set_active_tab(tab_id: String) -> void`
- Produces: `active_tab() -> String`

- [ ] **Step 1: 先把组件测试改为新页签契约**

```gdscript
window.display_province(province, armies, "auroria", "army_1", 10000, quote)
window.set_active_tab("military")
if window.active_tab() != "military" or \
        not window.get_node("Tabs/Military").visible or \
        window.get_node("Tabs/Overview").visible:
    _fail("Province management tabs are not mutually exclusive")
    return
window.set_pending_orders([{
    "order_id": "order_7", "order_type": "recruitment",
    "province_id": "capital_auroria", "manpower": 100,
    "remaining_months": 1,
}])
window.set_active_tab("orders")
if not window.get_node("Tabs/Orders/OrderSummary").text.contains("剩余1个月"):
    _fail("Province order tab lost its local order summary")
    return
```

原有征兵、选择军队、移动、推进、合并、更名测试继续保留，改用 `Tabs/Military/...` 路径。

- [ ] **Step 2: 运行三项地区管理测试并确认 RED**

Run:

```powershell
$godot = '..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/province_management_window_component_smoke_test.gd
& $godot --headless --path game --script res://tests/province_management_window_smoke_test.gd
& $godot --headless --path game --script res://tests/province_management_advance_smoke_test.gd
```

Expected: FAIL，原因是 `Tabs` 结构和页签 API 不存在。

- [ ] **Step 3: 重排场景但保持现有业务方法**

页签 ID 固定为：

```gdscript
const TAB_INDEX := {
    "overview": 0,
    "military": 1,
    "construction": 2,
    "orders": 3,
    "technology_legacy": 4,
}

func set_active_tab(tab_id: String) -> void:
    if not TAB_INDEX.has(tab_id):
        return
    %Tabs.current_tab = TAB_INDEX[tab_id]

func active_tab() -> String:
    for tab_id: String in TAB_INDEX:
        if TAB_INDEX[tab_id] == %Tabs.current_tab:
            return tab_id
    return "overview"
```

`technology_legacy` 在本任务保留现有研究能力以确保主场景持续可玩；Task 8 接通国家科技页后删除该页签。原来三个不可用建设按钮改成说明卡片，不展示可点击按钮。

- [ ] **Step 4: 运行地区管理测试并确认所有现有操作仍可用**

Run: 与 Step 2 相同。

Expected: 三项 PASS；征兵、移动、推进、合并、更名、科技研究与本地区订单没有功能回退。

- [ ] **Step 5: 提交页签式地区管理**

```powershell
git add game/scenes/ui/province_management_window.tscn game/scripts/province_management_window.gd game/tests/province_management_window_component_smoke_test.gd game/tests/province_management_window_smoke_test.gd game/tests/province_management_advance_smoke_test.gd
git commit -m "feat: organize province management into tabs"
```

---

### Task 5: 重构道路规划面板

**Files:**
- Modify: `game/scenes/ui/road_construction_window.tscn`
- Modify: `game/scripts/road_construction_window.gd`
- Modify: `game/tests/road_construction_window_smoke_test.gd`

**Interfaces:**
- Preserves existing signals: `select_start_requested`、`select_end_requested`、`build_requested`、`reset_requested`。
- Produces signal: `exit_requested`
- Preserves: `open_window()`、`reset_selection()`、`set_start()`、`set_end_province()`、`set_status()`、`clear()`。
- Produces: `set_selection_mode(mode: String) -> void`

- [ ] **Step 1: 写道路工具视觉状态失败测试**

```gdscript
road.open_window()
road.set_selection_mode("start")
road.set_start("北境")
road.set_selection_mode("end")
road.set_end_province("西境", 800, true, "路线合法，可以创建订单")
if road.get_node("Quote/Cost").text != "800" or \
        road.get_node("Quote/Status").text != "路线合法，可以创建订单" or \
        road.get_node("Actions/BuildRoad").disabled:
    push_error("Road planning panel did not show the authoritative quote")
    quit(1)
    return
```

继续保留敌方起点、非相邻终点、负国库、跨月道路已建、端点易主和成功下单后重置测试。

- [ ] **Step 2: 运行道路 UI 测试并确认 RED**

Run:

```powershell
$godot = '..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/road_construction_window_smoke_test.gd
```

Expected: FAIL，原因是 `Quote`、`Actions` 与选择模式 API 不存在。

- [ ] **Step 3: 实现道路报价卡与退出信号**

```gdscript
signal exit_requested

func set_selection_mode(mode: String) -> void:
    %SelectStart.button_pressed = mode == "start"
    %SelectEnd.button_pressed = mode == "end"
    %ModeHint.text = {
        "start": "请在地图上选择道路起点",
        "end": "请在地图上选择相邻终点",
    }.get(mode, "请选择道路端点")

func set_end_province(
    province_name: String,
    estimated_cost: int = 0,
    can_build: bool = true,
    status_message: String = "路线合法，可以创建订单"
) -> void:
    %EndProvince.text = province_name
    %Cost.text = "%d" % estimated_cost if estimated_cost > 0 else "—"
    %Status.text = status_message
    %BuildRoad.disabled = not can_build
```

不得恢复任何本地道路费用、科技门槛或控制权判断。

- [ ] **Step 4: 运行道路 UI 与道路桥接测试**

Run:

```powershell
$godot = '..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/road_construction_window_smoke_test.gd
& $godot --headless --path game --script res://tests/road_bridge_smoke_test.gd
```

Expected: 两项 PASS，报价始终与 `get_road_order_quote()` 一致。

- [ ] **Step 5: 提交道路面板**

```powershell
git add game/scenes/ui/road_construction_window.tscn game/scripts/road_construction_window.gd game/tests/road_construction_window_smoke_test.gd
git commit -m "feat: redesign road planning panel"
```

---

### Task 6: 创建订单、通知与回合报告底部抽屉

**Files:**
- Create: `game/scenes/ui/bottom_drawer.tscn`
- Create: `game/scripts/ui/bottom_drawer.gd`
- Create: `game/tests/bottom_drawer_smoke_test.gd`

**Interfaces:**
- Produces: `BottomDrawer.show_orders(orders: Array) -> void`
- Produces: `BottomDrawer.show_notifications(messages: Array[String]) -> void`
- Produces: `BottomDrawer.show_turn_report(report_text: String) -> void`
- Produces: `BottomDrawer.close() -> void`
- Produces: `BottomDrawer.current_drawer() -> String`
- Produces signal: `BottomDrawer.cancel_order_requested(order_id: String)`

- [ ] **Step 1: 写底部抽屉互斥与取消信号失败测试**

```gdscript
extends SceneTree

func _initialize() -> void:
    var drawer := (load("res://scenes/ui/bottom_drawer.tscn") as PackedScene).instantiate()
    root.add_child(drawer)
    var cancelled := ""
    drawer.cancel_order_requested.connect(func(order_id: String) -> void: cancelled = order_id)
    drawer.show_orders([{
        "order_id": "order_4", "order_type": "recruitment",
        "province_name": "北境", "manpower": 100, "remaining_months": 1,
    }])
    if drawer.current_drawer() != "orders" or not drawer.visible:
        push_error("Order drawer did not open")
        quit(1)
        return
    drawer.get_node("Panel/Body/Orders/Rows/Order0/Cancel").pressed.emit()
    if cancelled != "order_4":
        push_error("Order drawer did not emit the stable order ID")
        quit(1)
        return
    drawer.show_turn_report("财政收入：3150")
    if drawer.current_drawer() != "turn_report" or \
            drawer.get_node("Panel/Body/Orders").visible:
        push_error("Bottom drawers were not mutually exclusive")
        quit(1)
        return
    print("Bottom drawer smoke test passed")
    quit(0)
```

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```powershell
$godot = '..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/bottom_drawer_smoke_test.gd
```

Expected: FAIL，原因是抽屉场景不存在。

- [ ] **Step 3: 实现抽屉的稳定模式和订单行**

```gdscript
class_name BottomDrawer
extends Control

signal cancel_order_requested(order_id: String)
var _drawer := "closed"

func show_orders(orders: Array) -> void:
    _set_drawer("orders")
    _clear_order_rows()
    for index: int in orders.size():
        var order: Dictionary = orders[index]
        var row := _create_order_row(index, order)
        %OrderRows.add_child(row)

func show_notifications(messages: Array[String]) -> void:
    _set_drawer("notifications")
    %NotificationText.text = "\n".join(messages)

func show_turn_report(report_text: String) -> void:
    _set_drawer("turn_report")
    %TurnReport.text = report_text

func close() -> void:
    _set_drawer("closed")

func current_drawer() -> String:
    return _drawer
```

订单行必须使用现有 `GameTextFormatter.pending_order_text()`，取消按钮元数据只保存 `order_id`。

- [ ] **Step 4: 运行抽屉与文本格式化测试**

Run:

```powershell
$godot = '..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/bottom_drawer_smoke_test.gd
& $godot --headless --path game --script res://tests/game_text_formatter_smoke_test.gd
```

Expected: 两项 PASS，未知订单原因继续回落为稳定中文。

- [ ] **Step 5: 提交底部抽屉**

```powershell
git add game/scenes/ui/bottom_drawer.tscn game/scripts/ui/bottom_drawer.gd game/tests/bottom_drawer_smoke_test.gd
git commit -m "feat: add strategic information drawer"
```

---

### Task 7: 创建完整管理页面容器与只读国家页面

**Files:**
- Create: `game/scenes/ui/management_page_host.tscn`
- Create: `game/scripts/ui/management_page_host.gd`
- Create: `game/scenes/ui/country_overview_page.tscn`
- Create: `game/scripts/ui/country_overview_page.gd`
- Create: `game/scenes/ui/military_overview_page.tscn`
- Create: `game/scripts/ui/military_overview_page.gd`
- Create: `game/scenes/ui/economic_overview_page.tscn`
- Create: `game/scripts/ui/economic_overview_page.gd`
- Create: `game/tests/management_pages_smoke_test.gd`

**Interfaces:**
- Produces: `ManagementPageHost.open_page(page_id: String) -> void`
- Produces: `ManagementPageHost.close_page() -> void`
- Produces: `ManagementPageHost.current_page() -> String`
- Produces signal: `ManagementPageHost.back_requested`
- Produces: `CountryOverviewPage.set_snapshot(country: Dictionary, totals: Dictionary) -> void`
- Produces: `MilitaryOverviewPage.set_snapshot(armies: Array, orders: Array) -> void`
- Produces: `EconomicOverviewPage.set_snapshot(country: Dictionary, provinces: Array) -> void`

- [ ] **Step 1: 写页面路由与权威快照失败测试**

```gdscript
var host := (load("res://scenes/ui/management_page_host.tscn") as PackedScene).instantiate()
root.add_child(host)
host.open_page("country")
if host.current_page() != "country" or not host.get_node("Pages/Country").visible:
    push_error("Country page did not open exclusively")
    quit(1)
    return
host.get_node("Pages/Economy").set_snapshot(
    {"treasury": 10300, "fiscal_income": 3150, "last_maintenance_charge": 500},
    [{"name": "北境", "fiscal_income": 1200}, {"name": "西境", "fiscal_income": 900}]
)
host.open_page("economy")
if not host.get_node("Pages/Economy/Content/NetIncome").text.contains("2650"):
    push_error("Economic page did not derive display totals from the supplied snapshot")
    quit(1)
    return
```

这里的 `2650` 仅为 `3150 - 500` 的展示组合；测试禁止页面自行推导地区经济、维护费率或财政规则。

- [ ] **Step 2: 运行管理页面测试并确认 RED**

Run:

```powershell
$godot = '..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/management_pages_smoke_test.gd
```

Expected: FAIL，原因是页面容器与页面场景不存在。

- [ ] **Step 3: 实现互斥页面路由与三类只读页面**

```gdscript
class_name ManagementPageHost
extends PanelContainer

signal back_requested
const PAGE_IDS := ["country", "diplomacy", "technology", "military", "economy", "settings"]
var _page := "closed"

func open_page(page_id: String) -> void:
    if not page_id in PAGE_IDS:
        return
    for child: Control in %Pages.get_children():
        child.visible = child.get_meta("page_id", "") == page_id
    _page = page_id
    visible = true

func close_page() -> void:
    _page = "closed"
    visible = false

func current_page() -> String:
    return _page
```

国家页展示国库、人口、可招募士兵、控制地区和三项科技；军事页按稳定显示名列出玩家军队及当前订单；经济页按 `fiscal_income` 排序显示地区贡献，并使用桥接提供的维护费。

- [ ] **Step 4: 运行页面测试并检查无内部 ID**

Run: 与 Step 2 相同。

Expected: PASS；页面之间互斥，未知页面 ID 不改变当前页面，玩家可见文本不含 `army_`、`order_`、`capital_`、`cell_`。

- [ ] **Step 5: 提交页面容器和只读页面**

```powershell
git add game/scenes/ui/management_page_host.tscn game/scripts/ui/management_page_host.gd game/scenes/ui/country_overview_page.tscn game/scripts/ui/country_overview_page.gd game/scenes/ui/military_overview_page.tscn game/scripts/ui/military_overview_page.gd game/scenes/ui/economic_overview_page.tscn game/scripts/ui/economic_overview_page.gd game/tests/management_pages_smoke_test.gd
git commit -m "feat: add national management pages"
```

---

### Task 8: 创建外交、科技与设置页面

**Files:**
- Create: `game/scenes/ui/diplomacy_page.tscn`
- Create: `game/scripts/ui/diplomacy_page.gd`
- Create: `game/scenes/ui/technology_page.tscn`
- Create: `game/scripts/ui/technology_page.gd`
- Create: `game/scenes/ui/settings_page.tscn`
- Create: `game/scripts/ui/settings_page.gd`
- Modify: `game/scenes/ui/management_page_host.tscn`
- Modify: `game/tests/management_pages_smoke_test.gd`

**Interfaces:**
- Produces signal: `DiplomacyPage.declare_war_requested(target_country_id: String)`
- Produces signal: `DiplomacyPage.make_peace_requested(target_country_id: String, annex_occupied: bool)`
- Produces: `DiplomacyPage.set_snapshot(player_country_id: String, countries: Array, wars: Array) -> void`
- Produces signal: `TechnologyPage.research_requested(track: String)`
- Produces: `TechnologyPage.set_snapshot(technology: Dictionary, pending_orders: Array, treasury: int) -> void`
- Produces signal: `SettingsPage.quick_save_requested`
- Produces signal: `SettingsPage.quick_load_requested`
- Produces: `SettingsPage.set_build_info(version: String, save_count: int) -> void`

- [ ] **Step 1: 扩展管理页面测试，先锁定三个页面信号**

```gdscript
var diplomacy := host.get_node("Pages/Diplomacy")
var declared_target := ""
diplomacy.declare_war_requested.connect(func(country_id: String) -> void:
    declared_target = country_id
)
diplomacy.set_snapshot("auroria", countries, [])
diplomacy.select_country("solmere")
diplomacy.get_node("Content/Actions/DeclareWar").pressed.emit()
if declared_target != "solmere":
    push_error("Diplomacy page did not emit the selected stable country ID")
    quit(1)
    return

var technology := host.get_node("Pages/Technology")
technology.set_snapshot({
    "economy_level": 0, "economy_cost": 5000, "economy_max": false,
    "military_level": 0, "military_cost": 5000, "military_max": false,
    "roads_level": 0, "roads_cost": 5000, "roads_max": false,
}, [], 10000)
if technology.get_node("Content/Tracks/Economy/Research").disabled:
    push_error("Technology page ignored its authoritative affordability snapshot")
    quit(1)
    return
```

- [ ] **Step 2: 运行测试并确认 RED**

Run:

```powershell
$godot = '..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/management_pages_smoke_test.gd
```

Expected: FAIL，原因是三个功能页面不存在。

- [ ] **Step 3: 实现页面展示和纯意图信号**

科技按钮状态必须直接使用桥接摘要字段：

```gdscript
func _set_track(track: String, data: Dictionary, treasury: int, blocked: bool) -> void:
    var level := int(data.get("%s_level" % track, 0))
    var cost := int(data.get("%s_cost" % track, 0))
    var at_max := bool(data.get("%s_max" % track, false))
    var button: Button = _track_button(track)
    button.text = "已达最高等级" if at_max else "研究（%d）" % cost
    button.disabled = at_max or blocked or treasury < cost
    _track_level_label(track).text = "等级 %d" % level
```

外交页面只负责选择目标与发信号；宣战、议和合法性继续由 `main.gd -> ProvinceBridge` 决定。设置页面只发出保存/读取信号，不自行读写文件。

- [ ] **Step 4: 运行页面测试、科技桥接测试与存档测试**

Run:

```powershell
$godot = '..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/management_pages_smoke_test.gd
& $godot --headless --path game --script res://tests/technology_bridge_smoke_test.gd
& $godot --headless --path game --script res://tests/save_game_bridge_smoke_test.gd
```

Expected: 三项 PASS；页面不直接调用文件 API，不重新计算科技费用。

- [ ] **Step 5: 提交外交、科技和设置页面**

```powershell
git add game/scenes/ui/diplomacy_page.tscn game/scripts/ui/diplomacy_page.gd game/scenes/ui/technology_page.tscn game/scripts/ui/technology_page.gd game/scenes/ui/settings_page.tscn game/scripts/ui/settings_page.gd game/scenes/ui/management_page_host.tscn game/tests/management_pages_smoke_test.gd
git commit -m "feat: add diplomacy technology and settings pages"
```

---

### Task 9: 将主场景切换到战略指挥台壳

**Files:**
- Modify: `game/scenes/main/main.tscn`
- Modify: `game/scripts/main.gd`
- Modify: `game/scenes/ui/province_management_window.tscn`
- Modify: `game/scripts/province_management_window.gd`
- Modify: `game/tests/main_layout_smoke_test.gd`
- Modify: `game/tests/province_info_window_smoke_test.gd`
- Modify: `game/tests/province_management_window_smoke_test.gd`
- Modify: `game/tests/province_management_advance_smoke_test.gd`
- Modify: `game/tests/road_construction_window_smoke_test.gd`

**Interfaces:**
- Consumes all component APIs from Tasks 1–8.
- Preserves existing public test helpers: `workspace_mode_name()` and `map_input_mode_name()`；`workspace_mode_name()` 返回值映射到新检查器模式。
- Produces main UI state: `active_page_name() -> String`、`active_drawer_name() -> String`、`active_map_mode_name() -> String`。

- [ ] **Step 1: 先把主布局测试改成最终节点契约**

```gdscript
var top_bar := main_scene.get_node_or_null("Shell/Layout/GlobalStatusBar") as Control
var navigation := main_scene.get_node_or_null("Shell/Layout/MainRow/PrimaryNavigation") as Control
var map_panel := main_scene.get_node_or_null("Shell/Layout/MainRow/MapPanel") as Control
var inspector := main_scene.get_node_or_null("Shell/Layout/MainRow/ContextInspector") as Control
var mode_bar := main_scene.get_node_or_null("Shell/Layout/MapModeBar") as Control
var drawer := main_scene.get_node_or_null("Shell/BottomDrawer") as Control
if top_bar == null or navigation == null or map_panel == null or \
        inspector == null or mode_bar == null or drawer == null:
    push_error("Strategic shell is incomplete")
    quit(1)
    return
if main_scene.get_node_or_null("RightPanel") != null or \
        main_scene.get_node_or_null("WorkspacePanel") != null or \
        main_scene.get_node_or_null("TurnBar") != null:
    push_error("Legacy double-right-column layout still exists")
    quit(1)
    return
```

测试同时断言下一回合始终可见、检查器只有一个顶级 `ScrollContainer`、订单抽屉初始关闭、版本/存档数量不在地图首屏。

- [ ] **Step 2: 运行所有主界面集成测试并确认 RED**

Run:

```powershell
$godot = '..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/main_layout_smoke_test.gd
& $godot --headless --path game --script res://tests/province_info_window_smoke_test.gd
& $godot --headless --path game --script res://tests/province_management_window_smoke_test.gd
& $godot --headless --path game --script res://tests/road_construction_window_smoke_test.gd
```

Expected: FAIL，原因是主场景仍使用旧节点结构。

- [ ] **Step 3: 重建 `main.tscn` 壳并使用唯一节点名**

最终主场景层级必须为：

```text
Main
├── SimulationBridge
├── Background
└── Shell
    ├── Layout
    │   ├── GlobalStatusBar
    │   ├── MainRow
    │   │   ├── PrimaryNavigation
    │   │   ├── MapPanel
    │   │   │   ├── ProvinceMap
    │   │   │   └── MapHoverTooltip
    │   │   └── ContextInspector
    │   └── MapModeBar
    ├── BottomDrawer
    └── ManagementPageHost
```

`Main` 加载 `strategic_ui_theme.tres`。核心节点设置 `unique_name_in_owner = true`，`main.gd` 使用 `%GlobalStatusBar`、`%ProvinceMap`、`%ContextInspector`、`%MapModeBar`、`%BottomDrawer` 和 `%ManagementPageHost`，不再保存长路径字符串。

- [ ] **Step 4: 迁移 `main.gd` 编排并接通全部功能**

初始化信号集中到以下方法：

```gdscript
func _connect_strategic_ui() -> void:
    %GlobalStatusBar.advance_turn_requested.connect(_on_advance_turn_pressed)
    %PrimaryNavigation.destination_requested.connect(_on_navigation_requested)
    %MapModeBar.map_mode_requested.connect(_on_map_mode_requested)
    %MapModeBar.drawer_requested.connect(_on_drawer_requested)
    %ContextInspector.close_requested.connect(_close_workspace)
    %BottomDrawer.cancel_order_requested.connect(_on_cancel_order_pressed)
    %ManagementPageHost.back_requested.connect(_return_to_map)
```

新增刷新入口：

```gdscript
func _refresh_strategic_ui() -> void:
    var country := _player_country_summary()
    %GlobalStatusBar.set_snapshot(country, bridge.get_current_date())
    %MapModeBar.set_counts(_player_pending_orders().size(), _notifications.size())
    _refresh_active_context()
    _refresh_active_management_page()
```

必须逐项迁移并保留：

- 下一回合与固定一月显示。
- 单击地区摘要、双击地区管理、空白点击关闭临时摘要。
- 征兵、军队选择、移动、推进、合并、更名。
- 修路起点/终点选择、权威报价、创建订单和重置。
- 订单取消与退款反馈。
- 宣战、议和及和平退款反馈。
- 科技研究。
- 快速保存、读取、玩家身份恢复和读取后本地选择清理。
- 回合行动、事件历史、订单状态与错误中文化。

科技页接通后删除地区管理中的 `technology_legacy` 页签及 `set_technology()` 的页面渲染职责；为短期兼容可保留该方法为空转发，但必须在本任务内更新所有调用并删除空方法。

- [ ] **Step 5: 运行主布局与全部业务 UI 测试**

Run:

```powershell
$godot = '..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
$tests = @(
    'main_layout_smoke_test.gd',
    'province_info_window_smoke_test.gd',
    'province_management_window_component_smoke_test.gd',
    'province_management_window_smoke_test.gd',
    'province_management_advance_smoke_test.gd',
    'road_construction_window_smoke_test.gd',
    'bottom_drawer_smoke_test.gd',
    'management_pages_smoke_test.gd'
)
foreach ($test in $tests) {
    & $godot --headless --path game --script ("res://tests/" + $test)
    if ($LASTEXITCODE -ne 0) { throw "FAILED: $test" }
}
```

Expected: 8/8 PASS；主场景日志不含 `Node not found`、`SCRIPT ERROR`、`push_error` 或英文玩家错误。

- [ ] **Step 6: 提交主场景切换**

```powershell
git add game/scenes/main/main.tscn game/scripts/main.gd game/scenes/ui/province_management_window.tscn game/scripts/province_management_window.gd game/tests/main_layout_smoke_test.gd game/tests/province_info_window_smoke_test.gd game/tests/province_management_window_smoke_test.gd game/tests/province_management_advance_smoke_test.gd game/tests/road_construction_window_smoke_test.gd
git commit -m "feat: switch to strategic command interface"
```

---

### Task 10: 增加地图模式、交互高亮和悬停提示

**Files:**
- Create: `game/scenes/ui/map_hover_tooltip.tscn`
- Create: `game/scripts/ui/map_hover_tooltip.gd`
- Modify: `game/scripts/province_map.gd`
- Modify: `game/scripts/main.gd`
- Create: `game/tests/map_presentation_smoke_test.gd`
- Modify: `game/tests/map_smoke_test.gd`

**Interfaces:**
- Produces: `ProvinceMap.set_map_mode(mode: String) -> bool`
- Produces: `ProvinceMap.map_mode() -> String`
- Produces: `ProvinceMap.set_interaction_highlights(reachable: Array, attackable: Array, road_targets: Array) -> void`
- Produces signal: `ProvinceMap.province_hover_changed(province_id: String, screen_position: Vector2)`
- Produces: `MapHoverTooltip.show_snapshot(province: Dictionary, country_name: String, position: Vector2) -> void`
- Produces: `MapHoverTooltip.hide_tooltip() -> void`

- [ ] **Step 1: 写地图模式与高亮失败测试**

```gdscript
var map := ProvinceMap.new()
root.add_child(map)
if not map.load_grid_layout("res://data/grid_map_layout.json"):
    push_error(map.geometry_error())
    quit(1)
    return
map.set_scenario_data(provinces, countries)
if not map.set_map_mode("terrain") or map.map_mode() != "terrain":
    push_error("Terrain map mode was not accepted")
    quit(1)
    return
if map.set_map_mode("unknown") or map.map_mode() != "terrain":
    push_error("Unknown map mode changed map state")
    quit(1)
    return
map.set_interaction_highlights(["cell_1_1"], ["cell_2_1"], ["cell_1_2"])
var debug := map.presentation_state()
if debug.get("reachable", []) != ["cell_1_1"] or \
        debug.get("attackable", []) != ["cell_2_1"]:
    push_error("Map interaction highlights were not stable")
    quit(1)
    return
```

- [ ] **Step 2: 运行地图测试并确认 RED**

Run:

```powershell
$godot = '..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/map_presentation_smoke_test.gd
& $godot --headless --path game --script res://tests/map_smoke_test.gd
```

Expected: 新测试 FAIL，既有命中测试 PASS。

- [ ] **Step 3: 实现五种地图模式和三种交互高亮**

```gdscript
const MAP_MODES := ["political", "terrain", "economy", "military", "roads"]
var _map_mode := "political"
var _reachable_highlights: Array[String] = []
var _attackable_highlights: Array[String] = []
var _road_target_highlights: Array[String] = []

func set_map_mode(mode: String) -> bool:
    if not mode in MAP_MODES:
        return false
    _map_mode = mode
    queue_redraw()
    return true

func map_mode() -> String:
    return _map_mode

func set_interaction_highlights(
    reachable: Array,
    attackable: Array,
    road_targets: Array
) -> void:
    _reachable_highlights.assign(reachable)
    _attackable_highlights.assign(attackable)
    _road_target_highlights.assign(road_targets)
    queue_redraw()
```

绘制规则：

- `political`：现有国家颜色。
- `terrain`：平原、森林、丘陵、山地、首都使用稳定地形色，国家边界继续可见。
- `economy`：按当前场景地区 `fiscal_income` 最小/最大值归一化着色；无主地区保持中性灰。
- `military`：按地区驻军总兵力归一化，零驻军地区保持低亮度。
- `roads`：降低领土填充饱和度，提高道路线和合法端点对比度。

这些模式只改变绘制，不修改场景数据。

- [ ] **Step 4: 接通悬停提示与目标选择高亮**

`map_hover_tooltip.gd`：

```gdscript
class_name MapHoverTooltip
extends PanelContainer

func show_snapshot(province: Dictionary, country_name: String, position: Vector2) -> void:
    %Name.text = String(province.get("name", "未知地区"))
    %Summary.text = "%s · %s · 人口 %d · 驻军 %d" % [
        country_name,
        _terrain_name(String(province.get("terrain", "plains"))),
        int(province.get("population", 0)),
        int(province.get("stationed_manpower", 0)),
    ]
    global_position = position + Vector2(12, 12)
    visible = true

func hide_tooltip() -> void:
    visible = false
```

`main.gd` 在军队目的地选择时把桥接返回目标按 `is_attack` 分成 `reachable` 与 `attackable`；道路目标只根据逐个权威 quote 的 `accepted` 结果进入 `road_targets`。

- [ ] **Step 5: 运行地图、军队与道路测试**

Run:

```powershell
$godot = '..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/map_presentation_smoke_test.gd
& $godot --headless --path game --script res://tests/map_smoke_test.gd
& $godot --headless --path game --script res://tests/province_management_advance_smoke_test.gd
& $godot --headless --path game --script res://tests/road_construction_window_smoke_test.gd
```

Expected: 4/4 PASS；切换地图模式不改变任何桥接摘要或订单。

- [ ] **Step 6: 提交地图表现层**

```powershell
git add game/scenes/ui/map_hover_tooltip.tscn game/scripts/ui/map_hover_tooltip.gd game/scripts/province_map.gd game/scripts/main.gd game/tests/map_presentation_smoke_test.gd game/tests/map_smoke_test.gd
git commit -m "feat: add strategic map presentation modes"
```

---

### Task 11: 完成响应式布局、键盘返回、文档与全量验收

**Files:**
- Modify: `game/scenes/main/main.tscn`
- Modify: `game/scripts/main.gd`
- Modify: `game/themes/strategic_ui_theme.tres`
- Modify: `game/tests/main_layout_smoke_test.gd`
- Modify: `docs/project-structure.md`

**Interfaces:**
- Produces: `apply_viewport_profile(size: Vector2) -> void`
- Produces: `viewport_profile_name() -> String`，返回 `compact`、`standard` 或 `wide`
- Preserves all player workflows and bridge contracts.

- [ ] **Step 1: 为三种分辨率和 Esc 层级写失败测试**

```gdscript
var sizes := [Vector2(1280, 720), Vector2(1440, 900), Vector2(1920, 1080)]
for size: Vector2 in sizes:
    main_scene.size = size
    main_scene.apply_viewport_profile(size)
    await process_frame
    var map_rect := main_scene.get_node("Shell/Layout/MainRow/MapPanel").get_global_rect()
    var inspector_rect := main_scene.get_node(
        "Shell/Layout/MainRow/ContextInspector"
    ).get_global_rect()
    var advance_rect := main_scene.get_node(
        "Shell/Layout/GlobalStatusBar/Margin/Row/AdvanceTurn"
    ).get_global_rect()
    if map_rect.intersects(inspector_rect) or not Rect2(Vector2.ZERO, size).encloses(advance_rect):
        push_error("Strategic layout overlaps at %s" % size)
        quit(1)
        return

main_scene.call("_on_drawer_requested", "orders")
var escape_event := InputEventKey.new()
escape_event.pressed = true
escape_event.keycode = KEY_ESCAPE
main_scene.call("_unhandled_key_input", escape_event)
```

继续重复打开对应层级并发送同样的 `escape_event`，依次断言：确认框、抽屉、地图目标选择、设置页按规定顺序关闭。

- [ ] **Step 2: 运行主布局测试并确认 RED**

Run:

```powershell
$godot = '..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
& $godot --headless --path game --script res://tests/main_layout_smoke_test.gd
```

Expected: FAIL，原因是响应式 profile API 或 Esc 层级尚未完整实现。

- [ ] **Step 3: 实现三档响应式 profile**

```gdscript
func apply_viewport_profile(viewport_size: Vector2) -> void:
    if viewport_size.x < 1400.0 or viewport_size.y < 850.0:
        _viewport_profile = "compact"
        %PrimaryNavigation.custom_minimum_size.x = 56.0
        %ContextInspector.custom_minimum_size.x = 320.0
        %GlobalStatusBar.set_compact(true)
    elif viewport_size.x >= 1800.0:
        _viewport_profile = "wide"
        %PrimaryNavigation.custom_minimum_size.x = 64.0
        %ContextInspector.custom_minimum_size.x = 420.0
        %GlobalStatusBar.set_compact(false)
    else:
        _viewport_profile = "standard"
        %PrimaryNavigation.custom_minimum_size.x = 64.0
        %ContextInspector.custom_minimum_size.x = 360.0
        %GlobalStatusBar.set_compact(false)

func viewport_profile_name() -> String:
    return _viewport_profile
```

监听 `get_viewport().size_changed`，只应用尺寸与展示密度，不重新请求或修改模拟状态。

- [ ] **Step 4: 实现 Esc 返回层级与焦点规则**

```gdscript
func _unhandled_key_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    if event.keycode != KEY_ESCAPE:
        return
    if _close_confirmation_if_open():
        return
    if %BottomDrawer.current_drawer() != "closed":
        %BottomDrawer.close()
        return
    if map_input_mode != MapInputMode.NORMAL:
        _cancel_map_input_mode()
        return
    if %ManagementPageHost.current_page() != "closed":
        _return_to_map()
        return
    _open_settings_page()
```

所有图标按钮设置中文 tooltip；键盘焦点使用主题的 2 像素金色边框；禁用状态同时降低不透明度并保留原因 tooltip。

- [ ] **Step 5: 更新项目结构文档**

在 `docs/project-structure.md` 的 UI 部分逐项记录 Task 1–10 新增场景与脚本的职责，并删除 `RightPanel`、`WorkspacePanel` 和旧顶栏职责描述。明确 `main.gd` 只负责编排，组件负责展示，C++ 核心负责规则。

- [ ] **Step 6: 运行全量构建和全部 Godot 测试**

Run:

```powershell
cmd /c scripts\build.cmd
if ($LASTEXITCODE -ne 0) { throw 'C++/GDExtension build failed' }

$godot = '..\tools\godot-4.6.3\Godot_v4.6.3-stable_win64_console.exe'
$tests = Get-ChildItem -LiteralPath game\tests -Filter '*_test.gd' | Sort-Object Name
foreach ($test in $tests) {
    $log = Join-Path build ("strategic-ui-" + $test.BaseName + ".log")
    & $godot --headless --log-file $log --path game --script ("res://tests/" + $test.Name)
    if ($LASTEXITCODE -ne 0) { throw "FAILED: $($test.Name)" }
    if (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|push_error|ERROR:' -Quiet) {
        throw "ERROR MARKER: $($test.Name)"
    }
}
& $godot --headless --log-file build\strategic-ui-main.log --path game --quit-after 2
if ($LASTEXITCODE -ne 0) { throw 'Main scene startup failed' }
```

Expected: SCons/MSVC C++20 构建 PASS，核心测试 PASS，全部 `game/tests/*_test.gd` PASS，主场景启动 PASS，所有日志错误标记为 0。

- [ ] **Step 7: 完成三种分辨率视觉验收**

Run the game at 1280×720, 1440×900 and 1920×1080. At each size capture and inspect these states:

```text
1. 默认地图与空检查器
2. 地区摘要
3. 地区管理军事页
4. 道路规划并已选择两个端点
5. 待执行订单抽屉展开
6. 外交页面
7. 科技页面
```

Expected: 无面板重叠、文字截断、水平滚动或不可达按钮；1440×900 主页面与批准的概念图保持相同信息层级，不要求地图美术完全一致。

- [ ] **Step 8: 检查差异并提交最终验收**

```powershell
git diff --check
git status --short
git add game/scenes/main/main.tscn game/scripts/main.gd game/themes/strategic_ui_theme.tres game/tests/main_layout_smoke_test.gd docs/project-structure.md
git commit -m "feat: finish responsive strategic interface"
```

提交前确认索引不含用户既有格式化改动和生成日志。

---

## Final Verification Checklist

- [ ] `cmd /c scripts\build.cmd` 返回 0，并输出核心 smoke test passed。
- [ ] 所有 Godot `*_test.gd` 返回 0，日志无错误标记。
- [ ] 主场景 headless 启动返回 0，仍显示 4 个国家与 69 个地区。
- [ ] 1280×720、1440×900、1920×1080 七种关键界面状态视觉检查通过。
- [ ] 下一回合按钮在地图状态下始终可见。
- [ ] 主页面不存在 `RightPanel`、`WorkspacePanel`、旧 `TurnBar` 或两套顶级业务滚动区。
- [ ] 快速保存/读取、外交、科技、征兵、移动、推进、合并、更名、修路、取消订单和回合报告均可达。
- [ ] UI 未复制核心费用、上限、道路、科技或移动公式。
- [ ] 玩家界面不显示内部 ID 或英文错误。
- [ ] `git diff --check` 无输出，工作树只保留明确属于用户且未暂存的修改。
