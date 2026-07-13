#include "province/core/population_system.hpp"

#include <algorithm>
#include <limits>
#include <stdexcept>

namespace province::core {

MonthlyPopulationReport PopulationSystem::resolve_month(GameState& state) const {
    MonthlyPopulationReport report;
    report.changes.reserve(state.province_count());

    const auto scaled_floor = [](const std::int64_t value,
                                 const std::int64_t numerator) {
        return (value / rate_denominator) * numerator +
            ((value % rate_denominator) * numerator) / rate_denominator;
    };

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

        const std::int64_t previous_recruitable_population =
            province->recruitable_population;
        const std::int64_t candidate_recruitable_growth =
            scaled_floor(province->population, recruitable_growth_rate);
        const std::int64_t recruitable_cap =
            scaled_floor(province->population, recruitable_cap_rate);
        const std::int64_t available_capacity = std::max<std::int64_t>(
            0,
            recruitable_cap - province->recruitable_population
        );
        const std::int64_t recruitable_growth = std::min(
            candidate_recruitable_growth,
            available_capacity
        );
        province->recruitable_population += recruitable_growth;

        report.changes.push_back(ProvincePopulationChange{
            province_id,
            previous_population,
            province->population,
            growth,
            previous_recruitable_population,
            province->recruitable_population,
            recruitable_growth,
        });
    }
    return report;
}

} // namespace province::core
