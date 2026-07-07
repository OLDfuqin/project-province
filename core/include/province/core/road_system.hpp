#pragma once

#include "province/core/game_state.hpp"
#include "province/core/road.hpp"

#include <cstdint>
#include <string>

namespace province::core {

struct RoadBuildResult final {
    bool accepted{};
    std::string error;
    std::int64_t cost{};
};

class RoadSystem final {
public:
    static constexpr std::int64_t paved_road_cost = 500;

    [[nodiscard]] RoadBuildResult build_paved_road(
        GameState& state,
        const CountryId& country_id,
        const ProvinceId& province_a,
        const ProvinceId& province_b
    ) const;
};

} // namespace province::core

