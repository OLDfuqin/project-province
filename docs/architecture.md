# 架构基线

## 依赖方向

```text
Godot表现层 -> GDExtension桥接层 -> C++模拟核心
                                      -> 数据注册表
```

当前地图有两条共享同一布局数据的依赖链：

```text
game/data/grid_map_layout.json
  -> GridMapLayoutLoader
  -> MapCellGenerator
  -> MapScenarioGenerator
  -> GameState / SaveGameSerializer
  -> ProvinceBridge

game/data/grid_map_layout.json
  -> province_map.gd动态生成69个可点击多边形
```

布局JSON只描述9×9尺寸、四国角落范围和2×2首都源格。随机地形、人口、基础经济、无主地区和守军由C++核心生成，Godot不重复生成玩法数据；Godot只根据相同布局构造画面几何。

模拟核心不允许引用Godot类型。桥接层只能通过稳定ID、命令DTO和只读快照交换数据。

## 可复现数值与战斗随机性

- 时间以整数月份表示。
- 金钱、人口、库存优先使用整数定点数。
- 正式战斗由进程内系统熵随机源独立抽取双方参数；测试通过 `BattleSystem` 的回调注入固定参数。
- 新游戏地图也使用进程内系统熵随机源；地图生成器接受可注入索引源，使概率边界与固定场景能够测试。
- 战斗随机种子和随机状态不由 `GameState` 持有，也不写入存档；读取同一存档后重复战斗可能得到不同结果。
- 地图随机源状态同样不写入存档；存档保存已经生成的69地区完整状态和布局ID，读档不会重新生成地图。
- 除正式战斗的随机抽取外，相同显式输入应保持可复现。

## 第一阶段接口

- `IDataRegistry`
- `IGameCommand`
- `IGameEvent`
- `IRuleModule`
- `IAIController`
- `ISaveCodec`
- `IPathCostPolicy`
- `ICombatResolver`

这些接口将在对应首个用例出现时引入，避免只有抽象、没有行为的空壳设计。
