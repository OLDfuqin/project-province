#include "province/core/population_system.hpp"

#include <limits>
#include <stdexcept>

namespace province::core {

MonthlyPopulationReport PopulationSystem::resolve_month(GameState& state) const {
    MonthlyPopulationReport report;
    report.changes.reserve(state.province_count());

    for (const auto& [province_id, province_snapshot] : state.provinces()) {
        Province* province = state.find_province(province_id);
        if (province == nullptr) {
            throw std::logic_error{"province disappeared during population resolution"};
        }

        const std::int64_t whole_units = province_snapshot.population / rate_denominator;
        const std::int64_t fractional_units = province_snapshot.population % rate_denominator;
        const std::int64_t fractional_numerator =
            fractional_units * monthly_growth_rate +
            province_snapshot.population_growth_remainder;
        const std::int64_t growth =
            whole_units * monthly_growth_rate + fractional_numerator / rate_denominator;
        const std::int64_t remainder = fractional_numerator % rate_denominator;

        if (growth > std::numeric_limits<std::int64_t>::max() - province->population) {
            throw std::overflow_error{"province population overflow"};
        }

        const std::int64_t previous_population = province->population;
        province->population += growth;
        province->population_growth_remainder = remainder;
        report.changes.push_back(ProvincePopulationChange{
            province_id,
            previous_population,
            province->population,
            growth,
        });
    }
    return report;
}

} // namespace province::core

