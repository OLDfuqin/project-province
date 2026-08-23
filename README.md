# Project Province

一款以领土扩张、宏观经济、道路网络和军事组织为核心的回合制大战略游戏。

## 技术栈

- Godot 4.6.3：地图、界面与表现层
- C++20：独立模拟核心（整数规则、随机地图与随机战斗）
- SCons 4.10.1：本地构建
- JSON：剧本与规则数据

## 目录

```text
core/       与Godot无关的C++模拟核心
game/       Godot工程、场景、脚本与资源
game/data/  四国数据、科技数据与共享9×9地图布局
tests/      C++与集成测试
docs/       架构和设计文档
scripts/    开发与构建辅助脚本
```

详细入口、目录职责和常见修改位置见 [`docs/project-structure.md`](docs/project-structure.md)。

## 构建模拟核心

在仓库根目录运行：

```powershell
.\scripts\build.cmd
```

## 启动Godot工程

```powershell
.\scripts\run_editor.cmd
```

新游戏会按 `game/data/grid_map_layout.json` 生成9×9随机地图：四角各有一个13地区国家，中间十字为17个有守军的无主地区，合并首都后共69个可操作地区。存档结构版本为6，不兼容旧32地区存档。
