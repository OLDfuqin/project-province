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
    static constexpr std::int32_t movement_point_scale = 2;
    static constexpr std::int32_t base_movement_cap_half = 6 * movement_point_scale;
    static constexpr std::int32_t base_monthly_movement_points_half =
        2 * movement_point_scale;
    static constexpr std::int32_t normal_connection_cost = 2;
    static constexpr std::int32_t paved_road_cost = 1;

    [[nodiscard]] static constexpr std::int32_t maximum_movement_points_half(
        std::int32_t military_level
    ) noexcept {
        return base_movement_cap_half +
            (military_level / 4) * movement_point_scale;
    }

    [[nodiscard]] static constexpr std::int32_t monthly_movement_points_half(
        std::int32_t military_level
    ) noexcept {
        return base_monthly_movement_points_half + military_level;
    }

    [[nodiscard]] MonthlyMovementReport grant_monthly_points(GameState& state) const;
    [[nodiscard]] ArmyMoveResult move(
        GameState& state,
        const ArmyId& army_id,
        const ProvinceId& destination
    ) const;
};

} // namespace province::core
