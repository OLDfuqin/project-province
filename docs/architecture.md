# 架构基线

## 依赖方向

```text
Godot表现层 -> GDExtension桥接层 -> C++模拟核心
                                      -> 数据注册表
```

模拟核心不允许引用Godot类型。桥接层只能通过稳定ID、命令DTO和只读快照交换数据。

## 可复现数值与战斗随机性

- 时间以整数月份表示。
- 金钱、人口、库存优先使用整数定点数。
- 正式战斗由进程内系统熵随机源独立抽取双方参数；测试通过 `BattleSystem` 的回调注入固定参数。
- 战斗随机种子和随机状态不由 `GameState` 持有，也不写入存档；读取同一存档后重复战斗可能得到不同结果。
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
