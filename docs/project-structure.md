# 项目结构与文件用途

本文档是 Project Province 仓库结构、目录职责和文件用途的正式说明。它回答三个问题：代码放在哪里、各文件负责什么、修改某项功能时应从哪里开始。

本文档描述当前仓库，不代表未来规划。当前玩法与计算公式以 [`current-game-rules.md`](current-game-rules.md) 为准；历史设计与实施过程以 `docs/superpowers/` 中的文档为准。

## 1. 总体架构

```text
玩家输入与画面
  game/scenes + game/scripts
            │
            ▼
Godot/C++ 适配
  bridge/src + game/province_bridge.gdextension
            │
            ▼
确定性模拟核心
  core/include + core/src
            │
            ▼
剧本初始数据
  game/data/*.json
```

依赖规则：

- `core/` 是独立 C++20 模拟核心，不得引用 Godot。
- `bridge/` 可同时引用 Godot C++ API 和 `core/`，但只做转换与转发，不复制玩法公式。
- `game/scripts/` 通过 `ProvinceBridge` 查询状态、提交操作并更新界面，不直接保存另一套权威游戏状态。
- `game/data/` 只保存新游戏的初始数据和版本信息，不承载运行中的局势。
- 会改变游戏状态的操作应进入 C++ 命令处理链，产生可报告的游戏事件。

## 2. 根目录

| 路径 | 用途 | 版本控制 |
| --- | --- | --- |
| `core/` | 与引擎无关的 C++20 游戏状态和模拟规则 | 提交 |
| `bridge/` | Godot GDExtension 与 C++ 核心之间的适配层 | 提交 |
| `game/` | Godot 工程、场景、脚本、地图、数据和集成测试 | 提交源文件 |
| `tests/` | 不启动 Godot 的 C++ 核心测试 | 提交 |
| `docs/` | 当前架构、当前规则、历史设计和实施计划 | 提交 |
| `scripts/` | Windows 构建和启动入口 | 提交 |
| `third_party/` | 外部 C++ 依赖 | 子模块或随仓库提交 |
| `build/` | SCons 生成的对象、静态库和测试程序 | 不提交，可重建 |
| `.vs/` | Visual Studio 本地缓存和用户设置 | 不提交 |
| `.worktrees/` | 临时 Git 工作树 | 不提交，完成后清理 |
| `.git/` | Git 对象、分支、索引和远程配置 | Git 自身管理 |

### 2.1 根目录文件

| 文件 | 用途 |
| --- | --- |
| `README.md` | 项目入口，介绍游戏、技术栈、主要目录以及构建和启动命令。 |
| `SConstruct` | SCons 顶层构建脚本；编译 C++20 核心、核心测试和 GDExtension DLL，并把中间文件集中到 `build/obj/`。 |
| `.gitignore` | 排除构建产物、Godot/IDE 缓存、日志和临时工作目录。 |
| `.gitattributes` | 固定源码文本换行规则，声明图片和音频等二进制类型。 |
| `.editorconfig` | 统一 UTF-8、缩进、行尾和尾随空格规则。 |
| `.gitmodules` | 声明 `third_party/godot-cpp` Git 子模块及其远程地址。 |
| `.sconsign.dblite` | SCons 本地增量构建数据库；由工具生成，不应提交。 |

## 3. C++ 模拟核心：`core/`

`core/include/province/core/` 保存公共类型与系统接口，`core/src/` 保存对应实现。界面或桥接层只应依赖公共头文件。

### 3.1 状态、标识和基础类型

| 公共头文件 | 对应实现 | 用途 |
| --- | --- | --- |
| `stable_id.hpp` | 仅头文件 | 定义国家、地区、军队的强类型稳定字符串 ID，避免不同 ID 混用。 |
| `country.hpp` | 仅头文件 | 定义国家状态，例如名称、国库和控制信息所需的国家数据。 |
| `province.hpp` | 仅头文件 | 定义地区状态，包括归属、控制、人口、可招募士兵、地形和经济等。 |
| `army.hpp` | 仅头文件 | 定义军队状态，包括所有者、位置、兵力、移动点和自动推进计划。 |
| `terrain.hpp` | 仅头文件 | 定义平原、森林、丘陵、山地四类地形。 |
| `diplomacy.hpp` | 仅头文件 | 定义外交状态、和平结算策略和无序国家关系键。 |
| `technology.hpp` | 仅头文件 | 定义经济、军事、道路科技分支及国家科技等级。 |
| `road.hpp` | `road.cpp` | 定义道路等级、无序地区连接键，以及道路字符串转换等基础逻辑。 |
| `version.hpp` | 仅头文件 | 保存核心或数据兼容性所需的版本常量。 |

### 3.2 游戏总状态与命令链

| 公共头文件 | 对应实现 | 用途 |
| --- | --- | --- |
| `game_state.hpp` | `game_state.cpp` | 权威运行时状态容器；保存国家、地区、军队、道路、外交、科技和时钟，并提供查询、校验及受控修改入口。 |
| `game_clock.hpp` | `game_clock.cpp` | 管理游戏年月和按 1、3、6、12 个月推进的日期计算。 |
| `game_command.hpp` | 由命令处理器实现 | 定义推进回合、修路、征兵、移动、宣战、议和和研究科技等命令数据。 |
| `game_event.hpp` | 由各系统产生 | 定义操作和月度结算事件，用于结果反馈、回合行动摘要和战斗报告。 |
| `command_processor.hpp` | `command_processor.cpp` | 所有外部状态变更的统一入口；校验并执行命令、编排各规则系统、返回事件和错误。 |
| `game_status.hpp` | `game_status.cpp` | 汇总国家是否仍存续、胜负状态及整局游戏状态。 |

### 3.3 经济、人口和科技

| 公共头文件 | 对应实现 | 用途 |
| --- | --- | --- |
| `economy_system.hpp` | `economy_system.cpp` | 按人口、经济科技和地形计算地区经济，汇总国家财政收入并执行月度入账。 |
| `population_system.hpp` | `population_system.cpp` | 执行月度人口与可招募士兵增长、上限和向下取整规则。 |
| `technology_system.hpp` | `technology_system.cpp` | 校验研究条件、扣除费用并提升经济、军事或道路科技。 |

### 3.4 军事、移动、道路和和平

| 公共头文件 | 对应实现 | 用途 |
| --- | --- | --- |
| `army_system.hpp` | `army_system.cpp` | 处理征兵、兵源与人口扣减、军队创建和驻军相关规则。 |
| `movement_system.hpp` | `movement_system.cpp` | 发放移动点、计算道路移动成本、寻路并执行军队移动。 |
| `battle_system.hpp` | `battle_system.cpp` | 自动结算敌军接触后的战斗、损失、胜负、撤退和占领。 |
| `road_system.hpp` | `road_system.cpp` | 校验相邻地区、所有权和费用，创建或升级道路连接。 |
| `peace_system.hpp` | `peace_system.cpp` | 结束战争、按策略恢复或保留领土，并遣返不合法驻留的军队。 |

### 3.5 AI、剧本和存档

| 公共头文件 | 对应实现 | 用途 |
| --- | --- | --- |
| `ai_system.hpp` | `ai_system.cpp` | 为非玩家国家选择研究、征兵、宣战和军队行动等决策。 |
| `scenario_loader.hpp` | `scenario_loader.cpp` | 读取并校验 `game/data/` JSON，创建新游戏初始状态。 |
| `save_game.hpp` | `save_game.cpp` | 序列化完整运行时状态，校验存档 schema，并从存档恢复游戏。 |

## 4. Godot 桥接层：`bridge/`

| 文件 | 用途 |
| --- | --- |
| `bridge/src/province_bridge.hpp` | 声明暴露给 GDScript 的 `ProvinceBridge` 节点、公开方法和所持有的 C++ 游戏状态。 |
| `bridge/src/province_bridge.cpp` | 实现剧本加载、状态查询、命令提交、路径预览、存档等 Godot API，并在 Godot `Variant` 与核心类型间转换。 |
| `bridge/src/province_bridge_bindings.cpp` | 用 `ClassDB` 注册 `ProvinceBridge` 的公开方法；新增 GDScript 可调用 API 时必须同步绑定。 |
| `bridge/src/register_types.hpp` | 声明 GDExtension 初始化和反初始化函数。 |
| `bridge/src/register_types.cpp` | 实现扩展入口，在 Godot 场景初始化阶段注册 `ProvinceBridge`。 |

桥接层中不应出现另一套经济、人口、战斗或移动公式。若桥接测试失败，应先判断是类型转换/API 合同问题，还是核心规则问题。

## 5. Godot 工程：`game/`

### 5.1 工程配置和扩展

| 文件或目录 | 用途 |
| --- | --- |
| `game/project.godot` | Godot 工程设置、主场景、窗口和渲染配置；编辑器可能自动重排或写入内容，提交前需审查差异。 |
| `game/province_bridge.gdextension` | 告诉 Godot 扩展入口名、最低兼容版本和各平台 DLL 路径。 |
| `game/province_bridge.gdextension.uid` | Godot 为 GDExtension 资源维护的稳定 UID，应随资源提交。 |
| `game/bin/.gitkeep` | 保留空的 DLL 输出目录；实际 DLL 是构建产物，不提交。 |
| `game/.godot/` | Godot 导入、脚本和编辑器缓存，不提交，可重新生成。 |

### 5.2 剧本与地图数据：`game/data/`

| 文件 | 用途 |
| --- | --- |
| `schema_version.json` | 声明当前剧本 JSON 的 schema 版本，供加载器拒绝不兼容数据。 |
| `countries.json` | 四个国家的新游戏初始信息，例如稳定 ID、中文名、颜色和初始国库。 |
| `provinces.json` | 地区 ID、名称、所有者、控制者、人口、可招募士兵、地形和相邻关系。 |
| `map_geometry.json` | 地区 ID 到扁平多边形坐标的映射，只决定地图形状与点击区域。 |
| `technologies.json` | 各国家经济、军事和道路科技的初始等级。 |

数据约束由 `scenario_loader` 负责。修改 ID 时，必须同步检查国家、地区相邻关系、地图形状、科技和测试中的引用。

### 5.3 场景：`game/scenes/`

| 文件 | 用途 |
| --- | --- |
| `scenes/main/main.tscn` | 主游戏页面；组织回合栏、地图区、国家/外交摘要和右侧功能窗口预留区。 |
| `scenes/ui/province_info_window.tscn` | 单击地区后显示的只读地区信息窗口布局。 |
| `scenes/ui/province_management_window.tscn` | 双击地区后显示的管理窗口布局，容纳征兵、部队调动、自动推进和科技操作。 |
| `scenes/ui/road_construction_window.tscn` | 独立修路界面布局，显示起点、终点、成本、状态和重置操作。 |

`.tscn` 负责节点结构和基础布局；复杂行为应放在对应 `.gd` 脚本中。

### 5.4 主界面和地图脚本：`game/scripts/`

| 文件 | 用途 |
| --- | --- |
| `main.gd` | 主界面协调器；连接节点信号，切换功能窗口和地图输入模式，调用桥接 API，刷新日期、国家、外交、科技、地图和行动报告。 |
| `province_map.gd` | `ProvinceMap` 自绘地图控件；加载多边形、缩放拖动、命中测试，并绘制国家颜色、道路、军队、前线和推进路径。 |
| `province_info_window.gd` | 把地区、国家、军队和道路查询结果格式化为单击地区的只读信息。 |
| `province_management_window.gd` | 管理双击地区窗口的显示状态，发出征兵、选军、移动、自动推进、清除计划和科技操作信号。 |
| `road_construction_window.gd` | 管理修路窗口的起终点选择流程、预计费用、提示文字和重置状态。 |
| `main.gd.uid` | Godot 为主脚本生成的资源 UID；当前已受版本控制，避免手工修改。 |

`main.gd` 只负责编排。可独立测试的文字格式或只读摘要应继续下沉到 `game/scripts/ui/`，避免主协调器持续膨胀。

### 5.5 UI 辅助脚本：`game/scripts/ui/`

| 文件 | 用途 |
| --- | --- |
| `game_text_formatter.gd` | `GameTextFormatter`；集中生成战斗、移动、回合行动等中文展示文本。 |
| `strategy_panel_presenter.gd` | `StrategyPanelPresenter`；把国家战略摘要和军队推进计划转换为主界面可显示的文本。 |

这类脚本可以组装只读视图，但不得拥有权威状态或重新实现 C++ 规则。

### 5.6 资源占位目录：`game/assets/`

| 文件或目录 | 用途 |
| --- | --- |
| `assets/maps/.gitkeep` | 为未来地图图片或地图相关资源保留目录。 |
| `assets/ui/.gitkeep` | 为未来图标、主题和界面美术资源保留目录。 |

`.gitkeep` 只是让 Git 记录空目录，不是运行时资源；目录加入真实资源后可以视情况删除。

## 6. 测试

### 6.1 C++ 核心测试：`tests/core/`

| 文件 | 用途 |
| --- | --- |
| `core_smoke_test.cpp` | 核心测试程序入口及综合规则测试，覆盖剧本、回合、经济、人口、道路、征兵、移动、战争、和平和科技。 |
| `ai_smoke_test.cpp` | AI 决策、目标选择、寻路和回合行动测试。 |
| `save_game_smoke_test.cpp` | 存档 schema、序列化/反序列化和状态往返一致性测试。 |
| `smoke_test_groups.hpp` | 声明拆分后的测试组函数，使单个测试程序统一调用各测试文件。 |

运行 `scripts/build.cmd` 会构建并执行 `build/bin/province_core_tests.exe`。

### 6.2 Godot 集成测试：`game/tests/`

| 文件 | 用途 |
| --- | --- |
| `map_smoke_test.gd` | 验证地图几何加载、地区命中、地图数据和绘制所需状态。 |
| `main_layout_smoke_test.gd` | 验证主页面关键控件、功能区边界和布局不重叠。 |
| `game_status_bridge_smoke_test.gd` | 验证游戏状态和国家存续信息能通过桥接层正确读取。 |
| `army_bridge_smoke_test.gd` | 验证征兵、移动、战斗和军队推进策略的桥接行为。 |
| `road_bridge_smoke_test.gd` | 验证道路修建、费用、连接和移动效果的桥接行为。 |
| `technology_bridge_smoke_test.gd` | 验证科技研究、费用和效果查询的桥接行为。 |
| `ai_bridge_smoke_test.gd` | 验证 AI 回合行动通过桥接层执行并返回结果。 |
| `save_game_bridge_smoke_test.gd` | 验证 Godot 侧快速存取所需的完整状态往返。 |
| `province_info_window_smoke_test.gd` | 验证地区信息窗口的只读内容和清空行为。 |
| `province_management_window_component_smoke_test.gd` | 验证地区管理窗口作为独立组件的节点、信号和基础状态。 |
| `province_management_window_smoke_test.gd` | 验证管理窗口与主场景之间的地区选择和操作集成。 |
| `province_management_advance_smoke_test.gd` | 验证管理窗口中的自动推进目标、策略和计划操作。 |
| `road_construction_window_smoke_test.gd` | 验证修路窗口的起点、终点、重置和完成后状态流程。 |

Godot 测试是独立脚本，通常使用控制台版 Godot 以 `--headless --script` 运行。修改桥接 DLL 后，应先完成构建，再顺序运行相关 Godot 测试，避免加载旧 DLL。

## 7. 开发脚本：`scripts/`

| 文件 | 用途 |
| --- | --- |
| `build.cmd` | 方便从资源管理器、终端或快捷方式调用的 Windows 构建入口，转交给 PowerShell 脚本。 |
| `build.ps1` | 定位仓库旁的 SCons 启动器，运行默认构建，并在成功后执行 C++ 核心测试。 |
| `run_editor.cmd` | Windows 编辑器启动入口，转交给 PowerShell 脚本。 |
| `run_editor.ps1` | 定位项目配套 Godot 4.6.3，使用 `game/` 作为项目路径启动编辑器。 |

这些脚本假设工具位于仓库父目录的 `tools/` 中。若移动仓库或工具目录，应同步修改路径解析并验证桌面快捷方式。

## 8. 文档：`docs/`

| 文件或目录 | 用途 |
| --- | --- |
| `architecture.md` | 稳定的高层架构、模块边界和长期技术原则。 |
| `current-game-rules.md` | 当前已实现玩法、公式、取整顺序和已知优先问题的唯一规则手册。 |
| `project-structure.md` | 本文档；当前目录、逐文件职责和修改入口的唯一结构指南。 |
| `superpowers/specs/` | 已讨论功能的设计决策记录，解释“为什么这样设计”。 |
| `superpowers/plans/` | 对应设计的实施步骤记录，解释“当时如何落地”。 |

`specs/` 和 `plans/` 是历史记录。功能完成后，最终有效规则必须写入 `current-game-rules.md`，最终文件职责必须写入本文档。

## 9. 第三方依赖：`third_party/`

| 文件或目录 | 用途 |
| --- | --- |
| `godot-cpp/` | Godot 官方 C++ 绑定，以 Git 子模块管理；用于编译 GDExtension。其 `bin/`、`gen/` 为生成物。 |
| `nlohmann/json.hpp` | nlohmann/json 单头文件库，供剧本和存档 JSON 解析、生成使用。 |
| `nlohmann/README.md` | 记录内置 JSON 依赖的来源、版本或使用说明。 |

除升级依赖外，不直接修改第三方源码。升级 `godot-cpp` 时应检查 Godot 版本兼容性并完整重建桥接层。

## 10. 构建产物与本地文件

| 路径或模式 | 产生者 | 是否可重建 |
| --- | --- | --- |
| `build/obj/` | SCons | 是，C++ 中间对象 |
| `build/lib/` | SCons | 是，模拟核心静态库 |
| `build/bin/` | SCons | 是，核心测试程序 |
| `game/bin/province_bridge*.dll` | SCons/godot-cpp | 是，Godot 加载的扩展 DLL |
| `game/.godot/` | Godot 编辑器 | 是，导入与脚本缓存 |
| `.vs/` | Visual Studio | 是，解决方案缓存和用户状态 |
| `.sconsign.dblite` | SCons | 是，增量构建数据库 |
| `*.obj`、`*.pdb`、`*.lib`、`*.exp` | MSVC/SCons | 是，编译和调试产物 |
| `logs/`、`*.log`、`.verify-*.log` | 测试或诊断命令 | 是，本地日志 |
| `tmp/`、`.layout-stage/` | 临时开发流程 | 是，不应承载唯一源码 |

这些内容不应纳入功能提交。删除缓存只能用于明确的重建或故障诊断，操作前应确认目标路径准确。

## 11. 常见改动导航

| 需求 | 主要修改位置 | 必须同步检查 |
| --- | --- | --- |
| 修改经济或财政收入 | `economy_system.*` | `current-game-rules.md`、核心测试、国家/地区摘要 |
| 修改人口或可招募士兵 | `population_system.*`、必要时 `army_system.*` | 规则文档、征兵测试、存档 |
| 修改战斗、占领或撤退 | `battle_system.*`、`command_processor.cpp` | 军队桥接测试、事件文本、和平逻辑 |
| 修改移动点或道路效率 | `movement_system.*`、`road_system.*` | 地图路径预览、道路测试、科技效果 |
| 修改宣战或和平 | `diplomacy.hpp`、`peace_system.*`、`command_processor.cpp` | 外交 UI、国家关系和军队遣返测试 |
| 修改科技 | `technology_system.*`、`technology.hpp` | `technologies.json`、管理窗口、科技测试 |
| 修改 AI | `ai_system.*` | AI 核心测试、AI 桥接测试、回合行动摘要 |
| 新增玩家命令 | `game_command.hpp`、`command_processor.*`、对应系统 | `game_event.hpp`、桥接 API、绑定、UI 和测试 |
| 新增 Godot 查询/API | `province_bridge.hpp/.cpp` | `province_bridge_bindings.cpp` 和桥接测试 |
| 修改主页面布局 | `main.tscn`、必要时 `main.gd` | `main_layout_smoke_test.gd` 和不同窗口尺寸 |
| 修改地区弹窗 | 对应 `scenes/ui/*.tscn` 与同名脚本 | 组件测试、主场景集成测试和滚动边界 |
| 修改地图绘制或交互 | `province_map.gd` | `map_geometry.json`、地图测试和输入模式 |
| 修改展示文字 | `game_text_formatter.gd` 或相应窗口脚本 | 不在格式化器中复制规则公式 |
| 修改剧本初值 | `game/data/*.json` | schema、交叉 ID、加载测试和地图覆盖 |
| 修改存档字段 | `save_game.*` | 存档 schema、往返测试、旧存档兼容策略 |
| 升级 Godot/GDExtension | `godot-cpp`、`.gdextension`、工具脚本 | 清洁构建和全部 Godot 集成测试 |

## 12. 新文件放置规则

- 新的纯模拟规则放入 `core/include/province/core/` 和 `core/src/`，不要放入 GDScript。
- 新的 Godot/C++ 转换放入 `bridge/src/`，不要在桥接层复制模拟规则。
- 新的可复用 UI 组件采用 `game/scenes/ui/<name>.tscn` 与 `game/scripts/<name>.gd` 配对。
- 新的纯展示辅助类放入 `game/scripts/ui/`。
- 新的初始剧本数据放入 `game/data/`，并由 `scenario_loader` 校验。
- C++ 规则测试放入 `tests/core/`；需要 Godot 节点或桥接 DLL 的测试放入 `game/tests/`。
- 当前有效说明更新正式文档；阶段性方案和实施记录分别放入 `docs/superpowers/specs/` 与 `docs/superpowers/plans/`。

## 13. 持续维护规则

出现以下任一情况时，必须在同一功能提交中更新本文档：

1. 新增、删除、重命名或移动受版本控制的文件或目录。
2. 某个文件的主要职责发生变化。
3. 模块依赖方向、构建入口、测试入口或第三方依赖发生变化。
4. 新增一种需要开发者理解的生成目录、缓存或本地工具文件。

更新时应先运行 `git ls-files` 对照文件清单，再检查 `SConstruct`、`.gitignore` 和 `.gitmodules`。不要把规划中的文件写成已经存在，也不要把临时构建产物写成源代码。
