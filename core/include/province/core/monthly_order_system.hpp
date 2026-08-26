#pragma once

#include "province/core/game_state.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace province::core {

struct ResolvedArmyMovement final {
    OrderId order_id;
    ArmyId army_id;
    ProvinceId origin;
    ProvinceId destination;
    std::int32_t movement_cost_half{};
    std::int32_t remaining_movement_half{};
    bool converted_from_attack{};
};

struct RefundedArmyAction final {
    OrderId order_id;
    ArmyId army_id;
    std::int32_t refunded_movement_half{};
    std::string reason;
};

struct MonthlyOrderMovementReport final {
    std::vector<ResolvedArmyMovement> movements;
    std::vector<RefundedArmyAction> refunds;
};

class MonthlyOrderSystem final {
public:
    [[nodiscard]] MonthlyOrderMovementReport resolve_movement(GameState& state) const;
};

} // namespace province::core
