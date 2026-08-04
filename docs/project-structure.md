# 项目结构导航

本文档记录当前仓库的实际结构。新增系统或移动文件时，应同步更新这里。

## 运行链路

```text
玩家输入
  -> game/scenes 与 game/scripts（Godot 界面和地图）
  -> bridge/src（Godot Variant 与 C++ 类型转换）
  -> core/src（确定性规则、状态和命令）
  -> game/data（剧本初始数据）
```

依赖只能沿箭头向右。`core/` 不得引用 Godot；数据文件不得承载运行时状态。

## 根目录

| 路径 | 内容 | 是否提交 |
| --- | --- | --- |
| `core/` | 独立 C++20 模拟核心 | 是 |
| `bridge/` | Godot GDExtension 适配层 | 是 |
| `game/` | Godot 工程、界面、地图与剧本数据 | 是 |
| `tests/` | C++ 核心测试 | 是 |
| `docs/` | 当前规则、架构、计划和历史设计 | 是 |
| `scripts/` | 构建和启动脚本 | 是 |
| `third_party/` | godot-cpp 等外部依赖 | 由子模块管理 |
| `build/` | C++ 对象文件、库和测试程序 | 否，可删除重建 |
| `.vs/`、`game/.godot/` | IDE 与 Godot 导入缓存 | 否，可删除重建 |

## C++ 模拟核心

- 公共接口：`core/include/province/core/`
- 实现：`core/src/`
- 总状态：`game_state.hpp/.cpp`
- 玩家和 AI 命令入口：`command_processor.hpp/.cpp`
- 月度结算：`economy_system`、`population_system`、`technology_system`
- 军事：`army_system`、`movement_system`、`battle_system`、`peace_system`
- 数据和存档：`scenario_loader`、`save_game`

核心使用稳定字符串 ID 关联国家、地区和军队。所有会改变游戏的操作应通过命令处理器产生事件，避免界面直接修改状态。

## Godot 桥接层

- `province_bridge.hpp`：暴露给 Godot 的完整 API。
- `province_bridge.cpp`：API 的命令和查询实现。
- `province_bridge_bindings.cpp`：Godot 方法注册表。新增公开 API 时必须在这里绑定。
- `register_types.cpp`：GDExtension 初始化与类型注册。

桥接层只负责类型转换和调用核心，不应复制经济、移动或战斗公式。

## Godot 表现层

- 主场景：`game/scenes/main/main.tscn`
- 主协调器：`game/scripts/main.gd`
- 地图输入与绘制：`game/scripts/province_map.gd`
- 地区窗口：`province_info_window.gd`、`province_management_window.gd`
- 道路窗口：`road_construction_window.gd`
- 展示文本：`game/scripts/ui/game_text_formatter.gd`
- 战略摘要与推进计划：`game/scripts/ui/strategy_panel_presenter.gd`

`main.gd` 负责节点连接、界面状态和玩家操作编排。纯文本格式化或只读视图组装应放进 `scripts/ui/`，避免主协调器继续膨胀。

## 数据与规则文档

- `game/data/countries.json`：国家初始数据。
- `game/data/provinces.json`：地区、人口、地形和相邻关系。
- `game/data/map_geometry.json`：扁平地图形状。
- `game/data/technologies.json`：科技初始状态。
- `docs/current-game-rules.md`：当前有效的计算公式和玩法规则，规则变更必须同步更新。
- `docs/superpowers/specs/`、`docs/superpowers/plans/`：历史设计与实施记录，不作为当前规则来源。

## 测试

- `tests/core/core_smoke_test.cpp`：核心规则综合入口。
- `tests/core/ai_smoke_test.cpp`：AI 决策和寻路。
- `tests/core/save_game_smoke_test.cpp`：存档结构与往返一致性。
- `game/tests/`：GDExtension、地图、布局、AI、道路、科技和存档集成测试。

运行 `scripts/build.cmd` 会构建核心、桥接 DLL，并执行 C++ 测试。对象文件统一位于 `build/obj/`，不应出现在源码目录。

## 常见修改位置

| 需求 | 首选修改位置 |
| --- | --- |
| 修改经济、人口、战斗公式 | `core/`，同时更新规则文档和核心测试 |
| 新增玩家命令 | `game_command.hpp`、`command_processor.cpp`、对应系统 |
| 向 Godot 暴露新能力 | `province_bridge.hpp/.cpp` 和 `province_bridge_bindings.cpp` |
| 修改主界面布局 | `game/scenes/main/main.tscn` 与布局烟雾测试 |
| 修改展示文字 | `game/scripts/ui/`，不要把公式写入格式化器 |
| 修改剧本初值或地图 | `game/data/`，随后运行全部 Godot 集成测试 |
| 修改存档字段 | `save_game.cpp`、schema 版本和存档测试 |
