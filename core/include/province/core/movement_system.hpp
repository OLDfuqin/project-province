#pragma once

#include "province/core/game_state.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace province::core {

struct ArmyMovementGrant final {
    ArmyId army_id;
    std::int32_t amount{};
    std::int32_t current_points{};
};

struct MonthlyMovementReport final {
    std::vector<ArmyMovementGrant> grants;
};

struct ArmyMoveResult final {
    bool accepted{};
    std::string error;
    ProvinceId origin;
    ProvinceId destination;
    std::int32_t cost{};
};

class MovementSystem final {
public:
    static constexpr std::int32_t monthly_movement_points = 2;
    static constexpr std::int32_t normal_connection_cost = 2;
    static constexpr std::int32_t paved_road_cost = 1;

    [[nodiscard]] MonthlyMovementReport grant_monthly_points(GameState& state) const;
    [[nodiscard]] ArmyMoveResult move(
        GameState& state,
        const ArmyId& army_id,
        const ProvinceId& destination
    ) const;
};

} // namespace province::core

