# Task 3 报告：范围路径军队订单与月度普通移动

## 完成范围

- `MovementSystem::find_order_path` 使用带稳定 ProvinceId 次级排序的 Dijkstra，返回包含起点与终点的完整路径；中间节点只允许己方实际控制，敌方仅可作为最终节点。
- `MovementSystem::path_cost_half` 统一计算道路/目的地地形边成本；`OrderSystem` 复用该函数，攻击订单另加 4 个半点单位（2 移动点）。
- `MoveArmyCommand` 改为寻路、预留和创建 `ArmyActionOrder`，不再即时移动或调用战斗系统；同军队第二条行动订单继续由 `OrderSystem` 拒绝。
- 新增 `MonthlyOrderSystem::resolve_movement`，按稳定订单 ID 重验并先执行普通移动；攻击订单仍敌对时保留给 Task 4。
- 月结会重验军队存在/归属/起点、路径端点与连续性、中间控制权、目标控制权与敌对关系。失效订单精确退回其预留半点并删除。
- 攻击目标变为己方控制时转为普通移动，仅退回 4 半点攻击附加费；普通移动目标不再由己方控制时取消并全额退款。
- `AdvanceTurn` 在月度移动点发放后执行普通移动，再进行旧 auto-advance 与 AI 的下月规划。
- 旧 auto-advance 即时多步循环已删除；每支军队每月最多尝试创建一条相邻的下月行动订单。
- AI 仍走同一 `MoveArmyCommand` 核心入口；费用预检改为复用 `find_order_path`，因此会计入攻击附加费，且 AI 订单不会在创建当月执行。
- 迁移核心 smoke 与中立战斗 smoke：普通移动在下一月验证；攻击在 Task 3 只验证排队和未提前改变军队/领土，战斗断言留待 Task 4 恢复。

## RED 证据

1. 范围路径测试先编译失败，MSVC 报 `MovementSystem` 缺少 `find_order_path` 和 `path_cost_half`。
2. 命令排队测试先运行失败，输出 `Move command did not queue a delayed range action`，证明旧命令仍按相邻即时移动处理。
3. 月结测试先编译失败，报缺少 `province/core/monthly_order_system.hpp`。
4. `AdvanceTurn` 集成测试先运行失败，输出 `Advance turn did not resolve the queued ordinary move`。
5. AI 完整费用测试先运行失败，输出 `AI planned an attack without its movement surcharge`。

以上失败均由待实现行为缺失造成，不是夹具、拼写或 mock 错误；测试使用真实 `GameState`、`CommandProcessor`、`OrderSystem` 和月结系统，无 mock。

## GREEN 与重构

- 各轮最小实现后均运行：
  - `C:\Users\Asus\Documents\Codex\2026-07-07\w\tools\scons.cmd -Q build\bin\province_core_tests.exe`
  - `build\bin\province_core_tests.exe`
- 月结实现 GREEN 后，核心全量程序输出 `Project Province core 0.1.0-dev smoke test passed`。
- AI 费用修复 GREEN 后，同一核心全量程序再次通过。
- 重构后 `OrderSystem` 不再重复维护边成本公式，仍由同一全量程序验证通过。
- Dijkstra 测试额外覆盖：
  - 直达山地边为 8 半点、两条铺装边合计 4 半点时选择铺装路径；
  - 等成本路径即使邻接表按 `z,a` 排列，仍选择稳定 ID 较小的 `a` 路径。

## 移动点不变量审计

- 订单创建立即从军队可用点数扣除完整预留值。
- `grant_monthly_points` 继续用“上限减预留值”计算可用上限。
- 普通移动执行时不再扣点，也不退款：路径成本已经在创建订单时消费。
- 外部局势导致失效时只加回订单记录的预留值；测试覆盖“满上限下单 -> 月度发点 -> 路径失效 -> 退款”，最终恰回 12 半点，不超过上限。
- 敌转己转换只退 4 半点攻击附加费；路径预留仍视为已消费，测试最终可用点数为 4，而不是 12。

## 自审

- 权威时间顺序：常规月结与移动点发放后执行普通移动，AI 规划在其后，符合 Task 3 边界。
- 路径合法性：未知/同点/隐藏中立/非敌对外国目标返回不可达；Dijkstra 不扩展非己方中间节点。
- 确定性：优先队列键为 `(累计半点成本, ProvinceId)`，相同成本由稳定 ID 排序。
- 原子性：命令只有路径和订单校验全部通过后才预留；月结使用订单快照并按 ID 删除，不调用公开即时移动命令。
- 战斗边界：仍敌对攻击保留在队列，无共同进攻、伤亡、占领或守军移动债务实现。
- auto-advance：删除按省份数循环，同月不会即时走多步；测试覆盖连续两月“先执行旧一步，再排下一步”。
- AI：不足攻击附加费时不生成无效移动决策；足够时只创建持久订单并保持军队原地。
- `SConstruct` 已通过 `Glob("build/obj/core/*.cpp")` 自动纳入新增 `monthly_order_system.cpp`，因此无需无意义修改构建脚本；实际构建日志确认该对象被编译并链接。
- `git diff --check` 无空白错误。

## Concerns / Task 4 交接

- Task 3 有意保留仍敌对的攻击订单；Task 4 必须消费这些订单、实现分组战斗，并把中立战斗 smoke 从“未提前执行”恢复为月度战斗结果断言。
- 当前系统失效退款在事件层复用 `order_cancelled`；退款半点与原因保存在 `MonthlyOrderMovementReport`，既有 `GameEvent` 尚没有专用失效退款 payload。后续月度战报若要展示数值与原因，应扩展事件模型，而不是从取消事件猜测。
- 旧 `MovementSystem::move` 仍保留给低层相邻移动兼容测试，但 `CommandProcessor` 与月结执行均不调用它；公开游戏命令已经完全排队化。

## 提交

- 目标提交消息：`feat: resolve queued army movement each month`
- 本报告与实现、测试迁移放在同一提交中；最终提交哈希由 Git 提交输出记录并在父任务汇总中引用。
