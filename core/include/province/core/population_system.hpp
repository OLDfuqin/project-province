#pragma once

#include "province/core/game_state.hpp"
#include "province/core/stable_id.hpp"

#include <cstdint>
#include <vector>

namespace province::core {

struct ProvincePopulationChange final {
    ProvinceId province_id;
    std::int64_t previous_population{};
    std::int64_t current_population{};
    std::int64_t growth{};
    std::int64_t previous_recruitable_population{};
    std::int64_t current_recruitable_population{};
    std::int64_t recruitable_growth{};
};

struct MonthlyPopulationReport final {
    std::vector<ProvincePopulationChange> changes;
};

class PopulationSystem final {
public:
    static constexpr std::int64_t rate_denominator = 10'000;
    static constexpr std::int64_t monthly_growth_rate = 10; // 0.1%
    static constexpr std::int64_t recruitable_growth_rate = 50; // 0.5%
    static constexpr std::int64_t recruitable_cap_rate = 1'000; // 10%

    [[nodiscard]] MonthlyPopulationReport resolve_month(GameState& state) const;
};

} // namespace province::core
