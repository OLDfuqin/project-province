#include "province/core/population_system.hpp"

#include <algorithm>
#include <limits>
#include <stdexcept>

namespace province::core {

void PopulationSystem::apply_population_delta(
    Province& province,
    const std::int64_t delta
) {
    if (delta == 0) return;
    if (delta == std::numeric_limits<std::int64_t>::min()) {
        throw std::overflow_error{"population delta magnitude overflow"};
    }
    const std::int64_t magnitude = delta > 0 ? delta : -delta;
    const std::int64_t percent = terrain_economy_percent(province.terrain);
    const std::int64_t economy_delta = (magnitude / 100) * percent +
        (magnitude % 100) * percent / 100;
    if (delta > 0) {
        if (magnitude > std::numeric_limits<std::int64_t>::max() - province.population ||
            economy_delta > std::numeric_limits<std::int64_t>::max() - province.base_economy) {
            throw std::overflow_error{"province population or base economy overflow"};
        }
        province.population += magnitude;
        province.base_economy += economy_delta;
        return;
    }
    if (magnitude > province.population) {
        throw std::invalid_argument{"population delta would make population negative"};
    }
    province.population -= magnitude;
    province.base_economy = std::max<std::int64_t>(
        0, province.base_economy - economy_delta
    );
}

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

        const std::int64_t previous_population = province->population;
        province->population_growth_remainder = remainder;

        const Country* owner = state.find_country(province->owner_id);
        if (owner == nullptr) {
            throw std::logic_error{"province owner disappeared during population resolution"};
        }
        if (owner->hidden) {
            Army* guard = nullptr;
            for (const auto& [army_id, army_snapshot] : state.armies()) {
                if (army_snapshot.owner_id != province->owner_id ||
                    army_snapshot.province_id != province_id) continue;
                if (guard != nullptr) {
                    throw std::logic_error{"neutral province has multiple guards"};
                }
                guard = state.find_army(army_id);
            }
            if (guard != nullptr) {
                if (growth > std::numeric_limits<std::int64_t>::max() - guard->manpower) {
                    throw std::overflow_error{"neutral guard manpower overflow"};
                }
                guard->manpower += growth;
            } else if (growth > 0) {
                [[maybe_unused]] const ArmyId recreated =
                    state.create_neutral_guard(
                        province->owner_id, province_id, growth
                    );
            }
            report.changes.push_back(ProvincePopulationChange{
                province_id,
                previous_population,
                previous_population,
                0,
                province->recruitable_population,
                province->recruitable_population,
                0,
            });
            continue;
        }

        apply_population_delta(*province, growth);

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
