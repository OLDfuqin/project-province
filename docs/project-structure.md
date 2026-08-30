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
C++ 模拟核心
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
| `stable_id.hpp` | 仅头文件 | 定义国家、地区、军队和订单使用的强类型稳定字符串 ID 基础，避免不同 ID 混用。 |
| `country.hpp` | 仅头文件 | 定义国家状态，例如名称、单字代号、国库和控制信息所需的国家数据。 |
| `province.hpp` | 仅头文件 | 定义地区状态，包括归属、控制、人口、可招募士兵、基础经济、地形和邻接。 |
| `army.hpp` | 仅头文件 | 定义军队状态，包括所有者、本国编制编号、位置、兵力、移动点和自动推进计划。 |
| `terrain.hpp` | 仅头文件 | 定义平原、森林、丘陵、山地、首都五类地形及经济、移动、道路和防守参数。 |
| `data_load_error.hpp` | 仅头文件 | 定义共享JSON数据加载异常，避免布局加载器依赖完整剧本加载器。 |
| `diplomacy.hpp` | 仅头文件 | 定义外交状态、和平结算策略和无序国家关系键。 |
| `technology.hpp` | 仅头文件 | 定义经济0–3级、军事0–8级、道路0–4级科技分支及国家科技等级。 |
| `road.hpp` | `road.cpp` | 定义道路等级、无序地区连接键，以及道路字符串转换等基础逻辑。 |
| `game_order.hpp` | 仅头文件 | 定义稳定订单 ID，以及军队行动、征兵、修路、研究和 AI 宣战五种强类型持久订单载荷。 |
| `version.hpp` | 仅头文件 | 保存核心或数据兼容性所需的版本常量。 |

### 3.2 游戏总状态与命令链

| 公共头文件 | 对应实现 | 用途 |
| --- | --- | --- |
| `game_state.hpp` | `game_state.cpp` | 权威运行时状态容器；保存国家、地区、军队、道路、外交、科技、时钟、待执行订单和序号，区分普通 `army_N` 分配器与按地区确定的重建中立守军 ID，并跨两种 ID 统一校验隐藏守军的位置唯一性、引用与资源预留。 |
| `game_clock.hpp` | `game_clock.cpp` | 管理游戏年月和跨年日期计算；外部回合长度由命令处理器固定为1个月。 |
| `game_command.hpp` | 由命令处理器实现 | 定义固定月度推进、修路、征兵、更名、合并、移动、宣战、议和、研究科技和取消订单等命令数据。 |
| `game_event.hpp` | 由各系统产生 | 定义订单创建/取消、维护、移动、战斗、项目完成、自动整编和月度结算事件，用于反馈与行动报告。 |
| `command_processor.hpp` | `command_processor.cpp` | 所有外部状态变更的统一入口；创建或取消订单，并按固定月度顺序编排收入、维护、人口、移动、战斗、项目、整编和 AI 规划。 |
| `order_system.hpp` | `order_system.cpp` | 事务式创建行动、征兵、修路、研究和宣战订单，负责资金、人口、移动点、军队 ID 容量预留、唯一性限制以及玩家取消退款。 |
| `monthly_order_system.hpp` | `monthly_order_system.cpp` | 分阶段重新校验并执行外交、普通移动、联合进攻和延迟项目，处理失效退款及月末自动整编。 |
| `game_status.hpp` | `game_status.cpp` | 汇总国家是否仍存续、胜负状态及整局游戏状态。 |

### 3.3 经济、人口和科技

| 公共头文件 | 对应实现 | 用途 |
| --- | --- | --- |
| `economy_system.hpp` | `economy_system.cpp` | 按已保存的地区基础经济和控制国经济科技计算最终经济，汇总普通国家财政收入并执行月度入账。 |
| `maintenance_system.hpp` | `maintenance_system.cpp` | 按普通国家全国总兵力的一半向下取整扣除月度维护费，允许国库为负并豁免隐藏中立国。 |
| `population_system.hpp` | `population_system.cpp` | 执行月度人口与可招募士兵增长、上限和向下取整规则；缺失中立守军以独立于普通军队序号的确定性地区 ID 重建。 |
| `technology_system.hpp` | `technology_system.cpp` | 提供研究费用与上限公式，并在研究订单到期时完成已预付的经济、军事或道路科技升级。 |

### 3.4 军事、移动、道路和和平

| 公共头文件 | 对应实现 | 用途 |
| --- | --- | --- |
| `army_system.hpp` | `army_system.cpp` | 处理预付征兵完成、兵源与人口扣减、编制编号、军队更名、订单锁定检查和同地军队合并规则。 |
| `movement_system.hpp` | `movement_system.cpp` | 以半点单位发放并限制移动点，偿还防守债务，计算完整路径成本，并寻找只以敌区为终点的订单路径。 |
| `battle_calculator.hpp` | `battle_calculator.cpp` | 头文件定义纯战斗输入/输出契约；实现联合进攻有效战力、双方比例伤亡、结果和稳定 ID 破平局。 |
| `battle_system.hpp` | `battle_system.cpp` | 收集并应用同国多军联合进攻与共同防守结果；注入战斗随机参数，分配双方伤亡、扣除守军移动点、撤回进攻军并处理占领。 |
| `road_system.hpp` | `road_system.cpp` | 按地形经济系数校验道路科技准入、计算费用与折扣，并在修路订单到期时完成已预付连接。 |
| `peace_system.hpp` | `peace_system.cpp` | 结束战争、按策略恢复或保留领土，并遣返不合法驻留的军队。 |

### 3.5 AI、剧本和存档

| 公共头文件 | 对应实现 | 用途 |
| --- | --- | --- |
| `ai_system.hpp` | `ai_system.cpp` | 在月度结算后为非玩家国家选择下个月的研究、征兵、宣战和军队行动订单，不直接执行即时行动。 |
| `grid_map_layout.hpp` | `grid_map_layout.cpp` | 读取并严格校验共享9×9布局、四国放置区和2×2首都源格。 |
| `map_cell_generator.hpp` | `map_cell_generator.cpp` | 按蛇形顺序、邻格权重、森林覆盖和离散人口规则生成81个随机原始格。 |
| `map_scenario_generator.hpp` | `map_scenario_generator.cpp` | 把原始格组装为69地区场景，合并首都、推导邻接并创建隐藏中立国和17支守军。 |
| `scenario_loader.hpp` | `scenario_loader.cpp` | 读取四国和共享布局；注入正式或测试随机源并创建新游戏状态。 |
| `save_game.hpp` | `save_game.cpp` | 以严格schema 7序列化完整随机地图、订单队列、预留与进度，并在恢复后执行跨引用和唯一性校验；拒绝schema 6及更早存档。 |

## 4. Godot 桥接层：`bridge/`

| 文件 | 用途 |
| --- | --- |
| `bridge/src/province_bridge.hpp` | 声明暴露给 GDScript 的 `ProvinceBridge` 节点、订单查询/取消/报价 API 和所持有的 C++ 游戏状态。 |
| `bridge/src/province_bridge.cpp` | 实现剧本、状态、schema 7存档与命令 API；序列化玩家本国订单、月度事件和联合战斗结果，并提供可达目标及征兵/修路报价。 |
| `bridge/src/province_bridge_bindings.cpp` | 用 `ClassDB` 注册全部 `ProvinceBridge` 方法，包括 `get_pending_orders`、`cancel_order`、`get_army_order_targets` 和项目报价；新增 API 时必须同步绑定。 |
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
| `grid_map_layout.json` | 共享地图布局：9×9尺寸、80像素格边长、四国角落范围和四组2×2首都源格。C++生成场景，Godot生成多边形。 |
| `technologies.json` | 各国家经济、军事和道路科技的初始等级。 |

固定地区文件 `provinces.json` 和固定几何文件 `map_geometry.json` 已移除。数据约束由 `scenario_loader`、`GridMapLayoutLoader` 和场景生成器共同负责。修改布局时，必须同步检查生成器、动态地图几何、存档布局ID和测试。

### 5.3 场景：`game/scenes/`

| 文件 | 用途 |
| --- | --- |
| `scenes/main/main.tscn` | 主游戏页面；组织固定1个月回合栏、地图区、国家/外交摘要、待执行订单列表和右侧功能窗口预留区。 |
| `scenes/ui/province_info_window.tscn` | 单击地区后显示的只读地区信息窗口布局。 |
| `scenes/ui/province_management_window.tscn` | 双击地区后显示的管理窗口布局，容纳征兵预留、可达行动目标、军队订单锁、研究倒计时和推进计划。 |
| `scenes/ui/road_construction_window.tscn` | 独立修路订单界面布局，显示端点、报价、订单剩余月份、状态和重置操作。 |

`.tscn` 负责节点结构和基础布局；复杂行为应放在对应 `.gd` 脚本中。

### 5.4 主界面和地图脚本：`game/scripts/`

| 文件 | 用途 |
| --- | --- |
| `main.gd` | 主界面协调器；连接节点信号，管理当前玩家国家、本国订单列表与取消按钮并提交订单；消费 bridge 返回的征兵/道路权威报价、国家维护摘要、月度事件和议和退款，并刷新固定回合按钮、地图与分阶段报告。 |
| `province_map.gd` | `ProvinceMap` 自绘地图控件；从共享布局动态生成65个单格与4个首都多边形，执行缩放拖动、命中测试，并绘制国家颜色、城市/首都、地形、逐编制军队、道路、前线和推进路径。 |
| `province_info_window.gd` | 把地区、国家、军队和道路查询结果格式化为单击地区的只读信息。 |
| `province_management_window.gd` | 管理地区窗口状态，显示人口预留、bridge 权威征兵报价、可达目的地和研究订单，禁止合并已下单军队，并发出征兵、行动、取消计划和研究等信号；不在窗口内复制征兵公式。 |
| `road_construction_window.gd` | 发出修路端点选择、提交和重置信号，并呈现 `main.gd` 传入的端点、预计费用、可提交状态、待执行状态和提示；脚本本身不拥有道路报价或负债规则。 |
| `main.gd.uid` | Godot 为主脚本生成的资源 UID；当前已受版本控制，避免手工修改。 |

`main.gd` 以界面编排为主要职责。维护费使用 bridge 国家摘要中的最近结算值；征兵上限通过 `get_recruitment_order_quote()` 做权威查询；道路费用与资格使用 `get_road_order_quote()`。界面不再拥有维护费重算、固定征兵单价或道路本地费用 fallback，核心与桥接是扣款、报价、资格和订单执行的唯一权威来源。GDScript 只负责把这些只读结果组织成界面文字与交互状态。

### 5.5 UI 辅助脚本：`game/scripts/ui/`

| 文件 | 用途 |
| --- | --- |
| `game_text_formatter.gd` | `GameTextFormatter`；集中生成待执行订单、退款、联合战斗、移动、项目完成和自动整编等中文文本，并本地化稳定错误。维护费摘要、负债标签和维护阶段日志由 `main.gd` 基于 bridge 只读结果组织。 |
| `strategy_panel_presenter.gd` | `StrategyPanelPresenter`；把国家战略摘要和军队推进计划转换为主界面可显示的文本。 |

这类脚本可以组装只读视图，但不得成为权威状态来源。维护、道路和征兵的公式、资格、扣款及最终拒绝结果均由 C++ 核心决定，并通过 bridge 返回；UI 不保留公式副本。

### 5.6 美术资源：`game/assets/`

| 文件或目录 | 用途 |
| --- | --- |
| `assets/maps/icons/city.png` | 普通城市透明底地图图标。 |
| `assets/maps/icons/capital.png` | 首都透明底地图图标。 |
| `assets/maps/icons/terrain_*.png` | 平原、森林、丘陵和山地四类透明底地形图标。 |
| `assets/maps/icons/army.png` | 每支编制军队对应的持枪士兵透明底图标。 |
| `assets/ui/.gitkeep` | 为未来图标、主题和界面美术资源保留目录。 |

`.gitkeep` 只是让 Git 记录空目录，不是运行时资源；目录加入真实资源后可以视情况删除。

## 6. 测试

### 6.1 C++ 核心测试：`tests/core/`

| 文件 | 用途 |
| --- | --- |
| `battle_calculator_test.cpp` | 使用固定随机参数验证联合进攻战斗公式边界、结果判定、双方比例伤亡、余数优先级与稳定 ID 破平局。 |
| `core_smoke_test.cpp` | 核心测试程序入口，串行调用本节各 C++ 测试组；自身验证时钟与稳定 ID、随机剧本集成、固定月度命令、征兵/移动/修路/研究订单、费用、维护事件顺序、自动整编、首都地形和版本。 |
| `order_system_test.cpp` | 集中验证军队行动与征兵、修路、研究项目订单，覆盖资源预留、取消/失效退款、议和遣返取消、路径与时序、进攻目标锁、联合战斗、防守移动债务、延迟项目、自动整编和整编后的 AI 规划。宣战订单的持久化变体由 `save_game_smoke_test.cpp` 覆盖，AI 延迟宣战由 `ai_smoke_test.cpp` 覆盖。 |
| `ai_smoke_test.cpp` | AI 决策、目标选择、寻路、订单创建和跨月延迟执行测试。 |
| `save_game_smoke_test.cpp` | 严格schema 7、全部订单载荷与进度往返、历史schema拒绝、军队 ID 容量和恶意预留/引用校验测试。 |
| `grid_map_layout_test.cpp` | 验证布局schema、尺寸、四国范围、首都源格和非法布局拒绝规则。 |
| `map_cell_generator_test.cpp` | 用固定随机索引验证蛇形顺序、相邻概率边界、森林覆盖、人口集合和基础经济。 |
| `map_scenario_generator_test.cpp` | 验证69地区、四首都、17无主地区/守军、邻接和100次正式随机场景不变量。 |
| `neutral_population_test.cpp` | 验证人口增减同步地形基础经济、无主地区增长转入守军、多个缺失守军的唯一确定性重建、碰撞拒绝、无中立财政收入，以及普通国家可因维护负债与隐藏中立国维护豁免。 |
| `neutral_combat_test.cpp` | 验证普通国家与中立国天然敌对、中立守军不可移动、延迟进攻、同归于尽、无守军占领和胜利后的直接法理征服。 |
| `smoke_test_groups.hpp` | 声明拆分后的测试组函数，使单个测试程序统一调用各测试文件。 |

运行 `scripts/build.cmd` 会构建并执行 `build/bin/province_core_tests.exe`。

### 6.2 Godot 集成测试：`game/tests/`

| 文件 | 用途 |
| --- | --- |
| `map_smoke_test.gd` | 验证地图几何加载、地区命中、城市/地形/军队图标布局、稳定ID排序和超量折叠。 |
| `main_layout_smoke_test.gd` | 验证移除月份选择器、固定1个月按钮、待执行订单区、功能区边界、极值征兵报价、议和退款刷新、读档身份/推进目标和布局不重叠。 |
| `game_status_bridge_smoke_test.gd` | 验证游戏状态和国家存续信息能通过桥接层正确读取。 |
| `army_bridge_smoke_test.gd` | 验证征兵与行动订单、取消及议和退款、可达目标、联合战斗、编制名称、更名、合并和推进策略的桥接行为。 |
| `road_bridge_smoke_test.gd` | 验证修路报价、订单预付创建、取消退款、延迟完成、结算事件和道路连接查询。 |
| `technology_bridge_smoke_test.gd` | 验证研究订单、5倍费用、倒计时、取消退款边界和完成后效果查询。 |
| `ai_bridge_smoke_test.gd` | 验证可玩剧本启用 AI，连续月度推进能通过桥接返回 AI 行动，并且隐藏中立国不会出现在这些行动或公开国家摘要中。AI 订单的延迟时序由 C++ `ai_smoke_test.cpp` 覆盖。 |
| `save_game_bridge_smoke_test.gd` | 验证 Godot 侧schema 7快速存取、订单进度与预留的完整状态往返。 |
| `game_text_formatter_smoke_test.gd` | 验证待执行订单、退款、移动、联合战斗、项目完成、自动整编等中文格式化，以及已知/未知稳定错误的本地化回退。 |
| `province_info_window_smoke_test.gd` | 验证地区信息窗口的只读内容和清空行为。 |
| `province_management_window_component_smoke_test.gd` | 验证地区管理窗口的订单节点、信号、负债禁用、研究倒计时和军队订单锁。 |
| `province_management_window_smoke_test.gd` | 验证管理窗口与主场景之间的可达目标、订单创建、待执行列表和取消操作集成。 |
| `province_management_advance_smoke_test.gd` | 验证长期推进目标、策略和创建下月行动订单的操作。 |
| `road_construction_window_smoke_test.gd` | 验证修路窗口的端点权限与邻接校验、权威报价、手动重置、订单延迟完成，以及负债、端点易手和外部建成后的重新报价与清理。取消退款由 `road_bridge_smoke_test.gd` 覆盖。 |
| `generated_scenario_helpers.gd` | 为随机场景测试按稳定ID选择首都、受控地区、相邻端点和无主邻格，避免依赖已删除的固定地区ID。 |

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
| 修改维护或负债限制 | `maintenance_system.*`、`order_system.*` | 月度顺序、bridge 维护摘要、`main.gd` 展示文字、订单/UI禁用和核心测试 |
| 修改人口或可招募士兵 | `population_system.*`、必要时 `army_system.*` | 规则文档、征兵测试、存档 |
| 修改军队编号、更名或合并 | `army_system.*`、`game_command.hpp` | 存档、桥接 API、地区管理窗口和军队测试 |
| 修改订单类型、预留或退款 | `game_order.hpp`、`order_system.*`、`monthly_order_system.*` | `game_state.cpp`校验、schema 7、桥接/UI和订单测试 |
| 修改战斗、占领或撤退 | `battle_calculator.*`、`battle_system.*`、`monthly_order_system.*` | 订单测试、军队桥接测试、事件文本、和平逻辑 |
| 修改移动点或道路效率 | `movement_system.*`、`road_system.*`、`monthly_order_system.*` | 行动预留、地图路径预览、道路测试、科技效果 |
| 修改宣战或和平 | `diplomacy.hpp`、`peace_system.*`、`command_processor.cpp` | 外交 UI、国家关系和军队遣返测试 |
| 修改科技 | `technology_system.*`、`technology.hpp` | `technologies.json`、管理窗口、科技测试 |
| 修改 AI | `ai_system.*` | AI 核心测试、AI 桥接测试、回合行动摘要 |
| 新增玩家命令 | `game_command.hpp`、`command_processor.*`、对应系统 | `game_event.hpp`、桥接 API、绑定、UI 和测试 |
| 新增 Godot 查询/API | `province_bridge.hpp/.cpp` | `province_bridge_bindings.cpp` 和桥接测试 |
| 修改主页面布局 | `main.tscn`、必要时 `main.gd` | `main_layout_smoke_test.gd` 和不同窗口尺寸 |
| 修改地区弹窗 | 对应 `scenes/ui/*.tscn` 与同名脚本 | 组件测试、主场景集成测试和滚动边界 |
| 修改地图绘制或交互 | `province_map.gd` | `grid_map_layout.json`、C++布局加载器、地图测试和输入模式 |
| 修改展示文字 | `game_text_formatter.gd` 或相应窗口脚本 | 不在格式化器中复制规则公式 |
| 修改四国或地图布局 | `countries.json`、`grid_map_layout.json` | schema、布局/单格/场景生成测试、动态地图覆盖和存档兼容性 |
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
