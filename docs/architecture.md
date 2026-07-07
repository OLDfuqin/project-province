# 架构基线

## 依赖方向

```text
Godot表现层 -> GDExtension桥接层 -> C++模拟核心
                                      -> 数据注册表
```

模拟核心不允许引用Godot类型。桥接层只能通过稳定ID、命令DTO和只读快照交换数据。

## 确定性

- 时间以整数月份表示。
- 金钱、人口、库存优先使用整数定点数。
- 随机数由游戏状态持有的单一受控生成器产生。
- 相同剧本、随机种子和命令序列必须得到相同结果。

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

