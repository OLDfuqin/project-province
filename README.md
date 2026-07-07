# Project Province

一款以领土扩张、宏观经济、道路网络和军事组织为核心的回合制大战略游戏。

## 技术栈

- Godot 4.6.3：地图、界面与表现层
- C++20：确定性模拟核心
- SCons 4.10.1：本地构建
- JSON：剧本与规则数据

## 目录

```text
core/       与Godot无关的C++模拟核心
game/       Godot工程、场景、脚本与资源
game/data/  可随游戏导出的国家、地区、科技等数据
tests/      C++与集成测试
docs/       架构和设计文档
scripts/    开发与构建辅助脚本
```

## 构建模拟核心

在仓库根目录运行：

```powershell
.\scripts\build.cmd
```

## 启动Godot工程

```powershell
.\scripts\run_editor.cmd
```
