#pragma once

#include "province/core/game_state.hpp"
#include "province/core/road.hpp"
#include "province/core/terrain.hpp"

#include <cstdint>
#include <algorithm>
#include <string>

namespace province::core {

struct RoadBuildResult final {
    bool accepted{};
    std::string error;
    std::int64_t cost{};
};

class RoadSystem final {
public:
    [[nodiscard]] static constexpr std::int32_t terrain_coefficient_t(
        TerrainType terrain
    ) noexcept {
        return terrain == TerrainType::plains ? 10 :
            terrain == TerrainType::mountains ? 8 : 9;
    }

    [[nodiscard]] static constexpr std::int64_t endpoint_base_cost(
        TerrainType terrain
    ) noexcept {
        return terrain == TerrainType::plains ? 300 :
            terrain == TerrainType::mountains ? 700 : 500;
    }

    [[nodiscard]] static constexpr std::int32_t required_roads_level(
        TerrainType first,
        TerrainType second
    ) noexcept {
        const std::int32_t minimum_t =
            std::min(terrain_coefficient_t(first), terrain_coefficient_t(second));
        return minimum_t >= 10 ? 1 : minimum_t >= 9 ? 2 : 3;
    }

    [[nodiscard]] static constexpr std::int64_t discount_percent(
        std::int32_t roads_level
    ) noexcept {
        switch (roads_level) {
        case 1: return 10;
        case 2: return 20;
        case 3: return 30;
        case 4: return 50;
        default: return 0;
        }
    }

    [[nodiscard]] RoadBuildResult build_paved_road(
        GameState& state,
        const CountryId& country_id,
        const ProvinceId& province_a,
        const ProvinceId& province_b
    ) const;
};

} // namespace province::core
